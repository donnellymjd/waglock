//
//  VideosView.swift
//  WagLock
//
//  视频视图
//  列表展示所有视频，支持播放
//

import AVKit
import SwiftData
import SwiftUI

struct VideosView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    // 只查询视频类型的媒体
    @Query(
        filter: #Predicate<MediaItem> { item in
            item.typeRawValue == "video"
        },
        sort: \MediaItem.createdAt,
        order: .reverse
    )
    private var videos: [MediaItem]

    // MARK: - State

    @EnvironmentObject private var guestModeManager: GuestModeManager
    @State private var searchText = ""
    @State private var showImportView = false
    private struct VideoSelection: Identifiable {
        let id = UUID()
        let view: VideoPlayerView
    }
    @State private var selectedVideo: VideoSelection?
    @State private var videoToDelete: MediaItem?
    @State private var deleteErrorMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            WagLockSearchField(title: "Search videos", text: $searchText).padding(.horizontal, 24)
            ZStack {
            // 访客模式下始终显示空状态
            if guestModeManager.isGuestMode || videos.isEmpty {
                emptyStateView
            } else {
                videoListView
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(ColorTheme.primaryBackground)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // 访客模式下隐藏导入按钮
                if guestModeManager.isOwnerMode {
                    Button {
                        showImportView = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }.accessibilityIdentifier("videos.import").accessibilityLabel("Import videos")
                }
            }
        }
        .sheet(isPresented: $showImportView) {
            ImportButtonsView(onImportComplete: { items in
            })
            .environment(\.modelContext, modelContext)
            .environmentObject(authViewModel)
        }
        .fullScreenCover(item: $selectedVideo) { video in
            video.view
        }
        .alert(
            String(localized: "video.delete.confirmTitle"),
            isPresented: Binding(
                get: { videoToDelete != nil },
                set: { if !$0 { videoToDelete = nil } }
            ),
            presenting: videoToDelete
        ) { video in
            Button(String(localized: "common.delete"), role: .destructive) {
                deleteVideo(video)
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: { _ in
            Text(String(localized: "video.delete.confirmMessage"))
        }
        .alert(
            String(localized: "common.error"),
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }

    }

    // Missing ciphertext is an explicit read/recovery error. Never delete
    // library records automatically or inspect dismissed models in a late task.

    // MARK: - Empty State

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 24) {
                WagLockEmptyState(symbol: "play.rectangle", title: "Keep your moments close.", detail: "Add videos to watch here, on this device.")
                if guestModeManager.isOwnerMode {
                    Button("Add videos") { showImportView = true }
                        .buttonStyle(WagLockPrimaryButtonStyle()).padding(.horizontal, 24)
                }
            }.padding(.vertical, 48)
        }
    }

    // MARK: - Video List

    private var videoListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("RECENTLY ADDED").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                ForEach(videos.filter { searchText.isEmpty || $0.fileName.localizedCaseInsensitiveContains(searchText) }) { video in
                    VideoCardView(video: video)
                        .onTapGesture {
                            selectedVideo = VideoSelection(view: VideoPlayerView(video: video, sessionID: authViewModel.librarySessionID))
                        }
                        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("videos.preview")
                        .contextMenu {
                            Button(role: .destructive) {
                                videoToDelete = video
                            } label: {
                                Label(String(localized: "common.delete"), systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 8)
        }
    }

    // MARK: - Methods

    private func deleteVideo(_ video: MediaItem) {
        let encryptedPath = video.encryptedPath

        // 先提交数据库删除，成功后再删文件，
        // 避免 save 失败时留下指向已删除文件的记录
        modelContext.delete(video)
        do {
            try LibraryWriteCoordinator.save(modelContext)
        } catch {
            modelContext.rollback()
            deleteErrorMessage = String(
                format: String(localized: "gallery.error.deleteFailed"),
                error.localizedDescription)
            return
        }

        do {
            try vaultServices.storage.deleteFile(path: encryptedPath)
        } catch {
            // 记录已删除，文件删除失败只会残留无引用的加密文件
        }
    }
}

// MARK: - Video Card View

struct VideoCardView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext
    let video: MediaPreviewSnapshot
    private let thumbnailData: Data?
    @State private var thumbnailImage: UIImage?

    init(video: MediaItem) {
        self.video = MediaPreviewSnapshot(video)
        self.thumbnailData = video.thumbnailData
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 视频缩略图
            ZStack {
                // 缩略图或占位背景
                if let thumbnailImage {
                    VideoThumbnailImage(image: thumbnailImage)
                } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.pink.opacity(0.3), .orange.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .aspectRatio(16 / 9, contentMode: .fit)
                }

                // 播放图标
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 10)

                // 时长标签（右下角）
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(video.formattedDuration ?? "00:00")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                            .padding(8)
                    }
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)

            // 视频信息
            VStack(alignment: .leading, spacing: 6) {
                Text(video.fileName)
                    .font(.headline)
                    .lineLimit(1)

                HStack {
                    Label(
                        formatFileSize(video.fileSize),
                        systemImage: "doc"
                    )

                    Spacer()

                    Text(formatDate(video.createdAt))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
        }
        .background(ColorTheme.secondaryBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .task(id: video.id) {
            guard let thumbnailData else { return }
            let image = await vaultServices.thumbnails.image(
                for: video.id.uuidString,
                data: thumbnailData
            )
            guard !Task.isCancelled else { return }
            thumbnailImage = image
        }
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
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    VideosView()
        .modelContainer(for: MediaItem.self, inMemory: true)
        .environmentObject(AuthenticationViewModel())
}
