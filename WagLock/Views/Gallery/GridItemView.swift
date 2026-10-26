//
//  GridItemView.swift
//  WagLock
//
//  Grid item view
//  Shows a media thumbnail
//

import SwiftUI

struct GridItemView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext

    // MARK: - Properties

    let mediaItem: MediaItem
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var showsMetadata = true
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    @State private var didFailToLoadThumbnail = false

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Background and thumbnail
                thumbnailView(size: geometry.size)

                if showsMetadata {
                    LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    overlayInfo
                }

                // Selection mode marker
                if isSelectionMode {
                    selectionOverlay
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.blue, lineWidth: isSelected ? 3 : 0)
            )
        }
        .aspectRatio(1, contentMode: .fill)
        .task(id: mediaItem.id) {
            await loadThumbnailIfNeeded()
        }
    }

    // MARK: - Thumbnail View

    @ViewBuilder
    private func thumbnailView(size: CGSize) -> some View {
        if let image = thumbnailImage {
            // Show the thumbnail
            if mediaItem.type == .video {
                VideoThumbnailImage(image: image)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
            }
        } else if mediaItem.thumbnailData != nil && !didFailToLoadThumbnail {
            placeholderView
                .overlay {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
        } else {
            // Placeholder
            placeholderView
        }
    }

    // MARK: - Placeholder View

    private var placeholderView: some View {
        ZStack {
            // Background color
            mediaItem.type.iconColor.opacity(0.2)

            // Type icon
            VStack(spacing: 8) {
                Image(systemName: mediaItem.type.iconName)
                    .font(.system(size: 40))
                    .foregroundColor(mediaItem.type.iconColor)

                Text(mediaItem.fileExtension)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Overlay Info

    private var overlayInfo: some View {
        HStack(alignment: .bottom) {
            // Type icon
            Image(systemName: mediaItem.type.iconName)
                .font(.caption)
                .foregroundColor(.white)
                .padding(6)
                .background(Circle().fill(mediaItem.type.iconColor))

            Spacer()

            // Video duration
            if mediaItem.type == .video, let duration = mediaItem.formattedDuration {
                Text(duration)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.6))
                    )
            }
        }
        .padding(8)
    }

    // MARK: - Selection Overlay

    private var selectionOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .white)
                    .padding(8)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func loadThumbnailIfNeeded() async {
        // Don't retry thumbnails that already failed, so each reappearance doesn't decrypt and decode again
        guard thumbnailImage == nil,
            !isLoadingThumbnail,
            !didFailToLoadThumbnail,
            let thumbnailData = mediaItem.thumbnailData
        else {
            return
        }

        isLoadingThumbnail = true
        let image = await vaultServices.thumbnails.image(
            for: mediaItem.id.uuidString,
            data: thumbnailData
        )
        guard !Task.isCancelled else {
            isLoadingThumbnail = false
            return
        }

        thumbnailImage = image
        isLoadingThumbnail = false
        didFailToLoadThumbnail = image == nil
    }
}

// MARK: - Preview

#Preview {
    let sampleItem = MediaItem(
        fileName: "Sample",
        fileExtension: ".jpg",
        fileSize: 1_024_000,
        type: .photo,
        encryptedPath: "/path/to/file",
        thumbnailData: nil,
        width: 1920,
        height: 1080
    )

    return GridItemView(mediaItem: sampleItem)
        .frame(width: 150, height: 150)
        .padding()
}
