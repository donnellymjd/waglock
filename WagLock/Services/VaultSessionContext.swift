import Foundation
internal import Combine

/// Immutable service handles for one authenticated vault/session. No global root is changed.
/// Login integration is gated until all views and operations consume this context.
@MainActor
final class VaultSessionContext: ObservableObject {
    nonisolated deinit {}
    let vaultID: UUID
    let sessionID: UUID
    let storage: FileStorageService
    let imports: MediaImportService
    let mediaLoader: MediaLoaderService
    let thumbnails: ThumbnailImageLoader
    let albums: AlbumStore
    let exports: ExportService
    let documents: DocumentPreviewService
    @Published private(set) var isActive = true
    private var isRevoking = false

    init(vaultID: UUID, sessionID: UUID, dataPassword: String, storage: FileStorageService,
         temporaryRoot: URL, keychainNamespace: String) throws {
        guard !dataPassword.isEmpty, !keychainNamespace.isEmpty, temporaryRoot.isFileURL else {
            throw VaultAccessError.invalidData
        }
        self.vaultID = vaultID
        self.sessionID = sessionID
        self.storage = storage
        self.imports = MediaImportService(storage: storage)
        let loader = MediaLoaderService(storage: storage)
        let thumbnails = ThumbnailImageLoader()
        self.mediaLoader = loader
        self.thumbnails = thumbnails
        let namespace = keychainNamespace + ".vault." + vaultID.uuidString
        self.albums = AlbumStore(biometrics: BiometricSecretStore(service: namespace + ".album-biometrics"),
            attemptStorage: SystemKeychainStorage(service: namespace + ".album-attempts"),
            storage: storage, mediaLoader: loader, thumbnails: thumbnails)
        self.exports = ExportService(storage: storage, directory: temporaryRoot
            .appendingPathComponent(vaultID.uuidString, isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true))
        self.documents = DocumentPreviewService()
        albums.beginSession(vaultSecret: dataPassword)
        exports.beginSession(sessionID)
        documents.beginSession(sessionID)
    }

    func makeDocumentPreview() -> DocumentPreviewModel {
        let storage = storage
        return DocumentPreviewModel(service: documents, loader: { path, password, ext in
            try await storage.loadDecryptedDataAsync(path: path, password: password, preferredExtension: ext)
        })
    }

    /// Flush synchronously while the originating model lease is live, then revoke it.
    /// A revoked context cannot be reassigned or reactivated for a different session.
    func revoke() {
        guard isActive, !isRevoking else { return }
        isRevoking = true
        documents.flushNotesBeforeSuspending(sessionID)
        isActive = false
        LibraryMountCoordinator.invalidateSession(sessionID)
        exports.endSession(matching: sessionID)
        documents.endSession(matching: sessionID)
        albums.endSession()
        mediaLoader.clearCache()
        thumbnails.clearAll()
        isRevoking = false
    }
}
