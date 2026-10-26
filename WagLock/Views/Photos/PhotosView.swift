//
//  PhotosView.swift
//  WagLock
//
//  Photos view
//  Grid of all images with preview, zoom, search and batch selection
//

import SwiftData
import SwiftUI

struct PhotosView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    // Query only image media
    @Query(
        filter: #Predicate<MediaItem> { item in
            item.typeRawValue == "photo"
        },
        sort: \MediaItem.createdAt,
        order: .reverse
    )
    private var photos: [MediaItem]

    // MARK: - State

    @StateObject private var settings = AppSettings.shared
    @StateObject private var viewModel = PhotosViewModel()
    @EnvironmentObject private var guestModeManager: GuestModeManager
    @State private var showImportView = false
    @State private var showExportView = false
    private struct PhotoSelection: Identifiable {
        let id = UUID()
        let view: PhotoDetailView
    }
    @State private var selectedPhoto: PhotoSelection?
    @State private var photoToDelete: MediaItem?
    @State private var deleteErrorMessage: String?
    @State private var searchText = ""
    @State private var isSelectionMode = false
    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var batchPhotosToDelete: [MediaItem] = []
    @State private var showBatchDeleteConfirmation = false

    // MARK: - Constants

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: settings.gridColumns)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(guestModeManager.isGuestMode ? 0 : photos.count) photos · On this device")
                        .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    WagLockSearchField(title: "Search photos", text: $searchText)
                    if guestModeManager.isOwnerMode {
                        NavigationLink { AlbumBrowserView() } label: {
                            HStack(spacing: 0) {
                                WagLockNavigationRow(symbol: "rectangle.stack", title: "Albums", detail: "Organize with separate protection")
                                Image(systemName: "chevron.right").font(.footnote)
                                    .foregroundStyle(ColorTheme.secondaryText).padding(.trailing, 14)
                            }.background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
                        }.accessibilityIdentifier("photos.albums")
                    }
                }.padding(.horizontal, 24)
                ZStack {
                // Always show the empty state in guest mode
                if guestModeManager.isGuestMode || photos.isEmpty {
                    emptyStateView
                } else if filteredPhotos.isEmpty {
                    searchEmptyView
                } else {
                    photoGridView
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(ColorTheme.primaryBackground)
            .navigationTitle(String(localized: "photos.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelectionMode && !filteredPhotos.isEmpty {
                        selectAllButton
                    } else if !photos.isEmpty {
                        Button {
                            showExportView = true
                        } label: {
                            Label(
                                String(localized: "photos.export"),
                                systemImage: "square.and.arrow.up")
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSelectionMode {
                        cancelButton
                    } else if guestModeManager.isOwnerMode {
                        HStack(spacing: 16) {
                            if !photos.isEmpty {
                                selectButton
                            }
                            Button {
                                showImportView = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .accessibilityLabel("Import photos and files")
                            .accessibilityIdentifier("photos.import")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectionMode && !selectedPhotoIDs.isEmpty {
                    batchActionsToolbar
                }
            }
            .sheet(isPresented: $showImportView) {
                ImportButtonsView(onImportComplete: { items in
                })
                .environment(\.modelContext, modelContext)
                .environmentObject(authViewModel)
            }
            .sheet(isPresented: $showExportView) {
                BatchExportView(initialSelection: isSelectionMode ? selectedPhotoIDs : [])
                    .environment(\.modelContext, modelContext)
                    .environmentObject(authViewModel)
            }
            .fullScreenCover(item: $selectedPhoto) { photo in
                photo.view
                    .environmentObject(authViewModel)
            }
            .alert(
                String(localized: "photo.delete.confirmTitle"),
                isPresented: Binding(
                    get: { photoToDelete != nil },
                    set: { if !$0 { photoToDelete = nil } }
                ),
                presenting: photoToDelete
            ) { photo in
                Button(String(localized: "common.delete"), role: .destructive) {
                    deletePhoto(photo)
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: { _ in
                Text(String(localized: "photo.delete.confirmMessage"))
            }
            .alert(
                String(localized: "photo.delete.confirmTitle"),
                isPresented: $showBatchDeleteConfirmation
            ) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    deletePhotos(batchPhotosToDelete)
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(
                    String(
                        format: String(localized: "photos.delete.multipleMessage"),
                        batchPhotosToDelete.count))
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
            .onChange(of: searchText) { _, _ in
                // Clear the selection when the search changes so "N selected" always matches the visible results
                selectedPhotoIDs.removeAll()
            }

        }
    }

    // Missing ciphertext is an explicit read/recovery error. Never delete
    // library records automatically or inspect dismissed models in a late task.

    // MARK: - Empty State

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 24) {
                WagLockEmptyState(symbol: "photo", title: "Make room for your memories.", detail: "Add a few photos to get started. Your originals stay in your photo library.")
                if guestModeManager.isOwnerMode {
                    Button("Add photos") { showImportView = true }
                        .buttonStyle(WagLockPrimaryButtonStyle()).padding(.horizontal, 24)
                }
            }.padding(.vertical, 48)
        }
    }

    // MARK: - Search Empty State

    private var searchEmptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text(String(localized: "photos.search.noResults"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Photo Grid

    private struct PhotoDay: Identifiable {
        let date: Date?
        let items: [MediaItem]
        var id: Date { date ?? .distantPast }
        var title: String {
            guard let date else { return "ALL PHOTOS" }
            let formatted = date.formatted(.dateTime.month(.wide).day().year()).uppercased()
            return Calendar.current.isDateInToday(date) ? "TODAY · " + formatted : formatted
        }
    }

    private var photoDays: [PhotoDay] {
        let items = filteredPhotos
        guard settings.sortOrder == .dateNewest || settings.sortOrder == .dateOldest else {
            return [PhotoDay(date: nil, items: items)]
        }
        let groups = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.createdAt) }
        let dates = groups.keys.sorted { settings.sortOrder == .dateNewest ? $0 > $1 : $0 < $1 }
        return dates.map { PhotoDay(date: $0, items: groups[$0] ?? []) }
    }

    private var photoGridView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(photoDays) { day in
                    Text(day.title).font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(day.items) { photo in
                            photoTile(photo)
                        }
                    }
                }
            }.padding(.horizontal, 24).padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func photoTile(_ photo: MediaItem) -> some View {
                    if isSelectionMode {
                        // Selection mode: tap toggles selection
                        Button {
                            toggleSelection(for: photo)
                        } label: {
                            GridItemView(
                                mediaItem: photo,
                                isSelectionMode: true,
                                isSelected: selectedPhotoIDs.contains(photo.id),
                                showsMetadata: false
                            )
                            .aspectRatio(1, contentMode: .fill)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Normal mode: tap to preview
                        GridItemView(mediaItem: photo, showsMetadata: false)
                            .aspectRatio(1, contentMode: .fill)
                            .onTapGesture {
                                selectedPhoto = PhotoSelection(view: PhotoDetailView(photo: photo, allPhotos: filteredPhotos, sessionID: authViewModel.librarySessionID))
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("photos.preview")
                            .accessibilityLabel(photo.fileName)
                            .contextMenu {
                                Button(role: .destructive) {
                                    photoToDelete = photo
                                } label: {
                                    Label(
                                        String(localized: "common.delete"),
                                        systemImage: "trash")
                                }
                            }
                    }
    }

    // MARK: - Toolbar Items

    private var selectButton: some View {
        Button {
            isSelectionMode = true
        } label: {
            Text(String(localized: "common.select"))
        }
    }

    private var selectAllButton: some View {
        Button {
            if selectedPhotoIDs.count == filteredPhotos.count {
                selectedPhotoIDs.removeAll()
            } else {
                selectedPhotoIDs = Set(filteredPhotos.map { $0.id })
            }
        } label: {
            Text(
                selectedPhotoIDs.count == filteredPhotos.count
                    ? String(localized: "export.deselectAll")
                    : String(localized: "common.selectAll"))
        }
    }

    private var cancelButton: some View {
        Button {
            isSelectionMode = false
            selectedPhotoIDs.removeAll()
        } label: {
            Text(String(localized: "common.cancel"))
        }
    }

    // MARK: - Batch Actions Toolbar

    private var batchActionsToolbar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 20) {
                Text(
                    String(
                        format: String(localized: "gallery.selectedCount"),
                        selectedPhotoIDs.count)
                )
                .font(.subheadline)
                .foregroundColor(.secondary)

                Spacer()

                Button { showExportView = true } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }.accessibilityIdentifier("photos.exportSelection")

                Button(role: .destructive) {
                    batchPhotosToDelete = filteredPhotos.filter {
                        selectedPhotoIDs.contains($0.id)
                    }
                    showBatchDeleteConfirmation = true
                } label: {
                    Label(String(localized: "common.delete"), systemImage: "trash")
                        .font(.subheadline)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Computed Properties

    /// Photos filtered by the search text
    private var filteredPhotos: [MediaItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = photos.sorted(using: settings.sortOrder.sortDescriptor)
        guard !query.isEmpty else { return sorted }

        return sorted.filter { item in
            item.fileName.localizedCaseInsensitiveContains(query)
                || item.fileExtension.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Methods

    private func toggleSelection(for photo: MediaItem) {
        if selectedPhotoIDs.contains(photo.id) {
            selectedPhotoIDs.remove(photo.id)
        } else {
            selectedPhotoIDs.insert(photo.id)
        }
    }

    private func deletePhoto(_ photo: MediaItem) {
        let encryptedPath = photo.encryptedPath

        // Commit the database deletion first and delete files only after it succeeds,
        // so a failed save never leaves records pointing at deleted files
        modelContext.delete(photo)
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
            // The record is gone; a failed file delete only leaves an unreferenced encrypted file
        }
    }

    /// Batch delete the selected photos
    private func deletePhotos(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }

        let encryptedPaths = items.map { $0.encryptedPath }

        // Commit the database deletion first and delete files only after it succeeds,
        // so a failed save never leaves records pointing at deleted files
        for item in items {
            modelContext.delete(item)
        }
        do {
            try LibraryWriteCoordinator.save(modelContext)
        } catch {
            modelContext.rollback()
            deleteErrorMessage = String(
                format: String(localized: "gallery.error.deleteFailed"),
                error.localizedDescription)
            return
        }

        for path in encryptedPaths {
            do {
                try vaultServices.storage.deleteFile(path: path)
            } catch {
                // The record is gone; a failed file delete only leaves an unreferenced encrypted file
            }
        }

        // Leave selection mode and clear the selection
        isSelectionMode = false
        selectedPhotoIDs.removeAll()
        batchPhotosToDelete = []
        showBatchDeleteConfirmation = false
    }
}

// MARK: - Photo Thumbnail View

struct PhotoThumbnailView: View {
    let photo: MediaItem

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay {
                // TODO: load the real thumbnail
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            }
            .clipped()
    }
}

// MARK: - Preview

#Preview {
    PhotosView()
        .modelContainer(for: MediaItem.self, inMemory: true)
        .environmentObject(AuthenticationViewModel())
}
