//
//  MediaLoaderService.swift
//  WagLock
//
//  Media loading service
//  Decrypts and loads images, videos and other media
//

import Foundation
import CryptoKit
import SwiftUI
import UIKit

/// Media loading service
///
/// Cache publication is generation-checked; workers only decrypt/decode.
nonisolated final class MediaLoaderService: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = MediaLoaderService()

    // MARK: - Services

    private let storage: FileStorageService
    private let decoder: @Sendable (Data, CGFloat) -> UIImage?

    // MARK: - Cache

    private let imageCache = SessionImageCache(countLimit: 100, costLimit: 100 * 1024 * 1024)
    private let loadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.d2sci.waglock.image-loading"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    init(storage: FileStorageService = .shared,
         decoder: @escaping @Sendable (Data, CGFloat) -> UIImage? = ThumbnailImageLoader.decode) {
        self.storage = storage
        self.decoder = decoder

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Public Methods

    /// Load an image (cached)
    @MainActor
    func loadImage(from mediaItem: MediaItem, password: String) async throws -> UIImage {
        try await loadImage(from: MediaPreviewSnapshot(mediaItem), password: password)
    }

    @MainActor
    func loadImage(from mediaItem: MediaPreviewSnapshot, password: String) async throws -> UIImage {
        let encryptedPath = mediaItem.encryptedPath
        // A cached path must not bypass the password supplied by a later request.
        let context = SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
        let cacheKey = encryptedPath + ":" + context
        try Task.checkCancellation()
        let snapshot = imageCache.lookup(cacheKey)

        // Check the cache
        if let cachedImage = snapshot.image {
            return cachedImage
        }

        // Use the single ZNSC-aware decryption pipeline; format detection lives only in FileStorageService
        try Task.checkCancellation()
        let decryptedData = try await storage.loadDecryptedDataAsync(
            path: encryptedPath,
            password: password,
            preferredExtension: mediaItem.fileExtension
        )
        try Task.checkCancellation()

        // Decode in the background to avoid blocking the main thread
        let image: UIImage? = await withCheckedContinuation { continuation in
            loadQueue.addOperation {
                continuation.resume(returning: self.decoder(decryptedData, AppConstants.previewImageMaxPixelSize))
            }
        }
        guard let image = image else {
            throw MediaLoaderError.invalidImageData
        }

        try Task.checkCancellation()
        guard imageCache.insert(image, key: cacheKey, generation: snapshot.generation) else {
            throw CancellationError()
        }
        return image
    }

    /// Clear the cache (NSCache is thread-safe; callable from any thread)
    func clearCache() {
        imageCache.clear()
    }

    /// Clear the cache for one image (NSCache is thread-safe; callable from any thread)
    func clearCache(forPath encryptedPath: String) {
        // Invalidate pending loads in every password context for this asset.
        // NSCache cannot enumerate context keys; conservative eviction is intentional.
        imageCache.clear()
    }

    // MARK: - Notifications

    @objc private func handleMemoryWarning() {
        clearCache()
    }
}

// MARK: - Errors

enum MediaLoaderError: Error {
    case invalidImageData
    case fileNotFound
    case decryptionFailed

    var localizedDescription: String {
        switch self {
        case .invalidImageData:
            return String(localized: "mediaLoader.error.invalidImageData")
        case .fileNotFound:
            return AppConstants.ErrorMessages.fileNotFound
        case .decryptionFailed:
            return AppConstants.ErrorMessages.decryptionFailed
        }
    }
}
