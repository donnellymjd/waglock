//
//  FilePreviewView.swift
//  WagLock
//
//  Session-bound PDF and text document previews.
//

import PDFKit
import SwiftUI

struct FilePreviewView: View {

    // MARK: - Properties

    private let sourceFile: MediaItem
    let file: MediaPreviewSnapshot

    init(file: MediaItem) {
        sourceFile = file
        self.file = MediaPreviewSnapshot(file)
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @State private var originatingSessionID: UUID?
    @State private var exportJobID: UUID?
    @Environment(\.scenePhase) private var exportScenePhase
    @StateObject private var preview = DocumentPreviewModel()
    @State private var isExporting: Bool = false
    @State private var exportedURLs: [URL] = []
    @State private var showShareSheet = false
    @State private var exportError: String?
    @State private var showAlert = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                ColorTheme.primaryBackground
                    .ignoresSafeArea()

                previewContent
            }
            .navigationTitle(file.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            shareFile()
                        } label: {
                            Label(
                                String(localized: "common.share"),
                                systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            deleteFile()
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task(id: preview.authorizationRevision) { loadPreview() }
        .alert(String(localized: "filePreview.alert.title"), isPresented: $showAlert) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onDisappear {
            preview.clear()
            if !showShareSheet, let exportJobID { ExportService.shared.cancelExport(exportJobID) }
        }
        .onChange(of: exportScenePhase) { _, phase in
            if phase == .background {
                preview.clear()
                isExporting = false
                showShareSheet = false
            }
        }
        .sheet(
            isPresented: $showShareSheet,
            onDismiss: {
                exportedURLs.removeAll()
            }
        ) {
            ShareSheet(items: exportedURLs)
        }
        .loadingOverlay(
            isShowing: preview.isLoading || isExporting,
            message: isExporting
                ? String(localized: "filePreview.exporting")
                : String(localized: "filePreview.decrypting")
        )
    }

    // MARK: - Preview Content

    @ViewBuilder
    private var previewContent: some View {
        let ext = file.fileExtension.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        switch ext {
        case "pdf":
            pdfPreview
        case "txt", "md":
            textPreview
        default:
            unsupportedPreview
        }
    }

    // MARK: - PDF Preview

    private var pdfPreview: some View {
        Group {
            if let data = preview.data {
                PDFReaderView(data: data, onShare: shareFile)
            } else if preview.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(String(localized: "filePreview.decrypting"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = preview.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)

                    Text(String(localized: "filePreview.error.title"))
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        loadPreview()
                    } label: {
                        Label(String(localized: "common.retry"), systemImage: "arrow.clockwise")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
                    .onAppear {
                        loadPreview()
                    }
            }
        }
    }

    // MARK: - Text Preview

    private var textPreview: some View {
        ScrollView {
            if let error = preview.error {
                Text(error)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let data = preview.data, let content = String(data: data, encoding: .utf8) {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if preview.isLoading {
                ProgressView(String(localized: "filePreview.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(String(localized: "filePreview.text.error"))
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Unsupported Preview

    private var unsupportedPreview: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text(String(localized: "filePreview.unsupported"))
                .font(.headline)
                .foregroundColor(.secondary)

            Text(file.fileExtension.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.gray)
                .cornerRadius(8)

            Button {
                shareFile()
            } label: {
                Label(String(localized: "filePreview.export"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.top)
        }
    }

    // MARK: - Methods

    private func loadPreview() {
        guard authViewModel.isAuthenticated else { return }
        if originatingSessionID == nil { originatingSessionID = authViewModel.librarySessionID }
        guard originatingSessionID == authViewModel.librarySessionID else { return }
        let ext = file.fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard ext == "pdf" || isTextFile,
              !preview.isLoading, preview.data == nil,
              authViewModel.isAuthenticated,
              let password = authViewModel.sessionPassword else { return }
        preview.load(path: file.encryptedPath, password: password,
                     fileExtension: file.fileExtension, sessionID: authViewModel.librarySessionID)
    }

    private func shareFile() {
        guard authViewModel.isAuthenticated, originatingSessionID == authViewModel.librarySessionID, !isExporting else { return }
        guard let password = authViewModel.sessionPassword, !password.isEmpty else {
            exportError = String(localized: "filePreview.error.noPassword")
            return
        }

        isExporting = true
        exportError = nil

        let exportSessionID = authViewModel.librarySessionID
        exportJobID = ExportService.shared.exportItems([sourceFile], password: password, sessionID: exportSessionID) { result in
            guard authViewModel.isAuthenticated, authViewModel.librarySessionID == exportSessionID else { return }
            switch result {
            case .success(let urls):
                exportedURLs = urls
                showShareSheet = true
            case .failure(let error):
                exportError = error.localizedDescription
                showAlert = true
            }

            isExporting = false
        }
    }

    private func deleteFile() {
        // TODO: Implement deletion through the vault deletion/Trash policy.
        dismiss()
    }

    private var isTextFile: Bool {
        let ext = file.fileExtension.lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: "."))
        return ["txt", "md", "json", "csv", "log"].contains(ext)
    }

    private var alertMessage: String {
        if let exportError = exportError {
            return exportError
        }
        if let error = preview.error {
            return error
        }
        return String(localized: "filePreview.error.generic")
    }
}

// MARK: - Preview

#Preview {
    let sampleFile = MediaItem(
        fileName: "sample.pdf",
        fileExtension: "pdf",
        fileSize: 512_000,
        type: .document,
        encryptedPath: "/path/to/file"
    )

    FilePreviewView(file: sampleFile)
        .environmentObject(AuthenticationViewModel())
}
