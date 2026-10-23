import Foundation
import Security
import XCTest
@testable import WagLock

@MainActor
final class InMemoryAttemptStorage: KeychainStorage {
    nonisolated deinit { }
    var values: [String: Data] = [:]
    var unavailable = false
    var failWrites = false
    func read(account: String) throws -> Data {
        if unavailable { throw KeychainError.unexpectedStatus(errSecInteractionNotAllowed) }
        guard let value = values[account] else { throw KeychainError.itemNotFound }; return value
    }
    func write(account: String, data: Data, createOnly: Bool) throws {
        if failWrites { throw KeychainError.unexpectedStatus(errSecInteractionNotAllowed) }
        values[account] = data
    }
    func delete(account: String) throws { values.removeValue(forKey: account) }
}

@MainActor
final class PasswordAttemptLimiterTests: XCTestCase {
    func testReservationsSurviveNewInstancesAndCooldownGrowsWithoutDeletingAnything() throws {
        let storage = InMemoryAttemptStorage()
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let make = { PasswordAttemptLimiter(storage: storage, scope: "vault", now: { date }) }
        for _ in 0..<5 { _ = try make().reserve() }
        XCTAssertThrowsError(try make().reserve())
        XCTAssertEqual(try make().status().failures, 5)
        date = date.addingTimeInterval(301)
        _ = try make().reserve()
        XCTAssertEqual(try make().status().blockedUntil, date.addingTimeInterval(600))
        XCTAssertThrowsError(try make().reserve())
        date = date.addingTimeInterval(-100)
        XCTAssertThrowsError(try make().reserve(), "A clock rollback must not reset the budget")
        XCTAssertEqual(storage.values.count, 1)
    }

    func testScopesAreIndependentAndStaleSuccessCannotResetANewerReservation() throws {
        let storage = InMemoryAttemptStorage()
        let first = PasswordAttemptLimiter(storage: storage, scope: "first")
        let second = PasswordAttemptLimiter(storage: storage, scope: "second")
        let old = try first.reserve(); let current = try first.reserve()
        XCTAssertThrowsError(try first.recordSuccess(old))
        XCTAssertEqual(try first.status().failures, 2)
        XCTAssertEqual(try second.status().failures, 0)
        try first.recordSuccess(current)
        XCTAssertEqual(try first.status().failures, 0)
    }

    func testUnavailableCorruptAndUnwritableStateRejectBeforeVerification() throws {
        let storage = InMemoryAttemptStorage()
        let limiter = PasswordAttemptLimiter(storage: storage, scope: "vault")
        storage.unavailable = true; XCTAssertThrowsError(try limiter.reserve())
        storage.unavailable = false; storage.failWrites = true
        XCTAssertThrowsError(try limiter.reserve()); XCTAssertTrue(storage.values.isEmpty)
        storage.failWrites = false; _ = try limiter.reserve()
        let key = try XCTUnwrap(storage.values.keys.first)
        storage.values[key] = Data("not a limiter record".utf8)
        XCTAssertThrowsError(try limiter.reserve())
        XCTAssertEqual(storage.values[key], Data("not a limiter record".utf8))
    }

    func testRealAuthenticationBudgetPersistsAcrossViewModelRecreationAndSuccessResets() async throws {
        let storage = InMemoryAttemptStorage()
        let keychain = KeychainService(service: UUID().uuidString, storage: storage)
        try keychain.savePassword("PUBLIC-owner-password")
        for _ in 0..<5 {
            let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false)
            auth.password = "PUBLIC-wrong-password"; await auth.login()?.value
            XCTAssertFalse(auth.isAuthenticated)
        }
        let blocked = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false)
        blocked.password = "PUBLIC-owner-password"
        XCTAssertNil(blocked.login()); XCTAssertFalse(blocked.isAuthenticated)
        var date = Date().addingTimeInterval(301)
        let limiter = keychain.passwordAttemptLimiter(now: { date })
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false, attemptLimiter: limiter)
        auth.password = "PUBLIC-owner-password"; await auth.login()?.value
        XCTAssertTrue(auth.isAuthenticated); auth.logout()
        date = date.addingTimeInterval(1)
        XCTAssertEqual(try limiter.status().failures, 0)
        let fresh = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false)
        fresh.password = "PUBLIC-owner-password"; await fresh.login()?.value
        XCTAssertTrue(fresh.isAuthenticated); fresh.logout()
    }
}
