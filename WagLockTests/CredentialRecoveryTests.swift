import CryptoKit
import Foundation
import Security
import Testing

@testable import WagLock

@MainActor
@Suite(.serialized)
struct CredentialRecoveryTests {
    private let ownerAccount = "vaultito.owner-credentials.v1"

    private func fixture() -> (KeychainService, FaultKeychainStorage) {
        let storage = FaultKeychainStorage()
        return (KeychainService(service: "recovery-fixture", storage: storage), storage)
    }

    @Test func freshRandomSecretIsRetainedAcrossPasswordChange() throws {
        let storage = FaultKeychainStorage()
        var calls = 0
        let keychain = KeychainService(service: "fresh-secret-fixture", storage: storage, makeDataPassword: {
            calls += 1; return "PUBLIC-generated-independent-data-secret"
        })
        let secret = try keychain.savePassword("first-password")
        #expect(secret != "first-password")
        #expect(try keychain.retrieveDataPassword(using: "first-password") == secret)
        #expect(try keychain.changePassword(oldPassword: "first-password", newPassword: "changed-password") == secret)
        #expect(try keychain.retrieveDataPassword(using: "changed-password") == secret)
        #expect(!keychain.verifyPassword("first-password"))
        #expect(calls == 1)
    }
    @Test func failedFreshRandomGenerationLeavesNoCredentials() {
        let storage = FaultKeychainStorage()
        let keychain = KeychainService(service: "fresh-secret-failure", storage: storage, makeDataPassword: {
            throw EncryptionError.randomGenerationFailed
        })
        #expect(throws: (any Error).self) { try keychain.savePassword("first-password") }
        #expect(storage.items.isEmpty)
    }
    @Test func libraryIdentityCannotBeOverwrittenAndUnavailableIsNotAbsence() throws {
        let (keychain, storage) = fixture()
        #expect(try keychain.loadLibraryIdentity() == nil)
        let identity = Data(repeating: 7, count: 32)
        try keychain.establishLibraryIdentity(identity)
        #expect(try keychain.loadLibraryIdentity() == identity)
        #expect(throws: (any Error).self) { try keychain.establishLibraryIdentity(Data(repeating: 8, count: 32)) }
        storage.failReads = true
        #expect(throws: (any Error).self) { try keychain.loadLibraryIdentity() }
        #expect(storage.items["waglock.library-identity.v1"] == identity)
    }

    @Test func independentGuestRetainsIdentityAndSecretAcrossRestartAndPasswordChange() throws {
        let (keychain, storage) = fixture()
        let primary = try keychain.savePassword("primary-password")
        let guest = try keychain.provisionIndependentGuest(password: "secondary-password")
        #expect(guest.dataPassword != primary)
        #expect(guest.dataPassword != "secondary-password")
        #expect(try keychain.independentGuestVaultID() == guest.vaultID)
        let encrypted = try EncryptionService.shared.encrypt(data: Data("secondary fixture".utf8), password: guest.dataPassword)
        #expect(throws: (any Error).self) { try EncryptionService.shared.decrypt(encryptedData: encrypted, password: primary) }
        let restarted = KeychainService(service: "recovery-fixture", storage: storage)
        #expect(try restarted.unlockIndependentGuest(password: "secondary-password") == guest)
        #expect(try restarted.changeIndependentGuestPassword(oldPassword: "secondary-password", newPassword: "changed-secondary") == guest)
        #expect(throws: (any Error).self) { try restarted.unlockIndependentGuest(password: "secondary-password") }
        #expect(try restarted.unlockIndependentGuest(password: "changed-secondary") == guest)
        #expect(try restarted.retrieveDataPassword(using: "primary-password") == primary)
    }

    @Test func independentGuestRejectsAmbiguousPasswordsAndReplacement() throws {
        let (keychain, storage) = fixture()
        try keychain.savePassword("primary-password")
        #expect(throws: (any Error).self) { try keychain.provisionIndependentGuest(password: "primary-password") }
        try keychain.provisionIndependentGuest(password: "secondary-password")
        let previous = storage.items
        #expect(throws: (any Error).self) { try keychain.provisionIndependentGuest(password: "replacement-password") }
        #expect(throws: (any Error).self) { try keychain.changePassword(oldPassword: "primary-password", newPassword: "secondary-password") }
        #expect(throws: (any Error).self) { try keychain.changeIndependentGuestPassword(oldPassword: "secondary-password", newPassword: "primary-password") }
        #expect(storage.items == previous)
    }

    @Test func independentGuestFailedProvisionAndChangePreservePrimaryAndGuest() throws {
        let (keychain, storage) = fixture()
        try keychain.savePassword("primary-password")
        let primaryItems = storage.items
        storage.failWrites = true
        #expect(throws: (any Error).self) { try keychain.provisionIndependentGuest(password: "secondary-password") }
        #expect(storage.items == primaryItems)
        storage.failWrites = false
        let guest = try keychain.provisionIndependentGuest(password: "secondary-password")
        let bothItems = storage.items
        storage.failWrites = true
        #expect(throws: (any Error).self) { try keychain.changeIndependentGuestPassword(oldPassword: "secondary-password", newPassword: "changed-secondary") }
        #expect(storage.items == bothItems)
        #expect(try keychain.unlockIndependentGuest(password: "secondary-password") == guest)
    }

    @Test func independentGuestUnavailableOrCorruptRecordDoesNotBecomeAbsence() throws {
        let (keychain, storage) = fixture()
        try keychain.savePassword("primary-password")
        storage.failReads = true
        #expect(throws: (any Error).self) { try keychain.independentGuestVaultID() }
        #expect(throws: (any Error).self) { try keychain.provisionIndependentGuest(password: "secondary-password") }
        storage.failReads = false
        storage.items["waglock.secondary-credentials.v1"] = Data("broken".utf8)
        let previous = storage.items
        #expect(throws: (any Error).self) { try keychain.independentGuestVaultID() }
        #expect(throws: (any Error).self) { try keychain.provisionIndependentGuest(password: "secondary-password") }
        #expect(throws: (any Error).self) { try keychain.changePassword(oldPassword: "primary-password", newPassword: "changed-primary") }
        #expect(storage.items == previous)
    }

    @Test func independentGuestAuthenticatesServiceIdentityAndCiphertext() throws {
        let (keychain, storage) = fixture()
        try keychain.savePassword("primary-password")
        try keychain.provisionIndependentGuest(password: "secondary-password")
        let account = "waglock.secondary-credentials.v1"
        let original = try #require(storage.items[account])
        let otherService = KeychainService(service: "other-service", storage: storage)
        #expect(throws: (any Error).self) { try otherService.unlockIndependentGuest(password: "secondary-password") }
        #expect(throws: (any Error).self) { try keychain.unlockIndependentGuest(password: "primary-password") }
        var json = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        json["vaultID"] = UUID().uuidString
        storage.items[account] = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try keychain.unlockIndependentGuest(password: "secondary-password") }
        json = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        let encodedEnvelope = try #require(json["envelope"] as? String)
        var envelope = try #require(Data(base64Encoded: encodedEnvelope))
        envelope[envelope.count - 1] ^= 1
        json["envelope"] = envelope.base64EncodedString()
        storage.items[account] = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try keychain.unlockIndependentGuest(password: "secondary-password") }
        json["envelope"] = Data("not a modern wrapper".utf8).base64EncodedString()
        storage.items[account] = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try keychain.unlockIndependentGuest(password: "secondary-password") }
    }

    private func legacy(_ storage: FaultKeychainStorage, password: String = "legacy-password",
                        secret: String = "original-data-secret") throws {
        let salt = Data(repeating: 42, count: 16)
        storage.items = [
            "userPassword": Data(SHA256.hash(data: Data(password.utf8) + salt)),
            "passwordSalt": salt, "isPasswordSet": Data([1]),
            "dataEncryptionPassword": try EncryptionService.shared.encrypt(data: Data(secret.utf8), password: password),
        ]
    }

    @Test
    func failedPasswordChangePreservesCredentialsAndExistingMedia() throws {
        let (keychain, storage) = fixture()
        let secret = try keychain.savePassword("old-password")
        let media = try EncryptionService.shared.encrypt(data: Data("keep my media".utf8), password: secret)
        let previous = storage.items
        storage.failWrites = true
        #expect(throws: (any Error).self) {
            try keychain.changePassword(oldPassword: "old-password", newPassword: "new-password")
        }
        #expect(storage.items == previous)
        let restarted = KeychainService(service: "recovery-fixture", storage: storage)
        #expect(restarted.verifyPassword("old-password"))
        #expect(!restarted.verifyPassword("new-password"))
        let retained = try restarted.retrieveDataPassword(using: "old-password")
        #expect(try EncryptionService.shared.decrypt(encryptedData: media, password: retained) == Data("keep my media".utf8))
    }

    @Test
    func passwordChangeCommitsOneRecordAndPreservesTheDataKey() throws {
        let (keychain, storage) = fixture()
        try legacy(storage)
        storage.writes.removeAll()
        #expect(try keychain.changePassword(oldPassword: "legacy-password", newPassword: "new-password") == "original-data-secret")
        #expect(storage.writes == [ownerAccount])
        #expect(Set(storage.items.keys) == [ownerAccount])
        #expect(!keychain.verifyPassword("legacy-password"))
        #expect(keychain.verifyPassword("new-password"))
        #expect(try keychain.retrieveDataPassword(using: "new-password") == "original-data-secret")
    }

    @Test
    func failedLegacyPasswordChangeKeepsAllRecoveryMaterial() throws {
        let (keychain, storage) = fixture()
        try legacy(storage)
        let previous = storage.items
        storage.failWrites = true
        #expect(throws: (any Error).self) {
            try keychain.changePassword(oldPassword: "legacy-password", newPassword: "new-password")
        }
        #expect(storage.items == previous)
        storage.failWrites = false
        let restarted = KeychainService(service: "recovery-fixture", storage: storage)
        #expect(try restarted.retrieveDataPassword(using: "legacy-password") == "original-data-secret")
        #expect(storage.items == previous)
        try restarted.changePassword(oldPassword: "legacy-password", newPassword: "new-password")
        #expect(Set(storage.items.keys) == [ownerAccount])
    }

    @Test
    func anOwnerPasswordChangeCannotAdoptTheGuestPassword() throws {
        let (keychain, storage) = fixture()
        try keychain.savePassword("owner-password")
        try keychain.saveGuestPassword("135790")
        let previous = storage.items
        #expect(throws: (any Error).self) {
            try keychain.changePassword(oldPassword: "owner-password", newPassword: "135790")
        }
        #expect(storage.items == previous)
        #expect(keychain.verifyPassword("owner-password"))
        #expect(keychain.verifyGuestPassword("135790"))
    }

    @Test
    func committedRecordWinsWhenLegacyCleanupIsInterrupted() throws {
        let (keychain, storage) = fixture()
        try legacy(storage)
        storage.failDeletes = true
        try keychain.changePassword(oldPassword: "legacy-password", newPassword: "new-password")
        #expect(storage.items["userPassword"] != nil)
        let restarted = KeychainService(service: "recovery-fixture", storage: storage)
        #expect(!restarted.verifyPassword("legacy-password"))
        #expect(try restarted.retrieveDataPassword(using: "new-password") == "original-data-secret")
        storage.failDeletes = false
        #expect(try restarted.retrieveDataPassword(using: "new-password") == "original-data-secret")
        #expect(Set(storage.items.keys) == [ownerAccount])
    }

    @Test
    func corruptCurrentRecordNeverFallsBackToStaleLegacyCredentials() throws {
        let (keychain, storage) = fixture()
        try legacy(storage)
        storage.items[ownerAccount] = Data("corrupt record".utf8)
        let previous = storage.items
        #expect(keychain.isPasswordSet())
        #expect(!keychain.verifyPassword("legacy-password"))
        #expect(throws: (any Error).self) { try keychain.retrieveDataPassword(using: "legacy-password") }
        #expect(storage.items == previous)
    }

    @Test
    func unavailableKeychainAndPartialCredentialsCannotTriggerSetup() throws {
        let (keychain, storage) = fixture()
        storage.failReads = true
        #expect(keychain.isPasswordSet())
        #expect(throws: (any Error).self) { try keychain.savePassword("replacement-password") }
        #expect(storage.items.isEmpty)
        storage.failReads = false
        for account in ["userPassword", "passwordSalt", "isPasswordSet", "dataEncryptionPassword"] {
            storage.items = [account: Data([0])]
            #expect(keychain.isPasswordSet())
            #expect(throws: (any Error).self) { try keychain.savePassword("replacement-password") }
            #expect(storage.items.count == 1)
        }
    }

    @Test
    func damagedLegacyWrapperIsPreservedWithoutPromotion() throws {
        let (keychain, storage) = fixture()
        try legacy(storage)
        storage.items["dataEncryptionPassword"] = Data("damaged wrapper".utf8)
        let previous = storage.items
        #expect(!keychain.verifyPassword("legacy-password"))
        #expect(throws: (any Error).self) { try keychain.retrieveDataPassword(using: "legacy-password") }
        #expect(storage.items == previous)
    }

    @Test
    func failedSetupLeavesNoPartialCredentialsAndRetryWorks() throws {
        let (keychain, storage) = fixture()
        storage.failWrites = true
        #expect(throws: (any Error).self) { try keychain.savePassword("first-password") }
        #expect(!keychain.isPasswordSet())
        #expect(storage.items.isEmpty)
        storage.failWrites = false
        try keychain.savePassword("first-password")
        let previous = storage.items
        #expect(throws: (any Error).self) { try keychain.savePassword("replacement-password") }
        #expect(storage.items == previous)
        #expect(keychain.verifyPassword("first-password"))
    }

    @Test
    func copiedCredentialsCannotAuthenticateInAnotherNamespace() throws {
        let (keychain, storage) = fixture()
        try keychain.savePassword("fixture-password")
        let other = KeychainService(service: "another-namespace", storage: storage)
        #expect(!other.verifyPassword("fixture-password"))
        #expect(throws: (any Error).self) { try other.retrieveDataPassword(using: "fixture-password") }
    }

    @Test
    func oldAuthenticatedCredentialReadsWithoutConversionAndExplicitChangeUsesVersionedKDF() throws {
        let (keychain, storage) = fixture()
        let payload = #"{"version":1,"service":"recovery-fixture","dataPassword":"PUBLIC-preserved-secret"}"#
        let old = try EncryptionService.shared.encrypt(data: Data(payload.utf8), password: "old-password")
        storage.items[ownerAccount] = old
        #expect(try keychain.retrieveDataPassword(using: "old-password") == "PUBLIC-preserved-secret")
        #expect(storage.items[ownerAccount] == old)
        try keychain.changePassword(oldPassword: "old-password", newPassword: "new-password")
        #expect(storage.items[ownerAccount]?.starts(with: Data("WLPE".utf8)) == true)
        #expect(try keychain.retrieveDataPassword(using: "new-password") == "PUBLIC-preserved-secret")
        #expect(!keychain.verifyPassword("old-password"))
    }

    @Test
    func malformedVersionOrEmptyDataKeyNeverAuthenticates() throws {
        let (keychain, storage) = fixture()
        for payload in [
            #"{"version":2,"service":"recovery-fixture","dataPassword":"secret"}"#,
            #"{"version":1,"service":"recovery-fixture","dataPassword":""}"#,
        ] {
            storage.items[ownerAccount] = try EncryptionService.shared.encrypt(data: Data(payload.utf8), password: "fixture-password")
            #expect(!keychain.verifyPassword("fixture-password"))
        }
    }

    @Test
    func invalidOrWrongPasswordsNeverMutateCommittedCredentials() throws {
        let (keychain, storage) = fixture()
        try keychain.savePassword("fixture-password")
        let previous = storage.items
        for (old, new) in [("wrong-password", "new-password"), ("fixture-password", ""), ("fixture-password", "short")] {
            #expect(throws: (any Error).self) { try keychain.changePassword(oldPassword: old, newPassword: new) }
            #expect(storage.items == previous)
        }
    }

    @Test
    func missingPreferencesMarkerNeverDeletesCredentials() throws {
        let keychain = KeychainService(service: "vaultito-recovery-" + UUID().uuidString)
        defer { keychain.clearAllKeychainData() }
        let secret = try keychain.savePassword("fixture-password")
        let defaults = UserDefaults.standard
        let marker = AppConstants.UserDefaultsKeys.appInitialized
        let previous = defaults.object(forKey: marker)
        defer {
            if let previous { defaults.set(previous, forKey: marker) }
            else { defaults.removeObject(forKey: marker) }
        }
        defaults.removeObject(forKey: marker)
        let auth = AuthenticationViewModel(keychainService: keychain)
        #expect(auth.isPasswordSet)
        #expect(keychain.verifyPassword("fixture-password"))
        #expect(try keychain.retrieveDataPassword(using: "fixture-password") == secret)
    }

    @Test
    func legacyMissingWrapperCannotBeCreatedWithAnUnverifiedPassword() throws {
        let service = "vaultito-recovery-" + UUID().uuidString
        let keychain = KeychainService(service: service)
        defer { keychain.clearAllKeychainData() }
        let salt = Data(repeating: 42, count: 16)
        let hash = Data(SHA256.hash(data: Data("legacy-password".utf8) + salt))
        for (account, value) in [("userPassword", hash), ("passwordSalt", salt), ("isPasswordSet", Data([1]))] {
            let status = SecItemAdd([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: value,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ] as CFDictionary, nil)
            #expect(status == errSecSuccess)
        }
        #expect(throws: (any Error).self) {
            try keychain.retrieveDataPassword(using: "wrong-password")
        }
        #expect(try keychain.retrieveDataPassword(using: "legacy-password") == "legacy-password")
    }
}

@MainActor
private final class FaultKeychainStorage: KeychainStorage {
    var items: [String: Data] = [:]
    var writes: [String] = []
    var failReads = false
    var failWrites = false
    var failDeletes = false

    func read(account: String) throws -> Data {
        if failReads { throw KeychainError.unexpectedStatus(errSecInteractionNotAllowed) }
        guard let data = items[account] else { throw KeychainError.itemNotFound }
        return data
    }

    func write(account: String, data: Data, createOnly: Bool) throws {
        if failWrites { throw KeychainError.unexpectedStatus(errSecNotAvailable) }
        if createOnly, items[account] != nil { throw KeychainError.duplicateItem }
        items[account] = data
        writes.append(account)
    }

    func delete(account: String) throws {
        if failDeletes { throw KeychainError.unexpectedStatus(errSecInteractionNotAllowed) }
        items.removeValue(forKey: account)
    }
}
