import CryptoKit
import Foundation

/// Fixed-size storage (ADR-030, docs/portable-vault/fixed-size-storage.md).
///
/// In Fixed mode WagLock pre-allocates one file of pseudorandom bytes, the reserve, so
/// that everything WagLock keeps on this iPhone (every library, its metadata and the
/// reserve) adds up to the chosen size. Every write first takes its bytes out of the
/// reserve; deleting gives them back. iOS storage settings therefore show the same size
/// however much any library holds and however many libraries exist.
///
/// Library files and stores are never moved, rewritten or converted: switching modes
/// only allocates or frees the reserve. This hides totals from the iOS size display; it
/// does not hide per-library files from someone who images the phone (see the doc).
nonisolated final class StorageReserve: @unchecked Sendable {
    enum Mode: String, Codable, Sendable { case standard, fixed }

    struct Config: Codable, Equatable, Sendable {
        var version = 1
        var mode: Mode
        var targetBytes: Int64
        static let standard = Config(mode: .standard, targetBytes: 0)
    }

    enum Failure: Error, Equatable {
        /// The reserved space has no room for this write. Never shows how much is used.
        case full
        /// Outside 2–180 GB, or smaller than what WagLock already holds.
        case invalidSize
        /// The iPhone does not have the free space this size needs.
        case insufficientDevice
        case unavailable
    }

    static let gigabyte: Int64 = 1_000_000_000
    static let minimumBytes: Int64 = 2 * gigabyte
    static let maximumBytes: Int64 = 180 * gigabyte
    /// Room kept for metadata, journals and short-lived files that are not claimed.
    static let headroom: Int64 = 64 * 1_048_576
    /// Free space the device must keep after the reserve grows.
    static let deviceMargin: Int64 = gigabyte
    static let chunkSize = 4 * 1_048_576

    static let shared: StorageReserve = {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).resolvingSymlinksInPath()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .resolvingSymlinksInPath()
        return StorageReserve(measureRoot: home, directory: support, freeSpace: StorageReserve.deviceFreeSpace)
    }()

    let reserveURL: URL
    let configURL: URL
    private let measureRoot: URL
    private let freeSpace: @Sendable (URL) throws -> Int64
    private let lock = NSLock()
    private var cachedUsed: Int64?
    /// Instance limits equal the static ones in the app; tests use small values.
    let minimum: Int64, maximum: Int64, reserveHeadroom: Int64, margin: Int64

    init(measureRoot: URL, directory: URL, freeSpace: @escaping @Sendable (URL) throws -> Int64,
         minimum: Int64 = StorageReserve.minimumBytes, maximum: Int64 = StorageReserve.maximumBytes,
         headroom: Int64 = StorageReserve.headroom, deviceMargin: Int64 = StorageReserve.deviceMargin) {
        self.minimum = minimum; self.maximum = maximum
        self.reserveHeadroom = headroom; self.margin = deviceMargin
        self.measureRoot = measureRoot
        self.reserveURL = directory.appendingPathComponent("WagLockReserve.bin")
        self.configURL = directory.appendingPathComponent("WagLockStorageMode.json")
        self.freeSpace = freeSpace
    }

    // MARK: Configuration (app-wide, identical in every library)

    /// A missing file means Standard. An unreadable or malformed one fails closed with
    /// `.unavailable`, so writes stop rather than silently leaving Fixed mode.
    func config() throws -> Config {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return .standard }
        guard let data = try? Data(contentsOf: configURL), data.count < 4096,
              let value = try? JSONDecoder().decode(Config.self, from: data), value.version == 1,
              value.mode == .standard || (minimum...maximum).contains(value.targetBytes)
        else { throw Failure.unavailable }
        return value
    }

    private func write(_ value: Config) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: configURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        guard (try? Data(contentsOf: configURL)) == data else { throw Failure.unavailable }
    }

    // MARK: Measurement

    /// Bytes allocated by everything in WagLock's container except the reserve.
    func measureUsed() -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: measureRoot, includingPropertiesForKeys: keys) else { return 0 }
        let reservePath = reserveURL.resolvingSymlinksInPath().path
        var total: Int64 = 0
        for case let url as URL in walker {
            guard url.resolvingSymlinksInPath().path != reservePath,
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    func reserveBytes() -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: reserveURL.path)[.size] as? Int64) ?? 0
    }

    private func used() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        if let cachedUsed { return cachedUsed }
        let value = measureUsed(); cachedUsed = value; return value
    }

    /// Call after deletions or other changes outside `claim`.
    func invalidateUsage() { lock.lock(); cachedUsed = nil; lock.unlock() }

    // MARK: Claiming space for a write

    /// Takes `bytes` out of the reserve before a write. A no-op in Standard mode.
    func claim(_ bytes: Int64) throws {
        let current = try config()
        guard current.mode == .fixed else { return }
        guard bytes >= 0 else { throw Failure.full }
        let inUse = used()
        guard inUse + bytes + reserveHeadroom <= current.targetBytes else { throw Failure.full }
        try shrink(to: max(0, current.targetBytes - inUse - bytes - reserveHeadroom))
        lock.lock(); cachedUsed = inUse + bytes; lock.unlock()
    }

    private func shrink(to size: Int64) throws {
        guard reserveBytes() > size else { return }
        do {
            let handle = try FileHandle(forWritingTo: reserveURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(size))
        } catch { throw Failure.unavailable }
    }

    // MARK: Mode changes

    /// Bytes the reserve still needs to reach the target. Zero in Standard mode.
    func pendingGrowth() -> Int64 {
        guard let current = try? config(), current.mode == .fixed else { return 0 }
        return max(0, current.targetBytes - used() - reserveHeadroom - reserveBytes())
    }

    /// Validates a Fixed size against what WagLock holds and the iPhone's free space.
    func validate(targetBytes: Int64) throws {
        guard (minimum...maximum).contains(targetBytes) else { throw Failure.invalidSize }
        invalidateUsage()
        let inUse = used()
        guard inUse + reserveHeadroom * 2 <= targetBytes else { throw Failure.invalidSize }
        let growth = max(0, targetBytes - inUse - reserveHeadroom - reserveBytes())
        let free = (try? freeSpace(reserveURL.deletingLastPathComponent())) ?? 0
        guard growth + margin <= free else { throw Failure.insufficientDevice }
    }

    /// Largest size this iPhone can reserve now, in whole gigabytes (for the size picker).
    func largestAllowedBytes() -> Int64 {
        let free = (try? freeSpace(reserveURL.deletingLastPathComponent())) ?? 0
        let possible = used() + reserveBytes() + reserveHeadroom + max(0, free - margin)
        return min(maximum, possible / Self.gigabyte * Self.gigabyte)
    }

    /// Records Fixed mode at `targetBytes`; shrinks at once if the reserve is too large.
    /// Growth happens in `grow`, which can be paused and resumes where it stopped.
    func setFixed(targetBytes: Int64) throws {
        try validate(targetBytes: targetBytes)
        try write(Config(mode: .fixed, targetBytes: targetBytes))
        try shrink(to: max(0, targetBytes - used() - reserveHeadroom))
    }

    /// Standard mode: the reserve is deleted. No library data is touched.
    func setStandard() throws {
        try write(.standard)
        if FileManager.default.fileExists(atPath: reserveURL.path) {
            do { try FileManager.default.removeItem(at: reserveURL) } catch { throw Failure.unavailable }
        }
    }

    /// Brings the reserve back to size after deletions or an interrupted allocation.
    /// Writes pseudorandom chunks (AES-GCM keystream under a throwaway key) so the reserve
    /// is fully allocated and does not compress. Returns when done or when `shouldStop`.
    func grow(shouldStop: () -> Bool, progress: (_ written: Int64, _ total: Int64) -> Void) throws {
        invalidateUsage()
        let total = pendingGrowth()
        guard total > 0 else { progress(0, 0); return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: reserveURL.path) {
            guard fm.createFile(atPath: reserveURL.path, contents: nil,
                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
                throw Failure.unavailable
            }
            var url = reserveURL
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        let handle: FileHandle
        do { handle = try FileHandle(forWritingTo: reserveURL); try handle.seekToEnd() } catch { throw Failure.unavailable }
        defer { try? handle.close() }
        let key = SymmetricKey(size: .bits256)
        let zeros = Data(count: Self.chunkSize)
        var counter: UInt64 = 0
        var written: Int64 = 0
        while written < total, !shouldStop() {
            let count = Int(min(Int64(Self.chunkSize), total - written))
            var nonce = Data(count: 4)
            withUnsafeBytes(of: counter.bigEndian) { nonce.append(contentsOf: $0) }
            counter += 1
            guard let box = try? AES.GCM.seal(zeros.prefix(count), using: key, nonce: AES.GCM.Nonce(data: nonce)) else {
                throw Failure.unavailable
            }
            do { try handle.write(contentsOf: box.ciphertext) } catch { throw Failure.insufficientDevice }
            written += Int64(count)
            progress(written, total)
        }
        try? handle.synchronize()
    }

    static func deviceFreeSpace(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

extension Notification.Name {
    /// Posted after files are deleted so the reserve can grow back to size.
    static let wagLockStorageChanged = Notification.Name("WagLockStorageChanged")
}
