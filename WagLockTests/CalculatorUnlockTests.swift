import Foundation
import Testing
@testable import WagLock

@MainActor
struct CalculatorUnlockTests {
    private final class Storage: KeychainStorage {
        var values: [String: Data] = [:]
        var failedAccount: String?
        var deletions: [String] = []
        func read(account: String) throws -> Data {
            guard let value = values[account] else { throw KeychainError.itemNotFound }; return value
        }
        func write(account: String, data: Data, createOnly: Bool) throws { values[account] = data }
        func delete(account: String) throws {
            deletions.append(account)
            if account == failedAccount { throw KeychainError.invalidData }
            values.removeValue(forKey: account)
        }
    }

    @Test func retiredCleanupTouchesOnlyCalculatorMaterial() throws {
        let storage = Storage()
        storage.values = ["disguisePassword": Data([1]), "isDisguisePasswordSet": Data([1]),
                          "vaultito.owner-credentials.v1": Data([2]), "waglock.library-identity.v1": Data([3]),
                          "secretNoteDraft": Data([4])]
        let keychain = KeychainService(service: UUID().uuidString, storage: storage)
        let suite = "calculator-retirement-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppConstants.UserDefaultsKeys.disguiseModeEnabled)
        defaults.set("PUBLIC-obsolete", forKey: AppConstants.UserDefaultsKeys.disguisePasswordSequence)
        try keychain.retireCalculatorCredentials(defaults: defaults)
        #expect(storage.values["disguisePassword"] == nil)
        #expect(storage.values["isDisguisePasswordSet"] == nil)
        #expect(storage.values["vaultito.owner-credentials.v1"] == Data([2]))
        #expect(storage.values["waglock.library-identity.v1"] == Data([3]))
        #expect(storage.values["secretNoteDraft"] == Data([4]))
        #expect(!defaults.bool(forKey: AppConstants.UserDefaultsKeys.disguiseModeEnabled))
        #expect(defaults.object(forKey: AppConstants.UserDefaultsKeys.disguisePasswordSequence) == nil)
    }

    @Test func cleanupFailureIsReportedAndBothObsoleteAccountsAreAttempted() throws {
        let storage = Storage(); storage.failedAccount = "disguisePassword"
        storage.values = ["disguisePassword": Data([1]), "isDisguisePasswordSet": Data([1]), "userPassword": Data([2])]
        let keychain = KeychainService(service: UUID().uuidString, storage: storage)
        #expect(throws: (any Error).self) { try keychain.retireCalculatorCredentials() }
        #expect(storage.deletions == ["disguisePassword", "isDisguisePasswordSet"])
        #expect(storage.values["userPassword"] == Data([2]))
        storage.failedAccount = nil; try keychain.retireCalculatorCredentials()
        #expect(storage.values["disguisePassword"] == nil)
    }

    @Test func arithmeticAndStaleNotificationsCannotAuthenticate() async throws {
        let keychain = KeychainService(service: "calculator-retired-" + UUID().uuidString)
        defer { keychain.clearAllKeychainData() }
        try keychain.savePassword("246810")
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false)
        let calculator = CalculatorViewModel()
        for _ in 0..<10 {
            for number in [2, 4, 6, 8, 1, 0] { calculator.numberPressed(number) }
            calculator.equalsPressed()
        }
        #expect(!calculator.shouldUnlock)
        NotificationCenter.default.post(name: .unlockFromDisguise, object: nil,
            userInfo: ["mode": "owner", "password": "246810"])
        await Task.yield()
        #expect(!auth.isAuthenticated)
        auth.password = "246810"
        await auth.login()?.value
        #expect(auth.isAuthenticated)
        auth.logout()
    }

    @Test func passwordChangeRemovesOldCopyWithoutChangingDataSecret() throws {
        let storage = Storage()
        let keychain = KeychainService(service: UUID().uuidString, storage: storage)
        let secret = try keychain.savePassword("PUBLIC-old-password")
        storage.values["disguisePassword"] = Data([1]); storage.values["isDisguisePasswordSet"] = Data([1])
        #expect(try keychain.changePassword(oldPassword: "PUBLIC-old-password", newPassword: "PUBLIC-new-password") == secret)
        #expect(try keychain.retrieveDataPassword(using: "PUBLIC-new-password") == secret)
        #expect(!keychain.verifyPassword("PUBLIC-old-password"))
        #expect(storage.values["disguisePassword"] == nil)
        #expect(storage.values["isDisguisePasswordSet"] == nil)
    }
}
