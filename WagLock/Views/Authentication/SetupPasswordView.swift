//
//  SetupPasswordView.swift
//  WagLock
//
//  First-time password setup screen
//  Guides the user through creating an app password
//

import SwiftUI

struct SetupPasswordView: View {

    // MARK: - Properties

    @EnvironmentObject private var viewModel: AuthenticationViewModel
    @FocusState private var focusedField: Field?

    // MARK: - Focus Field Enum

    private enum Field: Hashable {
        case password
        case confirmPassword
    }

    @State private var keyboard: PasswordKeyboard = .fullKeyboard

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Start with a password you can keep").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    Text("A space that is yours.").font(.title2.bold())
                    passwordForm
                    WagLockInfoCard(title: LibraryStoragePolicy.encryptedMetadata ? "Keep your password safe" : "No password reset in this beta", detail: LibraryStoragePolicy.encryptedMetadata ? "WagLock cannot reset your password. Keep independent originals and an encrypted backup with its recovery credentials." : "Keep this password and independent originals. Do not rely on this test build as your only copy.")
                    setupButton
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .clipped()
            .background(ColorTheme.primaryBackground.ignoresSafeArea())
            .navigationTitle("Create your vault")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - View Components

    /// Header
    private var headerSection: some View {
        VStack(spacing: 20) {
            // Lock icon
            Image("AppIconDisplay")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 15, y: 8)
                .padding(.top, 40)

            VStack(spacing: 8) {
                Text(AppConstants.appName)
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text(AppConstants.tagline)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Offline privacy notice
    private var privacyNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "network.slash")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "setup.privacy.title"))
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(String(localized: "setup.privacy.message"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    /// Password entry form
    private var passwordForm: some View {
        VStack(spacing: 20) {
            PasswordKeyboardPicker(selection: $keyboard)
                .onChange(of: keyboard) { _, _ in focusedField = nil }
            // Password field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                        .frame(width: 20)

                    if viewModel.showPassword {
                        TextField(
                            String(localized: "setup.passwordPlaceholder"),
                            text: $viewModel.password
                        )
                        .textContentType(.newPassword)
                        .keyboardType(keyboard.keyboardType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("setup.password")
                        .focused($focusedField, equals: .password)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .confirmPassword
                        }
                    } else {
                        SecureField(
                            String(localized: "setup.passwordPlaceholder"),
                            text: $viewModel.password
                        )
                        .textContentType(.newPassword)
                        .keyboardType(keyboard.keyboardType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("setup.password")
                        .focused($focusedField, equals: .password)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .confirmPassword
                        }
                    }
                }
                .padding()
                .background(ColorTheme.secondaryBackground)
                .cornerRadius(12)

                PasswordStrengthView(password: viewModel.password)
            }

            // Confirm password field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                        .frame(width: 20)

                    if viewModel.showPassword {
                        TextField(
                            String(localized: "setup.confirmPasswordPlaceholder"),
                            text: $viewModel.confirmPassword
                        )
                        .textContentType(.newPassword)
                        .keyboardType(keyboard.keyboardType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("setup.confirmPassword")
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.done)
                        .onSubmit {
                            if viewModel.isSetupButtonEnabled {
                                viewModel.setupPassword()
                            }
                        }
                    } else {
                        SecureField(
                            String(localized: "setup.confirmPasswordPlaceholder"),
                            text: $viewModel.confirmPassword
                        )
                        .textContentType(.newPassword)
                        .keyboardType(keyboard.keyboardType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("setup.confirmPassword")
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.done)
                        .onSubmit {
                            if viewModel.isSetupButtonEnabled {
                                viewModel.setupPassword()
                            }
                        }
                    }
                }
                .padding()
                .background(ColorTheme.secondaryBackground)
                .cornerRadius(12)

                PasswordConfirmationButton(password: viewModel.password,
                    confirmation: $viewModel.confirmPassword, identifier: "setup.confirmEntered")
                    .disabled(viewModel.isProcessing)

                // Password match indicator
                if !viewModel.confirmPassword.isEmpty {
                    HStack {
                        Image(
                            systemName: PasswordText.matches(viewModel.password, viewModel.confirmPassword)
                                ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundColor(
                            PasswordText.matches(viewModel.password, viewModel.confirmPassword) ? .green : .red)

                        Text(
                            PasswordText.matches(viewModel.password, viewModel.confirmPassword)
                                ? String(localized: "setup.passwordMatch")
                                : String(localized: "setup.passwordMismatch")
                        )
                        .font(.caption)
                        .foregroundColor(
                            PasswordText.matches(viewModel.password, viewModel.confirmPassword) ? .green : .red)

                        Spacer()
                    }
                }
            }

            // Show/hide password toggle
            Button(action: {
                viewModel.togglePasswordVisibility()
            }) {
                HStack {
                    Image(systemName: viewModel.showPassword ? "eye.slash.fill" : "eye.fill")
                    Text(
                        viewModel.showPassword
                            ? String(localized: "setup.hidePassword")
                            : String(localized: "setup.showPassword"))
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Error message
            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.red)
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(ColorTheme.secondaryBackground)
        .cornerRadius(16)
        .shadow(radius: 5)
    }

    /// Set password button
    private var setupButton: some View {
        Button(action: {
            viewModel.setupPassword()
        }) {
            HStack {
                if viewModel.isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(String(localized: "setup.finish"))
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .foregroundColor(ColorTheme.onAccent)
        }
        .buttonStyle(WagLockPrimaryButtonStyle())
        .disabled(!viewModel.isSetupButtonEnabled)
        .accessibilityIdentifier("setup.save")
    }

    /// Password hints
    private var passwordHints: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "setup.requirement.length"), systemImage: "checkmark.circle")
            Label(String(localized: "setup.requirement.combination"), systemImage: "key")
            Label(
                String(localized: "setup.requirement.important"),
                systemImage: "exclamationmark.triangle")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    SetupPasswordView()
}
