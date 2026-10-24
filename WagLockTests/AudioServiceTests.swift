import AVFoundation
import SwiftData
import UniformTypeIdentifiers
import XCTest
import SwiftUI
import UIKit

@testable import WagLock

@MainActor
final class AudioServiceTests: XCTestCase {
    func testAudioDetectionDoesNotReclassifyVideoOrDocuments() {
        for ext in ["m4a", ".MP3", "wav", "aiff", "aac", "caf", "flac"] {
            XCTAssertEqual(MediaType.from(fileExtension: ext), .audio)
            XCTAssertTrue(MediaType.audio.matches(fileExtension: ext))
            XCTAssertFalse(MediaType.document.matches(fileExtension: ext))
        }
        XCTAssertEqual(MediaType.from(utType: .audio), .audio)
        XCTAssertEqual(MediaType.from(mimeType: "audio/mpeg"), .audio)
        XCTAssertEqual(MediaType.from(fileExtension: "mp4"), .video)
        XCTAssertEqual(MediaType.from(fileExtension: "pdf"), .document)
        XCTAssertEqual(MediaType.from(fileExtension: "jpg"), .photo)
        XCTAssertEqual(MediaType(rawValue: "document"), .document)
    }

    func testLegacyAudioIsVisibleWithoutChangingStoredRawValue() throws {
        let container = try ModelContainer(for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let item = MediaItem(fileName: "Old memo", fileExtension: ".M4A",
                             fileSize: 100, type: .document, encryptedPath: "legacy")
        container.mainContext.insert(item)
        try container.mainContext.save()
        let restored = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<MediaItem>()).first)
        XCTAssertEqual(restored.type, .audio)
        XCTAssertEqual(restored.typeRawValue, "document")
    }

    func testPlayableAudioEncryptsAndRoundTrips() async throws {
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = try Data(contentsOf: url)
        let item = try await AudioImportService.importFile(url: url, password: "audio-test-password")
        defer { try? FileStorageService.shared.deleteFile(path: item.encryptedPath) }
        XCTAssertEqual(item.type, .audio)
        XCTAssertEqual(item.fileExtension, ".wav")
        XCTAssertEqual(item.duration ?? 0, 0.25, accuracy: 0.01)
        XCTAssertEqual(item.fileSize, Int64(original.count))
        XCTAssertNotEqual(try FileStorageService.shared.loadEncrypted(path: item.encryptedPath), original)
        let decrypted = try await FileStorageService.shared.createDecryptedTempFileAsync(
            path: item.encryptedPath, password: "audio-test-password", preferredExtension: item.fileExtension)
        defer { try? FileManager.default.removeItem(at: decrypted) }
        XCTAssertEqual(try Data(contentsOf: decrypted), original)
        let player = try AVAudioPlayer(contentsOf: decrypted)
        XCTAssertEqual(player.duration, 0.25, accuracy: 0.01)
        try await capturePlayerForVisualReview(item)

    }

    func testAudioImportsUseTheSuppliedVaultWithoutReadingAnotherRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("audio-domains-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storageA = FileStorageService(directory: root.appendingPathComponent("a"), availableCapacity: { _ in 1_000_000_000 })
        let storageB = FileStorageService(directory: root.appendingPathComponent("b"), availableCapacity: { _ in 1_000_000_000 })
        let source = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: source) }
        let original = try Data(contentsOf: source)
        let a = try await AudioImportService.importFile(url: source, password: "PUBLIC audio key A", storage: storageA)
        let b = try await AudioImportService.importFile(url: source, password: "PUBLIC audio key B", storage: storageB)
        XCTAssertFalse(storageB.fileExists(path: a.encryptedPath))
        XCTAssertFalse(storageA.fileExists(path: b.encryptedPath))
        let bytesA = try await storageA.loadDecryptedDataAsync(path: a.encryptedPath, password: "PUBLIC audio key A", preferredExtension: "wav")
        let bytesB = try await storageB.loadDecryptedDataAsync(path: b.encryptedPath, password: "PUBLIC audio key B", preferredExtension: "wav")
        XCTAssertEqual(bytesA, original); XCTAssertEqual(bytesB, original)
        XCTAssertThrowsError(try storageB.getFileURL(for: storageA.getFileURL(for: a.encryptedPath).path))
        let savedA = try storageA.loadEncrypted(path: a.encryptedPath)
        try storageB.deleteFile(path: b.encryptedPath)
        XCTAssertEqual(try storageA.loadEncrypted(path: a.encryptedPath), savedA)
    }

    private func capturePlayerForVisualReview(_ item: MediaItem) async throws {
        let controller = AudioSessionController(directory: FileManager.default.temporaryDirectory.appendingPathComponent("audio-ui-" + UUID().uuidString))
        defer { controller.cleanup() }
        let sheet = AudioPlaybackSheet(item: MediaPreviewSnapshot(item), audio: controller,
            onToggle: { controller.togglePlayback(item: item, password: "audio-test-password") }, onExport: {})
        let host = UIHostingController(rootView: sheet)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let prior = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; prior?.makeKey() }
        for (name, style) in [("Light", UIUserInterfaceStyle.light), ("Dark", .dark)] {
            window.overrideUserInterfaceStyle = style
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let shot = XCTAttachment(image: image); shot.name = "\(name) - generated audio player"; shot.lifetime = .keepAlways; add(shot)
        }
    }

    func testInvalidAudioDoesNotWriteEncryptedFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try Data("not audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let before = Set(FileStorageService.shared.getAllEncryptedFiles())
        do {
            _ = try await AudioImportService.importFile(url: url, password: "audio-test-password")
            XCTFail("Corrupt audio must be rejected")
        } catch {}
        XCTAssertEqual(Set(FileStorageService.shared.getAllEncryptedFiles()), before)
    }

    func testCancelledImportDoesNotWriteEncryptedFile() async throws {
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let before = Set(FileStorageService.shared.getAllEncryptedFiles())
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await AudioImportService.importFile(url: url, password: "audio-test-password")
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(Set(FileStorageService.shared.getAllEncryptedFiles()), before)
    }

    func testControllerRemovesAbandonedRecordingsOnLaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("abandoned.m4a")
        try Data("private recording".utf8).write(to: url)
        let controller = AudioSessionController(directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        controller.pauseForInterruption()
        controller.cleanup()
        XCTAssertFalse(controller.isRecording)
        XCTAssertFalse(controller.hasRecording)
        XCTAssertNil(controller.recordingURL)
        XCTAssertNil(controller.playingID)
    }

    func testAudioExportPreservesOriginalBytes() async throws {
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let originalData = try Data(contentsOf: url)
        let item = try await AudioImportService.importFile(url: url, password: "audio-export-test-password")
        defer { try? FileStorageService.shared.deleteFile(path: item.encryptedPath) }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "test_share_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shareURL = tempDir.appendingPathComponent(item.fullFileName)
        let sourceURL = try FileStorageService.shared.getFileURL(for: item.encryptedPath)
        try EncryptionService.shared.decryptFile(inputURL: sourceURL, to: shareURL, password: "audio-export-test-password")

        XCTAssertTrue(FileManager.default.fileExists(atPath: shareURL.path))
        XCTAssertEqual(try Data(contentsOf: shareURL), originalData)
    }

    private func makeAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 11_025))
        buffer.frameLength = 11_025
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(buffer.frameLength) {
            samples[index] = Float(sin(Double(index) * 2 * .pi * 440 / 44_100)) * 0.2
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
