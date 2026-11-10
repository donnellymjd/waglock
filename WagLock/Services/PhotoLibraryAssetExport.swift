import CoreGraphics
import Foundation
import Photos

/// Copies the resources of photo-library assets the person selected in WagLock's own
/// photo browser (the one with Select All) into owned, protected temporary folders.
/// The system picker has no Select All, so this path reads the library directly and
/// needs Photos access; the system picker remains available without it.
nonisolated enum PhotoLibraryAssetExport {
    /// What to copy for one asset.
    struct Choice<Resource> {
        let primary: Resource
        /// The paired video of a Live Photo, when the still and video are both available.
        let motion: Resource?
    }

    /// Picks the resources that match what the system picker hands over in `.current`
    /// mode: the current (edited) photo or video. Live Photos keep their original still
    /// and paired video together, the same as Live Photos from the system picker. A Live
    /// Photo missing its video imports as the still alone.
    static func choose<Resource>(_ resources: [Resource], isLivePhoto: Bool,
                                 type: (Resource) -> PHAssetResourceType) -> Choice<Resource>? {
        func first(_ kinds: PHAssetResourceType...) -> Resource? {
            for kind in kinds { if let match = resources.first(where: { type($0) == kind }) { return match } }
            return nil
        }
        if isLivePhoto, LivePhotoSupport.isEnabled,
           let still = first(.photo, .fullSizePhoto), let motion = first(.pairedVideo, .fullSizePairedVideo) {
            return Choice(primary: still, motion: motion)
        }
        if let video = first(.fullSizeVideo, .video) { return Choice(primary: video, motion: nil) }
        if let photo = first(.fullSizePhoto, .photo, .alternatePhoto) { return Choice(primary: photo, motion: nil) }
        return nil
    }

    struct Written: Sendable {
        let primary: URL
        let motion: URL?
        let folder: URL
    }

    /// Writes one asset's chosen resources into a new owned folder. Returns nil when the
    /// asset is gone or has nothing importable; the caller removes `folder` when done.
    static func write(localIdentifier: String) async throws -> Written? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let choice = choose(resources, isLivePhoto: asset.mediaSubtypes.contains(.photoLive), type: \.type) else { return nil }
        let folder = try ownedFolder()
        do {
            let primary = folder.appendingPathComponent(safeName(choice.primary.originalFilename,
                fallback: asset.mediaType == .video ? "Video.MOV" : "Photo.JPG"))
            try await write(choice.primary, to: primary)
            var motion: URL?
            if let resource = choice.motion {
                var url = folder.appendingPathComponent(safeName(resource.originalFilename, fallback: "Live Photo.MOV"))
                if url == primary { url = folder.appendingPathComponent("Live Photo motion.MOV") }
                try await write(resource, to: url)
                motion = url
            }
            return Written(primary: primary, motion: motion, folder: folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Same folder naming as other import copies, so abandoned ones are cleaned up at launch.
    static func ownedFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("waglock-media-import-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        return folder
    }

    static func safeName(_ name: String, fallback: String) -> String {
        guard !name.isEmpty else { return fallback }
        let last = URL(fileURLWithPath: name).lastPathComponent
        return last.isEmpty || last == "." || last == ".." || last == "/" ? fallback : last
    }

    private static func write(_ resource: PHAssetResource, to url: URL) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true // iCloud originals download through iOS, as in the system picker.
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
}

/// Selection in WagLock's photo browser: tap to toggle, Select All for the album shown.
/// Keeps the order items were shown in so imports follow the album order.
struct PhotoLibrarySelection: Equatable {
    private(set) var selected: Set<String> = []
    private(set) var order: [String] = []

    var count: Int { selected.count }
    var isEmpty: Bool { selected.isEmpty }
    func contains(_ id: String) -> Bool { selected.contains(id) }

    /// True when every identifier shown is selected (and something is shown).
    func allSelected(_ shown: [String]) -> Bool { !shown.isEmpty && shown.allSatisfy(selected.contains) }

    mutating func toggle(_ id: String) {
        if selected.remove(id) != nil { order.removeAll { $0 == id } } else { selected.insert(id); order.append(id) }
    }

    /// Adds every shown item, keeping earlier picks from other albums.
    mutating func selectAll(_ shown: [String]) {
        for id in shown where selected.insert(id).inserted { order.append(id) }
    }

    /// Removes the shown items only; picks from other albums stay selected.
    mutating func deselectAll(_ shown: [String]) {
        let removing = Set(shown)
        selected.subtract(removing)
        order.removeAll(where: removing.contains)
    }

    /// Identifiers in the order they were selected.
    var identifiers: [String] { order }
}

/// Drag to select in the photo browser, as in Photos: the start tile decides whether the
/// drag selects or deselects, the range from the start tile to the finger takes that
/// state, and moving back gives the tiles left behind their earlier state.
struct PhotoDragSelection: Equatable {
    let anchor: Int
    let selecting: Bool
    let before: PhotoLibrarySelection

    init(anchor: Int, shown: [String], selection: PhotoLibrarySelection) {
        self.anchor = anchor
        self.before = selection
        selecting = shown.indices.contains(anchor) ? !selection.contains(shown[anchor]) : true
    }

    func selection(shown: [String], current: Int) -> PhotoLibrarySelection {
        guard !shown.isEmpty, shown.indices.contains(anchor) else { return before }
        let end = min(max(current, 0), shown.count - 1)
        let ids = anchor <= end ? Array(shown[anchor...end]) : Array(shown[end...anchor].reversed())
        var result = before
        if selecting { result.selectAll(ids) } else { result.deselectAll(ids) }
        return result
    }
}

/// Which tile of a fixed-column grid is under a point, in the grid's own coordinates.
enum PhotoGridGeometry {
    static func columns(width: CGFloat, minimumTile: CGFloat = 96, spacing: CGFloat = 2) -> Int {
        max(3, Int((width + spacing) / (minimumTile + spacing)))
    }

    static func index(at point: CGPoint, width: CGFloat, columns: Int, spacing: CGFloat = 2, count: Int) -> Int? {
        guard width > 0, columns > 0, count > 0 else { return nil }
        let tile = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let column = min(max(Int(point.x / (tile + spacing)), 0), columns - 1)
        let row = max(Int(point.y / (tile + spacing)), 0)
        return min(row * columns + column, count - 1)
    }

    /// Edge auto-scroll during a drag: direction (-1 up, 0 none, 1 down) and how long each
    /// row step takes. Within `edge` points of the top or bottom it scrolls; the closer
    /// to the edge (or past it), the faster.
    static func autoScrollStep(fingerY: CGFloat, viewportHeight: CGFloat, edge: CGFloat = 70)
        -> (direction: Int, interval: Double) {
        guard viewportHeight > edge * 2 else { return (0, 0) }
        let depth: CGFloat
        let direction: Int
        if fingerY > viewportHeight - edge { direction = 1; depth = fingerY - (viewportHeight - edge) }
        else if fingerY < edge { direction = -1; depth = edge - fingerY }
        else { return (0, 0) }
        let closeness = min(max(depth / edge, 0), 1)       // 0 at the zone's inner line, 1 at the edge or beyond
        return (direction, 0.25 - 0.17 * Double(closeness)) // 0.25 s per row down to 0.08 s
    }

    /// The tile to scroll to so one more row shows past the edge being dragged towards.
    static func autoScrollTarget(direction: Int, gridTop: CGFloat, viewportHeight: CGFloat, width: CGFloat,
                                 columns: Int, spacing: CGFloat = 2, count: Int) -> Int? {
        guard direction != 0, width > 0, columns > 0, count > 0 else { return nil }
        let tile = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let edgeY = (direction > 0 ? viewportHeight : 0) - gridTop  // the edge, in grid coordinates
        let edgeRow = Int(floor(edgeY / (tile + spacing)))
        let lastRow = (count - 1) / columns
        let row = min(max(edgeRow + direction, 0), lastRow)
        if direction > 0, edgeRow >= lastRow { return nil }     // already at the bottom
        if direction < 0, edgeY <= 0 { return nil }              // already at the top
        return min(row * columns, count - 1)
    }
}
