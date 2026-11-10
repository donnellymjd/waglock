import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import Photos
import PhotosUI
import UniformTypeIdentifiers

/// Live Photos: a still plus a short paired video that share a content identifier.
/// WagLock stores both files unchanged and encrypted; see docs/portable-vault/live-photos.md.
nonisolated enum LivePhotoSupport {
    /// Kill switch. When false, imports keep only the still, as before.
    static let isEnabled = true

    /// Stable, distinct ID for the motion file when it travels as its own backup asset.
    static func motionAssetID(for stillID: UUID) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(("waglock.live-photo-motion:" + stillID.uuidString).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50 // name-based UUID shape (version 5 bits)
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: Content identifiers

    /// Apple maker note key 17 holds the pairing identifier in Live Photo stills.
    static func contentIdentifier(ofImage url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let maker = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any],
              let identifier = maker["17"] as? String, !identifier.isEmpty else { return nil }
        return identifier
    }

    /// QuickTime `com.apple.quicktime.content.identifier` in the paired video.
    static func contentIdentifier(ofVideo url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.metadata) else { return nil }
        for item in items where item.identifier == .quickTimeMetadataContentIdentifier {
            if let value = try? await item.load(.stringValue), !value.isEmpty { return value }
        }
        return nil
    }

    // MARK: Pairing files picked in Files

    struct FilePair: Equatable, Sendable { let still: URL; let video: URL }

    /// Pairs a still with a video only when they share a base name *and* the same
    /// content identifier. Everything else imports as separate items.
    static func pairs(in urls: [URL],
                      identifierOfImage: (URL) -> String? = { LivePhotoSupport.contentIdentifier(ofImage: $0) },
                      identifierOfVideo: (URL) async -> String? = { await LivePhotoSupport.contentIdentifier(ofVideo: $0) }) async -> [FilePair] {
        func key(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent.lowercased() }
        let stills = urls.filter { MediaType.from(fileExtension: $0.pathExtension) == .photo }
        let videos = Dictionary(grouping: urls.filter { MediaType.from(fileExtension: $0.pathExtension) == .video }, by: key)
        var result: [FilePair] = []
        for still in stills {
            guard let candidates = videos[key(still)], candidates.count == 1, let video = candidates.first,
                  let stillID = identifierOfImage(still) else { continue }
            if await identifierOfVideo(video) == stillID { result.append(FilePair(still: still, video: video)) }
        }
        return result
    }

    // MARK: Photos picker

    struct Resources: Sendable { let still: URL; let video: URL; let folder: URL }

    /// Writes the original still and paired video of a picked Live Photo into an owned,
    /// protected folder. Returns nil when the item isn't a Live Photo or iOS withholds
    /// either resource; the caller then imports the still alone.
    @MainActor
    static func resources(from provider: NSItemProvider) async -> Resources? {
        guard isEnabled, provider.canLoadObject(ofClass: PHLivePhoto.self) else { return nil }
        let live: PHLivePhoto? = await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: PHLivePhoto.self) { object, _ in continuation.resume(returning: object as? PHLivePhoto) }
        }
        guard let live else { return nil }
        let all = PHAssetResource.assetResources(for: live)
        guard let still = all.first(where: { $0.type == .photo }) ?? all.first(where: { $0.type == .fullSizePhoto }),
              let motion = all.first(where: { $0.type == .pairedVideo }) ?? all.first(where: { $0.type == .fullSizePairedVideo })
        else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("waglock-media-import-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
            let stillURL = folder.appendingPathComponent(safeName(still.originalFilename, fallback: "Live Photo.HEIC"))
            let videoURL = folder.appendingPathComponent(safeName(motion.originalFilename, fallback: "Live Photo.MOV"))
            try await write(still, to: stillURL)
            try await write(motion, to: videoURL)
            return Resources(still: stillURL, video: videoURL, folder: folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }

    private static func safeName(_ name: String, fallback: String) -> String {
        let last = URL(fileURLWithPath: name).lastPathComponent
        return last.isEmpty || last == "." || last == ".." ? fallback : last
    }

    private static func write(_ resource: PHAssetResource, to url: URL) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    // MARK: Save back to Photos

    enum SaveFailure: Error { case notAuthorized, failed }

    /// Rebuilds a real Live Photo in the person's library from decrypted copies.
    /// Needs add-only Photos access; asks only when the person chooses Save to Photos.
    @MainActor
    static func saveToPhotos(still: URL, video: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveFailure.notAuthorized }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: still, options: nil)
                request.addResource(with: .pairedVideo, fileURL: video, options: nil)
            }
        } catch { throw SaveFailure.failed }
    }
}
