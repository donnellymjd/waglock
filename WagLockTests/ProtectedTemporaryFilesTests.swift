import Foundation
import XCTest
@testable import WagLock

final class ProtectedTemporaryFilesTests: XCTestCase {
    func testStartupRemovesOnlyMarkedAbandonedJobsAndPreservesForeignFilesAndSymlinks() throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory.appendingPathComponent("plaintext-test-" + UUID().uuidString)
        try fm.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: parent) }
        let root = parent.appendingPathComponent("owned")
        let preview = try ProtectedTemporaryFiles.fileURL(preferredExtension: "../pdf", in: root)
        XCTAssertEqual(preview.pathExtension, "pdf")
        try Data("PUBLIC decrypted content".utf8).write(to: preview, options: .completeFileProtection)
        let foreign = parent.appendingPathComponent("foreign.txt")
        try Data("PUBLIC preserve".utf8).write(to: foreign)
        let unknown = root.appendingPathComponent("unknown.txt")
        try Data([1]).write(to: unknown)
        let unmarked = root.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: unmarked, withIntermediateDirectories: false)
        let linked = root.appendingPathComponent(UUID().uuidString)
        try fm.createSymbolicLink(at: linked, withDestinationURL: parent)
        ProtectedTemporaryFiles.removeAbandonedJobs(in: root)
        XCTAssertFalse(fm.fileExists(atPath: preview.path))
        XCTAssertTrue(fm.fileExists(atPath: unmarked.path))
        XCTAssertTrue(fm.fileExists(atPath: unknown.path))
        XCTAssertEqual(try Data(contentsOf: foreign), Data("PUBLIC preserve".utf8))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: linked.path), parent.path)
    }

    func testUnknownOrSymlinkRootsAreRejectedWithoutDeletingTheirContents() throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory.appendingPathComponent("plaintext-root-test-" + UUID().uuidString)
        try fm.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: parent) }
        let marker = parent.appendingPathComponent("unknown.txt")
        try Data([1]).write(to: marker)
        XCTAssertThrowsError(try ProtectedTemporaryFiles.createDirectory(in: parent))
        ProtectedTemporaryFiles.removeAbandonedJobs(in: parent)
        XCTAssertTrue(fm.fileExists(atPath: marker.path))
        let symlink = parent.appendingPathComponent("linked")
        try fm.createSymbolicLink(at: symlink, withDestinationURL: parent)
        XCTAssertThrowsError(try ProtectedTemporaryFiles.createDirectory(in: symlink))
        ProtectedTemporaryFiles.removeAbandonedJobs(in: symlink)
        XCTAssertTrue(fm.fileExists(atPath: marker.path))
    }
}
