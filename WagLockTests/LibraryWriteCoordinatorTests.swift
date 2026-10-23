import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import WagLock

@MainActor
final class LibraryWriteCoordinatorTests: XCTestCase {
    private var parents: [URL] = []
    override func tearDown() { for root in parents { try? FileManager.default.removeItem(at: root) }; parents = [] }
    private func root() throws -> URL {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("write-gate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false); parents.append(parent)
        return parent.appendingPathComponent("index")
    }
    private func domain() -> EncryptedMetadataStore.Domain { .init(libraryID: UUID(), vaultID: UUID()) }
    private func key() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }
    private func memory() throws -> ModelContainer { try MetadataModelCodec.memoryProjection([], authorized: { true }) }

    func testManagedLegacySaveHonorsAuthorizationAndRevokedContainerCannotFallback() throws {
        let container = try memory(), context = container.mainContext
        var authorized = true
        let lease = try LibraryWriteCoordinator.bindLegacy(container, authorized: { authorized })
        context.insert(SecretNote(title: "first")); try LibraryWriteCoordinator.save(context)
        context.insert(SecretNote(title: "stale")); authorized = false
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(context)); context.rollback()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SecretNote>()), 1)
        authorized = true; LibraryWriteCoordinator.revoke(lease)
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(context))
        XCTAssertFalse(LibraryWriteCoordinator.mayDiscardUncommittedResources(in: context))
    }
    func testOlderLeaseCannotRevokeAReplacementAndUnmanagedFixturesStillSave() throws {
        let container = try memory(), context = container.mainContext
        context.insert(SecretNote(title: "unmanaged")); try LibraryWriteCoordinator.save(context)
        let old = try LibraryWriteCoordinator.bindLegacy(container, authorized: { false })
        let new = try LibraryWriteCoordinator.bindLegacy(container, authorized: { true })
        defer { LibraryWriteCoordinator.revoke(new) }
        LibraryWriteCoordinator.revoke(old)
        context.insert(SecretNote(title: "replacement")); try LibraryWriteCoordinator.save(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SecretNote>()), 2)
    }
    func testEncryptedInsertEditDeleteAndReopenPreserveExactModelFields() throws {
        let root = try root(), domain = domain(), key = key()
        let repository = try EncryptedLibraryRepository.create(at: root, domain: domain, key: key, authorized: { true })
        let context = repository.container.mainContext
        XCTAssertTrue(repository.container.configurations.allSatisfy(\.isStoredInMemoryOnly))
        let media = MediaItem(fileName: "private cafe\u{301}", fileExtension: ".jpg", fileSize: 123, type: .photo,
                              encryptedPath: "unchanged-original", thumbnailData: Data([1, 2, 3]), width: 12, height: 34)
        let note = SecretNote(title: "note", content: "# first", tags: ["café", "cafe\u{301}"])
        let album = VaultAlbum(parentID: nil, name: "album", protection: .password, wrappedKey: Data([4]), encryptedCatalog: Data([5]))
        context.insert(media); context.insert(note); context.insert(album)
        try LibraryWriteCoordinator.save(context)
        note.content = "# edited"; media.fileName = "new cafe\u{301}"; try LibraryWriteCoordinator.save(context)
        context.delete(album); try LibraryWriteCoordinator.save(context)
        let expected = try MetadataModelCodec.capture(context, authorized: { true }); repository.revoke()
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(context))
        let reopened = try EncryptedLibraryRepository.open(at: root, domain: domain, key: key, authorized: { true }); defer { reopened.revoke() }
        XCTAssertEqual(try MetadataModelCodec.capture(reopened.container.mainContext, authorized: { true }), expected)
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            XCTAssertNil(try Data(contentsOf: file).range(of: Data("# edited".utf8)))
        }
    }
    func testPrecommitFailureRollsBackProjectionAndKeepsDurableRecords() throws {
        let root = try root(), domain = domain(), key = key()
        var failing = false
        let repository = try EncryptedLibraryRepository.create(at: root, domain: domain, key: key, authorized: { true }, checkpoint: { point in
            if failing, case .beforeCommit = point { throw CocoaError(.fileWriteOutOfSpace) }
        })
        let context = repository.container.mainContext
        let note = SecretNote(title: "retained"); context.insert(note); try LibraryWriteCoordinator.save(context)
        failing = true; note.title = "uncommitted"
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(context)); context.rollback()
        XCTAssertFalse(repository.needsReconciliation)
        repository.revoke()
        let opened = try EncryptedLibraryRepository.open(at: root, domain: domain, key: key, authorized: { true }); defer { opened.revoke() }
        XCTAssertEqual(try opened.container.mainContext.fetch(FetchDescriptor<SecretNote>()).first?.title, "retained")
    }
    func testUncertainCommitPreservesDurableDataAndForbidsResourceCleanup() throws {
        let root = try root(), domain = domain(), key = key()
        let repository = try EncryptedLibraryRepository.create(at: root, domain: domain, key: key, authorized: { true }, checkpoint: { point in
            if case .afterCommit = point { throw CocoaError(.fileWriteUnknown) }
        })
        let context = repository.container.mainContext
        context.insert(SecretNote(title: "committed despite error"))
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(context)) { XCTAssertTrue($0 as? EncryptedMetadataStore.Failure == .uncertainCommit) }
        context.rollback()
        XCTAssertTrue(repository.needsReconciliation)
        XCTAssertFalse(LibraryWriteCoordinator.mayDiscardUncommittedResources(in: context))
        let opened = try EncryptedLibraryRepository.open(at: root, domain: domain, key: key, authorized: { true }); defer { opened.revoke() }
        XCTAssertEqual(try opened.container.mainContext.fetch(FetchDescriptor<SecretNote>()).count, 1)
    }
    func testProjectionSaveFailureAfterDurableCommitRequiresReopen() throws {
        let root = try root(), domain = domain(), key = key()
        let repository = try EncryptedLibraryRepository.create(at: root, domain: domain, key: key, authorized: { true }, saveProjection: { _ in throw CocoaError(.fileWriteUnknown) })
        let context = repository.container.mainContext; context.insert(SecretNote(title: "durable"))
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(context))
        XCTAssertTrue(repository.needsReconciliation)
        XCTAssertFalse(LibraryWriteCoordinator.mayDiscardUncommittedResources(in: context))
        let opened = try EncryptedLibraryRepository.open(at: root, domain: domain, key: key, authorized: { true }); defer { opened.revoke() }
        XCTAssertEqual(try opened.container.mainContext.fetch(FetchDescriptor<SecretNote>()).first?.title, "durable")
    }
    func testForeignContextAndRevokedAuthorizationCannotPersistChanges() throws {
        let root = try root(), domain = domain(), key = key()
        var authorized = true
        let repository = try EncryptedLibraryRepository.create(at: root, domain: domain, key: key, authorized: { authorized })
        let foreign = ModelContext(repository.container); foreign.insert(SecretNote(title: "foreign"))
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(foreign))
        authorized = false
        repository.container.mainContext.insert(SecretNote(title: "revoked"))
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(repository.container.mainContext))
        repository.revoke()
        let opened = try EncryptedLibraryRepository.open(at: root, domain: domain, key: key, authorized: { true }); defer { opened.revoke() }
        XCTAssertEqual(try opened.container.mainContext.fetchCount(FetchDescriptor<SecretNote>()), 0)
    }
    func testFailedLegacySavePreservesPossiblyCommittedResources() throws {
        let container = try memory(), context = container.mainContext
        let lease = try LibraryWriteCoordinator.bindLegacy(container, authorized: { true }, saveContext: { context in
            try context.save(); throw CocoaError(.fileWriteUnknown)
        })
        defer { LibraryWriteCoordinator.revoke(lease) }
        context.insert(SecretNote(title: "possibly committed"))
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(context))
        XCTAssertFalse(LibraryWriteCoordinator.mayDiscardUncommittedResources(in: context))
        XCTAssertFalse(context.autosaveEnabled)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<SecretNote>()), 1)
    }
    func testEncryptedBindingCannotBeDowngradedToUnencryptedProjectionSave() throws {
        let root = try root(), domain = domain(), key = key()
        let repository = try EncryptedLibraryRepository.create(at: root, domain: domain, key: key, authorized: { true })
        XCTAssertThrowsError(try LibraryWriteCoordinator.bindLegacy(repository.container, authorized: { true }))
        repository.container.mainContext.insert(SecretNote(title: "still encrypted"))
        try LibraryWriteCoordinator.save(repository.container.mainContext); repository.revoke()
        let opened = try EncryptedLibraryRepository.open(at: root, domain: domain, key: key, authorized: { true }); defer { opened.revoke() }
        XCTAssertEqual(try opened.container.mainContext.fetchCount(FetchDescriptor<SecretNote>()), 1)
    }
    func testStaleEncryptedNoopRequiresReconciliationAndRetainsResources() throws {
        let root = try root(), domain = domain(), key = key()
        let first = try EncryptedLibraryRepository.create(at: root, domain: domain, key: key, authorized: { true })
        defer { first.revoke() }
        let second = try EncryptedLibraryRepository.open(at: root, domain: domain, key: key, authorized: { true })
        first.container.mainContext.insert(SecretNote(title: "new revision")); try LibraryWriteCoordinator.save(first.container.mainContext)
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(second.container.mainContext))
        XCTAssertTrue(second.needsReconciliation)
        XCTAssertFalse(LibraryWriteCoordinator.mayDiscardUncommittedResources(in: second.container.mainContext))
    }
    func testReleasedEncryptedOwnerCannotFallBackToMemoryOnlySuccess() throws {
        var repository: EncryptedLibraryRepository? = try EncryptedLibraryRepository.create(at: root(), domain: domain(), key: key(), authorized: { true })
        let context = try XCTUnwrap(repository).container.mainContext
        repository = nil
        // Do not touch the model/container after release: the gateway itself
        // must reject this retained context before consulting context.container.
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(context))
        XCTAssertFalse(LibraryWriteCoordinator.mayDiscardUncommittedResources(in: context))
    }
    private struct ContextProbe: View {
        @Environment(\.modelContext) private var context
        let observe: (ModelContext) -> Void
        var body: some View { Color.clear.onAppear { observe(context) } }
    }
    func testSwiftUIAttachmentPreservesManagedContextAndDisablesAutomaticSaving() async throws {
        let container = try memory()
        let lease = try LibraryWriteCoordinator.bindLegacy(container, authorized: { true })
        defer { LibraryWriteCoordinator.revoke(lease) }
        let appeared = expectation(description: "managed context attached")
        let host = UIHostingController(rootView: ContextProbe { context in
            XCTAssertTrue(context === container.mainContext)
            XCTAssertFalse(context.autosaveEnabled)
            appeared.fulfill()
        }.modelContainer(container))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [appeared], timeout: 5)
        XCTAssertFalse(container.mainContext.autosaveEnabled)
    }
    func testMountInvalidationRevokesRetainedOwnerContext() async throws {
        let container = try memory()
        let mounts = LibraryMountCoordinator(factory: { _ in container })
        let request = LibraryMountCoordinator.Request(sessionID: UUID(), scope: .legacyOwner)
        await mounts.mount(request) { true }
        container.mainContext.insert(SecretNote(title: "before lock")); try LibraryWriteCoordinator.save(container.mainContext)
        mounts.invalidate()
        container.mainContext.insert(SecretNote(title: "after lock"))
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(container.mainContext)); container.mainContext.rollback()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SecretNote>()), 1)
    }
}
