import PDFKit
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import WagLock

@MainActor
final class DocumentPreviewRenderingTests: XCTestCase {
    func testRealPDFRenderBackgroundResumeAndLogoutAfterRecordInvalidation() async throws {
        try await exercise(usePager: false)
    }

    func testFilesPagerSurvivesLogoutWithItsLibraryReleased() async throws {
        try await exercise(usePager: true)
    }

    private func exercise(usePager: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-resume-" + UUID().uuidString)
        // Rendering uses the production storage reader: fixtures must be inside its owned root.
        // Cleanup removes only the ciphertext created by this test, never other media.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storage = FileStorageService.shared
        // Keep the isolated temporary store until process teardown closes SQLite handles.
        let password = "disposable-pdf-password"
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 240, height: 320))
        let bytes = renderer.pdfData { context in
            context.beginPage()
            ("Disposable PDF lifecycle fixture" as NSString).draw(at: CGPoint(x: 15, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
        }
        let source = root.appendingPathComponent("source.pdf")
        try bytes.write(to: source)
        let encrypted = try storage.saveEncryptedFile(from: source, password: password)
        defer { try? storage.deleteFile(path: encrypted) }
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        var container: ModelContainer? = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: root.appendingPathComponent("fixture.store"))])
        var context: ModelContext? = ModelContext(try XCTUnwrap(container))
        context?.autosaveEnabled = false
        let item = MediaItem(fileName: "synthetic-pdf", fileExtension: ".pdf", fileSize: Int64(bytes.count), type: .document,
                             encryptedPath: try storage.getFileURL(for: encrypted).path)
        context?.insert(item)
        try context?.save()
        let credentials = KeychainService(service: "pdf-render-" + UUID().uuidString)
        try credentials.savePassword(password)
        let auth = AuthenticationViewModel(keychainService: credentials, manageInstallationState: false, dataPasswordLoader: { _ in password })
        defer { auth.logout(); credentials.clearAllKeychainData() }
        auth.password = password
        await (try XCTUnwrap(auth.login())).value
        let detail = MediaDetailView(mediaItem: item, sessionID: auth.librarySessionID)
        // Keep only immutable presentation data plus the inert source reference in the view.
        // The hosting controller deliberately has no SwiftData environment retaining the fixture store.
        let presented: AnyView = usePager
            ? AnyView(FilePagerView(files: [item], initialFile: item, sessionID: auth.librarySessionID))
            : AnyView(detail)
        let host = UIHostingController(rootView: presented.environmentObject(auth))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        try await eventually("initial render") { self.containsPDF(host.view) }
        auth.suspendAlbumAccess()
        try await eventually("background removal") { !self.containsPDF(host.view) }
        auth.resumeAlbumAccess()
        try await eventually("authorized resume") { self.containsPDF(host.view) }
        // Mimic the store disappearing while a presented screen is still dismissing.
        auth.logout()
        context = nil
        container = nil
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await eventually("logout removal") { !self.containsPDF(host.view) }
        // Force another render after the store is gone, the failure point in phone build 33.
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(detail.mediaItem.fileExtension, ".pdf")
        XCTAssertEqual(detail.mediaItem.fullFileName, "synthetic-pdf.pdf")
        XCTAssertFalse(containsPDF(host.view))
        XCTAssertTrue(storage.fileExists(path: encrypted))
    }

    private func containsPDF(_ view: UIView) -> Bool {
        if let pdf = view as? PDFView, pdf.document != nil { return true }
        return view.subviews.contains(where: containsPDF)
    }
    private func eventually(_ phase: String, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !predicate() {
            if Date() >= deadline { XCTFail("PDF lifecycle did not reach expected state: \(phase)"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
