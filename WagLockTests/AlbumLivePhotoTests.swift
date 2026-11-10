import Foundation
import SwiftData
import Testing
import UIKit

@testable import WagLock

@MainActor
private final class NoBiometrics: BiometricSecretStoring {
    func store(_ secret: String, account: String) async throws {}
    func read(account: String, reason: String) async throws -> String { throw VaultAccessError.locked }
    func remove(account: String) {}
}

/// Disposable albums and files only.
@MainActor
struct AlbumLivePhotoTests {
    private func fixture() async throws -> (AlbumStore, VaultAlbum, ModelContainer, FileStorageService, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("album-live-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storage = FileStorageService(directory: root.appendingPathComponent("media"), availableCapacity: { _ in 1_000_000_000 })
        let db = try ModelContainer(for: VaultAlbum.self, MediaItem.self, SecretNote.self,
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AlbumStore(biometrics: NoBiometrics(), attemptStorage: InMemoryAttemptStorage(), storage: storage)
        store.beginSession(vaultSecret: "PUBLIC album live root")
        let album = try await store.create(name: "Trips", parent: nil, protection: .inherited, password: "",
                                           albums: [], context: db.mainContext)
        return (store, album, db, storage, root)
    }

    private func write(_ root: URL, _ name: String, _ data: Data) throws -> URL {
        let url = root.appendingPathComponent(name); try data.write(to: url); return url
    }

    private func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    @Test
    func linkedPairShowsOncePlaysFromBothFilesAndDeletesTogether() async throws {
        let (store, album, db, storage, root) = try await fixture()
        defer { store.endSession(); try? FileManager.default.removeItem(at: root) }
        let still = try await store.importFile(try write(root, "IMG_1.PNG", png()), into: album, albums: [album], context: db.mainContext)
        let motion = try await store.importFile(try write(root, "IMG_1.MOV", Data(repeating: 9, count: 2048)),
                                                into: album, albums: [album], context: db.mainContext)
        try store.linkLivePhoto(still: still.id, motion: motion.id, in: album, albums: [album], context: db.mainContext)

        let catalog = try store.assets(in: album, albums: [album])
        #expect(AlbumStore.motionIDs(in: catalog) == [motion.id])
        let linked = try #require(catalog.first { $0.id == still.id })
        #expect(linked.livePhotoMotionID == motion.id)

        let pair = try await store.previewLivePhoto(linked, in: album, albums: [album])
        #expect(try Data(contentsOf: pair.motion) == Data(repeating: 9, count: 2048))
        for url in [pair.still, pair.motion] { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try store.delete(linked, from: album, albums: [album], context: db.mainContext)
        #expect(try store.assets(in: album, albums: [album]).isEmpty)
        #expect(!storage.fileExists(path: still.encryptedPath))
        #expect(!storage.fileExists(path: motion.encryptedPath))
    }

    @Test
    func linksMustPointFromAPhotoToAnUnclaimedVideo() async throws {
        let (store, album, db, _, root) = try await fixture()
        defer { store.endSession(); try? FileManager.default.removeItem(at: root) }
        let still = try await store.importFile(try write(root, "a.PNG", png()), into: album, albums: [album], context: db.mainContext)
        let other = try await store.importFile(try write(root, "b.PNG", png()), into: album, albums: [album], context: db.mainContext)
        let motion = try await store.importFile(try write(root, "a.MOV", Data(count: 64)), into: album, albums: [album], context: db.mainContext)
        #expect(throws: (any Error).self) {
            try store.linkLivePhoto(still: still.id, motion: other.id, in: album, albums: [album], context: db.mainContext)
        }
        try store.linkLivePhoto(still: still.id, motion: motion.id, in: album, albums: [album], context: db.mainContext)
        #expect(throws: (any Error).self) {
            try store.linkLivePhoto(still: other.id, motion: motion.id, in: album, albums: [album], context: db.mainContext)
        }
    }

    @Test
    func catalogsWrittenBeforeLivePhotosStillDecode() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","fileName":"x.png","encryptedPath":"p","fileSize":1,"type":"photo","createdAt":0}]"#
        let assets = try JSONDecoder().decode([AlbumAsset].self, from: Data(json.utf8))
        #expect(assets.first?.livePhotoMotionID == nil)
    }

    @Test
    func photoBrowserPairsAreLinkedOrNotKeptAtAll() async throws {
        let (store, album, db, _, root) = try await fixture()
        defer { store.endSession(); try? FileManager.default.removeItem(at: root) }
        let pair = try await store.importPair(still: try write(root, "IMG_2.PNG", png()),
                                              motion: try write(root, "IMG_2.MOV", Data(repeating: 4, count: 512)),
                                              into: album, albums: [album], context: db.mainContext)
        let catalog = try store.assets(in: album, albums: [album])
        #expect(catalog.count == 2)
        #expect(pair.livePhotoMotionID != nil)
        #expect(AlbumStore.motionIDs(in: catalog) == [try #require(pair.livePhotoMotionID)])

        // The motion can't be read: the still must not stay behind on its own.
        let missing = root.appendingPathComponent("gone.MOV")
        await #expect(throws: (any Error).self) {
            try await store.importPair(still: try write(root, "IMG_3.PNG", png()), motion: missing,
                                       into: album, albums: [album], context: db.mainContext)
        }
        #expect(try store.assets(in: album, albums: [album]).count == 2)

        let single = try await store.importPair(still: try write(root, "IMG_4.PNG", png()), motion: nil,
                                                into: album, albums: [album], context: db.mainContext)
        #expect(single.livePhotoMotionID == nil)
    }
}
