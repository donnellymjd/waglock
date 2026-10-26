//
//  MainTabView.swift
//  WagLock
//
//  Main tab bar view
//  Tabs: Photos, Media, Files, Notes and Settings
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
            // Photos tab
            PhotosView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label(
                        String(localized: "tab.photos"),
                        systemImage: selectedTab == 0 ? "photo.fill" : "photo")
                }
                .tag(0)

            // Media tab (videos and audio combined)
            MediaView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label(
                        String(localized: "tab.media"),
                        systemImage: selectedTab == 1 ? "play.rectangle.on.rectangle.fill" : "play.rectangle.on.rectangle")
                }
                .tag(1)

            // Files tab
            FilesView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label(
                        String(localized: "tab.files"),
                        systemImage: selectedTab == 2 ? "folder.fill" : "folder")
                }
                .tag(2)

            // Secret space tab (now a regular notes tab)
            SecretSpaceView()
                .tabItem {
                    Label(
                        String(localized: "tab.secretSpace"),
                        systemImage: selectedTab == 3 ? "note.text" : "note")
                }
                .tag(3)

            // Settings tab
            SettingsView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label(
                        String(localized: "tab.settings"),
                        systemImage: selectedTab == 4 ? "gearshape.fill" : "gearshape")
                }
                .tag(4)
        }
        .tint(ColorTheme.accent)  // Tab bar selection color
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
