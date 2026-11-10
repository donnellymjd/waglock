import AVKit
import SwiftUI

struct VideoPlayerView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext
    private let sourceVideo: MediaItem
    let video: MediaPreviewSnapshot
    private let originatingSessionID: UUID?

    init(video: MediaItem, sessionID: UUID? = nil) {
        sourceVideo = video
        self.video = MediaPreviewSnapshot(video)
        originatingSessionID = sessionID
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @State private var player: AVPlayer?
    @State private var playbackObservation: NSKeyValueObservation?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadGeneration = UUID()
    @State private var tempVideoURL: URL?
    @State private var audioSessionActive = false
    @State private var errorMessage: String?
    @State private var showInfo = false
    @State private var showDeleteConfirmation = false
    @State private var showDeleteErrorAlert = false
    @State private var deleteErrorMessage: String?
    @State private var exportJobID: UUID?
    @State private var shareGeneration = UUID()
    @State private var isSharing = false
    @State private var exportedURLs: [URL] = []
    @State private var showShareSheet = false
    @State private var shareError: String?
    @State private var showShareAlert = false
    @State private var showMoveToAlbum = false

    private var topBar: some View {
        HStack(spacing: 12) {
            WagLockRoundButton(symbol: "xmark", label: "Close", onMedia: true) { dismiss() }
                .accessibilityIdentifier("video.close")
            Spacer()
            VStack(spacing: 0) {
                Text(video.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.wlBodyStrong).foregroundStyle(.white)
                Text((["Video"] + [video.formattedDuration, video.formattedFileSize].compactMap { $0 }).joined(separator: " · "))
                    .font(.wlMeta).foregroundStyle(Color.white.opacity(0.75))
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Menu {
                Button("Info", systemImage: "info.circle") { showInfo = true }
                Button("Move to album", systemImage: "rectangle.stack.badge.plus") { showMoveToAlbum = true }
                Button("Export", systemImage: "square.and.arrow.up") { shareVideo() }
                Button("Delete video", systemImage: "trash", role: .destructive) { showDeleteConfirmation = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Color.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("Video actions")
            .disabled(!isCurrentSession)
        }
        .padding(.horizontal, 22).padding(.top, 8)
    }

    private var actions: [WagLockAction] {
        [
            WagLockAction(id: "video.info", symbol: "info.circle", title: "Info", enabled: isCurrentSession) { showInfo = true },
            WagLockAction(id: "video.album", symbol: "rectangle.stack.badge.plus", title: "Album", enabled: isCurrentSession) { showMoveToAlbum = true },
            WagLockAction(id: "video.share", symbol: "square.and.arrow.up", title: "Export", enabled: isCurrentSession && !isSharing) { shareVideo() },
            WagLockAction(id: "video.delete", symbol: "trash", title: "Delete", destructive: true, enabled: isCurrentSession) { showDeleteConfirmation = true },
        ]
    }

    private var isCurrentSession: Bool {
        authViewModel.isAuthenticated
            && (originatingSessionID == nil || authViewModel.librarySessionID == originatingSessionID)
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack(alignment: .top) {
                Graphite.media.ignoresSafeArea()
                VStack(spacing: 8) {
                    if !landscape { topBar }
                    Group {
                        if isCurrentSession {
                            if let player {
                                NativeVideoPlayer(player: player)
                            } else if let errorMessage {
                                VStack(spacing: 14) {
                                    WagLockNote(kind: .error, title: "Could not open this video", text: errorMessage)
                                    Button("Retry") { setupPlayer() }.buttonStyle(WagLockSecondaryButtonStyle())
                                }.padding(.horizontal, 22)
                            } else {
                                ProgressView("Opening video…").tint(.white).foregroundStyle(.white).font(.wlBody)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !landscape {
                        WagLockActionBar(actions: actions).padding(.horizontal, 22).padding(.bottom, 8)
                    }
                }
                .ignoresSafeArea(edges: landscape ? .all : [])
                if landscape { topBar.padding(.horizontal, 40) }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(String(localized: "video.delete.confirmTitle"), isPresented: $showDeleteConfirmation) {
            Button(String(localized: "common.delete"), role: .destructive) { deleteVideo() }
        } message: { Text(String(localized: "video.delete.confirmMessage")) }
        .onAppear { setupPlayer() }
        .onDisappear {
            stopPlayback()
            if !showShareSheet { cancelSharing() }
        }
        .onChange(of: isCurrentSession) { _, current in
            if !current {
                stopPlayback(); cancelSharing(); showInfo = false; showDeleteConfirmation = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                stopPlayback(); cancelSharing(); showInfo = false; showMoveToAlbum = false
            case .inactive:
                player?.pause()
            case .active:
                if isCurrentSession, player == nil, errorMessage == nil { setupPlayer() }
            @unknown default: break
            }
        }
        .sheet(isPresented: $showInfo) {
            PhotoInfoSheet(snapshot: video, subtitle: "Video") { showInfo = false }
        }
        .sheet(isPresented: $showMoveToAlbum) {
            if isCurrentSession {
                MoveToAlbumSheet(items: [sourceVideo]) { stopPlayback(); dismiss() }
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { exportedURLs.removeAll() }) {
            ShareSheet(items: exportedURLs)
        }
        .alert(String(localized: "export.failed"), isPresented: $showShareAlert) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { Text(shareError ?? String(localized: "common.unknownError")) }
        .alert(String(localized: "common.error"), isPresented: $showDeleteErrorAlert) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { Text(deleteErrorMessage ?? String(localized: "common.unknownError")) }
        .loadingOverlay(isShowing: isSharing, message: String(localized: "video.export.inProgress"))
    }

    private func setupPlayer() {
        guard isCurrentSession, scenePhase == .active, let password = authViewModel.sessionPassword else { return }
        stopPlayback()
        errorMessage = nil
        let generation = loadGeneration
        AVAudioSession.activateForVideoPlayback()
        audioSessionActive = true
        loadTask = Task { @MainActor in
            do {
                let url = try await vaultServices.storage.createDecryptedTempFileAsync(
                    path: video.encryptedPath, password: password, preferredExtension: video.fileExtension)
                guard !Task.isCancelled, loadGeneration == generation, isCurrentSession, scenePhase == .active else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                tempVideoURL = url
                let loaded = AVPlayer(url: url)
                loaded.allowsExternalPlayback = false
                player = loaded
                playbackObservation = loaded.observe(\.timeControlStatus, options: [.initial, .new]) { observed, _ in
                    DispatchQueue.main.async {
                        guard player === observed, loadGeneration == generation, isCurrentSession else { return }
                        UIApplication.shared.isIdleTimerDisabled = observed.timeControlStatus == .playing
                    }
                }
                loaded.play()
            } catch {
                guard !Task.isCancelled, loadGeneration == generation, isCurrentSession, scenePhase == .active else { return }
                stopPlayback()
                errorMessage = String(format: String(localized: "video.error.decryptFailed"), error.localizedDescription)
            }
        }
    }

    private func stopPlayback() {
        loadGeneration = UUID()
        loadTask?.cancel(); loadTask = nil
        playbackObservation?.invalidate(); playbackObservation = nil
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        if let url = tempVideoURL { try? FileManager.default.removeItem(at: url); tempVideoURL = nil }
        if audioSessionActive { AVAudioSession.deactivateAfterVideoPlayback(); audioSessionActive = false }
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func shareVideo() {
        guard isCurrentSession, scenePhase == .active, !isSharing,
              let password = authViewModel.sessionPassword, !password.isEmpty else { return }
        player?.pause()
        isSharing = true; shareError = nil
        shareGeneration = UUID()
        let generation = shareGeneration
        let sessionID = authViewModel.librarySessionID
        exportJobID = vaultServices.exports.exportItems([sourceVideo], password: password, sessionID: sessionID) { result in
            guard generation == shareGeneration, isCurrentSession,
                  authViewModel.librarySessionID == sessionID else { return }
            guard scenePhase == .active else { cancelSharing(); return }
            switch result {
            case .success(let urls): exportedURLs = urls; showShareSheet = true
            case .failure(let error): shareError = error.localizedDescription; showShareAlert = true
            }
            isSharing = false
        }
    }

    private func cancelSharing() {
        shareGeneration = UUID()
        if let exportJobID { vaultServices.exports.cancelExport(exportJobID) }
        exportJobID = nil; isSharing = false; showShareSheet = false; exportedURLs.removeAll()
    }

    private func deleteVideo() {
        guard isCurrentSession else { return }
        let path = video.encryptedPath
        modelContext.delete(sourceVideo)
        do {
            try LibraryWriteCoordinator.save(modelContext)
        } catch {
            modelContext.rollback()
            deleteErrorMessage = String(format: String(localized: "gallery.error.deleteFailed"), error.localizedDescription)
            showDeleteErrorAlert = true
            return
        }
        stopPlayback()
        try? vaultServices.storage.deleteFile(path: path)
        dismiss()
    }
}

/// Apple's controls own scrubbing, transport, volume and playback speed.
/// Playback remains within the authenticated app rather than Picture in Picture.
struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.updatesNowPlayingInfoCenter = false
        controller.view.backgroundColor = .black
        controller.view.accessibilityIdentifier = "video.player"
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
