//
//  SettingsView.swift
//  WagLock
//
//  设置视图
//  应用配置、存储管理、安全设置
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext

    // MARK: - Environment

    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AppSettings.shared

    // MARK: - State

    @EnvironmentObject private var guestModeManager: GuestModeManager
    @AppStorage(WagLockAppearance.preferenceKey) private var appearance = WagLockAppearance.system.rawValue
    @StateObject private var iconService = AppIconService()
    @State private var showLogoutConfirmation = false
    @State private var showChangePasswordSheet = false
    @State private var showAboutSheet = false
    @State private var showGuestModeSetup = false
    @State private var showGuestModeDisableConfirmation = false
    @State private var storageInfo: StorageInfo?
    @State private var isLoadingStorage = false
    @State private var showClearCacheConfirmation = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Make WagLock yours").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    VStack(alignment: .leading, spacing: 8) {
                        settingsHeading("SECURITY")
                        NavigationLink {
                            List { securitySection }.wagLockList().navigationTitle("Security & access")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            settingsCard("lock.shield", "Security & access", LibraryStoragePolicy.encryptedMetadata ? (authViewModel.canManageBiometricUnlock ? "Face ID, password and auto-lock" : "Password and auto-lock") : "Face ID, password and Guest Mode")
                        }.accessibilityIdentifier("settings.security")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        settingsHeading("APPEARANCE")
                        NavigationLink { appearanceScreen } label: {
                            settingsCard("circle.lefthalf.filled", "Appearance", "Follow device · Light · Dark")
                        }.accessibilityIdentifier("settings.appearance")
                        if guestModeManager.isOwnerMode {
                            NavigationLink { AppIconSettingsView() } label: {
                                settingsCard("app.badge", "App icon", currentIconTitle)
                            }.accessibilityIdentifier("settings.appIcon")
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        settingsHeading("ON THIS DEVICE")
                        NavigationLink {
                            storageScreen
                        } label: {
                            settingsCard("internaldrive", "Storage", storageInfo.map { "\($0.formattedTotalUsed) used on this device" } ?? "Calculating storage…")
                        }
                        if guestModeManager.isOwnerMode {
                            NavigationLink { PortableBackupView() } label: {
                                settingsCard("externaldrive.badge.icloud", "Encrypted backup", "Export to Files, iCloud Drive or another provider")
                            }.accessibilityIdentifier("settings.backup")
                        }
                        Button { showAboutSheet = true } label: {
                            settingsCard("info.circle", "About WagLock", LibraryStoragePolicy.encryptedMetadata ? "Open source · On-device encryption" : "Open source · Early test build")
                        }.accessibilityIdentifier("settings.about")
                    }
                    Button { showLogoutConfirmation = true } label: {
                        Label("Lock WagLock", systemImage: "lock")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.foregroundStyle(ColorTheme.accent).accessibilityIdentifier("settings.lock")
                }.padding(24)
            }
            .background(ColorTheme.primaryBackground)
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.inline)
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
            ChangePasswordView()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutView()
        }
        .sheet(isPresented: $showGuestModeSetup) {
            GuestModeSetupView {
                // 设置完成后启用访客模式
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

    private var appearanceScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Comfortable in any light").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                Picker("Appearance", selection: $appearance) {
                    ForEach(WagLockAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }.pickerStyle(.segmented).accessibilityIdentifier("settings.appearance.picker")
                WagLockInfoCard(title: "Follow your device", detail: "System matches the appearance chosen in iOS. You can choose Light or Dark for WagLock instead.")
                settingsHeading("LIBRARY LAYOUT")
                NavigationLink {
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
                } label: {
                    settingsCard("square.grid.3x3", "Library layout", "\(settings.gridColumns) columns · \(settings.sortOrder.displayName)")
                }.accessibilityIdentifier("settings.layout")
                Text("Your appearance preference applies throughout WagLock.")
                    .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
            }.padding(24)
        }.background(ColorTheme.primaryBackground).navigationTitle("Appearance")
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
                    Button { showChangePasswordSheet = true } label: {
                        securityRow("key", "Change password", "Verify your current password")
                    }.accessibilityIdentifier("settings.changePassword").wagLockCardRow()
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
                        Text("Alternative passcode configured").foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 18) {
                Text("Everything stays on this device").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                if let info = storageInfo {
                    WagLockProgressCard(title: "\(info.formattedTotalUsed) used by WagLock", detail: "Vault media compared with currently available device space", progress: Double(info.totalUsed) / max(Double(info.totalUsed) + Double(info.availableSpace), 1))
                    Text("DEVICE STORAGE").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    WagLockNavigationRow(symbol: "internaldrive", title: "Available on device", detail: info.formattedAvailableSpace)
                    WagLockNavigationRow(symbol: "photo", title: "Cached previews", detail: "\(info.formattedCacheSize) · Can be rebuilt")
                } else { ProgressView("Calculating storage…") }
                WagLockInfoCard(title: "Clear cache, keep originals", detail: "Only temporary previews are cleared. Encrypted originals remain in WagLock.")
                Button("Clear preview cache") { showClearCacheConfirmation = true }
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("settings.clearCache")
            }.padding(24)
        }.background(ColorTheme.primaryBackground).navigationTitle("Storage").navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Methods

    private func loadStorageInfo() async {
        isLoadingStorage = true
        defer { isLoadingStorage = false }

        storageInfo = await StorageService.shared.getStorageInfo(modelContext: modelContext, storage: vaultServices.storage)
    }

    private func clearCache() {
        Task {
            do {
                vaultServices.mediaLoader.clearCache()
                vaultServices.thumbnails.clearAll()

                // 重新加载存储信息
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
                    // 已设置访客密码 - 显示开关
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
                    // 未设置访客密码 - 显示设置按钮
                    Button {
                        showGuestModeSetup = true
                    } label: {
                        Text(String(localized: "guestMode.setup.action"))
                            .foregroundColor(.blue)
                    }.accessibilityIdentifier("settings.guest.configure")
                }
            }

            // 如果已设置访客密码，显示修改按钮
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
                    .keyboardType(keyboard.keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    SecureField(
                        String(localized: "settings.changePassword.new"), text: $newPassword
                    ).accessibilityIdentifier("passwordChange.new")
                    .keyboardType(keyboard.keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    SecureField(
                        String(localized: "settings.changePassword.confirm"), text: $confirmPassword
                    ).accessibilityIdentifier("passwordChange.confirm")
                    .submitLabel(.done).onSubmit { hideKeyboard() }
                    .keyboardType(keyboard.keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
        !currentPassword.isEmpty && !newPassword.isEmpty && newPassword == confirmPassword
            && KeychainService.validatePasswordStrength(newPassword).isValid
    }

    private func changePassword() {
        errorMessage = nil

        // 开始修改密码
        isChanging = true

        Task {
            do {
                try authViewModel.updatePassword(
                    oldPassword: currentPassword,
                    newPassword: newPassword
                )

                await MainActor.run {
                    isChanging = false
                    dismiss()
                }

            } catch {
                await MainActor.run {
                    isChanging = false
                    errorMessage = String(
                        format: String(localized: "settings.changePassword.error.generic"),
                        error.localizedDescription
                    )
                }
            }
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
