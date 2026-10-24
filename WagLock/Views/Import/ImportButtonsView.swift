//
//  ImportButtonsView.swift
//  WagLock
//
//  导入按钮视图
//  提供照片和文件导入选项
//

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

    @State private var showImportSuccess = false
    @State private var importSuccessCount = 0

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                ColorTheme.primaryBackground
                    .ignoresSafeArea()

                if viewModel.isImporting { importProgressView } else { importOptionsView }
            }
            .navigationTitle(viewModel.isImporting ? "Adding to WagLock" : "Add to WagLock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.isImporting ? "Stop" : "Cancel") {
                        if viewModel.isImporting { viewModel.cancelImport() }
                        dismiss()
                    }
                }
            }
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
            .alert(
                String(localized: "import.success.title"),
                isPresented: $showImportSuccess
            ) {
                Button(String(localized: "common.ok")) {
                    showImportSuccess = false
                    dismiss()
                }
            } message: {
                Text(
                    String(
                        format: String(localized: "import.success.count"),
                        importSuccessCount))
            }
            .onAppear {

                viewModel.modelContext = modelContext
                viewModel.authViewModel = authViewModel
                viewModel.onImportComplete = { items in
                    onImportComplete(items)

                    if items.isEmpty {
                        dismiss()
                    } else {
                        // 显示成功提示，用户确认后关闭
                        importSuccessCount = items.count
                        showImportSuccess = true
                    }
                }

            }
        }
    }

    private var importProgressView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Keep this screen open").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                WagLockProgressCard(title: "Encrypting your selection", detail: viewModel.progressText, progress: viewModel.importProgress?.percentage)
                WagLockNavigationRow(symbol: "folder", title: "Destination", detail: "Main library")
                WagLockInfoCard(title: "Your originals stay where they are", detail: "WagLock copies and encrypts selected items. Photos edit history and Live Photo motion are not imported. Keep independent originals.")
            }.padding(24)
        }
    }

    // MARK: - Import Options View

    private var importOptionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Choose where to import from").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                WagLockInfoCard(title: "Keep what matters close", detail: "Selected items are copied into the vault. Your originals stay where they are.")
                ImportOptionButton(icon: "photo", title: "Photos & videos", subtitle: "Choose from your photo library", color: ColorTheme.accent) {
                    viewModel.selectPhotos()
                }.accessibilityIdentifier("import.photos")
                ImportOptionButton(icon: "folder", title: "Files", subtitle: "Documents, archives and other files", color: ColorTheme.accent) {
                    viewModel.selectFiles()
                }.accessibilityIdentifier("import.files")
                ImportOptionButton(icon: "waveform", title: "Audio", subtitle: "Import recordings and audio files", color: ColorTheme.accent) {
                    viewModel.selectAudio()
                }.accessibilityIdentifier("import.audio")
                WagLockInfoCard(title: "Choosing a cloud file?", detail: "The iOS picker may download it first. That transfer is handled by iOS.")
                Text(LibraryStoragePolicy.encryptedMetadata ? "Keep independent originals and verify your encrypted backups." : "Use sample media in this early test build. Keep independent originals.")
                    .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                if viewModel.isImporting {
                    Button(role: .destructive) { viewModel.cancelImport(); dismiss() } label: {
                        Label("Stop import", systemImage: "stop.circle").frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }.padding(24)
        }
    }

    // MARK: - Importing View

    private var importingView: some View {
        VStack(spacing: 30) {
            Spacer()

            // 动画图标
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: viewModel.progressPercentage)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear, value: viewModel.progressPercentage)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
            }

            // 进度信息
            VStack(spacing: 12) {
                Text(viewModel.progressText)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let progress = viewModel.importProgress {
                    Text("\(Int(progress.percentage * 100))%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            // 成功消息
            if viewModel.importedCount > 0 && !viewModel.isImporting {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text(String(localized: "import.success.title"))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(
                        String(
                            format: String(localized: "import.success.count"),
                            viewModel.importedCount)
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
    }

}

// MARK: - Import Option Button

struct ImportOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                WagLockNavigationRow(symbol: icon, title: title, detail: subtitle)
                Image(systemName: "chevron.right").font(.footnote)
                    .foregroundStyle(ColorTheme.secondaryText).padding(.trailing, 14)
            }.background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ImportButtonsView { items in
    }
    .modelContainer(for: [MediaItem.self])
}
