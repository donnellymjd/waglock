import Foundation
import Security
import SwiftData
import XCTest
@testable import WagLock

@Model
private final class UnsupportedExportRecord {
    var text: String
    init() { text = "Future data must not disappear from exports" }
}

@MainActor
final class PortableExportSnapshotTests: XCTestCase {
    @MainActor
    private final class Biometrics: BiometricSecretStoring {
        var values: [String: String] = [:]
        func store(_ secret: String, account: String) async throws { values[account] = secret }
        func read(account: String, reason: String) async throws -> String { try XCTUnwrap(values[account]) }
        func remove(account: String) { values.removeValue(forKey: account) }
    }
    @MainActor
    private final class Fixture {
        let root: URL
        let db: ModelContainer
        let mounts: LibraryMountCoordinator
        let authority = DocumentPreviewService()
        let biometric = Biometrics()
        let albums: AlbumStore
        let storage: FileStorageService
        let request = LibraryMountCoordinator.Request(sessionID: UUID(), scope: .legacyOwner)
        var owner = true
        var keys: [UUID: String] = [:]
        var records: [VaultAlbum] = []
        init(unsupported: Bool = false) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("SnapshotFixture-" + UUID().uuidString)
            var types: [any PersistentModel.Type] = [MediaItem.self, SecretNote.self, VaultAlbum.self]
            if unsupported { types.append(UnsupportedExportRecord.self) }
            let schema = Schema(types)
            db = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            let container = db
            mounts = LibraryMountCoordinator { _ in container }
            albums = AlbumStore(biometrics: biometric)
            storage = FileStorageService(directory: root, availableCapacity: { _ in Int64.max })
            authority.beginSession(request.sessionID)
            albums.beginSession(vaultSecret: "synthetic-vault-key")
        }
        func begin() async { await mounts.mount(request) { true } }
        func cleanup() { albums.endSession(); mounts.invalidate(); try? FileManager.default.removeItem(at: root) }
        func collector(limit: Int = 64 * 1024 * 1024,
                       drafts: @escaping PortableExportSnapshotService.DraftReader = { [] }) -> PortableExportSnapshotService {
            PortableExportSnapshotService(mounts: mounts, authority: authority, albums: albums,
                storage: storage, metadataLimit: limit, isOwner: { [unowned self] in owner }, readDrafts: drafts)
        }
        func source(_ bytes: Data = Data("generated original".utf8)) throws -> String {
            let encrypted = try EncryptionService.shared.encrypt(data: bytes, password: "synthetic-vault-key")
            return try storage.saveEncrypted(data: encrypted)
        }
        func media(type: MediaType = .photo, id: UUID = UUID()) throws -> MediaItem {
            let item = MediaItem(id: id, fileName: "家族–café", fileExtension: ".bin", fileSize: 18,
                type: type, encryptedPath: try source(), thumbnailData: Data([0, 1, 2]),
                width: 320, height: 240, duration: type == .video ? 2.5 : nil)
            db.mainContext.insert(item)
            try db.mainContext.save()
            return item
        }
        /// Real authenticated catalogs and independent wrappers, all synthetic secrets.
        func album(name: String, parent: VaultAlbum? = nil, policy: AlbumProtection,
                   assets: [AlbumAsset] = []) async throws -> VaultAlbum {
            let id = UUID(), secret = "album-key-" + UUID().uuidString
            let factor = "factor-" + UUID().uuidString, account = UUID().uuidString
            let payload = try JSONSerialization.data(withJSONObject: ["albumID": id.uuidString, "secret": secret])
            let crypto = EncryptionService.shared
            let inner = policy == .inherited ? payload : try crypto.encrypt(data: payload, password: factor)
            let parentKey = parent.flatMap { keys[$0.id] } ?? "synthetic-vault-key"
            let album = VaultAlbum(id: id, parentID: parent?.id, name: name, protection: policy,
                wrappedKey: try crypto.encrypt(data: inner, password: parentKey),
                encryptedCatalog: try crypto.encrypt(data: JSONEncoder().encode(assets), password: secret),
                biometricAccount: policy.usesBiometrics ? account : nil)
            db.mainContext.insert(album); try db.mainContext.save()
            records.append(album); keys[id] = secret
            if policy.usesBiometrics { biometric.values[account] = factor }
            try await albums.unlock(album, password: factor, useBiometrics: policy == .faceIDOnly, albums: records)
            return album
        }
    }

    func testCapturesEveryLegacyCategoryAndPreservesIndependentNestedDomains() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let items = try MediaType.allCases.map { try f.media(type: $0) }
        let note = SecretNote(title: "秘密 café", content: "# Unmodified **Markdown**", isFavorite: true, tags: ["旅行", "café"])
        f.db.mainContext.insert(note); try f.db.mainContext.save()
        let asset = AlbumAsset(id: UUID(), fileName: "inner.mov", encryptedPath: try f.source(), fileSize: 18,
            type: .video, thumbnail: Data([3, 4]), createdAt: Date(timeIntervalSince1970: 123))
        let outer = try await f.album(name: "Outer private", policy: .password, assets: [asset])
        let child = try await f.album(name: "Inner private", parent: outer, policy: .passwordAndFaceID)
        let inherited = try await f.album(name: "Inherited leaf", parent: child, policy: .inherited)
        let publicAlbum = try await f.album(name: "Vault inherited", policy: .inherited)
        let draft = PortableExportSnapshot.Draft(origin: .keychain, title: "Draft", content: "not discarded", updatedAt: Date())
        let collector = f.collector(drafts: { [draft] })
        let snapshot = try collector.capture(f.request)
        XCTAssertEqual(snapshot.content.domains.count, 3)
        let root = try XCTUnwrap(snapshot.content.domains.first { $0.id == .root })
        XCTAssertEqual(Set(root.assets.map(\.id)), Set(items.map(\.id)))
        XCTAssertEqual(root.albums.map(\.id), [publicAlbum.id])
        XCTAssertEqual(root.notes.first?.tags, note.tags)
        XCTAssertEqual(root.notes.first?.content, note.content)
        XCTAssertEqual(root.drafts, [draft])
        XCTAssertEqual(root.children, [.album(outer.id)])
        let parent = try XCTUnwrap(snapshot.content.domains.first { $0.id == .album(outer.id) })
        XCTAssertEqual(parent.parent, .root)
        XCTAssertEqual(parent.children, [.album(child.id)])
        XCTAssertEqual(parent.assets.first?.id, asset.id)
        XCTAssertEqual(parent.assets.first?.thumbnail, asset.thumbnail)
        XCTAssertEqual(parent.albums.map(\.name), ["Outer private"])
        let inner = try XCTUnwrap(snapshot.content.domains.first { $0.id == .album(child.id) })
        XCTAssertEqual(inner.parent, .album(outer.id))
        XCTAssertEqual(Set(inner.albums.map(\.id)), [child.id, inherited.id])
        XCTAssertTrue(snapshot.content.trashNotImplemented)
        try collector.validateUnchanged(snapshot)
    }

    func testSnapshotIsIndependentOfLiveModelsAndSavedChangesInvalidateIt() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let item = try f.media()
        let collector = f.collector(), snapshot = try collector.capture(f.request)
        item.fileName = "Changed without modifiedAt update"
        XCTAssertThrowsError(try collector.capture(f.request))
        try f.db.mainContext.save()
        XCTAssertEqual(snapshot.content.domains[0].assets[0].name, "家族–café")
        XCTAssertThrowsError(try collector.validateUnchanged(snapshot))
    }

    func testOwnerGuestMountAndSameSessionRevocationCannotReuseSnapshots() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        _ = try f.media()
        let collector = f.collector(), snapshot = try collector.capture(f.request)
        f.owner = false
        XCTAssertThrowsError(try collector.capture(f.request))
        XCTAssertThrowsError(try collector.validateAuthorization(snapshot))
        f.owner = true
        f.authority.endSession(matching: f.request.sessionID)
        f.authority.beginSession(f.request.sessionID)
        XCTAssertThrowsError(try collector.validateAuthorization(snapshot))
        let fresh = try collector.capture(f.request)
        let guest = LibraryMountCoordinator.Request(sessionID: f.request.sessionID, scope: .ephemeralGuest)
        await f.mounts.mount(guest) { true }
        XCTAssertThrowsError(try collector.capture(guest))
        XCTAssertThrowsError(try collector.validateAuthorization(fresh))
    }

    func testAlbumRelockRevokesSnapshotAndLockedContentCannotBeOmitted() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let album = try await f.album(name: "Secret", policy: .password)
        let collector = f.collector(), snapshot = try collector.capture(f.request)
        f.albums.lock(album, albums: f.records)
        XCTAssertThrowsError(try collector.validateAuthorization(snapshot))
        XCTAssertThrowsError(try collector.capture(f.request)) { error in
            XCTAssertEqual(error as? PortableExportSnapshotService.Failure, .albumLocked(album.id))
        }
    }

    func testFaceIDOnlyIsExplicitlyBlockedEvenWhenUnlocked() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let album = try await f.album(name: "Biometric only", policy: .faceIDOnly)
        XCTAssertTrue(f.albums.isUnlocked(album, albums: f.records))
        XCTAssertThrowsError(try f.collector().capture(f.request)) { error in
            XCTAssertEqual(error as? PortableExportSnapshotService.Failure, .biometricRecoveryRequired(album.id))
        }
    }

    func testInvalidHierarchyUnknownPolicyAndCorruptCatalogFailClosed() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let album = try await f.album(name: "Test", policy: .inherited)
        let collector = f.collector()
        for parent in [album.id, UUID()] {
            album.parentID = parent; try f.db.mainContext.save()
            XCTAssertThrowsError(try collector.capture(f.request))
        }
        album.parentID = nil; album.protectionRawValue = "future-policy"; try f.db.mainContext.save()
        XCTAssertThrowsError(try collector.capture(f.request))
        album.protectionRawValue = AlbumProtection.inherited.rawValue
        album.encryptedCatalog = Data("corrupt".utf8); try f.db.mainContext.save()
        XCTAssertThrowsError(try collector.capture(f.request))
    }

    func testMissingForeignAndSymlinkSourcesAreRejectedWithoutChangingFiles() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let item = try f.media(), original = item.encryptedPath
        let sentinel = f.root.deletingLastPathComponent().appendingPathComponent("SnapshotSentinel-" + UUID().uuidString)
        try Data("keep".utf8).write(to: sentinel); defer { try? FileManager.default.removeItem(at: sentinel) }
        let link = f.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sentinel)
        for path in ["missing", sentinel.path, link.path, "../" + sentinel.lastPathComponent] {
            item.encryptedPath = path; try f.db.mainContext.save()
            XCTAssertThrowsError(try f.collector().capture(f.request))
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.root.appendingPathComponent(original).path))
    }

    func testSourceAndDraftChangesAreDetectedBeforeFuturePublication() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let item = try f.media()
        var draft = PortableExportSnapshot.Draft(origin: .keychain, title: "A", content: "old", updatedAt: Date())
        let collector = f.collector(drafts: { [draft] }), snapshot = try collector.capture(f.request)
        draft = .init(origin: .keychain, title: "A", content: "new", updatedAt: draft.updatedAt)
        XCTAssertThrowsError(try collector.validateUnchanged(snapshot))
        let fresh = try collector.capture(f.request)
        try Data("changed-length-ciphertext".utf8).write(to: f.root.appendingPathComponent(item.encryptedPath))
        XCTAssertThrowsError(try collector.validateUnchanged(fresh))
    }

    func testMetadataLimitsUnknownTypesAndDuplicateAssetIDsFailClosed() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let item = try f.media()
        XCTAssertThrowsError(try f.collector(limit: 1).capture(f.request))
        item.typeRawValue = "future-kind"; try f.db.mainContext.save()
        XCTAssertThrowsError(try f.collector().capture(f.request))
        item.typeRawValue = MediaType.photo.rawValue; try f.db.mainContext.save()
        _ = try f.media(id: item.id)
        XCTAssertThrowsError(try f.collector().capture(f.request))
    }

    func testUnsupportedSchemaAndRevocationDuringDraftReadFailClosed() async throws {
        let unsupported = try Fixture(unsupported: true); defer { unsupported.cleanup() }; await unsupported.begin()
        XCTAssertThrowsError(try unsupported.collector().capture(unsupported.request)) { error in
            XCTAssertEqual(error as? PortableExportSnapshotService.Failure, .unsupportedSchema)
        }
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let collector = f.collector { f.authority.endSession(); return [] }
        XCTAssertThrowsError(try collector.capture(f.request))
    }

    func testUnicodeEncodingChangesCannotPassUnchangedValidation() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let item = try f.media()
        let composed = "café", decomposed = "cafe\u{301}"
        XCTAssertEqual(composed, decomposed) // Swift's normal equality folds this distinction.
        XCTAssertNotEqual(Array(composed.utf8), Array(decomposed.utf8))
        item.fileName = composed
        let note = SecretNote(title: composed, content: composed, tags: [composed])
        f.db.mainContext.insert(note); try f.db.mainContext.save()
        let album = try await f.album(name: composed, policy: .inherited)
        var draft = PortableExportSnapshot.Draft(origin: .keychain, title: composed, content: composed, updatedAt: Date())
        let collector = f.collector(drafts: { [draft] })
        var snapshot = try collector.capture(f.request)
        item.fileName = decomposed; try f.db.mainContext.save()
        XCTAssertThrowsError(try collector.validateUnchanged(snapshot))
        snapshot = try collector.capture(f.request)
        note.content = decomposed; try f.db.mainContext.save()
        XCTAssertThrowsError(try collector.validateUnchanged(snapshot))
        snapshot = try collector.capture(f.request)
        note.tags = [decomposed]; try f.db.mainContext.save()
        XCTAssertThrowsError(try collector.validateUnchanged(snapshot))
        snapshot = try collector.capture(f.request)
        album.name = decomposed; try f.db.mainContext.save()
        XCTAssertThrowsError(try collector.validateUnchanged(snapshot))
        snapshot = try collector.capture(f.request)
        draft = .init(origin: .keychain, title: decomposed, content: composed, updatedAt: draft.updatedAt)
        XCTAssertThrowsError(try collector.validateUnchanged(snapshot))
    }

    func testUnknownAuthenticatedCatalogFieldsCannotSilentlyDisappear() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let asset = AlbumAsset(id: UUID(), fileName: "fixture.txt", encryptedPath: try f.source(), fileSize: 18,
            type: .document, thumbnail: nil, createdAt: Date())
        let album = try await f.album(name: "Future catalog", policy: .password, assets: [asset])
        let collector = f.collector()
        _ = try collector.capture(f.request)
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode([asset])) as? [[String: Any]])
        encoded[0]["futureCaption"] = "Metadata must not disappear"
        album.encryptedCatalog = try EncryptionService.shared.encrypt(
            data: JSONSerialization.data(withJSONObject: encoded), password: try XCTUnwrap(f.keys[album.id]))
        try f.db.mainContext.save()
        // Ordinary viewing remains compatible; a complete export must stop.
        XCTAssertEqual(try f.albums.assets(in: album, albums: f.records).count, 1)
        XCTAssertThrowsError(try collector.capture(f.request))
    }

    func testRemountedLibraryAndDifferentCollectorCannotReuseOldSnapshot() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let collector = f.collector(), snapshot = try collector.capture(f.request)
        XCTAssertThrowsError(try f.collector().validateAuthorization(snapshot))
        f.mounts.invalidate()
        await f.mounts.mount(f.request) { true }
        XCTAssertThrowsError(try collector.validateAuthorization(snapshot))
        let fresh = try collector.capture(f.request)
        try collector.validateAuthorization(fresh)
    }

    func testCancelledCaptureDoesNotReadDraftsOrReturnMetadata() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        var read = false
        let collector = f.collector(drafts: { read = true; return [] })
        let job = Task { try collector.capture(f.request) }
        job.cancel()
        do { _ = try await job.value; XCTFail("Cancelled capture returned metadata") }
        catch is CancellationError { }
        XCTAssertFalse(read)
    }

    func testCheckedDraftReadPreservesBothStoresAndRejectsInaccessibleOrCorruptData() throws {
        let store = DraftStorage(), keychain = KeychainService(service: "snapshot-fixture", storage: store)
        let suite = "SnapshotDrafts-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(try keychain.loadSecretNoteDraftChecked())
        let keychainDraft = try JSONEncoder().encode(SecretNoteDraft(title: "Keychain", content: "keep", updatedAt: Date()))
        let legacy = try JSONEncoder().encode(SecretNoteDraft(title: "Legacy", content: "also keep", updatedAt: Date()))
        store.items["secretNoteDraft"] = keychainDraft
        defaults.set(legacy, forKey: "secretSpace.draft")
        let values = try PortableExportSnapshotService.drafts(keychain: keychain, defaults: defaults)
        XCTAssertEqual(values.map(\.title), ["Keychain", "Legacy"])
        XCTAssertEqual(store.items["secretNoteDraft"], keychainDraft)
        XCTAssertEqual(defaults.data(forKey: "secretSpace.draft"), legacy)
        store.failReads = true
        XCTAssertThrowsError(try PortableExportSnapshotService.drafts(keychain: keychain, defaults: defaults))
        store.failReads = false
        defaults.set(Data("corrupt".utf8), forKey: "secretSpace.draft")
        XCTAssertThrowsError(try PortableExportSnapshotService.drafts(keychain: keychain, defaults: defaults))
        XCTAssertEqual(store.items["secretNoteDraft"], keychainDraft)
        defaults.set("wrong storage type", forKey: "secretSpace.draft")
        XCTAssertThrowsError(try PortableExportSnapshotService.drafts(keychain: keychain, defaults: defaults))
        defaults.set(legacy, forKey: "secretSpace.draft")
        var unknown = try XCTUnwrap(JSONSerialization.jsonObject(with: keychainDraft) as? [String: Any])
        unknown["futureAttachment"] = "must not disappear"
        store.items["secretNoteDraft"] = try JSONSerialization.data(withJSONObject: unknown)
        XCTAssertThrowsError(try PortableExportSnapshotService.drafts(keychain: keychain, defaults: defaults))
    }

    @MainActor
    private final class DraftStorage: KeychainStorage {
        var items: [String: Data] = [:]
        var failReads = false
        func read(account: String) throws -> Data {
            if failReads { throw KeychainError.unexpectedStatus(errSecInteractionNotAllowed) }
            guard let data = items[account] else { throw KeychainError.itemNotFound }
            return data
        }
        func write(account: String, data: Data, createOnly: Bool) throws { items[account] = data }
        func delete(account: String) throws { items.removeValue(forKey: account) }
    }
}
