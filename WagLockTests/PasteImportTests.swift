import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import WagLock

/// Pasted items arrive as NSItemProviders from the system Paste button.
@MainActor
final class PasteImportTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("paste-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func service() -> MediaImportService {
        MediaImportService(storage: FileStorageService(directory: root, availableCapacity: { _ in Int64.max }))
    }

    func testContentIsPreferredOverReferences() {
        XCTAssertNil(MediaImportService.pastedContentType([UTType.url.identifier, UTType.fileURL.identifier]))
        XCTAssertEqual(MediaImportService.pastedContentType([UTType.fileURL.identifier, UTType.pdf.identifier]),
                       UTType.pdf.identifier)
        XCTAssertEqual(MediaImportService.pastedContentType([UTType.utf8PlainText.identifier]), UTType.utf8PlainText.identifier)
    }

    func testPastedImageAndDocumentAreEncryptedAndTemporaryCopiesRemoved() async throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let image = NSItemProvider(item: png as NSData, typeIdentifier: UTType.png.identifier)
        let text = NSItemProvider(item: Data("PUBLIC pasted note".utf8) as NSData, typeIdentifier: UTType.utf8PlainText.identifier)
        let temporary = FileManager.default.temporaryDirectory.path
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: temporary).filter { $0.hasPrefix("waglock-media-import-") })
        let link = NSItemProvider(item: URL(string: "https://example.com")! as NSURL, typeIdentifier: UTType.url.identifier)
        let items = try await service().importPasted([image, text, link], password: "PUBLIC-paste-test")
        XCTAssertEqual(items.map(\.type), [.photo, .document], "A bare link is not a file and is skipped")
        for item in items {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(item.encryptedPath).path))
            let stored = try Data(contentsOf: root.appendingPathComponent(item.encryptedPath))
            XCTAssertNil(stored.range(of: Data("PUBLIC pasted note".utf8)), "Stored bytes are ciphertext")
        }
        let after = Set(try FileManager.default.contentsOfDirectory(atPath: temporary).filter { $0.hasPrefix("waglock-media-import-") })
        XCTAssertTrue(after.subtracting(before).isEmpty, "Owned temporary copies are removed after import")
    }
}
