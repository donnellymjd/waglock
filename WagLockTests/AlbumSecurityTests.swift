import Foundation
import SwiftData
import Testing
import UIKit

@testable import WagLock

@MainActor
private final class TestBiometricStore: BiometricSecretStoring {
    var values: [String: String] = [:]
    var cancelled = false
    var onRead: (() -> Void)?
    func store(_ secret: String, account: String) async throws {
        if cancelled { throw CancellationError() }
        values[account] = secret
    }
    func read(account: String, reason: String) async throws -> String {
        onRead?()
        if cancelled { throw CancellationError() }
        guard let value = values[account] else { throw VaultAccessError.locked }
        return value
    }
    func remove(account: String) { values.removeValue(forKey: account) }
}

@MainActor
struct AlbumSecurityTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: VaultAlbum.self, MediaItem.self, SecretNote.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func denied(_ operation: () async throws -> Void) async {
        do { try await operation(); Issue.record("Locked or invalid access unexpectedly succeeded") }
        catch { }
    }

    @Test
    func parentAndChildPasswordsAreIndependentAndParentLockCascades() async throws {
        let db = try container()
        let store = AlbumStore(biometrics: TestBiometricStore())
        store.beginSession(vaultSecret: "vault-fixture")
        let parent = try await store.create(name: "Parent", parent: nil, protection: .password,
            password: "parent-password", albums: [], context: db.mainContext)
        let child = try await store.create(name: "Child", parent: parent, protection: .password,
            password: "child-password", albums: [parent], context: db.mainContext)
        let albums = [parent, child]
        store.lock(parent, albums: albums)
        await denied { try await store.unlock(child, password: "child-password", albums: albums) }
        await denied { try await store.unlock(parent, password: "vault-fixture", albums: albums) }
        try await store.unlock(parent, password: "parent-password", albums: albums)
        await denied { try await store.unlock(child, password: "parent-password", albums: albums) }
        try await store.unlock(child, password: "child-password", albums: albums)
        #expect(store.isUnlocked(child, albums: albums))
        store.lock(parent, albums: albums)
        #expect(!store.isUnlocked(child, albums: albums))
        #expect(throws: (any Error).self) { try store.assets(in: child, albums: albums) }
    }

    @Test
    func faceIDOnlyRejectsPasswordsAndCancellationLeavesItLocked() async throws {
        let db = try container()
        let biometric = TestBiometricStore()
        let store = AlbumStore(biometrics: biometric)
        store.beginSession(vaultSecret: "vault-fixture")
        let album = try await store.create(name: "Biometric", parent: nil, protection: .faceIDOnly,
            password: "", albums: [], context: db.mainContext)
        let account = try #require(album.biometricAccount)
        let factor = try #require(biometric.values[account])
        store.lock(album, albums: [album])
        // Even knowledge of the stored factor cannot use the password route in the app API.
        await denied { try await store.unlock(album, password: factor, albums: [album]) }
        biometric.cancelled = true
        await denied { try await store.unlock(album, useBiometrics: true, albums: [album]) }
        #expect(!store.isUnlocked(album, albums: [album]))
        biometric.cancelled = false
        try await store.unlock(album, useBiometrics: true, albums: [album])
        #expect(store.isUnlocked(album, albums: [album]))
    }

    @Test
    func passwordRemainsUsableWhenOptionalBiometricKeyIsLost() async throws {
        let db = try container()
        let biometric = TestBiometricStore()
        let store = AlbumStore(biometrics: biometric)
        store.beginSession(vaultSecret: "vault-fixture")
        let album = try await store.create(name: "Optional Face ID", parent: nil, protection: .passwordAndFaceID,
            password: "album-password", albums: [], context: db.mainContext)
        biometric.values.removeAll()
        store.lock(album, albums: [album])
        await denied { try await store.unlock(album, useBiometrics: true, albums: [album]) }
        try await store.unlock(album, password: "album-password", albums: [album])
        #expect(store.isUnlocked(album, albums: [album]))
    }

    @Test
    func lateBiometricResultCannotReopenAnEndedSession() async throws {
        let db = try container()
        let biometric = TestBiometricStore()
        let store = AlbumStore(biometrics: biometric)
        store.beginSession(vaultSecret: "vault-fixture")
        let album = try await store.create(name: "Late result", parent: nil, protection: .faceIDOnly,
            password: "", albums: [], context: db.mainContext)
        store.lock(album, albums: [album])
        biometric.onRead = { store.endSession() }
        await denied { try await store.unlock(album, useBiometrics: true, albums: [album]) }
        #expect(!store.isUnlocked(album, albums: [album]))
    }

    @Test
    func protectionChangeRewrapsKeysAndPreservesDescendants() async throws {
        let db = try container()
        let store = AlbumStore(biometrics: TestBiometricStore())
        store.beginSession(vaultSecret: "vault-fixture")
        let parent = try await store.create(name: "Parent", parent: nil, protection: .inherited,
            password: "", albums: [], context: db.mainContext)
        let child = try await store.create(name: "Child", parent: parent, protection: .inherited,
            password: "", albums: [parent], context: db.mainContext)
        let albums = [parent, child]
        try await store.changeProtection(of: parent, to: .password, password: "new-password",
                                         albums: albums, context: db.mainContext)
        #expect(!store.isUnlocked(parent, albums: albums))
        #expect(!store.isUnlocked(child, albums: albums))
        try await store.unlock(parent, password: "new-password", albums: albums)
        try await store.unlock(child, albums: albums)
        #expect(try store.assets(in: child, albums: albums).isEmpty)
    }

    @Test
    func cancelledEnrollmentDoesNotDowngradeExistingProtection() async throws {
        let db = try container()
        let biometric = TestBiometricStore()
        let store = AlbumStore(biometrics: biometric)
        store.beginSession(vaultSecret: "vault-fixture")
        let album = try await store.create(name: "Keep password", parent: nil, protection: .password,
            password: "old-password", albums: [], context: db.mainContext)
        biometric.cancelled = true
        await denied {
            try await store.changeProtection(of: album, to: .faceIDOnly, password: "",
                                             albums: [album], context: db.mainContext)
        }
        #expect(album.protectionRawValue == AlbumProtection.password.rawValue)
        store.lock(album, albums: [album])
        try await store.unlock(album, password: "old-password", albums: [album])
        #expect(store.isUnlocked(album, albums: [album]))
    }

    @Test
    func albumMediaAndThumbnailsDoNotEnterGlobalGalleryAndRootKeyCannotDecrypt() async throws {
        let db = try container()
        let store = AlbumStore(biometrics: TestBiometricStore())
        store.beginSession(vaultSecret: "vault-fixture")
        let album = try await store.create(name: "Media", parent: nil, protection: .password,
            password: "album-password", albums: [], context: db.mainContext)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
        let image = renderer.image { c in UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 20, height: 20)) }
        let data = try #require(image.pngData())
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let asset = try await store.importFile(source, into: album, albums: [album], context: db.mainContext,
                                               originalName: "sensitive-original.png")
        defer { try? FileStorageService.shared.deleteFile(path: asset.encryptedPath) }
        #expect(try db.mainContext.fetchCount(FetchDescriptor<MediaItem>()) == 0)
        #expect(album.encryptedCatalog.range(of: Data("sensitive-original.png".utf8)) == nil)
        #expect(!asset.encryptedPath.contains("sensitive-original"))
        #expect(try store.assets(in: album, albums: [album]).first?.thumbnail != nil)
        await denied {
            _ = try await FileStorageService.shared.loadDecryptedDataAsync(
                path: asset.encryptedPath, password: "vault-fixture", preferredExtension: ".png")
        }
        let preview = try await store.preview(asset, in: album, albums: [album])
        defer { try? FileManager.default.removeItem(at: preview.deletingLastPathComponent()) }
        #expect(try Data(contentsOf: preview) == data)
        store.lock(album, albums: [album])
        await denied { _ = try await store.preview(asset, in: album, albums: [album]) }
    }

    @Test
    func movingFromMainLibraryVerifiesContentBeforeRemovingOriginal() async throws {
        let db = try container()
        let store = AlbumStore(biometrics: TestBiometricStore())
        store.beginSession(vaultSecret: "vault-fixture")
        let data = Data("fixture bytes to preserve".utf8)
        let source = try FileStorageService.shared.saveEncrypted(
            data: EncryptionService.shared.encrypt(data: data, password: "vault-fixture"))
        defer { try? FileStorageService.shared.deleteFile(path: source) }
        let media = MediaItem(fileName: "original", fileExtension: ".txt", fileSize: Int64(data.count),
                              type: .document, encryptedPath: source)
        db.mainContext.insert(media)
        try db.mainContext.save()
        let album = try await store.create(name: "Moved", parent: nil, protection: .password,
            password: "album-password", albums: [], context: db.mainContext)
        try await store.moveFromLibrary(media, into: album, albums: [album], context: db.mainContext)
        let asset = try #require(try store.assets(in: album, albums: [album]).first)
        defer { try? FileStorageService.shared.deleteFile(path: asset.encryptedPath) }
        #expect(try db.mainContext.fetchCount(FetchDescriptor<MediaItem>()) == 0)
        #expect(!FileStorageService.shared.fileExists(path: source))
        #expect(asset.fileName == "original.txt")
        let preview = try await store.preview(asset, in: album, albums: [album])
        defer { try? FileManager.default.removeItem(at: preview.deletingLastPathComponent()) }
        #expect(try Data(contentsOf: preview) == data)
    }

    @Test
    func corruptedHierarchyAndCatalogFailClosed() async throws {
        let db = try container()
        let store = AlbumStore(biometrics: TestBiometricStore())
        store.beginSession(vaultSecret: "vault-fixture")
        let album = try await store.create(name: "Invalid", parent: nil, protection: .inherited,
            password: "", albums: [], context: db.mainContext)
        album.parentID = album.id
        #expect(!store.isUnlocked(album, albums: [album]))
        album.parentID = nil
        album.encryptedCatalog[album.encryptedCatalog.count - 1] ^= 1
        store.lock(album, albums: [album])
        await denied { try await store.unlock(album, albums: [album]) }
        #expect(!store.isUnlocked(album, albums: [album]))
    }

    @Test
    func addingAlbumSchemaPreservesExistingPersistentMedia() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store")
        func writeOldSchema() throws {
            let schema = Schema([MediaItem.self, SecretNote.self])
            let db = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            db.mainContext.insert(MediaItem(fileName: "keep-me", fileExtension: ".jpg", fileSize: 10,
                                            type: .photo, encryptedPath: "fixture.encrypted"))
            try db.mainContext.save()
        }
        try writeOldSchema()
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        let db = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let media = try db.mainContext.fetch(FetchDescriptor<MediaItem>())
        #expect(media.count == 1)
        #expect(media.first?.fileName == "keep-me")
        #expect(try db.mainContext.fetchCount(FetchDescriptor<VaultAlbum>()) == 0)
    }

    @Test
    func guestCannotReuseAnOldVaultDataPasswordToOpenAlbums() async throws {
        let db = try container()
        let keychain = KeychainService(service: "vaultito-auth-album-test-" + UUID().uuidString)
        defer { keychain.clearAllKeychainData() }
        try keychain.savePassword("246810")
        try keychain.changePassword(oldPassword: "246810", newPassword: "135790")
        try keychain.saveGuestPassword("246810")
        let store = AlbumStore.shared
        store.beginSession(vaultSecret: "246810")
        let album = try await store.create(name: "Owner only", parent: nil, protection: .inherited,
            password: "", albums: [], context: db.mainContext)
        store.endSession()
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false)
        defer { auth.logout() }
        auth.password = "246810"
        auth.login()
        while auth.isProcessing { try await Task.sleep(for: .milliseconds(10)) }
        #expect(GuestModeManager.shared.isGuestMode)
        await denied { try await store.unlock(album, albums: [album]) }
        auth.logout()
        auth.password = "135790"
        auth.login()
        while auth.isProcessing { try await Task.sleep(for: .milliseconds(10)) }
        #expect(GuestModeManager.shared.isOwnerMode)
        try await store.unlock(album, albums: [album])
        #expect(store.isUnlocked(album, albums: [album]))
        auth.logout()
        #expect(!store.isUnlocked(album, albums: [album]))
    }
}
