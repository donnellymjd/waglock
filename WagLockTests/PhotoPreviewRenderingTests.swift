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

    private func exercise(video: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("photo-teardown-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        var container: ModelContainer? = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: root.appendingPathComponent("fixture.store"))])
        var context: ModelContext? = ModelContext(try XCTUnwrap(container))
        context?.autosaveEnabled = false
        let password = "disposable-photo-password"
        let storage = FileStorageService(directory: root.appendingPathComponent("media"), availableCapacity: { _ in 1_000_000_000 })
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 80))
        let bytes = try XCTUnwrap(renderer.image { drawing in
            UIColor.blue.setFill()
            drawing.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        }.pngData())
        let source = root.appendingPathComponent("synthetic.png")
        try bytes.write(to: source)
        let path = try storage.saveEncryptedFile(from: source, password: password)
        let item = MediaItem(fileName: "synthetic-photo", fileExtension: "png", fileSize: Int64(bytes.count), type: video ? .video : .photo, encryptedPath: storage.getFileURL(for: path).path)
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
        let host = UIHostingController(rootView: presented.environmentObject(auth))
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
