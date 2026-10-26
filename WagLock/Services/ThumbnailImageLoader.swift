import ImageIO
import CryptoKit
import UIKit

/// Decodes thumbnails in the background and shares the results across list views.
nonisolated final class ThumbnailImageLoader: @unchecked Sendable {
    static let shared = ThumbnailImageLoader()

    private let cache = SessionImageCache(countLimit: 150, costLimit: 48 * 1_024 * 1_024)
    private let decoder: @Sendable (Data, CGFloat) -> UIImage?
    private let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.d2sci.waglock.thumbnail-decoding"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    init(decoder: @escaping @Sendable (Data, CGFloat) -> UIImage? = ThumbnailImageLoader.decode) {
        self.decoder = decoder
    }

    func image(
        for key: String,
        data: Data,
        maxPixelSize: CGFloat = AppConstants.thumbnailMaxSize
    ) async -> UIImage? {
        let fingerprint = Data(SHA256.hash(data: data)).base64EncodedString()
        let cacheKey = "\(key)-\(Int(maxPixelSize))-\(fingerprint)"
        guard !Task.isCancelled else { return nil }
        let snapshot = cache.lookup(cacheKey)
        if let cachedImage = snapshot.image {
            return cachedImage
        }

        let image: UIImage? = await withCheckedContinuation { continuation in
            decodeQueue.addOperation { [weak self] in
                continuation.resume(returning: self?.decoder(data, maxPixelSize))
            }
        }
        guard !Task.isCancelled, let image,
              cache.insert(image, key: cacheKey, generation: snapshot.generation) else { return nil }
        return image
    }

    /// Clear all caches.
    ///
    /// Rejects pending results too; memory zeroization of UIKit pixels is not guaranteed.
    func clearAll() {
        cache.clear()
    }

    static func decode(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard maxPixelSize > 0,
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
