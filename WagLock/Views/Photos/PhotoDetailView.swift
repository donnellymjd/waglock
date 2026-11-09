//
//  PhotoDetailView.swift
//  WagLock
//
//  Photo detail preview view
//  Supports zoom, swipe navigation and gestures
//

import SwiftUI

struct PhotoDetailView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext

    // MARK: - Properties

    struct Entry: Identifiable {
        let source: MediaItem
        let snapshot: MediaPreviewSnapshot
        var id: UUID { snapshot.id }
        init(_ item: MediaItem) { source = item; snapshot = MediaPreviewSnapshot(item) }
    }
    private let originatingSessionID: UUID?

    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Local copy: remove an item from the array right after a successful delete so the dismiss animation never renders a deleted object
    @State private var exportJobID: UUID?
    @Environment(\.scenePhase) private var exportScenePhase
    @State private var photos: [Entry]
    @State private var currentIndex: Int
    @State private var showPhotoInfo = false
    @State private var showControls = true
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var isExporting = false
    @State private var exportedURLs: [URL] = []
    @State private var showShareSheet = false
    @State private var exportError: String?
    @State private var showExportError = false
    @State private var showMoveToAlbum = false

    // MARK: - Initialization

    init(photo: MediaItem, allPhotos: [MediaItem], sessionID: UUID? = nil) {
        self.originatingSessionID = sessionID
        _photos = State(initialValue: allPhotos.map(Entry.init))

        // Find the current image's index
        if let index = allPhotos.firstIndex(where: { $0.id == photo.id }) {
            _currentIndex = State(initialValue: index)
        } else {
            _currentIndex = State(initialValue: 0)
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                Graphite.media.ignoresSafeArea()
                if isCurrentSession, let current = currentPhoto {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, entry in
                            ZoomableImageView(photo: entry.snapshot, sessionID: originatingSessionID)
                                .environmentObject(authViewModel).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                    .simultaneousGesture(TapGesture().onEnded { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } })
                    .accessibilityAction(named: showControls ? "Hide controls" : "Show controls") { showControls.toggle() }

                    if showControls {
                        VStack(spacing: 0) {
                            topBar(current)
                            Spacer()
                            if !landscape {
                                WagLockActionBar(actions: actions).padding(.horizontal, 22).padding(.bottom, 8)
                            }
                        }
                        .padding(.horizontal, landscape ? 62 : 0)
                        .transition(.opacity)
                        if landscape {
                            HStack {
                                Spacer()
                                WagLockActionBar(actions: actions, vertical: true).padding(.trailing, 62)
                            }
                            .transition(.opacity)
                        }
                    }
                }
            }
        }
        .statusBarHidden(!showControls)
        .sheet(isPresented: $showPhotoInfo) {
            if isCurrentSession, let current = currentPhoto {
                PhotoInfoSheet(snapshot: current.snapshot) { showPhotoInfo = false }
            }
        }
        .sheet(isPresented: $showMoveToAlbum) {
            if isCurrentSession, let current = currentPhoto {
                MoveToAlbumSheet(items: [current.source]) { removeEntry(current.id) }
            }
        }
        .alert(String(localized: "photo.delete.confirmTitle"), isPresented: $showDeleteAlert) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "common.delete"), role: .destructive) {
                Task {
                    await deletePhoto()
                }
            }
        } message: {
            Text(String(localized: "photo.delete.confirmMessage"))
        }
        .alert(String(localized: "export.failed"), isPresented: $showExportError) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(exportError ?? String(localized: "common.unknownError"))
        }
        .onDisappear {
            if !showShareSheet, let exportJobID { vaultServices.exports.cancelExport(exportJobID) }
        }
        .onChange(of: exportScenePhase) { _, phase in
            if phase == .background { isExporting = false; showShareSheet = false }
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
            isShowing: isDeleting || isExporting,
            message: isDeleting
                ? String(localized: "photo.deleting") : String(localized: "photo.decrypting")
        )
    }

    private func topBar(_ current: Entry) -> some View {
        HStack(spacing: 12) {
            WagLockRoundButton(symbol: "xmark", label: "Close", onMedia: true) { dismiss() }
                .accessibilityIdentifier("photo.close")
            Spacer()
            VStack(spacing: 0) {
                Text(current.snapshot.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.wlBodyStrong).foregroundStyle(.white)
                Text(current.snapshot.createdAt.formatted(.dateTime.hour().minute()) + " · \(currentIndex + 1) of \(photos.count)")
                    .font(.wlMeta).foregroundStyle(Color.white.opacity(0.75))
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Menu {
                Button("Info", systemImage: "info.circle") { showPhotoInfo = true }
                Button("Export", systemImage: "square.and.arrow.up") { sharePhoto() }
                Button("Delete", systemImage: "trash", role: .destructive) { showDeleteAlert = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Color.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("More actions")
        }
        .padding(.horizontal, 22).padding(.top, 8)
    }

    private var actions: [WagLockAction] {
        [
            WagLockAction(id: "photo.info", symbol: "info.circle", title: "Info") { showPhotoInfo = true },
            WagLockAction(id: "photo.album", symbol: "rectangle.stack.badge.plus", title: "Album") { showMoveToAlbum = true },
            WagLockAction(id: "photo.share", symbol: "square.and.arrow.up", title: "Export", enabled: !isExporting) { sharePhoto() },
            WagLockAction(id: "photo.delete", symbol: "trash", title: "Delete", destructive: true) { showDeleteAlert = true },
        ]
    }

    /// After a verified move into an album the original record is gone; drop it locally.
    private func removeEntry(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos.remove(at: index)
        if photos.isEmpty { dismiss(); return }
        currentIndex = min(currentIndex, photos.count - 1)
    }

    // MARK: - Computed Properties

    private var isCurrentSession: Bool {
        authViewModel.isAuthenticated && (originatingSessionID == nil || authViewModel.librarySessionID == originatingSessionID)
    }

    private var currentPhoto: Entry? {
        guard photos.indices.contains(currentIndex) else {
            return photos.first
        }
        return photos[currentIndex]
    }

    // MARK: - Methods

    private func sharePhoto() {
        guard isCurrentSession, !isExporting else { return }
        guard let item = currentPhoto else { return }

        guard let password = authViewModel.sessionPassword, !password.isEmpty else {
            exportError = String(localized: "photo.error.noPassword")
            showExportError = true
            return
        }

        isExporting = true

        let exportSessionID = authViewModel.librarySessionID
        exportJobID = vaultServices.exports.exportItems([item.source], password: password, sessionID: exportSessionID) { result in
            guard authViewModel.isAuthenticated, authViewModel.librarySessionID == exportSessionID else { return }
            switch result {
            case .success(let urls):
                exportedURLs = urls
                showShareSheet = true
            case .failure(let error):
                exportError = error.localizedDescription
                showExportError = true
            }

            isExporting = false
        }
    }

    private func deletePhoto() async {
        guard isCurrentSession, let entry = currentPhoto else { return }
        let photoToDelete = entry.source
        isDeleting = true

        let encryptedPath = photoToDelete.encryptedPath

        // Commit the database deletion first, then close the screen and delete files;
        // on failure, stay on the screen and show an error instead of dismissing silently
        modelContext.delete(photoToDelete)
        do {
            try LibraryWriteCoordinator.save(modelContext)
        } catch {
            modelContext.rollback()
            isDeleting = false
            exportError = String(
                format: String(localized: "gallery.error.deleteFailed"),
                error.localizedDescription)
            showExportError = true
            return
        }

        // Remove it from the local array so the dismiss animation never renders a deleted object
        if let index = photos.firstIndex(where: { $0.id == entry.id }) {
            photos.remove(at: index)
            if currentIndex >= photos.count {
                currentIndex = max(photos.count - 1, 0)
            }
        }

        do {
            try vaultServices.storage.deleteFile(path: encryptedPath)
        } catch {
            // The record is gone; a failed file delete only leaves an unreferenced encrypted file
        }

        isDeleting = false
        dismiss()
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppConstants.presentationLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext
    let photo: MediaPreviewSnapshot
    let sessionID: UUID?

    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadError: String?
    // Zoom/pan state is private to each page so one photo's zoom doesn't carry over to the next
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = loadedImage {
                    // Show the loaded image
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if isLoading {
                    // Loading
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(ColorTheme.accent)
                } else if let error = loadError {
                    // Load failed
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        Text(String(localized: "media.loadFailed"))
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // Retry button
                        Button {
                            Task { await loadImage() }
                        } label: {
                            Label(
                                String(localized: "common.retry"),
                                systemImage: "arrow.clockwise")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(ColorTheme.tertiaryBackground)
                                .foregroundColor(ColorTheme.primaryText)
                                .cornerRadius(10)
                        }
                    }
                } else {
                    // Initial placeholder
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 80))
                                .foregroundColor(.gray)
                        }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale *= delta

                        // Clamp the zoom range
                        scale = min(max(scale, 1.0), 5.0)
                    }
                    .onEnded { _ in
                        lastScale = 1.0

                        // Reset if zoomed below 1
                        if scale < 1.0 {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        } else {
                            // After zooming, pull the offset back within the zoomed image's bounds
                            offset = clampedOffset(offset, containerSize: geometry.size)
                            lastOffset = offset
                        }
                    }
            )
            // The pan gesture is attached only when zoomed in (scale > 1);
            // when not zoomed it isn't attached, leaving horizontal swipes to the outer TabView for paging,
            // otherwise the DragGesture would steal the page-change gesture and swiping wouldn't work
            .simultaneousGesture(
                scale > 1.0
                    ? AnyGesture(
                        DragGesture()
                            .onChanged { value in
                                let proposed = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                                offset = clampedOffset(proposed, containerSize: geometry.size)
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    : nil
            )
            .onTapGesture(count: 2) {
                // Double-tap to zoom
                withAnimation(.spring()) {
                    if scale > 1.0 {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2.0
                    }
                }
            }
            .task {
                await loadImage()
            }
            .onChange(of: authViewModel.isAuthenticated) { _, authenticated in
                if !authenticated { loadedImage = nil; loadError = nil }
            }
            .onDisappear { loadedImage = nil }
        }
    }

    /// Clamp the pan offset to the zoomed image's bounds so it can't be dragged off screen
    private func clampedOffset(_ proposed: CGSize, containerSize: CGSize) -> CGSize {
        guard scale > 1.0, let image = loadedImage else {
            return .zero
        }

        // The image is aspect-fit in its container; first compute its unzoomed display size
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height
        let displayedSize: CGSize
        if imageAspect >= containerAspect {
            displayedSize = CGSize(
                width: containerSize.width,
                height: containerSize.width / imageAspect)
        } else {
            displayedSize = CGSize(
                width: containerSize.height * imageAspect,
                height: containerSize.height)
        }

        // The part that extends beyond the container after zooming is the allowed pan range
        let scaledWidth = displayedSize.width * scale
        let scaledHeight = displayedSize.height * scale
        let maxX = max(0, (scaledWidth - containerSize.width) / 2)
        let maxY = max(0, (scaledHeight - containerSize.height) / 2)

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY))
    }

    private var canRead: Bool {
        authViewModel.isAuthenticated && (sessionID == nil || authViewModel.librarySessionID == sessionID)
    }

    private func loadImage() async {
        guard canRead, let password = authViewModel.sessionPassword, !password.isEmpty else { return }
        isLoading = true
        loadError = nil

        do {
            let image = try await vaultServices.mediaLoader.loadImage(
                from: photo,
                password: password
            )
            guard canRead, !Task.isCancelled else { return }
            await MainActor.run {
                self.loadedImage = image
                self.isLoading = false
            }
        } catch {
            guard canRead, !Task.isCancelled else { return }
            await MainActor.run {
                self.loadError = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let samplePhoto = MediaItem(
        fileName: "sample.jpg",
        fileExtension: "jpg",
        fileSize: 1_024_000,
        type: .photo,
        encryptedPath: "/path/to/file"
    )

    return PhotoDetailView(photo: samplePhoto, allPhotos: [samplePhoto])
        .environmentObject(AuthenticationViewModel())
}

/// Photo information: name, created, dimensions, size and format, all from the immutable snapshot.
struct PhotoInfoSheet: View {
    let snapshot: MediaPreviewSnapshot
    var subtitle = "Original photograph"
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Graphite.line).frame(width: 40, height: 5).frame(maxWidth: .infinity).accessibilityHidden(true)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.fullFileName).font(.wlHeading).foregroundStyle(Graphite.textPrimary).lineLimit(2)
                    Text(subtitle).font(.wlMeta).foregroundStyle(Graphite.textMuted)
                }
                Spacer()
                Button("Done", action: close).font(WagLockFonts.poppins(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Graphite.accentText).frame(minHeight: 44)
                    .accessibilityIdentifier("photo.info.close")
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                card("Created", snapshot.createdAt.formatted(.dateTime.month(.abbreviated).day().year()),
                     snapshot.createdAt.formatted(.dateTime.hour().minute()))
                card("Dimensions", snapshot.formattedDimensions ?? "Not recorded", nil)
                card("File size", snapshot.formattedFileSize, snapshot.fileExtension.uppercased())
                if let duration = snapshot.formattedDuration { card("Duration", duration, nil) }
            }
            Label("Encrypted and stored on this device", systemImage: "lock")
                .font(.wlMeta).foregroundStyle(Graphite.textMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 20)
        .background(Graphite.base)
        .presentationDetents([.medium, .large])
    }

    private func card(_ label: String, _ value: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(WagLockFonts.poppins(11, .semibold, relativeTo: .caption)).tracking(1.5)
                .foregroundStyle(Graphite.textMuted)
            Text(value).font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary)
            if let detail { Text(detail).font(.wlMeta).foregroundStyle(Graphite.textMuted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
