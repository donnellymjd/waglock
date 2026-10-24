import Foundation
import LocalAuthentication
import Security

enum VaultAccessError: LocalizedError {
    case locked, invalidPassword, biometricsUnavailable, invalidAlbum, invalidData, albumNotEmpty
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .locked: return "Unlock the vault and every parent album first."
        case .invalidPassword: return "The password is incorrect or the album is damaged."
        case .biometricsUnavailable: return "Face ID is unavailable or not enrolled. Use a password where available."
        case .invalidAlbum: return "This album or its parent is unavailable."
        case .invalidData: return "The encrypted album data could not be read."
        case .albumNotEmpty: return "Remove media and subalbums before deleting this album."
        case .keychain: return "Biometric access was cancelled, invalidated or unavailable. Try again, or use the password."
        }
    }
}

@MainActor
protocol BiometricSecretStoring {
    func store(_ secret: String, account: String) async throws
    func store(_ secret: String, account: String, authorizing: @MainActor () -> Bool) async throws
    func read(account: String, reason: String) async throws -> String
    func remove(account: String)
}

extension BiometricSecretStoring {
    func store(_ secret: String, account: String, authorizing: @MainActor () -> Bool) async throws {
        guard authorizing(), !Task.isCancelled else { throw CancellationError() }
        try await store(secret, account: account)
        guard authorizing(), !Task.isCancelled else { throw CancellationError() }
    }
}

/// Secrets are released by Keychain ACL, not by an application-level Boolean.
@MainActor
final class BiometricSecretStore: BiometricSecretStoring {
    nonisolated deinit {}
    static let shared = BiometricSecretStore()
    static let vaultAccount = "vault-unlock"
    typealias Authenticator = @MainActor (String) async throws -> LAContext
    private let service: String
    private let authenticate: Authenticator?

    init(service: String = AppConstants.bundleIdentifier + ".biometrics",
         authenticate: Authenticator? = nil) {
        self.service = service
        self.authenticate = authenticate
    }

    var isAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private func authenticatedContext(reason: String) async throws -> LAContext {
        if let authenticate { return try await authenticate(reason) }
        let context = LAContext()
        context.localizedFallbackTitle = ""
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            throw VaultAccessError.biometricsUnavailable
        }
        do {
            guard try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics, localizedReason: reason
            ) else { throw VaultAccessError.biometricsUnavailable }
            return context
        } catch {
            context.invalidate()
            throw error
        }
    }

    func store(_ secret: String, account: String) async throws {
        try await store(secret, account: account, authorizing: { true })
    }

    func store(_ secret: String, account: String, authorizing: @MainActor () -> Bool) async throws {
        let context = try await authenticatedContext(reason: "Enable biometric unlock")
        defer { context.invalidate() }
        // Consent may finish after lock or a different session. Check before Keychain mutation.
        guard authorizing(), !Task.isCancelled else { throw CancellationError() }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &error
        ) else { throw VaultAccessError.biometricsUnavailable }
        var query = baseQuery(account: account)
        query[kSecAttrAccessControl as String] = access
        query[kSecUseAuthenticationContext as String] = context
        query[kSecValueData as String] = Data(secret.utf8)
        // Each album has a unique account. Replace vault convenience only after biometric consent.
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
            var existing = baseQuery(account: account)
            existing[kSecUseAuthenticationContext as String] = context
            let result = SecItemUpdate(existing as CFDictionary, update as CFDictionary)
            guard result == errSecSuccess else { throw VaultAccessError.keychain(result) }
        } else if status != errSecSuccess {
            throw VaultAccessError.keychain(status)
        }
    }

    func read(account: String, reason: String) async throws -> String {
        let context = try await authenticatedContext(reason: reason)
        defer { context.invalidate() }
        var query = baseQuery(account: account)
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        guard status == errSecSuccess, let data = value as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            throw VaultAccessError.keychain(status)
        }
        return secret
    }

    func remove(account: String) {
        Self.remove(account: account, service: service)
    }

    nonisolated static func remove(account: String, service: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
