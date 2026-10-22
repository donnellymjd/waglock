import Foundation
import XCTest
@testable import WagLock

@MainActor
final class NoteAutosaveSecurityTests: XCTestCase {
    /// Deliberately ignores cancellation so tests can deliver stale completions.
    private actor Gate {
        private var continuations: [CheckedContinuation<Void, Never>?] = []
        func pause() async { await withCheckedContinuation { continuations.append($0) } }
        func waitForCount(_ count: Int) async throws {
            let deadline = Date().addingTimeInterval(5)
            while continuations.count < count {
                if Date() >= deadline { throw CancellationError() }
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        func release(_ index: Int) { continuations[index]?.resume(); continuations[index] = nil }
    }

    func testInactiveWrongSessionAndUnavailableOwnerCannotScheduleWrites() {
        let authority = DocumentPreviewService()
        let autosave = NoteAutosaveCoordinator(authority: authority)
        let session = UUID()
        var writes = 0
        XCTAssertNil(autosave.schedule(session: session, authorize: { true }) { writes += 1; return true })
        authority.beginSession(session)
        XCTAssertNil(autosave.schedule(session: UUID(), authorize: { true }) { writes += 1; return true })
        XCTAssertNil(autosave.schedule(session: session, authorize: { false }) { writes += 1; return true })
        XCTAssertFalse(autosave.saveNow(session: session, authorize: { false }) { writes += 1; return true })
        XCTAssertEqual(writes, 0)
    }

    func testLatestEditWinsWhenOlderCancelledDelayCompletesLast() async throws {
        let authority = DocumentPreviewService(), gate = Gate(), session = UUID()
        authority.beginSession(session)
        let autosave = NoteAutosaveCoordinator(authority: authority, delay: { await gate.pause() })
        var writes: [String] = []
        let old = try XCTUnwrap(autosave.schedule(session: session, authorize: { true }) { writes.append("old"); return true })
        try await gate.waitForCount(1)
        let current = try XCTUnwrap(autosave.schedule(session: session, authorize: { true }) { writes.append("latest"); return true })
        try await gate.waitForCount(2)
        await gate.release(1); await current.value
        await gate.release(0); await old.value
        XCTAssertEqual(writes, ["latest"])
        XCTAssertNotNil(autosave.lastSavedAt)
    }

    func testExplicitSaveCannotResurrectTheClearedKeychainDraft() async throws {
        let authority = DocumentPreviewService(), gate = Gate(), session = UUID()
        let credentials = KeychainService(service: "note-save-" + UUID().uuidString)
        defer { credentials.clearAllKeychainData() }
        XCTAssertTrue(credentials.saveSecretNoteDraft(Data("current draft".utf8)))
        authority.beginSession(session)
        let autosave = NoteAutosaveCoordinator(authority: authority, delay: { await gate.pause() })
        let late = try XCTUnwrap(autosave.schedule(session: session, authorize: { true }) {
            credentials.saveSecretNoteDraft(Data("stale draft".utf8))
        })
        try await gate.waitForCount(1)
        XCTAssertTrue(autosave.saveNow(session: session, authorize: { true }) {
            credentials.deleteSecretNoteDraft()
            return true
        })
        await gate.release(0); await late.value
        XCTAssertNil(credentials.loadSecretNoteDraft())
    }

    func testBackgroundAndSameSessionResumeRejectTheOldRevisionButAllowFreshEdits() async throws {
        let authority = DocumentPreviewService(), gate = Gate(), session = UUID()
        authority.beginSession(session)
        let autosave = NoteAutosaveCoordinator(authority: authority, delay: { await gate.pause() })
        var writes: [String] = []
        let stale = try XCTUnwrap(autosave.schedule(session: session, authorize: { true }) { writes.append("stale"); return true })
        try await gate.waitForCount(1)
        authority.endSession(matching: session)
        XCTAssertFalse(autosave.flush())
        authority.beginSession(session)
        await gate.release(0); await stale.value
        XCTAssertTrue(writes.isEmpty)
        XCTAssertTrue(autosave.saveNow(session: session, authorize: { true }) { writes.append("fresh"); return true })
        XCTAssertEqual(writes, ["fresh"])
    }

    func testAuthorizationIsRecheckedAtCommitEvenWithoutARevisionChange() async throws {
        let authority = DocumentPreviewService(), gate = Gate(), session = UUID()
        authority.beginSession(session)
        let autosave = NoteAutosaveCoordinator(authority: authority, delay: { await gate.pause() })
        var available = true, wrote = false
        let pending = try XCTUnwrap(autosave.schedule(session: session, authorize: { available }) { wrote = true; return true })
        try await gate.waitForCount(1)
        available = false
        await gate.release(0); await pending.value
        XCTAssertFalse(wrote)
        XCTAssertNil(autosave.lastSavedAt)
    }

    func testBackFlushCommitsOnceAndLateTimerCannotDuplicateIt() async throws {
        let authority = DocumentPreviewService(), gate = Gate(), session = UUID()
        authority.beginSession(session)
        let autosave = NoteAutosaveCoordinator(authority: authority, delay: { await gate.pause() })
        var writes = 0
        let pending = try XCTUnwrap(autosave.schedule(session: session, authorize: { true }) { writes += 1; return true })
        try await gate.waitForCount(1)
        XCTAssertTrue(autosave.flush())
        XCTAssertFalse(autosave.flush())
        await gate.release(0); await pending.value
        XCTAssertEqual(writes, 1)
    }

    func testFailedStorageCommitDoesNotClaimSavedAndRetryClearsTheError() {
        let authority = DocumentPreviewService(), session = UUID()
        authority.beginSession(session)
        let autosave = NoteAutosaveCoordinator(authority: authority)
        XCTAssertFalse(autosave.saveNow(session: session, authorize: { true }) { false })
        XCTAssertNil(autosave.lastSavedAt)
        XCTAssertNotNil(autosave.error)
        XCTAssertTrue(autosave.saveNow(session: session, authorize: { true }) { true })
        XCTAssertNotNil(autosave.lastSavedAt)
        XCTAssertNil(autosave.error)
    }

    func testRealAuthenticationBackgroundLogoutGuestAndNewOwnerSessionBoundaries() async throws {
        let authority = DocumentPreviewService()
        let credentials = KeychainService(service: "note-auth-" + UUID().uuidString)
        try credentials.savePassword("owner-note-password")
        try credentials.saveGuestPassword("guest-note-password")
        let auth = AuthenticationViewModel(keychainService: credentials, manageInstallationState: false, documentPreviewService: authority)
        defer { auth.logout(); credentials.clearAllKeychainData() }
        let autosave = NoteAutosaveCoordinator(authority: authority)
        var writes = 0
        let ownerAvailable: @MainActor () -> Bool = { auth.isAuthenticated && GuestModeManager.shared.isOwnerMode }
        auth.password = "owner-note-password"
        await (try XCTUnwrap(auth.login())).value
        let firstOwner = auth.librarySessionID
        XCTAssertTrue(autosave.saveNow(session: firstOwner, authorize: ownerAvailable) { writes += 1; return true })
        auth.suspendAlbumAccess()
        XCTAssertFalse(autosave.saveNow(session: firstOwner, authorize: ownerAvailable) { writes += 1; return true })
        auth.resumeAlbumAccess()
        auth.logout()
        XCTAssertFalse(autosave.saveNow(session: firstOwner, authorize: ownerAvailable) { writes += 1; return true })
        auth.password = "guest-note-password"
        await (try XCTUnwrap(auth.login())).value
        XCTAssertTrue(GuestModeManager.shared.isGuestMode)
        XCTAssertFalse(autosave.saveNow(session: auth.librarySessionID, authorize: ownerAvailable) { writes += 1; return true })
        auth.logout()
        auth.password = "owner-note-password"
        await (try XCTUnwrap(auth.login())).value
        XCTAssertNotEqual(auth.librarySessionID, firstOwner)
        XCTAssertFalse(autosave.saveNow(session: firstOwner, authorize: ownerAvailable) { writes += 1; return true })
        XCTAssertTrue(autosave.saveNow(session: auth.librarySessionID, authorize: ownerAvailable) { writes += 1; return true })
        XCTAssertEqual(writes, 2)
    }
}
