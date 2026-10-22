import Foundation
import LocalAuthentication
import Security
import XCTest
@testable import WagLock

@MainActor
final class BiometricCommitAuthorizationTests: XCTestCase {
    private let account = "disposable-biometric-account"
    private func query(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    private func installSentinel(_ service: String) throws {
        var request = query(service)
        request[kSecValueData as String] = Data("existing-disposable-secret".utf8)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        XCTAssertEqual(SecItemAdd(request as CFDictionary, nil), errSecSuccess)
    }
    private func assertSentinelUnchanged(_ service: String) {
        var request = query(service)
        request[kSecReturnData as String] = true
        var data: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(request as CFDictionary, &data), errSecSuccess)
        XCTAssertEqual(data as? Data, Data("existing-disposable-secret".utf8))
    }

    func testRevokedEnrollmentCannotOverwriteAnExistingBiometricAccount() async throws {
        let service = "waglock-biometric-commit-" + UUID().uuidString
        try installSentinel(service)
        defer { SecItemDelete(query(service) as CFDictionary) }
        let gate = Gate()
        var authorized = true
        let store = BiometricSecretStore(service: service, authenticate: { _ in await gate.wait() })
        let pending = Task { try await store.store("stale-secret", account: account, authorizing: { authorized }) }
        try await gate.waitUntilRequested()
        authorized = false
        gate.resume()
        switch await pending.result {
        case .success: XCTFail("Revoked enrollment committed")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        assertSentinelUnchanged(service)
    }

    func testCancelledEnrollmentCannotOverwriteAnExistingBiometricAccount() async throws {
        let service = "waglock-biometric-cancel-" + UUID().uuidString
        try installSentinel(service)
        defer { SecItemDelete(query(service) as CFDictionary) }
        let gate = Gate()
        let store = BiometricSecretStore(service: service, authenticate: { _ in await gate.wait() })
        let pending = Task { try await store.store("cancelled-secret", account: account, authorizing: { true }) }
        try await gate.waitUntilRequested()
        pending.cancel()
        gate.resume()
        switch await pending.result {
        case .success: XCTFail("Cancelled enrollment committed")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        assertSentinelUnchanged(service)
    }

    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<LAContext, Never>?
        func wait() async -> LAContext { await withCheckedContinuation { continuation = $0 } }
        func waitUntilRequested() async throws {
            let deadline = Date().addingTimeInterval(5)
            while continuation == nil {
                if Date() > deadline { throw CancellationError() }
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        func resume() { continuation?.resume(returning: LAContext()); continuation = nil }
    }
}
