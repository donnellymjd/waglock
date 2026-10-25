import Foundation
import SwiftData
import XCTest
@testable import WagLock

@MainActor
final class PasswordWrappingUpgradeTests: XCTestCase {
    private let service = "PUBLIC-wrapping-upgrade"
    private let password = "PUBLIC-test-password"
    private let secret = "PUBLIC-preserved-random-data-secret"
    private func owner(_ storage: InMemoryAttemptStorage) throws -> (KeychainService, Data) {
        let plain = try JSONSerialization.data(withJSONObject: ["version": 1, "service": service, "dataPassword": secret])
        let legacy = try EncryptionService.shared.encrypt(data: plain, password: password)
        storage.values["vaultito.owner-credentials.v1"] = legacy
        return (KeychainService(service: service, storage: storage, allowLegacyCredentials: false), legacy)
    }
    func testAuthenticatedOwnerUpgradeKeepsSecretAndRestartReaderAndWrongPasswordPreservesSource() throws {
        let storage = InMemoryAttemptStorage(), account = "vaultito.owner-credentials.v1"
        let (keychain, legacy) = try owner(storage)
        XCTAssertEqual(try keychain.retrieveDataPassword(using: password), secret)
        XCTAssertEqual(storage.values[account], legacy, "Ordinary legacy reading is still read-only")
        XCTAssertThrowsError(try keychain.upgradeAuthenticatedOwnerWrapping(using: "PUBLIC-wrong"))
        XCTAssertEqual(storage.values[account], legacy)
        storage.failWrites = true
        XCTAssertThrowsError(try keychain.upgradeAuthenticatedOwnerWrapping(using: password))
        XCTAssertEqual(storage.values[account], legacy)
        storage.failWrites = false
        try keychain.upgradeAuthenticatedOwnerWrapping(using: password)
        let upgraded = try XCTUnwrap(storage.values[account])
        XCTAssertFalse(PasswordEnvelope.needsUpgrade(upgraded))
        XCTAssertNotEqual(upgraded, legacy)
        let restarted = KeychainService(service: service, storage: storage, allowLegacyCredentials: false)
        XCTAssertEqual(try restarted.retrieveDataPassword(using: password), secret)
        try restarted.upgradeAuthenticatedOwnerWrapping(using: password)
        XCTAssertEqual(storage.values[account], upgraded, "Modern records are not rewritten at each login")
    }
    func testSecondaryRejectsUnsupportedLegacyWrapperWithoutTouchingEitherRecord() throws {
        let storage = InMemoryAttemptStorage(), account = "waglock.secondary-credentials.v1"
        let keychain = KeychainService(service: service, storage: storage, allowLegacyCredentials: false)
        let id = UUID()
        let value = KeychainService.IndependentGuestCredential(version: 1, service: service, vaultID: id, dataPassword: secret)
        let envelope = try EncryptionService.shared.encrypt(data: JSONEncoder().encode(value), password: password)
        let source = try JSONSerialization.data(withJSONObject: ["version": 1, "vaultID": id.uuidString, "envelope": envelope.base64EncodedString()])
        storage.values[account] = source
        storage.values["vaultito.owner-credentials.v1"] = Data("PUBLIC unreadable primary".utf8)
        XCTAssertThrowsError(try keychain.unlockIndependentGuest(password: password))
        XCTAssertEqual(storage.values[account], source)
        XCTAssertEqual(storage.values["vaultito.owner-credentials.v1"], Data("PUBLIC unreadable primary".utf8))
    }
    func testSuccessfulSelectedPrimaryLoginUpgradesButFailedLoginDoesNot() async throws {
        let storage = InMemoryAttemptStorage(), account = "vaultito.owner-credentials.v1"
        let (keychain, original) = try owner(storage)
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false, independentVaultsEnabled: true)
        auth.password = "PUBLIC-wrong"; await auth.login()?.value
        XCTAssertFalse(auth.isAuthenticated); XCTAssertEqual(storage.values[account], original)
        auth.password = password; await auth.login()?.value
        XCTAssertTrue(auth.isAuthenticated); XCTAssertEqual(auth.sessionPassword, secret)
        XCTAssertFalse(PasswordEnvelope.needsUpgrade(try XCTUnwrap(storage.values[account])))
        auth.logout()
    }
    func testAuthenticatedAlbumUpgradeCommitsWithoutChangingPolicyCatalogOrSecret() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("album-upgrade-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let domain = EncryptedMetadataStore.Domain(libraryID: UUID(), vaultID: UUID()), key = Data(repeating: 19, count: 32)
        let repository = try EncryptedLibraryRepository.create(at: root, domain: domain, key: key, authorized: { true })
        defer { repository.revoke() }
        let db = repository.container
        let id = UUID(), parent = "PUBLIC-parent-random-key"
        let material = try JSONSerialization.data(withJSONObject: ["albumID": id.uuidString, "secret": secret])
        let factor = try EncryptionService.shared.encrypt(data: material, password: password)
        let wrapped = try EncryptionService.shared.encrypt(data: factor, password: parent)
        let catalog = try EncryptionService.shared.encrypt(data: Data("[]".utf8), password: secret)
        let album = VaultAlbum(id: id, parentID: nil, name: "PUBLIC album", protection: .password, wrappedKey: wrapped, encryptedCatalog: catalog)
        db.mainContext.insert(album); try LibraryWriteCoordinator.save(db.mainContext)
        let store = AlbumStore(attemptStorage: InMemoryAttemptStorage(), upgradeLegacyEnvelopes: true)
        store.beginSession(vaultSecret: parent)
        do { try await store.unlock(album, password: "PUBLIC-wrong", albums: [album]); XCTFail("Wrong password accepted") } catch {}
        XCTAssertEqual(album.wrappedKey, wrapped)
        try await store.unlock(album, password: password, albums: [album])
        XCTAssertEqual(album.encryptedCatalog, catalog); XCTAssertEqual(album.protectionRawValue, AlbumProtection.password.rawValue)
        let inner = try EncryptionService.shared.decrypt(encryptedData: album.wrappedKey, password: parent)
        XCTAssertFalse(PasswordEnvelope.needsUpgrade(inner))
        let opened = try PasswordEnvelope.open(inner, password: password, context: "album:" + id.uuidString)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: opened) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: material) as? NSDictionary)
        store.endSession(); repository.revoke()
        let reopened = try EncryptedLibraryRepository.open(at: root, domain: domain, key: key, authorized: { true })
        defer { reopened.revoke() }
        let restored = try XCTUnwrap(reopened.container.mainContext.fetch(FetchDescriptor<VaultAlbum>()).first)
        let restoredFactor = try EncryptionService.shared.decrypt(encryptedData: restored.wrappedKey, password: parent)
        XCTAssertFalse(PasswordEnvelope.needsUpgrade(restoredFactor))
        XCTAssertEqual(restored.encryptedCatalog, catalog)
    }
    private final class Biometrics: BiometricSecretStoring {
        nonisolated deinit {}
        var secret = ""
        func read(account: String, reason: String) async throws -> String { secret }
        func store(_ secret: String, account: String) async throws { self.secret = secret }
        func remove(account: String) { secret = "" }
    }
    func testBiometricsRequireOnePasswordUpgradeForAnOldPrimaryWrapper() async throws {
        let previous = UserDefaults.standard.object(forKey: "vaultito.faceID.enabled")
        defer { UserDefaults.standard.set(previous, forKey: "vaultito.faceID.enabled") }
        UserDefaults.standard.set(true, forKey: "vaultito.faceID.enabled")
        let storage = InMemoryAttemptStorage(), (keychain, original) = try owner(storage)
        let bio = Biometrics(); bio.secret = secret
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false,
            independentVaultsEnabled: true, biometrics: bio)
        defer { auth.logout() }
        await auth.loginWithBiometrics()
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertEqual(storage.values["vaultito.owner-credentials.v1"], original)
        auth.password = password; await auth.login()?.value
        XCTAssertTrue(auth.isAuthenticated); XCTAssertFalse(try keychain.ownerWrappingRequiresUpgrade())
        auth.logout(); await auth.loginWithBiometrics()
        XCTAssertTrue(auth.isAuthenticated); XCTAssertEqual(auth.sessionPassword, secret)
    }

    func testModernOptionalCredentialTimingEvidenceUsesSameDerivationBudget() throws {
        let absent = KeychainService(service: service, storage: InMemoryAttemptStorage(), allowLegacyCredentials: false)
        let storage = InMemoryAttemptStorage()
        let present = KeychainService(service: service, storage: storage, allowLegacyCredentials: false)
        try present.savePassword(password)
        try present.provisionIndependentGuest(password: "PUBLIC-secondary-password")
        let clock = ContinuousClock()
        func duration(_ operation: () -> Void) -> Double {
            let start = clock.now; operation()
            let value = start.duration(to: clock.now).components
            return Double(value.seconds) + Double(value.attoseconds) / 1e18
        }
        XCTAssertThrowsError(try absent.unlockIndependentGuest(password: "PUBLIC-wrong"))
        XCTAssertThrowsError(try present.unlockIndependentGuest(password: "PUBLIC-wrong"))
        XCTAssertNoThrow(try present.unlockIndependentGuest(password: "PUBLIC-secondary-password"))
        var absentTimes: [Double] = [], wrongTimes: [Double] = [], validTimes: [Double] = []
        // Alternate observations to reduce ordering/thermal bias. Evidence only, no flaky timing assertion.
        for _ in 0..<8 {
            absentTimes.append(duration { _ = try? absent.unlockIndependentGuest(password: "PUBLIC-wrong") })
            wrongTimes.append(duration { _ = try? present.unlockIndependentGuest(password: "PUBLIC-wrong") })
            validTimes.append(duration { _ = try? present.unlockIndependentGuest(password: "PUBLIC-secondary-password") })
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        let report: [String: Any] = ["samplesPerPath": 8, "absentMedianSeconds": median(absentTimes),
            "wrongMedianSeconds": median(wrongTimes), "validMedianSeconds": median(validTimes),
            "constantTimeClaim": false, "publicFixturesOnly": true]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("WAGLOCK_LOGIN_TIMING:" + String(decoding: data, as: UTF8.self))
    }
}
