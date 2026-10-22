import SwiftUI
import UIKit

struct PortableBackupView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel
    @EnvironmentObject private var mounts: LibraryMountCoordinator
    @EnvironmentObject private var mode: GuestModeManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = PortableBackupSession()
    @State private var method = "password"
    @State private var password = ""
    @State private var confirmation = ""
    @State private var recipient = ""
    @State private var albumPasswords: [UUID: String] = [:]
    @State private var albumConfirmations: [UUID: String] = [:]
    @State private var biometricConsent = false
    @State private var keyboard = PasswordKeyboard.fullKeyboard
    @State private var handoff: BackupFile?
    @State private var saved = false
    private struct BackupFile: Identifiable { let id = UUID(); let url: URL }
    private var request: LibraryMountCoordinator.Request { .init(sessionID: auth.librarySessionID, scope: .legacyOwner) }
    private var biometricRows: [PortableBackupSession.AlbumRow] { session.rows.filter { $0.policy == .faceIDOnly } }

    var body: some View {
        Form {
            Section {
                Text("Create an encrypted copy of your media, albums, notes and saved drafts. Your library stays on this device.")
                Text("Device settings and Face ID registrations are not copied. Keep independent originals while WagLock is in testing.")
                    .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
            }
            if session.readyURL == nil {
                Section("Protect the backup") {
                    Picker("Encryption method", selection: $method) {
                        Text("Password").tag("password")
                        Text("Age recovery key").tag("recipient")
                    }.pickerStyle(.segmented).accessibilityIdentifier("backup.method")
                    if method == "password" {
                        PasswordKeyboardPicker(selection: $keyboard)
                        passwordField("New backup password", text: $password, identifier: "backup.password")
                        passwordField("Confirm backup password", text: $confirmation, identifier: "backup.confirm")
                        PasswordStrengthView(password: password)
                        Text("Use at least 12 characters, preferably several random words. This password protects the copy; it does not change your WagLock password.")
                            .font(.footnote)
                    } else {
                        TextField("age1… public recipient", text: $recipient)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("backup.recipient")
                        Text("Enter an age X25519 public recipient. Keep its matching private identity separately; the public recipient cannot decrypt a backup.")
                            .font(.footnote)
                    }
                    Text("Standard age encryption uses ChaCha20-Poly1305. Password mode uses scrypt; recovery-key mode uses X25519.")
                        .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                }.disabled(session.isWorking)
                if session.rows.contains(where: { $0.policy != .inherited }) {
                    Section("Protected albums") {
                        if method != "password" { PasswordKeyboardPicker(selection: $keyboard) }
                        Text("Each protected album remains separately encrypted. Enter its current password. It must differ from its protected parent's password; short album PINs remain easier to guess.").font(.footnote)
                        ForEach(session.rows.filter { $0.policy != .inherited }) { album in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(album.name).font(.headline)
                                passwordField(album.policy == .faceIDOnly ? "New export password" : "Current album password",
                                    text: Binding(get: { albumPasswords[album.id] ?? "" }, set: { albumPasswords[album.id] = $0 }),
                                    identifier: "backup.album." + album.id.uuidString)
                                if album.policy == .faceIDOnly {
                                    passwordField("Confirm export password",
                                        text: Binding(get: { albumConfirmations[album.id] ?? "" }, set: { albumConfirmations[album.id] = $0 }),
                                        identifier: "backup.album.confirm." + album.id.uuidString)
                                    Text("Choose at least 12 characters. Face ID will authorize this album's export. The copy will use this separate password; this phone's album protection stays unchanged.").font(.footnote)
                                    PasswordStrengthView(password: albumPasswords[album.id] ?? "")
                                }
                            }
                        }
                        if !biometricRows.isEmpty {
                            Toggle("I understand that these Face ID-only albums will have password-readable copies in this backup", isOn: $biometricConsent)
                                .accessibilityIdentifier("backup.biometricConsent")
                        }
                    }.disabled(session.isWorking)
                }
                Section {
                    if session.isWorking {
                        Text("Keep WagLock open while the backup is prepared.").font(.footnote)
                        ProgressView("Preparing encrypted backup…", value: session.progress)
                            .accessibilityIdentifier("backup.progress")
                        Button("Cancel backup", role: .cancel) { session.cancel() }.accessibilityIdentifier("backup.cancel")
                    } else {
                        Button("Create encrypted backup") { start() }
                            .disabled(!canStart).accessibilityIdentifier("backup.create")
                    }
                }
            } else {
                Section("Encrypted backup ready") {
                    Text("Only the encrypted file will be given to Files. Keep your backup password, recovery identity and any separate album passwords safe.")
                    Button("Save to Files or cloud storage") {
                        guard let url = session.beginHandoff() else { return }
                        handoff = .init(url: url)
                    }.accessibilityIdentifier("backup.save")
                    Button("Discard this copy", role: .destructive) { session.cancel() }.accessibilityIdentifier("backup.discard")
                }
            }
            if let error = session.error { Section { Text(error).foregroundStyle(ColorTheme.destructive).accessibilityIdentifier("backup.error") } }
            if saved {
                Section { Text("Saved to Files. Your provider manages cloud upload; verify the copy on another device.").accessibilityIdentifier("backup.saved") }
            }
            Section("Recovery") {
                Text("Open the .tar.age file with the open-source age tool, then verify and extract it using WagLock's recovery helper. Protected child archives need their separate passwords.")
                Link("Recovery instructions", destination: URL(string: "https://github.com/donnellymjd/waglock/blob/main/docs/portable-vault/backup-recovery.md")!)
                Text("Choose On My iPhone, iCloud Drive or another provider enabled in Files. Backup is optional; there is no automatic upload or two-way sync.").font(.footnote)
            }
        }
        .wagLockList().navigationTitle("Encrypted backup").navigationBarTitleDisplayMode(.inline)
        .onAppear { session.refresh(mounts: mounts, request: request) }
        .onDisappear { session.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { session.cancel() } }
        .onChange(of: session.readyURL) { _, url in if url != nil { password = ""; confirmation = ""; albumPasswords = [:]; albumConfirmations = [:] } }
        .sheet(item: $handoff, onDismiss: { if session.handingOff { session.finishHandoff() } }) { file in
            SystemBackupSave(url: file.url) { success in
                saved = success; session.finishHandoff(); handoff = nil
            }
        }
    }
    private func passwordField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        SwitchablePasswordField(title: title, text: text, keyboard: keyboard, identifier: identifier,
            submitTitle: "Done", onSubmit: { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) })
            .frame(minHeight: 36)
    }
    private var canStart: Bool {
        guard mode.isOwnerMode, auth.isAuthenticated else { return false }
        if method == "password" {
            guard password.count >= 12, Data(password.utf8) == Data(confirmation.utf8) else { return false }
        } else { guard (try? AgeFileWriter.decodeRecipient(recipient.trimmingCharacters(in: .whitespacesAndNewlines))) != nil else { return false } }
        return session.rows.filter { $0.policy != .inherited }.allSatisfy { album in
            let value = albumPasswords[album.id] ?? ""
            return album.policy == .faceIDOnly ? biometricConsent && value.count >= 12 && Data(value.utf8) == Data((albumConfirmations[album.id] ?? "").utf8) : !value.isEmpty
        }
    }
    private func start() {
        saved = false
        let credential: AgeFileWriter.Credential = method == "password" ? .password(password) : .recipient(recipient.trimmingCharacters(in: .whitespacesAndNewlines))
        session.start(mounts: mounts, auth: auth, rootCredential: credential, passwords: albumPasswords,
            consent: biometricConsent ? Set(biometricRows.map(\.id)) : [])
    }
}

/// System-managed copy to local/iCloud/installed providers. No provider SDK or account access.
private struct SystemBackupSave: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private var done = false
        private let completion: (Bool) -> Void
        init(_ completion: @escaping (Bool) -> Void) { self.completion = completion }
        private func finish(_ saved: Bool) { guard !done else { return }; done = true; completion(saved) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(false) }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(!urls.isEmpty) }
    }
}
