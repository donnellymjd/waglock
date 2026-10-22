//
//  AuthenticationViewModel.swift
//  WagLock
//
//  认证逻辑视图模型
//  管理登录、设置密码、认证状态
//

internal import Combine
import Foundation
import SwiftUI

/// 认证视图模型
@MainActor
final class AuthenticationViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 是否已认证
    @Published var isAuthenticated: Bool = false

    /// Fresh identity whenever session key material is replaced or cleared.
    @Published private(set) var librarySessionID = UUID()

    /// 是否已设置密码
    @Published var isPasswordSet: Bool = false

    /// 当前输入的密码
    @Published var password: String = ""

    /// 确认密码（设置时使用）
    @Published var confirmPassword: String = ""

    /// 错误消息
    @Published var errorMessage: String?

    /// 是否正在处理
    @Published var isProcessing: Bool = false

    /// 是否显示密码
    @Published var showPassword: Bool = false

    /// 加密用密码（引用语义容器，置换/登出时就地清零）
    @Published private(set) var sessionPasswordData: SecureBytes? {
        willSet {
            // 零化旧密码内存
            sessionPasswordData?.wipe()
        }
        didSet {
            exports.endSession(matching: librarySessionID)
            documentPreviews.endSession(matching: librarySessionID)
            librarySessionID = UUID()
            AlbumStore.shared.endSession()
        }
    }

    /// 当前登录密码（用户本次输入，用于显示/修改配置）
    @Published private(set) var sessionLoginPassword: String?

    /// 获取会话密码（String格式，仅在需要时转换）
    var sessionPassword: String? {
        sessionPasswordData?.string
    }

    /// 登录失败次数
    @Published private(set) var failedAttempts: Int = 0

    /// 锁定截止时间
    @Published private(set) var lockoutUntil: Date?

    // MARK: - Constants

    private let maxAttempts = 5  // 最多尝试5次
    private let lockoutDuration: TimeInterval = 300  // 锁定5分钟

    // MARK: - Services

    typealias DataPasswordLoader = @MainActor (String) async throws -> String
    private let loadDataPassword: DataPasswordLoader
    private let exports: ExportService
    private let documentPreviews: DocumentPreviewService
    private let keychainService: KeychainService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Task Management

    private var loginTask: Task<Void, Never>?
    private var savePasswordTask: Task<Void, Never>?
    private var authenticationGeneration = UUID()
    @Published private(set) var isBiometricUnlockEnabled = UserDefaults.standard.bool(forKey: "vaultito.faceID.enabled")

    // MARK: - Initialization

    init(keychainService: KeychainService? = nil, manageInstallationState: Bool = true,
         dataPasswordLoader: DataPasswordLoader? = nil, exportService: ExportService? = nil,
         documentPreviewService: DocumentPreviewService? = nil) {
        let keychainService = keychainService ?? .shared
        self.exports = exportService ?? .shared
        self.documentPreviews = documentPreviewService ?? .shared
        self.keychainService = keychainService
        self.loadDataPassword = dataPasswordLoader ?? { password in
            try await Task.detached { try await keychainService.retrieveDataPassword(using: password) }.value
        }
        if manageInstallationState { markInstallationInitialized() }
        checkPasswordStatus()
        setupNotificationObservers()
    }

    deinit {
        // 取消所有进行中的任务
        loginTask?.cancel()
        savePasswordTask?.cancel()
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // 监听伪装模式解锁通知
        NotificationCenter.default.publisher(for: .unlockFromDisguise)
            .sink { [weak self] notification in
                Task { @MainActor in
                    // 获取解锁模式（owner 或 guest）和密码
                    let mode = notification.userInfo?["mode"] as? String ?? "owner"
                    let password = notification.userInfo?["password"] as? String ?? ""
                    await self?.handleDisguiseUnlock(mode: mode, password: password)
                }
            }
            .store(in: &cancellables)
    }

    private func handleDisguiseUnlock(mode: String, password: String) async {
        guard !isAuthenticated, !isProcessing, !password.isEmpty,
              lockoutUntil.map({ Date() >= $0 }) ?? true else { return }
        let token = UUID()
        authenticationGeneration = token
        isProcessing = true
        defer { if token == authenticationGeneration { isProcessing = false } }
        do {
            let dataPassword: String
            if mode == "guest" {
                let valid = await Task.detached {
                    await self.keychainService.verifyGuestPassword(password)
                }.value
                guard valid else { throw VaultAccessError.invalidPassword }
                dataPassword = password
            } else {
                dataPassword = try await loadDataPassword(password)
            }
            guard token == authenticationGeneration, !Task.isCancelled, !isAuthenticated else { return }
            sessionPasswordData = SecureBytes(dataPassword)
            sessionLoginPassword = password
            GuestModeManager.shared.setAuthenticationMode(mode == "guest" ? .guest : .owner)
            isAuthenticated = true
            resumeAlbumAccess()
        } catch {
            guard token == authenticationGeneration, !Task.isCancelled else { return }
            errorMessage = String(localized: "auth.error.disguiseUnlockFailed")
        }
    }

    // MARK: - Public Methods

    /// Preferences are not evidence that recoverable Keychain material is orphaned.
    private func markInstallationInitialized() {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.appInitialized)
    }

    /// 检查密码设置状态
    func checkPasswordStatus() {
        isPasswordSet = keychainService.isPasswordSet()
    }

    /// 设置密码（首次）
    func setupPassword() {
        guard !isProcessing else { return }

        // 清除之前的错误
        errorMessage = nil

        // 验证密码
        let validation = KeychainService.validatePasswordStrength(password)
        guard validation.isValid else {
            errorMessage = validation.message
            return
        }

        // 检查密码匹配
        guard password == confirmPassword else {
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

                // 保存成功
                sessionPasswordData = SecureBytes(dataPassword)
                sessionLoginPassword = inputPassword
                isPasswordSet = true
                isAuthenticated = true

                // 设置为主人模式（首次设置密码后直接进入主页）
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

    /// 登录验证
    @discardableResult
    func login() -> Task<Void, Never>? {
        guard !isProcessing else { return nil }

        // 取消之前的登录任务
        loginTask?.cancel()

        // 清除之前的错误
        errorMessage = nil

        // 🔒 检查是否被锁定
        if let lockoutUntil = lockoutUntil, Date() < lockoutUntil {
            let remaining = Int(lockoutUntil.timeIntervalSinceNow)
            let minutes = remaining / 60
            let seconds = remaining % 60
            if minutes > 0 {
                errorMessage = String(
                    format: String(localized: "auth.error.tooManyAttemptsMinutes"),
                    minutes,
                    seconds)
            } else {
                errorMessage = String(
                    format: String(localized: "auth.error.tooManyAttemptsSeconds"),
                    seconds)
            }
            return nil
        }

        // 检查密码非空
        guard !password.isEmpty else {
            errorMessage = AppConstants.ErrorMessages.passwordEmpty
            return nil
        }

        isProcessing = true
        let inputPassword = password
        let token = UUID()
        authenticationGeneration = token

        // 创建新的登录任务
        loginTask = Task(priority: .userInitiated) {
            defer { if token == authenticationGeneration { isProcessing = false } }
            // 在后台执行耗时的Keychain操作，避免阻塞主线程
            let ownerMatch = await Task.detached {
                await self.keychainService.verifyPassword(inputPassword)
            }.value

            let guestMatch = await Task.detached {
                guard await self.keychainService.isGuestPasswordSet() else { return false }
                return await self.keychainService.verifyGuestPassword(inputPassword)
            }.value

            guard token == authenticationGeneration, !Task.isCancelled else { return }

            // 回到主线程更新UI状态
            if ownerMatch {
                do {
                    let dataPassword = try await loadDataPassword(inputPassword)
                    guard token == authenticationGeneration, !Task.isCancelled else { return }

                    sessionPasswordData = SecureBytes(dataPassword)
                    sessionLoginPassword = inputPassword
                    isAuthenticated = true

                    // 设置为主人模式
                    GuestModeManager.shared.setAuthenticationMode(.owner)
                    resumeAlbumAccess()

                    // ✅ 登录成功，重置失败计数
                    failedAttempts = 0
                    lockoutUntil = nil

                    clearFields()
                } catch {
                    guard token == authenticationGeneration, !Task.isCancelled else { return }
                    errorMessage = String(localized: "auth.error.loadKeyFailed")
                }
            } else if guestMatch {
                // 访客模式登录成功
                // 保存访客密码以便伪装模式解锁时使用
                sessionPasswordData = SecureBytes(inputPassword)
                sessionLoginPassword = inputPassword
                isAuthenticated = true

                // 设置为访客模式
                GuestModeManager.shared.setAuthenticationMode(.guest)

                // ✅ 登录成功，重置失败计数
                failedAttempts = 0
                lockoutUntil = nil

                clearFields()
            } else {
                // ❌ 两个密码都验证失败
                failedAttempts += 1
                password = ""

                // 检查是否需要锁定
                if failedAttempts >= maxAttempts {
                    lockoutUntil = Date().addingTimeInterval(lockoutDuration)
                    errorMessage = String(
                        format: String(localized: "auth.error.lockedMinutes"),
                        Int(lockoutDuration / 60))
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

    /// 登出
    func logout() {
        authenticationGeneration = UUID()
        loginTask?.cancel()
        savePasswordTask?.cancel()
        isProcessing = false
        isAuthenticated = false

        // 🔒 安全清理密码内存（willSet 中就地清零）
        sessionPasswordData = nil
        sessionLoginPassword = nil

        // 清空解密图片缓存，确保明文像素不跨会话残留
        MediaLoaderService.shared.clearCache()
        ThumbnailImageLoader.shared.clearAll()

        // 重置访客模式为主人模式
        GuestModeManager.shared.reset()

        clearFields()
    }

    func enableBiometricUnlock(password: String) async throws {
        guard isAuthenticated, GuestModeManager.shared.isOwnerMode,
              keychainService.verifyPassword(password) else { throw VaultAccessError.invalidPassword }
        let token = authenticationGeneration
        let secret = try keychainService.retrieveDataPassword(using: password)
        try await BiometricSecretStore.shared.store(secret, account: BiometricSecretStore.vaultAccount) {
            token == self.authenticationGeneration && self.isAuthenticated
                && GuestModeManager.shared.isOwnerMode
        }
        guard token == authenticationGeneration, !Task.isCancelled, isAuthenticated, GuestModeManager.shared.isOwnerMode else {
            // Do not delete a shared account that a newer authorized enrollment may own.
            throw CancellationError()
        }
        isBiometricUnlockEnabled = true
        UserDefaults.standard.set(true, forKey: "vaultito.faceID.enabled")
    }

    func disableBiometricUnlock() {
        guard isAuthenticated, GuestModeManager.shared.isOwnerMode else { return }
        authenticationGeneration = UUID()
        BiometricSecretStore.shared.remove(account: BiometricSecretStore.vaultAccount)
        isBiometricUnlockEnabled = false
        UserDefaults.standard.set(false, forKey: "vaultito.faceID.enabled")
    }

    func loginWithBiometrics() async {
        guard !isProcessing, !isAuthenticated, isPasswordSet, isBiometricUnlockEnabled else { return }
        isProcessing = true
        errorMessage = nil
        let token = authenticationGeneration
        defer { if token == authenticationGeneration { isProcessing = false } }
        do {
            let secret = try await BiometricSecretStore.shared.read(
                account: BiometricSecretStore.vaultAccount, reason: "Unlock WagLock")
            guard token == authenticationGeneration, !isAuthenticated else { throw CancellationError() }
            sessionPasswordData = SecureBytes(secret)
            sessionLoginPassword = nil
            isAuthenticated = true
            GuestModeManager.shared.setAuthenticationMode(.owner)
            resumeAlbumAccess()
            failedAttempts = 0
            lockoutUntil = nil
            clearFields()
        } catch {
            guard token == authenticationGeneration else { return }
            errorMessage = "Biometric unlock was cancelled or unavailable. Use your vault password."
        }
    }

    func suspendAlbumAccess() {
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
            exports.beginSession(librarySessionID)
            documentPreviews.beginSession(librarySessionID)
            AlbumStore.shared.beginSession(vaultSecret: secret)
        }
    }

    /// 切换密码可见性
    func togglePasswordVisibility() {
        showPassword.toggle()
    }

    /// 清除输入字段
    func clearFields() {
        password = ""
        confirmPassword = ""
        errorMessage = nil
    }

    /// 验证密码是否正确
    func verifyPassword(_ password: String) -> Bool {
        return keychainService.verifyPassword(password)
    }

    /// 更新密码（重新加密后调用）
    func updatePassword(oldPassword: String, newPassword: String) throws {
        let dataPassword = try keychainService.changePassword(
            oldPassword: oldPassword,
            newPassword: newPassword
        )
        sessionPasswordData = SecureBytes(dataPassword)
        sessionLoginPassword = newPassword
        resumeAlbumAccess()

        // 密码变更同样清空明文图片缓存，只保留新会话下的解密结果
        MediaLoaderService.shared.clearCache()
        ThumbnailImageLoader.shared.clearAll()
    }

    // MARK: - Computed Properties

    /// 设置密码按钮是否可用
    var isSetupButtonEnabled: Bool {
        !password.isEmpty && !confirmPassword.isEmpty && !isProcessing
    }

    /// 登录按钮是否可用
    var isLoginButtonEnabled: Bool {
        !password.isEmpty && !isProcessing
    }
}

// MARK: - Password Strength Indicator

extension AuthenticationViewModel {

    /// 密码强度等级
    enum PasswordStrength {
        case weak  // 弱
        case medium  // 中等
        case strong  // 强

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

    /// 计算密码强度
    var passwordStrength: PasswordStrength {
        let score = PasswordAssessment(password).score
        return score >= 80 ? .strong : score >= 40 ? .medium : .weak
    }
}
