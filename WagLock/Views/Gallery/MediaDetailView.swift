//
//  MediaDetailView.swift
//  WagLock
//
//  Media detail view
//  Full-screen photo viewing, video playback and file preview
//

import AVKit
import CryptoKit
import PDFKit
import QuickLook
import SwiftUI

struct MediaDetailView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext

    // MARK: - Properties

    typealias VideoLoader = @Sendable (FileStorageService, String, String, String) async throws -> URL
    private let videoLoader: VideoLoader
    private let sourceItem: MediaItem
    let mediaItem: MediaPreviewSnapshot
    private let originatingSessionID: UUID?

    init(mediaItem: MediaItem, sessionID: UUID? = nil,
         videoLoader: @escaping VideoLoader = { storage, path, password, ext in
             try await storage.createDecryptedTempFileAsync(path: path, password: password, preferredExtension: ext)
         }) {
        self.videoLoader = videoLoader
        self.sourceItem = mediaItem
        self.mediaItem = MediaPreviewSnapshot(mediaItem)
        self.originatingSessionID = sessionID
    }

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    @State private var exportJobID: UUID?
    @Environment(\.scenePhase) private var exportScenePhase
    @StateObject private var documentPreview = DocumentPreviewModel()
    @State private var decryptedData: Data?
    @State private var decryptedImage: UIImage?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation: Bool = false
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero

    // Video player and temporary file management
    @State private var videoPlayer: AVPlayer?
    @State private var videoTempURL: URL?
    @State private var showFullScreenVideoPlayer = false

    // Document temporary file management (for QuickLook preview)
    @State private var documentTempURL: URL?

    // Sharing
    @State private var showShareSheet = false
    @State private var exportedURLs: [URL] = []
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showAlert = false

    // MARK: - Services

    private var storageService: FileStorageService { vaultServices.storage }
    private let keychainService = KeychainService.shared

    // MARK: - Body

    var body: some View {
        ZStack {
            ColorTheme.primaryBackground.ignoresSafeArea()

            if !isCurrentSession {
                Color.black
            } else if usesSessionDocumentPreview {
                if documentPreview.isLoading {
                    loadingView
                } else if let error = documentPreview.error {
                    errorView(message: error)
                } else if let data = documentPreview.data {
                    documentView(data: data)
                } else {
                    ProgressView("Opening document…").tint(ColorTheme.accent)
                }
            } else if isLoading {
                loadingView
            } else if let errorMessage = errorMessage {
                errorView(message: errorMessage)
            } else if let data = decryptedData {
                mediaContentView(data: data)
            } else if mediaItem.type == .video {
                videoContainerView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            String(localized: "gallery.delete.title"), isPresented: $showDeleteConfirmation
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                deleteMedia()
            }
        } message: {
            Text(String(localized: "media.delete.confirmation"))
        }
        .task(id: usesSessionDocumentPreview ? documentPreview.authorizationRevision : nil) {
            await loadAndDecryptMedia()
        }
        .fullScreenCover(isPresented: $showFullScreenVideoPlayer) {
            if isCurrentSession {
                VideoPlayerView(video: sourceItem, sessionID: authViewModel.librarySessionID)
                    .environmentObject(authViewModel)
            }
        }
        .safeAreaInset(edge: .top) {
            if isCurrentSession { topTitleBar }
        }
        .safeAreaInset(edge: .bottom) {
            if isCurrentSession, usesSessionDocumentPreview {
                Button("Export document") { shareMedia() }.buttonStyle(WagLockPrimaryButtonStyle())
                    .padding(24).background(ColorTheme.primaryBackground)
            }
        }
        .onDisappear {
            clearSensitiveMedia()
            documentPreview.clear()
            if !showShareSheet, let exportJobID { vaultServices.exports.cancelExport(exportJobID) }
        }
        .onChange(of: vaultServices.isActive) { _, active in if !active { clearSensitiveMedia() } }
        .onChange(of: exportScenePhase) { _, phase in
            if phase == .background {
                clearSensitiveMedia()
                documentPreview.clear()
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
        .alert(String(localized: "filePreview.alert.title"), isPresented: $showAlert) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            if let error = exportError {
                Text(error)
            }
        }
        .loadingOverlay(
            isShowing: isExporting,
            message: String(localized: "filePreview.exporting")
        )
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)

            Text(String(localized: "media.decrypting"))
                .foregroundColor(ColorTheme.primaryText)
                .font(.subheadline)
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text(String(localized: "media.loadFailed"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(ColorTheme.primaryText)

            Text(message)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Retry button
            Button {
                retryLoad()
            } label: {
                Label(String(localized: "common.retry"), systemImage: "arrow.clockwise")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.2))
                    .foregroundColor(ColorTheme.primaryText)
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - Media Content View

    @ViewBuilder
    private func mediaContentView(data: Data) -> some View {
        VStack(spacing: 0) {
            // Media content
            mediaContent(data: data)

            // Info bar
            mediaInfoBar
        }
    }

    private var videoContainerView: some View {
        VStack(spacing: 0) {
            videoView()
            mediaInfoBar
        }
    }

    @ViewBuilder
    private func mediaContent(data: Data) -> some View {
        switch mediaItem.type {
        case .photo:
            // The photo was already downsampled and decoded in the background into decryptedImage, so the main thread never decodes the full-resolution image
            if let image = decryptedImage {
                photoView(image: image)
            }
        case .video:
            videoView()
        case .audio, .document:
            documentView(data: data)
        }
    }

    // MARK: - Photo View

    private func photoView(image: UIImage) -> some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(imageScale)
                .offset(imageOffset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            imageScale = value
                        }
                        .onEnded { _ in
                            withAnimation(.spring()) {
                                if imageScale < 1 {
                                    imageScale = 1
                                    imageOffset = .zero
                                } else if imageScale > 3 {
                                    imageScale = 3
                                }
                            }
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if imageScale > 1 {
                                imageOffset = value.translation
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring()) {
                                if imageScale <= 1 {
                                    imageOffset = .zero
                                }
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if imageScale == 1 {
                            imageScale = 2
                        } else {
                            imageScale = 1
                            imageOffset = .zero
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - Video View

    private func videoView() -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let player = videoPlayer {
                    VideoPlayer(player: player)
                        .onDisappear {
                            cleanupVideoPlayer()
                        }
                } else {
                    ProgressView()
                        .tint(ColorTheme.accent)
                        .onAppear {
                            if let url = videoTempURL {
                                setupVideoPlayer(url: url)
                            }
                        }
                }
            }

            // Full-screen playback button
            Button {
                // Pause the inline player and open the full-screen player
                videoPlayer?.pause()
                showFullScreenVideoPlayer = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                    Text(String(localized: "media.fullscreen"))
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .foregroundColor(ColorTheme.primaryText)
                .cornerRadius(12)
                .padding()
                .disabled(videoPlayer == nil)
            }
        }
    }

    // MARK: - Document View

    private func documentView(data: Data) -> some View {
        let ext = mediaItem.fileExtension.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return Group {
            switch ext {
            case "pdf":
                pdfDocumentView(data: data)
            case "md":
                markdownDocumentView(data: data)
            case "txt", "json", "csv", "log":
                textDocumentView(data: data)
            default:
                genericDocumentQuickLookView(data: data)
            }
        }
    }

    // MARK: - PDF Document View

    private func pdfDocumentView(data: Data) -> some View {
        // The PDF reader is full-screen, with no extra info bar
        PDFReaderView(data: data, onShare: shareMedia)
            .ignoresSafeArea()
    }

    // MARK: - Markdown Document View

    private func markdownDocumentView(data: Data) -> some View {
        let text = String(data: data, encoding: .utf8) ?? String(localized: "media.text.parseError")
        let attributed: AttributedString? = try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))

        return ScrollView {
            if let attributed = attributed {
                Text(attributed)
                    .foregroundColor(ColorTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(ColorTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .background(ColorTheme.primaryBackground.ignoresSafeArea())
    }

    // MARK: - Text Document View

    private func textDocumentView(data: Data) -> some View {
        let text = String(data: data, encoding: .utf8) ?? String(localized: "media.text.parseError")

        return ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(ColorTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(ColorTheme.primaryBackground.ignoresSafeArea())
    }

    // MARK: - Generic Document View (QuickLook fallback)

    private func genericDocumentQuickLookView(data: Data) -> some View {
        ZStack {
            ColorTheme.primaryBackground.ignoresSafeArea()

            if let url = documentTempURL {
                QuickLookPreview(url: url)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(ColorTheme.accent)

                    Text(String(localized: "media.preparing"))
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .task {
            await prepareDocumentTempFile(data: data)
        }
        .onDisappear {
            cleanupDocumentTempFile()
        }
    }

    // MARK: - Media Info Bar

    private var mediaInfoBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Details
            HStack {
                Label(mediaItem.formattedFileSize, systemImage: "doc")

                if let dimensions = mediaItem.formattedDimensions {
                    Label(dimensions, systemImage: "rectangle")
                }

                if let duration = mediaItem.formattedDuration {
                    Label(duration, systemImage: "clock")
                }

                Spacer()
            }
            .font(.caption)
            .foregroundColor(ColorTheme.secondaryText)

            // Import date
            Text(mediaItem.formattedCreatedDate)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
        }
    }

    // MARK: - Private Methods

    /// Retry loading and decrypting the media (used after a load failure)
    private func retryLoad() {
        isLoading = true
        errorMessage = nil
        decryptedData = nil
        Task {
            await loadAndDecryptMedia()
        }
    }

    private var isCurrentSession: Bool {
        authViewModel.isAuthenticated && originatingSessionID == authViewModel.librarySessionID
    }

    private var usesSessionDocumentPreview: Bool {
        let ext = mediaItem.fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return mediaItem.type == .document && ["pdf", "txt", "md", "json", "csv", "log"].contains(ext)
    }

    /// Load common document formats through a revocable owner capability.
    private func loadAndDecryptMedia() async {
        guard isCurrentSession else { return }
        if usesSessionDocumentPreview {
            guard authViewModel.isAuthenticated, let password = getSessionPassword() else {
                documentPreview.clear()
                return
            }
            guard documentPreview.bind(to: vaultServices) else { return }
            documentPreview.load(path: mediaItem.encryptedPath, password: password,
                                 fileExtension: mediaItem.fileExtension, sessionID: authViewModel.librarySessionID)
            return
        }

        do {
            // Get the user's password (temporary approach)
            guard let password = getSessionPassword() else {
                errorMessage = String(localized: "media.error.noPassword")
                isLoading = false
                return
            }


            // Read the encrypted file

            // Check that the file exists (FileStorageService resolves relative paths)
            let fileExists = storageService.fileExists(path: mediaItem.encryptedPath)

            if !fileExists {
                throw NSError(
                    domain: "MediaDetailView", code: 404,
                    userInfo: [
                        NSLocalizedDescriptionKey: "The encrypted file is unavailable."
                    ])
            }

            if mediaItem.type == .video {
                let tempURL = try await videoLoader(storageService, mediaItem.encryptedPath, password, mediaItem.fileExtension)

                await MainActor.run {
                    guard isCurrentSession, vaultServices.isActive, !Task.isCancelled else {
                        try? FileManager.default.removeItem(at: tempURL)
                        return
                    }
                    self.isLoading = false
                    self.setupVideoPlayer(url: tempURL)
                }
                return
            }

            let data = try await storageService.loadDecryptedDataAsync(
                path: mediaItem.encryptedPath,
                password: password,
                preferredExtension: mediaItem.fileExtension
            )

            guard isCurrentSession, vaultServices.isActive, !Task.isCancelled else { return }

            // Photos are downsampled and decoded in the background so decoding 12MP+ images on the main thread doesn't stutter
            if mediaItem.type == .photo {
                let image = await vaultServices.thumbnails.image(
                    for: mediaItem.id.uuidString,
                    data: data,
                    maxPixelSize: AppConstants.previewImageMaxPixelSize
                )

                await MainActor.run {
                    guard isCurrentSession, vaultServices.isActive, !Task.isCancelled else { return }
                    guard let image = image else {
                        self.errorMessage = MediaLoaderError.invalidImageData.localizedDescription
                        self.isLoading = false
                        return
                    }
                    self.decryptedImage = image
                    self.decryptedData = data
                    self.isLoading = false
                }
                return
            }

            await MainActor.run {
                guard isCurrentSession, vaultServices.isActive, !Task.isCancelled else { return }
                self.decryptedData = data
                self.isLoading = false
            }

        } catch {
            await MainActor.run {
                guard isCurrentSession, vaultServices.isActive, !Task.isCancelled else { return }
                self.errorMessage = "Unable to open this file. Unlock and try again."
                self.isLoading = false
            }
        }
    }

    /// Share media
    private func shareMedia() {
        guard isCurrentSession, !isExporting else { return }
        guard let password = authViewModel.sessionPassword, !password.isEmpty else {
            exportError = String(localized: "filePreview.error.noPassword")
            showAlert = true
            return
        }

        isExporting = true
        exportError = nil

        let exportSessionID = authViewModel.librarySessionID
        exportJobID = vaultServices.exports.exportItems([sourceItem], password: password, sessionID: exportSessionID) { result in
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

    /// Delete media
    private func deleteMedia() {
        guard isCurrentSession else { return }
        Task {
            do {
                // For videos, release the player resources first
                if mediaItem.type == .video {
                    await MainActor.run {
                        cleanupVideoPlayer()
                    }
                    // Wait for resources to be released
                    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
                }

                // Commit the database deletion first and delete files only after it succeeds,
                // so a failed save never leaves records pointing at deleted files
                guard isCurrentSession, !Task.isCancelled else { return }
                let encryptedPath = mediaItem.encryptedPath
                modelContext.delete(sourceItem)
                try LibraryWriteCoordinator.save(modelContext)

                do {
                    try storageService.deleteFile(path: encryptedPath)
                } catch {
                }

                // Go back to the previous screen
                await MainActor.run {
                    dismiss()
                }


            } catch {
                await MainActor.run {
                    guard isCurrentSession else { return }
                    modelContext.rollback()
                    errorMessage = String(format: String(localized: "media.error.deleteFailed"), error.localizedDescription)
                }
            }
        }
    }

    /// Set up the video player
    private func setupVideoPlayer(url: URL) {
        videoTempURL = url
        videoPlayer = AVPlayer(url: url)
        // Activate the audio session so the inline preview has sound even with the silent switch on
        AVAudioSession.activateForVideoPlayback()
    }

    private func clearSensitiveMedia() {
        decryptedData = nil
        decryptedImage = nil
        cleanupVideoPlayer()
        cleanupDocumentTempFile()
    }

    /// Release video player resources
    private func cleanupVideoPlayer() {
        // Stop playback
        videoPlayer?.pause()
        videoPlayer?.replaceCurrentItem(with: nil)
        videoPlayer = nil
        AVAudioSession.deactivateAfterVideoPlayback()

        // Delete the temporary file
        if let tempURL = videoTempURL {
            try? FileManager.default.removeItem(at: tempURL)
            videoTempURL = nil
        }
    }

    /// Delete the document temporary file
    private func cleanupDocumentTempFile() {
        if let tempURL = documentTempURL {
            try? FileManager.default.removeItem(at: tempURL)
            documentTempURL = nil
        }
    }

    /// Save a temporary file (for document preview)
    private func prepareDocumentTempFile(data: Data) async {
        // Avoid creating it twice
        guard isCurrentSession, vaultServices.isActive, !Task.isCancelled else { return }
        if documentTempURL != nil {
            return
        }

        do {
            let tempURL = try ProtectedTemporaryFiles.fileURL(preferredExtension: mediaItem.fileExtension)
            // Plaintext document temporary files use the strongest file protection so they can't be read while the device is locked
            try data.write(to: tempURL, options: [.atomic, .completeFileProtection])
            await MainActor.run {
                guard isCurrentSession, vaultServices.isActive, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }
                documentTempURL = tempURL
            }
        } catch {
        }
    }

    /// Get the session password
    private func getSessionPassword() -> String? {
        return authViewModel.sessionPassword
    }

    // MARK: - Top Title Bar

    private var topTitleBar: some View {
        HStack(spacing: 12) {
            Button("Done") { dismiss() }
            Spacer()
            Text(mediaItem.fullFileName).font(.headline).foregroundStyle(ColorTheme.primaryText).lineLimit(1)
            Spacer()
            Button { shareMedia() } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Export file")
            Button(role: .destructive) { showDeleteConfirmation = true } label: { Image(systemName: "trash") }
                .accessibilityLabel("Delete file")
        }.padding(16).background(ColorTheme.primaryBackground)
    }
}

// MARK: - QuickLook Preview

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
