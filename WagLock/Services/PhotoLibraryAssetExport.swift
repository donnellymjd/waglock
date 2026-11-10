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
