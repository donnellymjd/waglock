import CryptoKit
import Foundation
import Security
import SwiftData
import XCTest
@testable import WagLock

@MainActor
final class MetadataDraftCodecTests: XCTestCase {
    private typealias Codec = MetadataDraftCodec
    private typealias Stage = MetadataTransitionStage
    private var roots: [URL] = []
    private var suites: [String] = []
    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        roots = []; suites = []
    }
    private func defaults() throws -> UserDefaults {
        let suite = "metadata-drafts-" + UUID().uuidString; suites.append(suite)
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }
    private func root() throws -> URL {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("draft-stage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false); roots.append(parent)
        return parent.appendingPathComponent("stage")
    }
    private func raw(_ title: String) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted]
        return try encoder.encode(SecretNoteDraft(title: title, content: "# cafe\u{301} 家族", updatedAt: Date(timeIntervalSinceReferenceDate: 123.125)))
    }
    private func key() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }
    private func domain() -> EncryptedMetadataStore.Domain { .init(libraryID: UUID(), vaultID: UUID()) }

    func testBothSourcesAndOriginalSerializedBytesArePreservedWithoutWrites() throws {
        let storage = Storage(), preferences = try defaults()
        let keychain = KeychainService(service: "public-draft-codec-fixture", storage: storage)
        let first = try raw("keychain cafe\u{301}"), second = try raw("legacy café")
        storage.items["secretNoteDraft"] = first; preferences.set(second, forKey: "secretSpace.draft")
        preferences.set("keep unrelated value", forKey: "sentinel")
        let records = try Codec.capture(keychain: keychain, defaults: preferences, authorized: { true })
        XCTAssertEqual(records.count, 2)
        let entries = try records.map(Codec.decode)
        XCTAssertEqual(entries.map(\.origin), [.keychain, .legacyPreferences])
        XCTAssertEqual(entries.map(\.serialized), [first, second]); XCTAssertTrue(entries.allSatisfy(\.present))
        XCTAssertEqual(Data(try Codec.value(first).title.utf8), Data("keychain cafe\u{301}".utf8))
        XCTAssertEqual(storage.items["secretNoteDraft"], first); XCTAssertEqual(preferences.data(forKey: "secretSpace.draft"), second)
        XCTAssertEqual(preferences.string(forKey: "sentinel"), "keep unrelated value")
        XCTAssertEqual(storage.writes, 0); XCTAssertEqual(storage.deletes, 0)
    }
    func testAbsentDraftsAreExplicitWhileUnavailableSourceIsNotTreatedAsEmpty() throws {
        let storage = Storage(), preferences = try defaults(), keychain = KeychainService(service: "public-absent-drafts", storage: storage)
        let absent = try Codec.capture(keychain: keychain, defaults: preferences, authorized: { true })
        XCTAssertEqual(absent.count, 2)
        for record in absent { let entry = try Codec.decode(record); XCTAssertFalse(entry.present); XCTAssertNil(entry.serialized) }
        storage.failReads = true
        XCTAssertThrowsError(try Codec.capture(keychain: keychain, defaults: preferences, authorized: { true }))
        XCTAssertEqual(storage.writes, 0); XCTAssertEqual(storage.deletes, 0)
    }
    func testCorruptWrongTypeAndFutureDraftFieldsRemainInSourceAndBlockCapture() throws {
        let storage = Storage(), preferences = try defaults(), keychain = KeychainService(service: "public-invalid-drafts", storage: storage)
        for invalid: Any in ["wrong storage type", Data("bad JSON".utf8)] {
            preferences.set(invalid, forKey: "secretSpace.draft")
            XCTAssertThrowsError(try Codec.capture(keychain: keychain, defaults: preferences, authorized: { true }))
            XCTAssertNotNil(preferences.object(forKey: "secretSpace.draft"))
        }
        var object = try JSONSerialization.jsonObject(with: raw("future draft")) as! [String: Any]
        object["attachment"] = "must not disappear"
        let future = try JSONSerialization.data(withJSONObject: object)
        storage.items["secretNoteDraft"] = future
        XCTAssertThrowsError(try Codec.capture(keychain: keychain, defaults: preferences, authorized: { true }))
        XCTAssertEqual(storage.items["secretNoteDraft"], future)
    }
    func testRevocationBeforeOrDuringReadNeverReturnsDrafts() throws {
        var reads = 0, allowed = false
        XCTAssertThrowsError(try Codec.capture(read: { _ in reads += 1; return nil }, authorized: { allowed }))
        XCTAssertEqual(reads, 0)
        allowed = true
        XCTAssertThrowsError(try Codec.capture(read: { _ in reads += 1; allowed = false; return try self.raw("private fixture") }, authorized: { allowed }))
        XCTAssertEqual(reads, 1)
    }
    func testCancelledCaptureDoesNotReadAnySource() async throws {
        var reads = 0
        let task = Task { try Codec.capture(read: { _ in reads += 1; return nil }, authorized: { true }) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled capture returned a snapshot") }
        catch is CancellationError { }
        XCTAssertEqual(reads, 0)
    }
    func testEnvelopeVersionIdentityExtraFieldsAndOversizedRawDataFailClosed() throws {
        let row = try Codec.capture(read: { _ in nil }, authorized: { true })[0]
        var object = try JSONSerialization.jsonObject(with: row.payload) as! [String: Any]
        object["version"] = 2
        XCTAssertThrowsError(try Codec.decode(.init(kind: row.kind, id: row.id, payload: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))))
        object["version"] = 1; object["future"] = "keep"
        XCTAssertThrowsError(try Codec.decode(.init(kind: row.kind, id: row.id, payload: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))))
        XCTAssertThrowsError(try Codec.decode(.init(kind: row.kind, id: UUID(), payload: row.payload)))
        XCTAssertThrowsError(try Codec.capture(read: { _ in Data(repeating: 0, count: Codec.maximumDraftBytes + 1) }, authorized: { true }))
    }
    func testInterruptedDraftStageResumesWithBothOriginsAndRejectsChangedBytes() throws {
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        let source = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        source.mainContext.autosaveEnabled = false
        for index in 0..<130 { source.mainContext.insert(SecretNote(title: "public-note-\(index)")) }; try source.mainContext.save()
        let models = try MetadataModelCodec.capture(source.mainContext, authorized: { true })
        let serialized = try raw("preserved public draft")
        let drafts = try Codec.capture(read: { $0 == .keychain ? serialized : nil }, authorized: { true })
        let records = models + drafts, root = try root(), domain = domain(), key = key(), sourceID = UUID()
        XCTAssertThrowsError(try Stage.run(mode: .create, root: root, domain: domain, key: key, sourceID: sourceID,
            records: records, scope: .modelsAndDrafts, authorized: { true }) { point in
                if case .batchCommitted = point { throw CocoaError(.fileWriteOutOfSpace) }
            })
        let changed = try Codec.capture(read: { $0 == .keychain ? try self.raw("changed public draft") : nil }, authorized: { true })
        XCTAssertThrowsError(try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: sourceID, records: models + changed, scope: .modelsAndDrafts, authorized: { true }))
        let result = try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: sourceID, records: records, scope: .modelsAndDrafts, authorized: { true })
        XCTAssertEqual(result.completed, 132)
        let store = try EncryptedMetadataStore.open(at: root, domain: domain, key: key); defer { store.revoke() }
        let access = store.access(), state = try store.state(access)
        let recovered = try (0..<state.count).map { try store.page(access, offset: $0, limit: 1, revision: state.revision).records[0] }.filter { $0.kind == "draft" }
        let entries = try recovered.map(Codec.decode)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first { $0.origin == .keychain }?.serialized, serialized)
        XCTAssertFalse(try XCTUnwrap(entries.first { $0.origin == .legacyPreferences }).present)
        XCTAssertEqual(try MetadataModelCodec.capture(source.mainContext, authorized: { true }), models)
    }
    func testScopeCannotSilentlyOmitDraftSourcesOrUpgradeExistingStage() throws {
        let drafts = try Codec.capture(read: { _ in nil }, authorized: { true })
        let root = try root(), domain = domain(), key = key(), sourceID = UUID()
        XCTAssertThrowsError(try Stage.run(mode: .create, root: root, domain: domain, key: key, sourceID: sourceID, records: drafts, authorized: { true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertThrowsError(try Stage.run(mode: .create, root: root, domain: domain, key: key, sourceID: sourceID, records: [drafts[0]], scope: .modelsAndDrafts, authorized: { true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        _ = try Stage.run(mode: .create, root: root, domain: domain, key: key, sourceID: sourceID, records: [], authorized: { true })
        XCTAssertThrowsError(try Stage.run(mode: .resume, root: root, domain: domain, key: key, sourceID: sourceID, records: drafts, scope: .modelsAndDrafts, authorized: { true }))
        XCTAssertThrowsError(try MetadataModelCodec.memoryProjection(drafts, authorized: { true }))
    }

    private final class Storage: KeychainStorage {
        nonisolated deinit { }
        var items: [String: Data] = [:]
        var failReads = false, writes = 0, deletes = 0
        func read(account: String) throws -> Data {
            if failReads { throw KeychainError.unexpectedStatus(errSecInteractionNotAllowed) }
            guard let data = items[account] else { throw KeychainError.itemNotFound }; return data
        }
        func write(account: String, data: Data, createOnly: Bool) throws { writes += 1; items[account] = data }
        func delete(account: String) throws { deletes += 1; items.removeValue(forKey: account) }
    }
}
