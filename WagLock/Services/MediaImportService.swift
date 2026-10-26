//
//  MediaImportService.swift
//  WagLock
//
//  Media import service
//  Imports, encrypts and saves photos, videos and files
//

import AVFoundation
import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Import errors
enum ImportError: Error {
    case loadFailed  // Load failed
    case unsupportedType  // Unsupported type
    case encryptionFailed  // Encryption failed
    case saveFailed  // Save failed
    case cancelled  // Cancelled by the user
    case permissionDenied  // Permission denied

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

/// Import progress
struct ImportProgress {
    let current: Int
    let total: Int
    let currentFileName: String

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

/// Media import service
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

    /// Import photos/videos (from PHPicker)
    /// - Parameters:
    ///   - results: PHPicker results
    ///   - password: Encryption password
    ///   - progress: Progress callback
    /// - Returns: Successfully imported MediaItems
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

    /// Import files (from the document picker)
    /// - Parameters:
    ///   - urls: File URLs
    ///   - password: Encryption password
    ///   - progress: Progress callback
    /// - Returns: Successfully imported MediaItems
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

    /// Import a single media item (photo/video)
    private func importSingleMedia(result: PHPickerResult, password: String) async throws
        -> MediaItem?
    {
        let itemProvider = result.itemProvider

        // Is it an image?
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return try await importImage(from: itemProvider, password: password)
        }

        // Is it a video?
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

        // Videos take a dedicated path so the thumbnail and metadata stay consistent
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

    /// Process a video
    private func processVideo(_ url: URL, password: String) async throws -> MediaItem {
        try Task.checkCancellation()
        // ⚠️ Important: extract metadata and the thumbnail before reading the data,
        // because the temporary URL may become invalid once the data is read


        // 1️⃣ Get video metadata first (the temporary file still exists)
        let (width, height, duration) = await getVideoMetadata(url: url)

        // 2️⃣ Generate the thumbnail (the temporary file still exists)
        let thumbnailData = try? await generateVideoThumbnail(url: url)


        // 3️⃣ Get the file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = "." + url.pathExtension

        // 4️⃣ Encrypt (streaming) and save
        let encryptedPath = try storageService.saveEncryptedFile(
            from: url,
            password: password,
            originalFileName: url.lastPathComponent
        )

        // 6️⃣ Create the MediaItem (make sure every parameter is passed through)
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

        // 7️⃣ Validate the MediaItem data

        return mediaItem
    }

    // MARK: - Thumbnail Generation

    /// Generate a thumbnail
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
            // Video thumbnails need a URL; return nil here and handle them in processVideo
            return nil

        case .audio, .document:
            // Documents use the default icon and need no thumbnail
            return nil
        }
    }

    /// Generate a video thumbnail
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

    /// Get video metadata
    private func getVideoMetadata(url: URL) async -> (width: Int?, height: Int?, duration: Double?)
    {
        let asset = AVAsset(url: url)

        // Get the duration
        let duration = try? await asset.load(.duration)
        let durationSeconds = duration.map { CMTimeGetSeconds($0) }

        // Get the video dimensions
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return (nil, nil, durationSeconds)
        }

        let size = try? await track.load(.naturalSize)
        let width = size.map { Int($0.width) }
        let height = size.map { Int($0.height) }

        return (width, height, durationSeconds)
    }

    // MARK: - Encrypted File Re-encryption

    /// Import an already-encrypted file and re-encrypt it with a new password
    /// - Parameters:
    ///   - url: Encrypted file URL
    ///   - originalPassword: Original encryption password
    ///   - newPassword: New encryption password
    /// - Returns: Imported MediaItems
    func importEncryptedFileWithReencryption(
        url: URL,
        originalPassword: String,
        newPassword: String
    ) async throws -> [MediaItem] {
        guard allowNativeEncryptedImport else { throw ImportError.unsupportedType }

        // 1. Read the encrypted file data
        let encryptedData = try Data(contentsOf: url)

        // 2. Decrypt with the original password
        let decryptedData = try encryptionService.decrypt(
            encryptedData: encryptedData,
            password: originalPassword
        )

        // 3. Re-encrypt with the new password
        let reencryptedData = try encryptionService.encrypt(
            data: decryptedData,
            password: newPassword
        )

        // 4. Save the re-encrypted data
        // Get the original file name (without the .encrypted suffix)
        let originalURL = url.deletingPathExtension()
        let fileName = originalURL.deletingPathExtension().lastPathComponent
        let fileExtension = "." + originalURL.pathExtension

        let encryptedPath = try storageService.saveEncrypted(
            data: reencryptedData,
            originalFileName: url.lastPathComponent
        )

        // 5. Try to extract metadata from the decrypted data
        let fileSize = Int64(decryptedData.count)
        let mediaType = MediaType.from(fileExtension: originalURL.pathExtension)

        var thumbnailData: Data?
        var width: Int?
        var height: Int?
        var duration: Double?

        // Try to generate a thumbnail (for images or videos)
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

        // Create the MediaItem
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
