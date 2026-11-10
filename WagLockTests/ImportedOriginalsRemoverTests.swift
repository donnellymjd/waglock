import XCTest
@testable import WagLock

/// Disposable files only. The decrypt closure stands in for FileStorageService.
@MainActor
final class ImportedOriginalsRemoverTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("originals-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func file(_ name: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// Returns a fresh decrypted-copy file holding `contents[path]`.
    private func decrypt(_ contents: [String: String]) -> ImportedOriginalsRemover.Decrypt {
        { path, _ in
            guard let text = contents[path] else { throw FileStorageError.fileNotFound }
            let url = self.root.appendingPathComponent("copy-" + UUID().uuidString)
            try Data(text.utf8).write(to: url)
            return url
        }
    }

    func testOnlyVerifiedOriginalsAreDeleted() async throws {
        let match = try file("match.pdf", "PUBLIC same bytes")
        let differs = try file("differs.pdf", "PUBLIC original")
        let missing = try file("missing.pdf", "PUBLIC no copy")
        let sources = [
            ImportedFileSource(original: match, encryptedPath: "a", fileExtension: ".pdf"),
            ImportedFileSource(original: differs, encryptedPath: "b", fileExtension: ".pdf"),
            ImportedFileSource(original: missing, encryptedPath: "c", fileExtension: ".pdf"),
        ]
        let outcome = await ImportedOriginalsRemover.remove(sources,
            decrypt: decrypt(["a": "PUBLIC same bytes", "b": "PUBLIC changed"]), stillAuthorized: { true })
        XCTAssertEqual(outcome, .init(deleted: 1, kept: 2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: match.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: differs.path), "A mismatched copy never deletes the original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: missing.path), "An unreadable copy never deletes the original")
        let copies = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("copy-") }
        XCTAssertTrue(copies.isEmpty, "Decrypted plaintext copies are removed")
    }

    func testLockStopsBeforeAnyDeletion() async throws {
        let original = try file("note.txt", "PUBLIC text")
        let outcome = await ImportedOriginalsRemover.remove(
            [ImportedFileSource(original: original, encryptedPath: "a", fileExtension: ".txt")],
            decrypt: decrypt(["a": "PUBLIC text"]), stillAuthorized: { false })
        XCTAssertEqual(outcome, .init(deleted: 0, kept: 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }
}
