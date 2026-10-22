import Foundation
import XCTest
@testable import WagLock

@MainActor
final class ExportSessionSecurityTests: XCTestCase {
    private let password = "synthetic-export-secret"
    private var root: URL!
    private var storage: FileStorageService!
    private var exports: ExportService!
    private var session: UUID!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("export-security-" + UUID().uuidString)
        storage = FileStorageService(directory: root.appendingPathComponent("media", isDirectory: true), availableCapacity: { _ in 1_000_000_000 })
        exports = ExportService(storage: storage, directory: root.appendingPathComponent("exports", isDirectory: true))
        session = UUID()
        exports.beginSession(session)
    }
    override func tearDownWithError() throws {
        exports.endSession()
        try? FileManager.default.removeItem(at: root)
    }
    private func item(_ name: String = "sample", bytes: Data = Data("synthetic original".utf8)) throws -> MediaItem {
        let source = root.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: source)
        let path = try storage.saveEncryptedFile(from: source, password: password)
        try FileManager.default.removeItem(at: source)
        return MediaItem(fileName: name, fileExtension: ".txt", fileSize: Int64(bytes.count), type: .document, encryptedPath: path)
    }
    private func export(_ items: [MediaItem], using service: ExportService? = nil) async throws -> [URL] {
        let service = service ?? exports!
        return try await withCheckedThrowingContinuation { continuation in
            service.exportItems(items, password: password, sessionID: session) { continuation.resume(with: $0.mapError { $0 as Error }) }
        }
    }
    private var outputs: [URL] { (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("exports"), includingPropertiesForKeys: nil)) ?? [] }

    func testInactiveAndWrongSessionRejectBeforeReadingMedia() {
        let absent = MediaItem(fileName: "absent", fileExtension: ".txt", fileSize: 0, type: .document, encryptedPath: "/not/a/source")
        var results: [ExportError] = []
        let first = exports.exportItems([absent], password: password, sessionID: UUID()) {
            if case .failure(let error) = $0 { results.append(error) }
        }
        XCTAssertNil(first)
        exports.endSession()
        XCTAssertNil(exports.exportItems([absent], password: password, sessionID: session) {
            if case .failure(let error) = $0 { results.append(error) }
        })
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { if case .cancelled = $0 { return true }; return false })
        XCTAssertTrue(outputs.isEmpty)
    }

    func testRoundTripCollisionNamesAndIndependentCleanup() async throws {
        let first = try item("same", bytes: Data("first".utf8))
        let second = try item("same", bytes: Data("second".utf8))
        let urls = try await export([first, second])
        XCTAssertEqual(urls.map(\.lastPathComponent), ["same.txt", "same (2).txt"])
        XCTAssertEqual(try Data(contentsOf: urls[0]), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: urls[1]), Data("second".utf8))
        let another = try await export([second])
        XCTAssertNotEqual(urls[0].deletingLastPathComponent(), another[0].deletingLastPathComponent())
        exports.cleanupExportedFiles(urls)
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].path))
        XCTAssertEqual(try Data(contentsOf: another[0]), Data("second".utf8))
        // A repeated completion from an old share cannot remove the newer job.
        exports.cleanupExportedFiles(urls)
        XCTAssertTrue(FileManager.default.fileExists(atPath: another[0].path))
        XCTAssertTrue(storage.fileExists(path: first.encryptedPath))
        exports.endSession()
        XCTAssertFalse(FileManager.default.fileExists(atPath: another[0].path))
        XCTAssertTrue(outputs.isEmpty)
    }

    func testPartialFailureCleansOnlyItsOwnOutput() async throws {
        let good = try item("valid")
        let retained = try await export([good])
        let corrupt = try item("corrupt")
        try Data("invalid ciphertext".utf8).write(to: storage.getFileURL(for: corrupt.encryptedPath))
        do { _ = try await export([good, corrupt]); XCTFail("Expected corruption failure") }
        catch { XCTAssertTrue(error is ExportError) }
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained[0].path))
        XCTAssertTrue(storage.fileExists(path: good.encryptedPath))
        XCTAssertTrue(storage.fileExists(path: corrupt.encryptedPath))
    }

    func testNamesCannotEscapeOutputDirectory() async throws {
        let malicious = try item("../../outside/escape\\name:")
        let urls = try await export([malicious])
        let job = try XCTUnwrap(exports.jobID(for: urls))
        XCTAssertTrue(exports.isReady(job))
        XCTAssertEqual(urls[0].deletingLastPathComponent().lastPathComponent, job.uuidString)
        XCTAssertEqual(urls[0].deletingLastPathComponent().deletingLastPathComponent().path, root.appendingPathComponent("exports").path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("outside").path))
    }

    func testForeignAndSymlinkSourcesAreRejectedWithoutRemovingOriginals() async throws {
        let valid = try item()
        let foreign = root.appendingPathComponent("foreign-ciphertext")
        try Data("keep foreign data".utf8).write(to: foreign)
        let suspect = MediaItem(fileName: "foreign", fileExtension: ".txt", fileSize: 17, type: .document, encryptedPath: foreign.path)
        do { _ = try await export([suspect]); XCTFail("Foreign source accepted") } catch { }
        let symlink = storage.getStorageDirectory().appendingPathComponent("linked.enc")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: storage.getFileURL(for: valid.encryptedPath))
        suspect.encryptedPath = "linked.enc"
        do { _ = try await export([suspect]); XCTFail("Symlink accepted") } catch { }
        XCTAssertTrue(outputs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: foreign), Data("keep foreign data".utf8))
        XCTAssertTrue(storage.fileExists(path: valid.encryptedPath))
    }

    func testBackgroundRevocationSuppressesLateOutputAndPreservesNewSession() async throws {
        let gate = Gate()
        let service = ExportService(storage: storage, directory: root.appendingPathComponent("exports", isDirectory: true)) { _, destination, _ in
            try Data("partial plaintext".utf8).write(to: destination)
            await gate.pause()
            try Data("finished plaintext".utf8).write(to: destination)
        }
        let oldSession = session!
        service.beginSession(oldSession)
        let media = try item()
        var oldCallbacks = 0
        service.exportItems([media], password: password, sessionID: oldSession,
                            progressHandler: { _, _ in oldCallbacks += 1 }) { _ in oldCallbacks += 1 }
        try await gate.waitUntilPaused()
        let drains = service.endSession(matching: oldSession)
        let newSession = UUID()
        service.beginSession(newSession)
        // The old writer is still suspended. No one else removes its directory while it writes.
        XCTAssertEqual(outputs.count, 1)
        await gate.release()
        for task in drains { await task.value }
        XCTAssertTrue(outputs.isEmpty)
        XCTAssertEqual(oldCallbacks, 0)
        // An obsolete session cannot revoke the replacement's export capability.
        service.endSession(matching: oldSession)
        let complete = expectation(description: "new session can export")
        service.exportItems([media], password: password, sessionID: newSession) { result in
            if case .success = result { complete.fulfill() }
        }
        await fulfillment(of: [complete], timeout: 5)
        XCTAssertEqual(outputs.count, 1)
        service.endSession()
        XCTAssertTrue(outputs.isEmpty)
    }

    func testMetadataIsSnapshottedBeforeBackgroundExecution() async throws {
        let media = try item("before", bytes: Data("original bytes".utf8))
        let gate = Gate()
        let service = ExportService(storage: storage, directory: root.appendingPathComponent("exports", isDirectory: true)) { source, destination, password in
            await gate.pause()
            try EncryptionService.shared.decryptFile(inputURL: source, to: destination, password: password)
        }
        service.beginSession(session)
        let complete = expectation(description: "snapshot exported")
        var urls: [URL] = []
        service.exportItems([media], password: password, sessionID: session) { result in
            if case .success(let result) = result { urls = result; complete.fulfill() }
        }
        try await gate.waitUntilPaused()
        media.fileName = "after"
        media.encryptedPath = "/foreign/changed.enc"
        await gate.release()
        await fulfillment(of: [complete], timeout: 5)
        XCTAssertEqual(urls.first?.lastPathComponent, "before.txt")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(urls.first)), Data("original bytes".utf8))
        service.endSession()
    }

    func testWrongPasswordAndSymlinkOutputRootPreserveSourcesAndForeignFiles() async throws {
        let media = try item()
        let finished = expectation(description: "wrong password rejected")
        exports.exportItems([media], password: "wrong-password", sessionID: session) { result in
            if case .failure(.decryptionFailed) = result { finished.fulfill() }
        }
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertTrue(outputs.isEmpty)
        XCTAssertTrue(storage.fileExists(path: media.encryptedPath))
        let target = root.appendingPathComponent("foreign")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let sentinel = target.appendingPathComponent("keep-me")
        try Data("unrelated output".utf8).write(to: sentinel)
        try FileManager.default.removeItem(at: root.appendingPathComponent("exports"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("exports"), withDestinationURL: target)
        do { _ = try await export([media]); XCTFail("Symlink output root accepted") } catch { }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("unrelated output".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), ["keep-me"])
    }

    func testExplicitCancellationDoesNotCancelAnotherOperation() async throws {
        let gate = Gate()
        let service = ExportService(storage: storage, directory: root.appendingPathComponent("exports", isDirectory: true)) { source, destination, password in
            if destination.lastPathComponent.hasPrefix("cancel") { await gate.pause() }
            try EncryptionService.shared.decryptFile(inputURL: source, to: destination, password: password)
        }
        service.beginSession(session)
        let cancelled = try item("cancel")
        let retained = try item("retained")
        var cancellations = 0
        let id = try XCTUnwrap(service.exportItems([cancelled], password: password, sessionID: session) { result in
            if case .failure(.cancelled) = result { cancellations += 1 }
        })
        try await gate.waitUntilPaused()
        let surviving = try await export([retained], using: service)
        let drain = service.cancelExport(id)
        await gate.release()
        await drain?.value
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: surviving[0].path))
        service.endSession()
    }

    func testRealAuthenticationLifecycleRevokesExportsAndGuestCannotUseOwnerService() async throws {
        let credentials = KeychainService(service: "export-auth-test-" + UUID().uuidString)
        try credentials.savePassword(password)
        try credentials.saveGuestPassword("guest-password")
        let auth = AuthenticationViewModel(keychainService: credentials, manageInstallationState: false, exportService: exports)
        defer { auth.logout(); credentials.clearAllKeychainData() }
        auth.password = password
        await (try XCTUnwrap(auth.login())).value
        session = auth.librarySessionID
        let media = try item()
        let first = try await export([media])
        auth.suspendAlbumAccess()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first[0].path))
        auth.resumeAlbumAccess()
        let second = try await export([media])
        auth.logout()
        XCTAssertFalse(FileManager.default.fileExists(atPath: second[0].path))
        auth.password = "guest-password"
        await (try XCTUnwrap(auth.login())).value
        XCTAssertTrue(GuestModeManager.shared.isGuestMode)
        XCTAssertTrue(auth.isAuthenticated)
        var rejected = false
        // Even knowing the fixture's real owner data key cannot authorize this guest session.
        XCTAssertNil(exports.exportItems([media], password: password, sessionID: auth.librarySessionID) { result in
            if case .failure(.cancelled) = result { rejected = true }
        })
        XCTAssertTrue(rejected)
        XCTAssertTrue(outputs.isEmpty)
        XCTAssertTrue(storage.fileExists(path: media.encryptedPath))
    }

    func testCleanupFailureRetriesOnlyRevokedOwnedOutput() async throws {
        let removal = RemovalFailure()
        let service = ExportService(storage: storage, directory: root.appendingPathComponent("exports", isDirectory: true),
                                    remove: { try removal.remove($0) })
        service.beginSession(session)
        let media = try item()
        let old = try await export([media], using: service)
        removal.setFailing(true)
        service.cleanupExportedFiles(old)
        XCTAssertNil(service.jobID(for: old))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old[0].path))
        let current = try await export([media], using: service)
        let unrelated = root.appendingPathComponent("exports/unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let sentinel = unrelated.appendingPathComponent("keep")
        try Data("unrelated".utf8).write(to: sentinel)
        removal.setFailing(false)
        service.retryCleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: old[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: current[0].path))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("unrelated".utf8))
        XCTAssertTrue(storage.fileExists(path: media.encryptedPath))
        service.endSession()
    }

    func testLegacyAbsoluteSourceInsideOwnerRootRemainsReadable() async throws {
        let media = try item("legacy")
        media.encryptedPath = storage.getFileURL(for: media.encryptedPath).path
        let urls = try await export([media])
        XCTAssertEqual(try Data(contentsOf: urls[0]), Data("synthetic original".utf8))
    }

    nonisolated private final class RemovalFailure: @unchecked Sendable {
        private let lock = NSLock()
        private var failing = false
        func setFailing(_ value: Bool) { lock.lock(); failing = value; lock.unlock() }
        func remove(_ url: URL) throws {
            lock.lock(); let shouldFail = failing; lock.unlock()
            if shouldFail { throw ExportError.exportFailed }
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    private actor Gate {
        private var paused = false
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func pause() async {
            if released { return }
            paused = true
            await withCheckedContinuation { continuation = $0 }
        }
        func waitUntilPaused() async throws {
            let deadline = Date().addingTimeInterval(5)
            while !paused {
                if Date() >= deadline { throw ExportError.exportFailed }
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }
}
