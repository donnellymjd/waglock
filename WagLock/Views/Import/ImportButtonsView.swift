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
    @State private var completedFileOriginals = 0
    @State private var showCamera = false
    @State private var showLibraryBrowser = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Graphite.base.ignoresSafeArea()
                if let completedCount {
                    ImportCompleteView(count: completedCount, photoAssetIDs: completedAssetIDs,
                                       pasted: viewModel.lastImportWasPaste,
                                       fileOriginalCount: completedFileOriginals,
                                       removeFileOriginals: { await viewModel.removeFileOriginals() }) { dismiss() }
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
            .fullScreenCover(isPresented: $showLibraryBrowser) {
                PhotoLibraryBrowserView(add: { identifiers in
                    showLibraryBrowser = false
                    viewModel.importFromLibraryAssets(identifiers)
                }, cancel: { showLibraryBrowser = false })
            }
            .sheet(isPresented: $viewModel.reservedSpaceFull) { StorageFullView() }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { url in
                    showCamera = false
                    if let url { viewModel.importFromCamera(url) }
                }
                .ignoresSafeArea()
            }
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
                    if items.isEmpty && viewModel.lastImportWasPaste {
                        viewModel.errorMessage = "Nothing on the clipboard could be added. Copy a photo, video, audio file or document, then paste again."
                    } else if items.isEmpty {
                        dismiss()
                    } else {
                        completedAssetIDs = viewModel.removablePhotoAssetIDs
                        completedFileOriginals = viewModel.removableFileSources.count
                        completedCount = items.count
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isImporting)
    }

    // MARK: - Paste

    /// The system Paste button reads the clipboard only when tapped, so iOS shows no
    /// paste prompt and WagLock never inspects the clipboard on its own.
    private var pasteRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 18)).foregroundStyle(Graphite.accentText)
                .frame(width: 40, height: 40).background(Graphite.surface2, in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Paste").font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary)
                Text("Photos, videos, audio or files you copied").font(.wlMeta).foregroundStyle(Graphite.textMuted)
            }
            Spacer(minLength: 8)
            PasteButton(supportedContentTypes: [.image, .movie, .audio, .data]) { providers in
                Task { @MainActor in viewModel.importFromPasteboard(providers: providers) }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
            .tint(Graphite.accentStrong)
            .accessibilityIdentifier("import.paste")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
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
                    if CameraCaptureView.isAvailable {
                        Button { showCamera = true } label: {
                            WagLockRow(symbol: "camera", title: "Take photo or video", detail: "Goes straight into WagLock, not your camera roll")
                        }.buttonStyle(.plain).accessibilityIdentifier("import.camera")
                    }
                    Button { viewModel.selectPhotos() } label: {
                        WagLockRow(symbol: "photo.on.rectangle", title: "Photos & videos", detail: "Choose from your photo library")
                    }.buttonStyle(.plain).accessibilityIdentifier("import.photos")
                    Button { showLibraryBrowser = true } label: {
                        WagLockRow(symbol: "checkmark.circle", title: "Select all from Photos",
                                   detail: "Browse an album and select everything in it. Needs access to your photo library")
                    }.buttonStyle(.plain).accessibilityIdentifier("import.photosSelectAll")
                    Button { viewModel.selectFiles() } label: {
                        WagLockRow(symbol: "folder", title: "Files", detail: "Documents, archives and other files")
                    }.buttonStyle(.plain).accessibilityIdentifier("import.files")
                    Button { viewModel.selectAudio() } label: {
                        WagLockRow(symbol: "waveform", title: "Audio", detail: "Import recordings and audio files")
                    }.buttonStyle(.plain).accessibilityIdentifier("import.audio")
                    pasteRow
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
    var pasted = false
    var fileOriginalCount = 0
    var removeFileOriginals: () async -> ImportedOriginalsRemover.Outcome = { .init() }
    let done: () -> Void
    @EnvironmentObject private var reminders: BackupReminderStore
    @State private var removingFromPhotos = false
    @State private var showBackup = false
    @State private var clipboardCleared = false
    @State private var fileRemoval: FileRemoval = .idle
    @State private var confirmFileRemoval = false
    enum FileRemoval: Equatable { case idle, kept, removing, done(ImportedOriginalsRemover.Outcome) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "checkmark.seal").font(.system(size: 34)).foregroundStyle(Graphite.accentText)
                        .frame(width: 64, height: 64).background(Graphite.accentTint, in: Circle())
                        .accessibilityHidden(true).padding(.top, 24)
                    WagLockTitle(text: "\(count) item\(count == 1 ? "" : "s") added", size: .sheet)
                    Text("Encrypted and saved in your Library").font(.wlBody).foregroundStyle(Graphite.textMuted)
                    if !photoAssetIDs.isEmpty { PhotosOriginalsCard(photoAssetIDs: photoAssetIDs, isRemoving: $removingFromPhotos) }
                    if pasted { clipboardCard }
                    if fileOriginalCount > 0 { fileOriginalsCard }
                    Button { showBackup = true } label: {
                        WagLockRow(symbol: "icloud.and.arrow.up", title: "Back up now",
                                   detail: reminders.lastSaved.map { "Last encrypted backup " + $0.formatted(.relative(presentation: .named)) }
                                       ?? "No encrypted backup yet")
                    }.buttonStyle(.plain).accessibilityIdentifier("import.complete.backup")
                }
            }
            Button("Done", action: done).buttonStyle(WagLockPrimaryButtonStyle())
                .disabled(removingFromPhotos || fileRemoval == .removing)
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

    /// Files originals: kept unless the person asks, and each deletion is preceded by a
    /// byte-for-byte check of the encrypted copy.
    private var fileOriginalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch fileRemoval {
            case .kept:
                WagLockNote(kind: .info, title: "Originals kept in Files", text: "They stay an independent copy outside WagLock.")
            case .done(let outcome):
                WagLockNote(kind: outcome.kept == 0 ? .info : .caution,
                            title: "Deleted \(outcome.deleted) original\(outcome.deleted == 1 ? "" : "s")",
                            text: outcome.kept == 0
                                ? "Each one was checked against its encrypted copy first. Some locations keep deleted files in Recently Deleted."
                                : "\(outcome.kept) kept because its copy couldn’t be checked or its location doesn’t allow deleting.")
            case .removing:
                ProgressView("Checking copies and deleting…").tint(Graphite.accentText).font(.wlMeta)
            case .idle:
                WagLockNote(kind: .caution, title: "Originals are still in Files",
                            text: "The \(fileOriginalCount == 1 ? "file you picked is" : "\(fileOriginalCount) files you picked are") still where you found \(fileOriginalCount == 1 ? "it" : "them"). Keep them as an independent copy, or delete them now.")
                HStack(spacing: 10) {
                    Button("Keep") { fileRemoval = .kept }.buttonStyle(WagLockSecondaryButtonStyle())
                        .accessibilityIdentifier("import.complete.keepFiles")
                    Button("Delete originals…") { confirmFileRemoval = true }.buttonStyle(WagLockSecondaryButtonStyle())
                        .accessibilityIdentifier("import.complete.deleteFiles")
                }
            }
        }
        .confirmationDialog("Delete \(fileOriginalCount) original\(fileOriginalCount == 1 ? "" : "s") from Files?",
                            isPresented: $confirmFileRemoval, titleVisibility: .visible) {
            Button("Delete originals", role: .destructive) {
                fileRemoval = .removing
                Task { fileRemoval = .done(await removeFileOriginals()) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WagLock first checks that each encrypted copy matches its original exactly. Anything it can’t check is kept. Some locations move deleted files to Recently Deleted; others delete them permanently.")
        }
    }

    /// Pasted items stay on the clipboard, which can sync to other devices (Universal Clipboard).
    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if clipboardCleared {
                WagLockNote(kind: .info, title: "Clipboard cleared", text: "The copied item is no longer on this iPhone’s clipboard.")
            } else {
                WagLockNote(kind: .caution, title: "Still on your clipboard",
                            text: "What you copied stays on the clipboard and can sync to your other devices. The original you copied it from is unchanged.")
                Button("Clear clipboard") {
                    UIPasteboard.general.items = []
                    clipboardCleared = true
                }
                .buttonStyle(WagLockSecondaryButtonStyle())
                .accessibilityIdentifier("import.complete.clearClipboard")
            }
        }
    }
}

/// Originals still in Photos after an import: Keep, or an explicit, iOS-confirmed
/// "Remove from Photos…". Nothing is removed without that tap and the iOS prompt.
/// Used by the main import and by album imports.
struct PhotosOriginalsCard: View {
    let photoAssetIDs: [String]
    @Binding var isRemoving: Bool
    @State private var removal: Removal = .idle
    enum Removal: Equatable { case idle, kept, removing, removed, failed(String) }

    var body: some View {
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
        .onChange(of: removal) { _, value in isRemoving = value == .removing }
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
