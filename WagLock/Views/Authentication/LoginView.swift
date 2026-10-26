import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var viewModel: AuthenticationViewModel
    @AppStorage(PasswordKeyboard.preferenceKey) private var keyboardRaw = PasswordKeyboard.numberPad.rawValue
    @State private var showPasswordHelp = false
    private var keyboard: PasswordKeyboard { PasswordKeyboard(rawValue: keyboardRaw) ?? .numberPad }
    private var keyboardBinding: Binding<PasswordKeyboard> {
        Binding(get: { keyboard }, set: { keyboardRaw = $0.rawValue })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 8) {
                        Image("AppIconDisplay").resizable().scaledToFit()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .accessibilityHidden(true)
                        Text(AppConstants.appName).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text(AppConstants.tagline).font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity).padding(.bottom, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your space. Safely kept.").font(.title2)
                        Text("Your vault stays on this device.\nUnlock to make yourself at home.")
                            .font(.body).foregroundStyle(ColorTheme.secondaryText)
                    }
                    passwordSection
                    Label("On-device encryption · Open source", systemImage: "lock")
                        .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                    Button { showPasswordHelp = true } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Can’t unlock?").font(.body).foregroundStyle(ColorTheme.accent)
                            Text(viewModel.canEraseLocalData ? "Try saved access, recover a backup, or learn how to start over." : "Try saved access or recover an exported backup.")
                                .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(ColorTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("password.help")
                }
                .foregroundStyle(ColorTheme.primaryText)
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ColorTheme.primaryBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPasswordHelp) {
                UnlockHelpView().environmentObject(viewModel)
            }
        }
        .loadingOverlay(isShowing: viewModel.isProcessing, message: String(localized: "login.verifying"))
    }

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Password").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
            PasswordKeyboardPicker(selection: keyboardBinding)
            HStack(spacing: 12) {
                SwitchablePasswordField(title: String(localized: "login.passwordPlaceholder"), text: $viewModel.password,
                                        keyboard: keyboard, secure: !viewModel.showPassword) {
                    if viewModel.isLoginButtonEnabled { viewModel.login() }
                }.frame(minHeight: 24)
                Button { viewModel.togglePasswordVisibility() } label: {
                    Image(systemName: viewModel.showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(ColorTheme.secondaryText)
                        .frame(minWidth: 24, minHeight: 32)
                }
                .accessibilityLabel(viewModel.showPassword ? "Hide password" : "Show password")
                .accessibilityIdentifier("password.visibility")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(viewModel.errorMessage == nil ? ColorTheme.border : ColorTheme.destructive))
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(ColorTheme.destructive)
                    .accessibilityIdentifier("password.error")
            }
            Button {
                hideKeyboard()
                viewModel.login()
            } label: {
                if viewModel.isProcessing { ProgressView() } else { Text("Unlock vault") }
            }
            .buttonStyle(WagLockPrimaryButtonStyle())
            .disabled(!viewModel.isLoginButtonEnabled || viewModel.isProcessing)
            .accessibilityIdentifier("password.unlock")
            if viewModel.isBiometricUnlockEnabled {
                Button { Task { await viewModel.loginWithBiometrics() } } label: {
                    Label("Unlock with Face ID", systemImage: "faceid").frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(ColorTheme.accent)
                .disabled(viewModel.isProcessing).accessibilityIdentifier("vault.faceID.unlock")
            }
        }
        .disabled(viewModel.isProcessing)
    }
}
