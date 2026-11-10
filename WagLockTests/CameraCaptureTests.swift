import ImageIO
import UIKit
import XCTest
@testable import WagLock

/// No camera is used: captures are simulated with generated pixels and files.
@MainActor
final class CameraCaptureTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("camera-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testCapturedPhotoKeepsCameraMetadataAndImportsThenLeavesNoPlaintext() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 12)).image { context in
            UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        }
        let metadata: [String: Any] = [kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifLensModel as String: "PUBLIC test lens"]]
        let url = try CameraCaptureView.write(image, metadata: metadata)
        XCTAssertTrue(url.deletingLastPathComponent().lastPathComponent.hasPrefix("waglock-media-import-"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertEqual(exif?[kCGImagePropertyExifLensModel] as? String, "PUBLIC test lens")

        let storage = FileStorageService(directory: root.appendingPathComponent("Media"), availableCapacity: { _ in Int64.max })
        let items = try await MediaImportService(storage: storage).importOwnedFiles([url], password: "PUBLIC-camera")
        XCTAssertEqual(items.map(\.type), [.photo])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path),
                       "The plaintext capture folder is removed after import")
    }

    func testCapturedMovieIsMovedIntoAnOwnedFolder() throws {
        let cameraTemp = root.appendingPathComponent("capture.MOV")
        try Data(repeating: 1, count: 128).write(to: cameraTemp)
        let owned = try CameraCaptureView.adopt(cameraTemp)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cameraTemp.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertEqual(owned.pathExtension, "MOV")
        try? FileManager.default.removeItem(at: owned.deletingLastPathComponent())
    }
}
