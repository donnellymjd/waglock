import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import WagLock

@MainActor
final class FreshEncryptedLibraryTests: XCTestCase {
    private final class Anchor: LibraryIdentityAnchor {
        nonisolated deinit { }
        var identity: Data?
        var unavailable = false
        var failEstablish = false
        func loadLibraryIdentity() throws -> Data? {
            if unavailable { throw KeychainError.unexpectedStatus(-25308) }; return identity
        }
        func establishLibraryIdentity(_ value: Data) throws {
            if failEstablish { throw CocoaError(.fileWriteOutOfSpace) }
            guard identity == nil else { throw KeychainError.duplicateItem }; identity = value
        }
    }
    func testVerifiedSystemVarAliasIsAcceptedWithoutAllowingOtherSymlinks() throws {
        try FreshEncryptedLibrary.safe(URL(fileURLWithPath: "/var"))
        try FreshEncryptedLibrary.safe(URL(fileURLWithPath: "/private/var"))
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let link = base.appendingPathComponent("untrusted-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: base)
        XCTAssertThrowsError(try FreshEncryptedLibrary.safe(link))
    }
    func testMountFailureReferencesNeverIncludeAssociatedPrivateValues() {
        XCTAssertEqual(LibraryMountCoordinator.reference(for: EncryptionError.fileNotFound(path: "PUBLIC-sensitive-path")), "WL-E01")
        XCTAssertEqual(LibraryMountCoordinator.reference(for: KeychainError.unexpectedStatus(-25308)), "WL-K01")
        XCTAssertEqual(LibraryMountCoordinator.reference(for: FreshEncryptedLibrary.Failure.missingLibrary), "WL-M06")
        XCTAssertEqual(LibraryMountCoordinator.reference(for: EncryptedMetadataStore.Failure.corrupt), "WL-I04")
        XCTAssertEqual(LibraryMountCoordinator.reference(for: NSError(domain: "PUBLIC-sensitive-domain", code: 42)), "WL-U01")
    }
    private var parents: [URL] = []
    private let secret = "PUBLIC disposable storage secret *._ café"
    override func tearDown() { for parent in parents { try? FileManager.default.removeItem(at: parent) }; parents = [] }
    private func root() throws -> URL {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("fresh-library-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false); parents.append(parent)
        return parent.appendingPathComponent("vault")
    }
    private func open(_ root: URL, _ anchor: Anchor) throws -> EncryptedLibraryRepository {
        try FreshEncryptedLibrary.open(at: root, dataPassword: secret, anchor: anchor, authorized: { true })
    }
    private func allFiles(_ root: URL) throws -> [URL] {
        try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
            .compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
    func testFreshLibraryEncryptsModelsThumbnailsAndDraftsAcrossReopen() throws {
        let root = try root(), anchor = Anchor(), repository = try open(root, anchor)
        let marker = "private-fixture-" + UUID().uuidString
        let context = repository.container.mainContext
        context.insert(SecretNote(title: marker, content: marker, tags: [marker]))
        context.insert(MediaItem(fileName: marker, fileExtension: "jpg", fileSize: 3, type: .photo,
                                 encryptedPath: marker, thumbnailData: Data(marker.utf8)))
        try LibraryWriteCoordinator.save(context)
        let drafts = LibraryWriteCoordinator.draftManager(in: context)
        XCTAssertTrue(drafts.saveDraft(title: marker, content: marker))
        repository.revoke()
        XCTAssertFalse(drafts.saveDraft(title: "stale", content: "must fail"))
        XCTAssertNil(drafts.loadDraft())
        for file in try allFiles(root) {
            let data = try Data(contentsOf: file)
            XCTAssertNil(data.range(of: Data(marker.utf8)))
            XCTAssertNil(data.range(of: Data(Data(marker.utf8).base64EncodedString().utf8)))
            XCTAssertNil(data.range(of: Data(secret.utf8)))
        }
        let reopened = try open(root, anchor); defer { reopened.revoke() }
        XCTAssertEqual(try reopened.container.mainContext.fetch(FetchDescriptor<SecretNote>()).first?.content, marker)
        let restoredDrafts = LibraryWriteCoordinator.draftManager(in: reopened.container.mainContext)
        XCTAssertEqual(restoredDrafts.loadDraft()?.content, marker)
        XCTAssertTrue(restoredDrafts.clearDraft())
        reopened.revoke()
        let cleared = try open(root, anchor); defer { cleared.revoke() }
        XCTAssertNil(try cleared.loadDraft())
    }
    func testPublicationResumesAtEveryCheckpointWithoutReset() throws {
        enum Interrupted: Error { case simulatedCrash }
        let points: [FreshEncryptedLibrary.Checkpoint] = [.keyFileWritten, .descriptorSaved, .indexCreated, .beforePublication, .afterPublication]
        for point in points {
            let root = try root(), anchor = Anchor()
            XCTAssertThrowsError(try FreshEncryptedLibrary.open(at: root, dataPassword: secret, anchor: anchor, authorized: { true }, checkpoint: {
                if String(describing: $0) == String(describing: point) { throw Interrupted.simulatedCrash }
            }))
            let repository = try open(root, anchor)
            XCTAssertNotNil(anchor.identity)
            repository.container.mainContext.insert(SecretNote(title: "resumed")); try LibraryWriteCoordinator.save(repository.container.mainContext)
            repository.revoke()
            let verified = try open(root, anchor); defer { verified.revoke() }
            XCTAssertEqual(try verified.container.mainContext.fetchCount(FetchDescriptor<SecretNote>()), 1)
        }
    }
    func testUnpublishedEmptySQLiteCreationCanResumeButUnknownContentIsPreserved() throws {
        enum Interrupted: Error { case simulatedCrash }
        let root = try root(), anchor = Anchor()
        XCTAssertThrowsError(try FreshEncryptedLibrary.open(at: root, dataPassword: secret, anchor: anchor, authorized: { true }, checkpoint: { point in
            if case .descriptorSaved = point {
                let index = root.deletingLastPathComponent().appendingPathComponent("vault.creating/index")
                try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
                try Data().write(to: index.appendingPathComponent("metadata.sqlite"))
                throw Interrupted.simulatedCrash
            }
        }))
        let repository = try open(root, anchor); repository.revoke()
        let other = try self.root(), otherAnchor = Anchor()
        let pending = other.deletingLastPathComponent().appendingPathComponent("vault.creating")
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: false)
        let unknown = pending.appendingPathComponent("do-not-delete")
        try Data("keep".utf8).write(to: unknown)
        XCTAssertThrowsError(try open(other, otherAnchor))
        XCTAssertEqual(try Data(contentsOf: unknown), Data("keep".utf8))
    }
    func testMissingSubstitutedAndCorruptPublishedLibraryNeverCreatesReplacement() throws {
        let root = try root(), anchor = Anchor(), repository = try open(root, anchor); repository.revoke()
        let moved = root.deletingLastPathComponent().appendingPathComponent("saved")
        try FileManager.default.moveItem(at: root, to: moved)
        XCTAssertThrowsError(try open(root, anchor))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        try FileManager.default.moveItem(at: moved, to: root)
        let wrong = Anchor(); wrong.identity = Data(repeating: 1, count: 32)
        XCTAssertThrowsError(try open(root, wrong))
        let file = root.appendingPathComponent("index/metadata.sqlite")
        try Data("damaged database".utf8).write(to: file)
        XCTAssertThrowsError(try open(root, anchor))
        XCTAssertEqual(try Data(contentsOf: file), Data("damaged database".utf8))
    }
    func testWrongPasswordUnavailableAnchorAndLegacySourceNeverResetAnything() throws {
        let root = try root(), anchor = Anchor(), repository = try open(root, anchor); repository.revoke()
        let descriptor = root.appendingPathComponent("library.json"), before = try Data(contentsOf: descriptor)
        XCTAssertThrowsError(try FreshEncryptedLibrary.open(at: root, dataPassword: "incorrect", anchor: anchor, authorized: { true }))
        XCTAssertEqual(try Data(contentsOf: descriptor), before)
        anchor.unavailable = true
        XCTAssertThrowsError(try open(root, anchor)); XCTAssertEqual(try Data(contentsOf: descriptor), before)
        let fresh = try self.root(), source = fresh.deletingLastPathComponent().appendingPathComponent("legacy.store-wal")
        try Data("legacy bytes".utf8).write(to: source)
        XCTAssertThrowsError(try FreshEncryptedLibrary.open(at: fresh, dataPassword: secret, anchor: Anchor(), legacySources: [source], authorized: { true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertEqual(try Data(contentsOf: source), Data("legacy bytes".utf8))
    }
    func testRevocationAndUncertainAnchorWriteKeepRecoverablePublishedRoot() throws {
        let root = try root(), anchor = Anchor()
        var authorized = true
        XCTAssertThrowsError(try FreshEncryptedLibrary.open(at: root, dataPassword: secret, anchor: anchor, authorized: { authorized }, checkpoint: { point in
            if case .beforePublication = point { authorized = false }
        }))
        let repository = try open(root, anchor); repository.revoke()
        let other = try self.root(), failing = Anchor(); failing.failEstablish = true
        XCTAssertThrowsError(try open(other, failing))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        failing.failEstablish = false
        let recovered = try open(other, failing); recovered.revoke()
    }
    func testSymlinkRootAndDescriptorAreRejected() throws {
        let root = try root(), target = root.deletingLastPathComponent().appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: target)
        XCTAssertThrowsError(try open(root, Anchor()))
        let other = try self.root(), anchor = Anchor(), repository = try open(other, anchor); repository.revoke()
        let descriptor = other.appendingPathComponent("library.json")
        let saved = other.appendingPathComponent("saved.json")
        try FileManager.default.moveItem(at: descriptor, to: saved)
        try FileManager.default.createSymbolicLink(at: descriptor, withDestinationURL: saved)
        XCTAssertThrowsError(try open(other, anchor))
    }
    func testBulkTransactionOverRehearsalLimitAndIncrementalEditsPersist() throws {
        let root = try root(), anchor = Anchor(), repository = try open(root, anchor)
        let context = repository.container.mainContext
        for value in 0..<513 { context.insert(SecretNote(title: "fixture-\(value)")) }
        try LibraryWriteCoordinator.save(context)
        let notes = try context.fetch(FetchDescriptor<SecretNote>())
        notes[0].content = "changed once"; context.delete(notes[1])
        let ephemeral = SecretNote(title: "never published"); context.insert(ephemeral); context.delete(ephemeral)
        try LibraryWriteCoordinator.save(context); repository.revoke()
        let reopened = try open(root, anchor); defer { reopened.revoke() }
        let restored = try reopened.container.mainContext.fetch(FetchDescriptor<SecretNote>())
        XCTAssertEqual(restored.count, 512)
        XCTAssertEqual(restored.filter { $0.content == "changed once" }.count, 1)
        XCTAssertFalse(restored.contains { $0.title == "never published" })
    }
    func testThousandThumbnailRecordsReopenWithinPagedResourceContract() throws {
        let root = try root(), anchor = Anchor(), repository = try open(root, anchor)
        let context = repository.container.mainContext
        let thumbnail = Data(repeating: 17, count: 24 * 1024)
        for index in 0..<1_000 {
            context.insert(MediaItem(fileName: "Scale fixture \(index)", fileExtension: "jpg", fileSize: 1,
                type: .photo, encryptedPath: "opaque-fixture-\(index)", thumbnailData: thumbnail))
        }
        let saveStart = Date(); try LibraryWriteCoordinator.save(context)
        let saveSeconds = Date().timeIntervalSince(saveStart); repository.revoke()
        let openStart = Date(); let reopened = try open(root, anchor); defer { reopened.revoke() }
        let openSeconds = Date().timeIntervalSince(openStart)
        XCTAssertEqual(try reopened.container.mainContext.fetchCount(FetchDescriptor<MediaItem>()), 1_000)
        let report: [String: Any] = ["fixtureOnly": true, "records": 1_000, "thumbnailBytesPerRecord": thumbnail.count,
            "saveSeconds": saveSeconds, "reopenSeconds": openSeconds,
            "projectionRemainsMemoryOnly": reopened.container.configurations.allSatisfy(\.isStoredInMemoryOnly)]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "public-encrypted-index-scale.json"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testDraftCommitFailuresPreservePreviousOrDurableNewDraft() throws {
        enum Interrupted: Error { case beforeCommit }
        for afterCommit in [false, true] {
            let root = try root(), domain = EncryptedMetadataStore.Domain(libraryID: UUID(), vaultID: UUID())
            let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            var failing = false
            let repository = try EncryptedLibraryRepository.create(at: root, domain: domain, key: key, authorized: { true }, checkpoint: { point in
                if failing {
                    if case .afterCommit = point, afterCommit { throw Interrupted.beforeCommit }
                    if case .beforeCommit = point, !afterCommit { throw Interrupted.beforeCommit }
                }
            })
            let manager = LibraryWriteCoordinator.draftManager(in: repository.container.mainContext)
            XCTAssertTrue(manager.saveDraft(title: "old", content: "old")); failing = true
            XCTAssertFalse(manager.saveDraft(title: "new", content: "new")); repository.revoke()
            let reopened = try EncryptedLibraryRepository.open(at: root, domain: domain, key: key, authorized: { true }); defer { reopened.revoke() }
            let value = try XCTUnwrap(reopened.loadDraft())
            XCTAssertEqual(try MetadataDraftCodec.value(value).title, afterCommit ? "new" : "old")
        }
    }
    func testBackgroundAndPasswordChangesRevokeMountedLibraryBeforeItsViewDisappears() async throws {
        let credentials = KeychainService(service: "background-mount-" + UUID().uuidString, storage: InMemoryAttemptStorage())
        try credentials.savePassword("PUBLIC background password")
        let auth = AuthenticationViewModel(keychainService: credentials, manageInstallationState: false)
        auth.password = "PUBLIC background password"; await auth.login()?.value
        defer { auth.logout() }
        let mounts = LibraryMountCoordinator(encryptedRoot: try root(), anchor: Anchor())
        let request = LibraryMountCoordinator.Request(sessionID: auth.librarySessionID, scope: .legacyOwner)
        await mounts.mount(request, dataPassword: auth.sessionPassword) { auth.isAuthenticated }
        let context = try mounts.container(for: request).mainContext
        let drafts = LibraryWriteCoordinator.draftManager(in: context)
        XCTAssertTrue(drafts.saveDraft(title: "PUBLIC saved draft", content: "PUBLIC content"))
        // Keep both the mount and memory projection alive: no SwiftUI disposal occurs.
        auth.handleBackground(lockImmediately: true)
        XCTAssertNil(mounts.active)
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(context))
        XCTAssertFalse(drafts.saveDraft(title: "late", content: "late"))
        XCTAssertThrowsError(try mounts.exportDrafts())
        auth.password = "PUBLIC background password"; await auth.login()?.value
        let fresh = LibraryMountCoordinator.Request(sessionID: auth.librarySessionID, scope: .legacyOwner)
        await mounts.mount(fresh, dataPassword: auth.sessionPassword) { auth.isAuthenticated }
        XCTAssertEqual(try mounts.exportDrafts().first?.title, "PUBLIC saved draft")
        let previous = auth.librarySessionID
        try auth.updatePassword(oldPassword: "PUBLIC background password", newPassword: "PUBLIC changed password")
        XCTAssertNil(mounts.active, "Password replacement must synchronously close the previous mount too")
        XCTAssertNotEqual(auth.librarySessionID, previous)
        let changed = LibraryMountCoordinator.Request(sessionID: auth.librarySessionID, scope: .legacyOwner)
        await mounts.mount(changed, dataPassword: auth.sessionPassword) { auth.isAuthenticated }
        XCTAssertEqual(try mounts.exportDrafts().first?.title, "PUBLIC saved draft")
        mounts.invalidate()
    }

    func testIndependentMountSeparatesNotesDraftsAndSessionRevocation() async throws {
        let firstID = UUID(), secondID = UUID()
        let first = LibraryMountCoordinator(encryptedRoot: try root(), anchor: Anchor(), scope: .independentVault(firstID))
        let second = LibraryMountCoordinator(encryptedRoot: try root(), anchor: Anchor(), scope: .independentVault(secondID))
        let firstRequest = LibraryMountCoordinator.Request(sessionID: UUID(), scope: .independentVault(firstID))
        let secondRequest = LibraryMountCoordinator.Request(sessionID: UUID(), scope: .independentVault(secondID))
        await first.mount(firstRequest, dataPassword: "PUBLIC-first-independent-key") { true }
        await second.mount(secondRequest, dataPassword: "PUBLIC-second-independent-key") { true }
        let firstContext = try first.container(for: firstRequest).mainContext
        let secondContext = try second.container(for: secondRequest).mainContext
        firstContext.insert(SecretNote(title: "PUBLIC first", content: "first only"))
        secondContext.insert(SecretNote(title: "PUBLIC second", content: "second only"))
        try LibraryWriteCoordinator.save(firstContext)
        try LibraryWriteCoordinator.save(secondContext)
        let firstDraft = LibraryWriteCoordinator.draftManager(in: firstContext)
        let secondDraft = LibraryWriteCoordinator.draftManager(in: secondContext)
        XCTAssertTrue(firstDraft.saveDraft(title: "first draft", content: "first"))
        XCTAssertTrue(secondDraft.saveDraft(title: "second draft", content: "second"))
        XCTAssertEqual(try first.exportDrafts().first?.content, "first")
        XCTAssertEqual(try second.exportDrafts().first?.content, "second")
        LibraryMountCoordinator.invalidateSession(firstRequest.sessionID)
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(firstContext))
        XCTAssertFalse(firstDraft.saveDraft(title: "late", content: "late"))
        XCTAssertEqual(try second.exportDrafts().first?.content, "second")
        await first.mount(firstRequest, dataPassword: "PUBLIC-first-independent-key") { true }
        let reopened = try first.container(for: firstRequest).mainContext
        XCTAssertEqual(try reopened.fetch(FetchDescriptor<SecretNote>()).map(\.content), ["first only"])
        XCTAssertEqual(try secondContext.fetch(FetchDescriptor<SecretNote>()).map(\.content), ["second only"])
        await first.mount(secondRequest, dataPassword: "PUBLIC-second-independent-key") { true }
        XCTAssertTrue(first.failed)
        XCTAssertNil(first.active)
        XCTAssertThrowsError(try first.exportDrafts())
        second.invalidate()
    }

    func testEncryptedMountRevokesWritesDraftsAndExportOnInvalidation() async throws {
        let root = try root(), anchor = Anchor(), mounts = LibraryMountCoordinator(encryptedRoot: root, anchor: anchor)
        let request = LibraryMountCoordinator.Request(sessionID: UUID(), scope: .legacyOwner)
        await mounts.mount(request, dataPassword: secret) { true }
        let container = try mounts.container(for: request), context = container.mainContext
        XCTAssertTrue(container.configurations.allSatisfy(\.isStoredInMemoryOnly))
        let drafts = LibraryWriteCoordinator.draftManager(in: context)
        XCTAssertTrue(drafts.saveDraft(title: "encrypted", content: "export me"))
        XCTAssertEqual(try mounts.exportDrafts().first?.origin, .encryptedVault)
        mounts.invalidate()
        XCTAssertThrowsError(try LibraryWriteCoordinator.save(context))
        XCTAssertFalse(drafts.saveDraft(title: "stale", content: "stale"))
        XCTAssertThrowsError(try mounts.exportDrafts())
        await mounts.mount(request, dataPassword: "wrong") { true }
        XCTAssertTrue(mounts.failed); XCTAssertNil(mounts.active)
        await mounts.mount(request, dataPassword: secret) { true }
        XCTAssertEqual(try mounts.exportDrafts().first?.content, "export me")
        mounts.invalidate()
    }
}
