import Foundation
import Security

@testable import WagLock

// Test-bundle-only experiment. No app session/storage singletons, Keychain or legacy stores.
@MainActor
final class VaultIsolationPrototype {
    enum Failure: Error, Equatable { case authentication, locked, wrongDomain, corrupt, unsafePath, duplicatePassword, tooLarge }

    struct Reference: Equatable {
        let vaultID: UUID
        let assetID: UUID
    }

    struct Entry: Codable, Equatable {
        let id: UUID
        let name: String
        let albumPath: [String]
        let thumbnail: Data
        let note: String
    }

    private struct Catalog: Codable {
        var entries: [Entry] = []
        var settings: [String: String] = [:]
    }

    private struct Envelope: Codable {
        let version: Int
        let storeID: UUID
        let vaultID: UUID
        let purpose: String
        let assetID: UUID?
        let payload: Data
    }

    @MainActor
    final class Context {
        let vaultID: UUID
        let generation = UUID()
        fileprivate let owner: UUID
        fileprivate var secret: SecureBytes?
        fileprivate var cachedEntries: [Entry]?

        fileprivate init(vaultID: UUID, owner: UUID, secret: String) {
            self.vaultID = vaultID
            self.owner = owner
            self.secret = SecureBytes(secret)
        }

        var cachedEntriesForTesting: [Entry]? { cachedEntries }

        fileprivate func revoke() {
            secret?.wipe()
            secret = nil
            cachedEntries = nil
        }
    }

    typealias Writer = (Data, URL) throws -> Void
    static let maxBufferSize = 1_048_576
    private let root: URL
    private let storeID: UUID
    private let instanceID = UUID()
    private let write: Writer
    private var active: Context?
    private let crypto = EncryptionService.shared
    private let manager = FileManager.default

    // Caller supplies a disposable root; this helper is compiled only into tests.
    init(root: URL, writer: @escaping Writer = { data, url in
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }) throws {
        self.root = root.standardizedFileURL
        self.write = writer
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard root.standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else {
            throw Failure.unsafePath
        }
        let marker = root.appendingPathComponent("store.json")
        if FileManager.default.fileExists(atPath: marker.path) {
            guard marker == marker.resolvingSymlinksInPath() else { throw Failure.unsafePath }
            storeID = try JSONDecoder().decode(UUID.self, from: Self.readFile(marker))
        } else {
            guard try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty else {
                throw Failure.corrupt
            }
            storeID = UUID()
            try writer(JSONEncoder().encode(storeID), marker)
        }
    }

    func provision(password: String) throws -> UUID {
        guard password.count >= 6 else { throw Failure.authentication }
        // Evaluate every committed slot, without exposing an owner/secondary role.
        if try matchingKeys(password: password).isEmpty == false { throw Failure.duplicatePassword }
        let id = UUID()
        let staging = try checked(root.appendingPathComponent("pending-" + UUID().uuidString))
        let destination = try vaultDirectory(id)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        defer { try? manager.removeItem(at: staging) }
        let secret = try Self.randomSecret()
        let key = try seal(Data(secret.utf8), vaultID: id, purpose: "key", assetID: nil, password: password)
        let catalog = try seal(JSONEncoder().encode(Catalog()), vaultID: id, purpose: "catalog",
                               assetID: nil, password: secret)
        try write(key, staging.appendingPathComponent("key.enc"))
        try write(catalog, staging.appendingPathComponent("index.enc"))
        // A directory rename publishes credentials and initial catalog together.
        try manager.moveItem(at: staging, to: destination)
        return id
    }

    func unlock(password: String) throws -> Context {
        lock()
        let matches: [(UUID, String)]
        do { matches = try matchingKeys(password: password) }
        catch { throw Failure.authentication }
        guard matches.count == 1, let (id, key) = matches.first else { throw Failure.authentication }
        let context = Context(vaultID: id, owner: instanceID, secret: key)
        // Authenticate the index before making the context usable.
        do { _ = try readCatalog(context, secret: key) }
        catch { context.revoke(); throw Failure.authentication }
        active = context
        return context
    }

    func lock() {
        active?.revoke()
        active = nil
    }

    func entries(in context: Context) throws -> [Entry] {
        let key = try require(context)
        if let cached = context.cachedEntries { return cached }
        let entries = try readCatalog(context, secret: key).entries
        context.cachedEntries = entries
        return entries
    }

    func settings(in context: Context) throws -> [String: String] {
        try readCatalog(context, secret: require(context)).settings
    }

    func setSetting(_ value: String, for name: String, in context: Context) throws {
        let key = try require(context)
        var catalog = try readCatalog(context, secret: key)
        catalog.settings[name] = value
        try saveCatalog(catalog, context: context, secret: key)
    }

    func importAsset(name: String, albumPath: [String], thumbnail: Data, note: String,
                     in context: Context, source: () async throws -> Data) async throws -> Reference {
        _ = try require(context)
        let data = try await source()
        try Task.checkCancellation()
        let key = try require(context) // reject late work after lock, switch or same-vault relogin
        guard data.count <= Self.maxBufferSize, thumbnail.count <= Self.maxBufferSize else { throw Failure.tooLarge }
        var catalog = try readCatalog(context, secret: key)
        let id = UUID()
        let file = try assetURL(id, vaultID: context.vaultID)
        let encrypted = try seal(data, vaultID: context.vaultID, purpose: "asset", assetID: id, password: key)
        catalog.entries.append(Entry(id: id, name: name, albumPath: albumPath, thumbnail: thumbnail, note: note))
        do {
            try write(encrypted, file)
            try saveCatalog(catalog, context: context, secret: key)
        } catch {
            // A writer may throw after committing. Preserve data when commit outcome is uncertain.
            let committed = try? readCatalog(context, secret: key).entries.contains { $0.id == id }
            if committed == false { try? manager.removeItem(at: file) }
            context.cachedEntries = nil
            throw error
        }
        return Reference(vaultID: context.vaultID, assetID: id)
    }

    func exportAsset(_ reference: Reference, in context: Context) throws -> Data {
        let key = try require(context)
        guard reference.vaultID == context.vaultID else { throw Failure.wrongDomain }
        let catalog = try readCatalog(context, secret: key)
        guard catalog.entries.contains(where: { $0.id == reference.assetID }) else { throw Failure.wrongDomain }
        return try open(Self.readFile(assetURL(reference.assetID, vaultID: context.vaultID)),
                        vaultID: context.vaultID, purpose: "asset", assetID: reference.assetID, password: key)
    }

    func deleteAsset(_ reference: Reference, in context: Context) throws {
        let key = try require(context)
        guard reference.vaultID == context.vaultID else { throw Failure.wrongDomain }
        var catalog = try readCatalog(context, secret: key)
        guard catalog.entries.contains(where: { $0.id == reference.assetID }) else { throw Failure.wrongDomain }
        let file = try assetURL(reference.assetID, vaultID: context.vaultID)
        catalog.entries.removeAll { $0.id == reference.assetID }
        try saveCatalog(catalog, context: context, secret: key)
        // Failure here leaves only an orphaned encrypted asset, never a cross-vault delete.
        try manager.removeItem(at: file)
    }

    private func require(_ context: Context) throws -> String {
        guard context.owner == instanceID else { throw Failure.wrongDomain }
        guard active === context, let secret = context.secret?.string else { throw Failure.locked }
        return secret
    }

    private func readCatalog(_ context: Context, secret: String) throws -> Catalog {
        let file = try checked(vaultDirectory(context.vaultID).appendingPathComponent("index.enc"))
        let bytes = try open(Self.readFile(file), vaultID: context.vaultID, purpose: "catalog",
                             assetID: nil, password: secret)
        return try JSONDecoder().decode(Catalog.self, from: bytes)
    }

    private func saveCatalog(_ catalog: Catalog, context: Context, secret: String) throws {
        let data = try seal(JSONEncoder().encode(catalog), vaultID: context.vaultID,
                            purpose: "catalog", assetID: nil, password: secret)
        defer { context.cachedEntries = nil }
        try write(data, checked(vaultDirectory(context.vaultID).appendingPathComponent("index.enc")))
    }

    private func matchingKeys(password: String) throws -> [(UUID, String)] {
        let children = try manager.contentsOfDirectory(at: checked(root), includingPropertiesForKeys: nil)
        var matches: [(UUID, String)] = []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let id = UUID(uuidString: child.lastPathComponent) else { continue }
            let file = try checked(vaultDirectory(id).appendingPathComponent("key.enc"))
            let encrypted = try Self.readFile(file)
            // Every valid directory gets a credential attempt; no early return on success.
            if let bytes = try? open(encrypted, vaultID: id, purpose: "key", assetID: nil, password: password),
               let key = String(data: bytes, encoding: .utf8), Data(base64Encoded: key)?.count == 32 {
                matches.append((id, key))
            }
        }
        return matches
    }

    private func seal(_ payload: Data, vaultID: UUID, purpose: String, assetID: UUID?, password: String) throws -> Data {
        let envelope = Envelope(version: 1, storeID: storeID, vaultID: vaultID,
                                purpose: purpose, assetID: assetID, payload: payload)
        let encoded = try JSONEncoder().encode(envelope)
        guard encoded.count <= 4 * Self.maxBufferSize else { throw Failure.tooLarge }
        return try crypto.encrypt(data: encoded, password: password)
    }

    private func open(_ data: Data, vaultID: UUID, purpose: String, assetID: UUID?, password: String) throws -> Data {
        let envelope = try JSONDecoder().decode(Envelope.self, from: crypto.decrypt(encryptedData: data, password: password))
        guard envelope.version == 1, envelope.storeID == storeID, envelope.vaultID == vaultID,
              envelope.purpose == purpose, envelope.assetID == assetID else { throw Failure.corrupt }
        return envelope.payload
    }

    private func vaultDirectory(_ id: UUID) throws -> URL { try checked(root.appendingPathComponent(id.uuidString)) }
    private func assetURL(_ id: UUID, vaultID: UUID) throws -> URL {
        try checked(vaultDirectory(vaultID).appendingPathComponent(id.uuidString + ".enc"))
    }

    private func checked(_ url: URL) throws -> URL {
        let value = url.standardizedFileURL
        guard value.path == root.path || value.path.hasPrefix(root.path + "/"),
              value == value.resolvingSymlinksInPath().standardizedFileURL else { throw Failure.unsafePath }
        return value
    }

    private static func readFile(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let limit = 5 * maxBufferSize
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw Failure.tooLarge }
        return data
    }

    private static func randomSecret() throws -> String {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else { throw EncryptionError.randomGenerationFailed }
        return bytes.base64EncodedString()
    }
}
