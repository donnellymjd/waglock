import AVFoundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AudioView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthenticationViewModel
    @EnvironmentObject private var guest: GuestModeManager
    @Query(filter: #Predicate<MediaItem> {
        $0.typeRawValue == "audio" || $0.typeRawValue == "document"
    }, sort: \MediaItem.createdAt, order: .reverse)
    private var candidates: [MediaItem]

    struct ShareAudioItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    @EnvironmentObject private var audio: AudioSessionController
    private struct AudioSelection: Identifiable {
        let id = UUID()
        let source: MediaItem
        let snapshot: MediaPreviewSnapshot
        let sessionID: UUID?
        init(_ item: MediaItem, sessionID: UUID?) {
            source = item; snapshot = MediaPreviewSnapshot(item); self.sessionID = sessionID
        }
    }
    @State private var selectedAudio: AudioSelection?
    @State private var pendingAudioShare: AudioSelection?
    @State private var searchText = ""
    @State private var showImportView = false
    @State private var isSaving = false
    @State private var isSharing = false
    @State private var saveFailed = false
    @State private var shareRequestID: UUID?
    @State private var saveTask: Task<Void, Never>?
    @State private var shareTask: Task<Void, Never>?
    @State private var shareAudioItem: ShareAudioItem?
    @State private var renameItem: MediaItem?
    @State private var newName = ""
    @State private var deleteItem: MediaItem?
    @State private var confirmDiscard = false
    @State private var errorMessage: String?
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var items: [MediaItem] {
        guest.isOwnerMode ? candidates.filter { $0.type == .audio } : []
    }

    private var canAccess: Bool { auth.isAuthenticated && guest.isOwnerMode }
    private var busy: Bool { isSaving || isSharing || audio.isRequestingPermission }

    var body: some View {
        VStack(spacing: 12) {
            WagLockSearchField(title: "Search audio", text: $searchText).padding(.horizontal, 24)
            Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "audio.empty.title"), systemImage: "waveform")
                } description: {
                    Text(String(localized: "audio.empty.message"))
                }
            } else {
                List {
                    Section("AUDIO") {
                        ForEach(items.filter { searchText.isEmpty || $0.fileName.localizedCaseInsensitiveContains(searchText) }) { item in
                            audioRow(item).wagLockCardRow()
                        }
                    }
                    Section {
                        WagLockInfoCard(title: "Listen here", detail: "Playback stays inside WagLock. Exporting a file creates a copy outside the vault.")
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                }
                .wagLockList()
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(ColorTheme.primaryBackground)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if guest.isOwnerMode {
                    Button {
                        audio.stopPlayback()
                        showImportView = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .disabled(busy || audio.hasRecording)
                    .accessibilityIdentifier("audio.import")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if guest.isOwnerMode && !LibraryStoragePolicy.encryptedMetadata { recordingPanel }
        }
        .overlay {
            if isSaving || isSharing {
                VStack(spacing: 16) {
                    ProgressView(String(localized: isSharing ? "export.preparingShare" : "audio.saving"))
                    if isSharing {
                        Button(String(localized: "common.cancel")) { cancelSharing() }
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .sheet(item: $selectedAudio, onDismiss: {
            guard let pending = pendingAudioShare else { return }
            pendingAudioShare = nil
            if canAccess, auth.librarySessionID == pending.sessionID { shareAudio(pending.source) }
        }) { selection in
            AudioPlaybackSheet(item: selection.snapshot, audio: audio, onToggle: {
                guard canAccess, auth.librarySessionID == selection.sessionID,
                      !busy, !audio.hasRecording, let password = auth.sessionPassword else { return }
                audio.togglePlayback(item: selection.source, password: password)
            }, onExport: {
                guard canAccess, auth.librarySessionID == selection.sessionID else { return }
                pendingAudioShare = selection
                selectedAudio = nil
            })
        }
        .sheet(isPresented: $showImportView) {
            ImportButtonsView(onImportComplete: { items in
            })
            .environment(\.modelContext, modelContext)
            .environmentObject(auth)
        }
        .alert(String(localized: "audio.rename"), isPresented: Binding(
            get: { renameItem != nil }, set: { if !$0 { renameItem = nil } })
        ) {
            TextField(String(localized: "audio.name"), text: $newName)
            Button(String(localized: "common.save")) { rename() }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .alert(String(localized: "audio.delete.title"), isPresented: Binding(
            get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } }), presenting: deleteItem
        ) { item in
            Button(String(localized: "common.delete"), role: .destructive) { delete(item) }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: { _ in Text(String(localized: "audio.delete.message")) }
        .confirmationDialog(String(localized: "audio.discard.title"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(String(localized: "audio.discard"), role: .destructive) { audio.discardRecording() }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .alert(String(localized: "common.error"), isPresented: Binding(
            get: { errorMessage != nil || audio.errorMessage != nil },
            set: { if !$0 { errorMessage = nil; audio.errorMessage = nil } })
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {
                errorMessage = nil
                audio.errorMessage = nil
            }
        } message: { Text(errorMessage ?? audio.errorMessage ?? "") }
        .sheet(item: $shareAudioItem) { item in
            ShareSheet(items: [item.url])
                .onDisappear {
                    let parentDir = item.url.deletingLastPathComponent()
                    try? FileManager.default.removeItem(at: parentDir)
                }
        }
        .onReceive(timer) { _ in audio.tick() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue {
                audio.pauseForInterruption()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                audio.pauseForInterruption()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive {
                if !audio.isRecording { audio.pauseForInterruption() }
            }
            if phase == .background {
                if !audio.isRecording {
                    audio.stopPlayback()
                }
            }
            if phase == .active {
                audio.tick()
            }
        }
        .onChange(of: auth.isAuthenticated) { _, authenticated in
            if !authenticated { revokeAccess() }
        }
        .onChange(of: guest.isOwnerMode) { _, owner in
            if !owner { revokeAccess() }
        }
        .onDisappear {
            if !audio.hasRecording {
                leaveAudio()
            } else {
                audio.stopPlayback()
            }
        }
    }

    private func audioRow(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    guard canAccess, let password = auth.sessionPassword else { return }
                    audio.togglePlayback(item: item, password: password)
                } label: {
                    Group {
                        if audio.playingID == item.id && audio.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: audio.playingID == item.id && audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(ColorTheme.accent)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .disabled(busy || audio.hasRecording || (audio.playingID == item.id && audio.isLoading))
                .accessibilityLabel(String(localized: audio.playingID == item.id && audio.isPlaying ? "audio.pause" : "audio.play"))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.fileName).font(.headline).lineLimit(2)
                    Text("\(item.formattedDuration ?? "Audio") · \(item.fileExtension.uppercased()) · \(item.formattedFileSize)")
                        .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                }
                Spacer()
                Text(item.formattedDuration ?? item.formattedFileSize)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button {
                    shareAudio(item)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .disabled(busy || audio.hasRecording)
                .accessibilityLabel(String(localized: "common.share"))
            }
            if audio.playingID == item.id {
                if audio.isLoading {
                    ProgressView()
                } else {
                    Slider(value: Binding(get: { audio.playbackTime }, set: { audio.seek(to: $0) }),
                           in: 0...max(audio.playbackDuration, 0.1))
                        .tint(ColorTheme.accent)
                        .accessibilityLabel(String(localized: "audio.progress"))
                    HStack {
                        Text(formatTime(audio.playbackTime))
                        Spacer()
                        Text(formatTime(audio.playbackDuration))
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 0)
        .contentShape(Rectangle())
        .accessibilityIdentifier("audio.row")
        .onTapGesture { if canAccess, !busy { selectedAudio = AudioSelection(item, sessionID: auth.librarySessionID) } }
        .contextMenu {
            Button {
                shareAudio(item)
            } label: {
                Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
            }
            Button(String(localized: "audio.rename"), systemImage: "pencil") {
                newName = item.fileName
                renameItem = item
            }
            Button(String(localized: "common.delete"), systemImage: "trash", role: .destructive) { deleteItem = item }
        }
        .swipeActions(edge: .trailing) {
            if !audio.isPlaying && audio.playingID != item.id {
                Button(String(localized: "common.delete"), role: .destructive) { deleteItem = item }
                Button(String(localized: "audio.rename")) { newName = item.fileName; renameItem = item }
                    .tint(.blue)
            }
        }
        .disabled(busy)
    }

    private var recordingPanel: some View {
        VStack(spacing: 14) {
            if audio.hasRecording {
                HStack(spacing: 3) {
                    ForEach(audio.levels.indices, id: \.self) { index in
                        Capsule().fill(.red.opacity(audio.isRecording ? 1 : 0.4))
                            .frame(height: max(3, CGFloat(audio.levels[index]) * 48))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 48)
                .accessibilityHidden(true)
                Text(formatTime(audio.elapsed)).font(.largeTitle.monospacedDigit())
                Text(String(localized: saveFailed ? "audio.error.save" : (audio.isRecording ? "audio.recording" : "audio.paused")))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(String(localized: saveFailed ? "audio.discard" : "common.cancel")) { confirmDiscard = true }
                    Spacer()
                    if !saveFailed {
                        Button { audio.toggleRecording() } label: {
                            Label(String(localized: audio.isRecording ? "audio.pause" : "audio.resume"),
                                  systemImage: audio.isRecording ? "pause.fill" : "mic.fill")
                        }
                        .disabled(!audio.canResume)
                        Spacer()
                    }
                    Button(String(localized: saveFailed ? "common.retry" : "common.save")) { saveRecording() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("audio.save")
                }
            } else {
                Button {
                    guard canAccess, hasCapacity(for: 1) else { return }
                    saveFailed = false
                    audio.startRecording()
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().stroke(.red.opacity(0.3), lineWidth: 3).frame(width: 68, height: 68)
                            Circle().fill(.red).frame(width: 56, height: 56)
                            Image(systemName: "mic.fill").foregroundStyle(.white).font(.title2)
                        }
                        Text(String(localized: "audio.record")).font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("audio.record")
            }
            Text(String(localized: "audio.localOnly"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(.bar)
        .disabled(busy)
    }

    private func hasCapacity(for count: Int) -> Bool {
        count >= 0
    }

    private func persist(_ item: MediaItem) throws {
        guard canAccess, !Task.isCancelled else {
            try? vaultServices.storage.deleteFile(path: item.encryptedPath)
            throw CancellationError()
        }
        modelContext.insert(item)
        do {
            try LibraryWriteCoordinator.save(modelContext)
        } catch {
            modelContext.rollback()
            try? vaultServices.storage.deleteFile(path: item.encryptedPath)
            throw error
        }
    }

    private func saveRecording() {
        guard !isSaving, canAccess, let password = auth.sessionPassword, hasCapacity(for: 1),
            let url = audio.finishRecording()
        else { return }
        saveFailed = false
        isSaving = true
        // Allow a recording already in progress to finish encrypting when entering the background.
        let backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Save audio memo") {
            saveTask?.cancel()
        }
        saveTask = Task {
            defer {
                isSaving = false
                if backgroundID != .invalid { UIApplication.shared.endBackgroundTask(backgroundID) }
            }
            do {
                let item = try await AudioImportService.importFile(url: url, password: password, storage: vaultServices.storage)
                let formatter = DateFormatter()
                formatter.locale = AppConstants.presentationLocale
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
                item.fileName = String(localized: "audio.newRecording") + " " + formatter.string(from: Date())
                try persist(item)
                audio.discardRecording()
            } catch is CancellationError {
                audio.discardRecording()
            } catch {
                saveFailed = true
                errorMessage = String(localized: "audio.error.save")
                if !canAccess { audio.discardRecording() }
            }
        }
    }

    private func shareAudio(_ item: MediaItem) {
        guard canAccess, !busy, let password = auth.sessionPassword else { return }

        isSharing = true
        let requestID = UUID()
        shareRequestID = requestID
        let path = item.encryptedPath
        let fileExtension = item.fileExtension
        let name = item.fileName.hasSuffix(fileExtension) ? item.fileName : item.fullFileName
        shareTask = Task {
            let tempDir: URL
            do { tempDir = try ProtectedTemporaryFiles.createDirectory() }
            catch {
                isSharing = false
                errorMessage = "Unable to prepare this share. Try again."
                return
            }
            var presented = false
            defer {
                if !presented { try? FileManager.default.removeItem(at: tempDir) }
                if shareRequestID == requestID {
                    isSharing = false
                    shareRequestID = nil
                    shareTask = nil
                }
            }
            do {
                let decryptedURL = try await vaultServices.storage.createDecryptedTempFileAsync(
                    path: path, password: password, preferredExtension: fileExtension)
                defer { try? FileManager.default.removeItem(at: decryptedURL) }
                try Task.checkCancellation()
                guard canAccess, shareRequestID == requestID else { return }
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let sanitized = String(name.map { c -> Character in
                    c == "/" || c == "\\" || c == ":" || c.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) ? "_" : c
                })
                let safeName = sanitized.isEmpty || sanitized == "." || sanitized == ".." ? "audio" : sanitized
                let shareURL = tempDir.appendingPathComponent(safeName)
                try FileManager.default.moveItem(at: decryptedURL, to: shareURL)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: shareURL.path)

                shareAudioItem = ShareAudioItem(url: shareURL)
                presented = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, shareRequestID == requestID else { return }
                errorMessage = String(localized: "export.failed")
            }
        }
    }

    private func cancelSharing() {
        shareTask?.cancel()
        shareTask = nil
        shareRequestID = nil
        isSharing = false
    }

    private func leaveAudio() {
        audio.stopPlayback()
        if canAccess, audio.hasRecording { saveRecording() }
        else if !isSaving { audio.discardRecording() }
    }

    private func revokeAccess() {
        showImportView = false
        pendingAudioShare = nil
        selectedAudio = nil
        saveTask?.cancel()
        cancelSharing()
        shareAudioItem = nil
        audio.stopPlayback()
        if !isSaving { audio.discardRecording() }
    }

    private func rename() {
        guard canAccess, let item = renameItem else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200, !name.contains("/"), !name.contains("\\") else {
            errorMessage = String(localized: "audio.error.name")
            return
        }
        item.fileName = name
        item.touch()
        do { try LibraryWriteCoordinator.save(modelContext) }
        catch { modelContext.rollback(); errorMessage = String(localized: "audio.error.save") }
    }

    private func delete(_ item: MediaItem) {
        guard canAccess else { return }
        let path = item.encryptedPath
        let itemID = item.id
        modelContext.delete(item)
        do { try LibraryWriteCoordinator.save(modelContext) }
        catch {
            modelContext.rollback()
            errorMessage = String(localized: "audio.error.save")
            return
        }
        if audio.playingID == itemID { audio.stopPlayback() }
        do { try vaultServices.storage.deleteFile(path: path) }
        catch { errorMessage = String(localized: "audio.error.deleteFile") }
    }

    private func formatTime(_ time: Double) -> String {
        let seconds = time.isFinite ? Int(max(0, time)) : 0
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
