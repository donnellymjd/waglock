//
//  MainTabView.swift
//  WagLock
//
//  主标签栏视图
//  包含：相片、影音、文件、记事本、设置五个标签
//

import SwiftUI

struct MainTabView: View {

    // MARK: - Environment

    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @EnvironmentObject private var services: VaultSessionContext
    @EnvironmentObject private var reminders: BackupReminderStore
    @State private var showBackupReminder = false
    @State private var showBackup = false
    @State private var selectedTab = 0

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            // 相片标签
            PhotosView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label(
                        String(localized: "tab.photos"),
                        systemImage: selectedTab == 0 ? "photo.fill" : "photo")
                }
                .tag(0)

            // 影音标签（合并视频与音频）
            MediaView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label(
                        String(localized: "tab.media"),
                        systemImage: selectedTab == 1 ? "play.rectangle.on.rectangle.fill" : "play.rectangle.on.rectangle")
                }
                .tag(1)

            // 文件标签
            FilesView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label(
                        String(localized: "tab.files"),
                        systemImage: selectedTab == 2 ? "folder.fill" : "folder")
                }
                .tag(2)

            // 隐藏空间标签（现在作为普通记事本）
            SecretSpaceView()
                .tabItem {
                    Label(
                        String(localized: "tab.secretSpace"),
                        systemImage: selectedTab == 3 ? "note.text" : "note")
                }
                .tag(3)

            // 设置标签
            SettingsView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label(
                        String(localized: "tab.settings"),
                        systemImage: selectedTab == 4 ? "gearshape.fill" : "gearshape")
                }
                .tag(4)
        }
        .tint(ColorTheme.accent)  // TabBar 选中颜色
        .task {
            await Task.yield()
            guard services.isActive, authViewModel.isAuthenticated, GuestModeManager.shared.isOwnerMode,
                  authViewModel.librarySessionID == services.sessionID else { return }
            showBackupReminder = reminders.claimDuePrompt()
        }
        .alert("Time for a backup", isPresented: $showBackupReminder) {
            Button("Open backups") { showBackup = true }
            Button("Remind me in a week") { reminders.remindInAWeek() }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("Keep a recoverable encrypted copy of this library. You choose where to save it.")
        }
        .sheet(isPresented: $showBackup) {
            NavigationStack {
                PortableBackupView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showBackup = false } } }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
        .environmentObject(AuthenticationViewModel())
}
