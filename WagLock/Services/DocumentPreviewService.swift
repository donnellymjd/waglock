internal import Combine
import Foundation

/// Revocable owner-session capability for document previews, note writes and export snapshots. No key or plaintext cache.
@MainActor
final class DocumentPreviewService: ObservableObject {
    static let shared = DocumentPreviewService()
    @Published private(set) var revision = UUID()
    private var activeSession: UUID?
    private let noteFlushRequests = PassthroughSubject<UUID, Never>()
    var pendingNoteFlushes: AnyPublisher<UUID, Never> { noteFlushRequests.eraseToAnyPublisher() }

    /// Finish the current editor's synchronous write while its owner lease is
    /// still valid. Revocation follows immediately; no work may resume afterward.
    func flushNotesBeforeSuspending(_ id: UUID) {
        guard activeSession == id else { return }
        noteFlushRequests.send(id)
    }

    // Avoid the isolated-deinit back-deployment path on older iOS runtimes.
    nonisolated deinit {}

    func beginSession(_ id: UUID) {
        guard activeSession != id else { return }
        activeSession = id
        revision = UUID()
    }

    func endSession(matching expected: UUID? = nil) {
        if let expected, activeSession != expected { return }
        activeSession = nil
        revision = UUID()
    }

    func permits(_ id: UUID, revision expected: UUID) -> Bool {
        activeSession == id && revision == expected
    }
}

/// Owns one view's plaintext and rejects stale results, including stale errors.
@MainActor
final class DocumentPreviewModel: ObservableObject {
    typealias Loader = @MainActor (String, String, String) async throws -> Data
    @Published private(set) var authorizationRevision: UUID
    @Published private(set) var data: Data?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let service: DocumentPreviewService
    private let loader: Loader
    private var observation: AnyCancellable?
    private var task: Task<Void, Never>?
    private var request = UUID()

    init(service: DocumentPreviewService? = nil, loader: Loader? = nil) {
        let service = service ?? .shared
        self.service = service
        self.authorizationRevision = service.revision
        self.loader = loader ?? { path, password, ext in
            try await FileStorageService.shared.loadDecryptedDataAsync(
                path: path, password: password, preferredExtension: ext)
        }
        observation = service.$revision.dropFirst().sink { [weak self] revision in
            self?.clear()
            self?.authorizationRevision = revision
        }
    }

    nonisolated deinit { task?.cancel() }

    /// Call on the main actor with immutable metadata, never a captured SwiftData model.
    @discardableResult
    func load(path: String, password: String, fileExtension: String, sessionID: UUID) -> Task<Void, Never>? {
        clear()
        let revision = service.revision
        guard !password.isEmpty, service.permits(sessionID, revision: revision) else { return nil }
        let token = request
        let loader = loader
        isLoading = true
        task = Task { [weak self] in
            do {
                let result = try await loader(path, password, fileExtension)
                guard let self, !Task.isCancelled, self.request == token,
                      self.service.permits(sessionID, revision: revision) else { return }
                self.data = result
                self.isLoading = false
                self.task = nil
            } catch {
                guard let self, !Task.isCancelled, self.request == token,
                      self.service.permits(sessionID, revision: revision) else { return }
                // Do not expose ciphertext paths or raw decoder/Keychain errors.
                self.error = "Unable to open this document. Try again after unlocking."
                self.isLoading = false
                self.task = nil
            }
        }
        return task
    }

    func clear() {
        request = UUID()
        task?.cancel()
        task = nil
        data = nil
        error = nil
        isLoading = false
    }
}
