import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AlbumBrowserView: View {
    var parent: VaultAlbum? = nil
    @Query(sort: \VaultAlbum.createdAt, order: .reverse) private var albums: [VaultAlbum]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var guest: GuestModeManager
    @EnvironmentObject private var store: AlbumStore
    @State private var showCreate = false
    @State private var showSecurity = false
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var showLibrary = false
    @State private var selectedAsset: AlbumAsset?
    @State private var busy = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @State private var showRename = false
    @State private var newName = ""
    @State private var showDeleteAlbum = false
    @State private var assetToDelete: AlbumAsset?

    private var canAccess: Bool {
        guest.isOwnerMode && (parent.map { store.isUnlocked($0, albums: albums) } ?? true)
    }
    private var children: [VaultAlbum] { albums.filter { $0.parentID == parent?.id } }
    private var assets: [AlbumAsset] {
        guard canAccess, let parent else { return [] }
        return (try? store.assets(in: parent, albums: albums)) ?? []
    }

    var body: some View {
        Group {
            if !guest.isOwnerMode {
                ContentUnavailableView("Albums are locked", systemImage: "lock")
            } else if let parent, !canAccess {
                AlbumUnlockView(album: parent, albums: albums)
            } else {
                albumContents
            }
        }
        .navigationTitle(parent == nil ? "" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canAccess && parent == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New") { showCreate = true }.disabled(busy)
                        .accessibilityIdentifier("album.create")
                }
            } else if canAccess {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(parent == nil ? "New Album" : "New Subalbum", systemImage: "folder.badge.plus") {
                            showCreate = true
                        }
                        if let parent {
                            Button("Import Photos & Videos", systemImage: "photo.on.rectangle") { showPhotos = true }
                            Button("Import from Files", systemImage: "doc.badge.plus") { showFiles = true }
                            Button("Move from Library", systemImage: "photo.stack") { showLibrary = true }
                            Button("Album Security", systemImage: "lock.shield") { showSecurity = true }
                            Button("Rename Album", systemImage: "pencil") {
                                newName = parent.name
                                showRename = true
                            }
                            Button("Lock Album", systemImage: "lock") { store.lock(parent, albums: albums) }
                            Button("Delete Empty Album", systemImage: "trash", role: .destructive) { showDeleteAlbum = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("album.actions")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            AlbumConfigurationView(parent: parent, albums: albums)
        }
        .sheet(isPresented: $showSecurity) {
            if let parent { AlbumConfigurationView(parent: nil, editing: parent, albums: albums) }
        }
        .sheet(isPresented: $showPhotos) {
            PhotoPickerRepresentable(isPresented: $showPhotos) { results in importPhotos(results) }
        }
        .sheet(isPresented: $showFiles) {
            DocumentPickerRepresentable(isPresented: $showFiles, contentTypes: [.item], allowsMultipleSelection: true) {
                importURLs($0)
            }
        }
        .sheet(isPresented: $showLibrary) {
            if let parent { AlbumLibraryMoveView(album: parent, albums: albums) }
        }
        .sheet(item: $selectedAsset) { asset in
            if let parent {
                AlbumPreviewView(asset: asset, album: parent, albums: albums)
            }
        }
        .onChange(of: store.revision) { _, _ in
            if !canAccess {
                operation?.cancel()
                showCreate = false
                showSecurity = false
                showPhotos = false
                showFiles = false
                showLibrary = false
                selectedAsset = nil
            }
        }
        .onDisappear { operation?.cancel() }
        .alert("Rename Album", isPresented: $showRename) {
            TextField("Album name", text: $newName)
            Button("Save") {
                if let parent {
                    do { try store.rename(parent, name: newName, albums: albums, context: context) }
                    catch { self.error = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this empty album?", isPresented: $showDeleteAlbum, titleVisibility: .visible) {
            Button("Delete Album", role: .destructive) {
                if let parent {
                    do { try store.deleteEmpty(parent, albums: albums, context: context); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .confirmationDialog("Delete this item?", isPresented: Binding(
            get: { assetToDelete != nil }, set: { if !$0 { assetToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Item", role: .destructive) {
                if let asset = assetToDelete, let parent {
                    do { try store.delete(asset, from: parent, albums: albums, context: context) }
                    catch { self.error = error.localizedDescription }
                }
                assetToDelete = nil
            }
        }
        .alert("Album", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var albumContents: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let parent { albumHeader(parent) } else { rootHeader }
                if busy { ProgressView("Encrypting import…").tint(Graphite.accentText).font(.wlMeta) }
                if parent != nil {
                    if assets.isEmpty {
                        WagLockNote(kind: .info, text: "Import media into this album. Its contents, filenames and thumbnails are encrypted separately.")
                    } else {
                        assetGrid
                    }
                    WagLockSectionLabel("Subalbums").padding(.top, 4)
                }
                albumGrid
                if parent != nil {
                    Menu {
                        Button("Import Photos & Videos", systemImage: "photo.on.rectangle") { showPhotos = true }
                        Button("Import from Files", systemImage: "doc.badge.plus") { showFiles = true }
                        Button("Move from Library", systemImage: "photo.stack") { showLibrary = true }
                    } label: {
                        Text("Add to album").font(.wlButton).tracking(3.3).textCase(.uppercase)
                            .frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(Graphite.onAccent)
                            .background(Graphite.accentGradient, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityIdentifier("album.add")
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .background(Graphite.base)
        .disabled(busy)
    }

    private var rootHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            WagLockTitle(text: "Albums")
            Text("Choose protection for each album. Album names remain visible.")
                .font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textMuted)
        }
    }

    private func albumHeader(_ album: VaultAlbum) -> some View {
        let protection = AlbumProtection(rawValue: album.protectionRawValue)
        let photosCount = assets.filter { $0.type == .photo }.count
        let videoCount = assets.filter { $0.type == .video }.count
        let parts = [photosCount > 0 ? "\(photosCount) photo\(photosCount == 1 ? "" : "s")" : nil,
                     videoCount > 0 ? "\(videoCount) video\(videoCount == 1 ? "" : "s")" : nil].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                WagLockTitle(text: album.name, size: .display)
                Text("\(assets.count) item\(assets.count == 1 ? "" : "s")" + (parts.isEmpty ? "" : " · " + parts.joined(separator: ", ")))
                    .font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textSecondary)
            }
            HStack(spacing: 8) {
                Label(protection == .inherited ? "Inherits parent" : protection?.title ?? "Unavailable", systemImage: "shield")
                    .font(WagLockFonts.poppins(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(Color(hex: 0xB8D6FF)).padding(.horizontal, 12).frame(minHeight: 30)
                    .background(Graphite.accentText.opacity(0.14), in: Capsule())
                if protection == .inherited {
                    Text("Opens with this library").font(WagLockFonts.poppins(12, .medium, relativeTo: .caption))
                        .foregroundStyle(Graphite.textSecondary).padding(.horizontal, 12).frame(minHeight: 30)
                        .background(Graphite.surface1, in: Capsule())
                }
            }
        }
    }

    private var assetGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(assets) { asset in
                Button { selectedAsset = asset } label: {
                    GeometryReader { proxy in
                        ZStack {
                            Graphite.surface2
                            if let data = asset.thumbnail, let image = UIImage(data: data) {
                                if asset.type == .video {
                                    VideoThumbnailImage(image: image)
                                } else {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                                }
                            } else {
                                VStack(spacing: 6) {
                                    Image(systemName: asset.type.iconName).font(.title3)
                                    Text(asset.fileName).font(.wlMeta).lineLimit(2)
                                }.padding(6).foregroundStyle(Graphite.textPrimary)
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 10))
                    }.aspectRatio(1, contentMode: .fit)
                }.buttonStyle(.plain).accessibilityLabel(asset.fileName)
                    .accessibilityIdentifier("album.asset")
                    .contextMenu { Button("Delete", role: .destructive) { assetToDelete = asset } }
            }
        }
    }

    private var albumGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            ForEach(children) { album in
                let open = store.isUnlocked(album, albums: albums)
                let protection = AlbumProtection(rawValue: album.protectionRawValue)
                NavigationLink { AlbumBrowserView(parent: album) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: open ? "rectangle.stack" : "lock").font(.system(size: 20))
                                .foregroundStyle(Graphite.accentText)
                                .frame(width: 40, height: 40).background(Graphite.surface2, in: RoundedRectangle(cornerRadius: 11))
                            Spacer()
                            Text(open ? "OPEN" : "LOCKED").font(WagLockFonts.poppins(10, .semibold, relativeTo: .caption2))
                                .tracking(1.2).foregroundStyle(open ? Graphite.accentText : Graphite.textMuted)
                        }
                        Spacer(minLength: 0)
                        Text(album.name).font(.wlHeading).foregroundStyle(Graphite.textPrimary).lineLimit(2)
                        Text((open ? "Open · " : "Locked · ") + (protection == .inherited ? "Inherits parent" : protection?.title ?? "Unavailable"))
                            .font(.wlMeta).foregroundStyle(Graphite.textMuted).lineLimit(2)
                    }
                    .padding(14).frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                    .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(album.name + (open ? ", open" : ", locked"))
                .accessibilityIdentifier(album.name)
            }
            Button { showCreate = true } label: {
                VStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(Graphite.accentText)
                        .frame(width: 40, height: 40).background(Graphite.accentTint, in: RoundedRectangle(cornerRadius: 11))
                    Text(parent == nil ? "New album" : "New subalbum").font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Graphite.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(parent == nil ? "album.create.footer" : "album.create")
        }
    }

    private func importURLs(_ urls: [URL]) {
        guard let parent, canAccess, !busy else { return }
        busy = true
        operation = Task {
            defer { busy = false }
            do {
                for url in urls {
                    try Task.checkCancellation()
                    try await store.importFile(url, into: parent, albums: albums, context: context)
                }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }

    private func importPhotos(_ results: [PHPickerResult]) {
        guard let parent, canAccess, !busy else { return }
        busy = true
        operation = Task {
            defer { busy = false }
            do {
                for result in results {
                    try Task.checkCancellation()
                    let url = try await AlbumPhotoTransfer.copyFile(from: result.itemProvider)
                    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                    try Task.checkCancellation()
                    try await store.importFile(url, into: parent, albums: albums, context: context)
                }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}

private struct AlbumLibraryMoveView: View {
    let album: VaultAlbum
    let albums: [VaultAlbum]
    @Query(sort: \MediaItem.createdAt, order: .reverse) private var media: [MediaItem]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AlbumStore
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The destination is encrypted and verified before the original is removed from the Library tab. Existing database journals may retain old metadata until later cleanup.")
                        .font(.footnote)
                }
                if busy { ProgressView("Moving…") }
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(media) { item in
                    Button {
                        busy = true
                        error = nil
                        Task {
                            defer { busy = false }
                            do {
                                try await store.moveFromLibrary(item, into: album, albums: albums, context: context)
                            } catch { self.error = error.localizedDescription }
                        }
                    } label: { Label(item.fullFileName, systemImage: item.type.iconName) }
                }
                if media.isEmpty { Text("No media outside albums.") }
            }
            .wagLockList()
            .disabled(busy)
            .navigationTitle("Move to \(album.name)")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
        }
        .onChange(of: store.revision) { _, _ in
            if !store.isUnlocked(album, albums: albums) { dismiss() }
        }
    }
}

struct AlbumUnlockView: View {
    let album: VaultAlbum
    let albums: [VaultAlbum]
    @EnvironmentObject private var store: AlbumStore
    @AppStorage(PasswordKeyboard.preferenceKey) private var keyboardRaw = PasswordKeyboard.numberPad.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    private var protection: AlbumProtection? { AlbumProtection(rawValue: album.protectionRawValue) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "lock").font(.system(size: 40)).foregroundStyle(Graphite.accentText)
                    .frame(width: 104, height: 104)
                    .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 30))
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(Graphite.accentText.opacity(0.25), lineWidth: 1))
                    .shadow(color: Graphite.accentStrong.opacity(0.28), radius: 40)
                    .accessibilityHidden(true).padding(.top, 40)
                VStack(spacing: 2) {
                    WagLockTitle(text: album.name)
                    Text(protection == .inherited ? "Inherits parent protection" : protection?.title ?? "Unavailable")
                        .font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textMuted)
                }
                if protection?.requiresPassword == true {
                    PasswordKeyboardPicker(selection: Binding(get: { PasswordKeyboard(rawValue: keyboardRaw) ?? .numberPad }, set: { keyboardRaw = $0.rawValue }))
                        .padding(.top, 12)
                    HStack(spacing: 12) {
                        Image(systemName: "key").foregroundStyle(Color(hex: 0xC9CFDB)).accessibilityHidden(true)
                        SwitchablePasswordField(title: "Album password", text: $password,
                            keyboard: PasswordKeyboard(rawValue: keyboardRaw) ?? .numberPad,
                            identifier: "album.unlock.password", submitTitle: "Unlock Album") {
                                if !password.isEmpty && !busy { unlock(biometric: false) }
                            }.frame(minHeight: 24).disabled(busy)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 54)
                    .background(Graphite.input, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(error == nil ? .clear : Graphite.dangerLine, lineWidth: 1.5))
                }
                HStack(spacing: 10) {
                    if protection?.requiresPassword == true {
                        Button("Unlock album") { unlock(biometric: false) }
                            .buttonStyle(WagLockPrimaryButtonStyle())
                            .disabled(password.isEmpty || busy)
                            .accessibilityIdentifier("album.unlock.submit")
                    } else if protection == .inherited {
                        Button("Open album") { unlock(biometric: false) }
                            .buttonStyle(WagLockPrimaryButtonStyle()).disabled(busy)
                            .accessibilityIdentifier("album.unlock.inherited")
                    } else if protection == .faceIDOnly {
                        Button("Unlock with Face ID") { unlock(biometric: true) }
                            .buttonStyle(WagLockPrimaryButtonStyle()).disabled(busy)
                            .accessibilityIdentifier("album.unlock.faceID")
                    }
                    if protection == .passwordAndFaceID {
                        Button { unlock(biometric: true) } label: {
                            Image(systemName: "faceid").font(.system(size: 22)).foregroundStyle(Graphite.accentText)
                                .frame(width: 54, height: 54)
                                .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Graphite.line, lineWidth: 1))
                        }
                        .disabled(busy).accessibilityLabel("Unlock with Face ID")
                        .accessibilityIdentifier("album.unlock.faceID")
                    }
                }
                if busy { ProgressView().tint(Graphite.accentText) }
                if let error { WagLockNote(kind: .error, text: error) }
                Label("Stays unlocked until you leave WagLock", systemImage: "timer")
                    .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                WagLockNote(kind: .info, text: "Contents, filenames and thumbnails stay encrypted until you unlock.")
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .background(Graphite.base)
        .onDisappear { password = "" }
        .onChange(of: scenePhase) { _, phase in if phase == .background { password = "" } }
    }

    private func unlock(biometric: Bool) {
        busy = true
        error = nil
        Task {
            defer { busy = false; password = "" }
            do { try await store.unlock(album, password: password, useBiometrics: biometric, albums: albums) }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct AlbumConfigurationView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext
    let parent: VaultAlbum?
    var editing: VaultAlbum? = nil
    let albums: [VaultAlbum]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var protection: AlbumProtection = .inherited
    @State private var password = ""
    @State private var confirmation = ""
    @State private var acknowledgeDeviceBound = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WagLockSheetHeader(title: editing == nil ? "New album" : "Album security") { dismiss() }
                .disabled(busy)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WagLockTitle(text: editing == nil ? "Name & protect" : editing?.name ?? "", size: .sheet)
                    if editing == nil {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.stack").foregroundStyle(Graphite.textSecondary).accessibilityHidden(true)
                            TextField("Album name", text: $name).font(WagLockFonts.poppins(16, .medium, relativeTo: .body))
                                .foregroundStyle(Graphite.textPrimary)
                                .accessibilityIdentifier("album.name")
                        }
                        .padding(.horizontal, 16).frame(minHeight: 54)
                        .background(Graphite.input, in: RoundedRectangle(cornerRadius: 12))
                        if let parent { Text("Inside: \(parent.name)").font(.wlMeta).foregroundStyle(Graphite.textMuted) }
                    }
                    WagLockSectionLabel("Protection")
                    VStack(spacing: 8) {
                        ForEach(AlbumProtection.allCases) { option in protectionRow(option) }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("album.protection")
                    if protection.requiresPassword {
                        SecureField("New album password (6+ characters)", text: $password)
                            .accessibilityIdentifier("album.password")
                            .textContentType(.newPassword)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .modifier(GraphiteFieldChrome())
                        SecureField("Confirm album password", text: $confirmation)
                            .accessibilityIdentifier("album.password.confirm")
                            .textContentType(.newPassword)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .modifier(GraphiteFieldChrome())
                    }
                    if protection == .faceIDOnly {
                        WagLockNote(kind: .caution, text: "Face ID-only albums have no album-password fallback. Resetting Face ID, removing the device passcode, losing the device or losing its Keychain entry can permanently lock the contents. Portable recovery is not implemented yet.")
                        Toggle("I understand this album is device-bound", isOn: $acknowledgeDeviceBound)
                            .font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary).tint(Graphite.accentStrong)
                    }
                    if protection.usesBiometrics {
                        Text("Face ID must be available and enrolled. Cancelling authentication leaves the album unchanged.")
                            .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                    }
                    WagLockNote(kind: .info, text: "Parent protection always applies. Album contents, filenames and thumbnails are encrypted separately; album names and hierarchy remain visible.")
                    if let error { WagLockNote(kind: .error, text: error) }
                }
            }
            Button(editing == nil ? "Create album" : "Save") { save() }
                .buttonStyle(WagLockPrimaryButtonStyle())
                .disabled(!canSave || busy)
                .accessibilityIdentifier("album.save")
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
        .background(Graphite.base)
        .interactiveDismissDisabled(busy)
        .onDisappear { password = ""; confirmation = "" }
        .onAppear {
            if let editing, let mode = AlbumProtection(rawValue: editing.protectionRawValue) {
                protection = mode
            }
        }
    }

    private func protectionRow(_ option: AlbumProtection) -> some View {
        let selected = protection == option
        let detail: String
        switch option {
        case .inherited: detail = "Opens with this library"
        case .password: detail = "A separate password for this album"
        case .passwordAndFaceID: detail = "Face ID, with the password as fallback"
        case .faceIDOnly: detail = "No album-password fallback"
        }
        return Button { protection = option } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20)).foregroundStyle(selected ? Graphite.accentText : Graphite.line)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title).font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary)
                    Text(detail).font(.wlMeta).foregroundStyle(Graphite.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Graphite.accentText.opacity(0.6) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(option.title)
    }

    private var canSave: Bool {
        (editing != nil || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (!protection.requiresPassword || (password.count >= 6 && PasswordText.matches(password, confirmation)))
            && (protection != .faceIDOnly || acknowledgeDeviceBound)
    }

    private func save() {
        busy = true
        error = nil
        Task {
            defer { busy = false; password = ""; confirmation = "" }
            do {
                if let editing {
                    try await vaultServices.albums.changeProtection(
                        of: editing, to: protection, password: password, albums: albums, context: context)
                } else {
                    _ = try await vaultServices.albums.create(name: name, parent: parent,
                        protection: protection, password: password, albums: albums, context: context)
                }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

enum AlbumPhotoTransfer {
    static func copyFile(from provider: NSItemProvider) async throws -> URL {
        guard let type = provider.registeredTypeIdentifiers.first(where: {
            guard let type = UTType($0) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .movie)
        }) else { throw VaultAccessError.invalidData }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? VaultAccessError.invalidData)
                    return
                }
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("WagLockAlbumImport-" + UUID().uuidString)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                        attributes: [.protectionKey: FileProtectionType.complete])
                    let destination = directory.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Input chrome for plain SwiftUI fields that must keep their own identifiers.
struct GraphiteFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(WagLockFonts.poppins(16, .medium, relativeTo: .body))
            .foregroundStyle(Graphite.textPrimary)
            .padding(.horizontal, 16).frame(minHeight: 54)
            .background(Graphite.input, in: RoundedRectangle(cornerRadius: 12))
    }
}
