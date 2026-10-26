import SwiftUI

struct UnlockHelpView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Try saved access") {
                    Text("Check your password manager for your saved WagLock password. Use https://waglock.d2sci.co as its website, then choose Full keyboard on the unlock screen if needed.")
                    Text("Face ID can help only if you enabled it earlier. If it still opens your library, make an encrypted backup before changing anything.")
                    if auth.isBiometricUnlockEnabled {
                        Button("Try Face ID") {
                            dismiss()
                            Task { await auth.loginWithBiometrics() }
                        }.accessibilityIdentifier("recovery.faceID")
                    }
                }
                Section("Recover an existing backup") {
                    Text("An exported encrypted backup can be opened on a computer using its own backup password or recovery key. Protected albums may need their separate passwords. Your backup password may differ from your WagLock password.")
                    Text("Recovery extracts your files. Restoring a backup inside WagLock is not available yet. WagLock cannot recover a forgotten password for you.")
                    Link("Open recovery instructions", destination: URL(string: "https://github.com/donnellymjd/waglock/blob/main/docs/portable-vault/backup-recovery.md")!)
                        .accessibilityIdentifier("recovery.instructions")
                }
                if auth.canEraseLocalData {
                    Section("Start over") {
                        Text("If you cannot recover access, you can erase WagLock's local vault content and create a new password. This cannot recover or unlock the old content.")
                        NavigationLink { EraseWagLockView() } label: {
                            Text("Erase WagLock and start over").foregroundStyle(ColorTheme.destructive)
                        }.accessibilityIdentifier("recovery.erase.open")
                    }
                }
            }
            .wagLockList()
            .navigationTitle("Can't unlock?")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct EraseWagLockView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel
    @Environment(\.scenePhase) private var phase
    @State private var confirmation = ""
    @State private var acknowledged = false
    var body: some View {
        Form {
            Section {
                Text("This permanently deletes all vault content stored in WagLock on this device, including protected photos, videos, files, notes and saved unlock credentials. Saved Face ID access is removed.")
                Text("Exported backups and originals saved outside the vault are not deleted. They remain protected by their existing passwords. This does not guarantee forensic erasure from the device or its backups.")
                Text("After you confirm, erasure cannot be cancelled. If interrupted, it resumes when you reopen WagLock.")
            }
            Section("Confirm permanent deletion") {
                Toggle("I understand that this cannot be undone", isOn: $acknowledged)
                    .accessibilityIdentifier("recovery.erase.acknowledge")
                TextField("Type ERASE", text: $confirmation)
                    .textContentType(nil).textInputAutocapitalization(.characters)
                    .autocorrectionDisabled().keyboardType(.asciiCapable)
                    .accessibilityIdentifier("recovery.erase.confirmation")
                Button("Erase WagLock", role: .destructive) {
                    guard phase == .active, acknowledged, confirmation == "ERASE" else { return }
                    let input = confirmation
                    confirmation = ""; acknowledged = false
                    Task { await auth.eraseLocalData(confirmation: input) }
                }
                .disabled(!acknowledged || confirmation != "ERASE" || phase != .active || auth.isErasing)
                .accessibilityIdentifier("recovery.erase.confirm")
            }
        }
        .wagLockList().navigationTitle("Erase WagLock")
        .onChange(of: phase) { _, value in
            if value == .background { confirmation = ""; acknowledged = false }
        }
        .onDisappear { confirmation = ""; acknowledged = false }
    }
}

struct EraseCompletionView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield").font(.largeTitle)
            Text("WagLock is locked").font(.title2.bold())
            if auth.isErasing {
                ProgressView("Erasing local content…").accessibilityIdentifier("recovery.erase.progress")
            } else {
                Text(auth.eraseError ?? "Finishing a previously confirmed erasure.")
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await auth.resumePendingErase() } }
                    .accessibilityIdentifier("recovery.erase.retry")
            }
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorTheme.primaryBackground.ignoresSafeArea())
        .task { await auth.resumePendingErase() }
    }
}
