import SwiftData
import SwiftUI

/// The Library tab: one header (title, this library's count, backup health, add) over
/// All / Photos / Videos / Audio chips. Photos, Videos and Audio reuse the existing
/// screens so selection, export, playback and deletion keep their audited session checks.
struct LibraryView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", photos = "Photos", videos = "Videos", audio = "Audio"
        var id: String { rawValue }
    }

    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @EnvironmentObject private var guestModeManager: GuestModeManager
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<MediaItem> { $0.typeRawValue == "photo" }, sort: \MediaItem.createdAt, order: .reverse)
    private var photos: [MediaItem]
    @Query(filter: #Predicate<MediaItem> { $0.typeRawValue == "video" }, sort: \MediaItem.createdAt, order: .reverse)
    private var videos: [MediaItem]
    @Query(filter: #Predicate<MediaItem> { $0.typeRawValue == "audio" }, sort: \MediaItem.createdAt, order: .reverse)
    private var audio: [MediaItem]
    @State private var filter: Filter = .all
    @State private var showImport = false
    @State private var showBackup = false

    private var total: Int { guestModeManager.isGuestMode ? 0 : photos.count + videos.count + audio.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if total == 0 && filter == .all {
                    EmptyLibraryView(addPhotos: { showImport = true }, importOther: { showImport = true })
                } else {
                    switch filter {
                    case .all:
                        AllMediaGrid(photos: photos, videos: videos, audio: audio) { filter = .audio }
                    case .photos:
                        PhotosView(showsTitle: false).environmentObject(authViewModel)
                    case .videos:
                        NavigationStack {
                            VideosView().environmentObject(authViewModel)
                                .background(Graphite.base).navigationBarTitleDisplayMode(.inline)
                        }
                    case .audio:
                        NavigationStack {
                            AudioView().background(Graphite.base).navigationBarTitleDisplayMode(.inline)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Graphite.base)
        .sheet(isPresented: $showImport) {
            ImportButtonsView(onImportComplete: { _ in })
                .environment(\.modelContext, modelContext)
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showBackup) {
            NavigationStack {
                PortableBackupView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showBackup = false } } }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    WagLockTitle(text: "Library")
                    Text("\(total) item\(total == 1 ? "" : "s") · On this device")
                        .font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textMuted)
                }
                Spacer()
                if guestModeManager.isOwnerMode {
                    WagLockRoundButton(symbol: "plus", label: "Add to WagLock", prominent: true) { showImport = true }
                        .accessibilityIdentifier("library.add")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases) { option in
                        WagLockChip(title: option.rawValue, count: option == .all ? nil : count(option),
                                    selected: filter == option) { filter = option }
                            .accessibilityIdentifier("library.filter." + option.rawValue.lowercased())
                    }
                }
            }
            if guestModeManager.isOwnerMode && total > 0 {
                WagLockBackupBanner { showBackup = true }
            }
        }
        .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func count(_ option: Filter) -> Int {
        guard !guestModeManager.isGuestMode else { return 0 }
        switch option {
        case .all: return total
        case .photos: return photos.count
        case .videos: return videos.count
        case .audio: return audio.count
        }
    }
}

/// Empty library: one large Add photos action plus importing files or audio.
private struct EmptyLibraryView: View {
    let addPhotos: () -> Void
    let importOther: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(Graphite.accentText)
                .frame(width: 88, height: 88)
                .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Graphite.line, lineWidth: 1))
                .accessibilityHidden(true)
            WagLockTitle(text: "Make room for\nyour memories.", size: .display)
            Text("Add a few photos to get started. Your originals stay in your photo library.")
                .font(.wlBody).foregroundStyle(Graphite.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Add photos", action: addPhotos).buttonStyle(WagLockPrimaryButtonStyle())
                .accessibilityIdentifier("library.empty.add")
            Button("Import files or audio instead", action: importOther)
                .font(WagLockFonts.poppins(14, .semibold, relativeTo: .body))
                .foregroundStyle(Graphite.accentText).frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
    }
}

/// Photos, videos and audio together, grouped by day. Photos open the photo viewer (swiping
/// through photos), videos open the video viewer, and audio switches to the Audio filter.
private struct AllMediaGrid: View {
    let photos: [MediaItem]
    let videos: [MediaItem]
    let audio: [MediaItem]
    let showAudio: () -> Void
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @StateObject private var settings = AppSettings.shared
    @State private var presented: Presented?

    private struct Presented: Identifiable {
        let id = UUID()
        let photo: PhotoDetailView?
        let video: VideoPlayerView?
    }

    private struct Day: Identifiable {
        let date: Date
        let items: [MediaItem]
        var id: Date { date }
        var title: String {
            let formatted = date.formatted(.dateTime.month(.abbreviated).day().year()).uppercased()
            return Calendar.current.isDateInToday(date) ? "TODAY · " + formatted : formatted
        }
    }

    private var days: [Day] {
        let all = (photos + videos + audio).sorted { $0.createdAt > $1.createdAt }
        let groups = Dictionary(grouping: all) { Calendar.current.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { Day(date: $0, items: groups[$0] ?? []) }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: settings.gridColumns)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(days) { day in
                    WagLockSectionLabel(day.title)
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(day.items) { item in tile(item) }
                    }
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 8)
        }
        .fullScreenCover(item: $presented) { item in
            if let photo = item.photo { photo.environmentObject(authViewModel) }
            else if let video = item.video { video }
        }
    }

    @ViewBuilder
    private func tile(_ item: MediaItem) -> some View {
        Group {
            if item.type == .audio {
                VStack(spacing: 6) {
                    Image(systemName: "waveform").font(.system(size: 24)).foregroundStyle(Graphite.accentText)
                    Text(item.fileName).font(.wlMeta).foregroundStyle(Graphite.textSecondary).lineLimit(1)
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 10))
            } else {
                GridItemView(mediaItem: item, showsMetadata: item.type == .video)
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open(item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.fileName)
        .accessibilityIdentifier("library.all.item")
    }

    private func open(_ item: MediaItem) {
        let session = authViewModel.librarySessionID
        switch item.type {
        case .photo:
            presented = Presented(photo: PhotoDetailView(photo: item, allPhotos: photos, sessionID: session), video: nil)
        case .video:
            presented = Presented(photo: nil, video: VideoPlayerView(video: item, sessionID: session))
        default:
            showAudio()
        }
    }
}

/// The Albums tab. Album protection, unlock and moves are unchanged; only the entry point moved.
struct AlbumsTabView: View {
    var body: some View {
        NavigationStack {
            AlbumBrowserView()
                .background(Graphite.base)
        }
    }
}
