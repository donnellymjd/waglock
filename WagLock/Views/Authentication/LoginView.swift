import SwiftUI

/// Graphite unlock screen. It looks the same whichever library a passcode opens: the
/// keyboard type is global and the error text never depends on the targeted library.
struct LoginView: View {
    @EnvironmentObject private var viewModel: AuthenticationViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PasswordKeyboard.preferenceKey) private var keyboardRaw = PasswordKeyboard.numberPad.rawValue
    @State private var showPasswordHelp = false
    @State private var shake = 0
    private var keyboard: PasswordKeyboard { PasswordKeyboard(rawValue: keyboardRaw) ?? .numberPad }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    VStack(alignment: .leading, spacing: 4) {
                        WagLockTitle(text: "Welcome home!", size: .display)
                        Text("Everything stays on this device. Unlock to make yourself at home.")
                            .font(.wlBody).foregroundStyle(Graphite.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    passwordField.padding(.top, 6)
                        .modifier(ShakeEffect(shakes: CGFloat(shake)))
                    if let error = viewModel.errorMessage {
                        Label {
                            Text(error).font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote))
                        } icon: { Image(systemName: "exclamationmark.circle") }
                            .foregroundStyle(Color(hex: 0xFFC0C0))
                            .accessibilityIdentifier("password.error")
                    }
                    HStack {
                        Label("On-device encryption", systemImage: "shield")
                            .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                        Spacer()
                        Button(keyboard == .numberPad ? "Use full keyboard" : "Use number pad") {
                            keyboardRaw = (keyboard == .numberPad ? PasswordKeyboard.fullKeyboard : .numberPad).rawValue
                        }
                        .font(WagLockFonts.poppins(12, .medium, relativeTo: .footnote))
                        .foregroundStyle(Graphite.accentText).frame(minHeight: 44)
                        .accessibilityIdentifier("password.keyboard.toggle")
                    }
                    HStack(spacing: 10) {
                        Button {
                            hideKeyboard()
                            viewModel.login()
                        } label: {
                            if viewModel.isProcessing { ProgressView().tint(Graphite.onAccent) } else { Text("Unlock") }
                        }
                        .buttonStyle(WagLockPrimaryButtonStyle())
                        .disabled(!viewModel.isLoginButtonEnabled || viewModel.isProcessing)
                        .accessibilityIdentifier("password.unlock")
                        if viewModel.isBiometricUnlockEnabled {
                            Button { Task { await viewModel.loginWithBiometrics() } } label: {
                                Image(systemName: "faceid").font(.system(size: 22)).foregroundStyle(Graphite.accentText)
                                    .frame(width: 54, height: 54)
                                    .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Graphite.line, lineWidth: 1))
                            }
                            .accessibilityLabel("Unlock with Face ID")
                            .disabled(viewModel.isProcessing).accessibilityIdentifier("vault.faceID.unlock")
                        }
                    }
                    HStack(spacing: 10) {
                        Text("Can’t unlock?").foregroundStyle(Graphite.textMuted)
                        Button("Get help") { showPasswordHelp = true }
                            .font(WagLockFonts.poppins(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(Graphite.accentText).frame(minHeight: 44)
                            .accessibilityIdentifier("password.help")
                    }
                    .font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote))
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
                .disabled(viewModel.isProcessing)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Graphite.base.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPasswordHelp) {
                UnlockHelpView().environmentObject(viewModel)
            }
        }
        .onChange(of: viewModel.failedAttempts) { old, new in
            if new > old, !reduceMotion { withAnimation(.default) { shake += 1 } }
        }
    }

    private var hero: some View {
        VStack(spacing: 28) {
            Text("WAGLOCK · WE ALWAYS GUARD")
                .font(WagLockFonts.poppins(11, .semibold, relativeTo: .caption))
                .tracking(3.5).foregroundStyle(Color(hex: 0xC9CFDB))
            Image("AppIconDisplay").resizable().scaledToFit()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Graphite.accentStrong.opacity(0.45), radius: 20, y: 18)
                .accessibilityLabel(AppConstants.appName)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40).padding(.bottom, 80)
    }

    private var passwordField: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock").foregroundStyle(Color(hex: 0xC9CFDB)).accessibilityHidden(true)
            SwitchablePasswordField(title: "Passcode", text: $viewModel.password, keyboard: keyboard,
                                    secure: !viewModel.showPassword, identifier: "Enter password") {
                if viewModel.isLoginButtonEnabled { viewModel.login() }
            }.frame(minHeight: 24)
            Button { viewModel.togglePasswordVisibility() } label: {
                Image(systemName: viewModel.showPassword ? "eye.slash" : "eye")
                    .foregroundStyle(Color(hex: 0xC9CFDB)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(viewModel.showPassword ? "Hide passcode" : "Show passcode")
            .accessibilityIdentifier("password.visibility")
        }
        .padding(.leading, 16).padding(.trailing, 6)
        .frame(minHeight: 54)
        .background(Graphite.input, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(viewModel.errorMessage == nil ? .clear : Graphite.dangerLine, lineWidth: 1.5))
    }
}

/// Horizontal shake on a wrong passcode; skipped under Reduce Motion.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 4), y: 0))
    }
}
