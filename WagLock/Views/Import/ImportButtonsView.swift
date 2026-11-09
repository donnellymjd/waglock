//
//  ImportButtonsView.swift
//  WagLock
//
//  Add to WagLock: source choice, import progress and import complete
//

import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportButtonsView: View {
    @EnvironmentObject private var services: VaultSessionContext
    let onImportComplete: ([MediaItem]) -> Void
    var body: some View {
        ScopedImportButtonsView(storage: services.storage, onImportComplete: onImportComplete)
            .id(services.sessionID)
    }
}

private struct ScopedImportButtonsView: View {

    // MARK: - Properties

    @StateObject private var viewModel: ImportViewModel
    init(storage: FileStorageService, onImportComplete: @escaping ([MediaItem]) -> Void) {
        _viewModel = StateObject(wrappedValue: ImportViewModel(storage: storage))
        self.onImportComplete = onImportComplete
    }
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    let onImportComplete: ([MediaItem]) -> Void

    @State private var completedCount: Int?
    @State private var completedAssetIDs: [String] = []

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Graphite.base.ignoresSafeArea()
                if let completedCount {
                    ImportCompleteView(count: completedCount, photoAssetIDs: completedAssetIDs) { dismiss() }
                } else if viewModel.isImporting {
                    importProgressView
                } else {
                    importOptionsView
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $viewModel.showPhotoPicker) {
                PhotoPickerRepresentable(
                    isPresented: $viewModel.showPhotoPicker,
                    selectionLimit: 0,
                    filter: .any(of: [.images, .videos])
                ) { results in
                    viewModel.importFromPhotoLibrary(results: results)
                }
            }
            .sheet(isPresented: $viewModel.showFilePicker) {
                DocumentPickerRepresentable(
                    isPresented: $viewModel.showFilePicker,
                    contentTypes: [.item],
                    allowsMultipleSelection: true
                ) { urls in
                    viewModel.importFromFiles(urls: urls)
                }
            }
            .sheet(isPresented: $viewModel.reservedSpaceFull) { StorageFullView() }
            .sheet(isPresented: $viewModel.showAudioPicker) {
                DocumentPickerRepresentable(
                    isPresented: $viewModel.showAudioPicker,
                    contentTypes: [.audio],
                    allowsMultipleSelection: true
                ) { urls in
                    viewModel.importFromFiles(urls: urls)
                }
            }
            .sheet(isPresented: $viewModel.showEncryptedPasswordInput, onDismiss: {
                if viewModel.pendingEncryptedFile != nil {
                    viewModel.cancelEncryptedFilePasswordInput()
                }
            }) {
                if let pendingFile = viewModel.pendingEncryptedFile {
                    EncryptedFilePasswordInputView(
                        fileName: pendingFile.fileName,
                        onConfirm: { password in
                            viewModel.handleEncryptedFilePassword(password)
                        },
                        onCancel: {
                            viewModel.cancelEncryptedFilePasswordInput()
                        }
                    )
                }
            }
            .alert(
                String(localized: "import.failed"),
                isPresented: .constant(viewModel.errorMessage != nil)
            ) {
                Button(String(localized: "common.ok")) {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .onAppear {
                viewModel.modelContext = modelContext
                viewModel.authViewModel = authViewModel
                viewModel.onImportComplete = { items in
                    onImportComplete(items)
                    if items.isEmpty {
                        dismiss()
                    } else {
                        completedAssetIDs = viewModel.removablePhotoAssetIDs
                        completedCount = items.count
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isImporting)
    }

    // MARK: - Import progress

    private var importProgressView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            WagLockSectionLabel("Adding to Library")
            if let progress = viewModel.importProgress {
                Text("\(progress.current) of \(progress.total)")
                    .font(.wlDisplay).foregroundStyle(Graphite.textPrimary).wlCappedDisplay()
                    .accessibilityLabel("\(progress.current) of \(progress.total) items added")
            } else {
                Text("Preparing…").font(.wlTitle).foregroundStyle(Graphite.textPrimary)
            }
            WagLockProgressCard(title: "Encrypting as we go",
                                detail: "Each item is encrypted the moment it’s copied in. Your originals stay where they are.",
                                progress: viewModel.importProgress?.percentage)
            WagLockNote(kind: .caution, text: "Leaving WagLock locks it right away and stops this import. Nothing partial is kept; add the rest after you unlock.")
            Spacer()
            Button("Cancel import") { viewModel.cancelImport(); dismiss() }
                .buttonStyle(WagLockSecondaryButtonStyle())
                .accessibilityIdentifier("import.cancel")
        }
        .padding(.horizontal, 22).padding(.vertical, 24)
    }

    // MARK: - Source choice

    private var importOptionsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WagLockRoundButton(symbol: "xmark", label: "Close") { dismiss() }
                    .accessibilityIdentifier("import.close")
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WagLockTitle(text: "Add to WagLock", size: .sheet)
                    Text("Selected items are copied into this library. Your originals stay where they are.")
                        .font(.wlBody).foregroundStyle(Graphite.textMuted)
                    Button { viewModel.selectPhotos() } label: {
                        WagLockRow(symbol: "photo.on.rectangle", title: "Photos & videos", detail: "Choose from your photo library")
                    }.buttonStyle(.plain).accessibilityIdentifier("import.photos")
                    Button { viewModel.selectFiles() } label: {
                        WagLockRow(symbol: "folder", title: "Files", detail: "Documents, archives and other files")
                    }.buttonStyle(.plain).accessibilityIdentifier("import.files")
                    Button { viewModel.selectAudio() } label: {
                        WagLockRow(symbol: "waveform", title: "Audio", detail: "Import recordings and audio files")
                    }.buttonStyle(.plain).accessibilityIdentifier("import.audio")
                    WagLockNote(kind: .info, title: "Choosing a cloud file?",
                                text: "The iOS picker may download it first. That transfer is handled by iOS.")
                    Text(LibraryStoragePolicy.encryptedMetadata ? "Keep independent originals and verify your encrypted backups." : "Use sample media in this early test build. Keep independent originals.")
                        .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                }
            }
            // Retained so existing tests and VoiceOver users find the familiar control.
            Button("Cancel") { dismiss() }
                .font(WagLockFonts.poppins(14, .semibold, relativeTo: .body))
                .foregroundStyle(Graphite.textSecondary).frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }
}

/// Import complete: count, the originals-in-Photos warning with an explicit, iOS-confirmed
/// "Remove from Photos…", and a path to back up. Nothing is removed without that tap.
private struct ImportCompleteView: View {
    let count: Int
    let photoAssetIDs: [String]
    let done: () -> Void
    @EnvironmentObject private var reminders: BackupReminderStore
    @State private var removal: Removal = .idle
    @State private var showBackup = false
    enum Removal: Equatable { case idle, kept, removing, removed, failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "checkmark.seal").font(.system(size: 34)).foregroundStyle(Graphite.accentText)
                        .frame(width: 64, height: 64).background(Graphite.accentTint, in: Circle())
                        .accessibilityHidden(true).padding(.top, 24)
                    WagLockTitle(text: "\(count) item\(count == 1 ? "" : "s") added", size: .sheet)
                    Text("Encrypted and saved in your Library").font(.wlBody).foregroundStyle(Graphite.textMuted)
                    if !photoAssetIDs.isEmpty { originalsCard }
                    Button { showBackup = true } label: {
                        WagLockRow(symbol: "icloud.and.arrow.up", title: "Back up now",
                                   detail: reminders.lastSaved.map { "Last encrypted backup " + $0.formatted(.relative(presentation: .named)) }
                                       ?? "No encrypted backup yet")
                    }.buttonStyle(.plain).accessibilityIdentifier("import.complete.backup")
                }
            }
            Button("Done", action: done).buttonStyle(WagLockPrimaryButtonStyle())
                .disabled(removal == .removing)
                .accessibilityIdentifier("import.complete.done")
        }
        .padding(.horizontal, 22).padding(.bottom, 24)
        .sheet(isPresented: $showBackup) {
            NavigationStack {
                PortableBackupView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showBackup = false } } }
            }
        }
    }

    private var originalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch removal {
            case .removed:
                WagLockNote(kind: .info, title: "Removed from Photos",
                            text: "They’re in Recently Deleted in Photos until iOS clears it. Recently Deleted shows that something was imported.")
            case .kept:
                WagLockNote(kind: .info, title: "Originals kept in Photos",
                            text: "They stay an independent copy outside WagLock.")
            default:
                WagLockNote(kind: .caution, title: "Originals are still in Photos",
                            text: "Anyone who opens your Photos app can still see them. Keep them as an independent copy, or remove them now.")
                HStack(spacing: 10) {
                    Button("Keep") { removal = .kept }.buttonStyle(WagLockSecondaryButtonStyle())
                        .accessibilityIdentifier("import.complete.keep")
                    Button("Remove from Photos…", action: removeOriginals).buttonStyle(WagLockSecondaryButtonStyle())
                        .accessibilityIdentifier("import.complete.remove")
                }
                .disabled(removal == .removing)
                Text("iOS asks you to confirm. Removed items go to Recently Deleted in Photos.")
                    .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                if case .failed(let message) = removal { WagLockNote(kind: .error, text: message) }
            }
        }
    }

    /// iOS shows its own deletion confirmation; cancelling it leaves everything in Photos.
    private func removeOriginals() {
        let identifiers = photoAssetIDs
        removal = .removing
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else {
                removal = .failed("WagLock needs Photos access to remove them. Your originals are unchanged; you can delete them in Photos.")
                return
            }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            guard assets.count > 0 else {
                removal = .failed("WagLock couldn’t find these originals in Photos. Nothing was removed.")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(assets)
                }
                removal = .removed
            } catch {
                removal = .idle // Cancelled at the iOS prompt, or iOS refused: nothing removed.
            }
        }
    }
}
