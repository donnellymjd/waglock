import Foundation
import UIKit
import XCTest
@testable import WagLock

/// Disposable files only; pairing identifiers are injected so no real Live Photo is needed.
@MainActor
final class LivePhotoSupportTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("live-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func touch(_ name: String, _ data: Data = Data("PUBLIC".utf8)) throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    func testMotionAssetIDIsStableDistinctAndNameBased() {
        let still = UUID()
        let motion = LivePhotoSupport.motionAssetID(for: still)
        XCTAssertEqual(motion, LivePhotoSupport.motionAssetID(for: still))
        XCTAssertNotEqual(motion, still)
        XCTAssertNotEqual(motion, LivePhotoSupport.motionAssetID(for: UUID()))
        XCTAssertEqual(motion.uuidString[motion.uuidString.index(motion.uuidString.startIndex, offsetBy: 14)], "5")
    }

    func testFilesPairOnlyWithMatchingNameAndContentIdentifier() async throws {
        let a = try touch("IMG_0001.HEIC"), aVideo = try touch("IMG_0001.MOV")
        let b = try touch("IMG_0002.HEIC"), bVideo = try touch("IMG_0002.MOV")
        let c = try touch("IMG_0003.JPG"), d = try touch("Other.MOV")
        let images: [URL: String] = [a: "A", b: "B", c: "C"]
        let videos: [URL: String] = [aVideo: "A", bVideo: "different", d: "C"]
        let pairs = await LivePhotoSupport.pairs(in: [a, aVideo, b, bVideo, c, d],
                                                 identifierOfImage: { images[$0] }, identifierOfVideo: { videos[$0] })
        XCTAssertEqual(pairs, [LivePhotoSupport.FilePair(still: a, video: aVideo)],
                       "Mismatched identifiers and different base names stay separate items")
    }

    func testLivePhotoImportStoresBothFilesAsOneItem() async throws {
        let storage = FileStorageService(directory: root.appendingPathComponent("Media"), availableCapacity: { _ in Int64.max })
        let still = try touch("IMG_0004.PNG", png())
        let video = try touch("IMG_0004.MOV", Data(repeating: 3, count: 4096))
        let item = try await MediaImportService(storage: storage).importLivePhoto(still: still, video: video, password: "PUBLIC-live")
        XCTAssertTrue(item.isLivePhoto)
        XCTAssertEqual(item.type, .photo)
        XCTAssertEqual(item.livePhotoVideoExtension, ".MOV")
        XCTAssertEqual(item.encryptedPaths.count, 2)
        for path in item.encryptedPaths { XCTAssertTrue(storage.fileExists(path: path)) }
    }

    func testMotionThatCannotBeSavedRemovesTheStillToo() async throws {
        final class Calls: @unchecked Sendable { var count = 0 }
        let calls = Calls()
        let storage = FileStorageService(directory: root.appendingPathComponent("Media"), availableCapacity: { _ in
            calls.count += 1
            return calls.count == 1 ? Int64.max : 0 // Room for the still, none for the motion.
        })
        let still = try touch("IMG_0005.PNG", png())
        let video = try touch("IMG_0005.MOV", Data(repeating: 3, count: 4096))
        do {
            _ = try await MediaImportService(storage: storage).importLivePhoto(still: still, video: video, password: "PUBLIC-live")
            XCTFail("A half pair must not be kept")
        } catch {}
        XCTAssertTrue(storage.getAllEncryptedFiles().isEmpty, "No orphaned still remains")
    }

    func testRecordsWrittenBeforeLivePhotosDecodeWithoutMotion() throws {
        let json = """
        {"id":"\(UUID().uuidString)","fileName":"IMG","fileExtension":".jpg","fileSize":1,"typeRawValue":"photo",
         "encryptedPath":"x.encrypted","createdAt":0,"modifiedAt":0}
        """
        let media = try JSONDecoder().decode(MetadataModelCodec.Media.self, from: Data(json.utf8))
        XCTAssertNil(media.livePhotoVideoPath)
        XCTAssertNil(media.livePhotoVideoExtension)
    }
}
