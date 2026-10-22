import Foundation
import XCTest
@testable import WagLock

@MainActor
final class AuthenticationSessionLifecycleTests: XCTestCase {
    private let password = "disposable-owner-passcode"
    private let guestPassword = "135790"

    private func keychain() throws -> KeychainService {
        let service = KeychainService(service: "waglock-session-test-" + UUID().uuidString)
        try service.savePassword(password)
        return service
    }

    func testDataKeyResultAfterLogoutCannotRestoreAuthentication() async throws {
        let service = try keychain()
        let gate = Gate()
        let auth = AuthenticationViewModel(keychainService: service, manageInstallationState: false,
                                           dataPasswordLoader: { _ in try await gate.wait() })
        defer { auth.logout(); service.clearAllKeychainData() }
        auth.password = password
        let task = try XCTUnwrap(auth.login())
        try await gate.waitUntilRequested()
        let previous = auth.librarySessionID
        auth.logout()
        let locked = auth.librarySessionID
        XCTAssertNotEqual(locked, previous)
        gate.resume(password)
        await task.value
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertFalse(auth.isProcessing)
        XCTAssertNil(auth.sessionPassword)
        XCTAssertEqual(auth.librarySessionID, locked)
        XCTAssertEqual(GuestModeManager.shared.currentMode, .unauthenticated)
        XCTAssertTrue(service.verifyPassword(password))
    }

    func testLateOwnerResultCannotReplaceTheNewGuestSession() async throws {
        let service = try keychain()
        try service.saveGuestPassword(guestPassword)
        let gate = Gate()
        let auth = AuthenticationViewModel(keychainService: service, manageInstallationState: false,
                                           dataPasswordLoader: { _ in try await gate.wait() })
        defer { auth.logout(); service.clearAllKeychainData() }
        auth.password = password
        let first = try XCTUnwrap(auth.login())
        try await gate.waitUntilRequested()
        auth.logout()
        auth.password = guestPassword
        await (try XCTUnwrap(auth.login())).value
        let guestID = auth.librarySessionID
        XCTAssertTrue(GuestModeManager.shared.isGuestMode)
        gate.resume(password)
        await first.value
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertTrue(GuestModeManager.shared.isGuestMode)
        XCTAssertEqual(auth.sessionPassword, guestPassword)
        XCTAssertEqual(auth.librarySessionID, guestID)
        XCTAssertNil(auth.errorMessage)
    }

    func testOldFailureDoesNotClearNewLoginProgressOrPublishAnError() async throws {
        let service = try keychain()
        let firstGate = Gate(), secondGate = Gate()
        var loads = 0
        let auth = AuthenticationViewModel(keychainService: service, manageInstallationState: false,
                                           dataPasswordLoader: { _ in
            loads += 1
            return try await (loads == 1 ? firstGate : secondGate).wait()
        })
        defer { auth.logout(); service.clearAllKeychainData() }
        auth.password = password
        let first = try XCTUnwrap(auth.login())
        try await firstGate.waitUntilRequested()
        auth.logout()
        auth.password = password
        let second = try XCTUnwrap(auth.login())
        try await secondGate.waitUntilRequested()
        firstGate.fail()
        await first.value
        XCTAssertTrue(auth.isProcessing)
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(auth.errorMessage)
        secondGate.resume(password)
        await second.value
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertFalse(auth.isProcessing)
        XCTAssertTrue(GuestModeManager.shared.isOwnerMode)
        XCTAssertEqual(auth.sessionPassword, password)
    }

    func testBackgroundInvalidatesPendingUnlockButPreservesCredentials() async throws {
        let service = try keychain()
        let gate = Gate()
        let auth = AuthenticationViewModel(keychainService: service, manageInstallationState: false,
                                           dataPasswordLoader: { _ in try await gate.wait() })
        defer { auth.logout(); service.clearAllKeychainData() }
        auth.password = password
        let task = try XCTUnwrap(auth.login())
        try await gate.waitUntilRequested()
        auth.suspendAlbumAccess()
        gate.resume(password)
        await task.value
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertFalse(auth.isProcessing)
        XCTAssertNil(auth.sessionPassword)
        XCTAssertNil(auth.errorMessage)
        XCTAssertTrue(service.verifyPassword(password))
        XCTAssertEqual(try service.retrieveDataPassword(using: password), password)
    }

    func testQueuedSetupCannotCreateCredentialsAfterLock() async {
        let service = KeychainService(service: "waglock-cancelled-setup-" + UUID().uuidString)
        let auth = AuthenticationViewModel(keychainService: service, manageInstallationState: false)
        defer { auth.logout(); service.clearAllKeychainData() }
        auth.password = password
        auth.confirmPassword = password
        auth.setupPassword()
        auth.logout() // runs before the queued MainActor setup task
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertFalse(auth.isProcessing)
        XCTAssertFalse(service.isPasswordSet())
    }

    func testCalculatorNotificationWaitsForVerifiedDataKey() async throws {
        let service = try keychain()
        let gate = Gate()
        let auth = AuthenticationViewModel(keychainService: service, manageInstallationState: false,
                                           dataPasswordLoader: { _ in try await gate.wait() })
        defer { auth.logout(); service.clearAllKeychainData() }
        NotificationCenter.default.post(name: .unlockFromDisguise, object: nil,
                                        userInfo: ["mode": "owner", "password": password])
        try await gate.waitUntilRequested()
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(auth.sessionPassword)
        gate.resume(password)
        let deadline = Date().addingTimeInterval(5)
        while !auth.isAuthenticated && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertTrue(GuestModeManager.shared.isOwnerMode)
        XCTAssertEqual(auth.sessionPassword, password)
    }

    private enum TestFailure: Error { case injected, timedOut }
    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<String, Error>?
        func wait() async throws -> String {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func waitUntilRequested() async throws {
            let deadline = Date().addingTimeInterval(5)
            while continuation == nil {
                guard Date() < deadline else { throw TestFailure.timedOut }
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        func resume(_ secret: String) { continuation?.resume(returning: secret); continuation = nil }
        func fail() { continuation?.resume(throwing: TestFailure.injected); continuation = nil }
    }
}
