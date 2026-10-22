import Foundation
import Testing
@testable import WagLock

@MainActor
struct PasswordInputPolicyTests {
    @Test func mainAndGuestAcceptTheSameCredentials() {
        for password in ["", "12345", "135790", "a text password", "  space preserved  ",
                         "cafe\u{301}-long-password", String(repeating: "x", count: 128), String(repeating: "x", count: 129)] {
            #expect(KeychainService.validateGuestPassword(password).isValid == KeychainService.validatePasswordStrength(password).isValid)
        }
        #expect(KeychainService.validateGuestPassword("a text password").isValid)
        #expect(!KeychainService.validateGuestPassword(String(repeating: "x", count: 129)).isValid)
    }

    @Test func textGuestPasswordPreservesExactUnicodeAndNumericCompatibility() throws {
        let storage = PasswordInputStorage()
        let keychain = KeychainService(service: "input-policy-fixture", storage: storage)
        try keychain.savePassword("main-password")
        try keychain.saveGuestPassword("135790")
        #expect(keychain.verifyGuestPassword("135790"))
        let password = " cafe\u{301}-guest password "
        try keychain.saveGuestPassword(password)
        #expect(keychain.verifyGuestPassword(password))
        #expect(!keychain.verifyGuestPassword(" café-guest password "))
        #expect(!keychain.verifyGuestPassword(password.trimmingCharacters(in: .whitespaces)))
        #expect(!keychain.verifyGuestPassword("135790"))
        let before = storage.items
        #expect(throws: (any Error).self) { try keychain.saveGuestPassword("main-password") }
        #expect(storage.items == before)
        #expect(keychain.verifyPassword("main-password"))
    }

    @Test func obviousWeakPatternsDoNotEarnHighScores() {
        for password in ["123456", "111111", "abcdef", "Password1!", "121212121212", "abcabcabcabc", "password password password", "violet-harbor-violet-harbor"] {
            #expect(PasswordAssessment(password).score < 30)
        }
        #expect(PasswordAssessment("violet harbor lantern bicycle 57").score > PasswordAssessment("593817").score)
        #expect(PasswordAssessment("").score == 0)
    }

    @Test func scoreIsBoundedAndDoesNotAlterInput() {
        let password = " cafe\u{301} 🚲 "+String(repeating: "broad horizon ", count: 20)
        let original = Array(password.utf8)
        let assessment = PasswordAssessment(password)
        #expect((0...100).contains(assessment.score))
        #expect(assessment == PasswordAssessment(password))
        #expect(Array(password.utf8) == original)
    }
}

@MainActor
private final class PasswordInputStorage: KeychainStorage {
    var items: [String: Data] = [:]
    func read(account: String) throws -> Data {
        guard let data = items[account] else { throw KeychainError.itemNotFound }
        return data
    }
    func write(account: String, data: Data, createOnly: Bool) throws {
        if createOnly && items[account] != nil { throw KeychainError.duplicateItem }
        items[account] = data
    }
    func delete(account: String) throws { items.removeValue(forKey: account) }
}
