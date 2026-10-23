import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import WagLock

@MainActor
final class OriginalImageImportTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDown() { for root in roots { try? FileManager.default.removeItem(at: root) }; roots = [] }
    private func fixture() throws -> (URL, FileStorageService, MediaImportService) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("original-image-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); roots.append(root)
        let storage = FileStorageService(directory: root.appendingPathComponent("encrypted"), availableCapacity: { _ in Int64.max })
        return (root, storage, MediaImportService(storage: storage))
    }
    private func image() throws -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 48, height: 32), format: format).image { context in
            UIColor.systemBlue.withAlphaComponent(0.5).setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        }
    }
    func testJPEGBytesEXIFOrientationAndUnicodeNameArePreserved() throws {
        let (root, storage, importer) = try fixture()
        let bytes = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(image().cgImage), [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:01:02 03:04:05"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let source = root.appendingPathComponent("cafe\u{301} original.jpeg")
        try (bytes as Data).write(to: source)
        let item = try importer.processOriginalImage(source, password: "PUBLIC-image-password")
        XCTAssertEqual(Array(item.fileName.utf8), Array("cafe\u{301} original".utf8))
        XCTAssertEqual(item.fileExtension, ".jpeg"); XCTAssertEqual(item.fileSize, Int64(bytes.length))
        XCTAssertEqual(item.width, 32); XCTAssertEqual(item.height, 48); XCTAssertNotNil(item.thumbnailData)
        let output = root.appendingPathComponent("recovered.jpeg")
        try EncryptionService.shared.decryptFile(inputURL: storage.getFileURL(for: item.encryptedPath), to: output, password: "PUBLIC-image-password")
        XCTAssertEqual(try Data(contentsOf: output), bytes as Data)
        XCTAssertEqual(try Data(contentsOf: source), bytes as Data)
    }
    func testPNGAlphaAndOriginalEncodingAreNotConvertedToJPEG() throws {
        let (root, storage, importer) = try fixture()
        let bytes = try XCTUnwrap(image().pngData()), source = root.appendingPathComponent("Transparent.png")
        try bytes.write(to: source)
        let item = try importer.processOriginalImage(source, password: "PUBLIC-image-password")
        XCTAssertEqual(item.fileExtension, ".png")
        let output = root.appendingPathComponent("recovered.png")
        try EncryptionService.shared.decryptFile(inputURL: storage.getFileURL(for: item.encryptedPath), to: output, password: "PUBLIC-image-password")
        XCTAssertEqual(try Data(contentsOf: output), bytes)
    }
    func testInvalidRepresentationPublishesNoCiphertext() throws {
        let (root, storage, importer) = try fixture()
        let source = root.appendingPathComponent("invalid.png"); try Data("not an image".utf8).write(to: source)
        XCTAssertThrowsError(try importer.processOriginalImage(source, password: "PUBLIC-image-password"))
        XCTAssertTrue(storage.getAllEncryptedFiles().isEmpty)
    }
    func testProviderRepresentationUsesOriginalBytesAndCleansItsOwnedCopy() async throws {
        let (root, storage, importer) = try fixture()
        let source = root.appendingPathComponent("provider.png"), bytes = try XCTUnwrap(image().pngData())
        try bytes.write(to: source)
        let provider = NSItemProvider(); provider.suggestedName = "Kept original.png"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(source, false, nil); return nil
        }
        let imported = try await importer.importImage(from: provider, password: "PUBLIC-image-password")
        let item = try XCTUnwrap(imported)
        XCTAssertEqual(item.fileName, "Kept original")
        let output = root.appendingPathComponent("recovered.png")
        try EncryptionService.shared.decryptFile(inputURL: storage.getFileURL(for: item.encryptedPath), to: output, password: "PUBLIC-image-password")
        XCTAssertEqual(try Data(contentsOf: output), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
}
