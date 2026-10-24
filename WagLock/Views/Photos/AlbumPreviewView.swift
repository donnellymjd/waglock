import QuickLook
import SwiftUI

struct AlbumPreviewView: View {
    let asset: AlbumAsset
    let album: VaultAlbum
    let albums: [VaultAlbum]
    @EnvironmentObject private var store: AlbumStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var url: URL?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let url { AlbumQuickLook(url: url) }
                else if let error { ContentUnavailableView(error, systemImage: "lock.trianglebadge.exclamationmark") }
                else { ProgressView("Opening…") }
            }
            .navigationTitle(asset.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            do { url = try await store.preview(asset, in: album, albums: albums) }
            catch { self.error = error.localizedDescription }
        }
        .onChange(of: store.revision) { _, _ in
            if !store.isUnlocked(album, albums: albums) { cleanup(); dismiss() }
        }
        .onChange(of: phase) { _, phase in
            if phase == .background { cleanup(); dismiss() }
        }
        .onDisappear { cleanup() }
    }

    private func cleanup() {
        if let url { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        url = nil
    }
}

private struct AlbumQuickLook: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
