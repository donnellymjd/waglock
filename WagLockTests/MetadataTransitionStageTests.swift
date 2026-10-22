import CryptoKit
import Foundation
import SQLite3
import SwiftData
import XCTest
@testable import WagLock

@MainActor
final class MetadataTransitionStageTests: XCTestCase {
    private typealias Store = EncryptedMetadataStore
    private typealias Stage = MetadataTransitionStage
    private var parents: [URL] = []
    override func tearDown() { for root in parents { try? FileManager.default.removeItem(at: root) }; parents = [] }
    private func root() throws -> URL {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("stage-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false); parents.append(parent)
        return parent.appendingPathComponent("staged")
    }
    private func key() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }
    private func domain() -> Store.Domain { .init(libraryID: UUID(), vaultID: UUID()) }
    private func fixture(count: Int = 3) throws -> ModelContainer {
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext; context.autosaveEnabled = false
        let date = Date(timeIntervalSinceReferenceDate: 12345.125)
        if count == 3 {
            let media = MediaItem(fileName: "family cafe\u{301} 家族", fileExtension: ".mov", fileSize: 123456789,
                type: .video, encryptedPath: "untouched-original.enc", thumbnailData: Data([0, 1, 255]),
                createdAt: date, modifiedAt: date.addingTimeInterval(99), width: 1920, height: 1080, duration: 25.625)
            media.typeRawValue = "future-media-value"
            let note = SecretNote(title: "café", content: "# cafe\u{301}\n秘密", isFavorite: true, tags: ["café", "cafe\u{301}", ""])
            note.createdAt = date; note.modifiedAt = date.addingTimeInterval(4)
            let album = VaultAlbum(parentID: UUID(), name: "private cafe\u{301}", protection: .passwordAndFaceID,
                wrappedKey: Data([7, 0, 9]), encryptedCatalog: Data([4, 0, 5]), biometricAccount: "retained-synthetic-account")
            album.protectionRawValue = "future-policy-value"; album.createdAt = date
            context.insert(media); context.insert(note); context.insert(album)
        } else {
            for index in 0..<count { context.insert(SecretNote(title: "public-fixture-\(index)", content: "body-\(index)")) }
        }
        try context.save(); return container
    }
    private func capture(_ container: ModelContainer) throws -> [Store.Record] {
        try MetadataModelCodec.capture(container.mainContext, authorized: { true })
    }

    func testEveryModelFieldRoundTripsThroughMemoryProjectionWithoutSourceMutation() throws {
        let source = try fixture(), snapshot = try capture(source)
        let destination = try root(), domain = domain(), key = key()
        _ = try Stage.run(mode: .create, root: destination, domain: domain, key: key, sourceID: UUID(), records: snapshot, authorized: { true })
        let store = try Store.open(at: destination, domain: domain, key: key), access = store.access()
        let count = try store.state(access).count
        let recovered = try (0..<count).map { try store.page(access, offset: $0, limit: 1).records[0] }.filter { $0.kind != "transition" }
        store.revoke()
        let projected = try MetadataModelCodec.memoryProjection(recovered, authorized: { true })
        XCTAssertTrue(projected.configurations.allSatisfy(\.isStoredInMemoryOnly))
        XCTAssertEqual(try capture(projected), snapshot)
        XCTAssertEqual(try capture(source), snapshot); XCTAssertFalse(source.mainContext.hasChanges)
        let original = try source.mainContext.fetch(FetchDescriptor<MediaItem>())[0]
        XCTAssertEqual(original.encryptedPath, "untouched-original.enc")
        let read = try projected.mainContext.fetch(FetchDescriptor<MediaItem>())[0]
        XCTAssertEqual(Data(read.fileName.utf8), Data(original.fileName.utf8))
    }
    func testDiskBackedCaptureIncludesCommittedWALWithoutCopyingOrChangingSource() throws {
        let destination = try root(), sourceURL = destination.deletingLastPathComponent().appendingPathComponent("source.sqlite")
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        let source = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: sourceURL, cloudKitDatabase: .none))
        let context = source.mainContext; context.autosaveEnabled = false
        let marker = "public-uncheckpointed-note-" + UUID().uuidString
        let note = SecretNote(title: marker, content: "# WAL fixture"); context.insert(note); try context.save()
        let wal = URL(fileURLWithPath: sourceURL.path + "-wal")
        let beforeDB = try Data(contentsOf: sourceURL), beforeWAL = try Data(contentsOf: wal)
        // Establish that this fixture actually depends on committed WAL content.
        XCTAssertNil(beforeDB.range(of: Data(marker.utf8)))
        XCTAssertNotNil(beforeWAL.range(of: Data(marker.utf8)))
        let records = try capture(source)
        XCTAssertEqual(records.count, 1)
        guard case .note(let decoded) = try MetadataModelCodec.decode(records[0]) else { return XCTFail("Expected note") }
        XCTAssertEqual(decoded.id, note.id); XCTAssertEqual(Data(decoded.title.utf8), Data(marker.utf8))
        _ = try Stage.run(mode: .create, root: destination, domain: domain(), key: key(), sourceID: UUID(), records: records, authorized: { true })
        XCTAssertEqual(try Data(contentsOf: sourceURL), beforeDB)
        XCTAssertEqual(try Data(contentsOf: wal), beforeWAL)
        XCTAssertEqual(try capture(source), records); XCTAssertFalse(context.hasChanges)
    }
    func testCaptureRejectsDirtyUnauthorizedAndUnsupportedSchemasWithoutSaving() throws {
        let source = try fixture()
        XCTAssertThrowsError(try MetadataModelCodec.capture(source.mainContext, authorized: { false }))
        source.mainContext.insert(SecretNote(title: "unsaved"))
        XCTAssertThrowsError(try capture(source)); XCTAssertTrue(source.mainContext.hasChanges)
        let schema = Schema([SecretNote.self])
        let unsupported = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        XCTAssertThrowsError(try capture(unsupported))
        XCTAssertThrowsError(try MetadataModelCodec.memoryProjection([], authorized: { false }))
    }
    func testUnknownFieldsVersionsIdentityKindsAndMalformedPayloadsAreRejected() throws {
        let source = try fixture(), record = try capture(source).first!
        var object = try JSONSerialization.jsonObject(with: record.payload) as! [String: Any]
        object["futureField"] = "preserve or refuse"
        let unknown = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertThrowsError(try MetadataModelCodec.decode(.init(kind: record.kind, id: record.id, payload: unknown)))
        object.removeValue(forKey: "futureField"); object["version"] = 99
        let version = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertThrowsError(try MetadataModelCodec.decode(.init(kind: record.kind, id: record.id, payload: version)))
        XCTAssertThrowsError(try MetadataModelCodec.decode(.init(kind: record.kind, id: UUID(), payload: record.payload)))
        XCTAssertThrowsError(try MetadataModelCodec.decode(.init(kind: "draft", id: record.id, payload: record.payload)))
        XCTAssertThrowsError(try MetadataModelCodec.decode(.init(kind: record.kind, id: record.id, payload: Data([1, 2]))))
        XCTAssertThrowsError(try MetadataModelCodec.memoryProjection([record, record], authorized: { true }))
    }
    func testInterruptedBatchesResumeOnlyAgainstSameSourceAndVerifyExactInventory() throws {
        let source = try fixture(count: 260), original = try capture(source)
        let records = original + [Store.Record(kind: "retained-key", id: UUID(), payload: Data("public-retained-secret".utf8))]
        let root = try root(), domain = domain(), key = key(), sourceID = UUID()
        XCTAssertThrowsError(try Stage.run(mode: .create, root: root, domain: domain, key: key, sourceID: sourceID,
            records: records, authorized: { true }) { point in
                if case .batchCommitted(127) = point { throw CocoaError(.fileWriteOutOfSpace) }
            })
        let stored = try Store.open(at: root, domain: domain, key: key)
        XCTAssertEqual(try stored.state(stored.access()).count, 128); stored.revoke()
        XCTAssertThrowsError(try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: UUID(), records: records, authorized: { true }))
        XCTAssertThrowsError(try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: sourceID, records: Array(records.dropLast()), authorized: { true }))
        let result = try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: sourceID, records: records.reversed(), authorized: { true })
        XCTAssertEqual(result.completed, 261)
        let again = try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: sourceID, records: records, authorized: { true })
        XCTAssertEqual(again.revision, result.revision)
        let reopened = try Store.open(at: root, domain: domain, key: key); defer { reopened.revoke() }
        try reopened.verifyAll(reopened.access())
        XCTAssertEqual(try reopened.state(reopened.access()).count, records.count + 1)
        XCTAssertEqual(try capture(source), original); XCTAssertFalse(source.mainContext.hasChanges)
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: file), marker = Data("public-retained-secret".utf8)
            XCTAssertNil(bytes.range(of: marker)); XCTAssertNil(bytes.range(of: Data(marker.base64EncodedString().utf8)))
        }
    }
    func testRevocationAfterCommittedBatchPreservesResumableProgress() throws {
        let source = try fixture(count: 130), records = try capture(source)
        let root = try root(), domain = domain(), key = key(), sourceID = UUID()
        var authorized = true
        XCTAssertThrowsError(try Stage.run(mode: .create, root: root, domain: domain, key: key, sourceID: sourceID,
            records: records, authorized: { authorized }) { point in
                if case .batchCommitted = point { authorized = false }
            })
        authorized = true
        let result = try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: sourceID, records: records, authorized: { authorized })
        XCTAssertEqual(result.completed, records.count)
    }
    func testEditedStagedPrefixCannotBeAcceptedAsSourceOrOverwrittenOnResume() throws {
        let records = try capture(fixture(count: 130)), root = try root(), domain = domain(), key = key(), sourceID = UUID()
        XCTAssertThrowsError(try Stage.run(mode: .create, root: root, domain: domain, key: key, sourceID: sourceID,
            records: records, authorized: { true }) { point in
                if case .batchCommitted = point { throw CocoaError(.fileWriteUnknown) }
            })
        let store = try Store.open(at: root, domain: domain, key: key), access = store.access()
        let before = try store.state(access)
        let target = records[0]
        try store.apply(access, revision: before.revision, mutations: [.put(.init(kind: target.kind, id: target.id, payload: Data("changed".utf8)))])
        store.revoke()
        XCTAssertThrowsError(try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: sourceID, records: records, authorized: { true }))
        let reopened = try Store.open(at: root, domain: domain, key: key); defer { reopened.revoke() }
        XCTAssertEqual(try reopened.state(reopened.access()).revision, before.revision + 1)
    }
    func testWrongKeysDomainsOccupiedDestinationsAndInvalidSourceDoNotResetStages() throws {
        let records = try capture(fixture()), root = try root(), domain = domain(), key = key(), sourceID = UUID()
        let first = try Stage.run(mode: .create, root: root, domain: domain, key: key, sourceID: sourceID, records: records, authorized: { true })
        XCTAssertThrowsError(try Stage.run(mode: .create, root: root, domain: domain, key: key, sourceID: sourceID, records: records, authorized: { true }))
        XCTAssertThrowsError(try Stage.run(mode: .resume, root: root, domain: domain, key: self.key(), sourceID: sourceID, records: records, authorized: { true }))
        XCTAssertThrowsError(try Stage.run(mode: .resume, root: root, domain: self.domain(), key: key, sourceID: sourceID, records: records, authorized: { true }))
        let again = try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: sourceID, records: records, authorized: { true })
        XCTAssertEqual(first.revision, again.revision)
        let missing = try self.root()
        XCTAssertThrowsError(try Stage.run(mode: .create, root: missing, domain: domain, key: key, sourceID: sourceID, records: records + records, authorized: { true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }
    func testLostCompletionResultCanBeReconciledWithoutDeletingVerifiedStage() throws {
        let records = try capture(fixture()), root = try root(), domain = domain(), key = key(), sourceID = UUID()
        XCTAssertThrowsError(try Stage.run(mode: .create, root: root, domain: domain, key: key, sourceID: sourceID,
            records: records, authorized: { true }) { point in
                if case .verified = point { throw CocoaError(.fileWriteUnknown) }
            })
        XCTAssertEqual(try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: sourceID, records: records, authorized: { true }).completed, records.count)
    }
    func testEmptySourceStillCreatesVerifiedResumableInventory() throws {
        let root = try root(), domain = domain(), key = key(), sourceID = UUID()
        let first = try Stage.run(mode: .create, root: root, domain: domain, key: key, sourceID: sourceID, records: [], authorized: { true })
        XCTAssertEqual(first.completed, 0)
        XCTAssertEqual(try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: sourceID, records: [], authorized: { true }).revision, first.revision)
    }
}
