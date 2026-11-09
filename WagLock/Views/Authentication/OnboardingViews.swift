import SwiftUI

/// First run for the multi-library model: Welcome → Create passcode → (after the library
/// opens) Backups. The storage-mode step is not shown: only Standard storage exists in
/// this build (see docs/portable-vault/library-slots.md, "Not implemented").
struct OnboardingFlowView: View {
    @EnvironmentObject private var viewModel: AuthenticationViewModel
    @State private var step: Step = .welcome
    enum Step { case welcome, passcode }

    var body: some View {
        Group {
            switch step {
            case .welcome: OnboardingWelcomeView { step = .passcode }
            case .passcode: OnboardingPasscodeView()
            }
        }
        .background(Graphite.base.ignoresSafeArea())
    }
}

private struct OnboardingWelcomeView: View {
    let start: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image("AppIconDisplay").resizable().scaledToFit().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: Graphite.accentStrong.opacity(0.45), radius: 16, y: 12)
                        .accessibilityHidden(true).padding(.top, 40)
                    WagLockTitle(text: "A private space\nof your own.", size: .display)
                    Text("A local-first vault for photos, media, documents and notes.")
                        .font(.wlBody).foregroundStyle(Graphite.textMuted)
                    VStack(spacing: 10) {
                        point("lock", "Encrypted on this iPhone", "Everything is encrypted before it’s saved")
                        point("wifi.slash", "No account. Works offline.", "Your library stays here unless you export it")
                        point("shield", "Open source", "Anyone can check how your data is protected")
                        point("square.and.arrow.up", "Yours to take with you", "Export items or a full encrypted backup anytime")
                    }
                }
            }
            Button("Get started", action: start).buttonStyle(WagLockPrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.start")
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        WagLockRow(symbol: symbol, title: title, detail: detail, showsChevron: false)
    }
}

private struct OnboardingPasscodeView: View {
    @EnvironmentObject private var viewModel: AuthenticationViewModel
    @AppStorage(PasswordKeyboard.preferenceKey) private var keyboardRaw = PasswordKeyboard.fullKeyboard.rawValue
    @State private var acknowledged = false
    private var keyboard: PasswordKeyboard { PasswordKeyboard(rawValue: keyboardRaw) ?? .fullKeyboard }
    private var matches: Bool { PasswordText.matches(viewModel.password, viewModel.confirmPassword) }
    private var canContinue: Bool { viewModel.isSetupButtonEnabled && acknowledged }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        WagLockTitle(text: "Create your passcode")
                        Text("This is how you’ll open WagLock. Choose something you can remember.")
                            .font(.wlBody).foregroundStyle(Graphite.textMuted)
                    }.padding(.top, 40)
                    PasswordKeyboardPicker(selection: Binding(get: { keyboard }, set: { keyboardRaw = $0.rawValue }))
                    field("Passcode", text: $viewModel.password, id: "setup.password") {}
                    PasswordStrengthView(password: viewModel.password)
                    field("Confirm passcode", text: $viewModel.confirmPassword, id: "setup.confirmPassword") {
                        if canContinue { viewModel.setupPassword() }
                    }
                    PasswordConfirmationButton(password: viewModel.password,
                        confirmation: $viewModel.confirmPassword, identifier: "setup.confirmEntered")
                        .disabled(viewModel.isProcessing)
                    if !viewModel.confirmPassword.isEmpty {
                        Label(matches ? "Matches" : "Passwords do not match",
                              systemImage: matches ? "checkmark.circle" : "xmark.circle")
                            .font(.wlMeta).foregroundStyle(matches ? Color(hex: 0x7FD8A4) : Graphite.danger)
                    }
                    Toggle(isOn: $acknowledged) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("There is no passcode reset").font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary)
                            Text("If you forget it, nobody can open this library. Keep independent originals and an encrypted backup.")
                                .font(.wlMeta).foregroundStyle(Graphite.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Graphite.accentStrong)
                    .padding(14).background(Graphite.warnTint, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("setup.acknowledge")
                    if let error = viewModel.errorMessage { WagLockNote(kind: .error, text: error) }
                }
            }
            Button {
                viewModel.setupPassword()
            } label: {
                if viewModel.isProcessing { ProgressView().tint(Graphite.onAccent) } else { Text("Continue") }
            }
            .buttonStyle(WagLockPrimaryButtonStyle())
            .disabled(!canContinue)
            .accessibilityIdentifier("setup.save")
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
    }

    private func field(_ title: String, text: Binding<String>, id: String, submit: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock").foregroundStyle(Graphite.textSecondary).accessibilityHidden(true)
            SwitchablePasswordField(title: title, text: text, keyboard: keyboard, secure: !viewModel.showPassword,
                                    contentType: .newPassword, identifier: id, submitTitle: "Continue", onSubmit: submit)
                .frame(minHeight: 24)
        }
        .padding(.horizontal, 16).frame(minHeight: 54)
        .background(Graphite.input, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// "Your way back": shown once after the first library opens. Reminders are per library
/// and device-only; "Not now" is always allowed and nothing is backed up automatically.
struct FirstBackupSetupView: View {
    @EnvironmentObject private var reminders: BackupReminderStore
    @Environment(\.dismiss) private var dismiss
    @State private var showBackup = false
    private let choices: [BackupReminderStore.Frequency] = [.weekly, .monthly, .quarterly, .off]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        WagLockTitle(text: "Your way back")
                        Text("There’s no passcode reset, so an encrypted backup is how you keep your library safe. It’s also how you take it with you.")
                            .font(.wlBody).foregroundStyle(Graphite.textMuted).fixedSize(horizontal: false, vertical: true)
                        WagLockSectionLabel("Save to")
                        WagLockRow(symbol: "icloud.and.arrow.up", title: "iCloud Drive, Files or another provider",
                                   detail: "You choose the location each time you back up", showsChevron: false)
                        WagLockSectionLabel("Backup password")
                        WagLockRow(symbol: "key", title: "Separate backup password",
                                   detail: "Chosen when you back up. A recovery-key option is also offered.", showsChevron: false)
                        WagLockSectionLabel("Remind me")
                        HStack(spacing: 8) {
                            ForEach(choices) { option in
                                let selected = reminders.frequency == option
                                Button { reminders.setFrequency(option) } label: {
                                    Text(option == .quarterly ? "3 months" : option.title)
                                        .font(selected ? .wlBodyStrong : .wlBody).lineLimit(1).minimumScaleFactor(0.8)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(selected ? Graphite.onAccent : Graphite.textPrimary)
                                        .background(selected ? AnyShapeStyle(Graphite.accentGradient) : AnyShapeStyle(Graphite.surface1),
                                                    in: RoundedRectangle(cornerRadius: 10))
                                }.accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        Text("Your first backup can run after you add something.")
                            .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                    }.padding(.top, 12)
                }
                Button("Back up now") { showBackup = true }.buttonStyle(WagLockPrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding.backup")
                Button("Not now") { dismiss() }
                    .font(WagLockFonts.poppins(14, .semibold, relativeTo: .body))
                    .foregroundStyle(Graphite.textSecondary).frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("onboarding.backup.notNow")
            }
            .padding(.horizontal, 22).padding(.bottom, 20)
            .background(Graphite.base)
            .navigationDestination(isPresented: $showBackup) { PortableBackupView() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
