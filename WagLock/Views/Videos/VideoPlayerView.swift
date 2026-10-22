//
//  VideoPlayerView.swift
//  WagLock
//
//  视频播放器视图
//  支持全屏播放、控制条、手势操作
//

import AVFoundation
import SwiftUI

struct VideoPlayerView: View {

    // MARK: - Properties

    private let sourceVideo: MediaItem
    let video: MediaPreviewSnapshot
    private let originatingSessionID: UUID?

    init(video: MediaItem, sessionID: UUID? = nil) {
        sourceVideo = video
        self.video = MediaPreviewSnapshot(video)
        originatingSessionID = sessionID
    }

    private var isCurrentSession: Bool {
        authViewModel.isAuthenticated && (originatingSessionID == nil || authViewModel.librarySessionID == originatingSessionID)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @State private var exportJobID: UUID?
    @Environment(\.scenePhase) private var exportScenePhase
    @State private var player: AVPlayer?
    @State private var showControls = true
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing: Bool = false
    @State private var playbackRate: Float = 1.0
    @State private var isMuted: Bool = false
    @State private var timeObserver: Any?
    @State private var errorMessage: String?
    @State private var tempVideoURL: URL?
    @State private var showDeleteConfirmation: Bool = false
    @State private var isDecrypting: Bool = false
    @State private var decryptMessage: String = String(localized: "video.loading")
    @State private var isSharing: Bool = false
    @State private var exportedURLs: [URL] = []
    @State private var showShareSheet = false
    @State private var shareError: String?
    @State private var showShareAlert = false
    @State private var showDeleteErrorAlert = false
    @State private var deleteErrorMessage: String?
    @State private var volume: Float = 1.0
    @State private var isBuffering = false
    @State private var wasPlayingBeforeInterruption = false
    @State private var seekFeedbackIcon: String?
    @State private var seekFeedbackText: String?
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var endObserver: NSObjectProtocol?
    @State private var interruptionObserver: NSObjectProtocol?
    @State private var statusObservation: NSKeyValueObservation?
    @State private var loadTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isCurrentSession {
                        Text("Video · \(video.formattedDuration ?? "Original quality")")
                            .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                        Group {
                            if let player {
                                PlayerContainerView(player: player)
                                    .onAppear { player.play(); isPlaying = true }
                            } else if let errorMessage {
                                VStack(spacing: 12) {
                                    Text("Could not open this video").font(.headline)
                                    Text(errorMessage).font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                                    Button("Retry") { retryLoad() }
                                }.padding(24)
                            } else { ProgressView("Opening video…") }
                        }.frame(maxWidth: .infinity).frame(height: 240)
                            .background(ColorTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: 16))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        if player != nil { bottomBar }
                        WagLockNavigationRow(symbol: "info.circle", title: video.fullFileName,
                            detail: [video.formattedDimensions, video.formattedFileSize].compactMap { $0 }.joined(separator: " · "))
                        Button("Export video") { shareVideo() }.buttonStyle(WagLockPrimaryButtonStyle()).disabled(isSharing)
                            .accessibilityIdentifier("video.share")
                        Button("Delete video", role: .destructive) { showDeleteConfirmation = true }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }.padding(24)
            }.background(ColorTheme.primaryBackground.ignoresSafeArea()).navigationTitle(video.fileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("video.close") } }
        }
        .confirmationDialog(
            String(localized: "video.delete.confirmTitle"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                deleteVideo()
            }
        } message: {
            Text(String(localized: "video.delete.confirmMessage"))
        }
        .onAppear {
            // 激活音频会话，保证静音开关打开时视频仍有声音
            AVAudioSession.activateForVideoPlayback()
            setupPlayer()
            registerInterruptionObserver()
        }
        .onDisappear {
            loadTask?.cancel()
            removePlaybackObservers()
            if let player = player, let observer = timeObserver {
                player.removeTimeObserver(observer)
                timeObserver = nil
            }
            player?.pause()
            cleanupTempFile()
            AVAudioSession.deactivateAfterVideoPlayback()
            UIApplication.shared.isIdleTimerDisabled = false
            controlsHideTask?.cancel()
            feedbackTask?.cancel()
        }
        .onChange(of: isPlaying) { _, playing in
            // 播放时禁用自动锁屏，暂停时恢复
            UIApplication.shared.isIdleTimerDisabled = playing
            if playing {
                scheduleControlsAutoHide()
            } else {
                controlsHideTask?.cancel()
                withAnimation {
                    showControls = true
                }
            }
        }
        .onChange(of: showControls) { _, visible in
            if visible {
                scheduleControlsAutoHide()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // `.playback` 类别允许后台出声；退到后台必须暂停，避免声音在后台继续播放
            if newPhase == .background, isPlaying {
                player?.pause()
                isPlaying = false
            }
        }
        .onDisappear {
            if !showShareSheet, let exportJobID { ExportService.shared.cancelExport(exportJobID) }
        }
        .onChange(of: exportScenePhase) { _, phase in
            if phase == .background { isSharing = false; showShareSheet = false }
        }
        .sheet(
            isPresented: $showShareSheet,
            onDismiss: {
                exportedURLs.removeAll()
            }
        ) {
            ShareSheet(items: exportedURLs)
        }
        .alert(String(localized: "export.failed"), isPresented: $showShareAlert) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(shareError ?? String(localized: "common.unknownError"))
        }
        .alert(String(localized: "common.error"), isPresented: $showDeleteErrorAlert) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? String(localized: "common.unknownError"))
        }
        .loadingOverlay(
            isShowing: isDecrypting || isSharing,
            message: isDecrypting ? decryptMessage : String(localized: "video.export.inProgress")
        )
    }

    // MARK: - Methods

    private func setupPlayer() {
        guard isCurrentSession, let password = authViewModel.sessionPassword else {
            errorMessage = String(localized: "video.error.passwordMissing")
            return
        }

        decryptMessage = String(localized: "video.decrypt.status")
        isDecrypting = true

        // 异步解密并创建播放器（持有 Task 引用，视图消失时可取消）
        loadTask?.cancel()
        loadTask = Task {
            do {
                let storageService = FileStorageService.shared
                let tempURL = try await storageService.createDecryptedTempFileAsync(
                    path: video.encryptedPath,
                    password: password,
                    preferredExtension: video.fileExtension
                )

                // 视图已消失：立即清理解密出的临时文件，避免明文残留
                if Task.isCancelled || !isCurrentSession {
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }

                // 创建播放器（不立即播放，等视图出现后再播放）
                await MainActor.run {
                    self.tempVideoURL = tempURL
                    let playerItem = AVPlayerItem(url: tempURL)
                    let avPlayer = AVPlayer(playerItem: playerItem)

                    self.player = avPlayer
                    self.isPlaying = false

                    // 播放结束后回到开头并显示重播状态
                    self.endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: playerItem,
                        queue: .main
                    ) { _ in
                        self.isPlaying = false
                        self.currentTime = 0
                        self.player?.seek(to: .zero)
                    }

                    // 监听缓冲状态，卡顿时显示加载提示
                    self.statusObservation = avPlayer.observe(
                        \.timeControlStatus, options: [.initial, .new]
                    ) { observedPlayer, _ in
                        let waiting = observedPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
                        DispatchQueue.main.async {
                            self.isBuffering = waiting
                        }
                    }

                    // 同步总时长（优先使用播放器的时长，退回到元数据）
                    let assetDuration = playerItem.asset.duration
                    let totalSeconds = CMTimeGetSeconds(assetDuration)
                    if totalSeconds.isFinite && totalSeconds > 0 {
                        self.duration = totalSeconds
                    } else if let metaDuration = video.duration {
                        self.duration = metaDuration
                    }

                    // 添加周期性时间观察者，更新当前播放时间
                    addTimeObserver(to: avPlayer)
                }

                await MainActor.run {
                    isDecrypting = false
                }

            } catch {
                guard isCurrentSession, !Task.isCancelled else { return }
                await MainActor.run {
                    errorMessage = String(
                        format: String(localized: "video.error.decryptFailed"),
                        error.localizedDescription)
                    isDecrypting = false
                }
            }
        }
    }

    private func shareVideo() {
        guard isCurrentSession, !isSharing else { return }
        guard let password = authViewModel.sessionPassword, !password.isEmpty else {
            shareError = String(localized: "video.error.passwordMissing")
            showShareAlert = true
            return
        }

        isSharing = true
        shareError = nil

        let exportSessionID = authViewModel.librarySessionID
        exportJobID = ExportService.shared.exportItems([sourceVideo], password: password, sessionID: exportSessionID) { result in
            guard authViewModel.isAuthenticated, authViewModel.librarySessionID == exportSessionID else { return }
            switch result {
            case .success(let urls):
                exportedURLs = urls
                showShareSheet = true
            case .failure(let error):
                shareError = error.localizedDescription
                showShareAlert = true
            }

            isSharing = false
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 18) {
            HStack {
                Button("−15 sec") { seek(by: -15) }
                Spacer()
                Button(isPlaying ? "Pause" : "Play") { togglePlayPause() }
                Spacer()
                Button("+15 sec") { seek(by: 15) }
            }.buttonStyle(.bordered).padding(3)
                .background(ColorTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text("\(formatTime(currentTime)) / \(formatTime(duration))").font(.body.weight(.semibold).monospacedDigit())
                Text(isPlaying ? "Playing on this device" : "Paused").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                Slider(value: Binding(get: { currentTime }, set: {
                    currentTime = $0
                    player?.seek(to: CMTime(seconds: $0, preferredTimescale: 600))
                }), in: 0...max(duration, 1)).tint(ColorTheme.accent).accessibilityLabel("Playback progress")
                HStack {
                    Menu("Speed: \(String(format: "%g", playbackRate))×") {
                        ForEach([Float(0.5), 1, 1.5, 2], id: \.self) { rate in
                            Button("\(String(format: "%g", rate))×") { playbackRate = rate; if isPlaying { player?.rate = rate } }
                        }
                    }
                    Spacer()
                    Button { toggleMute() } label: { Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.2") }
                        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                }
                Slider(value: $volume, in: 0...1).onChange(of: volume) { _, value in player?.volume = value }
                    .accessibilityLabel("Volume").tint(ColorTheme.accent)
            }.padding(16).background(ColorTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func cleanupTempFile() {
        guard let tempURL = tempVideoURL else { return }

        try? FileManager.default.removeItem(at: tempURL)
        tempVideoURL = nil
    }

    // MARK: - Playback Helpers

    private func togglePlayPause() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        }
    }

    private func seek(by offset: Double) {
        guard let player = player else { return }
        let newTime = max(0, min(currentTime + offset, duration))
        let time = CMTime(seconds: newTime, preferredTimescale: 600)
        player.seek(to: time)
        currentTime = newTime
    }

    private func addTimeObserver(to player: AVPlayer) {
        // 避免重复添加
        if timeObserver != nil { return }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { time in
            guard !isScrubbing else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite {
                currentTime = seconds
            }
        }
    }

    private func speedButton(title: String, rate: Float) -> some View {
        Button {
            playbackRate = rate
            if isPlaying, let player = player {
                player.rate = playbackRate
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(rate == playbackRate ? .bold : .regular)
                // 固定宽高，保证所有倍速按钮大小一致
                .frame(width: 40, height: 26)
                .background(
                    Capsule().fill(
                        rate == playbackRate
                            ? Color.white.opacity(0.9)
                            : Color.white.opacity(0.2)
                    )
                )
                .foregroundColor(rate == playbackRate ? .black : .white)
        }
    }

    private func toggleMute() {
        guard let player = player else { return }
        isMuted.toggle()
        // 取消静音时如果音量为 0，恢复到可听见的音量
        if !isMuted && volume <= 0.01 {
            volume = 0.5
            player.volume = 0.5
        }
        player.isMuted = isMuted
    }

    // MARK: - Playback Observers

    /// 注册音频中断监听（来电、闹钟等），中断时暂停、结束后恢复
    private func registerInterruptionObserver() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let info = notification.userInfo,
                let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: rawType)
            else { return }

            if type == .began {
                wasPlayingBeforeInterruption = isPlaying
                player?.pause()
                isPlaying = false
            } else if type == .ended, wasPlayingBeforeInterruption {
                wasPlayingBeforeInterruption = false
                // 仅当系统明确允许恢复时才自动继续播放
                let rawOptions = (info[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                guard options.contains(.shouldResume) else { return }
                player?.play()
                player?.rate = playbackRate
                isPlaying = true
            }
        }
    }

    /// 移除与播放器相关的通知观察者和 KVO
    private func removePlaybackObservers() {
        statusObservation?.invalidate()
        statusObservation = nil

        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    // MARK: - Controls Auto-Hide

    /// 播放中无操作一段时间后自动隐藏控制条
    private func scheduleControlsAutoHide() {
        controlsHideTask?.cancel()
        guard isPlaying, !isScrubbing else { return }
        controlsHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                showControls = false
            }
        }
    }

    /// 显示双击快进/快退的反馈提示，短暂停留后自动消失
    private func showSeekFeedback(backward: Bool) {
        seekFeedbackIcon = backward ? "gobackward.10" : "goforward.10"
        seekFeedbackText = backward ? "-10s" : "+10s"
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                seekFeedbackIcon = nil
            }
        }
    }

    /// 音量图标：随静音状态和当前音量变化
    private var volumeIconName: String {
        if isMuted || volume <= 0.01 { return "speaker.slash.fill" }
        return volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }

    // MARK: - Delete Video

    private func deleteVideo() {
        guard isCurrentSession else { return }
        let storage = FileStorageService.shared
        let encryptedPath = video.encryptedPath

        // 先提交数据库删除，成功后再停播放器/删文件（与列表页保持一致），
        // 避免 save 失败时留下指向已删除文件的记录，也让播放器保持可用
        modelContext.delete(sourceVideo)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            deleteErrorMessage = String(
                format: String(localized: "gallery.error.deleteFailed"),
                error.localizedDescription)
            showDeleteErrorAlert = true
            return
        }

        // 停止播放并清理观察者
        if let player = player, let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()

        // 删除加密文件
        do {
            try storage.deleteFile(path: encryptedPath)
        } catch {
            // 记录已删除，文件删除失败只会残留无引用的加密文件
        }

        // 清理临时文件并退出播放器
        cleanupTempFile()
        dismiss()
    }

    /// 重新尝试加载视频（解密失败时使用）
    private func retryLoad() {
        cleanupTempFile()
        removePlaybackObservers()
        errorMessage = nil
        player = nil
        timeObserver = nil
        setupPlayer()
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Player Container View

/// 仅承载 AVPlayer 画面、不带任何系统控制条的无控件播放视图
struct PlayerContainerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }
}

final class PlayerUIView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.videoGravity = .resizeAspect; playerLayer.player = newValue }
    }
}

// MARK: - Preview

#Preview {
    let sampleVideo = MediaItem(
        fileName: "sample.mp4",
        fileExtension: "mp4",
        fileSize: 10_240_000,
        type: .video,
        encryptedPath: "/path/to/file"
    )

    VideoPlayerView(video: sampleVideo)
}
