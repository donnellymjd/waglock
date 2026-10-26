import Foundation
import CryptoKit
import Security
import UIKit
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
    private final class FixtureAnchor: LibraryIdentityAnchor {
        nonisolated deinit { }
        private var value: Data?
        func loadLibraryIdentity() throws -> Data? { value }
        func establishLibraryIdentity(_ identity: Data) throws {
            guard value == nil else { throw KeychainError.duplicateItem }; value = identity
        }
    }
    @MainActor
    private final class Fixture {
        let root: URL
        var db: ModelContainer!
        let mounts: LibraryMountCoordinator
        let authority = DocumentPreviewService()
        let biometric = Biometrics()
        let albums: AlbumStore
        let storage: FileStorageService
        let request = LibraryMountCoordinator.Request(sessionID: UUID(), scope: .legacyOwner)
        var owner = true
        var keys: [UUID: String] = [:]
        var factors: [UUID: String] = [:]
        var records: [VaultAlbum] = []
        init(unsupported: Bool = false, encrypted: Bool = false) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("SnapshotFixture-" + UUID().uuidString)
            var types: [any PersistentModel.Type] = [MediaItem.self, SecretNote.self, VaultAlbum.self]
            if unsupported { types.append(UnsupportedExportRecord.self) }
            let schema = Schema(types)
            if encrypted {
                mounts = LibraryMountCoordinator(encryptedRoot: root.resolvingSymlinksInPath().appendingPathComponent("encrypted-metadata"), anchor: FixtureAnchor())
            } else {
                let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
                db = container
                mounts = LibraryMountCoordinator { _ in container }
            }
            albums = AlbumStore(biometrics: biometric, attemptStorage: InMemoryAttemptStorage())
            storage = FileStorageService(directory: root, availableCapacity: { _ in Int64.max })
            authority.beginSession(request.sessionID)
            albums.beginSession(vaultSecret: "synthetic-vault-key")
        }
        func begin() async {
            await mounts.mount(request, dataPassword: "synthetic-vault-key") { true }
            if db == nil { db = mounts.active?.container }
        }
        func cleanup() { albums.endSession(); mounts.invalidate(); try? FileManager.default.removeItem(at: root) }
        func collector(limit: Int = 64 * 1024 * 1024,
                       drafts: @escaping PortableExportSnapshotService.DraftReader = { [] }) -> PortableExportSnapshotService {
            PortableExportSnapshotService(mounts: mounts, authority: authority, albums: albums,
                storage: storage, metadataLimit: limit, isOwner: { [unowned self] in owner }, readDrafts: drafts)
        }
        func source(_ bytes: Data = Data("generated original".utf8), key: String = "synthetic-vault-key") throws -> String {
            let encrypted = try EncryptionService.shared.encrypt(data: bytes, password: key)
            return try storage.saveEncrypted(data: encrypted)
        }
        func media(type: MediaType = .photo, id: UUID = UUID()) throws -> MediaItem {
            let item = MediaItem(id: id, fileName: "家族–café", fileExtension: ".bin", fileSize: 18,
                type: type, encryptedPath: try source(), thumbnailData: Data([0, 1, 2]),
                width: 320, height: 240, duration: type == .video ? 2.5 : nil)
            db.mainContext.insert(item)
            try LibraryWriteCoordinator.save(db.mainContext)
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
            db.mainContext.insert(album); try LibraryWriteCoordinator.save(db.mainContext)
            records.append(album); keys[id] = secret; factors[id] = factor
            if policy.usesBiometrics { biometric.values[account] = factor }
            try await albums.unlock(album, password: factor, useBiometrics: policy == .faceIDOnly, albums: records)
            return album
        }
    }

    func testCapturesEveryLegacyCategoryAndPreservesIndependentNestedDomains() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let items = try MediaType.allCases.map { try f.media(type: $0) }
        let note = SecretNote(title: "秘密 café", content: "# Unmodified **Markdown**", isFavorite: true, tags: ["旅行", "café"])
        f.db.mainContext.insert(note); try LibraryWriteCoordinator.save(f.db.mainContext)
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
        try LibraryWriteCoordinator.save(f.db.mainContext)
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
            album.parentID = parent; try LibraryWriteCoordinator.save(f.db.mainContext)
            XCTAssertThrowsError(try collector.capture(f.request))
        }
        album.parentID = nil; album.protectionRawValue = "future-policy"; try LibraryWriteCoordinator.save(f.db.mainContext)
        XCTAssertThrowsError(try collector.capture(f.request))
        album.protectionRawValue = AlbumProtection.inherited.rawValue
        album.encryptedCatalog = Data("corrupt".utf8); try LibraryWriteCoordinator.save(f.db.mainContext)
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
            item.encryptedPath = path; try LibraryWriteCoordinator.save(f.db.mainContext)
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
        item.typeRawValue = "future-kind"; try LibraryWriteCoordinator.save(f.db.mainContext)
        XCTAssertThrowsError(try f.collector().capture(f.request))
        item.typeRawValue = MediaType.photo.rawValue; try LibraryWriteCoordinator.save(f.db.mainContext)
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
        f.db.mainContext.insert(note); try LibraryWriteCoordinator.save(f.db.mainContext)
        let album = try await f.album(name: composed, policy: .inherited)
        var draft = PortableExportSnapshot.Draft(origin: .keychain, title: composed, content: composed, updatedAt: Date())
        let collector = f.collector(drafts: { [draft] })
        var snapshot = try collector.capture(f.request)
        item.fileName = decomposed; try LibraryWriteCoordinator.save(f.db.mainContext)
        XCTAssertThrowsError(try collector.validateUnchanged(snapshot))
        snapshot = try collector.capture(f.request)
        note.content = decomposed; try LibraryWriteCoordinator.save(f.db.mainContext)
        XCTAssertThrowsError(try collector.validateUnchanged(snapshot))
        snapshot = try collector.capture(f.request)
        note.tags = [decomposed]; try LibraryWriteCoordinator.save(f.db.mainContext)
        XCTAssertThrowsError(try collector.validateUnchanged(snapshot))
        snapshot = try collector.capture(f.request)
        album.name = decomposed; try LibraryWriteCoordinator.save(f.db.mainContext)
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
        try LibraryWriteCoordinator.save(f.db.mainContext)
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

    func testCompleteNativeBackupFixtureForIndependentRecovery() async throws {
        try await completeBackupFixture(encrypted: false)
    }
    func testEncryptedLibraryBackupFixtureForIndependentRecovery() async throws {
        try await completeBackupFixture(encrypted: true)
    }
    private func recoveryPayload(_ type: MediaType) throws -> (Data, String) {
        switch type {
        case .photo:
            let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 96)).image { context in
                UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 96))
            }
            return (try XCTUnwrap(image.pngData()), "png")
        case .video:
            let bundle = Bundle(for: Self.self)
            let url = bundle.url(forResource: "public-synthetic-video", withExtension: "mov", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "public-synthetic-video", withExtension: "mov")
            return (try Data(contentsOf: XCTUnwrap(url)), "mov")
        case .audio:
            func little<T: FixedWidthInteger>(_ value: T) -> Data {
                var word = value.littleEndian; return Data(bytes: &word, count: MemoryLayout<T>.size)
            }
            let samples = Data(repeating: 0, count: 16_000)
            var bytes = Data("RIFF".utf8); bytes += little(UInt32(36 + samples.count)); bytes += Data("WAVEfmt ".utf8)
            bytes += little(UInt32(16)); bytes += little(UInt16(1)); bytes += little(UInt16(1))
            bytes += little(UInt32(8_000)); bytes += little(UInt32(16_000)); bytes += little(UInt16(2)); bytes += little(UInt16(16))
            bytes += Data("data".utf8); bytes += little(UInt32(samples.count)); bytes += samples
            return (bytes, "wav")
        case .document:
            let bytes = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 320, height: 240)).pdfData { context in
                context.beginPage(); ("Public synthetic recovery document" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
            }
            return (bytes, "pdf")
        }
    }

    private func completeBackupFixture(encrypted: Bool) async throws {
        let f = try Fixture(encrypted: encrypted); defer { f.cleanup() }; await f.begin()
        XCTAssertNotNil(f.db)
        guard f.db != nil else { return XCTFail("Encrypted fixture failed to mount") }
        var originals: [String: String] = [:], formats: [String: String] = [:]
        let items: [MediaItem]
        if encrypted {
            items = try MediaType.allCases.map { type in
                let (bytes, suffix) = try recoveryPayload(type)
                let item = MediaItem(fileName: "Recovery " + type.rawValue + " café", fileExtension: suffix,
                    fileSize: Int64(bytes.count), type: type, encryptedPath: try f.source(bytes),
                    thumbnailData: type == .photo ? bytes : nil)
                f.db.mainContext.insert(item)
                originals[item.id.uuidString] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                formats[item.id.uuidString] = suffix
                return item
            }
            try LibraryWriteCoordinator.save(f.db.mainContext)
        } else { items = try MediaType.allCases.map { try f.media(type: $0) } }
        let note = SecretNote(title: "Public café 家族", content: "# Disposable **recovery** note", isFavorite: true, tags: ["cafe\u{301}"])
        f.db.mainContext.insert(note); try LibraryWriteCoordinator.save(f.db.mainContext)
        let parent = try await f.album(name: "Private parent", policy: .passwordAndFaceID)
        let child = try await f.album(name: "Private child", parent: parent, policy: .password)
        let leaf = try await f.album(name: "Inherited leaf", parent: child, policy: .inherited)
        var expected: [String: String] = [:]
        for album in [parent, child, leaf] {
            let key = try XCTUnwrap(f.keys[album.id])
            let content = Data((0..<73113).map { UInt8(($0 * 7) % 251) })
            let asset = AlbumAsset(id: UUID(), fileName: "original café.bin", encryptedPath: try f.source(content, key: key),
                fileSize: Int64(content.count), type: .document, thumbnail: Data([7, 8, 9]), createdAt: Date(timeIntervalSince1970: 42))
            album.encryptedCatalog = try EncryptionService.shared.encrypt(data: JSONEncoder().encode([asset]), password: key)
            expected[asset.id.uuidString] = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        }
        try LibraryWriteCoordinator.save(f.db.mainContext)
        for item in items { expected[item.id.uuidString] = originals[item.id.uuidString] ?? SHA256.hash(data: Data("generated original".utf8)).map { String(format: "%02x", $0) }.joined() }
        let draft = PortableExportSnapshot.Draft(origin: .keychain, title: "Public draft", content: "Saved, not omitted", updatedAt: Date(timeIntervalSince1970: 99))
        let collector: PortableExportSnapshotService
        if encrypted {
            let manager = LibraryWriteCoordinator.draftManager(in: f.db.mainContext)
            XCTAssertTrue(manager.saveDraft(title: draft.title, content: draft.content))
            collector = PortableExportSnapshotService(mounts: f.mounts, authority: f.authority, albums: f.albums,
                storage: f.storage, isOwner: { true })
        } else { collector = f.collector(drafts: { [draft] }) }
        let snapshot = try collector.capture(f.request)
        if encrypted { XCTAssertEqual(snapshot.content.domains.first { $0.id == .root }?.drafts.first?.origin, .encryptedVault) }
        let rootPassword = "WagLock*public._backup-test2026"
        let credentials: [PortableExportSnapshot.DomainID: AgeFileWriter.Credential] = [
            .root: .password(rootPassword), .album(parent.id): .password(try XCTUnwrap(f.factors[parent.id])),
            .album(child.id): .password(try XCTUnwrap(f.factors[child.id]))]
        let plan = try BackupPlanFactory.make(snapshot: snapshot, rootKey: "synthetic-vault-key", albumStore: f.albums, albums: f.records, credentials: credentials)
        let folder = f.root.appendingPathComponent("backup-job")
        let output = try await Task.detached { try BackupArchiveBuilder.build(plan, directory: folder, lease: BackupLease()) }.value
        try collector.validateUnchanged(snapshot)
        let encryptedBytes = try Data(contentsOf: output)
        XCTAssertNil(encryptedBytes.range(of: Data(note.content.utf8)))
        XCTAssertNil(encryptedBytes.range(of: Data("Private child".utf8)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("working-media").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
        let fixture: [String: Any] = ["fixtureOnly": true, "rootPassword": rootPassword,
            "childPasswords": [parent.id.uuidString: f.factors[parent.id]!, child.id.uuidString: f.factors[child.id]!],
            "expectedPayloadHashes": expected, "expectedMediaFormats": formats, "expectedNotes": [note.content], "expectedDrafts": [draft.content],
            "expectedAlbums": [parent.name, child.name, leaf.name], "originalPhoneKeychainRequired": false]
        let archive = XCTAttachment(contentsOfFile: output); archive.name = encrypted ? "public-encrypted-library-backup.tar.age" : "public-native-backup.tar.age"; archive.lifetime = .keepAlways; add(archive)
        let details = XCTAttachment(data: try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        details.name = encrypted ? "public-encrypted-library-backup-expected.json" : "public-native-backup-expected.json"; details.lifetime = .keepAlways; add(details)
    }

    func testFaceIDOnlyPortableCopyNeedsExplicitConsentAndKeepsItsOwnDomain() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let album = try await f.album(name: "Face ID fixture", policy: .faceIDOnly)
        let collector = f.collector()
        XCTAssertThrowsError(try collector.capture(f.request))
        let snapshot = try collector.capture(f.request, approvedBiometricAlbums: [album.id])
        XCTAssertEqual(snapshot.content.domains.count, 2)
        XCTAssertTrue(snapshot.content.domains.first { $0.id == .root }!.albums.isEmpty)
        let key = Data(album.wrappedKey)
        let plan = try BackupPlanFactory.make(snapshot: snapshot, rootKey: "synthetic-vault-key", albumStore: f.albums,
            albums: f.records, credentials: [.root: .password("new outer password"), .album(album.id): .password("separate export password")])
        XCTAssertEqual(plan.domains.count, 2)
        XCTAssertEqual(album.wrappedKey, key)
        XCTAssertEqual(album.protectionRawValue, AlbumProtection.faceIDOnly.rawValue)
        try collector.validateUnchanged(snapshot)
        XCTAssertThrowsError(try collector.capture(f.request, approvedBiometricAlbums: [UUID()]))
    }

    func testBackupMayReuseVerifiedShortVaultPasswordOnlyWithConsent() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let keychain = KeychainService(service: "PUBLIC-reuse-backup-" + UUID().uuidString)
        defer { keychain.clearAllKeychainData() }
        _ = try keychain.savePassword("123456")
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false, documentPreviewService: f.authority)
        defer { auth.logout() }
        auth.password = "123456"; await (try XCTUnwrap(auth.login())).value
        let request = LibraryMountCoordinator.Request(sessionID: auth.librarySessionID, scope: .legacyOwner)
        await f.mounts.mount(request) { true }
        f.db.mainContext.insert(SecretNote(title: "PUBLIC reused password", content: "PUBLIC preserved note"))
        try LibraryWriteCoordinator.save(f.db.mainContext)
        let session = PortableBackupSession(authority: f.authority)
        defer { session.cancel() }
        func finish() async throws {
            let deadline = Date().addingTimeInterval(30)
            while session.isWorking, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertFalse(session.isWorking)
        }
        session.start(mounts: f.mounts, auth: auth, rootCredential: .password("123456"), passwords: [:], consent: [])
        try await finish(); XCTAssertNil(session.readyURL); XCTAssertNotNil(session.error)
        session.start(mounts: f.mounts, auth: auth, rootCredential: .password("123456"), passwords: [:], consent: [], passwordSource: .currentVault)
        try await finish(); XCTAssertNil(session.readyURL)
        session.start(mounts: f.mounts, auth: auth, rootCredential: .password("654321"), passwords: [:], consent: [], passwordSource: .currentVault, acknowledgedReuse: true)
        try await finish(); XCTAssertNil(session.readyURL)
        XCTAssertEqual(try keychain.passwordAttemptLimiter(scope: "settings:primary").status().failures, 1)
        session.start(mounts: f.mounts, auth: auth, rootCredential: .password("123456"), passwords: [:], consent: [], passwordSource: .currentVault, acknowledgedReuse: true)
        try await finish()
        let output = try XCTUnwrap(session.readyURL, session.error ?? "No backup")
        XCTAssertEqual(try keychain.passwordAttemptLimiter(scope: "settings:primary").status().failures, 0)
        XCTAssertTrue(try Data(contentsOf: output).starts(with: Data("age-encryption.org/v1".utf8)))
        let archive = XCTAttachment(contentsOfFile: output); archive.name = "PUBLIC-reused-vault-password.tar.age"
        archive.lifetime = .keepAlways; add(archive)
        XCTAssertTrue(auth.isAuthenticated); XCTAssertTrue(keychain.verifyPassword("123456"))
    }

    func testBackupReuseWrongPasswordsShareDurableSettingsCooldown() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let keychain = KeychainService(service: "PUBLIC-reuse-budget-" + UUID().uuidString)
        defer { keychain.clearAllKeychainData() }
        _ = try keychain.savePassword("PUBLIC vault password")
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false, documentPreviewService: f.authority)
        defer { auth.logout() }
        auth.password = "PUBLIC vault password"; await (try XCTUnwrap(auth.login())).value
        await f.mounts.mount(.init(sessionID: auth.librarySessionID, scope: .legacyOwner)) { true }
        let session = PortableBackupSession(authority: f.authority)
        defer { session.cancel() }
        for candidate in Array(repeating: "PUBLIC wrong password", count: 5) + ["PUBLIC vault password"] {
            session.start(mounts: f.mounts, auth: auth, rootCredential: .password(candidate), passwords: [:], consent: [], passwordSource: .currentVault, acknowledgedReuse: true)
            let deadline = Date().addingTimeInterval(10)
            while session.isWorking, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNil(session.readyURL); XCTAssertNotNil(session.error)
        }
        let state = try keychain.passwordAttemptLimiter(scope: "settings:primary").status()
        XCTAssertEqual(state.failures, 5); XCTAssertNotNil(state.blockedUntil)
        XCTAssertTrue(auth.isAuthenticated); XCTAssertTrue(keychain.verifyPassword("PUBLIC vault password"))
    }

    func testBackupSessionHandoffKeepsOnlyFinishedCiphertextAcrossRevocation() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let keychain = KeychainService(service: "backup-session-" + UUID().uuidString)
        defer { keychain.clearAllKeychainData() }
        _ = try keychain.savePassword("public-owner-password")
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false, documentPreviewService: f.authority)
        defer { auth.logout() }
        auth.password = "public-owner-password"; await (try XCTUnwrap(auth.login())).value
        let request = LibraryMountCoordinator.Request(sessionID: auth.librarySessionID, scope: .legacyOwner)
        await f.mounts.mount(request) { true }
        let note = SecretNote(title: "Public handoff", content: "Only ciphertext may leave")
        f.db.mainContext.insert(note); try LibraryWriteCoordinator.save(f.db.mainContext)
        let session = PortableBackupSession(authority: f.authority)
        session.start(mounts: f.mounts, auth: auth, rootCredential: .password("public backup password"), passwords: [:], consent: [])
        let deadline = Date().addingTimeInterval(30)
        while session.isWorking, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let originalReady = try XCTUnwrap(session.readyURL)
        XCTAssertNil(session.beginHandoff(filename: "../outside"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalReady.path))
        let unowned = originalReady.deletingLastPathComponent().appendingPathComponent("Occupied.tar.age")
        try Data("unowned".utf8).write(to: unowned)
        XCTAssertNil(session.beginHandoff(filename: "Occupied"))
        XCTAssertEqual(try Data(contentsOf: unowned), Data("unowned".utf8))
        try FileManager.default.removeItem(at: unowned)
        let file = try XCTUnwrap(session.beginHandoff(filename: "My backup 2026"), session.error ?? "No finished backup")
        XCTAssertEqual(file.lastPathComponent, "My backup 2026.tar.age")
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalReady.path))
        XCTAssertTrue(try Data(contentsOf: file).starts(with: Data("age-encryption.org/v1".utf8)))
        let folder = file.deletingLastPathComponent()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [file.lastPathComponent])
        f.authority.endSession(matching: auth.librarySessionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        session.finishHandoff()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(note.content, "Only ciphertext may leave")
    }

    func testBackupSessionRevokesOldWorkerAcrossSameSessionResume() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let keychain = KeychainService(service: "backup-revoke-" + UUID().uuidString)
        defer { keychain.clearAllKeychainData() }
        _ = try keychain.savePassword("public-owner-password")
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false, documentPreviewService: f.authority)
        defer { auth.logout() }
        auth.password = "public-owner-password"; await (try XCTUnwrap(auth.login())).value
        let request = LibraryMountCoordinator.Request(sessionID: auth.librarySessionID, scope: .legacyOwner)
        await f.mounts.mount(request) { true }
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: PortableBackupSession.jobRoot.path)) ?? [])
        let session = PortableBackupSession(authority: f.authority)
        session.start(mounts: f.mounts, auth: auth, rootCredential: .password("public backup password"), passwords: [:], consent: [])
        var owned = Set<String>()
        let deadline = Date().addingTimeInterval(30)
        while owned.isEmpty, Date() < deadline {
            owned = Set((try? FileManager.default.contentsOfDirectory(atPath: PortableBackupSession.jobRoot.path)) ?? []).subtracting(before)
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(owned.isEmpty)
        f.authority.endSession(matching: auth.librarySessionID)
        f.authority.beginSession(auth.librarySessionID)
        while owned.contains(where: { FileManager.default.fileExists(atPath: PortableBackupSession.jobRoot.appendingPathComponent($0).path) }), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(session.readyURL)
        XCTAssertFalse(owned.contains { FileManager.default.fileExists(atPath: PortableBackupSession.jobRoot.appendingPathComponent($0).path) })
    }

    func testLargeStreamedBackupFixtureForIndependentRecovery() async throws {
        let f = try Fixture(); defer { f.cleanup() }; await f.begin()
        let plain = f.root.appendingPathComponent("public-stream-source")
        XCTAssertTrue(FileManager.default.createFile(atPath: plain.path, contents: nil))
        let handle = try FileHandle(forWritingTo: plain)
        let chunk = Data((0..<65536).map { UInt8($0 % 251) })
        var hash = SHA256(), size: Int64 = 0
        for _ in 0..<1024 { try handle.write(contentsOf: chunk); hash.update(data: chunk); size += Int64(chunk.count) }
        let tail = Data([9, 8, 7]); try handle.write(contentsOf: tail); hash.update(data: tail); size += 3; try handle.close()
        let encrypted = f.root.appendingPathComponent("public-stream-cipher")
        try EncryptionService.shared.encryptFile(inputURL: plain, to: encrypted, password: "synthetic-vault-key")
        try FileManager.default.removeItem(at: plain)
        let item = MediaItem(fileName: "large fixture", fileExtension: ".bin", fileSize: size, type: .video, encryptedPath: encrypted.path)
        f.db.mainContext.insert(item); try LibraryWriteCoordinator.save(f.db.mainContext)
        let collector = f.collector(), snapshot = try collector.capture(f.request)
        let recipient = "age1zvkyg2lqzraa2lnjvqej32nkuu0ues2s82hzrye869xeexvn73equnujwj"
        let plan = try BackupPlanFactory.make(snapshot: snapshot, rootKey: "synthetic-vault-key", albumStore: f.albums, albums: [], credentials: [.root: .recipient(recipient)])
        let directory = f.root.appendingPathComponent("stream-job")
        let output = try await Task.detached { try BackupArchiveBuilder.build(plan, directory: directory, lease: BackupLease()) }.value
        try collector.validateUnchanged(snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("working-media").path))
        let expected: [String: Any] = ["fixtureOnly": true, "bytes": size, "id": item.id.uuidString,
            "sha256": hash.finalize().map { String(format: "%02x", $0) }.joined(),
            "identity": "AGE-SECRET-KEY-1GFPYYSJZGFPYYSJZGFPYYSJZGFPYYSJZGFPYYSJZGFPYYSJZGFPQ4EGAEX"]
        let archive = XCTAttachment(contentsOfFile: output); archive.name = "public-large-backup.tar.age"; archive.lifetime = .keepAlways; add(archive)
        let details = XCTAttachment(data: try JSONSerialization.data(withJSONObject: expected), uniformTypeIdentifier: "public.json")
        details.name = "public-large-backup-expected.json"; details.lifetime = .keepAlways; add(details)
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
