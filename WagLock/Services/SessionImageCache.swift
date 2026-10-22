import Foundation
import UIKit

/// Invalidation and publication share a lock so late decoders cannot refill a cleared cache.
nonisolated final class SessionImageCache: @unchecked Sendable {
    private let lock = NSLock()
    private let images = NSCache<NSString, UIImage>()
    private var generation = UUID()

    init(countLimit: Int, costLimit: Int) {
        images.countLimit = countLimit
        images.totalCostLimit = costLimit
    }

    func lookup(_ key: String) -> (image: UIImage?, generation: UUID) {
        lock.lock()
        defer { lock.unlock() }
        return (images.object(forKey: key as NSString), generation)
    }

    func insert(_ image: UIImage, key: String, generation expected: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard expected == generation else { return false }
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        images.setObject(image, forKey: key as NSString, cost: width * height * 4)
        return true
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        generation = UUID()
        images.removeAllObjects()
    }
}
