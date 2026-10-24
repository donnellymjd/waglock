import Foundation
import SwiftData
import XCTest
@testable import WagLock

@MainActor
final class SecondaryVaultAuthenticationTests: XCTestCase {
    private final class Biometrics: BiometricSecretStoring {
        nonisolated deinit {}
        var values: [String: String] = [:]
        var cancelled = false
        func store(_ secret: String, account: String) async throws { values[account] = secret }
        func read(account: String, reason: String) async throws -> String {
            if cancelled { throw CancellationError() }
            guard let value = values[account] else { throw VaultAccessError.locked }; return value
        }
        func remove(account: String) { values.removeValue(forKey: account) }
    }
    private final class Anchor: LibraryIdentityAnchor {
        nonisolated deinit {}
        var value: Data?
        func loadLibraryIdentity() throws -> Data? { value }
        func establishLibraryIdentity(_ identity: Data) throws {
            guard value == nil else { throw KeychainError.duplicateItem }; value = identity
        }
    }
    private var roots: [URL] = []
    override func tearDown() { for root in roots { try? FileManager.default.removeItem(at: root) }; roots = [] }
    private func fixture() throws -> (AuthenticationViewModel, KeychainService, Biometrics, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); roots.append(root)
        let keychain = KeychainService(service: UUID().uuidString, storage: InMemoryAttemptStorage(),
            makeDataPassword: { "PUBLIC-independent-primary-data-key" })
        try keychain.savePassword("PUBLIC-primary-password")
        let biometrics = Biometrics()
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false,
            independentVaultsEnabled: true, contextFactory: { id, session, secret in
                let storage = FileStorageService(directory: root.appendingPathComponent(id?.uuidString ?? "primary"), availableCapacity: { _ in Int64.max })
                return try VaultSessionContext(vaultID: id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    sessionID: session, dataPassword: secret, storage: storage, temporaryRoot: root,
                    keychainNamespace: "PUBLIC-" + root.lastPathComponent)
            }, biometrics: biometrics)
        return (auth, keychain, biometrics, root)
    }
    private func login(_ auth: AuthenticationViewModel, _ password: String) async throws {
        auth.password = password
        await (try XCTUnwrap(auth.login())).value
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertNotNil(auth.vaultContext)
    }

    func testOrdinaryLoginSelectsIndependentUsableVaultAndPasswordChangesStayWithinIt() async throws {
        let (auth, keychain, _, root) = try fixture()
        defer { auth.logout() }
        try await login(auth, "PUBLIC-primary-password")
        try auth.provisionSecondaryVault(password: "PUBLIC-secondary-password")
        let primary = try XCTUnwrap(auth.vaultContext)
        let primarySecret = try XCTUnwrap(auth.sessionPassword)
        let primaryFile = try primary.storage.saveEncrypted(data: EncryptionService.shared.encrypt(data: Data("PUBLIC primary only".utf8), password: primarySecret))
        auth.logout()
        XCTAssertFalse(primary.isActive)
        try await login(auth, "PUBLIC-secondary-password")
        XCTAssertFalse(auth.isPrimaryVault)
        XCTAssertTrue(GuestModeManager.shared.isOwnerMode)
        XCTAssertFalse(GuestModeManager.shared.isGuestMode)
        let secondary = try XCTUnwrap(auth.vaultContext)
        let secondaryID = try XCTUnwrap(auth.secondaryVaultID)
        let secondarySecret = try XCTUnwrap(auth.sessionPassword)
        XCTAssertNotEqual(primarySecret, secondarySecret)
        XCTAssertNotEqual(primary.storage.getStorageDirectory(), secondary.storage.getStorageDirectory())
        XCTAssertThrowsError(try auth.provisionSecondaryVault(password: "PUBLIC-other-password"))
        let anchor = Anchor()
        let mount = LibraryMountCoordinator(encryptedRoot: root.appendingPathComponent("secondary-index"), anchor: anchor,
            scope: auth.libraryScope, storage: secondary.storage)
        var request = LibraryMountCoordinator.Request(sessionID: auth.librarySessionID, scope: auth.libraryScope)
        await mount.mount(request, dataPassword: secondarySecret) { auth.isAuthenticated }
        let context = try mount.container(for: request).mainContext
        context.insert(SecretNote(title: "PUBLIC secondary note", content: "secondary only"))
        try LibraryWriteCoordinator.save(context)
        XCTAssertTrue(LibraryWriteCoordinator.draftManager(in: context).saveDraft(title: "PUBLIC draft", content: "unfinished secondary"))
        _ = try await secondary.albums.create(name: "PUBLIC protected album", parent: nil, protection: .password,
            password: "PUBLIC-album-password", albums: [], context: context)
        let collector = PortableExportSnapshotService(mounts: mount, authority: secondary.documents,
            albums: secondary.albums, storage: secondary.storage,
            isOwner: { auth.isAuthenticated && auth.secondaryVaultID == secondaryID })
        let snapshot = try collector.capture(request)
        XCTAssertEqual(snapshot.content.domains.flatMap(\.notes).map(\.content), ["secondary only"])
        XCTAssertEqual(snapshot.content.domains.flatMap(\.drafts).map(\.content), ["unfinished secondary"])
        let foreign = MediaItem(fileName: "PUBLIC foreign", fileExtension: "txt", fileSize: 19, type: .document,
            encryptedPath: try primary.storage.getFileURL(for: primaryFile).path)
        context.insert(foreign); try LibraryWriteCoordinator.save(context)
        XCTAssertThrowsError(try collector.capture(request))
        context.delete(foreign); try LibraryWriteCoordinator.save(context)
        XCTAssertTrue(primary.storage.fileExists(path: primaryFile))
        try auth.updatePassword(oldPassword: "PUBLIC-secondary-password", newPassword: "PUBLIC-changed-secondary")
        XCTAssertNil(mount.active)
        XCTAssertFalse(secondary.isActive)
        XCTAssertEqual(auth.secondaryVaultID, secondaryID)
        XCTAssertEqual(auth.sessionPassword, secondarySecret)
        XCTAssertTrue(keychain.verifyPassword("PUBLIC-primary-password"))
        auth.logout()
        try await login(auth, "PUBLIC-changed-secondary")
        request = .init(sessionID: auth.librarySessionID, scope: auth.libraryScope)
        await mount.mount(request, dataPassword: auth.sessionPassword) { auth.isAuthenticated }
        XCTAssertEqual(try mount.container(for: request).mainContext.fetch(FetchDescriptor<SecretNote>()).first?.content, "secondary only")
        XCTAssertEqual(try mount.exportDrafts().first?.content, "unfinished secondary")
        auth.logout()
        try await login(auth, "PUBLIC-primary-password")
        XCTAssertTrue(auth.isPrimaryVault)
        XCTAssertEqual(auth.sessionPassword, primarySecret)
    }

    func testFaceIDCanBeExplicitlyAssignedToEitherVaultAndCancellationStaysLocked() async throws {
        let previous = UserDefaults.standard.object(forKey: "vaultito.faceID.enabled")
        defer { UserDefaults.standard.set(previous, forKey: "vaultito.faceID.enabled") }
        let (auth, _, bio, _) = try fixture()
        defer { auth.logout() }
        try await login(auth, "PUBLIC-primary-password")
        try auth.provisionSecondaryVault(password: "PUBLIC-secondary-password")
        try await auth.enableBiometricUnlock(password: "PUBLIC-primary-password")
        auth.logout()
        await auth.loginWithBiometrics()
        XCTAssertTrue(auth.isAuthenticated); XCTAssertTrue(auth.isPrimaryVault)
        auth.logout()
        try await login(auth, "PUBLIC-secondary-password")
        let guestID = auth.secondaryVaultID
        XCTAssertThrowsError(try auth.updatePassword(oldPassword: "PUBLIC-secondary-password", newPassword: "PUBLIC-primary-password"))
        do { try await auth.enableBiometricUnlock(password: "PUBLIC-primary-password"); XCTFail("Wrong vault authorized enrollment") } catch {}
        try await auth.enableBiometricUnlock(password: "PUBLIC-secondary-password")
        auth.logout()
        await auth.loginWithBiometrics()
        XCTAssertTrue(auth.isAuthenticated); XCTAssertEqual(auth.secondaryVaultID, guestID)
        auth.logout(); bio.cancelled = true
        await auth.loginWithBiometrics()
        XCTAssertFalse(auth.isAuthenticated); XCTAssertNil(auth.vaultContext)
        bio.cancelled = false
        bio.values[BiometricSecretStore.vaultAccount] = "WLBG1:invalid"
        await auth.loginWithBiometrics()
        XCTAssertFalse(auth.isAuthenticated); XCTAssertNil(auth.sessionPassword)
    }
}
