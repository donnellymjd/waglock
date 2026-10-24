import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import WagLock

@MainActor
final class PhotoPreviewRenderingTests: XCTestCase {
    func testPhotoPagerSurvivesLogoutAfterItsStoreIsReleased() async throws {
        try await exercise(video: false)
    }

    func testVideoViewerSurvivesLogoutAfterItsStoreIsReleased() async throws {
        try await exercise(video: true)
    }

    func testLateGenericVideoPlaintextIsRemovedAfterLogout() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("late-preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LateVideoPreviewGate()
        let storage = FileStorageService(directory: root.appendingPathComponent("media"), availableCapacity: { _ in Int64.max })
        let password = "PUBLIC-late-preview-password"
        let source = root.appendingPathComponent("PUBLIC-source")
        try Data("PUBLIC owned plaintext sample".utf8).write(to: source)
        let path = try storage.saveEncryptedFile(from: source, password: password)
        let credentials = KeychainService(service: UUID().uuidString, storage: InMemoryAttemptStorage())
        try credentials.savePassword(password)
        let auth = AuthenticationViewModel(keychainService: credentials, manageInstallationState: false,
            contextFactory: { id, session, secret in
                try VaultSessionContext(vaultID: id ?? UUID(), sessionID: session, dataPassword: secret,
                    storage: storage, temporaryRoot: root, keychainNamespace: "PUBLIC-" + root.lastPathComponent)
            })
        defer { auth.logout() }
        auth.password = password; await auth.login()?.value
        let services = try XCTUnwrap(auth.vaultContext)
        let item = MediaItem(fileName: "PUBLIC late preview", fileExtension: "mp4", fileSize: 28,
            type: .video, encryptedPath: path)
        let host = UIHostingController(rootView: MediaDetailView(mediaItem: item, sessionID: auth.librarySessionID,
            videoLoader: { storage, path, password, ext in
                let output = try await storage.createDecryptedTempFileAsync(path: path, password: password, preferredExtension: ext)
                await gate.pause(output)
                return output
            })
            .environmentObject(auth).environmentObject(services).environmentObject(services.exports))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let output = try await gate.waitUntilPaused()
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        auth.logout()
        await gate.resume()
        let deadline = Date().addingTimeInterval(5)
        while FileManager.default.fileExists(atPath: output.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path), "Late plaintext must not attach to a revoked view")
        XCTAssertTrue(storage.fileExists(path: path))
    }

    private func exercise(video: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("photo-teardown-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        var container: ModelContainer? = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: root.appendingPathComponent("fixture.store"))])
        var context: ModelContext? = ModelContext(try XCTUnwrap(container))
        context?.autosaveEnabled = false
        let password = "disposable-photo-password"
        // Rendering uses the production storage reader: fixtures must be inside its owned root.
        // Cleanup removes only the ciphertext created by this test, never other media.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storage = FileStorageService.shared
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 80))
        let bytes = try XCTUnwrap(renderer.image { drawing in
            UIColor.blue.setFill()
            drawing.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        }.pngData())
        let source = root.appendingPathComponent("synthetic.png")
        try bytes.write(to: source)
        let path = try storage.saveEncryptedFile(from: source, password: password)
        defer { try? storage.deleteFile(path: path) }
        let item = MediaItem(fileName: "synthetic-photo", fileExtension: "png", fileSize: Int64(bytes.count), type: video ? .video : .photo, encryptedPath: try storage.getFileURL(for: path).path)
        context?.insert(item)
        try context?.save()
        let credentials = KeychainService(service: "photo-render-" + UUID().uuidString)
        try credentials.savePassword(password)
        let auth = AuthenticationViewModel(keychainService: credentials, manageInstallationState: false, dataPasswordLoader: { _ in password })
        defer { auth.logout(); credentials.clearAllKeychainData() }
        auth.password = password
        await (try XCTUnwrap(auth.login())).value
        let entry = PhotoDetailView.Entry(item)
        let detail = PhotoDetailView(photo: item, allPhotos: [item], sessionID: auth.librarySessionID)
        let presented: AnyView = video
            ? AnyView(VideoPlayerView(video: item, sessionID: auth.librarySessionID))
            : AnyView(detail)
        let host = UIHostingController(rootView: AnyView(presented.environmentObject(auth).environmentObject(try XCTUnwrap(auth.vaultContext)).environmentObject(try XCTUnwrap(auth.vaultContext).exports)))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        auth.logout()
        context = nil
        container = nil
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        // This forces rendering after the backing store is gone, matching the crash.
        _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        XCTAssertEqual(entry.snapshot.fileName, "synthetic-photo")
        XCTAssertEqual(entry.id, entry.snapshot.id)
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertTrue(storage.fileExists(path: path))
    }
}


private actor LateVideoPreviewGate {
    private var output: URL?
    private var continuation: CheckedContinuation<Void, Never>?
    func pause(_ url: URL) async {
        output = url
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilPaused() async throws -> URL {
        let deadline = Date().addingTimeInterval(8)
        while output == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard let output else { throw CancellationError() }; return output
    }
    func resume() { continuation?.resume(); continuation = nil }
}
