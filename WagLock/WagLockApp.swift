//
//  WagLockApp.swift
//  WagLock
//
//  Created by WangQiao on 2025/11/5.
//  Modified: Added the authentication flow and the MediaItem data model
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

    // The app-level scenePhase aggregates all scenes. iPad multi-window is not enabled
    // (no UIApplicationSupportsMultipleScenes), so with a single scene it matches the window state;
    // if multi-window is enabled later, the privacy cover and auto-lock must move to the scene level
    @Environment(\.scenePhase) private var scenePhase
    /// Time the app last went to the background (used for auto-lock)
    @State private var lastBackgroundedAt: Date?

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Show a different screen depending on authentication state
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
                        // Authenticated and not in the unauthenticated mode - show the main app
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
                        // Not authenticated - show the authentication screen
                        // Calculator login is retired; stale preferences cannot change authentication.
                        if authViewModel.isPasswordSet {
                            LoginView()
                                .environmentObject(authViewModel)
                                .environmentObject(guestModeManager)
                        } else {
                            // No password set - show password setup
                            SetupPasswordView()
                                .environmentObject(authViewModel)
                                .environmentObject(guestModeManager)
                        }
                    }
                }
                .accessibilityHidden(showLaunchScreen)
                .onAppear {
                    // Check password status at launch
                    authViewModel.checkPasswordStatus()
                    if screenCaptured { revokeCapturedSession() }
                }

                // Launch screen
                if showLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }

                // Privacy cover: hide decrypted content when leaving the foreground
                // so the snapshot the system takes for the app switcher doesn't leak anything
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
                // Show the launch screen for 1.5 seconds
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

    /// On returning to the foreground, decide whether to log out based on the auto-lock setting.
    /// The timer starts only after a real trip to the background (.background); a brief .inactive
    /// (e.g. pulling down Notification Center, an incoming call) doesn't lock, though the privacy cover still applies
    private func autoLockIfNeeded() {
        defer { lastBackgroundedAt = nil }

        // Don't auto-lock while recording or while an unsaved recording exists, so long background recordings aren't destroyed
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
