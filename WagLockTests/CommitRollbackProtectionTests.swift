import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import WagLock

@MainActor
final class CommitRollbackProtectionTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDown() { for root in roots { try? FileManager.default.removeItem(at: root) }; roots = [] }
    private func fixture() throws -> (URL, EncryptedMetadataStore.Domain, Data, InMemoryAttemptStorage, KeychainService) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("commit-protection-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); roots.append(root)
        let storage = InMemoryAttemptStorage()
        return (root, .init(libraryID: UUID(), vaultID: UUID()), Data(repeating: 37, count: 32), storage,
                KeychainService(service: UUID().uuidString, storage: storage))
    }
    private func record(_ text: String) -> EncryptedMetadataStore.Record { .init(kind: "note", id: UUID(), payload: Data(text.utf8)) }
    func testWholeCopyRollbackAndSameRevisionDifferentBranchAreRejected() throws {
        let (root, domain, key, _, anchor) = try fixture()
        let index = root.appendingPathComponent("index"), old = root.appendingPathComponent("old")
        let store = try EncryptedMetadataStore.create(at: index, domain: domain, key: key)
        try store.enableRollbackProtection(anchor)
        try FileManager.default.copyItem(at: index, to: old)
        _ = try store.apply(store.access(), revision: 0, mutations: [.put(record("PUBLIC new state"))]); store.revoke()
        let trusted = try anchor.loadCommitAnchor()
        try FileManager.default.removeItem(at: index); try FileManager.default.copyItem(at: old, to: index)
        var reopened = try EncryptedMetadataStore.open(at: index, domain: domain, key: key)
        XCTAssertThrowsError(try reopened.enableRollbackProtection(anchor))
        XCTAssertEqual(try anchor.loadCommitAnchor(), trusted); reopened.revoke()
        // A different valid branch with the same revision is also a rollback/substitution.
        reopened = try EncryptedMetadataStore.open(at: index, domain: domain, key: key)
        _ = try reopened.apply(reopened.access(), revision: 0, mutations: [.put(record("PUBLIC alternate branch"))]); reopened.revoke()
        reopened = try EncryptedMetadataStore.open(at: index, domain: domain, key: key)
        defer { reopened.revoke() }
        XCTAssertThrowsError(try reopened.enableRollbackProtection(anchor))
        XCTAssertEqual(try anchor.loadCommitAnchor(), trusted)
    }
    func testInterruptedBeforeAndAfterSQLiteCommitRecoverExactPendingState() throws {
        for point in [EncryptedMetadataStore.Checkpoint.beforeCommit, .afterCommit] {
            let (root, domain, key, _, anchor) = try fixture()
            let index = root.appendingPathComponent("index")
            let store = try EncryptedMetadataStore.create(at: index, domain: domain, key: key)
            try store.enableRollbackProtection(anchor)
            let value = record("PUBLIC recoverable pending state")
            XCTAssertThrowsError(try store.apply(store.access(), revision: 0, mutations: [.put(value)], checkpoint: {
                if $0 == point { throw CocoaError(.fileWriteUnknown) }
            }))
            store.revoke()
            let reopened = try EncryptedMetadataStore.open(at: index, domain: domain, key: key)
            defer { reopened.revoke() }
            try reopened.enableRollbackProtection(anchor)
            try reopened.verifyAll(reopened.access())
            XCTAssertEqual(try reopened.page(reopened.access(), offset: 0, limit: 1).records, [value])
            XCTAssertFalse(FileManager.default.fileExists(atPath: index.appendingPathComponent("commit-recovery.v1").path))
        }
    }
    func testMissingOrDamagedRequiredJournalFailsClosedWithoutReset() throws {
        for damage in [false, true] {
            let (root, domain, key, _, anchor) = try fixture()
            let index = root.appendingPathComponent("index")
            let store = try EncryptedMetadataStore.create(at: index, domain: domain, key: key)
            try store.enableRollbackProtection(anchor)
            XCTAssertThrowsError(try store.apply(store.access(), revision: 0, mutations: [.put(record("PUBLIC interrupted"))], checkpoint: {
                if $0 == .beforeCommit { throw CocoaError(.fileWriteUnknown) }
            })); store.revoke()
            let journal = index.appendingPathComponent("commit-recovery.v1")
            if damage { try Data("PUBLIC damaged journal".utf8).write(to: journal) }
            else { try FileManager.default.removeItem(at: journal) }
            let before = try Data(contentsOf: index.appendingPathComponent("metadata.sqlite"))
            let trusted = try anchor.loadCommitAnchor()
            let reopened = try EncryptedMetadataStore.open(at: index, domain: domain, key: key)
            defer { reopened.revoke() }
            XCTAssertThrowsError(try reopened.enableRollbackProtection(anchor))
            XCTAssertEqual(try Data(contentsOf: index.appendingPathComponent("metadata.sqlite")), before)
            XCTAssertEqual(try anchor.loadCommitAnchor(), trusted)
        }
    }
    func testKeychainFailureBeforeAndAfterCommitIsRecoverableWithoutWeakFallback() throws {
        for afterCommit in [false, true] {
            let (root, domain, key, storage, anchor) = try fixture()
            let index = root.appendingPathComponent("index")
            let store = try EncryptedMetadataStore.create(at: index, domain: domain, key: key)
            try store.enableRollbackProtection(anchor)
            if !afterCommit { storage.failWrites = true }
            XCTAssertThrowsError(try store.apply(store.access(), revision: 0, mutations: [.put(record("PUBLIC pending"))], checkpoint: {
                if $0 == .afterCommit && afterCommit { storage.failWrites = true }
            })); store.revoke(); storage.failWrites = false
            let reopened = try EncryptedMetadataStore.open(at: index, domain: domain, key: key)
            defer { reopened.revoke() }
            try reopened.enableRollbackProtection(anchor)
            XCTAssertEqual(try reopened.state(reopened.access()).count, afterCommit ? 1 : 0)
        }
    }
    func testCorruptTargetInventoryCannotFinalizeAnchorOrDiscardRecoveryJournal() throws {
        let (root, domain, key, _, anchor) = try fixture()
        let index = root.appendingPathComponent("index")
        let store = try EncryptedMetadataStore.create(at: index, domain: domain, key: key)
        try store.enableRollbackProtection(anchor)
        XCTAssertThrowsError(try store.apply(store.access(), revision: 0, mutations: [.put(record("PUBLIC recoverable target"))], checkpoint: {
            if $0 == .afterCommit { throw CocoaError(.fileWriteUnknown) }
        })); store.revoke()
        let journal = index.appendingPathComponent("commit-recovery.v1")
        let recovery = try Data(contentsOf: journal), trusted = try anchor.loadCommitAnchor()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(index.appendingPathComponent("metadata.sqlite").path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "UPDATE records SET body=zeroblob(length(body))", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let reopened = try EncryptedMetadataStore.open(at: index, domain: domain, key: key)
        defer { reopened.revoke() }
        XCTAssertThrowsError(try reopened.enableRollbackProtection(anchor))
        XCTAssertEqual(try anchor.loadCommitAnchor(), trusted)
        XCTAssertEqual(try Data(contentsOf: journal), recovery)
    }

    func testUnknownRecoveryFileAndUnavailableAnchorArePreservedAndRejected() throws {
        let (root, domain, key, storage, anchor) = try fixture()
        let index = root.appendingPathComponent("index")
        let store = try EncryptedMetadataStore.create(at: index, domain: domain, key: key)
        let journal = index.appendingPathComponent("commit-recovery.v1"), unknown = Data("PUBLIC unknown file".utf8)
        try unknown.write(to: journal)
        XCTAssertThrowsError(try store.enableRollbackProtection(anchor))
        XCTAssertEqual(try Data(contentsOf: journal), unknown)
        XCTAssertNil(try anchor.loadCommitAnchor())
        try FileManager.default.removeItem(at: journal)
        try store.enableRollbackProtection(anchor)
        storage.unavailable = true
        XCTAssertThrowsError(try store.apply(store.access(), revision: 0, mutations: [.put(record("PUBLIC denied"))]))
        storage.unavailable = false; store.revoke()
        let reopened = try EncryptedMetadataStore.open(at: index, domain: domain, key: key)
        defer { reopened.revoke() }; try reopened.enableRollbackProtection(anchor)
        XCTAssertEqual(try reopened.state(reopened.access()).count, 0)
    }
}
