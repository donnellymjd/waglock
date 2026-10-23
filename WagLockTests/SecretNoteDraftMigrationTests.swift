import Foundation
import Security
import XCTest
@testable import WagLock

@MainActor
final class SecretNoteDraftMigrationTests: XCTestCase {
    private var suites: [String] = []
    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }; suites = []
    }
    private func defaults() throws -> UserDefaults {
        let name = "draft-migration-" + UUID().uuidString; suites.append(name)
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }
    private func raw(_ title: String) throws -> Data {
        try JSONEncoder().encode(SecretNoteDraft(title: title, content: "# disposable draft", updatedAt: Date(timeIntervalSinceReferenceDate: 123)))
    }
    private func manager(_ storage: Storage, _ defaults: UserDefaults) -> SecretNoteDraftManager {
        SecretNoteDraftManager(keychainService: KeychainService(service: "public-draft-migration", storage: storage), defaults: defaults)
    }
    func testDifferentDraftsAreBothPreservedWithoutKeychainWrites() throws {
        let storage = Storage(), preferences = try defaults(), first = try raw("keychain"), second = try raw("legacy")
        storage.item = first; preferences.set(second, forKey: "secretSpace.draft")
        let drafts = manager(storage, preferences)
        XCTAssertEqual(drafts.loadDraft()?.title, "keychain")
        XCTAssertEqual(storage.item, first); XCTAssertEqual(preferences.data(forKey: "secretSpace.draft"), second)
        XCTAssertEqual(storage.writes, 0); XCTAssertEqual(storage.deletes, 0)
    }
    func testOnlyExactDuplicateLegacyCopyIsRemoved() throws {
        let storage = Storage(), preferences = try defaults(), draft = try raw("identical bytes")
        storage.item = draft; preferences.set(draft, forKey: "secretSpace.draft"); preferences.set("keep", forKey: "sentinel")
        _ = manager(storage, preferences)
        XCTAssertEqual(storage.item, draft); XCTAssertNil(preferences.object(forKey: "secretSpace.draft"))
        XCTAssertEqual(preferences.string(forKey: "sentinel"), "keep"); XCTAssertEqual(storage.writes, 0)
    }
    func testAbsentKeychainDraftIsReadBackBeforeLegacyCopyIsRemoved() throws {
        let storage = Storage(), preferences = try defaults(), draft = try raw("legacy only")
        preferences.set(draft, forKey: "secretSpace.draft")
        let drafts = manager(storage, preferences)
        XCTAssertEqual(storage.item, draft); XCTAssertNil(preferences.object(forKey: "secretSpace.draft"))
        XCTAssertEqual(storage.writes, 1); XCTAssertGreaterThanOrEqual(storage.reads, 2)
        XCTAssertEqual(drafts.loadDraft()?.title, "legacy only")
    }
    func testInaccessibleReadOrFailedWriteNeverClearsLegacyDraft() throws {
        for failure in 0..<2 {
            let storage = Storage(), preferences = try defaults(), draft = try raw("keep source")
            preferences.set(draft, forKey: "secretSpace.draft")
            if failure == 0 { storage.failRead = true } else { storage.failWrite = true }
            _ = manager(storage, preferences)
            XCTAssertEqual(preferences.data(forKey: "secretSpace.draft"), draft); XCTAssertNil(storage.item)
            XCTAssertEqual(storage.deletes, 0)
            if failure == 0 { XCTAssertEqual(storage.writes, 0) }
        }
    }
    func testMismatchedOrInaccessibleReadbackDoesNotRemoveSource() throws {
        for failure in 0..<2 {
            let storage = Storage(), preferences = try defaults(), draft = try raw("readback required")
            preferences.set(draft, forKey: "secretSpace.draft")
            if failure == 0 { storage.corruptWrite = true } else { storage.failReadAfterWrite = true }
            _ = manager(storage, preferences)
            XCTAssertEqual(preferences.data(forKey: "secretSpace.draft"), draft); XCTAssertEqual(storage.deletes, 0)
        }
    }
    func testNewerLegacyValueIsPreservedIfSourceChangesDuringPromotion() throws {
        let storage = Storage(), preferences = try defaults(), first = try raw("first"), second = try raw("newer")
        preferences.set(first, forKey: "secretSpace.draft")
        storage.didWrite = { preferences.set(second, forKey: "secretSpace.draft") }
        _ = manager(storage, preferences)
        XCTAssertEqual(storage.item, first); XCTAssertEqual(preferences.data(forKey: "secretSpace.draft"), second)
    }
    func testMalformedOrUnknownFieldLegacyDraftIsPreservedWithoutPromotion() throws {
        var future = try JSONSerialization.jsonObject(with: raw("future")) as! [String: Any]; future["attachment"] = "keep"
        for data in [Data("bad JSON".utf8), try JSONSerialization.data(withJSONObject: future)] {
            let storage = Storage(), preferences = try defaults(); preferences.set(data, forKey: "secretSpace.draft")
            _ = manager(storage, preferences)
            XCTAssertEqual(preferences.data(forKey: "secretSpace.draft"), data)
            XCTAssertNil(storage.item); XCTAssertEqual(storage.writes, 0)
        }
    }
    func testNormalSaveLoadAndExplicitClearKeepWorkingWithInjectedStorage() throws {
        let storage = Storage(), preferences = try defaults(), drafts = manager(storage, preferences)
        XCTAssertTrue(drafts.saveDraft(title: "new draft", content: "body"))
        XCTAssertEqual(drafts.loadDraft()?.content, "body")
        drafts.clearDraft(); XCTAssertNil(drafts.loadDraft())
    }

    private final class Storage: KeychainStorage {
        nonisolated deinit { }
        var item: Data?
        var failRead = false, failWrite = false, corruptWrite = false, failReadAfterWrite = false
        var reads = 0, writes = 0, deletes = 0
        var didWrite: (() -> Void)?
        func read(account: String) throws -> Data {
            reads += 1
            if failRead || (failReadAfterWrite && writes > 0) { throw KeychainError.unexpectedStatus(errSecInteractionNotAllowed) }
            guard let item else { throw KeychainError.itemNotFound }; return item
        }
        func write(account: String, data: Data, createOnly: Bool) throws {
            writes += 1
            if failWrite { throw KeychainError.unexpectedStatus(errSecNotAvailable) }
            item = corruptWrite ? Data("mismatched fixture".utf8) : data; didWrite?()
        }
        func delete(account: String) throws { deletes += 1; item = nil }
    }
}
