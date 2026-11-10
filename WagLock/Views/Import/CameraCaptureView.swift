import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Takes a photo or video straight into WagLock. Nothing is saved to the camera roll:
/// the capture is written to an owned, protected temporary folder, imported like any
/// other file, and the temporary copy is removed.
struct CameraCaptureView: UIViewControllerRepresentable {
    let captured: (URL?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(captured) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let captured: (URL?) -> Void
        init(_ captured: @escaping (URL?) -> Void) { self.captured = captured }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { captured(nil) }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let movie = info[.mediaURL] as? URL {
                captured(try? CameraCaptureView.adopt(movie))
            } else if let image = info[.originalImage] as? UIImage {
                captured(try? CameraCaptureView.write(image, metadata: info[.mediaMetadata] as? [String: Any] ?? [:]))
            } else {
                captured(nil)
            }
        }
    }

    // MARK: Owned temporary files

    /// Same folder naming as other import copies, so abandoned ones are cleaned up at launch.
    static func ownedFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("waglock-media-import-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        return folder
    }

    private static func timestampName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Camera " + formatter.string(from: Date())
    }

    /// Encodes the still once (HEIC, or JPEG where HEIC encoding isn't available) with the
    /// camera's metadata. The camera supplies decoded pixels, so this is the original.
    static func write(_ image: UIImage, metadata: [String: Any]) throws -> URL {
        guard let cgImage = image.cgImage else { throw ImportError.loadFailed }
        let folder = try ownedFolder()
        do {
            let heic = UTType.heic.identifier as CFString
            let types = ((CGImageDestinationCopyTypeIdentifiers() as NSArray) as? [String]) ?? []
            let useHEIC = types.contains(heic as String)
            let url = folder.appendingPathComponent(timestampName() + (useHEIC ? ".HEIC" : ".JPG"))
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, useHEIC ? heic : UTType.jpeg.identifier as CFString, 1, nil)
            else { throw ImportError.saveFailed }
            var properties = metadata
            properties[kCGImagePropertyOrientation as String] = Self.exifOrientation(image.imageOrientation)
            properties[kCGImageDestinationLossyCompressionQuality as String] = 0.9
            CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw ImportError.saveFailed }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            return url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Moves the camera's own temporary movie into an owned folder.
    static func adopt(_ movie: URL) throws -> URL {
        let folder = try ownedFolder()
        do {
            let ext = movie.pathExtension.isEmpty ? "MOV" : movie.pathExtension
            let url = folder.appendingPathComponent(timestampName() + "." + ext)
            try FileManager.default.moveItem(at: movie, to: url)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            return url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: movie)
            throw error
        }
    }

    private static func exifOrientation(_ orientation: UIImage.Orientation) -> Int {
        switch orientation {
        case .up: 1
        case .upMirrored: 2
        case .down: 3
        case .downMirrored: 4
        case .leftMirrored: 5
        case .right: 6
        case .rightMirrored: 7
        case .left: 8
        @unknown default: 1
        }
    }
}
