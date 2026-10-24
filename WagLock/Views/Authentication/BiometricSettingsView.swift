import SwiftUI

struct BiometricSettingsView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @State private var showAssignmentWarning = false

    var body: some View {
        Form {
            Section {
                Label(auth.isBiometricUnlockEnabled ? "Face ID enabled" : "Face ID disabled", systemImage: "faceid")
                Text("Your vault password remains available. Face ID unlocks only on this device; changing enrolled biometrics requires enabling it again with your vault password.")
                    .font(.footnote)
                Text("Enter this vault’s password to assign Face ID to it. Passcodes continue to select their own libraries.")
                    .font(.footnote)
                if auth.isBiometricUnlockEnabled {
                    Button("Disable Face ID", role: .destructive) { auth.disableBiometricUnlock() }
                }
                Group {
                    SecureField("Current vault password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("vault.faceID.password")
                    Button(auth.isBiometricUnlockEnabled ? "Assign Face ID to This Vault" : "Enable Face ID") {
                        error = nil
                        showAssignmentWarning = true
                    }
                    .disabled(password.isEmpty || busy)
                    .accessibilityIdentifier("vault.faceID.enable")
                }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .wagLockList()
        .navigationTitle("Face ID Unlock")
        .alert("Face ID opens its assigned vault", isPresented: $showAssignmentWarning) {
            Button("Enable for This Vault") { enableForCurrentVault() }
                .accessibilityIdentifier("vault.faceID.confirm")
            Button("Cancel", role: .cancel) { password = "" }
        } message: {
            Text("Face ID always opens the vault assigned to it. It cannot tell which vault you intend to use. Someone asking you to unlock the app could see that vault's contents. Use the appropriate passcode when you need to choose a vault.")
        }
        .onDisappear { password = ""; showAssignmentWarning = false }
    }
    private func enableForCurrentVault() {
        let sessionID = auth.librarySessionID
        let enteredPassword = password
        password = ""
        busy = true
        Task {
            defer { busy = false }
            do { try await auth.enableBiometricUnlock(password: enteredPassword) }
            catch {
                guard auth.isAuthenticated, auth.librarySessionID == sessionID else { return }
                self.error = error.localizedDescription
            }
        }
    }
}
