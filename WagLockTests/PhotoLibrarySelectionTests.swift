import Photos
import XCTest
@testable import WagLock

/// The Select All browser's selection model and resource choice. No photo library is used.
@MainActor
final class PhotoLibrarySelectionTests: XCTestCase {
    private struct Resource: Equatable { let type: PHAssetResourceType; let name: String }

    func testSelectAllAddsEveryShownItemOnceAndKeepsOrder() {
        var selection = PhotoLibrarySelection()
        selection.toggle("b")
        selection.selectAll(["a", "b", "c"])
        XCTAssertEqual(selection.identifiers, ["b", "a", "c"])
        XCTAssertTrue(selection.allSelected(["a", "b", "c"]))
        selection.selectAll(["a", "b", "c"])
        XCTAssertEqual(selection.count, 3)
    }

    func testDeselectAllRemovesOnlyTheShownAlbum() {
        var selection = PhotoLibrarySelection()
        selection.selectAll(["x", "y"])        // another album
        selection.selectAll(["a", "b"])
        selection.deselectAll(["a", "b"])
        XCTAssertEqual(selection.identifiers, ["x", "y"])
        XCTAssertFalse(selection.allSelected(["a", "b"]))
    }

    func testToggleAndEmptyAlbum() {
        var selection = PhotoLibrarySelection()
        selection.toggle("a"); selection.toggle("a")
        XCTAssertTrue(selection.isEmpty)
        XCTAssertFalse(selection.allSelected([]), "Select All has nothing to select in an empty album")
    }

    func testLivePhotoKeepsStillAndPairedVideo() throws {
        let resources = [Resource(type: .photo, name: "IMG.HEIC"), Resource(type: .pairedVideo, name: "IMG.MOV"),
                         Resource(type: .fullSizePhoto, name: "FullSizeRender.HEIC")]
        let choice = try XCTUnwrap(PhotoLibraryAssetExport.choose(resources, isLivePhoto: true, type: \.type))
        XCTAssertEqual(choice.primary.name, "IMG.HEIC")
        XCTAssertEqual(choice.motion?.name, "IMG.MOV")
    }

    func testLivePhotoWithoutVideoImportsTheCurrentStill() throws {
        let resources = [Resource(type: .photo, name: "IMG.HEIC"), Resource(type: .fullSizePhoto, name: "FullSizeRender.HEIC")]
        let choice = try XCTUnwrap(PhotoLibraryAssetExport.choose(resources, isLivePhoto: true, type: \.type))
        XCTAssertEqual(choice.primary.name, "FullSizeRender.HEIC")
        XCTAssertNil(choice.motion)
    }

    func testEditedPhotoAndVideoUseTheCurrentVersionLikeTheSystemPicker() throws {
        let photo = [Resource(type: .photo, name: "IMG.JPG"), Resource(type: .fullSizePhoto, name: "Edited.JPG")]
        XCTAssertEqual(PhotoLibraryAssetExport.choose(photo, isLivePhoto: false, type: \.type)?.primary.name, "Edited.JPG")
        let video = [Resource(type: .video, name: "IMG.MOV"), Resource(type: .fullSizeVideo, name: "Edited.MOV")]
        let choice = try XCTUnwrap(PhotoLibraryAssetExport.choose(video, isLivePhoto: false, type: \.type))
        XCTAssertEqual(choice.primary.name, "Edited.MOV")
        XCTAssertNil(choice.motion)
        let plain = [Resource(type: .photo, name: "IMG.HEIC")]
        XCTAssertEqual(PhotoLibraryAssetExport.choose(plain, isLivePhoto: false, type: \.type)?.primary.name, "IMG.HEIC")
    }

    func testNothingImportableAndUnsafeNames() {
        XCTAssertNil(PhotoLibraryAssetExport.choose([Resource(type: .adjustmentData, name: "x.plist")], isLivePhoto: false, type: \.type))
        XCTAssertEqual(PhotoLibraryAssetExport.safeName("../../evil.JPG", fallback: "Photo.JPG"), "evil.JPG")
        XCTAssertEqual(PhotoLibraryAssetExport.safeName("", fallback: "Photo.JPG"), "Photo.JPG")
        XCTAssertEqual(PhotoLibraryAssetExport.safeName("..", fallback: "Photo.JPG"), "Photo.JPG")
    }

    func testOwnedFolderIsPrivateAndUsesTheImportPrefix() throws {
        let folder = try PhotoLibraryAssetExport.ownedFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertTrue(folder.lastPathComponent.hasPrefix("waglock-media-import-"))
        let permissions = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o700)
    }
}
