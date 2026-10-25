import CryptoKit
import Darwin
import Foundation
import Security
import SwiftData

@MainActor
protocol LibraryIdentityAnchor: AnyObject {
    func loadLibraryIdentity() throws -> Data?
    func establishLibraryIdentity(_ identity: Data) throws
}

/// Selected only by the isolated first-release configuration, never by the legacy phone build.
enum LibraryStoragePolicy {
    nonisolated static var encryptedMetadata: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "WagLockEncryptedLibrary")
        return (value as? Bool) == true || (value as? String)?.uppercased() == "YES"
    }
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .resolvingSymlinksInPath().appendingPathComponent("WagLockVault", isDirectory: true)
    }
}

/// Fresh libraries only. Publication is an atomic sibling-directory rename.
/// A legacy database is a hard error, never permission to create an empty replacement.
@MainActor
enum FreshEncryptedLibrary {
    enum Failure: Error { case legacySource, invalidDescriptor, unsafePath, storage, conflictingRoots, missingLibrary, foreignLibrary }
    enum Checkpoint { case keyFileWritten, descriptorSaved, indexCreated, beforePublication, afterPublication }
    private struct Descriptor: Codable { let version: Int; let domain: EncryptedMetadataStore.Domain; let wrappedKey: Data }
    private struct KeyMaterial: Codable { let version: Int; let domain: EncryptedMetadataStore.Domain; let key: Data }

    static func randomSecret() throws -> String { try randomKey().base64EncodedString() }
    private static func randomKey() throws -> Data {
        var bytes = Data(count: 32)
        guard bytes.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess else {
            throw EncryptionError.randomGenerationFailed
        }
        return bytes
    }
    static func open(at root: URL, dataPassword: String, anchor: any LibraryIdentityAnchor, legacySources: [URL] = [],
                     authorized: @escaping () -> Bool,
                     checkpoint: (Checkpoint) throws -> Void = { _ in }) throws -> EncryptedLibraryRepository {
        try check(authorized)
        guard !dataPassword.isEmpty else { throw Failure.invalidDescriptor }
        for source in legacySources where exists(source) { throw Failure.legacySource }
        let expectedIdentity = try anchor.loadLibraryIdentity()
        guard expectedIdentity == nil || expectedIdentity?.count == 32 else { throw Failure.invalidDescriptor }
        if expectedIdentity != nil, !exists(root) { throw Failure.missingLibrary }
        let parent = root.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try safe(parent)
        let pending = parent.appendingPathComponent(root.lastPathComponent + ".creating", isDirectory: true)
        if exists(root) {
            guard !exists(pending) else { throw Failure.conflictingRoots }
            let material = try read(root, password: dataPassword)
            try bindIdentity(root, material: material, anchor: anchor, expected: expectedIdentity, authorized: authorized)
            try check(authorized)
            return try EncryptedLibraryRepository.open(at: root.appendingPathComponent("index"), domain: material.domain,
                                                       key: material.key, authorized: authorized, commitAnchor: anchor as? any LibraryCommitAnchor)
        }
        if !exists(pending) {
            guard mkdir(pending.path, S_IRWXU) == 0 else { throw Failure.storage }
            try protect(pending)
        }
        try safe(pending)
        let descriptor = pending.appendingPathComponent("library.json")
        if !exists(descriptor) {
            // A crash between mkdir and descriptor creation can only leave an empty root.
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: pending.path)
            for name in leftovers {
                guard name.hasPrefix("key-"), name.hasSuffix(".partial"),
                      UUID(uuidString: String(name.dropFirst(4).dropLast(8))) != nil else { throw Failure.invalidDescriptor }
                let file = pending.appendingPathComponent(name); try safe(file)
                guard try FileManager.default.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType == .typeRegular else { throw Failure.unsafePath }
            }
            let domain = EncryptedMetadataStore.Domain(libraryID: UUID(), vaultID: UUID())
            let key = try randomKey()
            let payload = try encode(KeyMaterial(version: 1, domain: domain, key: key))
            let wrapped = try EncryptionService.shared.encrypt(data: payload, password: dataPassword)
            let temporary = pending.appendingPathComponent("key-" + UUID().uuidString + ".partial")
            try writeExclusive(try encode(Descriptor(version: 1, domain: domain, wrappedKey: wrapped)), to: temporary)
            try checkpoint(.keyFileWritten); try check(authorized)
            guard renamex_np(temporary.path, descriptor.path, UInt32(RENAME_EXCL)) == 0 else { throw Failure.storage }
            try sync(pending)
        }
        try checkpoint(.descriptorSaved); try check(authorized)
        let material = try read(pending, password: dataPassword)
        let index = pending.appendingPathComponent("index", isDirectory: true)
        let store: EncryptedMetadataStore
        if exists(index) {
            do { store = try EncryptedMetadataStore.open(at: index, domain: material.domain, key: material.key) }
            catch {
                // Only an unpublished, empty SQLite schema can be completed in place.
                store = try EncryptedMetadataStore.resumeUnpublishedEmpty(at: index, domain: material.domain, key: material.key)
            }
        } else { store = try EncryptedMetadataStore.create(at: index, domain: material.domain, key: material.key) }
        do {
            try store.verifyAll(store.access())
            guard try store.state(store.access()).count == 0 else { throw Failure.invalidDescriptor }
            store.revoke()
        } catch { store.revoke(); throw error }
        try checkpoint(.indexCreated); try check(authorized)
        try sync(index); try sync(pending)
        try checkpoint(.beforePublication); try check(authorized)
        guard !exists(root) else { throw Failure.conflictingRoots }
        // Same parent/volume; exclusive rename refuses a competing destination.
        guard renamex_np(pending.path, root.path, UInt32(RENAME_EXCL)) == 0 else { throw Failure.storage }
        try sync(parent)
        try checkpoint(.afterPublication); try check(authorized)
        try bindIdentity(root, material: material, anchor: anchor, expected: expectedIdentity, authorized: authorized)
        return try EncryptedLibraryRepository.open(at: root.appendingPathComponent("index"), domain: material.domain,
                                                   key: material.key, authorized: authorized, commitAnchor: anchor as? any LibraryCommitAnchor)
    }
    private static func bindIdentity(_ root: URL, material: KeyMaterial, anchor: any LibraryIdentityAnchor,
                                     expected: Data?, authorized: () -> Bool) throws {
        let bytes = try Data(contentsOf: root.appendingPathComponent("library.json"))
        let identity = Data(HMAC<SHA256>.authenticationCode(for: bytes, using: SymmetricKey(data: material.key)))
        try check(authorized)
        if let expected { guard expected == identity else { throw Failure.foreignLibrary } }
        else { try anchor.establishLibraryIdentity(identity) }
        try check(authorized)
        guard try anchor.loadLibraryIdentity() == identity else { throw Failure.foreignLibrary }
    }
    private static func read(_ root: URL, password: String) throws -> KeyMaterial {
        try safe(root)
        let file = root.appendingPathComponent("library.json")
        try safe(file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= 16_384 else { throw Failure.invalidDescriptor }
        let bytes = try Data(contentsOf: file)
        let descriptor = try JSONDecoder().decode(Descriptor.self, from: bytes)
        guard descriptor.version == 1, try encode(descriptor) == bytes else { throw Failure.invalidDescriptor }
        let opened = try EncryptionService.shared.decrypt(encryptedData: descriptor.wrappedKey, password: password)
        let material = try JSONDecoder().decode(KeyMaterial.self, from: opened)
        guard material.version == 1, material.domain == descriptor.domain, material.key.count == 32,
              try encode(material) == opened else { throw Failure.invalidDescriptor }
        return material
    }
    private static func check(_ authorized: () -> Bool) throws {
        guard authorized() else { throw LibraryWriteCoordinator.Failure.revoked }; try Task.checkCancellation()
    }
    private static func exists(_ url: URL) -> Bool {
        var value = stat(); return lstat(url.path, &value) == 0
    }
    static func safe(_ url: URL) throws {
        guard url.isFileURL else { throw Failure.unsafePath }
        // Foundation can abbreviate an already-resolved /private/var URL back to
        // /var. Expand only verified OS aliases, as the ciphertext index does;
        // every other symlink component remains forbidden.
        var canonicalPath = url.standardizedFileURL.path
        for alias in ["/var", "/tmp"] where canonicalPath == alias || canonicalPath.hasPrefix(alias + "/") {
            if let pointer = realpath(alias, nil) {
                let target = String(cString: pointer); free(pointer)
                if target == "/private" + alias { canonicalPath = target + canonicalPath.dropFirst(alias.count) }
            }
        }
        let components = (canonicalPath as NSString).pathComponents
        for count in 1...components.count {
            let path = NSString.path(withComponents: Array(components.prefix(count)))
            var value = stat()
            guard lstat(path, &value) == 0, value.st_mode & S_IFMT != S_IFLNK else { throw Failure.unsafePath }
        }
    }
    private static func writeExclusive(_ data: Data, to file: URL) throws {
        let fd = Darwin.open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure.storage }; defer { Darwin.close(fd) }
        try protect(file)
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard written > 0 else { throw Failure.storage }; offset += written
            }
        }
        guard fsync(fd) == 0 else { throw Failure.storage }
    }
    private static func protect(_ url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
    }
    private static func sync(_ root: URL) throws {
        let fd = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.storage }; defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw Failure.storage }
    }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
}
