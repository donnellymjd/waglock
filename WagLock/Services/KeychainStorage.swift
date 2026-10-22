import Foundation
import Security

/// A single write replaces one complete value. Tests inject failures at this boundary.
protocol KeychainStorage {
    func read(account: String) throws -> Data
    func write(account: String, data: Data, createOnly: Bool) throws
    func delete(account: String) throws
}

struct SystemKeychainStorage: KeychainStorage {
    let service: String

    func read(account: String) throws -> Data {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        try check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let data = result as? Data else { throw KeychainError.invalidData }
        return data
    }

    func write(account: String, data: Data, createOnly: Bool = false) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let match = query(account: account)
        if !createOnly {
            let status = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
            if status != errSecItemNotFound {
                try check(status)
                return
            }
        }
        let item = match.merging(attributes) { _, new in new }
        let status = SecItemAdd(item as CFDictionary, nil)
        // A concurrent creator can win between an update miss and the add.
        if status == errSecDuplicateItem && !createOnly {
            try check(SecItemUpdate(match as CFDictionary, attributes as CFDictionary))
        } else {
            try check(status)
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecItemNotFound: throw KeychainError.itemNotFound
        case errSecDuplicateItem: throw KeychainError.duplicateItem
        default: throw KeychainError.unexpectedStatus(status)
        }
    }
}
