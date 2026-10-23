//
//  PhotoDetailView.swift
//  WagLock
//
//  相片详细预览视图
//  支持缩放、滑动切换、手势交互
//

import SwiftUI

struct PhotoDetailView: View {

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

    // 本地副本：删除成功后先从数组移除，避免 dismiss 动画期间渲染已删除的对象
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

    // MARK: - Initialization

    init(photo: MediaItem, allPhotos: [MediaItem], sessionID: UUID? = nil) {
        self.originatingSessionID = sessionID
        _photos = State(initialValue: allPhotos.map(Entry.init))

        // 找到当前图片的索引
        if let index = allPhotos.firstIndex(where: { $0.id == photo.id }) {
            _currentIndex = State(initialValue: index)
        } else {
            _currentIndex = State(initialValue: 0)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if isCurrentSession, let current = currentPhoto {
                    Text("\(currentIndex + 1) of \(photos.count) · Original photograph")
                        .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TabView(selection: $currentIndex) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, entry in
                            ZoomableImageView(photo: entry.snapshot, sessionID: originatingSessionID)
                                .environmentObject(authViewModel).tag(index)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack {
                        Button("Info") { showPhotoInfo = true }.frame(maxWidth: .infinity)
                        Button("Export") { sharePhoto() }.frame(maxWidth: .infinity)
                            .disabled(isExporting).accessibilityIdentifier("photo.share")
                        Button("Delete", role: .destructive) { showDeleteAlert = true }.frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).padding(3)
                        .background(ColorTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: 12))
                    Button { showPhotoInfo = true } label: {
                        WagLockNavigationRow(symbol: "info.circle", title: current.snapshot.fullFileName,
                            detail: [current.snapshot.formattedDimensions, current.snapshot.formattedFileSize].compactMap { $0 }.joined(separator: " · "))
                    }.buttonStyle(.plain).accessibilityIdentifier("photo.info")
                    Text("Pinch to zoom · Swipe to the next photo").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ColorTheme.primaryBackground.ignoresSafeArea())
                .navigationTitle(currentPhoto?.snapshot.formattedCreatedDate ?? "Photo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("photo.close") } }
        }
        .sheet(isPresented: $showPhotoInfo) {
            if isCurrentSession, let current = currentPhoto {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(current.snapshot.fullFileName).font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                            ZoomableImageView(photo: current.snapshot, sessionID: originatingSessionID)
                                .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("DETAILS").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                            WagLockNavigationRow(symbol: "clock", title: "Created", detail: current.snapshot.formattedCreatedDate)
                            WagLockNavigationRow(symbol: "photo", title: "Dimensions", detail: current.snapshot.formattedDimensions ?? "Not recorded")
                            WagLockNavigationRow(symbol: "internaldrive", title: "File size", detail: "\(current.snapshot.formattedFileSize) · \(current.snapshot.fileExtension.uppercased())")
                        }.padding(24)
                    }.background(ColorTheme.primaryBackground).navigationTitle("Photo information")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPhotoInfo = false }.accessibilityIdentifier("photo.info.close") } }
                }
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
            if !showShareSheet, let exportJobID { ExportService.shared.cancelExport(exportJobID) }
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
        exportJobID = ExportService.shared.exportItems([item.source], password: password, sessionID: exportSessionID) { result in
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

        // 先提交数据库删除，成功后再关页面、删文件；
        // 失败时留在页面上提示，而不是无声地 dismiss
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

        // 从本地数组移除，避免 dismiss 动画期间渲染已删除的对象
        if let index = photos.firstIndex(where: { $0.id == entry.id }) {
            photos.remove(at: index)
            if currentIndex >= photos.count {
                currentIndex = max(photos.count - 1, 0)
            }
        }

        do {
            try FileStorageService.shared.deleteFile(path: encryptedPath)
        } catch {
            // 记录已删除，文件删除失败只会残留无引用的加密文件
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
    let photo: MediaPreviewSnapshot
    let sessionID: UUID?

    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadError: String?
    // 缩放/平移状态归每页私有，避免翻页时把上一张的缩放带到下一张
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = loadedImage {
                    // 显示加载的图片
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if isLoading {
                    // 加载中
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(ColorTheme.accent)
                } else if let error = loadError {
                    // 加载失败
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

                        // 重试按钮
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
                    // 初始占位
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

                        // 限制缩放范围
                        scale = min(max(scale, 1.0), 5.0)
                    }
                    .onEnded { _ in
                        lastScale = 1.0

                        // 如果缩放小于1，重置
                        if scale < 1.0 {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        } else {
                            // 缩放结束后把偏移收敛到放大图像的边界内
                            offset = clampedOffset(offset, containerSize: geometry.size)
                            lastOffset = offset
                        }
                    }
            )
            // 平移手势只在放大(scale > 1)时挂载；
            // 未放大时不挂载，把左右滑动让给外层 TabView 完成翻页，
            // 否则 DragGesture 会抢占页面切换手势导致无法左右滑动
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
                // 双击缩放
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

    /// 将平移偏移限制在放大图像的边界内，避免图片被拖出屏幕
    private func clampedOffset(_ proposed: CGSize, containerSize: CGSize) -> CGSize {
        guard scale > 1.0, let image = loadedImage else {
            return .zero
        }

        // 图片按 aspectFit 显示在容器内，先算出未缩放的显示尺寸
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

        // 缩放后超出容器的部分就是允许平移的范围
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
            let image = try await MediaLoaderService.shared.loadImage(
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
