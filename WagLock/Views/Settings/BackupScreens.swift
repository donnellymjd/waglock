import SwiftUI
import UIKit

/// "Save your recovery key": shows a freshly generated age identity once. There is no copy
/// button (the clipboard can sync to other devices). Print and Save to Files hand the key
/// to iOS; the temporary file for Files is removed when the picker closes.
struct RecoveryKeyView: View {
    let key: AgeRecoveryKey
    let onContinue: (String) -> Void
    let onCancel: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var stored = false
    @State private var exportURL: ExportFile?
    private struct ExportFile: Identifiable { let id = UUID(); let url: URL }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WagLockRoundButton(symbol: "chevron.left", label: "Back", action: onCancel)
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WagLockSectionLabel("Encrypted backup")
                    WagLockTitle(text: "Save your recovery key")
                    Text("If you lose this key, backups made with it can’t be opened. Anyone with it can open them too.")
                        .font(.wlBody).foregroundStyle(Graphite.textMuted).fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(Array(key.groupedIdentity.enumerated()), id: \.offset) { _, group in
                            Text(group).font(.system(size: 16, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Graphite.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Graphite.input, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(14).background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Recovery key")
                    .accessibilityValue(key.groupedIdentity.joined(separator: " "))
                    .privacySensitive()
                    Text("Starts with AGE-SECRET-KEY-1. It works with the open-source age tool on any computer.")
                        .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                    HStack(spacing: 10) {
                        Button { printKey() } label: { Label("Print", systemImage: "printer") }
                            .buttonStyle(WagLockSecondaryButtonStyle()).accessibilityIdentifier("recoveryKey.print")
                        Button { saveToFiles() } label: { Label("Save to Files", systemImage: "folder") }
                            .buttonStyle(WagLockSecondaryButtonStyle()).accessibilityIdentifier("recoveryKey.save")
                    }
                    WagLockNote(kind: .caution, text: "No copy button: the clipboard can sync to other devices. WagLock won’t show this key again.")
                    Toggle(isOn: $stored) {
                        Text("I’ve stored it somewhere safe").font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary)
                    }
                    .tint(Graphite.accentStrong).accessibilityIdentifier("recoveryKey.stored")
                }
            }
            Button("Continue") { onContinue(key.recipient) }
                .buttonStyle(WagLockPrimaryButtonStyle()).disabled(!stored)
                .accessibilityIdentifier("recoveryKey.continue")
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(Graphite.base.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in if phase == .background { onCancel() } }
        .sheet(item: $exportURL, onDismiss: removeExport) { file in
            KeyFileExporter(url: file.url) { exportURL = nil }
        }
    }

    private func printKey() {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.outputType = .grayscale
        info.jobName = "WagLock recovery key"
        controller.printInfo = info
        controller.printFormatter = UISimpleTextPrintFormatter(text: key.identityFileText)
        controller.present(animated: true)
    }

    private func saveToFiles() {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("WagLockRecoveryKey-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
            let url = directory.appendingPathComponent("waglock-recovery-key.txt")
            try Data(key.identityFileText.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = ExportFile(url: url)
        } catch {}
    }

    private func removeExport() {
        let root = FileManager.default.temporaryDirectory
        if let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for item in items where item.lastPathComponent.hasPrefix("WagLockRecoveryKey-") {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }
}

private struct KeyFileExporter: UIViewControllerRepresentable {
    let url: URL
    let done: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(done) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let done: () -> Void
        init(_ done: @escaping () -> Void) { self.done = done }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { done() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done() }
    }
}

/// "Backup didn't finish": the reason, reassurance that the library is unchanged, and ways forward.
struct BackupFailedCard: View {
    let reason: String
    let lastBackup: Date?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "icloud.slash").font(.system(size: 28)).foregroundStyle(Graphite.danger)
                .frame(width: 64, height: 64).background(Graphite.dangerTint, in: Circle())
                .accessibilityHidden(true)
            WagLockTitle(text: "Backup didn’t finish", size: .sheet)
            Text(reason).font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("backup.error")
            WagLockNote(kind: .info, text: "This library is unchanged. WagLock removes its own incomplete backup file, so nothing partial is left behind.")
            WagLockSectionLabel("Try another way")
            Button(action: retry) {
                WagLockRow(symbol: "arrow.clockwise", title: "Try again", detail: "Check the details above, then start the backup again")
            }.buttonStyle(.plain).accessibilityIdentifier("backup.retry")
            Text(lastBackup.map { "Last successful backup: " + $0.formatted(.relative(presentation: .named)) } ?? "No successful backup yet")
                .font(.wlMeta).foregroundStyle(Graphite.textMuted).frame(maxWidth: .infinity)
        }
    }
}
