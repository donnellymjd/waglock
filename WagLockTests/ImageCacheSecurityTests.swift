import Foundation
import SwiftData
import Testing
import UIKit

@testable import WagLock

@MainActor
struct ImageCacheSecurityTests {
    @Test
    func thumbnailClearRejectsAnAlreadyRunningDecode() async throws {
        let gate = DecodeGate()
        defer { gate.release() }
        let loader = ThumbnailImageLoader(decoder: { gate.decode($0, $1) })
        let pending = Task { await loader.image(for: "asset", data: Data([1])) }
        #expect(await gate.waitUntilStarted())
        loader.clearAll()
        gate.release()
        #expect(await pending.value == nil)
        #expect(await loader.image(for: "asset", data: Data([1])) != nil)
        #expect(gate.count == 2)
        #expect(await loader.image(for: "asset", data: Data([1])) != nil)
        #expect(gate.count == 2)
    }

    @Test
    func cancelledThumbnailRequestCannotPublishOrPopulateTheCache() async throws {
        let gate = DecodeGate()
        defer { gate.release() }
        let loader = ThumbnailImageLoader(decoder: { gate.decode($0, $1) })
        let pending = Task { await loader.image(for: "asset", data: Data([1])) }
        #expect(await gate.waitUntilStarted())
        pending.cancel()
        gate.release()
        #expect(await pending.value == nil)
        #expect(await loader.image(for: "asset", data: Data([1])) != nil)
        #expect(gate.count == 2)
    }

    @Test
    func fullThumbnailContentParticipatesInTheCacheKey() async throws {
        let gate = DecodeGate(blockFirst: false)
        let loader = ThumbnailImageLoader(decoder: { gate.decode($0, $1) })
        var first = Data(repeating: 1, count: 256)
        let second = first
        first[128] = 2
        #expect(await loader.image(for: "asset", data: first) != nil)
        #expect(await loader.image(for: "asset", data: second) != nil)
        #expect(gate.count == 2)
    }

    private func fixture(_ gate: DecodeGate) throws -> (MediaLoaderService, MediaItem, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cache-test-" + UUID().uuidString)
        let storage = FileStorageService(directory: directory, availableCapacity: { _ in Int64.max })
        let encrypted = try EncryptionService.shared.encrypt(data: Data("fixture pixels".utf8), password: "fixture-password")
        let path = try storage.saveEncrypted(data: encrypted)
        let item = MediaItem(fileName: "fixture", fileExtension: ".jpg", fileSize: 14, type: .photo, encryptedPath: path)
        return (MediaLoaderService(storage: storage, decoder: { gate.decode($0, $1) }), item, directory)
    }

    @Test
    func mediaClearRejectsAnAlreadyRunningDecode() async throws {
        let gate = DecodeGate()
        let (loader, item, directory) = try fixture(gate)
        defer { gate.release(); try? FileManager.default.removeItem(at: directory) }
        let pending = Task { try await loader.loadImage(from: item, password: "fixture-password") }
        #expect(await gate.waitUntilStarted())
        loader.clearCache()
        gate.release()
        do { _ = try await pending.value; Issue.record("A stale image was published after cache invalidation") }
        catch is CancellationError { }
        _ = try await loader.loadImage(from: item, password: "fixture-password")
        #expect(gate.count == 2)
    }

    @Test
    func cancelledMediaRequestCannotPublishOrPopulateTheCache() async throws {
        let gate = DecodeGate()
        let (loader, item, directory) = try fixture(gate)
        defer { gate.release(); try? FileManager.default.removeItem(at: directory) }
        let pending = Task { try await loader.loadImage(from: item, password: "fixture-password") }
        #expect(await gate.waitUntilStarted())
        pending.cancel()
        gate.release()
        do { _ = try await pending.value; Issue.record("A cancelled image was published") }
        catch is CancellationError { }
        _ = try await loader.loadImage(from: item, password: "fixture-password")
        #expect(gate.count == 2)
    }

    @Test
    func cachedPreviewCannotBypassAWrongPassword() async throws {
        let gate = DecodeGate(blockFirst: false)
        let (loader, item, directory) = try fixture(gate)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await loader.loadImage(from: item, password: "fixture-password")
        do { _ = try await loader.loadImage(from: item, password: "wrong-password"); Issue.record("The cache bypassed password authentication") }
        catch { }
        #expect(gate.count == 1)
    }
}

/// A bounded, deterministic pause inside a background decoder, never on the main actor.
nonisolated private final class DecodeGate: @unchecked Sendable {
    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private let resume = DispatchSemaphore(value: 0)
    private let blockFirst: Bool
    private var invocations = 0

    init(blockFirst: Bool = true) { self.blockFirst = blockFirst }

    var count: Int { lock.withLock { invocations } }

    func decode(_ data: Data, _ pixels: CGFloat) -> UIImage? {
        let first = lock.withLock { invocations += 1; return invocations == 1 }
        if first && blockFirst {
            started.signal()
            guard resume.wait(timeout: .now() + 5) == .success else { return nil }
        }
        return UIImage()
    }

    func waitUntilStarted() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: self.started.wait(timeout: .now() + 5) == .success)
            }
        }
    }

    func release() { resume.signal() }
}
