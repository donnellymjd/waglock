import SwiftUI
import UIKit

struct PortableBackupView: View {
    @EnvironmentObject private var services: VaultSessionContext
    var body: some View { ScopedPortableBackupView(services: services).id(services.sessionID) }
}

private struct ScopedPortableBackupView: View {
    init(services: VaultSessionContext) {
        _session = StateObject(wrappedValue: PortableBackupSession(authority: services.documents,
            albums: services.albums, storage: services.storage))
    }
    @EnvironmentObject private var auth: AuthenticationViewModel
    @EnvironmentObject private var services: VaultSessionContext
    @EnvironmentObject private var reminders: BackupReminderStore
    @EnvironmentObject private var mounts: LibraryMountCoordinator
    @EnvironmentObject private var mode: GuestModeManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: PortableBackupSession
    @State private var method = "password"
    @State private var useVaultPassword = false
    @State private var acknowledgedReuse = false
    @State private var password = ""
    @State private var confirmation = ""
    @State private var recipient = ""
    @State private var albumPasswords: [UUID: String] = [:]
    @State private var albumConfirmations: [UUID: String] = [:]
    @State private var biometricConsent = false
    @State private var keyboard = PasswordKeyboard.fullKeyboard
    @State private var handoff: BackupFile?
    @State private var saved = false
    @State private var backupName = PortableBackupSession.suggestedExportName()
    private struct BackupFile: Identifiable { let id = UUID(); let url: URL }
    private var request: LibraryMountCoordinator.Request { .init(sessionID: auth.librarySessionID, scope: auth.libraryScope) }
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
                        Toggle("Use this vault's password", isOn: $useVaultPassword)
                            .accessibilityIdentifier("backup.useVaultPassword")
                        if useVaultPassword {
                            passwordField("Current vault password", text: $password, identifier: "backup.vaultPassword", contentType: .password)
                            Text("Enter this library's password again, even if you unlocked with Face ID. It will be verified before export. This does not use your device passcode.").font(.footnote)
                            Text("An exported backup can be guessed offline. Short PINs give weaker protection. Changing your vault password later does not change existing backups; each copy needs the password used when it was made.").font(.footnote)
                            Toggle("I understand the risks of using the same password for this backup", isOn: $acknowledgedReuse)
                                .accessibilityIdentifier("backup.reuseConsent")
                        } else {
                            passwordField("New backup password", text: $password, identifier: "backup.password", contentType: .newPassword)
                            passwordField("Confirm backup password", text: $confirmation, identifier: "backup.confirm", contentType: .newPassword)
                            PasswordConfirmationButton(password: password, confirmation: $confirmation, identifier: "backup.confirmEntered")
                            PasswordStrengthView(password: password)
                            Text("Use at least 12 characters, preferably several random words. This password protects the copy; it does not change your WagLock password.")
                                .font(.footnote)
                        }
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
                                    identifier: "backup.album." + album.id.uuidString,
                                    contentType: album.policy == .faceIDOnly ? .newPassword : .password)
                                if album.policy == .faceIDOnly {
                                    passwordField("Confirm export password",
                                        text: Binding(get: { albumConfirmations[album.id] ?? "" }, set: { albumConfirmations[album.id] = $0 }),
                                        identifier: "backup.album.confirm." + album.id.uuidString, contentType: .newPassword)
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
                    LabeledContent("Filename") {
                        HStack {
                            TextField("Backup name", text: $backupName)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.done)
                                .onSubmit { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                                .accessibilityIdentifier("backup.filename")
                            if !backupName.isEmpty {
                                Button { backupName = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(ColorTheme.secondaryText)
                                }.buttonStyle(.borderless).accessibilityLabel("Clear backup filename")
                                    .accessibilityIdentifier("backup.filename.clear")
                            }
                        }
                    }
                    Text("The default name includes the date and time in UTC. You can edit it; .tar.age is added automatically.").font(.footnote)
                    Button("Save to Files or cloud storage") {
                        guard let url = session.beginHandoff(filename: backupName) else { return }
                        handoff = .init(url: url)
                    }.disabled(PortableBackupSession.exportFilename(backupName) == nil).accessibilityIdentifier("backup.save")
                    Button("Discard this copy", role: .destructive) { session.cancel() }.accessibilityIdentifier("backup.discard")
                }
            }
            if let error = session.error { Section { Text(error).foregroundStyle(ColorTheme.destructive).accessibilityIdentifier("backup.error") } }
            if saved {
                Section { Text("Saved to Files. Your provider manages cloud upload; verify the copy on another device.").accessibilityIdentifier("backup.saved") }
            }
            Section("Reminders") {
                NavigationLink("Backup reminders") { BackupReminderSettingsView() }
                    .accessibilityIdentifier("backup.reminder.settings")
                Text("Monthly by default, only after unlock. Change the frequency or turn reminders off in Settings.").font(.footnote)
            }
            Section("Recovery") {
                Text("Open the .tar.age file with the open-source age tool, then verify and extract it using WagLock's recovery helper. Protected child archives need their separate passwords.")
                Link("Recovery instructions", destination: URL(string: "https://github.com/donnellymjd/waglock/blob/main/docs/portable-vault/backup-recovery.md")!)
                Text("Choose On My iPhone, iCloud Drive or another provider enabled in Files. Backup is optional; there is no automatic upload or two-way sync.").font(.footnote)
            }
        }
        .wagLockList().navigationTitle("Encrypted backup").navigationBarTitleDisplayMode(.inline)
        .onAppear { session.refresh(mounts: mounts, request: request) }
        .onDisappear { session.cancel(); clearCredentials() }
        .onChange(of: useVaultPassword) { _, _ in password = ""; confirmation = ""; acknowledgedReuse = false }
        .onChange(of: method) { _, _ in clearCredentials() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { session.cancel(); clearCredentials() } }
        .onChange(of: session.readyURL) { previous, url in
            if url != nil { password = ""; confirmation = ""; albumPasswords = [:]; albumConfirmations = [:] }
            if previous == nil, url != nil { backupName = PortableBackupSession.suggestedExportName() }
        }
        .sheet(item: $handoff, onDismiss: { if session.handingOff { session.finishHandoff() } }) { file in
            SystemBackupSave(url: file.url) { success in
                saved = success
                if success, services.isActive, auth.librarySessionID == services.sessionID { reminders.recordSavedToFiles() }
                session.finishHandoff(); handoff = nil
            }
        }
    }
    private func clearCredentials() {
        password = ""; confirmation = ""; acknowledgedReuse = false; albumPasswords = [:]; albumConfirmations = [:]
    }

    private func passwordField(_ title: String, text: Binding<String>, identifier: String,
                               contentType: UITextContentType = .password) -> some View {
        SwitchablePasswordField(title: title, text: text, keyboard: keyboard, contentType: contentType, identifier: identifier,
            submitTitle: "Done", onSubmit: { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) })
            .frame(minHeight: 36)
    }
    private var canStart: Bool {
        guard mode.isOwnerMode, auth.isAuthenticated else { return false }
        if method == "password" {
            if useVaultPassword {
                guard acknowledgedReuse, !password.isEmpty else { return false }
            } else { guard password.count >= 12, PasswordText.matches(password, confirmation) else { return false } }
        } else { guard (try? AgeFileWriter.decodeRecipient(recipient.trimmingCharacters(in: .whitespacesAndNewlines))) != nil else { return false } }
        return session.rows.filter { $0.policy != .inherited }.allSatisfy { album in
            let value = albumPasswords[album.id] ?? ""
            return album.policy == .faceIDOnly ? biometricConsent && value.count >= 12 && PasswordText.matches(value, albumConfirmations[album.id] ?? "") : !value.isEmpty
        }
    }
    private func start() {
        saved = false
        let credential: AgeFileWriter.Credential = method == "password" ? .password(password) : .recipient(recipient.trimmingCharacters(in: .whitespacesAndNewlines))
        session.start(mounts: mounts, auth: auth, rootCredential: credential, passwords: albumPasswords,
            consent: biometricConsent ? Set(biometricRows.map(\.id)) : [],
            passwordSource: method == "password" && useVaultPassword ? .currentVault : .independent,
            acknowledgedReuse: acknowledgedReuse)
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
