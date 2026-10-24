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
        .navigationTitle(parent?.name ?? "Albums")
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
                            Button("Move from Main Library", systemImage: "photo.stack") { showLibrary = true }
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
        List {
            if parent == nil {
                Section {
                    WagLockInfoCard(title: "A place for everything", detail: "Choose separate protection for each album. Album names remain visible.")
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            if busy { ProgressView("Encrypting import…") }
            Section(parent == nil ? "Albums" : "Subalbums") {
                ForEach(children) { album in
                    NavigationLink {
                        AlbumBrowserView(parent: album)
                    } label: {
                        WagLockNavigationRow(
                            symbol: store.isUnlocked(album, albums: albums) ? "folder" : "lock",
                            title: album.name,
                            detail: (store.isUnlocked(album, albums: albums) ? "" : "Locked · ") + (AlbumProtection(rawValue: album.protectionRawValue)?.title ?? "Unavailable"))
                    }.wagLockCardRow()
                }
                if children.isEmpty {
                    Text(parent == nil ? "Create your first album." : "No subalbums yet.").foregroundStyle(.secondary)
                }
                Button(parent == nil ? "New Album" : "New Subalbum") { showCreate = true }
                    .accessibilityIdentifier(parent == nil ? "album.create.footer" : "album.create")
            }
            if parent != nil {
                Section("Photos, Videos & Files") {
                    if assets.isEmpty { Text("Import media into this album.").foregroundStyle(.secondary) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(assets) { asset in
                            Button { selectedAsset = asset } label: {
                                GeometryReader { proxy in
                                    ZStack {
                                        ColorTheme.tertiaryBackground
                                        if let data = asset.thumbnail, let image = UIImage(data: data) {
                                            if asset.type == .video {
                                                VideoThumbnailImage(image: image)
                                            } else {
                                                Image(uiImage: image).resizable().scaledToFill()
                                                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                                            }
                                        } else {
                                            VStack(spacing: 8) {
                                                Image(systemName: asset.type.iconName).font(.title2)
                                                Text(asset.fileName).font(.caption).lineLimit(2)
                                            }.padding(8).foregroundStyle(ColorTheme.primaryText)
                                        }
                                    }.clipShape(RoundedRectangle(cornerRadius: 12))
                                }.aspectRatio(1, contentMode: .fit)
                            }.buttonStyle(.plain).accessibilityLabel(asset.fileName)
                                .accessibilityIdentifier("album.asset")
                                .contextMenu { Button("Delete", role: .destructive) { assetToDelete = asset } }
                        }
                    }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    Button("Import Photos & Videos") { showPhotos = true }
                    Button("Import from Files") { showFiles = true }
                    Button("Move from Main Library") { showLibrary = true }
                }
            }
        }
        .wagLockList()
        .disabled(busy)
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
                    Text("The destination is encrypted and verified before the original is removed from the main library. Existing database journals may retain old metadata until later cleanup.")
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
                if media.isEmpty { Text("No media in the main library.") }
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
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    private var protection: AlbumProtection? { AlbumProtection(rawValue: album.protectionRawValue) }

    var body: some View {
        Form {
            Section {
                Label("Album Locked", systemImage: "lock.shield")
                if protection?.requiresPassword == true {
                    PasswordKeyboardPicker(selection: Binding(get: { PasswordKeyboard(rawValue: keyboardRaw) ?? .numberPad }, set: { keyboardRaw = $0.rawValue }))
                    SwitchablePasswordField(title: "Album password", text: $password,
                        keyboard: PasswordKeyboard(rawValue: keyboardRaw) ?? .numberPad,
                        identifier: "album.unlock.password", submitTitle: "Unlock Album") {
                            if !password.isEmpty && !busy { unlock(biometric: false) }
                        }.frame(minHeight: 30).disabled(busy)
                    Button("Unlock with Password") { unlock(biometric: false) }
                        .disabled(password.isEmpty || busy)
                }
                if protection?.usesBiometrics == true {
                    Button("Unlock with Face ID", systemImage: "faceid") { unlock(biometric: true) }
                        .disabled(busy)
                }
                if protection == .inherited {
                    Text("This album inherits its parent’s protection.")
                    Button("Open Album") { unlock(biometric: false) }.disabled(busy)
                        .accessibilityIdentifier("album.unlock.inherited")
                }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
            }
        }.wagLockList()
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
        NavigationStack {
            Form {
                if editing == nil {
                    Section("Album") {
                        TextField("Album name", text: $name).accessibilityIdentifier("album.name")
                        if let parent { Text("Inside: \(parent.name)").font(.caption) }
                    }
                }
                Section("Security") {
                    Picker("Protection", selection: $protection) {
                        ForEach(AlbumProtection.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("album.protection")
                    if protection.requiresPassword {
                        SecureField("New album password (6+ characters)", text: $password)
                            .accessibilityIdentifier("album.password")
                        SecureField("Confirm album password", text: $confirmation)
                            .accessibilityIdentifier("album.password.confirm")
                    }
                    Text("Parent protection always applies. Album contents, filenames and thumbnails are encrypted separately; album names and hierarchy remain visible.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if protection == .faceIDOnly {
                        Text("Face ID-only albums have no album-password fallback. Resetting Face ID, removing the device passcode, losing the device or losing its Keychain entry can permanently lock the contents. Portable recovery is not implemented yet.")
                            .font(.footnote)
                        Toggle("I understand this album is device-bound", isOn: $acknowledgeDeviceBound)
                    }
                    if protection.usesBiometrics {
                        Text("Face ID must be available and enrolled. Cancelling authentication leaves the album unchanged.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if busy { ProgressView() }
            }
            .wagLockList()
            .navigationTitle(editing == nil ? "New Album" : "Album Security")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave || busy)
                        .accessibilityIdentifier("album.save")
                }
            }
            .interactiveDismissDisabled(busy)
            .onDisappear { password = ""; confirmation = "" }
            .onAppear {
                if let editing, let mode = AlbumProtection(rawValue: editing.protectionRawValue) {
                    protection = mode
                }
            }
        }
    }

    private var canSave: Bool {
        (editing != nil || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (!protection.requiresPassword || (password.count >= 6 && password == confirmation))
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
