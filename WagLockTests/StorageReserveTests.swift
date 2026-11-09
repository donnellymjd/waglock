import Foundation
import XCTest
@testable import WagLock

/// Disposable directories only; limits are scaled down to megabytes.
final class StorageReserveTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private final class Free: @unchecked Sendable { var bytes: Int64 = 1 << 40 }
    private let free = Free()
    private let mb: Int64 = 1_048_576

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("reserve-" + UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Application Support"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func make() -> StorageReserve {
        let free = self.free
        return StorageReserve(measureRoot: home, directory: home.appendingPathComponent("Library/Application Support"),
                              freeSpace: { _ in free.bytes }, minimum: 1 * mb, maximum: 64 * mb,
                              headroom: 64 * 1024, deviceMargin: 0)
    }

    private func addLibraryFile(_ bytes: Int) throws -> URL {
        let url = home.appendingPathComponent("Documents/" + UUID().uuidString)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    private func grow(_ reserve: StorageReserve) throws {
        try reserve.grow(shouldStop: { false }, progress: { _, _ in })
    }

    func testStandardModeNeverAllocatesOrBlocksWrites() throws {
        let reserve = make()
        XCTAssertEqual(try reserve.config().mode, .standard)
        try reserve.claim(500 * mb)
        try grow(reserve)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reserve.reserveURL.path))
    }

    func testFixedModeKeepsTheTotalConstantAsLibrariesGrowAndShrink() throws {
        let reserve = make()
        _ = try addLibraryFile(Int(2 * mb))
        try reserve.setFixed(targetBytes: 16 * mb)
        try grow(reserve)
        let total = reserve.measureUsed() + reserve.reserveBytes()
        XCTAssertEqual(Double(total), Double(16 * mb - 64 * 1024), accuracy: Double(mb) / 8)

        // A write takes its bytes out of the reserve first.
        try reserve.claim(3 * mb)
        let file = try addLibraryFile(Int(3 * mb))
        reserve.invalidateUsage()
        XCTAssertEqual(Double(reserve.measureUsed() + reserve.reserveBytes()), Double(total), accuracy: Double(mb) / 8)

        // Deleting gives the bytes back once the reserve regrows.
        try FileManager.default.removeItem(at: file)
        reserve.invalidateUsage()
        try grow(reserve)
        XCTAssertEqual(Double(reserve.measureUsed() + reserve.reserveBytes()), Double(total), accuracy: Double(mb) / 8)
    }

    func testFullReservedSpaceRejectsTheWriteAndChangesNothing() throws {
        let reserve = make()
        try reserve.setFixed(targetBytes: 4 * mb)
        try grow(reserve)
        let before = reserve.reserveBytes()
        XCTAssertThrowsError(try reserve.claim(5 * mb)) { XCTAssertEqual($0 as? StorageReserve.Failure, .full) }
        XCTAssertEqual(reserve.reserveBytes(), before)
    }

    func testSizesAreBoundedByWhatIsHeldAndByFreeDeviceSpace() throws {
        let reserve = make()
        _ = try addLibraryFile(Int(6 * mb))
        XCTAssertThrowsError(try reserve.setFixed(targetBytes: 4 * mb)) { XCTAssertEqual($0 as? StorageReserve.Failure, .invalidSize) }
        XCTAssertThrowsError(try reserve.setFixed(targetBytes: 128 * mb)) { XCTAssertEqual($0 as? StorageReserve.Failure, .invalidSize) }
        free.bytes = 2 * mb
        XCTAssertThrowsError(try reserve.setFixed(targetBytes: 32 * mb)) { XCTAssertEqual($0 as? StorageReserve.Failure, .insufficientDevice) }
        XCTAssertEqual(try reserve.config().mode, .standard, "A rejected size leaves the mode unchanged")
    }

    func testSwitchingToStandardReleasesOnlyTheReserve() throws {
        let reserve = make()
        let file = try addLibraryFile(Int(mb))
        try reserve.setFixed(targetBytes: 8 * mb)
        try grow(reserve)
        try reserve.setStandard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: reserve.reserveURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Library data is never touched")
        XCTAssertEqual(try reserve.config().mode, .standard)
    }

    func testInterruptedAllocationResumesWhereItStopped() throws {
        let reserve = make()
        try reserve.setFixed(targetBytes: 32 * mb)
        var chunks = 0
        try reserve.grow(shouldStop: { chunks >= 2 }, progress: { _, _ in chunks += 1 })
        let partial = reserve.reserveBytes()
        XCTAssertGreaterThan(partial, 0)
        XCTAssertGreaterThan(reserve.pendingGrowth(), 0)
        try grow(reserve)
        XCTAssertEqual(reserve.pendingGrowth(), 0)
        XCTAssertGreaterThan(reserve.reserveBytes(), partial)
    }

    func testReserveIsNotZerosAndIsExcludedFromDeviceBackup() throws {
        let reserve = make()
        try reserve.setFixed(targetBytes: 4 * mb)
        try grow(reserve)
        let sample = try FileHandle(forReadingFrom: reserve.reserveURL).read(upToCount: 65_536) ?? Data()
        XCTAssertGreaterThan(Set(sample).count, 200, "Pseudorandom filler, not a sparse or zero file")
        let values = try reserve.reserveURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testMalformedModeFailsClosed() throws {
        let reserve = make()
        try Data("not a mode".utf8).write(to: reserve.configURL)
        XCTAssertThrowsError(try reserve.claim(1)) { XCTAssertEqual($0 as? StorageReserve.Failure, .unavailable) }
    }

    func testFileStorageMapsAFullReserveToReservedSpaceFull() throws {
        let reserve = make()
        try reserve.setFixed(targetBytes: 2 * mb)
        let storage = FileStorageService(directory: home.appendingPathComponent("Documents/Media"),
                                         availableCapacity: { _ in Int64.max }, reserve: reserve)
        XCTAssertThrowsError(try storage.saveEncrypted(data: Data(count: Int(3 * mb)))) {
            XCTAssertEqual($0 as? FileStorageError, .reservedSpaceFull)
        }
    }
}
