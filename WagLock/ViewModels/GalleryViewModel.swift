//
//  GalleryViewModel.swift
//  WagLock
//
//  Gallery view model
//  Manages the media list, sorting, deletion and related actions
//

internal import Combine
import Foundation
import SwiftData
import SwiftUI

/// Gallery view model
@MainActor
class GalleryViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Whether loading is in progress
    @Published var isLoading: Bool = false

    /// Error message
    @Published var errorMessage: String?

    /// Whether to show the import view
    @Published var showImportView: Bool = false


    /// Media item pending deletion
    @Published var mediaItemToDelete: MediaItem?

    /// Whether to show the delete confirmation
    @Published var showDeleteConfirmation: Bool = false

    /// Sort order
    @Published var sortOrder: MediaItem.SortOrder {
        didSet {
            AppSettings.shared.sortOrder = sortOrder
        }
    }

    /// Whether to show sort options
    @Published var showSortOptions: Bool = false

    /// Whether batch selection mode is active
    @Published var isSelectionMode: Bool = false

    /// IDs of selected media items
    @Published var selectedItemIDs: Set<UUID> = []

    // MARK: - Properties

    var modelContext: ModelContext?

    private let storageService: FileStorageService
    private let encryptionService = EncryptionService.shared
    private let appSettings = AppSettings.shared

    // MARK: - Initialization

    init(storage: FileStorageService = .shared) {
        self.storageService = storage
        self.sortOrder = AppSettings.shared.sortOrder
    }

    // MARK: - Public Methods

    /// Delete a media item
    func deleteMediaItem(_ item: MediaItem) {
        mediaItemToDelete = item
        showDeleteConfirmation = true
    }

    /// Confirm deletion
    func confirmDelete() {
        guard let item = mediaItemToDelete, let context = modelContext else { return }

        Task {
            let encryptedPath = item.encryptedPath
            let fileName = item.fileName

            do {
                // Commit the database deletion first and delete files only after it succeeds,
                // so a failed save never leaves records pointing at deleted files
                context.delete(item)
                try LibraryWriteCoordinator.save(context)

                do {
                    try storageService.deleteFile(path: encryptedPath)
                } catch {
                    // The record is gone; a failed file delete only leaves an unreferenced encrypted file
                }


            } catch {
                modelContext?.rollback()
                errorMessage = String(
                    format: String(localized: "gallery.error.deleteFailed"),
                    error.localizedDescription)
            }

            mediaItemToDelete = nil
            showDeleteConfirmation = false
        }
    }

    /// Cancel deletion
    func cancelDelete() {
        mediaItemToDelete = nil
        showDeleteConfirmation = false
    }

    /// Show the import view
    func showImport() {
        showImportView = true
    }

    /// Toggle sort order
    func toggleSortOptions() {
        showSortOptions.toggle()
    }

    /// Change sort order
    func changeSortOrder(to newOrder: MediaItem.SortOrder) {
        sortOrder = newOrder
        showSortOptions = false
    }

    /// Batch delete
    func deleteMultipleItems(_ items: [MediaItem]) {
        guard let context = modelContext else { return }
        Task {
            // Commit the database deletion first and delete files only after it succeeds,
            // so a failed save never leaves records pointing at deleted files
            let encryptedPaths = items.map { $0.encryptedPath }
            for item in items {
                context.delete(item)
            }

            do {
                try LibraryWriteCoordinator.save(context)
            } catch {
                modelContext?.rollback()
                errorMessage = String(
                    format: String(localized: "gallery.error.deleteFailed"),
                    error.localizedDescription)
                return
            }

            var successCount = 0
            for path in encryptedPaths {
                do {
                    try storageService.deleteFile(path: path)
                    successCount += 1
                } catch {
                }
            }

        }
    }

    /// Get storage statistics
    func getStorageStatistics() -> FileStorageService.StorageStatistics {
        return storageService.getStorageStatistics()
    }

    // MARK: - Batch Selection Methods

    /// Toggle batch selection mode
    func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedItemIDs.removeAll()
        }
    }

    /// Toggle selection of one media item
    func toggleSelection(for item: MediaItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    /// Select all
    func selectAll(_ items: [MediaItem]) {
        selectedItemIDs = Set(items.map { $0.id })
    }

    /// Deselect all
    func deselectAll() {
        selectedItemIDs.removeAll()
    }

    /// Delete the selected media items
    func deleteSelectedItems(_ allItems: [MediaItem]) {
        let itemsToDelete = allItems.filter { selectedItemIDs.contains($0.id) }
        deleteMultipleItems(itemsToDelete)
        selectedItemIDs.removeAll()
        isSelectionMode = false
    }

}

// MARK: - Filter Methods

extension GalleryViewModel {

    /// Filter media by type
    func filterByType(_ items: [MediaItem], type: MediaType?) -> [MediaItem] {
        guard let type = type else {
            return items
        }
        return items.filter { $0.type == type }
    }

    /// Search media
    func search(_ items: [MediaItem], query: String) -> [MediaItem] {
        guard !query.isEmpty else {
            return items
        }

        return items.filter { item in
            item.fileName.localizedCaseInsensitiveContains(query)
                || item.fileExtension.localizedCaseInsensitiveContains(query)
        }
    }
}
