//
//  MediaImportService.swift
//  WagLock
//
//  媒体导入服务
//  处理照片、视频、文件的导入、加密和保存
//

import AVFoundation
import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 导入错误
enum ImportError: Error {
    case loadFailed  // 加载失败
    case unsupportedType  // 不支持的类型
    case encryptionFailed  // 加密失败
    case saveFailed  // 保存失败
    case cancelled  // 用户取消
    case permissionDenied  // 权限被拒绝

    var localizedDescription: String {
        switch self {
        case .loadFailed:
            return String(localized: "importError.loadFailed")
        case .unsupportedType:
            return String(localized: "importError.unsupportedType")
        case .encryptionFailed:
            return AppConstants.ErrorMessages.encryptionFailed
        case .saveFailed:
            return AppConstants.ErrorMessages.saveFailed
        case .cancelled:
            return String(localized: "importError.cancelled")
        case .permissionDenied:
            return AppConstants.ErrorMessages.permissionDenied
        }
    }
}

/// 导入进度
struct ImportProgress {
    let current: Int
    let total: Int
    let currentFileName: String

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

/// 媒体导入服务
class MediaImportService {
    nonisolated deinit { }

    // MARK: - Singleton

    static let shared = MediaImportService()

    // MARK: - Services

    private let encryptionService = EncryptionService.shared
    private let storageService: FileStorageService
    private let allowNativeEncryptedImport: Bool

    init(storage: FileStorageService = .shared,
         allowNativeEncryptedImport: Bool = !LibraryStoragePolicy.encryptedMetadata) {
        storageService = storage
        self.allowNativeEncryptedImport = allowNativeEncryptedImport
    }

    // MARK: - Public Methods

    /// 导入照片/视频（从PHPicker）
    /// - Parameters:
    ///   - results: PHPicker结果数组
    ///   - password: 加密密码
    ///   - progress: 进度回调
    /// - Returns: 导入成功的MediaItem数组
    func importMedia(
        from results: [PHPickerResult],
        password: String,
        progress: @escaping (ImportProgress) -> Void = { _ in }
    ) async throws -> [MediaItem] {
        try await importBatch(Array(results.enumerated())) { index, result in
            let current = ImportProgress(current: index + 1, total: results.count,
                                         currentFileName: "Media \(index + 1)")
            await MainActor.run { progress(current) }
            return try await self.importSingleMedia(result: result, password: password)
        }
    }

    /// 导入文件（从文档选择器）
    /// - Parameters:
    ///   - urls: 文件URL数组
    ///   - password: 加密密码
    ///   - progress: 进度回调
    /// - Returns: 导入成功的MediaItem数组
    func importFiles(
        from urls: [URL],
        password: String,
        progress: @escaping (ImportProgress) -> Void = { _ in }
    ) async throws -> [MediaItem] {
        try await importBatch(Array(urls.enumerated())) { index, url in
            let current = ImportProgress(current: index + 1, total: urls.count,
                                         currentFileName: url.lastPathComponent)
            await MainActor.run { progress(current) }
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }
            return try await self.importSingleFile(url: url, password: password)
        }
    }

    /// Owns fresh outputs until the complete batch is handed to its caller.
    /// Cancellation discards the batch; ordinary per-item failures retain successes.
    func importBatch<Input>(_ inputs: [Input],
                            operation: (Input) async throws -> MediaItem?) async throws -> [MediaItem] {
        var imported: [MediaItem] = []
        var handedOff = false
        defer {
            if !handedOff {
                for item in imported { try? storageService.deleteFile(path: item.encryptedPath) }
            }
        }
        for input in inputs {
            try Task.checkCancellation()
            do {
                if let item = try await operation(input) { imported.append(item) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A failed item must not erase successfully imported siblings.
            }
        }
        try Task.checkCancellation()
        handedOff = true
        return imported
    }

    // MARK: - Private Methods - Media Import

    /// 导入单个媒体（照片/视频）
    private func importSingleMedia(result: PHPickerResult, password: String) async throws
        -> MediaItem?
    {
        let itemProvider = result.itemProvider

        // 检查是否为图片
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return try await importImage(from: itemProvider, password: password)
        }

        // 检查是否为视频
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return try await importVideo(from: itemProvider, password: password)
        }

        return nil
    }

    /// Preserve the provider's current encoded representation; never re-encode originals.
    func importImage(from itemProvider: NSItemProvider, password: String) async throws -> MediaItem? {
        let type = itemProvider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
        let url = try await ownedRepresentation(from: itemProvider, type: type)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return try processOriginalImage(url, password: password)
    }

    private func importVideo(from itemProvider: NSItemProvider, password: String) async throws -> MediaItem? {
        let type = itemProvider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .movie) == true } ?? UTType.movie.identifier
        let url = try await ownedRepresentation(from: itemProvider, type: type)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return try await processVideo(url, password: password)
    }

    private func ownedRepresentation(from provider: NSItemProvider, type: String) async throws -> URL {
        try Task.checkCancellation()
        let suggested = provider.suggestedName
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard error == nil, let url else { continuation.resume(throwing: ImportError.loadFailed); return }
                do { continuation.resume(returning: try Self.copyRepresentation(url, suggestedName: suggested, type: type)) }
                catch { continuation.resume(throwing: error) }
            }
        }
        do { try Task.checkCancellation(); return url }
        catch { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); throw error }
    }

    nonisolated private static func copyRepresentation(_ source: URL, suggestedName: String?, type: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("waglock-media-import-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        do {
            var name = suggestedName.map { URL(fileURLWithPath: $0).lastPathComponent } ?? source.lastPathComponent
            if name.isEmpty || name == "." || name == ".." { name = "Imported media" }
            if URL(fileURLWithPath: name).pathExtension.isEmpty {
                let suffix = source.pathExtension.isEmpty ? UTType(type)?.preferredFilenameExtension : source.pathExtension
                if let suffix, !suffix.isEmpty { name += "." + suffix }
            }
            let target = folder.appendingPathComponent(name)
            try FileManager.default.copyItem(at: source, to: target)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
            return target
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }

    static func removeAbandonedProviderCopies() {
        let root = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for folder in entries {
            guard folder.lastPathComponent.hasPrefix("waglock-media-import-"),
                  UUID(uuidString: String(folder.lastPathComponent.dropFirst("waglock-media-import-".count))) != nil,
                  let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Caller holds provider access; all type dispatch retains this instance's storage.
    func importSingleFile(url: URL, password: String) async throws -> MediaItem? {
        try Task.checkCancellation()

        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = "." + url.pathExtension
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        let mediaType = MediaType.from(fileExtension: url.pathExtension)

        // 针对视频文件走专用处理流程，保证缩略图与元数据一致
        if mediaType == .video {
            return try await processVideo(url, password: password)
        }

        if mediaType == .audio {
            return try await AudioImportService.importFile(url: url, password: password, storage: storageService)
        }
        if mediaType == .photo { return try processOriginalImage(url, password: password) }

        var encryptedPath: String
        var thumbnailData: Data?

        encryptedPath = try storageService.saveEncryptedFile(from: url, password: password, originalFileName: url.lastPathComponent)
        thumbnailData = nil

        let mediaItem = MediaItem(
            fileName: fileName,
            fileExtension: fileExtension,
            fileSize: fileSize,
            type: mediaType,
            encryptedPath: encryptedPath,
            thumbnailData: thumbnailData
        )

        return mediaItem
    }

    // MARK: - Image Processing

    /// Metadata/thumbnail decoding is separate from byte-preserving original encryption.
    func processOriginalImage(_ url: URL, password: String) throws -> MediaItem {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String), type.conforms(to: .image),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int else { throw ImportError.unsupportedType }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = [5, 6, 7, 8].contains(orientation)
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(AppConstants.thumbnailMaxSize),
            kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            .flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: AppConstants.thumbnailCompressionQuality) }
        let fileSize = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let suffix = UTType(filenameExtension: url.pathExtension) == type ? url.pathExtension : type.preferredFilenameExtension ?? url.pathExtension
        try Task.checkCancellation()
        let path = try storageService.saveEncryptedFile(from: url, password: password, originalFileName: url.lastPathComponent)
        return MediaItem(fileName: url.deletingPathExtension().lastPathComponent, fileExtension: "." + suffix,
                         fileSize: fileSize, type: .photo, encryptedPath: path, thumbnailData: thumbnail,
                         width: rotated ? pixelHeight : pixelWidth, height: rotated ? pixelWidth : pixelHeight)
    }

    // MARK: - Video Processing

    /// 处理视频
    private func processVideo(_ url: URL, password: String) async throws -> MediaItem {
        try Task.checkCancellation()
        // ⚠️ 重要: 必须先提取元数据和缩略图，再读取数据
        // 因为临时 URL 可能在读取数据后就失效


        // 1️⃣ 先获取视频元数据（此时临时文件还存在）
        let (width, height, duration) = await getVideoMetadata(url: url)

        // 2️⃣ 生成缩略图（此时临时文件还存在）
        let thumbnailData = try? await generateVideoThumbnail(url: url)


        // 3️⃣ 获取文件大小
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = "." + url.pathExtension

        // 4️⃣ 流式加密并保存
        let encryptedPath = try storageService.saveEncryptedFile(
            from: url,
            password: password,
            originalFileName: url.lastPathComponent
        )

        // 6️⃣ 创建MediaItem（确保所有参数都正确传递）
        let mediaItem = MediaItem(
            fileName: fileName,
            fileExtension: fileExtension,
            fileSize: fileSize,
            type: .video,
            encryptedPath: encryptedPath,
            thumbnailData: thumbnailData,
            width: width,
            height: height,
            duration: duration
        )

        // 7️⃣ 验证MediaItem数据

        return mediaItem
    }

    // MARK: - Thumbnail Generation

    /// 生成缩略图
    private func generateThumbnail(for data: Data, type: MediaType, fileExtension: String) -> Data?
    {
        switch type {
        case .photo:
            guard let image = UIImage(data: data),
                let thumbnail = image.thumbnail(maxSize: AppConstants.thumbnailMaxSize)
            else {
                return nil
            }
            return thumbnail.compressedJPEGData(quality: AppConstants.thumbnailCompressionQuality)

        case .video:
            // 视频缩略图需要URL，这里返回nil，在processVideo中单独处理
            return nil

        case .audio, .document:
            // 文档使用默认图标，不需要缩略图
            return nil
        }
    }

    /// 生成视频缩略图
    private func generateVideoThumbnail(url: URL) async throws -> Data? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: AppConstants.videoThumbnailTime, preferredTimescale: 600)

        return try await withCheckedThrowingContinuation { continuation in
            imageGenerator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                if let error = error {
                    continuation.resume(returning: nil)
                    return
                }

                guard let cgImage = cgImage else {
                    continuation.resume(returning: nil)
                    return
                }

                let image = UIImage(cgImage: cgImage)
                if let thumbnail = image.thumbnail(maxSize: AppConstants.thumbnailMaxSize),
                    let thumbnailData = thumbnail.compressedJPEGData(
                        quality: AppConstants.thumbnailCompressionQuality)
                {
                    continuation.resume(returning: thumbnailData)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 获取视频元数据
    private func getVideoMetadata(url: URL) async -> (width: Int?, height: Int?, duration: Double?)
    {
        let asset = AVAsset(url: url)

        // 获取时长
        let duration = try? await asset.load(.duration)
        let durationSeconds = duration.map { CMTimeGetSeconds($0) }

        // 获取视频尺寸
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return (nil, nil, durationSeconds)
        }

        let size = try? await track.load(.naturalSize)
        let width = size.map { Int($0.width) }
        let height = size.map { Int($0.height) }

        return (width, height, durationSeconds)
    }

    // MARK: - Encrypted File Re-encryption

    /// 导入已加密文件并使用新密码重新加密
    /// - Parameters:
    ///   - url: 加密文件URL
    ///   - originalPassword: 原始加密密码
    ///   - newPassword: 新的加密密码
    /// - Returns: 导入的MediaItem数组
    func importEncryptedFileWithReencryption(
        url: URL,
        originalPassword: String,
        newPassword: String
    ) async throws -> [MediaItem] {
        guard allowNativeEncryptedImport else { throw ImportError.unsupportedType }

        // 1. 读取加密文件数据
        let encryptedData = try Data(contentsOf: url)

        // 2. 使用原始密码解密
        let decryptedData = try encryptionService.decrypt(
            encryptedData: encryptedData,
            password: originalPassword
        )

        // 3. 使用新密码重新加密
        let reencryptedData = try encryptionService.encrypt(
            data: decryptedData,
            password: newPassword
        )

        // 4. 保存重新加密的数据
        // 获取原始文件名（去掉.encrypted后缀）
        let originalURL = url.deletingPathExtension()
        let fileName = originalURL.deletingPathExtension().lastPathComponent
        let fileExtension = "." + originalURL.pathExtension

        let encryptedPath = try storageService.saveEncrypted(
            data: reencryptedData,
            originalFileName: url.lastPathComponent
        )

        // 5. 尝试从解密数据中提取元数据
        let fileSize = Int64(decryptedData.count)
        let mediaType = MediaType.from(fileExtension: originalURL.pathExtension)

        var thumbnailData: Data?
        var width: Int?
        var height: Int?
        var duration: Double?

        // 尝试生成缩略图（如果是图片或视频）
        if mediaType == .photo {
            if let image = UIImage(data: decryptedData) {
                width = Int(image.size.width)
                height = Int(image.size.height)
                if let thumbnail = image.thumbnail(maxSize: AppConstants.thumbnailMaxSize) {
                    thumbnailData = thumbnail.compressedJPEGData(
                        quality: AppConstants.thumbnailCompressionQuality
                    )
                }
            }
        }

        // 创建MediaItem
        let mediaItem = MediaItem(
            fileName: fileName,
            fileExtension: fileExtension,
            fileSize: fileSize,
            type: mediaType,
            encryptedPath: encryptedPath,
            thumbnailData: thumbnailData,
            width: width,
            height: height,
            duration: duration
        )

        return [mediaItem]
    }
}
