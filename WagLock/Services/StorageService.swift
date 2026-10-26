//
//  StorageService.swift
//  WagLock
//
//  Storage management service
//  Calculates file sizes, clears caches, etc.
//

import Foundation
import SwiftData

/// Storage management service
class StorageService {

    // MARK: - Singleton

    static let shared = StorageService()
    private init() {}

    // MARK: - Storage Calculation

    /// Calculate the total size of all encrypted files
    func calculateTotalStorageUsed(modelContext: ModelContext) async -> Int64 {
        let descriptor = FetchDescriptor<MediaItem>()

        do {
            let items = try modelContext.fetch(descriptor)
            let totalSize = items.reduce(0) { $0 + $1.fileSize }
            return totalSize
        } catch {
            return 0
        }
    }

    /// Format a file size
    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Get the size of the app's Documents directory
    func calculateDocumentsDirectorySize() -> Int64 {
        guard
            let documentsURL = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return 0
        }

        return calculateDirectorySize(url: documentsURL)
    }

    /// Calculate the size of a directory
    private func calculateDirectorySize(url: URL) -> Int64 {
        var totalSize: Int64 = 0

        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [
                    .fileSizeKey, .isRegularFileKey,
                ])

                if let isRegularFile = resourceValues.isRegularFile, isRegularFile {
                    totalSize += Int64(resourceValues.fileSize ?? 0)
                }
            } catch {
            }
        }

        return totalSize
    }

    // MARK: - Cache Management

    /// Calculate the temporary cache size
    func calculateCacheSize() -> Int64 {
        guard
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first
        else {
            return 0
        }

        return calculateDirectorySize(url: cacheURL)
    }

    /// Clear the temporary cache
    func clearCache() throws -> Int64 {
        guard
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first
        else {
            throw StorageError.cacheDirectoryNotFound
        }

        let fileManager = FileManager.default
        let cacheSize = calculateDirectorySize(url: cacheURL)

        // Get all files in the cache directory
        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: cacheURL,
                includingPropertiesForKeys: nil,
                options: []
            )
        else {
            throw StorageError.clearCacheFailed
        }

        // Delete each file and subdirectory
        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }

        return cacheSize
    }

    /// Clear the temporary files directory
    func clearTemporaryFiles() throws -> Int64 {
        let tempURL = FileManager.default.temporaryDirectory
        let fileManager = FileManager.default
        let tempSize = calculateDirectorySize(url: tempURL)

        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: tempURL,
                includingPropertiesForKeys: nil,
                options: []
            )
        else {
            throw StorageError.clearTempFailed
        }

        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }

        return tempSize
    }

    // MARK: - Storage Info

    /// Get storage statistics
    func getStorageInfo(modelContext: ModelContext, storage: FileStorageService? = nil) async -> StorageInfo {
        let totalUsed = await calculateTotalStorageUsed(modelContext: modelContext)
        let cacheSize = storage == nil ? calculateCacheSize() : 0
        let documentsSize = storage.map { calculateDirectorySize(url: $0.getStorageDirectory()) } ?? calculateDocumentsDirectorySize()

        // Get the device's available space
        let availableSpace = getAvailableSpace()

        return StorageInfo(
            totalUsed: totalUsed,
            cacheSize: cacheSize,
            documentsSize: documentsSize,
            availableSpace: availableSpace
        )
    }

    /// Get the device's available space
    private func getAvailableSpace() -> Int64 {
        guard
            let documentsURL = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return 0
        }

        do {
            let values = try documentsURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ])
            return Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        } catch {
            return 0
        }
    }
}

// MARK: - Storage Info Model

struct StorageInfo {
    /// Total space used by all media files
    let totalUsed: Int64

    /// Space used by caches
    let cacheSize: Int64

    /// Total size of the Documents directory
    let documentsSize: Int64

    /// Device available space
    let availableSpace: Int64

    /// Formatted total used space
    var formattedTotalUsed: String {
        ByteCountFormatter.string(fromByteCount: totalUsed, countStyle: .file)
    }

    /// Formatted cache size
    var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
    }

    /// Formatted Documents size
    var formattedDocumentsSize: String {
        ByteCountFormatter.string(fromByteCount: documentsSize, countStyle: .file)
    }

    /// Formatted available space
    var formattedAvailableSpace: String {
        ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file)
    }
}

// MARK: - Storage Errors

enum StorageError: Error {
    case cacheDirectoryNotFound
    case clearCacheFailed
    case clearTempFailed

    var localizedDescription: String {
        switch self {
        case .cacheDirectoryNotFound:
            return String(localized: "storage.error.cacheNotFound")
        case .clearCacheFailed:
            return String(localized: "storage.error.clearCacheFailed")
        case .clearTempFailed:
            return String(localized: "storage.error.clearTempFailed")
        }
    }
}
