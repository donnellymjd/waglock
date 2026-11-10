import Photos
import SwiftUI
import UIKit

/// WagLock's own photo browser, used when the person wants Select All (iOS's picker has
/// none). It needs Photos access, asked only when this screen opens. Thumbnails are held
/// in memory by Photos' image manager; nothing is written to disk until "Add" is tapped,
/// and then only into the encrypted import path.
struct PhotoLibraryBrowserView: View {
    let add: ([String]) -> Void
    let cancel: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var albums: [Album] = []
    @State private var albumID = Album.allID
    @State private var assets: PHFetchResult<PHAsset> = PHFetchResult()
    @State private var shownIDs: [String] = []
    @State private var selection = PhotoLibrarySelection()
    @State private var observer: LibraryChangeObserver?
    @State private var gridWidth: CGFloat = 0
    @State private var drag: PhotoDragSelection?
    /// A drag that started mostly vertically is a scroll, not a selection.
    @State private var dragIsScroll = false

    struct Album: Identifiable, Hashable {
        static let allID = "all"
        static let videosID = "videos"
        let id: String
        let title: String
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            switch status {
            case .authorized, .limited:
                if status == .limited {
                    WagLockNote(kind: .info, text: "WagLock can see only the photos you allowed. To show more, change Photos access for WagLock in Settings.")
                        .padding(.horizontal, 16).padding(.bottom, 8)
                }
                albumChips
                grid
                footer
            case .notDetermined:
                Spacer()
                ProgressView().tint(Graphite.accentText)
                Spacer()
            default:
                denied
            }
        }
        .background(Graphite.base.ignoresSafeArea())
        .task { await authorize() }
        .onDisappear { observer = nil }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack {
            Button("Cancel", action: cancel)
                .font(WagLockFonts.poppins(15, .medium, relativeTo: .body)).foregroundStyle(Graphite.textSecondary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("photoBrowser.cancel")
            Spacer()
            Text(selection.isEmpty ? "Select items" : "\(selection.count) selected")
                .font(.wlHeading).foregroundStyle(Graphite.textPrimary)
                .accessibilityIdentifier("photoBrowser.count")
            Spacer()
            Button(allShownSelected ? "Deselect All" : "Select All") {
                if allShownSelected { selection.deselectAll(shownIDs) } else { selection.selectAll(shownIDs) }
            }
            .font(WagLockFonts.poppins(15, .semibold, relativeTo: .body)).foregroundStyle(Graphite.accentText)
            .frame(minHeight: 44)
            .disabled(shownIDs.isEmpty || !isReadable)
            .accessibilityIdentifier("photoBrowser.selectAll")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Button(selection.isEmpty ? "Add" : "Add \(selection.count) item\(selection.count == 1 ? "" : "s")") {
                add(selection.identifiers)
            }
            .buttonStyle(WagLockPrimaryButtonStyle())
            .disabled(selection.isEmpty)
            .accessibilityIdentifier("photoBrowser.add")
            Text("Your originals stay in Photos. You can remove them after they’re added.")
                .font(.wlMeta).foregroundStyle(Graphite.textMuted).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(Graphite.bar)
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: 14) {
            WagLockNote(kind: .caution, title: "Photos access is off",
                        text: "Select All needs WagLock to read your photo library. You can still choose items one by one with “Photos & videos”, which needs no access.")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(WagLockSecondaryButtonStyle())
            Spacer()
        }
        .padding(.horizontal, 22).padding(.top, 12)
    }

    // MARK: Albums

    private var albumChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(albums) { album in
                    WagLockChip(title: album.title, selected: album.id == albumID) {
                        guard albumID != album.id else { return }
                        albumID = album.id
                        load()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    // MARK: Grid

    private var columnCount: Int { PhotoGridGeometry.columns(width: gridWidth) }

    private var grid: some View {
        ScrollView {
            if shownIDs.isEmpty {
                Text("Nothing here").font(.wlBody).foregroundStyle(Graphite.textMuted).padding(.top, 60)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount), spacing: 2) {
                ForEach(0..<assets.count, id: \.self) { index in
                    let asset = assets.object(at: index)
                    PhotoLibraryTile(asset: asset, selected: selection.contains(asset.localIdentifier))
                        .id(asset.localIdentifier)
                        .onTapGesture { selection.toggle(asset.localIdentifier) }
                }
            }
            .coordinateSpace(name: "photoGrid")
            .background(GeometryReader { proxy in
                Color.clear.onAppear { gridWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in gridWidth = width }
            })
            // Drag sideways across tiles to select or deselect a run of them, as in Photos.
            // A drag that starts vertically scrolls instead. Simultaneous, so scrolling
            // still works and a selection drag can carry on down the grid.
            .simultaneousGesture(DragGesture(minimumDistance: 10, coordinateSpace: .named("photoGrid"))
                .onChanged(dragChanged)
                .onEnded { _ in drag = nil; dragIsScroll = false })
            .id(albumID)
        }
    }

    private func dragChanged(_ value: DragGesture.Value) {
        guard !dragIsScroll else { return }
        let count = shownIDs.count
        if drag == nil {
            let moved = value.translation
            guard abs(moved.width) > abs(moved.height) else { dragIsScroll = true; return }
            guard let start = PhotoGridGeometry.index(at: value.startLocation, width: gridWidth, columns: columnCount, count: count)
            else { return }
            drag = PhotoDragSelection(anchor: start, shown: shownIDs, selection: selection)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        guard let drag, let current = PhotoGridGeometry.index(at: value.location, width: gridWidth, columns: columnCount, count: count)
        else { return }
        let updated = drag.selection(shown: shownIDs, current: current)
        if updated != selection { selection = updated }
    }

    private var isReadable: Bool { status == .authorized || status == .limited }
    private var allShownSelected: Bool { selection.allSelected(shownIDs) }

    // MARK: Loading

    private func authorize() async {
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard isReadable else { return }
        albums = Self.loadAlbums()
        load()
        observer = LibraryChangeObserver { load() }
    }

    private func load() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        switch albumID {
        case Album.allID:
            options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            assets = PHAsset.fetchAssets(with: options)
        case Album.videosID:
            assets = PHAsset.fetchAssets(with: .video, options: options)
        default:
            if let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject {
                options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                                PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
                assets = PHAsset.fetchAssets(in: collection, options: options)
            } else {
                albumID = Album.allID
                load()
                return
            }
        }
        var ids: [String] = []
        ids.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        shownIDs = ids
    }

    private static func loadAlbums() -> [Album] {
        var result = [Album(id: Album.allID, title: "All"), Album(id: Album.videosID, title: "Videos")]
        let smart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil)
        smart.enumerateObjects { collection, _, _ in
            result.append(Album(id: collection.localIdentifier, title: collection.localizedTitle ?? "Favorites"))
        }
        let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        user.enumerateObjects { collection, _, _ in
            result.append(Album(id: collection.localIdentifier, title: collection.localizedTitle ?? "Album"))
        }
        return result
    }
}

/// Reloads the grid when the photo library changes (for example after limited access changes).
private final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private nonisolated let changed: @MainActor @Sendable () -> Void
    init(_ changed: @escaping @MainActor @Sendable () -> Void) {
        self.changed = changed
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [changed] in changed() }
    }
}

/// One square thumbnail with a selection badge. Thumbnails come from Photos' image
/// manager in memory only.
private struct PhotoLibraryTile: View {
    let asset: PHAsset
    let selected: Bool
    @State private var image: UIImage?
    @State private var request: PHImageRequestID?

    var body: some View {
        Graphite.surface1
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    Text(Self.duration(asset.duration))
                        .font(WagLockFonts.poppins(11, .semibold, relativeTo: .caption2)).foregroundStyle(.white)
                        .padding(4).shadow(radius: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(selected ? Graphite.onAccent : .white, selected ? Graphite.accentStrong : Color.black.opacity(0.25))
                    .padding(5).shadow(radius: selected ? 0 : 2)
                    .accessibilityHidden(true)
            }
            .overlay { if selected { Rectangle().stroke(Graphite.accentStrong, lineWidth: 3) } }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .onAppear(perform: loadThumbnail)
            .onDisappear {
                if let request { PHImageManager.default().cancelImageRequest(request) }
                request = nil
            }
    }

    private var accessibilityText: String {
        let kind = asset.mediaType == .video ? "Video" : asset.mediaSubtypes.contains(.photoLive) ? "Live Photo" : "Photo"
        guard let date = asset.creationDate else { return kind }
        return kind + ", " + date.formatted(date: .abbreviated, time: .shortened)
    }

    private func loadThumbnail() {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let scale = UITraitCollection.current.displayScale
        request = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 130 * scale, height: 130 * scale),
                                                        contentMode: .aspectFill, options: options) { result, _ in
            if let result { image = result }
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
