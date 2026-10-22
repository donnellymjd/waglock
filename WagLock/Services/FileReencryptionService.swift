//
//  FileReencryptionService.swift
//  WagLock
//
//  文件重新加密服务
//  处理密码更改时的批量文件重新加密
//

import Foundation
import SwiftData

/// 文件重新加密服务
@MainActor
class FileReencryptionService: ObservableObject {

    // MARK: - Singleton

    static let shared = FileReencryptionService()

    private init() {}

    // MARK: - Published Properties

    /// 是否正在重新加密
    @Published var isReencrypting: Bool = false

    /// 当前进度（0.0 - 1.0）
    @Published var progress: Double = 0.0

    /// 当前处理的文件名
    @Published var currentFileName: String = ""

    /// 已处理的文件数
    @Published var processedCount: Int = 0

    /// 总文件数
    @Published var totalCount: Int = 0

    /// 错误消息
    @Published var errorMessage: String?

    // MARK: - Services

    private let encryptionService = EncryptionService.shared
    private let fileManager = FileManager.default

    // MARK: - Constants

    /// 批处理大小（每批处理的文件数，避免内存压力）
    private let batchSize = 10

    // MARK: - Public Methods

    /// 重新加密所有文件
    /// - Parameters:
    ///   - oldPassword: 旧密码
    ///   - newPassword: 新密码
    ///   - modelContext: SwiftData模型上下文
    /// - Returns: 成功重新加密的文件数
    func reencryptAllFiles(
        oldPassword: String,
        newPassword: String,
        modelContext: ModelContext
    ) async throws -> Int {

        guard !isReencrypting else {
            throw ReencryptionError.alreadyInProgress
        }

        // 重置状态
        await resetState()
        isReencrypting = true

        do {
            // 1. 查询所有媒体文件
            let descriptor = FetchDescriptor<MediaItem>()
            let allItems = try modelContext.fetch(descriptor)

            totalCount = allItems.count

            guard totalCount > 0 else {
                isReencrypting = false
                return 0
            }


            // 2. 分批处理文件
            var successCount = 0
            let batches = stride(from: 0, to: allItems.count, by: batchSize).map {
                Array(allItems[$0..<min($0 + batchSize, allItems.count)])
            }

            for (batchIndex, batch) in batches.enumerated() {

                // 处理批次中的每个文件
                for item in batch {
                    do {
                        try await reencryptSingleFile(
                            item: item,
                            oldPassword: oldPassword,
                            newPassword: newPassword
                        )
                        successCount += 1
                        processedCount = successCount
                        progress = Double(successCount) / Double(totalCount)
                    } catch {
                        throw ReencryptionError.fileReencryptionFailed(
                            fileName: item.fileName,
                            error: error
                        )
                    }
                }

                // 批次间短暂延迟，避免CPU过载
                if batchIndex < batches.count - 1 {
                    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1秒
                }
            }

            isReencrypting = false

            return successCount

        } catch {
            isReencrypting = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Private Methods

    /// 重新加密单个文件
    private func reencryptSingleFile(
        item: MediaItem,
        oldPassword: String,
        newPassword: String
    ) async throws {

        currentFileName = item.fileName

        let encryptedURL = URL(fileURLWithPath: item.encryptedPath)

        // 1. 读取加密文件
        guard fileManager.fileExists(atPath: encryptedURL.path) else {
            throw ReencryptionError.fileNotFound(path: item.encryptedPath)
        }

        let encryptedData = try Data(contentsOf: encryptedURL)

        // 2. 用旧密码解密
        let decryptedData = try encryptionService.decrypt(
            encryptedData: encryptedData,
            password: oldPassword
        )

        // 3. 用新密码加密
        let reencryptedData = try encryptionService.encrypt(
            data: decryptedData,
            password: newPassword
        )

        // 4. 写回文件（原子操作，先写临时文件，再替换）
        let tempURL = encryptedURL.deletingLastPathComponent()
            .appendingPathComponent("temp_\(UUID().uuidString)")

        try reencryptedData.write(to: tempURL, options: .atomic)

        // 5. 替换原文件
        _ = try fileManager.replaceItemAt(encryptedURL, withItemAt: tempURL)

        // 6. 处理缩略图（如果存在）
        if let thumbnailData = item.thumbnailData {
            do {
                // 解密旧缩略图
                let decryptedThumbnail = try encryptionService.decrypt(
                    encryptedData: thumbnailData,
                    password: oldPassword
                )

                // 用新密码加密
                let reencryptedThumbnail = try encryptionService.encrypt(
                    data: decryptedThumbnail,
                    password: newPassword
                )

                // 更新缩略图
                item.thumbnailData = reencryptedThumbnail
            } catch {
                // 缩略图失败不影响主流程，继续
            }
        }

    }

    /// 重置状态
    private func resetState() async {
        progress = 0.0
        processedCount = 0
        totalCount = 0
        currentFileName = ""
        errorMessage = nil
    }
}

// MARK: - Errors

enum ReencryptionError: LocalizedError {
    case alreadyInProgress
    case fileNotFound(path: String)
    case fileReencryptionFailed(fileName: String, error: Error)

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return String(localized: "reencryptionError.inProgress")
        case .fileNotFound(let path):
            return String(
                format: String(localized: "reencryptionError.fileNotFound"),
                path)
        case .fileReencryptionFailed(let fileName, let error):
            return String(
                format: String(localized: "reencryptionError.fileFailed"),
                fileName,
                error.localizedDescription)
        }
    }
}
