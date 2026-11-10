import Photos
import PhotosUI
import SwiftUI

/// Plays a Live Photo from decrypted temporary copies of its still and motion. The copies
/// live only while playback is on screen and are removed on finish, lock or disappearance.
struct LivePhotoPlaybackView: View {
    let stillPath: String
    let stillExtension: String
    let motionPath: String
    let motionExtension: String
    let sessionID: UUID?
    let finished: () -> Void

    @EnvironmentObject private var services: VaultSessionContext
    @EnvironmentObject private var auth: AuthenticationViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var livePhoto: PHLivePhoto?
    @State private var copies: [URL] = []
    @State private var failed = false

    private var isCurrentSession: Bool {
        auth.isAuthenticated && (sessionID == nil || auth.librarySessionID == sessionID) && services.isActive
    }

    var body: some View {
        ZStack {
            Graphite.media.ignoresSafeArea()
            if let livePhoto {
                LivePhotoUIView(livePhoto: livePhoto, finished: finish)
                    .ignoresSafeArea()
                    .accessibilityLabel("Live Photo playing")
            } else if failed {
                WagLockNote(kind: .error, text: "This Live Photo couldn’t be played. The photo is still here.")
                    .padding(.horizontal, 22)
                    .onTapGesture(perform: finish)
            } else {
                ProgressView().tint(.white)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .task { await load() }
        .onDisappear(perform: cleanup)
        .onChange(of: scenePhase) { _, phase in if phase == .background { finish() } }
        .onChange(of: isCurrentSession) { _, current in if !current { finish() } }
    }

    private func load() async {
        guard isCurrentSession, let password = auth.sessionPassword else { failed = true; return }
        do {
            // Recheck the session after every await and discard late plaintext.
            let still = try await services.storage.createDecryptedTempFileAsync(path: stillPath, password: password, preferredExtension: stillExtension)
            copies.append(still)
            guard isCurrentSession, !Task.isCancelled else { cleanup(); return }
            let motion = try await services.storage.createDecryptedTempFileAsync(path: motionPath, password: password, preferredExtension: motionExtension)
            copies.append(motion)
            guard isCurrentSession, !Task.isCancelled else { cleanup(); return }
            let photo = await Self.request(still: still, motion: motion)
            guard isCurrentSession, !Task.isCancelled else { cleanup(); return }
            livePhoto = photo
            if photo == nil { failed = true }
        } catch {
            failed = true
        }
    }

    /// Waits for the full-quality result; iOS may deliver a degraded one first.
    static func request(still: URL, motion: URL) async -> PHLivePhoto? {
        await withCheckedContinuation { continuation in
            var resumed = false
            PHLivePhoto.request(withResourceFileURLs: [still, motion], placeholderImage: nil,
                                targetSize: .zero, contentMode: .aspectFit) { photo, info in
                guard !resumed else { return }
                let degraded = (info[PHLivePhotoInfoIsDegradedKey] as? Bool) ?? false
                let cancelled = (info[PHLivePhotoInfoCancelledKey] as? Bool) ?? false
                if info[PHLivePhotoInfoErrorKey] != nil || cancelled { resumed = true; continuation.resume(returning: nil); return }
                if !degraded { resumed = true; continuation.resume(returning: photo) }
            }
        }
    }

    private func finish() {
        cleanup()
        finished()
    }

    private func cleanup() {
        livePhoto = nil
        for url in copies { try? FileManager.default.removeItem(at: url) }
        copies = []
    }
}

struct LivePhotoUIView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    /// False shows the still with touch-and-hold playback; true plays once on appear.
    var autoplay = true
    let finished: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finished) }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.livePhoto = livePhoto
        if autoplay { view.startPlayback(with: .full) }
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        if view.livePhoto !== livePhoto { view.livePhoto = livePhoto }
    }

    static func dismantleUIView(_ view: PHLivePhotoView, coordinator: Coordinator) {
        view.stopPlayback()
        view.livePhoto = nil
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        let finished: () -> Void
        init(_ finished: @escaping () -> Void) { self.finished = finished }
        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            finished()
        }
    }
}

/// The LIVE badge on grid tiles and the viewer.
struct LivePhotoBadge: View {
    var body: some View {
        Label("LIVE", systemImage: "livephoto")
            .font(WagLockFonts.poppins(10, .semibold, relativeTo: .caption2)).tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.black.opacity(0.5), in: Capsule())
            .accessibilityLabel("Live Photo")
    }
}
