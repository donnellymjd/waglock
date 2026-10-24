//
//  StorageService.swift
//  WagLock
//
//  存储空间管理服务
//  计算文件大小、清理缓存等
//

import Foundation
import SwiftData

/// 存储管理服务
class StorageService {

    // MARK: - Singleton

    static let shared = StorageService()
    private init() {}

    // MARK: - Storage Calculation

    /// 计算所有加密文件的总大小
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

    /// 格式化文件大小
    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 获取应用文档目录大小
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

    /// 计算指定目录的大小
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

    /// 计算临时缓存大小
    func calculateCacheSize() -> Int64 {
        guard
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first
        else {
            return 0
        }

        return calculateDirectorySize(url: cacheURL)
    }

    /// 清理临时缓存
    func clearCache() throws -> Int64 {
        guard
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first
        else {
            throw StorageError.cacheDirectoryNotFound
        }

        let fileManager = FileManager.default
        let cacheSize = calculateDirectorySize(url: cacheURL)

        // 获取缓存目录中的所有文件
        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: cacheURL,
                includingPropertiesForKeys: nil,
                options: []
            )
        else {
            throw StorageError.clearCacheFailed
        }

        // 删除每个文件和子目录
        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }

        return cacheSize
    }

    /// 清理临时文件目录
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

    /// 获取存储统计信息
    func getStorageInfo(modelContext: ModelContext, storage: FileStorageService? = nil) async -> StorageInfo {
        let totalUsed = await calculateTotalStorageUsed(modelContext: modelContext)
        let cacheSize = storage == nil ? calculateCacheSize() : 0
        let documentsSize = storage.map { calculateDirectorySize(url: $0.getStorageDirectory()) } ?? calculateDocumentsDirectorySize()

        // 获取设备可用空间
        let availableSpace = getAvailableSpace()

        return StorageInfo(
            totalUsed: totalUsed,
            cacheSize: cacheSize,
            documentsSize: documentsSize,
            availableSpace: availableSpace
        )
    }

    /// 获取设备可用空间
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
    /// 所有媒体文件占用的总空间
    let totalUsed: Int64

    /// 缓存占用空间
    let cacheSize: Int64

    /// 文档目录总大小
    let documentsSize: Int64

    /// 设备可用空间
    let availableSpace: Int64

    /// 格式化的总使用空间
    var formattedTotalUsed: String {
        ByteCountFormatter.string(fromByteCount: totalUsed, countStyle: .file)
    }

    /// 格式化的缓存大小
    var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
    }

    /// 格式化的文档大小
    var formattedDocumentsSize: String {
        ByteCountFormatter.string(fromByteCount: documentsSize, countStyle: .file)
    }

    /// 格式化的可用空间
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
