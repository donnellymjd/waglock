import CryptoKit
import Foundation
import SQLite3
import SwiftData
import XCTest
@testable import WagLock

@MainActor
final class EncryptedMetadataStoreTests: XCTestCase {
    private typealias Store = EncryptedMetadataStore
    private var roots: [URL] = []
    override func tearDown() { for root in roots { try? FileManager.default.removeItem(at: root) }; roots = [] }
    private func parent() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("encrypted-metadata-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false); roots.append(url); return url
    }
    private func key() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }
    private func domain() -> Store.Domain { .init(libraryID: UUID(), vaultID: UUID()) }
    private func record(_ text: String = "private fixture 家族 cafe\u{301}", id: UUID = UUID()) -> Store.Record {
        .init(kind: "note", id: id, payload: Data(text.utf8))
    }
    private func sql(_ root: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(root.appendingPathComponent("metadata.sqlite").path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { throw Store.Failure.storage }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw Store.Failure.storage }
    }
    private func all(_ store: Store) throws -> [Store.Record] {
        let access = store.access(), state = try store.state(access)
        return try stride(from: 0, to: state.count, by: 128).flatMap { try store.page(access, offset: $0, limit: 128, revision: state.revision).records }
    }

    func testFreshReopenAtomicUpdatesDeletesAndExactUnicodeBytes() throws {
        let root = try parent().appendingPathComponent("index"), domain = domain(), key = key()
        let store = try Store.create(at: root, domain: domain, key: key), access = store.access()
        let a = record(), b = record("second")
        let one = try store.apply(access, revision: 0, mutations: [.put(a), .put(b)])
        XCTAssertEqual(one.count, 2); XCTAssertEqual(one.revision, 1)
        let changed = record("replacement café", id: a.id)
        let two = try store.apply(access, revision: 1, mutations: [.put(changed), .remove(kind: b.kind, id: b.id)])
        XCTAssertEqual(two.count, 1)
        store.revoke()
        let reopened = try Store.open(at: root, domain: domain, key: key)
        XCTAssertEqual(try all(reopened), [changed]); try reopened.verifyAll(reopened.access())
        XCTAssertEqual(try all(reopened)[0].payload, changed.payload)
    }
    func testPagedReadsDecodeOnlyRequestedRecords() throws {
        let root = try parent().appendingPathComponent("index")
        let store = try Store.create(at: root, domain: domain(), key: key()), access = store.access()
        let records = (0..<1000).map { record("record-\($0)") }
        var revision: UInt64 = 0
        for start in stride(from: 0, to: records.count, by: 100) {
            revision = try store.apply(access, revision: revision, mutations: records[start..<min(start + 100, records.count)].map(Store.Mutation.put)).revision
        }
        XCTAssertEqual(store.decodedRecords, 0)
        let page = try store.page(access, offset: 400, limit: 32, revision: revision)
        XCTAssertEqual(page.records.count, 32); XCTAssertEqual(store.decodedRecords, 32)
        try store.verifyAll(access); XCTAssertEqual(store.decodedRecords, 32)
        XCTAssertThrowsError(try store.page(access, offset: -1, limit: 32))
        XCTAssertThrowsError(try store.page(access, offset: 0, limit: Int.max))
    }
    func testWrongKeyLibraryVaultAndForeignOrRevokedAccessFailClosed() throws {
        let root = try parent().appendingPathComponent("index"), domain = domain(), key = key()
        let store = try Store.create(at: root, domain: domain, key: key), old = store.access()
        try store.apply(old, revision: 0, mutations: [.put(record())])
        XCTAssertThrowsError(try Store.open(at: root, domain: domain, key: self.key()))
        XCTAssertThrowsError(try Store.open(at: root, domain: .init(libraryID: UUID(), vaultID: domain.vaultID), key: key))
        XCTAssertThrowsError(try Store.open(at: root, domain: .init(libraryID: domain.libraryID, vaultID: UUID()), key: key))
        let second = try Store.open(at: root, domain: domain, key: key)
        XCTAssertThrowsError(try second.state(old))
        store.revoke(); XCTAssertThrowsError(try store.state(old)); XCTAssertThrowsError(try store.state(store.access()))
        XCTAssertEqual(try second.state(second.access()).count, 1)
    }
    func testConcurrentHandlesRejectStaleRevisionsAndPages() throws {
        let root = try parent().appendingPathComponent("index"), domain = domain(), key = key()
        let a = try Store.create(at: root, domain: domain, key: key), aa = a.access()
        let b = try Store.open(at: root, domain: domain, key: key), ba = b.access()
        try a.apply(aa, revision: 0, mutations: [.put(record("first"))])
        XCTAssertThrowsError(try b.apply(ba, revision: 0, mutations: [.put(record("stale"))]))
        XCTAssertThrowsError(try b.page(ba, offset: 0, limit: 32, revision: 0))
        XCTAssertEqual(try b.state(ba).count, 1)
    }
    func testPrecommitFailuresRollbackAllRowsAndAuthenticatedInventory() throws {
        for stage in 0..<2 {
            let root = try parent().appendingPathComponent("index"), domain = domain(), key = key()
            let store = try Store.create(at: root, domain: domain, key: key), access = store.access(), original = record("original")
            try store.apply(access, revision: 0, mutations: [.put(original)])
            XCTAssertThrowsError(try store.apply(access, revision: 1, mutations: [.put(record("new")), .remove(kind: original.kind, id: original.id)]) { point in
                if stage == 0, case .afterRecords = point { throw CocoaError(.fileWriteOutOfSpace) }
                if stage == 1, case .beforeCommit = point { throw CocoaError(.fileWriteOutOfSpace) }
            })
            XCTAssertEqual(try all(store), [original]); try store.verifyAll(access)
            XCTAssertEqual(try store.state(access).revision, 1)
        }
    }
    func testPostcommitErrorIsUncertainAndCommittedRowsArePreserved() throws {
        let root = try parent().appendingPathComponent("index"), domain = domain(), key = key()
        let store = try Store.create(at: root, domain: domain, key: key), access = store.access(), value = record()
        XCTAssertThrowsError(try store.apply(access, revision: 0, mutations: [.put(value)]) { point in
            if case .afterCommit = point { throw CocoaError(.fileWriteUnknown) }
        }) { XCTAssertTrue($0 as? Store.Failure == .uncertainCommit) }
        XCTAssertThrowsError(try store.state(access))
        let reopened = try Store.open(at: root, domain: domain, key: key)
        XCTAssertEqual(try all(reopened), [value]); try reopened.verifyAll(reopened.access())
    }
    func testRevocationDuringCommitRollsBackWithoutUsingClosedConnection() throws {
        let root = try parent().appendingPathComponent("index"), domain = domain(), key = key()
        let store = try Store.create(at: root, domain: domain, key: key), access = store.access()
        XCTAssertThrowsError(try store.apply(access, revision: 0, mutations: [.put(record())]) { point in
            if case .beforeCommit = point { store.revoke() }
        })
        let reopened = try Store.open(at: root, domain: domain, key: key)
        XCTAssertEqual(try reopened.state(reopened.access()).count, 0)
    }
    func testTamperDeletionSubstitutionAndBucketDamageReject() throws {
        for mutation in ["DELETE FROM records WHERE token=(SELECT token FROM records LIMIT 1)",
                         "UPDATE records SET body=x'00010203' WHERE token=(SELECT token FROM records LIMIT 1)",
                         "UPDATE records SET body=(SELECT body FROM records ORDER BY token DESC LIMIT 1) WHERE token=(SELECT token FROM records ORDER BY token LIMIT 1)",
                         "UPDATE buckets SET body=x'00010203' WHERE id=0", "UPDATE head SET body=x'00010203'"] {
            let root = try parent().appendingPathComponent("index"), domain = domain(), key = key()
            let store = try Store.create(at: root, domain: domain, key: key), access = store.access()
            try store.apply(access, revision: 0, mutations: [.put(record("a")), .put(record("b"))])
            store.revoke(); try sql(root, mutation)
            XCTAssertThrowsError(try { let opened = try Store.open(at: root, domain: domain, key: key); try opened.verifyAll(opened.access()) }())
        }
    }
    func testCorruptRecordCannotBeSilentlyReplacedByAnOrdinaryUpdate() throws {
        let root = try parent().appendingPathComponent("index"), domain = domain(), key = key()
        let store = try Store.create(at: root, domain: domain, key: key), access = store.access(), value = record()
        try store.apply(access, revision: 0, mutations: [.put(value)])
        try sql(root, "UPDATE records SET body=x'00010203'")
        XCTAssertThrowsError(try store.apply(access, revision: 1, mutations: [.put(record("new", id: value.id))]))
        XCTAssertEqual(try store.state(access).revision, 1)
        XCTAssertThrowsError(try store.verifyAll(access))
    }

    func testNoFixturePlaintextInDatabaseOrLiveRollbackJournal() throws {
        let parent = try parent(), root = parent.appendingPathComponent("index")
        let store = try Store.create(at: root, domain: domain(), key: key()), access = store.access()
        let secret = "private-filename-thumbnail-note-" + UUID().uuidString
        func scan() throws {
            for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                let bytes = try Data(contentsOf: file)
                XCTAssertNil(bytes.range(of: Data(secret.utf8)))
                XCTAssertNil(bytes.range(of: Data(Data(secret.utf8).base64EncodedString().utf8)))
            }
        }
        try store.apply(access, revision: 0, mutations: [.put(record(secret))]) { point in
            if case .beforeCommit = point { try scan() }
        }
        try scan()
    }
    func testExistingRootsSymlinksAndUnknownSchemasArePreserved() throws {
        let parent = try parent(), occupied = parent.appendingPathComponent("occupied")
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: false)
        let sentinel = occupied.appendingPathComponent("keep"); try Data("owned elsewhere".utf8).write(to: sentinel)
        XCTAssertThrowsError(try Store.create(at: occupied, domain: domain(), key: key()))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("owned elsewhere".utf8))
        let linked = parent.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: occupied)
        XCTAssertThrowsError(try Store.create(at: linked.appendingPathComponent("index"), domain: domain(), key: key()))
        let root = parent.appendingPathComponent("index"), domain = domain(), key = key()
        let store = try Store.create(at: root, domain: domain, key: key); store.revoke()
        try sql(root, "PRAGMA user_version=99")
        XCTAssertThrowsError(try Store.open(at: root, domain: domain, key: key))
    }
    func testDuplicateBatchAndMissingDeleteRollbackRatherThanDropContent() throws {
        let root = try parent().appendingPathComponent("index"), store = try Store.create(at: root, domain: domain(), key: key()), access = store.access()
        let value = record()
        XCTAssertThrowsError(try store.apply(access, revision: 0, mutations: [.put(value), .put(value)]))
        XCTAssertEqual(try store.state(access).count, 0)
        XCTAssertThrowsError(try store.apply(access, revision: 0, mutations: [.put(value), .remove(kind: "note", id: UUID())]))
        XCTAssertEqual(try store.state(access).count, 0)
    }
    func testRecordAndPageByteBudgetsFailWithoutChangingTheIndex() throws {
        let root = try parent().appendingPathComponent("index"), store = try Store.create(at: root, domain: domain(), key: key()), access = store.access()
        let large = Store.Record(kind: "note", id: UUID(), payload: Data(count: Store.maximumPayloadBytes + 1))
        XCTAssertThrowsError(try store.apply(access, revision: 0, mutations: [.put(large)]))
        XCTAssertEqual(try store.state(access).count, 0)
        try store.apply(access, revision: 0, mutations: [.put(record(String(repeating: "x", count: 512)))])
        XCTAssertThrowsError(try store.page(access, offset: 0, limit: 32, byteLimit: 128))
        XCTAssertEqual(try store.page(access, offset: 0, limit: 1, byteLimit: 1024).records.count, 1)
        XCTAssertEqual(try store.state(access).revision, 1)
    }

    func testFullLegacyFieldTransitionRehearsalPreservesSourceAndRetainedKey() throws {
        let parent = try parent(), schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        let source = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = source.mainContext; context.autosaveEnabled = false
        let media = MediaItem(fileName: "家族 cafe\u{301}", fileExtension: ".jpg", fileSize: 42, type: .photo,
                              encryptedPath: "unchanged-original-ciphertext", thumbnailData: Data([1, 3, 5]))
        let note = SecretNote(title: "private title", content: "# content", isFavorite: true, tags: ["cafe\u{301}"])
        let album = VaultAlbum(parentID: nil, name: "private album", protection: .password, wrappedKey: Data([8, 9]), encryptedCatalog: Data([4, 5]))
        context.insert(media); context.insert(note); context.insert(album); try context.save()
        let snapshot = try LegacyMetadataTransitionPrototype.capture(context)
        let retainedKey = Data("retained-original-key-fixture".utf8)
        let root = parent.appendingPathComponent("staged-index"), domain = domain(), key = key()
        let store = try Store.create(at: root, domain: domain, key: key), access = store.access()
        let records = snapshot.map { Store.Record(kind: $0.kind, id: $0.id, payload: $0.payload) }
        let keyRecord = Store.Record(kind: "retained-key", id: UUID(), payload: retainedKey)
        try store.apply(access, revision: 0, mutations: (records + [keyRecord]).map(Store.Mutation.put)); try store.verifyAll(access)
        store.revoke()
        let reopened = try Store.open(at: root, domain: domain, key: key)
        let recovered = try all(reopened)
        XCTAssertEqual(Set(recovered.map(\.id)), Set((records + [keyRecord]).map(\.id)))
        for expected in records + [keyRecord] { XCTAssertEqual(recovered.first { $0.id == expected.id }?.payload, expected.payload) }
        XCTAssertEqual(try LegacyMetadataTransitionPrototype.capture(context), snapshot)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(media.encryptedPath, "unchanged-original-ciphertext")
        XCTAssertEqual(album.wrappedKey, Data([8, 9])); XCTAssertEqual(album.encryptedCatalog, Data([4, 5]))
    }
}
