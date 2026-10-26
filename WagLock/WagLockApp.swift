//
//  WagLockApp.swift
//  WagLock
//
//  Created by WangQiao on 2025/11/5.
//  Modified: 添加认证流程和MediaItem数据模型
//

import SwiftData
import SwiftUI

@main
struct WagLockApp: App {
    init() {
        ProtectedTemporaryFiles.removeAbandonedJobs()
        ProtectedTemporaryFiles.removeAbandonedJobs(in: FileManager.default.temporaryDirectory
            .appendingPathComponent("WagLockSessions").appendingPathComponent("WagLockSessionJobs"))
        MediaImportService.removeAbandonedProviderCopies()
        ExportService.shared.cleanupAbandonedExports()
        PortableBackupSession.cleanupAbandonedJobs()
        AlbumStore.removeAbandonedTemporaryFiles()
        EncryptionService.shared.removeAbandonedStagingFiles(in: FileManager.default.temporaryDirectory)
        EncryptionService.shared.removeAbandonedStagingFiles(in: FileStorageService.shared.getStorageDirectory())
    }

    // MARK: - State

    @StateObject private var authViewModel = AuthenticationViewModel()
    @StateObject private var guestModeManager = GuestModeManager.shared
    @AppStorage(WagLockAppearance.preferenceKey) private var appearance = WagLockAppearance.system.rawValue
    @State private var showLaunchScreen = true
    @State private var screenCaptured = UIScreen.main.isCaptured

    // App 级 scenePhase 是所有 scene 的聚合状态。当前未开启 iPad 多窗口
    // （无 UIApplicationSupportsMultipleScenes），单 scene 下与窗口状态等价；
    // 若日后启用多窗口，隐私遮罩/自动锁定需下沉到 scene 级别
    @Environment(\.scenePhase) private var scenePhase
    /// 最近一次进入后台的时间（用于自动锁定判定）
    @State private var lastBackgroundedAt: Date?

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 根据认证状态显示不同界面
                Group {
                    if screenCaptured {
                        VStack(spacing: 16) {
                            Image(systemName: "eye.slash.fill").font(.largeTitle)
                            Text("WagLock is locked").font(.title2.bold())
                            Text("Stop screen recording or mirroring to continue.")
                                .multilineTextAlignment(.center)
                        }
                        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ColorTheme.primaryBackground)
                        .accessibilityIdentifier("privacy.screenCapture")
                    } else if authViewModel.requiresEraseCompletion {
                        EraseCompletionView().environmentObject(authViewModel)
                    } else if authViewModel.isAuthenticated
                        && guestModeManager.currentMode != .unauthenticated
                    {
                        // 已认证且模式不为未认证状态 - 显示主应用
                        Group {
                            if let services = authViewModel.vaultContext {
                                AuthenticatedLibraryView(services: services, library: authViewModel.makeSelectedLibraryMount())
                                    .id(services.sessionID)
                            }
                        }
                            .id(authViewModel.librarySessionID)
                            .environmentObject(authViewModel)
                            .environmentObject(guestModeManager)
                    } else {
                        // 未认证 - 显示认证界面
                        // Calculator login is retired; stale preferences cannot change authentication.
                        if authViewModel.isPasswordSet {
                            LoginView()
                                .environmentObject(authViewModel)
                                .environmentObject(guestModeManager)
                        } else {
                            // 未设置密码 - 显示设置密码界面
                            SetupPasswordView()
                                .environmentObject(authViewModel)
                                .environmentObject(guestModeManager)
                        }
                    }
                }
                .accessibilityHidden(showLaunchScreen)
                .onAppear {
                    // 应用启动时检查密码状态
                    authViewModel.checkPasswordStatus()
                    if screenCaptured { revokeCapturedSession() }
                }

                // 启动页
                if showLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }

                // 隐私遮罩：离开前台时盖住已解密内容，
                // 防止系统为多任务切换器截取的快照泄露隐私
                if authViewModel.isAuthenticated && scenePhase != .active && !showLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .preferredColorScheme((WagLockAppearance(rawValue: appearance) ?? .system).colorScheme)
            .tint(ColorTheme.accent)
            .environment(\.locale, AppConstants.presentationLocale)
            .task {
                // 显示启动页1.5秒
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation(.easeOut(duration: 0.5)) {
                    showLaunchScreen = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                screenCaptured = UIScreen.main.isCaptured
                if screenCaptured { revokeCapturedSession() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    lastBackgroundedAt = Date()
                    // Fresh 1.0 libraries always drop their session keys on background.
                    // New recording is disabled there; preserve the legacy Dev recording policy.
                    authViewModel.handleBackground(lockImmediately: LibraryStoragePolicy.encryptedMetadata)
                case .active:
                    screenCaptured = UIScreen.main.isCaptured
                    if screenCaptured { revokeCapturedSession() }
                    ExportService.shared.retryCleanup()
                    PortableBackupSession.retryCleanup()
                    let returnedFromBackground = lastBackgroundedAt != nil
                    autoLockIfNeeded()
                    if returnedFromBackground { authViewModel.resumeAlbumAccess() }
                    authViewModel.vaultContext?.audio.tick()
                default:
                    break
                }
            }
        }
    }

    private func revokeCapturedSession() {
        authViewModel.handleBackground(lockImmediately: true)
        authViewModel.vaultContext?.audio.stopPlayback()
    }

    // MARK: - Auto Lock

    /// 回到前台时按"离开后自动锁定"设置决定是否登出。
    /// 只在真正进过后台（.background）后计时；短暂的 .inactive
    /// （如下拉通知中心、来电）不触发锁定，但隐私遮罩仍会覆盖
    private func autoLockIfNeeded() {
        defer { lastBackgroundedAt = nil }

        // 正在录音或存在未保存录音时，不执行自动锁定，确保长时间后台录音稳定不被销毁
        guard !(authViewModel.vaultContext?.audio.hasRecording ?? false) else { return }

        guard authViewModel.isAuthenticated,
            let backgroundedAt = lastBackgroundedAt
        else { return }

        let timeout = AppSettings.shared.autoLockTimeout
        guard timeout != .never else { return }

        if Date().timeIntervalSince(backgroundedAt) >= Double(timeout.rawValue) {
            authViewModel.logout()
        }
    }
}
