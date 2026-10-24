import Foundation
import XCTest
@testable import WagLock

@MainActor
final class DocumentPreviewSecurityTests: XCTestCase {
    private actor Gate {
        private var paused = false
        private var continuation: CheckedContinuation<Void, Never>?
        func pause() async { paused = true; await withCheckedContinuation { continuation = $0 } }
        func wait() async throws {
            let deadline = Date().addingTimeInterval(5)
            while !paused {
                if Date() >= deadline { throw CancellationError() }
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    func testInactiveOrWrongSessionDoesNotStartLoader() {
        let service = DocumentPreviewService()
        var reads = 0
        let model = DocumentPreviewModel(service: service) { _, _, _ in reads += 1; return Data() }
        let session = UUID()
        XCTAssertNil(model.load(path: "absent", password: "key", fileExtension: ".txt", sessionID: session))
        service.beginSession(session)
        XCTAssertNil(model.load(path: "absent", password: "key", fileExtension: ".txt", sessionID: UUID()))
        XCTAssertNil(model.load(path: "absent", password: "", fileExtension: ".txt", sessionID: session))
        XCTAssertEqual(reads, 0)
        XCTAssertNil(model.data)
        XCTAssertFalse(model.isLoading)
    }

    func testRealEncryptedDocumentRoundTripAndRevocationClearsLoadedData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("document-preview-" + UUID().uuidString)
        let storage = FileStorageService(directory: root.appendingPathComponent("media"), availableCapacity: { _ in 1_000_000_000 })
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let bytes = Data("Disposable document — café".utf8)
        try bytes.write(to: source)
        let path = try storage.saveEncryptedFile(from: source, password: "fixture-key")
        let service = DocumentPreviewService()
        let session = UUID()
        service.beginSession(session)
        let model = DocumentPreviewModel(service: service) { path, password, ext in
            try await storage.loadDecryptedDataAsync(path: path, password: password, preferredExtension: ext)
        }
        await model.load(path: path, password: "fixture-key", fileExtension: ".txt", sessionID: session)?.value
        XCTAssertEqual(model.data, bytes)
        XCTAssertNil(model.error)
        service.endSession(matching: session)
        XCTAssertNil(model.data)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(storage.fileExists(path: path))
        service.beginSession(session)
        await model.load(path: path, password: "wrong-key", fileExtension: ".txt", sessionID: session)?.value
        XCTAssertNil(model.data)
        XCTAssertEqual(model.error, "Unable to open this document. Try again after unlocking.")
        XCTAssertFalse(model.error!.contains(root.path))
    }

    func testRevokedLateSuccessAndErrorAreDiscardedEvenAfterSameSessionResumes() async throws {
        for fail in [false, true] {
            let service = DocumentPreviewService()
            let session = UUID()
            service.beginSession(session)
            let gate = Gate()
            let model = DocumentPreviewModel(service: service) { _, _, _ in
                await gate.pause()
                if fail { throw NSError(domain: "/private/sensitive-path", code: 1) }
                return Data("late plaintext".utf8)
            }
            let task = try XCTUnwrap(model.load(path: "snapshot", password: "key", fileExtension: ".pdf", sessionID: session))
            try await gate.wait()
            service.endSession(matching: session)
            service.beginSession(session)
            await gate.release()
            await task.value
            XCTAssertNil(model.data)
            XCTAssertNil(model.error)
            XCTAssertFalse(model.isLoading)
        }
    }

    func testNewRequestSurvivesOldCompletionAndObsoleteSessionRevocation() async throws {
        let service = DocumentPreviewService()
        let oldSession = UUID()
        service.beginSession(oldSession)
        let gate = Gate()
        let model = DocumentPreviewModel(service: service) { path, _, _ in
            if path == "old" { await gate.pause() }
            return Data(path.utf8)
        }
        let old = try XCTUnwrap(model.load(path: "old", password: "key", fileExtension: ".txt", sessionID: oldSession))
        try await gate.wait()
        let newSession = UUID()
        service.beginSession(newSession)
        await model.load(path: "new", password: "new-key", fileExtension: ".txt", sessionID: newSession)?.value
        service.endSession(matching: oldSession)
        await gate.release()
        await old.value
        XCTAssertEqual(model.data, Data("new".utf8))
        XCTAssertTrue(service.permits(newSession, revision: service.revision))
    }

    func testClosingOneViewDoesNotClearAnotherAndLateResultCannotReopenIt() async throws {
        let service = DocumentPreviewService()
        let session = UUID()
        service.beginSession(session)
        let gate = Gate()
        let first = DocumentPreviewModel(service: service) { _, _, _ in await gate.pause(); return Data("old".utf8) }
        let second = DocumentPreviewModel(service: service) { _, _, _ in Data("retained".utf8) }
        let task = try XCTUnwrap(first.load(path: "one", password: "key", fileExtension: ".txt", sessionID: session))
        try await gate.wait()
        await second.load(path: "two", password: "key", fileExtension: ".txt", sessionID: session)?.value
        first.clear()
        await gate.release()
        await task.value
        XCTAssertNil(first.data)
        XCTAssertEqual(second.data, Data("retained".utf8))
        service.endSession()
        XCTAssertNil(second.data)
    }

    func testAuthenticationBackgroundLogoutAndGuestDoNotRetainOwnerCapability() async throws {
        let service = DocumentPreviewService()
        let credentials = KeychainService(service: "document-auth-" + UUID().uuidString)
        try credentials.savePassword("owner-preview-password")
        try credentials.saveGuestPassword("guest-preview-password")
        let auth = AuthenticationViewModel(keychainService: credentials, manageInstallationState: false, documentPreviewService: service)
        defer { auth.logout(); credentials.clearAllKeychainData() }
        auth.password = "owner-preview-password"
        await (try XCTUnwrap(auth.login())).value
        let session = auth.librarySessionID
        let model = DocumentPreviewModel(service: service) { _, _, _ in Data("owner".utf8) }
        await model.load(path: "owner", password: "key", fileExtension: ".pdf", sessionID: session)?.value
        XCTAssertNotNil(model.data)
        auth.suspendAlbumAccess()
        XCTAssertNil(model.data)
        XCTAssertNil(model.load(path: "owner", password: "key", fileExtension: ".pdf", sessionID: session))
        auth.resumeAlbumAccess()
        XCTAssertNotEqual(auth.librarySessionID, session)
        XCTAssertNil(model.load(path: "owner", password: "key", fileExtension: ".pdf", sessionID: session))
        await model.load(path: "owner", password: "key", fileExtension: ".pdf", sessionID: auth.librarySessionID)?.value
        XCTAssertNotNil(model.data)
        auth.logout()
        XCTAssertNil(model.data)
        auth.password = "guest-preview-password"
        await (try XCTUnwrap(auth.login())).value
        XCTAssertTrue(GuestModeManager.shared.isGuestMode)
        XCTAssertNil(model.load(path: "owner", password: "key", fileExtension: ".pdf", sessionID: auth.librarySessionID))
    }
}
