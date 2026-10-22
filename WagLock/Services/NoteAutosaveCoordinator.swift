internal import Combine
import Foundation

/// Serializes note writes under the existing revocable owner-session authority.
/// It owns no persisted note data and never keeps a cancelled write eligible.
@MainActor
final class NoteAutosaveCoordinator: ObservableObject {
    typealias Action = @MainActor () -> Bool
    typealias Delay = @MainActor () async throws -> Void
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var error: String?
    private struct Pending {
        let session: UUID
        let revision: UUID
        let authorize: @MainActor () -> Bool
        let commit: Action
    }
    private let authority: DocumentPreviewService
    private let delay: Delay
    private var pending: Pending?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var observation: AnyCancellable?

    init(authority: DocumentPreviewService? = nil, delay: Delay? = nil) {
        let authority = authority ?? .shared
        self.authority = authority
        self.delay = delay ?? { try await Task.sleep(for: .seconds(1)) }
        observation = authority.$revision.dropFirst().sink { [weak self] _ in self?.cancel() }
    }

    nonisolated deinit { task?.cancel() }

    @discardableResult
    func schedule(session: UUID, authorize: @escaping @MainActor () -> Bool,
                  commit: @escaping Action) -> Task<Void, Never>? {
        cancel()
        let revision = authority.revision
        guard authority.permits(session, revision: revision), authorize() else { return nil }
        error = nil
        pending = Pending(session: session, revision: revision, authorize: authorize, commit: commit)
        let token = generation
        let delay = delay
        task = Task { [weak self] in
            do { try await delay() } catch { return }
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.flush()
        }
        return task
    }

    /// Used for a normal Back/inactive transition, preserving the latest authorized edit.
    @discardableResult
    func flush() -> Bool {
        let write = pending
        cancel()
        guard let write else { return false }
        return perform(write)
    }

    /// An explicit Save first invalidates the older debounced draft, then commits once.
    @discardableResult
    func saveNow(session: UUID, authorize: @escaping @MainActor () -> Bool,
                 commit: @escaping Action) -> Bool {
        cancel()
        return perform(Pending(session: session, revision: authority.revision, authorize: authorize, commit: commit))
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        pending = nil
    }

    private func perform(_ write: Pending) -> Bool {
        guard authority.permits(write.session, revision: write.revision), write.authorize() else { return false }
        guard write.commit() else {
            error = "Unable to save this note. Keep the editor open and try again."
            return false
        }
        lastSavedAt = Date()
        error = nil
        return true
    }
}
