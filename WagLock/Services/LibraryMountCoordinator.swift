internal import Combine
import SwiftData
import Foundation

/// Transitional mount boundary. Guest Mode is still not an independent encrypted vault.
/// Only the authenticated owner may open the unchanged legacy persistent schema.
@MainActor
final class LibraryMountCoordinator: ObservableObject {
    enum Scope: Hashable {
        case legacyOwner
        case ephemeralGuest
    }

    struct Request: Hashable {
        let sessionID: UUID
        let scope: Scope
    }

    struct Mount {
        let id = UUID()
        let request: Request
        let container: ModelContainer
    }

    enum Failure: Error { case inactiveSession }
    typealias Factory = @MainActor (Scope) async throws -> ModelContainer

    @Published private(set) var active: Mount?
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private var generation = UUID()
    private let factory: Factory

    init(factory: @escaping Factory = LibraryMountCoordinator.openLegacyContainer) {
        self.factory = factory
    }

    /// Recheck authorization after suspension; a completed open never authorizes a session.
    func mount(_ request: Request, isAuthorized: () -> Bool) async {
        guard isAuthorized(), !Task.isCancelled else { return }
        if active?.request == request { return }
        invalidate()
        let token = generation
        isLoading = true
        do {
            let container = try await factory(request.scope)
            guard token == generation else { return }
            guard !Task.isCancelled, isAuthorized() else {
                invalidate()
                return
            }
            active = Mount(request: request, container: container)
            isLoading = false
        } catch {
            guard token == generation else { return }
            guard !Task.isCancelled, isAuthorized() else {
                invalidate()
                return
            }
            isLoading = false
            failed = true
            // No fallback store, reset, schema replacement or credential mutation.
        }
    }

    func container(for request: Request) throws -> ModelContainer {
        guard let active, active.request == request else { throw Failure.inactiveSession }
        return active.container
    }

    func invalidate() {
        generation = UUID()
        active = nil
        isLoading = false
        failed = false
    }

    private static func openLegacyContainer(_ scope: Scope) async throws -> ModelContainer {
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        // Keep the owner configuration byte-for-byte equivalent to the former app setup:
        // default URL, schema, migration and identity. Never open that store for Guest Mode.
        let configuration = ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: scope == .ephemeralGuest)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
