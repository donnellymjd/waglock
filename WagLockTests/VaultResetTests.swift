import Foundation
import XCTest
@testable import WagLock

@MainActor
final class VaultResetTests: XCTestCase {
    private final class Store: KeychainStorage {
        nonisolated deinit {}
        var items: [String: Data] = [:]
        var failRead = false, failWrite = false, failDelete = false, failAfterWrite = false, corruptWrite = false
        func read(account: String) throws -> Data {
            if failRead { throw KeychainError.unexpectedStatus(-1) }
            guard let value = items[account] else { throw KeychainError.itemNotFound }; return value
        }
        func write(account: String, data: Data, createOnly: Bool) throws {
            if failWrite { throw KeychainError.unexpectedStatus(-1) }
            if createOnly && items[account] != nil { throw KeychainError.duplicateItem }
            items[account] = corruptWrite ? Data("corrupt".utf8) : data
            if failAfterWrite { throw KeychainError.unexpectedStatus(-1) }
        }
        func delete(account: String) throws {
            if failDelete { throw KeychainError.unexpectedStatus(-1) }; items.removeValue(forKey: account)
        }
    }
    private final class Keys: VaultResetKeychain {
        nonisolated deinit {}
        var values = Set<String>()
        var failing: String?
        var removed: [String] = []
        var onRemove: (String) -> Void = { _ in }
        func services() throws -> [String] { Array(values) }
        func remove(service: String) throws {
            if service == failing { throw KeychainError.unexpectedStatus(-1) }
            values.remove(service); removed.append(service); onRemove(service)
        }
    }
    private var directories: [URL] = []
    override func tearDown() { for url in directories { try? FileManager.default.removeItem(at: url) } }
    private func fixture() throws -> (URL, URL, Store, Keys, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PUBLIC-reset-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        directories.append(root)
        let vault = root.appendingPathComponent("owned-vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: false)
        try Data("PUBLIC disposable ciphertext".utf8).write(to: vault.appendingPathComponent("item"))
        let namespace = "PUBLIC-reset-" + UUID().uuidString
        let keys = Keys(); keys.values = [namespace, namespace + ".biometrics", namespace + ".album-attempts",
            namespace + ".vault." + UUID().uuidString,
            namespace + ".vault." + UUID().uuidString + ".album-biometrics",
            namespace + ".vault." + UUID().uuidString + ".album-attempts",
            "com.d2sci.vaultito.dev", namespace + ".vault.not-a-uuid", namespace + ".erase-intent.v1"]
        return (root, vault, Store(), keys, namespace)
    }
    func testCheckedAbsenceNeverAuthorizesDeletionAndCompleteErasePreservesOutsideData() async throws {
        let (root, vault, store, keys, namespace) = try fixture()
        let backup = root.appendingPathComponent("Backup.tar.age")
        try Data("PUBLIC keep backup".utf8).write(to: backup)
        var preferencesCleared = false
        let service = VaultResetService(namespace: namespace, intentStore: store, keychain: keys,
            roots: [vault], clearPreferences: { preferencesCleared = true })
        let absent = try await service.resume()
        XCTAssertFalse(absent); XCTAssertTrue(FileManager.default.fileExists(atPath: vault.path))
        XCTAssertTrue(keys.removed.isEmpty)
        try service.begin(); XCTAssertTrue(try service.hasPendingErase())
        let completed = try await service.resume(); XCTAssertTrue(completed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.path))
        XCTAssertTrue(preferencesCleared); XCTAssertFalse(try service.hasPendingErase())
        XCTAssertEqual(try Data(contentsOf: backup), Data("PUBLIC keep backup".utf8))
        XCTAssertEqual(keys.values, ["com.d2sci.vaultito.dev", namespace + ".vault.not-a-uuid", namespace + ".erase-intent.v1"])
    }
    func testEveryInterruptedPhaseResumesFromTheDurableExplicitRequest() async throws {
        for stage in 0...3 {
            let (_, vault, store, keys, namespace) = try fixture()
            var cleared = 0
            let interrupted = VaultResetService(namespace: namespace, intentStore: store, keychain: keys,
                roots: [vault], clearPreferences: { cleared += 1 }, checkpoint: { point in
                    if point == stage { throw VaultResetService.Failure.incomplete }
                })
            do { try interrupted.begin(); _ = try await interrupted.resume(); XCTFail("Missing injected interruption") }
            catch {}
            XCTAssertTrue(try interrupted.hasPendingErase())
            let reopened = VaultResetService(namespace: namespace, intentStore: store, keychain: keys,
                roots: [vault], clearPreferences: { cleared += 1 })
            let resumed = try await reopened.resume(); XCTAssertTrue(resumed)
            XCTAssertFalse(try reopened.hasPendingErase()); XCTAssertGreaterThan(cleared, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: vault.path))
            XCTAssertFalse(keys.values.contains(namespace))
        }
    }
    func testUnavailableUnwrittenCorruptOrForeignIntentPreservesData() async throws {
        let (_, vault, store, keys, namespace) = try fixture()
        let service = VaultResetService(namespace: namespace, intentStore: store, keychain: keys, roots: [vault], clearPreferences: {})
        store.failRead = true
        XCTAssertThrowsError(try service.begin()); XCTAssertThrowsError(try service.hasPendingErase())
        store.failRead = false; store.failWrite = true
        XCTAssertThrowsError(try service.begin()); XCTAssertTrue(store.items.isEmpty)
        store.failWrite = false
        for bytes in [Data("bad".utf8), try JSONSerialization.data(withJSONObject: ["version": 1, "id": UUID().uuidString, "services": ["com.d2sci.vaultito.dev"]], options: [.sortedKeys])] {
            store.items["explicit-erase-request"] = bytes
            do { _ = try await service.resume(); XCTFail("Invalid intent accepted") } catch {}
            XCTAssertEqual(store.items["explicit-erase-request"], bytes)
        }
        XCTAssertTrue(keys.removed.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: vault.path))
    }
    func testKeychainAndFinalMarkerFailuresRemainPendingAndRetryable() async throws {
        for finalMarker in [false, true] {
            let (_, vault, store, keys, namespace) = try fixture()
            let service = VaultResetService(namespace: namespace, intentStore: store, keychain: keys, roots: [vault], clearPreferences: {})
            try service.begin()
            if finalMarker { store.failDelete = true } else { keys.failing = namespace }
            do { _ = try await service.resume(); XCTFail("Failure ignored") } catch {}
            XCTAssertTrue(try service.hasPendingErase())
            store.failDelete = false; keys.failing = nil
            _ = try await service.resume(); XCTAssertFalse(try service.hasPendingErase())
        }
    }
    func testSymlinkRootFailsClosedAndNestedLinkNeverDeletesExternalTarget() async throws {
        let (root, vault, store, keys, namespace) = try fixture()
        let outside = root.appendingPathComponent("preserve")
        try Data("PUBLIC keep".utf8).write(to: outside)
        let link = root.appendingPathComponent("root-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: vault)
        let refused = VaultResetService(namespace: namespace, intentStore: store, keychain: keys, roots: [link], clearPreferences: {})
        try refused.begin()
        do { _ = try await refused.resume(); XCTFail("Root link followed") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.path)); XCTAssertTrue(keys.removed.isEmpty)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("external"), withDestinationURL: outside)
        let resumed = VaultResetService(namespace: namespace, intentStore: store, keychain: keys, roots: [vault], clearPreferences: {})
        _ = try await resumed.resume()
        XCTAssertEqual(try Data(contentsOf: outside), Data("PUBLIC keep".utf8))
    }
    func testSystemKeychainDeletionIsScopedAndLeavesNoVaultOrIntentRecords() async throws {
        let (_, vault, _, _, _) = try fixture()
        let namespace = "PUBLIC-system-reset-" + UUID().uuidString
        let unrelated = namespace + "-dev"
        let intentStore = SystemKeychainStorage(service: namespace + ".erase-intent.v1")
        let system = SystemVaultResetKeychain()
        let names = [namespace, namespace + ".biometrics", namespace + ".vault." + UUID().uuidString, unrelated]
        defer { for service in names + [namespace + ".erase-intent.v1"] { try? system.remove(service: service) } }
        for service in names { try SystemKeychainStorage(service: service).write(account: "PUBLIC", data: Data([1]), createOnly: true) }
        let reset = VaultResetService(namespace: namespace, intentStore: intentStore, keychain: system, roots: [vault], clearPreferences: {})
        try reset.begin(); _ = try await reset.resume()
        XCTAssertFalse(try system.services().contains(namespace))
        XCTAssertFalse(try reset.hasPendingErase())
        XCTAssertEqual(try SystemKeychainStorage(service: unrelated).read(account: "PUBLIC"), Data([1]))
    }
    func testUncertainIntentReadbackAndPreferenceFailuresNeverPublishFreshSetup() async throws {
        let (_, vault, store, keys, namespace) = try fixture()
        var failPreferences = true
        let service = VaultResetService(namespace: namespace, intentStore: store, keychain: keys,
            roots: [vault], clearPreferences: { if failPreferences { throw VaultResetService.Failure.incomplete } })
        store.corruptWrite = true
        XCTAssertThrowsError(try service.begin())
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.path)); XCTAssertTrue(keys.removed.isEmpty)
        XCTAssertThrowsError(try service.hasPendingErase())
        store.items.removeAll(); store.corruptWrite = false; store.failAfterWrite = true
        XCTAssertThrowsError(try service.begin())
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.path)); XCTAssertTrue(keys.removed.isEmpty)
        store.failAfterWrite = false
        XCTAssertTrue(try service.hasPendingErase())
        do { _ = try await service.resume(); XCTFail("Preference failure ignored") } catch {}
        XCTAssertTrue(try service.hasPendingErase())
        failPreferences = false
        let resumed = try await service.resume(); XCTAssertTrue(resumed)
        XCTAssertFalse(try service.hasPendingErase())
    }

    func testPendingIntentBlocksAllAuthenticationAndNewSetupUntilCleanupCompletes() async throws {
        let (_, vault, store, keys, namespace) = try fixture()
        let credentials = Store()
        let keychain = KeychainService(service: namespace, storage: credentials)
        try keychain.savePassword("PUBLIC-old-password")
        keys.onRemove = { if $0 == namespace { credentials.items.removeAll() } }
        let reset = VaultResetService(namespace: namespace, intentStore: store, keychain: keys, roots: [vault], clearPreferences: {})
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false, independentVaultsEnabled: true, resetService: reset)
        await auth.eraseLocalData(confirmation: "erase")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.path)); XCTAssertTrue(store.items.isEmpty)
        try reset.begin()
        auth.checkPasswordStatus()
        XCTAssertTrue(auth.requiresEraseCompletion)
        auth.password = "PUBLIC-old-password"; auth.confirmPassword = auth.password
        XCTAssertNil(auth.login()); XCTAssertFalse(auth.isSetupButtonEnabled)
        auth.setupPassword(); await auth.loginWithBiometrics()
        XCTAssertFalse(auth.isAuthenticated); XCTAssertTrue(keychain.verifyPassword("PUBLIC-old-password"))
        await auth.resumePendingErase()
        XCTAssertFalse(auth.requiresEraseCompletion); XCTAssertFalse(auth.isPasswordSet)
        auth.password = "PUBLIC-new-password"; auth.confirmPassword = auth.password
        XCTAssertTrue(auth.isSetupButtonEnabled)
    }
}
