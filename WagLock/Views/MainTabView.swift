//
//  MainTabView.swift
//  WagLock
//
//  Main tab bar view
//  Tabs: Library, Albums, Files, Notes and Settings
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
            LibraryView()
                .environmentObject(authViewModel)
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
                .tag(0)

            AlbumsTabView()
                .tabItem { Label("Albums", systemImage: "rectangle.stack") }
                .tag(1)

            FilesView()
                .environmentObject(authViewModel)
                .tabItem { Label(String(localized: "tab.files"), systemImage: "folder") }
                .tag(2)

            SecretSpaceView()
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(3)

            SettingsView()
                .environmentObject(authViewModel)
                .tabItem { Label(String(localized: "tab.settings"), systemImage: "slider.horizontal.3") }
                .tag(4)
        }
        .tint(ColorTheme.accent)  // Tab bar selection color
        .task {
            await Task.yield()
            guard services.isActive, authViewModel.isAuthenticated, GuestModeManager.shared.isOwnerMode,
                  authViewModel.librarySessionID == services.sessionID else { return }
            showBackupReminder = reminders.claimDuePrompt()
        }
        .alert("Time to back up WagLock", isPresented: $showBackupReminder) {
            Button("Open backups") { showBackup = true }
            Button("Remind me in a week") { reminders.remindInAWeek() }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("Keep a recoverable encrypted copy of this library. You choose where to save it.")
        }
        .sheet(isPresented: $authViewModel.showsFirstBackupSetup) {
            FirstBackupSetupView()
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
