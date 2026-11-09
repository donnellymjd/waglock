//
//  SettingsView.swift
//  WagLock
//
//  Settings view
//  App configuration, storage management and security settings
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext
    @EnvironmentObject private var backupReminders: BackupReminderStore

    // MARK: - Environment

    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AppSettings.shared

    // MARK: - State

    @EnvironmentObject private var guestModeManager: GuestModeManager
    @StateObject private var iconService = AppIconService()
    @State private var showLogoutConfirmation = false
    @State private var showChangePasswordSheet = false
    @State private var showAboutSheet = false
    @State private var showGuestModeSetup = false
    @State private var showAlternativePasswordChange = false
    @State private var showGuestModeDisableConfirmation = false
    @State private var storageInfo: StorageInfo?
    @State private var isLoadingStorage = false
    @State private var showClearCacheConfirmation = false
    @State private var counts = (photos: 0, videos: 0, audio: 0, files: 0)

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        WagLockTitle(text: String(localized: "settings.title"))
                        Spacer()
                        Button("Lock now") { showLogoutConfirmation = true }
                            .font(WagLockFonts.poppins(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(Graphite.accentText).frame(minHeight: 44)
                            .accessibilityIdentifier("settings.lockNow")
                    }
                    if guestModeManager.isOwnerMode { backupCard }
                    VStack(spacing: 10) {
                        NavigationLink { securityDestination } label: {
                            WagLockRow(symbol: "lock.shield", title: "Security & access", detail: securitySummary)
                        }.buttonStyle(.plain).accessibilityIdentifier("settings.security")
                        if guestModeManager.isOwnerMode {
                            NavigationLink { AppIconSettingsView() } label: {
                                WagLockRow(symbol: "app.badge", title: "App icon", detail: currentIconTitle)
                            }.buttonStyle(.plain).accessibilityIdentifier("settings.appIcon")
                        }
                        NavigationLink { layoutScreen } label: {
                            WagLockRow(symbol: "square.grid.3x3", title: "Library layout",
                                       detail: "\(settings.gridColumns) columns · \(settings.sortOrder.displayName)")
                        }.buttonStyle(.plain).accessibilityIdentifier("settings.layout")
                        NavigationLink { storageScreen } label: {
                            WagLockRow(symbol: "internaldrive", title: "Storage",
                                       detail: storageInfo.map { "\($0.formattedTotalUsed) used by this library" } ?? "Calculating storage…")
                        }.buttonStyle(.plain).accessibilityIdentifier("settings.storage")
                        if guestModeManager.isOwnerMode {
                            NavigationLink { PortableBackupView() } label: {
                                WagLockRow(symbol: "externaldrive.badge.icloud", title: "Encrypted backup",
                                           detail: "Export to Files, iCloud Drive or another provider")
                            }.buttonStyle(.plain).accessibilityIdentifier("settings.backup")
                        }
                        Button { showAboutSheet = true } label: {
                            WagLockRow(symbol: "info.circle", title: "About WagLock",
                                       detail: LibraryStoragePolicy.encryptedMetadata ? "Open source · On-device encryption" : "Open source · Early test build")
                        }.buttonStyle(.plain).accessibilityIdentifier("settings.about")
                    }
                    Button { showLogoutConfirmation = true } label: { Text("Lock WagLock") }
                        .buttonStyle(WagLockDestructiveButtonStyle()).accessibilityIdentifier("settings.lock")
                }
                .padding(.horizontal, 22).padding(.vertical, 12)
            }
            .background(Graphite.base)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { iconService.refresh() }
        }
        .confirmationDialog(
            String(localized: "settings.logout.title"), isPresented: $showLogoutConfirmation
        ) {
            Button(String(localized: "settings.logout.confirm"), role: .destructive) {
                authViewModel.logout()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.logout.message"))
        }
        .sheet(isPresented: $showChangePasswordSheet) {
            if authViewModel.canChangeVaultPasswords {
                ChangePasswordView().environmentObject(authViewModel)
            }
        }
        .sheet(isPresented: $showAlternativePasswordChange) {
            if authViewModel.canChangeVaultPasswords {
                AlternativePasswordChangeView(sessionID: authViewModel.librarySessionID)
                    .environmentObject(authViewModel)
            }
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutView()
        }
        .sheet(isPresented: $showGuestModeSetup) {
            GuestModeSetupView {
                // Enable guest mode once setup is complete
                settings.guestModeEnabled = true
            }
        }
        .confirmationDialog(
            String(localized: "guestMode.disable.title"),
            isPresented: $showGuestModeDisableConfirmation
        ) {
            Button(String(localized: "guestMode.disable.action"), role: .destructive) {
                disableGuestMode()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "guestMode.disable.message"))
        }
        .confirmationDialog(
            String(localized: "settings.clearCache.title"), isPresented: $showClearCacheConfirmation
        ) {
            Button(String(localized: "settings.clearCache.confirm"), role: .destructive) {
                clearCache()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            if let cacheSize = storageInfo?.formattedCacheSize {
                Text(String(format: String(localized: "settings.clearCache.message"), cacheSize))
            }
        }
        .task {
            await loadStorageInfo()
        }
    }

    private var currentIconTitle: String {
        (AppIconOption.allCases.first { $0.iconName == iconService.selectedIconName } ?? .primary).title
    }

    private func settingsHeading(_ title: String) -> some View {
        Text(title).font(.footnote).foregroundStyle(ColorTheme.secondaryText)
    }

    private func settingsCard(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 0) {
            WagLockNavigationRow(symbol: symbol, title: title, detail: detail)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                .foregroundStyle(ColorTheme.secondaryText).padding(.trailing, 14)
        }.background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private var layoutScreen: some View {
        Form {
            Section("Grid columns") {
                Stepper("Columns: \(settings.gridColumns)", value: $settings.gridColumns, in: 2...5)
            }
            Section("Sort order") {
                Picker("Sort order", selection: $settings.sortOrder) {
                    ForEach(MediaItem.SortOrder.allCases) { order in Text(order.displayName).tag(order) }
                }.pickerStyle(.inline)
            }
        }.wagLockList().navigationTitle("Library layout")
    }

    /// Identical in every library with library slots; the inherited list otherwise.
    @ViewBuilder private var securityDestination: some View {
        if authViewModel.usesLibrarySlots {
            SecurityAccessView()
        } else {
            List { securitySection }.wagLockList().navigationTitle("Security & access")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var securitySummary: String {
        if authViewModel.usesLibrarySlots {
            return (authViewModel.isBiometricAssignedHere ? "Face ID on" : "Face ID off") + " · Locks immediately"
        }
        return LibraryStoragePolicy.encryptedMetadata ? (authViewModel.canManageBiometricUnlock ? "Face ID and auto-lock" : "Auto-lock") : "Face ID, password and Guest Mode"
    }

    private var backupCard: some View {
        let last = backupReminders.lastSaved
        let due = backupReminders.nextReminder.map { $0 <= Date() } ?? (last == nil)
        return VStack(alignment: .leading, spacing: 12) {
            if due {
                Text("BACKUP DUE").font(WagLockFonts.poppins(11, .semibold, relativeTo: .caption)).tracking(1.5)
                    .foregroundStyle(Graphite.warn).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Graphite.warnTint, in: Capsule())
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Last backup").font(.wlMeta).foregroundStyle(Graphite.textMuted)
                Text(last.map { $0.formatted(.relative(presentation: .named)) } ?? "Not yet")
                    .font(WagLockFonts.poppins(22, .extraBold, relativeTo: .title2)).foregroundStyle(Graphite.textPrimary)
            }
            Text("There’s no passcode reset, so an encrypted backup is your way back.")
                .font(.wlMeta).foregroundStyle(Graphite.textSecondary).fixedSize(horizontal: false, vertical: true)
            NavigationLink { PortableBackupView() } label: { Text("Back up now") }
                .buttonStyle(WagLockPrimaryButtonStyle()).accessibilityIdentifier("settings.backupNow")
            HStack(spacing: 4) {
                Text("Reminders: \(backupReminders.frequency.title) ·").foregroundStyle(Graphite.textMuted)
                NavigationLink("Change") { BackupReminderSettingsView() }
                    .foregroundStyle(Graphite.accentText).accessibilityIdentifier("settings.backupReminders")
            }.font(.wlMeta)
        }
        .padding(16)
        .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(due ? Graphite.warn.opacity(0.35) : .clear, lineWidth: 1))
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Group {
            Section("UNLOCKING") {
                if guestModeManager.isOwnerMode {
                    if authViewModel.canManageBiometricUnlock {
                    NavigationLink { BiometricSettingsView() } label: {
                        securityRow("faceid", "Face ID", authViewModel.isBiometricUnlockEnabled ? "Enabled" : "Disabled")
                    }.accessibilityIdentifier("settings.faceID").wagLockCardRow()
                    }
                    if authViewModel.canChangeVaultPasswords {
                        Button { showChangePasswordSheet = true } label: {
                            securityRow("key", "Change password", "Verify your current password")
                        }.accessibilityIdentifier("settings.changePassword").wagLockCardRow()
                    }
                }
                if LibraryStoragePolicy.encryptedMetadata {
                    securityRow("lock.rotation", "Auto-lock", "Immediately when you leave the app")
                        .accessibilityIdentifier("settings.autoLock.immediate").wagLockCardRow()
                } else {
                NavigationLink {
                    List {
                        Section {
                            ForEach(AutoLockTimeout.allCases) { timeout in
                                Button { settings.autoLockTimeout = timeout } label: {
                                    HStack {
                                        Text(timeout.title).foregroundStyle(ColorTheme.primaryText)
                                        Spacer()
                                        if settings.autoLockTimeout == timeout { Image(systemName: "checkmark").foregroundStyle(ColorTheme.accent) }
                                    }.frame(minHeight: 36)
                                }
                            }
                        } footer: { Text("Choose when WagLock locks after you leave the app. A short timeout limits access on an unattended phone.") }
                    }.wagLockList().navigationTitle("Auto-lock")
                } label: { securityRow("lock.rotation", "Auto-lock", settings.autoLockTimeout.title) }
                    .accessibilityIdentifier("settings.autoLock").wagLockCardRow()
                }
            }
            Section {
                if LibraryStoragePolicy.encryptedMetadata && authViewModel.isPrimaryVault {
                    if authViewModel.hasSecondaryVault {
                        Button { showAlternativePasswordChange = true } label: {
                            securityRow("key.horizontal", "Change alternative password", "Verify both current passwords")
                        }.accessibilityIdentifier("settings.guest.changePassword").wagLockCardRow()
                    } else {
                        Button { showGuestModeSetup = true } label: {
                            securityRow("eye.slash", "Set up alternative passcode", "Open a separate encrypted library")
                        }.accessibilityIdentifier("settings.guest.configure").wagLockCardRow()
                    }
                }
                if guestModeManager.isOwnerMode && !LibraryStoragePolicy.encryptedMetadata {
                    NavigationLink {
                        List {
                            Section { guestModeRow }
                            Section {
                                WagLockInfoCard(title: "Presentation only", detail: "Guest Mode hides content; it is not a separate encrypted vault. Independent alternative-vault protection is still in development.")
                                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                            }
                        }.wagLockList().navigationTitle("Guest Mode")
                    } label: { securityRow("eye.slash", "Guest Mode", "Hides content · Not a separate vault") }
                        .accessibilityIdentifier("settings.guest").wagLockCardRow()
                }
            }
            Section {
                WagLockInfoCard(title: "Keep your password safe", detail: "There is no password reset. Keep independent originals.")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                Button("Log Out", role: .destructive) { showLogoutConfirmation = true }
            }
        }
    }

    private func securityRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(ColorTheme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(ColorTheme.primaryText)
                Text(detail).font(.footnote).foregroundStyle(ColorTheme.secondaryText)
            }
        }.frame(minHeight: 38)
    }

    private var storageScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WagLockTitle(text: "Storage")
                WagLockSectionLabel("This library")
                VStack(alignment: .leading, spacing: 4) {
                    Text(storageInfo?.formattedTotalUsed ?? "Calculating…")
                        .font(WagLockFonts.poppins(28, .extraBold, relativeTo: .title)).foregroundStyle(Graphite.textPrimary)
                    Text(itemCounts).font(.wlMeta).foregroundStyle(Graphite.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                StorageModeSection()
                Button { showClearCacheConfirmation = true } label: {
                    WagLockRow(symbol: "photo.stack", title: "Clear cache", detail: "Previews rebuild when needed")
                }.buttonStyle(.plain).accessibilityIdentifier("settings.clearCache")
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }.background(Graphite.base).navigationBarTitleDisplayMode(.inline)
    }

    private var itemCounts: String {
        func plural(_ count: Int, _ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }
        return [plural(counts.photos, "photo"), plural(counts.videos, "video"), "\(counts.audio) audio", plural(counts.files, "file")]
            .joined(separator: " · ")
    }

    // MARK: - Methods

    private func loadStorageInfo() async {
        isLoadingStorage = true
        defer { isLoadingStorage = false }

        storageInfo = await StorageService.shared.getStorageInfo(modelContext: modelContext, storage: vaultServices.storage)
        // This library's own records only; nothing here reads another library.
        func count(_ type: String) -> Int {
            (try? modelContext.fetchCount(FetchDescriptor<MediaItem>(predicate: #Predicate { $0.typeRawValue == type }))) ?? 0
        }
        counts = (count("photo"), count("video"), count("audio"), count("document"))
    }

    private func clearCache() {
        Task {
            do {
                vaultServices.mediaLoader.clearCache()
                vaultServices.thumbnails.clearAll()

                // Reload storage info
                await loadStorageInfo()
            } catch {
            }
        }
    }

    // MARK: - Guest Mode

    private var guestModeRow: some View {
        VStack(spacing: 0) {
            HStack {
                Label(String(localized: "guestMode.title"), systemImage: "person.2.fill")

                Spacer()

                if KeychainService.shared.isGuestPasswordSet() {
                    // Guest password set - show the toggle
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { settings.guestModeEnabled },
                            set: { newValue in
                                if newValue {
                                    settings.guestModeEnabled = true
                                } else {
                                    showGuestModeDisableConfirmation = true
                                }
                            }
                        ))
                } else {
                    // No guest password - show the setup button
                    Button {
                        showGuestModeSetup = true
                    } label: {
                        Text(String(localized: "guestMode.setup.action"))
                            .foregroundColor(.blue)
                    }.accessibilityIdentifier("settings.guest.configure")
                }
            }

            // If a guest password is set, show the change button
            if KeychainService.shared.isGuestPasswordSet() {
                HStack {
                    Spacer()
                    Button {
                        showGuestModeSetup = true
                    } label: {
                        Text(String(localized: "guestMode.changePassword"))
                            .font(.caption)
                            .foregroundColor(.blue)
                    }.accessibilityIdentifier("settings.guest.configure")
                }
                .padding(.top, 4)
            }
        }
    }

    private func disableGuestMode() {
        Task {
            do {
                try KeychainService.shared.deleteGuestPassword()
                settings.guestModeEnabled = false
            } catch {
            }
        }
    }
}

// MARK: - Change Password View

struct ChangePasswordView: View {
    @Environment(\.scenePhase) private var passwordScenePhase
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var keyboard: PasswordKeyboard = .fullKeyboard
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isChanging = false

    private var isCalculatorLoginEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.disguiseModeEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PasswordKeyboardPicker(selection: $keyboard)
                        .onChange(of: keyboard) { _, _ in hideKeyboard() }
                    SecureField(
                        String(localized: "settings.changePassword.current"), text: $currentPassword
                    ).accessibilityIdentifier("passwordChange.current")
                    .textContentType(.password)
                    .keyboardType(keyboard.keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    SecureField(
                        String(localized: "settings.changePassword.new"), text: $newPassword
                    ).accessibilityIdentifier("passwordChange.new")
                    .textContentType(.newPassword)
                    .keyboardType(keyboard.keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    SecureField(
                        String(localized: "settings.changePassword.confirm"), text: $confirmPassword
                    ).accessibilityIdentifier("passwordChange.confirm")
                    .textContentType(.newPassword)
                    .submitLabel(.done).onSubmit { hideKeyboard() }
                    .keyboardType(keyboard.keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    PasswordConfirmationButton(password: newPassword,
                        confirmation: $confirmPassword, identifier: "passwordChange.confirmEntered")
                        .disabled(isChanging)
                    PasswordStrengthView(password: newPassword)
                } header: {
                    Text(String(localized: "settings.changePassword"))
                } footer: {
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                    } else if isCalculatorLoginEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "settings.passwordRequirement"))
                            Text(String(localized: "settings.changePassword.calculatorLoginHint"))
                                .foregroundColor(.orange)
                                .fontWeight(.medium)
                        }
                    } else {
                        Text(String(localized: "settings.passwordRequirement"))
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(String(localized: "settings.importantReminder"))
                                .fontWeight(.semibold)
                        }

                        Text(String(localized: "settings.changePassword.warning"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button {
                        changePassword()
                    } label: {
                        if isChanging {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                                Text(String(localized: "settings.changingPassword"))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text(String(localized: "settings.confirmChange"))
                        }
                    }
                    .disabled(!isValid || isChanging).accessibilityIdentifier("passwordChange.save")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(String(localized: "settings.changePassword.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .disabled(isChanging)
                }
            }
        }
        .onDisappear { clearPasswordInputs() }
        .onChange(of: passwordScenePhase) { _, phase in if phase == .background { clearPasswordInputs() } }
    }

    private func clearPasswordInputs() {
        currentPassword = ""; newPassword = ""; confirmPassword = ""
    }

    private var isValid: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty && PasswordText.matches(newPassword, confirmPassword)
            && KeychainService.validatePasswordStrength(newPassword).isValid
    }

    private func changePassword() {
        guard isValid, !isChanging else { return }
        errorMessage = nil; isChanging = true
        defer { isChanging = false }
        do {
            try authViewModel.updatePassword(oldPassword: currentPassword, newPassword: newPassword)
            clearPasswordInputs(); dismiss()
        } catch {
            clearPasswordInputs()
            errorMessage = (error as? VaultPasswordManagementError)?.errorDescription
                ?? "The password could not be changed. Check your current password and try again. Repeated incorrect attempts require a wait."
        }
    }

}

// MARK: - Primary-authorized alternative password management

struct AlternativePasswordChangeView: View {
    let sessionID: UUID
    @EnvironmentObject private var auth: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboard: PasswordKeyboard = .fullKeyboard
    @State private var primaryPassword = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @State private var isChanging = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Authorize this change") {
                    Text("Enter your main password and the current alternative password. Face ID alone cannot authorize this change.")
                        .font(.footnote).foregroundStyle(.secondary)
                    PasswordKeyboardPicker(selection: $keyboard).onChange(of: keyboard) { _, _ in hideKeyboard() }
                    passwordField("Main password", text: $primaryPassword, id: "alternativeChange.primary", content: .password)
                    passwordField("Current alternative password", text: $currentPassword, id: "alternativeChange.current", content: .password)
                }
                Section("New alternative password") {
                    passwordField("New password", text: $newPassword, id: "alternativeChange.new", content: .newPassword)
                    passwordField("Confirm new password", text: $confirmation, id: "alternativeChange.confirm", content: .newPassword)
                    PasswordConfirmationButton(password: newPassword, confirmation: $confirmation,
                        identifier: "alternativeChange.confirmEntered")
                    PasswordStrengthView(password: newPassword)
                    Text("Use a different password from your main library. This changes the alternative login password; both libraries and their contents are preserved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("alternativeChange.error") } }
                Section {
                    Button("Change alternative password", action: save)
                        .accessibilityIdentifier("alternativeChange.save")
                        .disabled(isChanging || !isValid || !auth.canChangeVaultPasswords)
                }
            }.wagLockList().scrollDismissesKeyboard(.interactively)
                .navigationTitle("Alternative password").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onDisappear { clear() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { clear(); dismiss() } }
        .onChange(of: auth.librarySessionID) { _, _ in clear(); dismiss() }
        .onChange(of: auth.isAuthenticated) { _, value in if !value { clear(); dismiss() } }
    }

    private func passwordField(_ title: String, text: Binding<String>, id: String,
                               content: UITextContentType) -> some View {
        SecureField(title, text: text).textContentType(content).keyboardType(keyboard.keyboardType)
            .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier(id)
    }
    private var isValid: Bool {
        !primaryPassword.isEmpty && !currentPassword.isEmpty && PasswordText.matches(newPassword, confirmation)
            && KeychainService.validatePasswordStrength(newPassword).isValid
    }
    private func clear() { primaryPassword = ""; currentPassword = ""; newPassword = ""; confirmation = ""; errorMessage = nil }
    private func save() {
        guard isValid, !isChanging else { return }
        hideKeyboard(); isChanging = true; errorMessage = nil
        defer { isChanging = false }
        do {
            try auth.updateSecondaryPassword(primaryPassword: primaryPassword, oldPassword: currentPassword,
                newPassword: newPassword, expectedSessionID: sessionID)
            clear(); dismiss()
        } catch {
            clear()
            errorMessage = (error as? VaultPasswordManagementError)?.errorDescription
                ?? "The password could not be changed. Check both current passwords and try again. Repeated incorrect attempts require a wait. If the change was interrupted, try the new password before retrying."
        }
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(AppConstants.tagline).font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    Image("AppIconDisplay").resizable().scaledToFit().frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    Text("WagLock").font(.title.bold())
                    Text("A private space of your own.").font(.title2.bold())
                    Text("A local-first vault for photos, media, documents, and notes.")
                        .foregroundStyle(ColorTheme.secondaryText)
                    NavigationLink {
                        OpenSourceNoticesView()
                    } label: {
                        WagLockNavigationRow(symbol: "doc.text", title: "Open source notices", detail: "License and original attribution")
                    }.accessibilityIdentifier("about.openSourceNotices")
                    NavigationLink { NetworkVerificationView() } label: {
                        WagLockNavigationRow(symbol: "network.slash", title: "Offline & privacy", detail: "What stays local and what iOS handles")
                    }
                    if LibraryStoragePolicy.encryptedMetadata {
                        WagLockInfoCard(title: "Encrypted library", detail: "Originals, library metadata, thumbnails, notes and saved drafts are encrypted on device. Keep independent originals and encrypted backups.")
                            .accessibilityIdentifier("about.encryptedLibrary")
                    } else {
                        WagLockInfoCard(title: "Early test build", detail: AppConstants.developmentNotice)
                        Text("Vault access depends on its password and optional device-bound Face ID. Keep independent backups.")
                            .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    }
                    Text("Local imports have no item limit or purchase requirement.")
                        .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    Text("Version \(AppConstants.appVersion)").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    if let url = URL(string: AppConstants.githubRepositoryURL) {
                        Link("View source on GitHub", destination: url)
                    }
                    Text(String(localized: "settings.copyright")).font(.caption).foregroundStyle(ColorTheme.secondaryText)
                }.padding(24)
            }.background(ColorTheme.primaryBackground)
            .navigationTitle("About WagLock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "settings.done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AuthenticationViewModel())
}
