//
//  EncryptedFilePasswordInputView.swift
//  WagLock
//
//  加密文件密码输入视图
//  用于导入旧加密文件时输入原始密码
//

import SwiftUI

struct EncryptedFilePasswordInputView: View {
    @Environment(\.dismiss) private var dismiss

    let fileName: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var password: String = ""
    @State private var showPassword: Bool = false

    @State private var keyboard: PasswordKeyboard = .fullKeyboard

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Enter the password used to encrypt this file").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    WagLockNavigationRow(symbol: "lock.doc", title: fileName, detail: "Password-protected file")
                    PasswordKeyboardPicker(selection: $keyboard)
                    HStack {
                        SwitchablePasswordField(title: String(localized: "import.encryptedFile.passwordPlaceholder"), text: $password,
                            keyboard: keyboard, secure: !showPassword) { confirm() }
                            .frame(minHeight: 28)
                        Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }
                            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                    }.padding(16).background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
                    WagLockInfoCard(title: "Use the original password", detail: "This may be different from your WagLock password. Importing does not change the original file.")
                    Button("Unlock and import") { confirm() }.buttonStyle(WagLockPrimaryButtonStyle()).disabled(password.isEmpty)
                }.padding(24)
            }.background(ColorTheme.primaryBackground).navigationTitle("Unlock imported file")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel(); dismiss() } } }
        }
    }

    private func confirm() {
        guard !password.isEmpty else { return }
        onConfirm(password)
        dismiss()
    }
}
