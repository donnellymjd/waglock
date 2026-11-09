import SwiftData
import SwiftUI

/// The Library tab: photos, videos and audio behind one set of filter chips.
/// Each filter reuses the existing screen, so selection, export, import, playback and
/// deletion keep their audited session checks. Counts are this library's only.
struct LibraryView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case photos = "Photos", videos = "Videos", audio = "Audio"
        var id: String { rawValue }
    }

    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @EnvironmentObject private var guestModeManager: GuestModeManager
    @Query(filter: #Predicate<MediaItem> { $0.typeRawValue == "photo" }) private var photos: [MediaItem]
    @Query(filter: #Predicate<MediaItem> { $0.typeRawValue == "video" }) private var videos: [MediaItem]
    @Query(filter: #Predicate<MediaItem> { $0.typeRawValue == "audio" }) private var audio: [MediaItem]
    @State private var filter: Filter = .photos

    private var total: Int { guestModeManager.isGuestMode ? 0 : photos.count + videos.count + audio.count }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    WagLockTitle(text: "Library")
                    Text("\(total) item\(total == 1 ? "" : "s") · On this device")
                        .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { option in chip(option) }
                    }
                }
                .accessibilityElement(children: .contain).accessibilityLabel("Show")
            }
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                switch filter {
                case .photos:
                    PhotosView(showsTitle: false).environmentObject(authViewModel)
                case .videos:
                    NavigationStack {
                        VideosView().environmentObject(authViewModel)
                            .background(Graphite.base)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                case .audio:
                    NavigationStack {
                        AudioView().background(Graphite.base)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Graphite.base)
    }

    private func count(_ option: Filter) -> Int {
        guard !guestModeManager.isGuestMode else { return 0 }
        switch option {
        case .photos: return photos.count
        case .videos: return videos.count
        case .audio: return audio.count
        }
    }

    private func chip(_ option: Filter) -> some View {
        let selected = filter == option
        return Button { filter = option } label: {
            HStack(spacing: 6) {
                Text(option.rawValue).font(selected ? .wlBodyStrong : WagLockFonts.poppins(14, .medium, relativeTo: .body))
                Text("\(count(option))").font(.wlMeta)
                    .foregroundStyle(selected ? Graphite.onAccent.opacity(0.75) : Graphite.textMuted)
            }
            .padding(.horizontal, 14).frame(minHeight: 36)
            .foregroundStyle(selected ? Graphite.onAccent : Graphite.textPrimary)
            .background(selected ? AnyShapeStyle(Graphite.accentGradient) : AnyShapeStyle(Graphite.surface1),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? .clear : Graphite.line, lineWidth: 1))
        }
        .frame(minHeight: 44)
        .accessibilityLabel("\(option.rawValue), \(count(option))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("library.filter." + option.rawValue.lowercased())
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
