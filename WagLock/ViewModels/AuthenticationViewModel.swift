//
//  AuthenticationViewModel.swift
//  WagLock
//
//  Authentication view model
//  Manages login, password setup and authentication state
//

internal import Combine
import Foundation
import SwiftUI

/// Authentication view model
@MainActor
final class AuthenticationViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Whether the user is authenticated
    @Published var isAuthenticated: Bool = false

    /// Fresh identity whenever session key material is replaced or cleared.
    @Published private(set) var librarySessionID = UUID()

    @Published private(set) var vaultContext: VaultSessionContext?
    @Published private(set) var secondaryVaultID: UUID?
    var isPrimaryVault: Bool { secondaryVaultID == nil }
    var libraryScope: LibraryMountCoordinator.Scope {
        secondaryVaultID.map { .independentVault($0) } ?? .legacyOwner
    }
    private static let primaryVaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private struct BiometricGrant: Codable { let version: Int; let secondaryID: UUID?; let secret: String }

    /// Whether a password has been set
    @Published var isPasswordSet: Bool = false

    /// Password currently being entered
    @Published var password: String = ""

    /// Password confirmation (used during setup)
    @Published var confirmPassword: String = ""

    /// Error message
    @Published var errorMessage: String?

    /// Whether processing is in progress
    @Published var isProcessing: Bool = false

    /// Whether to show the password
    @Published var showPassword: Bool = false

    /// Encryption password (reference container; zeroed in place when replaced or on logout)
    @Published private(set) var sessionPasswordData: SecureBytes? {
        willSet {
            // Zero the old password's memory
            sessionPasswordData?.wipe()
        }
        didSet {
            vaultContext?.revoke()
            vaultContext = nil
            LibraryMountCoordinator.invalidateSession(librarySessionID)
            exports.endSession(matching: librarySessionID)
            documentPreviews.endSession(matching: librarySessionID)
            librarySessionID = UUID()
            AlbumStore.shared.endSession()
        }
    }

    /// Session password as a String (converted only when needed)
    var sessionPassword: String? {
        sessionPasswordData?.string
    }

    /// Failed login count
    @Published private(set) var failedAttempts: Int = 0

    /// Lockout end time
    @Published private(set) var lockoutUntil: Date?

    // MARK: - Constants

    private let maxAttempts = 5  // At most 5 attempts

    @Published private(set) var requiresEraseCompletion = false
    @Published private(set) var isErasing = false
    @Published private(set) var eraseError: String?
    private let resetService: VaultResetService?
    var canEraseLocalData: Bool { resetService != nil }

    // MARK: - Services

    typealias DataPasswordLoader = @MainActor (String) async throws -> String
    typealias ContextFactory = @MainActor (UUID?, UUID, String) throws -> VaultSessionContext
    private let independentVaultsEnabled: Bool
    private let contextFactory: ContextFactory?
    private let biometrics: any BiometricSecretStoring
    private let loadDataPassword: DataPasswordLoader
    private let exports: ExportService
    private let documentPreviews: DocumentPreviewService
    private let keychainService: KeychainService
    private let attemptLimiter: PasswordAttemptLimiter
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Task Management

    private var loginTask: Task<Void, Never>?
    private var savePasswordTask: Task<Void, Never>?
    private var authenticationGeneration = UUID()
    @Published private(set) var isBiometricUnlockEnabled = UserDefaults.standard.bool(forKey: "vaultito.faceID.enabled")

    // MARK: - Initialization

    init(keychainService: KeychainService? = nil, manageInstallationState: Bool = true,
         dataPasswordLoader: DataPasswordLoader? = nil, exportService: ExportService? = nil,
         documentPreviewService: DocumentPreviewService? = nil, attemptLimiter: PasswordAttemptLimiter? = nil,
         independentVaultsEnabled: Bool = LibraryStoragePolicy.encryptedMetadata,
         contextFactory: ContextFactory? = nil, biometrics: (any BiometricSecretStoring)? = nil,
         resetService: VaultResetService? = nil) {
        self.resetService = resetService ?? (manageInstallationState ? VaultResetService.live() : nil)
        self.independentVaultsEnabled = independentVaultsEnabled
        self.contextFactory = contextFactory
        self.biometrics = biometrics ?? BiometricSecretStore.shared
        let keychainService = keychainService ?? .shared
        self.exports = exportService ?? .shared
        self.documentPreviews = documentPreviewService ?? .shared
        self.keychainService = keychainService
        self.attemptLimiter = attemptLimiter ?? keychainService.passwordAttemptLimiter()
        self.loadDataPassword = dataPasswordLoader ?? { password in
            try await Task.detached { try await keychainService.retrieveDataPassword(using: password) }.value
        }
        if manageInstallationState {
            markInstallationInitialized()
            try? keychainService.retireCalculatorCredentials()
        }
        checkPasswordStatus()
    }

    deinit {
        // Cancel all in-flight tasks
        loginTask?.cancel()
        savePasswordTask?.cancel()
    }

    // Calculator notification unlocks are deliberately not observed.

    // MARK: - Public Methods

    /// Preferences are not evidence that recoverable Keychain material is orphaned.
    private func markInstallationInitialized() {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.appInitialized)
    }

    /// Check whether a password has been set
    func checkPasswordStatus() {
        if let resetService {
            do { requiresEraseCompletion = try resetService.hasPendingErase() }
            catch {
                requiresEraseCompletion = true
                eraseError = "Unable to check erasure status. Unlock your device and retry."
            }
        }
        guard !requiresEraseCompletion else { return }
        isPasswordSet = keychainService.isPasswordSet()
    }

    /// Set the password (first time)
    func setupPassword() {
        guard !isProcessing, !requiresEraseCompletion, !isErasing else { return }

        // Clear any previous error
        errorMessage = nil

        // Validate the password
        let validation = KeychainService.validatePasswordStrength(password)
        guard validation.isValid else {
            errorMessage = validation.message
            return
        }

        // Check that the passwords match
        guard PasswordText.matches(password, confirmPassword) else {
            errorMessage = AppConstants.ErrorMessages.passwordMismatch
            return
        }

        isProcessing = true

        let inputPassword = password
        let token = UUID()
        authenticationGeneration = token
        // Do not provision credentials if this queued setup was invalidated by lock.
        savePasswordTask = Task {
            defer { if token == authenticationGeneration { isProcessing = false } }
            guard token == authenticationGeneration, !Task.isCancelled else { return }
            do {
                let dataPassword = try keychainService.savePassword(inputPassword)

                // Saved successfully
                sessionPasswordData = SecureBytes(dataPassword)
                isPasswordSet = true
                isAuthenticated = true

                // Switch to owner mode (go straight to the main screen after first-time setup)
                GuestModeManager.shared.setAuthenticationMode(.owner)
                resumeAlbumAccess()

                clearFields()

            } catch {
                errorMessage = String(
                    format: String(localized: "auth.error.savePasswordFailed"),
                    error.localizedDescription)
            }

        }
    }

    /// Log in
    @discardableResult
    func login() -> Task<Void, Never>? {
        guard !isProcessing, !requiresEraseCompletion, !isErasing else { return nil }

        // Cancel any previous login task
        loginTask?.cancel()

        // Clear any previous error
        errorMessage = nil

        guard !password.isEmpty else {
            errorMessage = AppConstants.ErrorMessages.passwordEmpty
            return nil
        }
        let reservation: PasswordAttemptLimiter.Reservation
        do {
            reservation = try attemptLimiter.reserve()
            failedAttempts = reservation.failures
            lockoutUntil = reservation.blockedUntil
        } catch PasswordAttemptLimiter.Failure.blocked(let seconds) {
            errorMessage = "Too many attempts. Try again in \(seconds) seconds."
            return nil
        } catch {
            errorMessage = "Unable to verify login protection. Unlock your device and try again."
            return nil
        }

        isProcessing = true
        let inputPassword = password
        let token = UUID()
        authenticationGeneration = token

        // Start a new login task
        loginTask = Task(priority: .userInitiated) {
            defer { if token == authenticationGeneration { isProcessing = false } }
            // Run the slow Keychain work in the background so the main thread isn't blocked
            let ownerKey: String?
            let ownerMatch: Bool
            if independentVaultsEnabled {
                ownerKey = try? await loadDataPassword(inputPassword)
                ownerMatch = ownerKey != nil
            } else {
                ownerKey = nil
                ownerMatch = await Task.detached { await self.keychainService.verifyPassword(inputPassword) }.value
            }

            let independentGuest: KeychainService.IndependentGuestCredential? = independentVaultsEnabled
                ? try? keychainService.unlockIndependentGuest(password: inputPassword) : nil
            let guestMatch = await Task.detached {
                guard await self.keychainService.isGuestPasswordSet() else { return false }
                return await self.keychainService.verifyGuestPassword(inputPassword)
            }.value

            guard token == authenticationGeneration, !Task.isCancelled else { return }

            // Back on the main thread, update UI state
            if ownerMatch && independentGuest == nil {
                do {
                    let dataPassword: String
                    if let ownerKey { dataPassword = ownerKey }
                    else { dataPassword = try await loadDataPassword(inputPassword) }
                    guard token == authenticationGeneration, !Task.isCancelled else { return }

                    if independentVaultsEnabled { try keychainService.upgradeAuthenticatedOwnerWrapping(using: inputPassword) }
                    try attemptLimiter.recordSuccess(reservation)
                    sessionPasswordData = SecureBytes(dataPassword)
                    secondaryVaultID = nil
                    isAuthenticated = true

                    // Switch to owner mode
                    GuestModeManager.shared.setAuthenticationMode(.owner)
                    resumeAlbumAccess()

                    // ✅ Login succeeded; reset the failure count
                    failedAttempts = 0
                    lockoutUntil = nil

                    clearFields()
                } catch {
                    guard token == authenticationGeneration, !Task.isCancelled else { return }
                    errorMessage = String(localized: "auth.error.loadKeyFailed")
                }
            } else if let independentGuest {
                do {
                    try attemptLimiter.recordSuccess(reservation)
                } catch { errorMessage = "Unable to complete login protection. Try again."; return }
                sessionPasswordData = SecureBytes(independentGuest.dataPassword)
                secondaryVaultID = independentGuest.vaultID
                isAuthenticated = true
                GuestModeManager.shared.setAuthenticationMode(.secondaryOwner)
                resumeAlbumAccess()
                failedAttempts = 0; lockoutUntil = nil
                clearFields()
            } else if guestMatch {
                do { try attemptLimiter.recordSuccess(reservation) }
                catch { errorMessage = "Unable to complete login protection. Try again."; return }
                // Guest mode login succeeded
                // Keep the guest password for later disguise-mode unlocks
                sessionPasswordData = SecureBytes(inputPassword)
                isAuthenticated = true

                // Switch to guest mode
                GuestModeManager.shared.setAuthenticationMode(.guest)

                // ✅ Login succeeded; reset the failure count
                failedAttempts = 0
                lockoutUntil = nil

                clearFields()
            } else {
                // ❌ Neither password matched
                // The guess was already persisted before any password verification.
                failedAttempts = reservation.failures
                password = ""

                // Check whether to lock out
                if failedAttempts >= maxAttempts {
                    lockoutUntil = reservation.blockedUntil
                    let minutes = Int(ceil(max(0, reservation.blockedUntil?.timeIntervalSinceNow ?? 0) / 60))
                    errorMessage = "Too many attempts. Try again in \(max(1, minutes)) minutes."
                } else {
                    let remaining = maxAttempts - failedAttempts
                    errorMessage = String(
                        format: String(localized: "auth.error.remainingAttempts"),
                        remaining)
                }
            }

        }
        return loginTask
    }

    /// Log out
    func logout() {
        vaultContext?.revoke()
        authenticationGeneration = UUID()
        loginTask?.cancel()
        savePasswordTask?.cancel()
        isProcessing = false
        isAuthenticated = false

        // 🔒 Securely clear password memory (zeroed in place in willSet)
        sessionPasswordData = nil
        secondaryVaultID = nil

        // Clear the decrypted image cache so plaintext pixels don't outlive the session
        MediaLoaderService.shared.clearCache()
        ThumbnailImageLoader.shared.clearAll()

        // Reset the authentication mode
        GuestModeManager.shared.reset()

        clearFields()
    }

    func enableBiometricUnlock(password: String) async throws {
        guard canManageBiometricUnlock else { throw VaultAccessError.locked }
        guard try verifyCurrentPassword(password) else { throw VaultAccessError.invalidPassword }
        let token = authenticationGeneration
        let secret: String
        if let id = secondaryVaultID {
            let credential = try keychainService.unlockIndependentGuest(password: password)
            guard credential.vaultID == id else { throw VaultAccessError.invalidPassword }
            secret = credential.dataPassword
        } else { secret = try keychainService.retrieveDataPassword(using: password) }
        let payload = try JSONEncoder().encode(BiometricGrant(version: 1, secondaryID: secondaryVaultID, secret: secret))
        let grant = "WLBG1:" + payload.base64EncodedString()
        try await biometrics.store(grant, account: BiometricSecretStore.vaultAccount) {
            token == self.authenticationGeneration && self.isAuthenticated
                && self.canManageBiometricUnlock
        }
        guard token == authenticationGeneration, !Task.isCancelled, canManageBiometricUnlock else {
            // Do not delete a shared account that a newer authorized enrollment may own.
            throw CancellationError()
        }
        try keychainService.setBiometricOwner(secondaryVaultID?.uuidString ?? "primary")
        isBiometricUnlockEnabled = true
        UserDefaults.standard.set(true, forKey: "vaultito.faceID.enabled")
    }

    /// Legacy enrollments without ownership metadata belong to the primary vault.
    var canManageBiometricUnlock: Bool {
        guard isAuthenticated, GuestModeManager.shared.isOwnerMode else { return false }
        if isPrimaryVault { return true }
        do {
            if let owner = try keychainService.biometricOwner() { return owner == secondaryVaultID?.uuidString }
            return !isBiometricUnlockEnabled
        } catch { return false }
    }

    func disableBiometricUnlock() {
        guard canManageBiometricUnlock else { return }
        authenticationGeneration = UUID()
        biometrics.remove(account: BiometricSecretStore.vaultAccount)
        keychainService.clearBiometricOwner()
        isBiometricUnlockEnabled = false
        UserDefaults.standard.set(false, forKey: "vaultito.faceID.enabled")
    }

    func loginWithBiometrics() async {
        guard !isProcessing, !requiresEraseCompletion, !isErasing, !isAuthenticated, isPasswordSet, isBiometricUnlockEnabled else { return }
        isProcessing = true
        errorMessage = nil
        let token = authenticationGeneration
        defer { if token == authenticationGeneration { isProcessing = false } }
        do {
            let secret = try await biometrics.read(
                account: BiometricSecretStore.vaultAccount, reason: "Unlock WagLock")
            guard token == authenticationGeneration, !isAuthenticated else { throw CancellationError() }
            let target: UUID?
            let dataPassword: String
            if secret.hasPrefix("WLBG1:") {
                guard let bytes = Data(base64Encoded: String(secret.dropFirst(6))) else { throw VaultAccessError.invalidData }
                let grant = try JSONDecoder().decode(BiometricGrant.self, from: bytes)
                guard grant.version == 1, !grant.secret.isEmpty else { throw VaultAccessError.invalidData }
                if let id = grant.secondaryID {
                    guard try keychainService.independentGuestVaultID() == id else { throw VaultAccessError.invalidData }
                }
                target = grant.secondaryID; dataPassword = grant.secret
            } else { target = nil; dataPassword = secret } // Existing enrollment remains primary-only.
            if independentVaultsEnabled, target == nil, try keychainService.ownerWrappingRequiresUpgrade() {
                throw VaultAccessError.locked // One password unlock is required to upgrade an older wrapper.
            }
            // The successfully authenticated protected grant is authoritative. Older
            // enrollments can lack the later ownership marker; repair it only here,
            // never from a password-entered secondary session or cancelled Face ID.
            if independentVaultsEnabled {
                try keychainService.setBiometricOwner(target?.uuidString ?? "primary")
            }
            sessionPasswordData = SecureBytes(dataPassword)
            secondaryVaultID = target
            isAuthenticated = true
            GuestModeManager.shared.setAuthenticationMode(target == nil ? .owner : .secondaryOwner)
            resumeAlbumAccess()
            clearFields()
        } catch {
            guard token == authenticationGeneration else { return }
            errorMessage = "Biometric unlock was cancelled or unavailable. Use your vault password."
        }
    }

    /// Flush drafts before revocation. Release callers require immediate key disposal.
    func handleBackground(lockImmediately: Bool) {
        suspendAlbumAccess()
        if lockImmediately { logout() }
    }

    func suspendAlbumAccess() {
        vaultContext?.revoke()
        documentPreviews.flushNotesBeforeSuspending(librarySessionID)
        exports.endSession(matching: librarySessionID)
        documentPreviews.endSession(matching: librarySessionID)
        authenticationGeneration = UUID()
        loginTask?.cancel()
        savePasswordTask?.cancel()
        isProcessing = false
        AlbumStore.shared.endSession()
        MediaLoaderService.shared.clearCache()
        ThumbnailImageLoader.shared.clearAll()
    }

    func resumeAlbumAccess() {
        if isAuthenticated, GuestModeManager.shared.isOwnerMode, let secret = sessionPassword {
            do {
                if vaultContext?.isActive != true {
                    if vaultContext != nil { librarySessionID = UUID() }
                    if let contextFactory {
                        vaultContext = try contextFactory(secondaryVaultID, librarySessionID, secret)
                    } else {
                        let storage: FileStorageService
                        if let id = secondaryVaultID {
                            let parent = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                .resolvingSymlinksInPath().appendingPathComponent("WagLockSecondaryMedia", isDirectory: true)
                            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                            try FreshEncryptedLibrary.safe(parent)
                            let root = parent.appendingPathComponent(id.uuidString, isDirectory: true)
                            if FileManager.default.fileExists(atPath: root.path) { try FreshEncryptedLibrary.safe(root) }
                            storage = FileStorageService(directory: root)
                        } else { storage = .shared }
                        vaultContext = try VaultSessionContext(vaultID: secondaryVaultID ?? Self.primaryVaultID,
                            sessionID: librarySessionID, dataPassword: secret, storage: storage,
                            temporaryRoot: FileManager.default.temporaryDirectory.appendingPathComponent("WagLockSessions"),
                            keychainNamespace: keychainService.contextNamespace, preservePrimaryNamespaces: isPrimaryVault)
                    }
                }
            } catch {
                logout(); errorMessage = "Unable to open this library. Lock and try again."; return
            }
            if isPrimaryVault {
                exports.beginSession(librarySessionID)
                documentPreviews.beginSession(librarySessionID)
                AlbumStore.shared.beginSession(vaultSecret: secret)
            }
        }
    }

    /// Toggle password visibility
    func togglePasswordVisibility() {
        showPassword.toggle()
    }

    /// Clear the input fields
    func clearFields() {
        password = ""
        confirmPassword = ""
        errorMessage = nil
    }

    /// Check whether a password is correct
    func verifyPassword(_ password: String) -> Bool {
        (try? verifyCurrentPassword(password)) == true
    }

    /// Selected-vault security operations share a durable budget, even after biometric entry.
    private func verifyCurrentPassword(_ password: String) throws -> Bool {
        guard isAuthenticated, GuestModeManager.shared.isOwnerMode else { throw VaultAccessError.locked }
        let limiter = keychainService.passwordAttemptLimiter(scope: "settings:" + (secondaryVaultID?.uuidString ?? "primary"))
        let reservation = try limiter.reserve()
        let valid: Bool
        if let id = secondaryVaultID {
            valid = (try? keychainService.unlockIndependentGuest(password: password).vaultID) == id
        } else { valid = keychainService.verifyPassword(password) }
        if valid {
            if independentVaultsEnabled, isPrimaryVault { try keychainService.upgradeAuthenticatedOwnerWrapping(using: password) }
            try limiter.recordSuccess(reservation)
        }
        return valid
    }

    var canChangeVaultPasswords: Bool {
        isAuthenticated && GuestModeManager.shared.isOwnerMode && isPrimaryVault
            && (!independentVaultsEnabled || vaultContext?.isActive == true)
    }

    /// Main-password changes are unavailable from a secondary session, even with its password.
    func updatePassword(oldPassword: String, newPassword: String) throws {
        guard canChangeVaultPasswords else { throw VaultAccessError.locked }
        guard try verifyCurrentPassword(oldPassword) else { throw VaultAccessError.invalidPassword }
        let dataPassword = try keychainService.changePassword(oldPassword: oldPassword, newPassword: newPassword)
        sessionPasswordData = SecureBytes(dataPassword)
        resumeAlbumAccess()
        MediaLoaderService.shared.clearCache()
        ThumbnailImageLoader.shared.clearAll()
    }

    /// Synchronous on the main actor: authorization and commit cannot straddle a scene/session change.
    func updateSecondaryPassword(primaryPassword: String, oldPassword: String, newPassword: String,
                                 expectedSessionID: UUID) throws {
        guard independentVaultsEnabled, canChangeVaultPasswords,
              librarySessionID == expectedSessionID, vaultContext?.isActive == true else {
            throw VaultAccessError.locked
        }
        _ = try keychainService.changeIndependentGuestPassword(primaryPassword: primaryPassword,
            oldPassword: oldPassword, newPassword: newPassword)
        // Preserve the primary session, both data keys and the existing biometric assignment.
    }

    func provisionSecondaryVault(password: String) throws {
        guard independentVaultsEnabled, isAuthenticated, isPrimaryVault else { throw VaultAccessError.locked }
        _ = try keychainService.provisionIndependentGuest(password: password)
    }
    var hasSecondaryVault: Bool {
        do { return try keychainService.independentGuestVaultID() != nil } catch { return true }
    }
    func makeSelectedLibraryMount() -> LibraryMountCoordinator {
        if let id = secondaryVaultID, let context = vaultContext {
            let root = LibraryStoragePolicy.defaultRoot.deletingLastPathComponent()
                .appendingPathComponent("WagLockSecondaryLibraries", isDirectory: true).appendingPathComponent(id.uuidString)
            return LibraryMountCoordinator(encryptedRoot: root, anchor: keychainService.secondaryIdentityAnchor(id),
                scope: .independentVault(id), storage: context.storage)
        }
        return LibraryMountCoordinator()
    }

    /// The UI supplies the exact typed confirmation; merely opening help never erases.
    func eraseLocalData(confirmation: String) async {
        guard confirmation == "ERASE", !isAuthenticated, !isProcessing, !isErasing,
              !requiresEraseCompletion, let resetService else { return }
        logout()
        isErasing = true; requiresEraseCompletion = true; eraseError = nil
        defer { isErasing = false }
        do {
            try resetService.begin()
            _ = try await resetService.resume()
            finishErasureState()
        } catch { eraseError = "Erasure could not finish. Unlock your device and retry. WagLock stays locked until cleanup completes." }
    }

    func resumePendingErase() async {
        guard !isErasing, let resetService else { return }
        logout()
        isErasing = true; eraseError = nil
        defer { isErasing = false }
        do {
            _ = try await resetService.resume()
            finishErasureState()
        } catch { eraseError = "Erasure could not finish. Unlock your device and retry. WagLock stays locked until cleanup completes." }
    }

    private func finishErasureState() {
        requiresEraseCompletion = false
        isBiometricUnlockEnabled = UserDefaults.standard.bool(forKey: "vaultito.faceID.enabled")
        failedAttempts = 0; lockoutUntil = nil
        clearFields(); checkPasswordStatus()
    }

    // MARK: - Computed Properties

    /// Whether the set-password button is enabled
    var isSetupButtonEnabled: Bool {
        !password.isEmpty && !confirmPassword.isEmpty && !isProcessing && !requiresEraseCompletion && !isErasing
    }

    /// Whether the login button is enabled
    var isLoginButtonEnabled: Bool {
        !password.isEmpty && !isProcessing && !requiresEraseCompletion && !isErasing
    }
}

// MARK: - Password Strength Indicator

extension AuthenticationViewModel {

    /// Password strength level
    enum PasswordStrength {
        case weak  // Weak
        case medium  // Medium
        case strong  // Strong

        var color: Color {
            switch self {
            case .weak: return .red
            case .medium: return .orange
            case .strong: return .green
            }
        }

        var text: String {
            switch self {
            case .weak: return String(localized: "passwordStrength.weak")
            case .medium: return String(localized: "passwordStrength.medium")
            case .strong: return String(localized: "passwordStrength.strong")
            }
        }
    }

    /// Calculate password strength
    var passwordStrength: PasswordStrength {
        let score = PasswordAssessment(password).score
        return score >= 80 ? .strong : score >= 40 ? .medium : .weak
    }
}
