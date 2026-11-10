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

    func testDragSelectsTheRunAndMovingBackRestoresEarlierState() {
        let shown = ["a", "b", "c", "d", "e"]
        var before = PhotoLibrarySelection()
        before.toggle("d")                       // picked earlier by tap
        let drag = PhotoDragSelection(anchor: 1, shown: shown, selection: before)
        XCTAssertTrue(drag.selecting, "Starting on an unselected tile selects")
        XCTAssertEqual(Set(drag.selection(shown: shown, current: 3).identifiers), ["b", "c", "d"])
        // Back towards the start: c and d go back to how they were (d stays picked).
        XCTAssertEqual(Set(drag.selection(shown: shown, current: 1).identifiers), ["b", "d"])
        // Past the start in the other direction.
        XCTAssertEqual(Set(drag.selection(shown: shown, current: 0).identifiers), ["a", "b", "d"])
        // Beyond the ends is clamped.
        XCTAssertEqual(drag.selection(shown: shown, current: 99).count, 4)
    }

    func testDragStartingOnASelectedTileDeselects() {
        let shown = ["a", "b", "c", "d"]
        var before = PhotoLibrarySelection()
        before.selectAll(shown)
        before.selectAll(["other-album"])
        let drag = PhotoDragSelection(anchor: 2, shown: shown, selection: before)
        XCTAssertFalse(drag.selecting)
        XCTAssertEqual(Set(drag.selection(shown: shown, current: 0).identifiers), ["d", "other-album"])
        XCTAssertEqual(drag.selection(shown: [], current: 0), before)
    }

    func testGridHitTesting() {
        // 3 columns of 98-pt tiles with 2-pt spacing in a 298-pt grid.
        XCTAssertEqual(PhotoGridGeometry.columns(width: 298), 3)
        XCTAssertEqual(PhotoGridGeometry.columns(width: 0), 3)
        XCTAssertEqual(PhotoGridGeometry.columns(width: 800), 8)
        func index(_ x: CGFloat, _ y: CGFloat, count: Int = 100) -> Int? {
            PhotoGridGeometry.index(at: CGPoint(x: x, y: y), width: 298, columns: 3, count: count)
        }
        XCTAssertEqual(index(10, 10), 0)
        XCTAssertEqual(index(150, 10), 1)
        XCTAssertEqual(index(290, 10), 2)
        XCTAssertEqual(index(10, 110), 3)
        XCTAssertEqual(index(-20, -20), 0, "Outside the grid clamps to the nearest tile")
        XCTAssertEqual(index(500, 10), 2)
        XCTAssertEqual(index(10, 10_000, count: 7), 6, "Below the last row clamps to the last tile")
        XCTAssertNil(PhotoGridGeometry.index(at: .zero, width: 298, columns: 3, count: 0))
    }
}
