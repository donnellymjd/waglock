//
//  GuestModeSetupView.swift
//  WagLock
//
//  Created by Claude on 2025-01-17.
//  访客密码设置界面
//

import SwiftUI

struct GuestModeSetupView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @State private var keyboard: PasswordKeyboard = .fullKeyboard
    @State private var guestPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isProcessing = false

    // MARK: - Services

    private let keychainService = KeychainService.shared

    // MARK: - Callback

    let onComplete: () -> Void

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        // 标题说明
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .font(.title)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "guestMode.setup.header"))
                                    .font(.title3)
                                    .fontWeight(.bold)

                                Text(LibraryStoragePolicy.encryptedMetadata ? "Create a separate encrypted library opened by a different passcode on the ordinary login screen." : String(localized: "guestMode.setup.description"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("")
                }

                Section {
                    PasswordKeyboardPicker(selection: $keyboard)
                        .onChange(of: keyboard) { _, _ in hideKeyboard() }
                    // 访客密码输入
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "number")
                                .foregroundColor(.secondary)

                            SecureField(
                                String(localized: "guestMode.password.placeholder"),
                                text: $guestPassword
                            )
                            .keyboardType(keyboard.keyboardType)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.newPassword)
                            .accessibilityIdentifier("guest.password")
                        }

                        Text(String(localized: "guestMode.password.hint"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    // 确认密码
                    HStack {
                        Image(systemName: "checkmark.shield")
                            .foregroundColor(.secondary)

                        SecureField(
                            String(localized: "guestMode.password.confirm"), text: $confirmPassword
                        )
                        .keyboardType(keyboard.keyboardType)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("guest.password.confirm")
                    }
                    .padding(.vertical, 4)

                    PasswordStrengthView(password: guestPassword)
                } header: {
                    Text(String(localized: "guestMode.password.label"))
                } footer: {
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    VStack(spacing: 12) {
                        // 安全说明
                        infoRow(
                            icon: "eye.slash.fill",
                            text: "Each vault has independent content and keys.")
                        infoRow(
                            icon: "person.2.fill",
                            text: "Lock the app before entering the other passcode.")
                        infoRow(
                            icon: "key.fill",
                            text: String(localized: "guestMode.info.differentPassword"))
                        infoRow(
                            icon: "number.circle.fill",
                            text: "Use a PIN or a full password. No forensic invisibility is promised.")
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text(String(localized: "guestMode.info.title"))
                }
            }
            .wagLockList()
        .navigationTitle(String(localized: "guestMode.setup.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) {
                        saveGuestPassword()
                    }
                    .disabled(!isValid || isProcessing)
                    .accessibilityIdentifier("guest.password.save")
                }
            }
            .disabled(isProcessing)
            .onDisappear { guestPassword = ""; confirmPassword = "" }
            .onChange(of: scenePhase) { _, phase in if phase == .background { guestPassword = ""; confirmPassword = "" } }
        }
    }

    // MARK: - Helper Views

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()
        }
    }

    // MARK: - Computed Properties

    private var isValid: Bool {
        KeychainService.validateGuestPassword(guestPassword).isValid && guestPassword == confirmPassword
    }

    // MARK: - Methods

    private func saveGuestPassword() {
        errorMessage = nil

        // 1. 验证格式
        let validation = KeychainService.validateGuestPassword(guestPassword)
        guard validation.isValid else {
            errorMessage = validation.message
            return
        }

        // 2. 检查密码匹配
        guard guestPassword == confirmPassword else {
            errorMessage = String(localized: "guestMode.error.mismatch")
            return
        }

        // 3. 检查与主密码不冲突
        if keychainService.verifyPassword(guestPassword) {
            errorMessage = String(localized: "guestMode.error.sameAsMain")
            return
        }

        isProcessing = true

        // 4. 保存访客密码
        Task {
            do {
                if LibraryStoragePolicy.encryptedMetadata { try auth.provisionSecondaryVault(password: guestPassword) }
                else { try keychainService.saveGuestPassword(guestPassword) }

                await MainActor.run {
                    isProcessing = false
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = String(
                        format: String(localized: "guestMode.error.saveFailed"),
                        error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    GuestModeSetupView(onComplete: {
    })
}
