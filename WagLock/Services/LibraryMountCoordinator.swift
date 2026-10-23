internal import Combine
import SwiftData
import Foundation

/// Transitional mount boundary. Guest Mode is still not an independent encrypted vault.
/// Only the authenticated owner may open the unchanged legacy persistent schema.
@MainActor
final class LibraryMountCoordinator: ObservableObject {
    nonisolated deinit { }
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
    @Published private(set) var failureReference: String?
    private var generation = UUID()
    private let factory: Factory
    private var writeLease: LibraryWriteCoordinator.Lease?
    private var encryptedRepository: EncryptedLibraryRepository?
    private let encryptedRoot: URL?
    private let legacySources: [URL]
    private let anchor: any LibraryIdentityAnchor

    init(factory: @escaping Factory = LibraryMountCoordinator.openLegacyContainer) {
        self.factory = factory
        self.anchor = KeychainService.shared
        self.encryptedRoot = LibraryStoragePolicy.encryptedMetadata ? LibraryStoragePolicy.defaultRoot : nil
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        let url = ModelConfiguration(schema: schema).url
        self.legacySources = [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
    }

    init(encryptedRoot: URL, anchor: any LibraryIdentityAnchor, legacySources: [URL] = []) {
        self.factory = Self.openLegacyContainer
        self.encryptedRoot = encryptedRoot; self.legacySources = legacySources; self.anchor = anchor
    }

    /// Recheck authorization after suspension; a completed open never authorizes a session.
    func mount(_ request: Request, dataPassword: String? = nil, isAuthorized: @escaping () -> Bool) async {
        guard isAuthorized(), !Task.isCancelled else { return }
        if active?.request == request { return }
        invalidate()
        let token = generation
        isLoading = true
        do {
            let container: ModelContainer
            if let encryptedRoot, request.scope == .legacyOwner {
                guard let dataPassword else { throw Failure.inactiveSession }
                if LibraryStoragePolicy.encryptedMetadata, !FileManager.default.fileExists(atPath: encryptedRoot.path),
                   !FileStorageService.shared.getAllEncryptedFiles().isEmpty { throw FreshEncryptedLibrary.Failure.legacySource }
                let repository = try FreshEncryptedLibrary.open(at: encryptedRoot, dataPassword: dataPassword, anchor: anchor,
                    legacySources: legacySources, authorized: { [weak self] in self?.generation == token && isAuthorized() })
                encryptedRepository = repository
                container = repository.container
            } else {
                container = try await factory(request.scope)
            }
            guard token == generation else { return }
            guard !Task.isCancelled, isAuthorized() else {
                invalidate()
                return
            }
            let mounted = Mount(request: request, container: container)
            let mountedID = mounted.id
            if encryptedRepository == nil {
                writeLease = try LibraryWriteCoordinator.bindLegacy(container) { [weak self] in
                    guard let self else { return false }
                    return self.generation == token && self.active?.id == mountedID
                        && request.scope == .legacyOwner && isAuthorized()
                }
            }
            active = mounted
            isLoading = false
        } catch {
            guard token == generation else { return }
            guard !Task.isCancelled, isAuthorized() else {
                invalidate()
                return
            }
            isLoading = false
            failed = true
            failureReference = Self.reference(for: error)
            // No fallback store, reset, schema replacement or credential mutation.
        }
    }

    func container(for request: Request) throws -> ModelContainer {
        guard let active, active.request == request else { throw Failure.inactiveSession }
        return active.container
    }

    func invalidate() {
        if let writeLease { LibraryWriteCoordinator.revoke(writeLease) }; writeLease = nil
        encryptedRepository?.revoke(); encryptedRepository = nil
        generation = UUID()
        active = nil
        isLoading = false
        failed = false
        failureReference = nil
    }

    /// Fixed diagnostic codes only: never render paths, passwords, keys or record content.
    static func reference(for error: Error) -> String {
        if let value = error as? FreshEncryptedLibrary.Failure {
            switch value {
            case .legacySource: return "WL-M01"
            case .invalidDescriptor: return "WL-M02"
            case .unsafePath: return "WL-M03"
            case .storage: return "WL-M04"
            case .conflictingRoots: return "WL-M05"
            case .missingLibrary: return "WL-M06"
            case .foreignLibrary: return "WL-M07"
            }
        }
        if let value = error as? EncryptedMetadataStore.Failure {
            switch value {
            case .locked: return "WL-I01"
            case .stale: return "WL-I02"
            case .busy: return "WL-I03"
            case .corrupt: return "WL-I04"
            case .storage: return "WL-I05"
            case .exists: return "WL-I06"
            case .unsafePath: return "WL-I07"
            case .tooLarge: return "WL-I08"
            case .uncertainCommit: return "WL-I09"
            }
        }
        if error is KeychainError { return "WL-K01" }
        if error is MetadataModelCodec.Failure { return "WL-P01" }
        if error is EncryptionError { return "WL-E01" }
        if error is CancellationError { return "WL-C01" }
        return "WL-U01"
    }

    func exportDrafts() throws -> [PortableExportSnapshot.Draft] {
        guard active?.request.scope == .legacyOwner else { throw Failure.inactiveSession }
        if let repository = encryptedRepository {
            guard let raw = try repository.loadDraft() else { return [] }
            let value = try MetadataDraftCodec.value(raw)
            return [.init(origin: .encryptedVault, title: value.title, content: value.content, updatedAt: value.updatedAt)]
        }
        return try PortableExportSnapshotService.drafts(keychain: .shared, defaults: .standard)
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
