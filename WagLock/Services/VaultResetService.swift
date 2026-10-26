import Darwin
import Foundation
import Security

@MainActor
protocol VaultResetKeychain {
    func services() throws -> [String]
    func remove(service: String) throws
}

@MainActor
struct SystemVaultResetKeychain: VaultResetKeychain {
    func services() throws -> [String] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else {
            throw KeychainError.unexpectedStatus(status)
        }
        return try rows.map {
            guard let service = $0[kSecAttrService as String] as? String else { throw KeychainError.invalidData }
            return service
        }
    }
    func remove(service: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// Only a checked, durable explicit erase request authorizes deletion. Preferences never do.
@MainActor
final class VaultResetService {
    nonisolated deinit {}
    enum Failure: Error { case unavailable, invalidIntent, incomplete }
    private struct Intent: Codable { let version: Int; let id: UUID; let services: [String] }
    private let namespace: String
    private let intentStore: any KeychainStorage
    private let keychain: any VaultResetKeychain
    private let roots: [URL]
    private let extraRoots: () throws -> [URL]
    private let clearPreferences: () throws -> Void
    private let checkpoint: (Int) throws -> Void
    private let account = "explicit-erase-request"

    init(namespace: String, intentStore: any KeychainStorage, keychain: any VaultResetKeychain,
         roots: [URL], extraRoots: @escaping () throws -> [URL] = { [] },
         clearPreferences: @escaping () throws -> Void,
         checkpoint: @escaping (Int) throws -> Void = { _ in }) {
        self.namespace = namespace; self.intentStore = intentStore; self.keychain = keychain
        self.roots = roots; self.extraRoots = extraRoots; self.clearPreferences = clearPreferences; self.checkpoint = checkpoint
    }

    static func live() -> VaultResetService? {
        let namespace = AppConstants.bundleIdentifier
        guard LibraryStoragePolicy.encryptedMetadata, namespace == "com.d2sci.waglock" else { return nil }
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
        let temporary = fm.temporaryDirectory.resolvingSymlinksInPath()
        let roots = [documents.appendingPathComponent("EncryptedMedia"),
            documents.appendingPathComponent("WagLockSecondaryMedia"),
            support.appendingPathComponent("WagLockVault"), support.appendingPathComponent("WagLockVault.creating"),
            support.appendingPathComponent("WagLockSecondaryLibraries")]
            + ["WagLockSessions", "WagLockPlaintextJobs", "WagLockExport", "ZeroNetExport", "AudioMemos", "WagLockBackupJobs"]
                .map { temporary.appendingPathComponent($0) }
        return VaultResetService(namespace: namespace,
            intentStore: SystemKeychainStorage(service: namespace + ".erase-intent.v1"),
            keychain: SystemVaultResetKeychain(), roots: roots, extraRoots: {
                let prefixes = ["WagLockAlbumImport-", "WagLockAlbumPreview-", "waglock-media-import-"]
                return try fm.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil).filter { url in
                    prefixes.contains { url.lastPathComponent.hasPrefix($0)
                        && UUID(uuidString: String(url.lastPathComponent.dropFirst($0.count))) != nil }
                }
            }, clearPreferences: {
                UserDefaults.standard.removePersistentDomain(forName: namespace)
                guard UserDefaults.standard.synchronize() else { throw Failure.incomplete }
                // The existing shared storage instance needs its empty directory for new enrollment.
                try fm.createDirectory(at: documents.appendingPathComponent("EncryptedMedia"),
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
            })
    }

    static func owns(service: String, namespace: String) -> Bool {
        if [namespace, namespace + ".biometrics", namespace + ".album-attempts"].contains(service) { return true }
        let prefix = namespace + ".vault."
        guard service.hasPrefix(prefix) else { return false }
        let suffix = String(service.dropFirst(prefix.count))
        let id = String(suffix.prefix(36))
        guard UUID(uuidString: id) != nil else { return false }
        return ["", ".album-biometrics", ".album-attempts"].contains(String(suffix.dropFirst(36)))
    }
    private func encode(_ intent: Intent) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(intent)
    }
    private func intent() throws -> Intent? {
        let data: Data
        do { data = try intentStore.read(account: account) }
        catch KeychainError.itemNotFound { return nil }
        guard data.count <= 65536 else { throw Failure.invalidIntent }
        let value = try JSONDecoder().decode(Intent.self, from: data)
        guard value.version == 1, value.services.count <= 1024,
              value.services == Array(Set(value.services)).sorted(),
              value.services.allSatisfy({ Self.owns(service: $0, namespace: namespace) }),
              try encode(value) == data else { throw Failure.invalidIntent }
        return value
    }
    func hasPendingErase() throws -> Bool { try intent() != nil }

    func begin() throws {
        guard try intent() == nil else { throw Failure.incomplete }
        let services = Array(Set(try keychain.services().filter { Self.owns(service: $0, namespace: namespace) })).sorted()
        let value = Intent(version: 1, id: UUID(), services: services)
        let data = try encode(value)
        guard data.count <= 65536, services.count <= 1024 else { throw Failure.invalidIntent }
        try intentStore.write(account: account, data: data, createOnly: true)
        guard try intentStore.read(account: account) == data else { throw Failure.unavailable }
        try checkpoint(0)
    }

    /// Returns false on checked absence; retrying a failed state check never implies consent.
    @discardableResult
    func resume() async throws -> Bool {
        guard let value = try intent() else { return false }
        let roots = try roots + extraRoots()
        try await Task.detached(priority: .userInitiated) { try Self.removeOwnedRoots(roots) }.value
        try checkpoint(1)
        for service in value.services { try keychain.remove(service: service) }
        guard try keychain.services().allSatisfy({ !Self.owns(service: $0, namespace: namespace) }) else {
            throw Failure.incomplete
        }
        try checkpoint(2)
        try clearPreferences()
        try checkpoint(3)
        // Recheck the same explicit request before final publication of an empty installation.
        guard try intent()?.id == value.id else { throw Failure.invalidIntent }
        try intentStore.delete(account: account)
        guard try intent() == nil else { throw Failure.incomplete }
        return true
    }

    private nonisolated static func removeOwnedRoots(_ roots: [URL]) throws {
        for root in roots {
            var attributes = stat()
            if lstat(root.path, &attributes) != 0 {
                guard errno == ENOENT else { throw Failure.unavailable }; continue
            }
            try FreshEncryptedLibrary.safe(root)
            // Foundation removes descendant links themselves, not their external targets.
            try FileManager.default.removeItem(at: root)
        }
    }
}
