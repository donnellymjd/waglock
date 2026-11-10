import SwiftData
import SwiftUI

// Graphite controls shared by the Library, viewers, albums, notes and files screens.

/// 44 pt round icon button on surface/input (Close, Search, Export, More).
struct WagLockRoundButton: View {
    let symbol: String
    let label: String
    var prominent = false
    var onMedia = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(prominent ? Graphite.onAccent : Graphite.textPrimary)
                .frame(width: 44, height: 44)
                .background(prominent ? AnyShapeStyle(Graphite.accentGradient)
                            : onMedia ? AnyShapeStyle(Color.black.opacity(0.45)) : AnyShapeStyle(Graphite.input),
                            in: Circle())
        }
        .accessibilityLabel(label)
    }
}

/// Filter chip. Selected chips are filled; others are outlined.
struct WagLockChip: View {
    let title: String
    var count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(selected ? WagLockFonts.poppins(13, .semibold, relativeTo: .footnote)
                                 : WagLockFonts.poppins(13, .medium, relativeTo: .footnote))
                if let count {
                    Text("\(count)").font(.wlMeta).opacity(0.7)
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 40)
            .foregroundStyle(selected ? Graphite.base : Color(hex: 0xC9CFDB))
            .background(selected ? Graphite.textPrimary : .clear, in: Capsule())
            .overlay(Capsule().stroke(selected ? .clear : Graphite.line, lineWidth: 1))
        }
        .frame(minHeight: 44)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One action in a viewer or selection toolbar.
struct WagLockAction: Identifiable {
    let id: String
    let symbol: String
    let title: String
    var destructive = false
    var enabled = true
    let perform: () -> Void
}

/// Rounded toolbar (radius 24). Horizontal by default; a vertical side rail in landscape.
struct WagLockActionBar: View {
    let actions: [WagLockAction]
    var vertical = false

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            ForEach(actions) { action in
                Button(action: action.perform) {
                    VStack(spacing: 4) {
                        Image(systemName: action.symbol).font(.system(size: 19))
                        Text(action.title).font(WagLockFonts.poppins(11, .medium, relativeTo: .caption2))
                    }
                    .foregroundStyle(action.destructive ? Graphite.danger : Graphite.textPrimary)
                    .frame(maxWidth: vertical ? nil : .infinity, minHeight: 52)
                    .frame(width: vertical ? 64 : nil)
                    .contentShape(Rectangle())
                }
                .disabled(!action.enabled)
                .opacity(action.enabled ? 1 : 0.45)
                .accessibilityIdentifier(action.id)
            }
        }
        .padding(6)
        .background(Graphite.bar.opacity(0.96), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Graphite.line.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }
}

/// Backup health strip for the Library header. Shows only this library's backup state.
struct WagLockBackupBanner: View {
    @EnvironmentObject private var reminders: BackupReminderStore
    let open: () -> Void

    var body: some View {
        let last = reminders.lastSaved
        let due = reminders.nextReminder.map { $0 <= Date() } ?? (last == nil)
        if due {
            HStack(spacing: 12) {
                Image(systemName: "icloud.and.arrow.up").foregroundStyle(Graphite.warn).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(last == nil ? "Not backed up yet" : "Backup due").font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary)
                    Text(last.map { "Last backup " + $0.formatted(.relative(presentation: .named)) } ?? "There’s no passcode reset, so a backup is your way back")
                        .font(.wlMeta).foregroundStyle(Graphite.textMuted).lineLimit(2)
                }
                Spacer(minLength: 0)
                Button("Back up", action: open)
                    .font(WagLockFonts.poppins(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Graphite.accentText).frame(minHeight: 44)
                    .accessibilityIdentifier("library.backup")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Graphite.warnTint, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// Moves Library items into an unlocked album. Each move is encrypted and verified in the
/// album before the original record is removed (AlbumStore.moveFromLibrary).
struct MoveToAlbumSheet: View {
    let items: [MediaItem]
    var onFinished: () -> Void = {}
    @Query(sort: \VaultAlbum.createdAt, order: .reverse) private var albums: [VaultAlbum]
    @EnvironmentObject private var store: AlbumStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var moved = 0
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WagLockSheetHeader(title: "Move to album") { dismiss() }
            Text("\(items.count) item\(items.count == 1 ? "" : "s") selected. Each one is encrypted into the album and checked before it leaves your Library.")
                .font(.wlMeta).foregroundStyle(Graphite.textMuted)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(albums) { album in
                        let open = store.isUnlocked(album, albums: albums)
                        Button { move(into: album) } label: {
                            WagLockRow(symbol: open ? "rectangle.stack" : "lock", title: album.name,
                                       detail: open ? "Open" : "Locked · Unlock it in Albums first", showsChevron: open)
                        }
                        .buttonStyle(.plain).disabled(!open || busy).opacity(open ? 1 : 0.6)
                    }
                    if albums.isEmpty {
                        Text("No albums yet. Create one in the Albums tab.").font(.wlBody).foregroundStyle(Graphite.textMuted)
                    }
                }
            }
            if busy { ProgressView("Moving \(moved + 1) of \(items.count)…").tint(Graphite.accentText).font(.wlMeta) }
            if let error { WagLockNote(kind: .error, text: error) }
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
        .background(Graphite.base)
        .interactiveDismissDisabled(busy)
    }

    private func move(into album: VaultAlbum) {
        guard !busy else { return }
        busy = true; error = nil; moved = 0
        let pending = items
        Task {
            defer { busy = false }
            for item in pending {
                guard store.isUnlocked(album, albums: albums) else {
                    error = "The album locked before every item moved. Items not moved are still in your Library."; return
                }
                do { try await store.moveFromLibrary(item, into: album, albums: albums, context: context); moved += 1 }
                catch { self.error = "Not every item moved. Items not moved are still in your Library."; return }
            }
            onFinished()
            dismiss()
        }
    }
}
