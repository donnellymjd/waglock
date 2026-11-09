import Foundation
import XCTest
@testable import WagLock

/// View-model behavior of the multi-library model with disposable Keychain and roots.
@MainActor
final class LibrarySlotAuthenticationTests: XCTestCase {
    private final class Biometrics: BiometricSecretStoring {
        nonisolated deinit {}
        var values: [String: String] = [:]
        func store(_ secret: String, account: String) async throws { values[account] = secret }
        func read(account: String, reason: String) async throws -> String {
            guard let value = values[account] else { throw VaultAccessError.locked }; return value
        }
        func remove(account: String) { values.removeValue(forKey: account) }
    }
    private var roots: [URL] = []
    override func tearDown() { for root in roots { try? FileManager.default.removeItem(at: root) }; roots = [] }

    private func fixture() throws -> (AuthenticationViewModel, Biometrics) {
        let storage = InMemoryAttemptStorage()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); roots.append(root)
        let keychain = KeychainService(service: UUID().uuidString, storage: storage,
            makeDataPassword: { try FreshEncryptedLibrary.randomSecret() }, allowLegacyCredentials: false)
        let limiter = keychain.passwordAttemptLimiter()
        let passcodes = LibraryPasscodeService(keychain: keychain, table: keychain.librarySlotTable(logN: 10),
                                               limiter: limiter, minimumDuration: .zero)
        let biometrics = Biometrics()
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false,
            attemptLimiter: limiter, independentVaultsEnabled: true, contextFactory: { id, session, secret in
                let storage = FileStorageService(directory: root.appendingPathComponent(id?.uuidString ?? "legacy"),
                                                 availableCapacity: { _ in Int64.max })
                return try VaultSessionContext(vaultID: id ?? UUID(), sessionID: session, dataPassword: secret,
                    storage: storage, temporaryRoot: root, keychainNamespace: "PUBLIC-" + root.lastPathComponent)
            }, biometrics: biometrics, librarySlotsEnabled: true, passcodeService: passcodes)
        return (auth, biometrics)
    }

    private func setUp(_ auth: AuthenticationViewModel, _ passcode: String) async {
        auth.password = passcode; auth.confirmPassword = passcode
        auth.setupPassword()
        while auth.isProcessing { await Task.yield() }
    }

    private func unlock(_ auth: AuthenticationViewModel, _ passcode: String) async {
        auth.password = passcode
        await auth.login()?.value
    }

    func testEveryLibraryIsAPeerWithIdenticalControls() async throws {
        let (auth, _) = try fixture()
        await setUp(auth, "first-passcode")
        XCTAssertTrue(auth.isAuthenticated)
        let first = try XCTUnwrap(auth.currentLibrary)
        XCTAssertNotNil(first.independentID)
        XCTAssertFalse(auth.hasSecondaryVault)
        XCTAssertFalse(auth.canChangeVaultPasswords, "Slot mode never uses the primary-only API")
        try await auth.addLibraryPasscode("second-passcode")
        auth.logout()

        await unlock(auth, "second-passcode")
        let second = try XCTUnwrap(auth.currentLibrary)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(auth.canManageBiometricUnlock)
        XCTAssertFalse(auth.hasSecondaryVault)
        // The second library can change its own passcode without any other passcode.
        try await auth.changeLibraryPasscode(current: "second-passcode", new: "second-renamed")
        auth.logout()
        await unlock(auth, "second-renamed")
        XCTAssertEqual(auth.currentLibrary, second)
        auth.logout()
        await unlock(auth, "first-passcode")
        XCTAssertEqual(auth.currentLibrary, first)
    }

    func testWrongAndTimeLockedPasscodesShowTheSameMessage() async throws {
        let (auth, _) = try fixture()
        await setUp(auth, "first-passcode")
        try await auth.addLibraryPasscode("second-passcode")
        auth.logout()
        await unlock(auth, "second-passcode")
        try await auth.timeLockLibrary(passcode: "second-passcode", until: Date().addingTimeInterval(3600))
        XCTAssertFalse(auth.isAuthenticated, "Setting a time lock locks WagLock")
        await unlock(auth, "second-passcode")
        let locked = auth.errorMessage
        XCTAssertFalse(auth.isAuthenticated)
        await unlock(auth, "never-a-passcode")
        let wrong = auth.errorMessage
        XCTAssertEqual(locked?.prefix(16), wrong?.prefix(16))
        XCTAssertEqual(locked, "Wrong passcode. 4 tries left before a 5-minute wait.")
        XCTAssertEqual(wrong, "Wrong passcode. 3 tries left before a 5-minute wait.")
    }

    func testFaceIDMovesBetweenLibrariesAndOnlyItsHolderCanTurnItOff() async throws {
        let (auth, _) = try fixture()
        await setUp(auth, "first-passcode")
        let first = try XCTUnwrap(auth.currentLibrary)
        try await auth.enableBiometricUnlock(password: "first-passcode")
        XCTAssertTrue(auth.isBiometricAssignedHere)
        try await auth.addLibraryPasscode("second-passcode")
        auth.logout()
        await unlock(auth, "second-passcode")
        XCTAssertFalse(auth.isBiometricAssignedHere, "Shown as Off for this library")
        auth.disableBiometricUnlock()
        XCTAssertTrue(auth.isBiometricUnlockEnabled, "A library cannot turn off another library's Face ID")
        let second = try XCTUnwrap(auth.currentLibrary)
        try await auth.enableBiometricUnlock(password: "second-passcode")
        auth.logout()
        await auth.loginWithBiometrics()
        XCTAssertEqual(auth.currentLibrary, second)
        XCTAssertNotEqual(auth.currentLibrary, first)
    }

    func testDeletingALibraryRemovesOnlyItsPasscodeAndFaceID() async throws {
        let (auth, biometrics) = try fixture()
        await setUp(auth, "first-passcode")
        let first = try XCTUnwrap(auth.currentLibrary)
        try await auth.addLibraryPasscode("second-passcode")
        auth.logout()
        await unlock(auth, "second-passcode")
        try await auth.enableBiometricUnlock(password: "second-passcode")
        try await auth.deleteLibrary(passcode: "second-passcode")
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertTrue(biometrics.values.isEmpty)
        await unlock(auth, "second-passcode")
        XCTAssertFalse(auth.isAuthenticated)
        await unlock(auth, "first-passcode")
        XCTAssertEqual(auth.currentLibrary, first)
    }
}
