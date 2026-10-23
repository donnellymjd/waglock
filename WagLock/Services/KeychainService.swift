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
         makeDataPassword: (() throws -> String)? = nil) {
        self.service = service
        self.storage = storage ?? SystemKeychainStorage(service: service)
        self.makeDataPassword = makeDataPassword ?? (LibraryStoragePolicy.encryptedMetadata ? { try FreshEncryptedLibrary.randomSecret() } : nil)
    }

    // MARK: - Constants

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
        guard !verifyGuestPassword(password) else { throw KeychainError.invalidData }
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
        guard !verifyGuestPassword(newPassword) else { throw KeychainError.invalidData }
        let dataPassword = try readDataPassword(using: oldPassword)
        let record = try encodeOwnerCredentials(dataPassword, using: newPassword)
        // The only required mutation: verifier and wrapped key cannot diverge.
        try storage.write(account: ownerAccount, data: record, createOnly: false)
        removeLegacyOwnerCredentials()

        // 🎭 自动同步计算器登录模式密码序列（如果计算器登录模式已启用）
        let disguiseModeEnabled = UserDefaults.standard.bool(
            forKey: AppConstants.UserDefaultsKeys.disguiseModeEnabled
        )
        if disguiseModeEnabled {
            do {
                try saveDisguisePassword(newPassword)
            } catch {
            }
        }

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
            let plaintext = try encryptionService.decrypt(encryptedData: record, password: loginPassword)
            let credentials = try JSONDecoder().decode(OwnerCredentials.self, from: plaintext)
            guard credentials.version == 1, credentials.service == service,
                  !credentials.dataPassword.isEmpty else { throw KeychainError.invalidData }
            return credentials.dataPassword
        }
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
        return try encryptionService.encrypt(data: JSONEncoder().encode(payload), password: password)
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
        guard !LibraryStoragePolicy.encryptedMetadata else { throw KeychainError.invalidData }
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
        guard !LibraryStoragePolicy.encryptedMetadata else { return false }
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
        guard !LibraryStoragePolicy.encryptedMetadata else { return false }
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

// MARK: - Disguise Mode Password Management

extension KeychainService {

    /// 保存计算器登录模式密码（加密存储）
    /// - Parameter password: 计算器登录密码（仅数字和小数点）
    /// - Throws: KeychainError
    func saveDisguisePassword(_ password: String) throws {
        // 1. 验证计算器登录密码格式（仅数字和小数点）
        let allowedCharacters = CharacterSet(charactersIn: "0123456789.")
        let passwordCharacters = CharacterSet(charactersIn: password)
        guard passwordCharacters.isSubset(of: allowedCharacters), password.count >= 4 else {
            throw KeychainError.invalidData
        }

        // 2. 使用设备唯一标识生成加密密钥
        let deviceKey =
            "ZNS_DISGUISE_\(UIDevice.current.identifierForVendor?.uuidString ?? "DEFAULT")"

        // 3. 加密计算器登录密码
        let passwordData = Data(password.utf8)
        let encryptedData = try encryptionService.encrypt(data: passwordData, password: deviceKey)

        // 4. 存储到 Keychain
        try saveToKeychain(account: disguisePasswordAccount, data: encryptedData)
        try saveToKeychain(account: isDisguiseSetAccount, data: Data([1]))

    }

    /// 读取计算器登录模式密码
    /// - Returns: 计算器登录密码，如果未设置返回 nil
    func loadDisguisePassword() -> String? {
        do {
            // 1. 从 Keychain 读取加密数据
            let encryptedData = try readFromKeychain(account: disguisePasswordAccount)

            // 2. 使用设备唯一标识解密
            let deviceKey =
                "ZNS_DISGUISE_\(UIDevice.current.identifierForVendor?.uuidString ?? "DEFAULT")"
            let decryptedData = try encryptionService.decrypt(
                encryptedData: encryptedData,
                password: deviceKey
            )

            // 3. 转换为字符串
            guard let password = String(data: decryptedData, encoding: .utf8) else {
                return nil
            }

            return password
        } catch KeychainError.itemNotFound {
            // 计算器登录密码未设置，返回 nil
            return nil
        } catch {
            return nil
        }
    }

    /// 检查是否已设置伪装密码
    /// - Returns: 是否已设置伪装密码
    func isDisguisePasswordSet() -> Bool {
        do {
            let data = try readFromKeychain(account: isDisguiseSetAccount)
            return data.first == 1
        } catch {
            return false
        }
    }

    /// 删除伪装密码
    /// - Throws: KeychainError
    func deleteDisguisePassword() throws {
        try deleteFromKeychain(account: disguisePasswordAccount)
        try deleteFromKeychain(account: isDisguiseSetAccount)
    }

    /// 迁移旧的 UserDefaults 伪装密码到 Keychain
    /// - Returns: 是否成功迁移
    @discardableResult
    func migrateDisguisePasswordFromUserDefaults() -> Bool {
        // 检查是否已经设置了 Keychain 密码
        if isDisguisePasswordSet() {
            return false
        }

        // 尝试从 UserDefaults 读取旧密码
        if let oldPassword = UserDefaults.standard.string(
            forKey: AppConstants.UserDefaultsKeys.disguisePasswordSequence
        ), !oldPassword.isEmpty {
            do {
                // 保存到 Keychain
                try saveDisguisePassword(oldPassword)

                // 从 UserDefaults 删除（安全清理）
                UserDefaults.standard.removeObject(
                    forKey: AppConstants.UserDefaultsKeys.disguisePasswordSequence
                )

                return true
            } catch {
                return false
            }
        }

        return false
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
