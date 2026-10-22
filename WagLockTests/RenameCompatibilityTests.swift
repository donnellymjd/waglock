import Foundation
import SwiftData
import XCTest
@testable import WagLock

@MainActor
final class RenameCompatibilityTests: XCTestCase {
    func testPersistedLibrarySurvivesModuleRename() throws {
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        let bundle = Bundle(for: Self.self)
        let fixture = try XCTUnwrap(bundle.url(forResource: "legacy-model", withExtension: "sqlite"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("model.store")
        try FileManager.default.copyItem(at: fixture, to: file)
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: file)])
        let context = ModelContext(store)
        let media = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(media.count, 1)
        let item = try XCTUnwrap(media.first)
        XCTAssertEqual(Array(item.fileName.utf8), Array("家族–café".utf8))
        XCTAssertEqual(item.encryptedPath, "retained-original-ciphertext.encrypted")
        XCTAssertEqual(item.thumbnailData, Data([10, 20, 30]))
        XCTAssertEqual(item.width, 1080)
        XCTAssertEqual(item.height, 1920)
        XCTAssertEqual(item.duration, 4.5)
        let notes = try context.fetch(FetchDescriptor<SecretNote>())
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.content, "Unicode: café 家族")
        XCTAssertEqual(notes.first?.tags, ["fixture"])
        let albums = try context.fetch(FetchDescriptor<VaultAlbum>())
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums.first?.wrappedKey, Data([40, 50]))
        XCTAssertEqual(albums.first?.encryptedCatalog, Data([60, 70]))
        item.fileSize = 5678
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MediaItem>()), 1)
    }
}
