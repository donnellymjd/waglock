import SwiftUI

struct BiometricSettingsView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @State private var showAssignmentWarning = false

    var body: some View {
        Form {
            if auth.canManageBiometricUnlock {
            Section {
                Label(auth.isBiometricUnlockEnabled ? "Face ID enabled" : "Face ID disabled", systemImage: "faceid")
                Text("Your vault password remains available. Face ID unlocks only on this device; changing enrolled biometrics requires enabling it again with your vault password.")
                    .font(.footnote)
                if auth.isPrimaryVault {
                    Text("Enter your vault password to choose the library Face ID opens.").font(.footnote)
                }
                if auth.isBiometricUnlockEnabled {
                    Button("Disable Face ID", role: .destructive) { auth.disableBiometricUnlock() }
                }
                Group {
                    SecureField("Current vault password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("vault.faceID.password")
                    Button("Enable Face ID") {
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
        }
        .wagLockList()
        .navigationTitle("Face ID Unlock")
        .alert(auth.isPrimaryVault ? "Face ID opens its assigned vault" : "Enable Face ID", isPresented: $showAssignmentWarning) {
            Button("Enable for This Vault") { enableForCurrentVault() }
                .accessibilityIdentifier("vault.faceID.confirm")
            Button("Cancel", role: .cancel) { password = "" }
        } message: {
            if auth.isPrimaryVault {
                Text("Face ID always opens the vault assigned to it. It cannot tell which vault you intend to use. Someone asking you to unlock the app could see that vault's contents. Use the appropriate passcode when you need to choose a vault.")
            } else {
                Text("Face ID opens your library on this device. Anyone able to use your enrolled biometrics may open its contents. Your vault password remains available.")
            }
        }
        .onDisappear { password = ""; showAssignmentWarning = false }
        .onChange(of: scenePhase) { _, phase in if phase == .background { password = "" } }
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
