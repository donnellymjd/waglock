//
//  KeychainService.swift
//  WagLock
//
//  Keychain密码管理服务
//  功能：安全存储和验证用户密码
//

import CryptoKit
import Foundation
import Security
import UIKit

/// Keychain操作错误类型
enum KeychainError: Error {
    case duplicateItem  // 重复项
    case itemNotFound  // 项不存在
    case invalidData  // 无效数据
    case unexpectedStatus(OSStatus)  // 未预期的状态码

    var localizedDescription: String {
        switch self {
        case .duplicateItem:
            return String(localized: "keychain.error.duplicateItem")
        case .itemNotFound:
            return String(localized: "keychain.error.itemNotFound")
        case .invalidData:
            return String(localized: "keychain.error.invalidData")
        case .unexpectedStatus(let status):
            return String(
                format: String(localized: "keychain.error.status"),
                status)
        }
    }
}

/// Keychain密码管理服务
/// Owner verification and data-secret wrapping share one authenticated record.
/// Legacy salted SHA-256 credentials remain readable until successful promotion.
/// 安全级别：kSecAttrAccessibleWhenUnlockedThisDeviceOnly
class KeychainService: LibraryIdentityAnchor {
    // Avoid the isolated-deinit back-deployment path when a scoped instance is released
    // from a SwiftUI property graph on older iOS. No credential work belongs in teardown.
    nonisolated deinit {}

    // MARK: - Singleton

    static let shared = KeychainService()
    /// 独立命名空间用于隔离凭据，不迁移其他 service 的数据。
    init(service: String = AppConstants.bundleIdentifier, storage: (any KeychainStorage)? = nil,
         makeDataPassword: (() throws -> String)? = nil,
         allowLegacyCredentials: Bool = !LibraryStoragePolicy.encryptedMetadata) {
        self.allowLegacyCredentials = allowLegacyCredentials
        self.service = service
        self.storage = storage ?? SystemKeychainStorage(service: service)
        self.makeDataPassword = makeDataPassword ?? (LibraryStoragePolicy.encryptedMetadata ? { try FreshEncryptedLibrary.randomSecret() } : nil)
    }

    func passwordAttemptLimiter(scope: String = "vault", now: @escaping () -> Date = Date.init) -> PasswordAttemptLimiter {
        PasswordAttemptLimiter(storage: storage, scope: scope, now: now)
    }

    // MARK: - Constants

    private let allowLegacyCredentials: Bool
    private let service: String
    private let storage: any KeychainStorage
    private let makeDataPassword: (() throws -> String)?
    private let ownerAccount = "vaultito.owner-credentials.v1"
    private struct OwnerCredentials: Codable {
        let version: Int
        let service: String
        let dataPassword: String
    }
    private let passwordAccount = "userPassword"
    private let saltAccount = "passwordSalt"
    private let isSetAccount = "isPasswordSet"
    private let dataPasswordAccount = "dataEncryptionPassword"

    // 访客模式相关账户
    private let guestPasswordAccount = "guestPassword"
    private let guestSaltAccount = "guestPasswordSalt"
    private let isGuestSetAccount = "isGuestPasswordSet"

    // 计算器登录模式相关账户
    private let disguisePasswordAccount = "disguisePassword"
    private let isDisguiseSetAccount = "isDisguisePasswordSet"

    private let encryptionService = EncryptionService.shared

    func loadLibraryIdentity() throws -> Data? {
        do { return try storage.read(account: "waglock.library-identity.v1") }
        catch KeychainError.itemNotFound { return nil }
    }
    func establishLibraryIdentity(_ identity: Data) throws {
        guard identity.count == 32 else { throw KeychainError.invalidData }
        try storage.write(account: "waglock.library-identity.v1", data: identity, createOnly: true)
    }

    // MARK: - Public Methods

    /// 保存密码（首次设置）
    /// - Parameter password: 用户密码
    /// - Throws: KeychainError
    @discardableResult
    func savePassword(_ password: String) throws -> String {
        guard Self.validatePasswordStrength(password).isValid else { throw KeychainError.invalidData }
        guard !isPasswordSet() else { throw KeychainError.duplicateItem }
        guard !verifyGuestPassword(password), !(try matchesIndependentGuestPassword(password)) else { throw KeychainError.invalidData }
        let dataPassword = try makeDataPassword?() ?? password
        guard !dataPassword.isEmpty else { throw KeychainError.invalidData }
        let record = try encodeOwnerCredentials(dataPassword, using: password)
        try storage.write(account: ownerAccount, data: record, createOnly: true)
        BiometricSecretStore.remove(account: "vault-unlock", service: service + ".biometrics")
        return dataPassword
    }

    /// 验证密码
    /// - Parameter password: 用户输入的密码
    /// - Returns: 密码是否正确
    func verifyPassword(_ password: String) -> Bool {
        (try? readDataPassword(using: password)) != nil
    }

    /// 检查是否已设置密码
    /// - Returns: 是否已设置密码
    func isPasswordSet() -> Bool {
        // Unavailable, corrupt or partial credentials must never route to setup.
        for account in [ownerAccount, passwordAccount, saltAccount, isSetAccount, dataPasswordAccount] {
            do {
                _ = try readFromKeychain(account: account)
                return true
            } catch KeychainError.itemNotFound {
                continue
            } catch {
                return true
            }
        }
        return false
    }

    /// 删除密码（重置应用）
    /// - Throws: KeychainError
    func deletePassword() throws {
        BiometricSecretStore.remove(account: "vault-unlock", service: service + ".biometrics")
        try deleteFromKeychain(account: ownerAccount)
        try deleteFromKeychain(account: passwordAccount)
        try deleteFromKeychain(account: saltAccount)
        try deleteFromKeychain(account: isSetAccount)
        try deleteFromKeychain(account: dataPasswordAccount)

    }

    /// 清空所有Keychain数据（包括主密码、访客密码、计算器登录密码）
    /// Explicit reset/test-fixture cleanup only. Never infer consent from preferences.
    func clearAllKeychainData() {
        try? deleteFromKeychain(account: "waglock.library-identity.v1")
        BiometricSecretStore.remove(account: "vault-unlock", service: service + ".biometrics")
        try? deleteFromKeychain(account: ownerAccount)
        // 清空主密码
        try? deleteFromKeychain(account: passwordAccount)
        try? deleteFromKeychain(account: saltAccount)
        try? deleteFromKeychain(account: isSetAccount)
        try? deleteFromKeychain(account: dataPasswordAccount)

        // 清空访客密码
        try? deleteFromKeychain(account: guestPasswordAccount)
        try? deleteFromKeychain(account: guestSaltAccount)
        try? deleteFromKeychain(account: isGuestSetAccount)

        // 清空计算器登录密码
        try? deleteFromKeychain(account: disguisePasswordAccount)
        try? deleteFromKeychain(account: isDisguiseSetAccount)

        // 清空私密笔记草稿
        deleteSecretNoteDraft()

    }

    /// 更改密码
    /// - Parameters:
    ///   - oldPassword: 旧密码
    ///   - newPassword: 新密码
    /// - Throws: KeychainError
    @discardableResult
    func changePassword(oldPassword: String, newPassword: String) throws -> String {
        guard Self.validatePasswordStrength(newPassword).isValid else { throw KeychainError.invalidData }
        guard !verifyGuestPassword(newPassword), !(try matchesIndependentGuestPassword(newPassword)) else { throw KeychainError.invalidData }
        let dataPassword = try readDataPassword(using: oldPassword)
        let record = try encodeOwnerCredentials(dataPassword, using: newPassword)
        // The only required mutation: verifier and wrapped key cannot diverge.
        try storage.write(account: ownerAccount, data: record, createOnly: false)
        removeLegacyOwnerCredentials()

        // Never retain a second, device-derived copy of the login password.
        try? retireCalculatorCredentials()

        return dataPassword
    }

    func retrieveDataPassword(using loginPassword: String) throws -> String {
        let secret = try readDataPassword(using: loginPassword)
        // Reading an existing legacy vault never changes its credentials.
        // Only initial setup or an explicit password change writes the new record.
        if try optionalItem(account: ownerAccount) != nil {
            removeLegacyOwnerCredentials()
        }
        return secret
    }

    private func readDataPassword(using loginPassword: String) throws -> String {
        if let record = try optionalItem(account: ownerAccount) {
            let plaintext = try PasswordEnvelope.open(record, password: loginPassword, context: "owner:" + service)
            let credentials = try JSONDecoder().decode(OwnerCredentials.self, from: plaintext)
            guard credentials.version == 1, credentials.service == service,
                  !credentials.dataPassword.isEmpty else { throw KeychainError.invalidData }
            return credentials.dataPassword
        }
        guard allowLegacyCredentials else { throw KeychainError.invalidData }
        let savedHash = try readFromKeychain(account: passwordAccount)
        let salt = try readFromKeychain(account: saltAccount)
        guard salt.count == 16, savedHash.count == 32,
              savedHash == hashPassword(loginPassword, salt: salt) else { throw KeychainError.invalidData }
        do {
            let encrypted = try readFromKeychain(account: dataPasswordAccount)
            let decrypted = try encryptionService.decrypt(
                encryptedData: encrypted,
                password: loginPassword
            )
            guard let string = String(data: decrypted, encoding: .utf8), !string.isEmpty else {
                throw KeychainError.invalidData
            }
            return string
        } catch let error as KeychainError {
            if case .itemNotFound = error {
                // The oldest format used the verified login password as its data key.
                return loginPassword
            }
            throw error
        } catch {
            throw KeychainError.invalidData
        }
    }

    // MARK: - Private Methods

    private func optionalItem(account: String) throws -> Data? {
        do { return try readFromKeychain(account: account) }
        catch KeychainError.itemNotFound { return nil }
    }

    private func encodeOwnerCredentials(_ secret: String, using password: String) throws -> Data {
        let payload = OwnerCredentials(version: 1, service: service, dataPassword: secret)
        return try PasswordEnvelope.seal(JSONEncoder().encode(payload), password: password, context: "owner:" + service)
    }

    private func removeLegacyOwnerCredentials() {
        // Cleanup occurs only after the complete replacement is committed.
        // Retry on later successful login if Keychain temporarily rejects deletion.
        for account in [passwordAccount, saltAccount, isSetAccount, dataPasswordAccount] {
            try? deleteFromKeychain(account: account)
        }
    }

    /// 生成随机盐值（16字节）
    private func generateSalt() throws -> Data {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 16, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return salt
    }

    /// 使用SHA-256哈希密码
    /// - Parameters:
    ///   - password: 密码字符串
    ///   - salt: 盐值
    /// - Returns: 哈希值
    private func hashPassword(_ password: String, salt: Data) -> Data {
        let passwordData = Data(password.utf8)
        let combined = passwordData + salt
        let hash = SHA256.hash(data: combined)
        return Data(hash)
    }

    private func saveToKeychain(account: String, data: Data) throws {
        try storage.write(account: account, data: data, createOnly: false)
    }

    private func readFromKeychain(account: String) throws -> Data {
        try storage.read(account: account)
    }

    private func deleteFromKeychain(account: String) throws {
        try storage.delete(account: account)
    }

}

// MARK: - Guest Mode Password Management

extension KeychainService {

    /// 保存访客密码
    /// - Parameter password: Guest credential, using the same 6–128 character policy as the owner.
    /// - Throws: KeychainError
    func saveGuestPassword(_ password: String) throws {
        guard allowLegacyCredentials else { throw KeychainError.invalidData }
        // Input rules match the owner; existing credential encoding/readers are retained.
        guard Self.validateGuestPassword(password).isValid else {
            throw KeychainError.invalidData
        }

        // 2. 服务层校验：访客密码不能与主密码相同（安全约束）
        guard !verifyPassword(password) else {
            throw KeychainError.invalidData
        }

        let salt = try generateSalt()
        let hash = hashPassword(password, salt: salt)

        try saveToKeychain(account: guestPasswordAccount, data: hash)
        try saveToKeychain(account: guestSaltAccount, data: salt)
        try saveToKeychain(account: isGuestSetAccount, data: Data([1]))

    }

    /// 验证访客密码
    /// - Parameter password: 用户输入的密码
    /// - Returns: 密码是否正确
    func verifyGuestPassword(_ password: String) -> Bool {
        guard allowLegacyCredentials else { return false }
        do {
            let savedHash = try readFromKeychain(account: guestPasswordAccount)
            let salt = try readFromKeychain(account: guestSaltAccount)
            let inputHash = hashPassword(password, salt: salt)
            return savedHash == inputHash
        } catch {
            return false
        }
    }

    /// 检查是否已设置访客密码
    /// - Returns: 是否已设置访客密码
    func isGuestPasswordSet() -> Bool {
        guard allowLegacyCredentials else { return false }
        do {
            let data = try readFromKeychain(account: isGuestSetAccount)
            return data.first == 1
        } catch {
            return false
        }
    }

    /// 删除访客密码
    /// - Throws: KeychainError
    func deleteGuestPassword() throws {
        try deleteFromKeychain(account: guestPasswordAccount)
        try deleteFromKeychain(account: guestSaltAccount)
        try deleteFromKeychain(account: isGuestSetAccount)
    }

    /// 验证访客密码格式（纯数字，6-8位）
    /// - Parameter password: 密码
    /// - Returns: (是否有效, 错误信息)
    static func validateGuestPassword(_ password: String) -> (isValid: Bool, message: String?) {
        validatePasswordStrength(password)
    }
}

extension KeychainService {
    var contextNamespace: String { service }
    func secondaryIdentityAnchor(_ id: UUID) -> KeychainService {
        KeychainService(service: service + ".vault." + id.uuidString)
    }
}

// MARK: - Independent Secondary Vault Credentials

extension KeychainService {
    /// Not connected to login until every selected-vault service boundary is wired.
    /// One create-only record provisions the opaque identity and independent random secret.
    struct IndependentGuestCredential: Codable, Equatable {
        let version: Int
        let service: String
        let vaultID: UUID
        let dataPassword: String
    }

    private struct IndependentGuestRecord: Codable {
        let version: Int
        let vaultID: UUID
        let envelope: Data
    }

    private var independentGuestAccount: String { "waglock.secondary-credentials.v1" }

    /// Checked absence only; an unavailable or malformed item is never a setup invitation.
    /// The outer ID is an unauthenticated routing hint, never authorization to mount.
    /// Unlock authenticates this ID against both the wrapper context and its payload.
    func independentGuestVaultID() throws -> UUID? {
        guard let record = try optionalItem(account: independentGuestAccount) else { return nil }
        return try decodeIndependentGuestRecord(record).vaultID
    }

    @discardableResult
    func provisionIndependentGuest(password: String) throws -> IndependentGuestCredential {
        guard Self.validatePasswordStrength(password).isValid else { throw KeychainError.invalidData }
        // Require an existing, readable primary record; setup cannot mask a Keychain failure.
        guard let owner = try optionalItem(account: ownerAccount), !owner.isEmpty else {
            throw KeychainError.invalidData
        }
        guard !verifyPassword(password) else { throw KeychainError.invalidData }
        guard try independentGuestVaultID() == nil else { throw KeychainError.duplicateItem }
        let credential = IndependentGuestCredential(version: 1, service: service,
            vaultID: UUID(), dataPassword: try FreshEncryptedLibrary.randomSecret())
        let record = try encodeIndependentGuest(credential, password: password)
        try storage.write(account: independentGuestAccount, data: record, createOnly: true)
        return credential
    }

    func unlockIndependentGuest(password: String) throws -> IndependentGuestCredential {
        let record = try decodeIndependentGuestRecord(storage.read(account: independentGuestAccount))
        return try openIndependentGuest(record, password: password)
    }

    private func openIndependentGuest(_ record: IndependentGuestRecord, password: String) throws -> IndependentGuestCredential {
        let plaintext = try PasswordEnvelope.open(record.envelope, password: password,
            context: independentGuestContext(record.vaultID))
        let credential = try JSONDecoder().decode(IndependentGuestCredential.self, from: plaintext)
        guard credential.version == 1, credential.service == service,
              credential.vaultID == record.vaultID, !credential.dataPassword.isEmpty else {
            throw KeychainError.invalidData
        }
        return credential
    }

    @discardableResult
    func changeIndependentGuestPassword(oldPassword: String, newPassword: String) throws -> IndependentGuestCredential {
        guard Self.validatePasswordStrength(newPassword).isValid else { throw KeychainError.invalidData }
        // Read primary storage explicitly so an unavailable item cannot conceal a collision.
        guard try optionalItem(account: ownerAccount) != nil, !verifyPassword(newPassword) else {
            throw KeychainError.invalidData
        }
        let credential = try unlockIndependentGuest(password: oldPassword)
        let record = try encodeIndependentGuest(credential, password: newPassword)
        try storage.write(account: independentGuestAccount, data: record, createOnly: false)
        return credential
    }

    private func matchesIndependentGuestPassword(_ password: String) throws -> Bool {
        guard let bytes = try optionalItem(account: independentGuestAccount) else { return false }
        let record = try decodeIndependentGuestRecord(bytes)
        return (try? openIndependentGuest(record, password: password)) != nil
    }

    private func independentGuestContext(_ id: UUID) -> String {
        "secondary:" + service + ":" + id.uuidString
    }

    private func encodeIndependentGuest(_ credential: IndependentGuestCredential, password: String) throws -> Data {
        let envelope = try PasswordEnvelope.seal(JSONEncoder().encode(credential), password: password,
            context: independentGuestContext(credential.vaultID))
        return try JSONEncoder().encode(IndependentGuestRecord(version: 1, vaultID: credential.vaultID, envelope: envelope))
    }

    private func decodeIndependentGuestRecord(_ data: Data) throws -> IndependentGuestRecord {
        guard data.count <= 100_000 else { throw KeychainError.invalidData }
        let record = try JSONDecoder().decode(IndependentGuestRecord.self, from: data)
        // This slot has no legacy format: never permit PasswordEnvelope's legacy fallback.
        guard record.version == 1, record.envelope.starts(with: Data("WLPE".utf8)) else {
            throw KeychainError.invalidData
        }
        return record
    }
}

// MARK: - Password Validation

extension KeychainService {

    /// 验证密码强度
    /// - Parameter password: 密码
    /// - Returns: (是否有效, 错误信息)
    static func validatePasswordStrength(_ password: String) -> (isValid: Bool, message: String?) {
        if password.isEmpty {
            return (false, AppConstants.ErrorMessages.passwordEmpty)
        }

        if password.count < 6 {
            return (false, AppConstants.ErrorMessages.passwordTooShort)
        }

        if password.count > 128 {
            return (false, AppConstants.ErrorMessages.passwordTooLong)
        }

        return (true, nil)
    }
}

// MARK: - Retired Calculator Login

extension KeychainService {
    /// Remove only obsolete calculator material. Main keys, identity and user data are untouched.
    func retireCalculatorCredentials(defaults: UserDefaults = .standard) throws {
        defaults.set(false, forKey: AppConstants.UserDefaultsKeys.disguiseModeEnabled)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.disguisePasswordSequence)
        var failure: Error?
        for account in [disguisePasswordAccount, isDisguiseSetAccount] {
            do { try storage.delete(account: account) } catch { if failure == nil { failure = error } }
        }
        if let failure { throw failure }
    }
}

// MARK: - Secret Note Draft Storage

extension KeychainService {

    private var secretNoteDraftAccount: String { "secretNoteDraft" }

    /// 保存私密笔记草稿（覆盖旧值）
    /// - Returns: 是否写入成功（锁屏等场景下 Keychain 可能不可写）
    @discardableResult
    func saveSecretNoteDraft(_ data: Data) -> Bool {
        do {
            try saveToKeychain(account: secretNoteDraftAccount, data: data)
            return true
        } catch {
            return false
        }
    }

    /// 读取私密笔记草稿
    func loadSecretNoteDraft() -> Data? {
        try? readFromKeychain(account: secretNoteDraftAccount)
    }

    /// Recovery must distinguish an absent draft from an inaccessible Keychain entry.
    func loadSecretNoteDraftChecked() throws -> Data? {
        try optionalItem(account: secretNoteDraftAccount)
    }

    /// 删除私密笔记草稿
    func deleteSecretNoteDraft() {
        try? deleteFromKeychain(account: secretNoteDraftAccount)
    }
}

// MARK: - Legacy Service Migration

extension KeychainService {

    /// 早期构建使用的 Keychain service 标识符。
    /// 若不迁移，从旧包升级的用户会被当作全新安装，
    /// 旧登录密码和数据加密密钥读不到，已加密数据将永久无法解密
    private static let legacyService = "com.wq.ZeroNet-Space"

    private var legacyMigratableAccounts: [String] {
        [
            passwordAccount, saltAccount, isSetAccount, dataPasswordAccount,
            guestPasswordAccount, guestSaltAccount, isGuestSetAccount,
            disguisePasswordAccount, isDisguiseSetAccount,
        ]
    }

    /// 把旧 service 下的条目迁移到当前 service。
    /// 逐项进行：写入新 service 成功后才删除旧项；任何一项失败（如
    /// Keychain 暂不可写）都保留旧数据，等下次启动重试，绝不丢数据
    fileprivate func migrateFromLegacyServiceIfNeeded() {
        // 新 service 下已有主密码，说明用户已在新体系内，不做任何覆盖
        if (try? readFromKeychain(account: isSetAccount)) != nil { return }

        var migratedCount = 0
        for account in legacyMigratableAccounts {
            guard let legacyData = readLegacyItem(account: account) else { continue }

            if (try? readFromKeychain(account: account)) == nil {
                guard (try? saveToKeychain(account: account, data: legacyData)) != nil else {
                    continue
                }
            }
            deleteLegacyItem(account: account)
            migratedCount += 1
        }

        if migratedCount > 0 {
        }
    }

    private func readLegacyItem(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.legacyService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private func deleteLegacyItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.legacyService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
