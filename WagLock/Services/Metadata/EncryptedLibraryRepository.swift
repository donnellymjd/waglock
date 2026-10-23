import Foundation
import SwiftData

/// Explicit-root backend for integration tests/new-library preparation only.
/// Never opens/converts the legacy source and has no production mount factory yet.
@MainActor
final class EncryptedLibraryRepository {
    typealias Store = EncryptedMetadataStore
    let container: ModelContainer
    private let store: Store
    private let authorized: () -> Bool
    private let checkpoint: (Store.Checkpoint) throws -> Void
    private let saveProjection: (ModelContext) throws -> Void
    private var committed: [String: Store.Record]
    private var revision: UInt64
    private var closed = false
    private var committing = false
    private var lease: LibraryWriteCoordinator.Lease?
    private(set) var needsReconciliation = false
    var mayDiscardUncommittedResources: Bool { !closed && !needsReconciliation && authorized() }
    nonisolated deinit { }

    static func create(at root: URL, domain: Store.Domain, key: Data, authorized: @escaping () -> Bool,
                       checkpoint: @escaping (Store.Checkpoint) throws -> Void = { _ in },
                       saveProjection: @escaping (ModelContext) throws -> Void = { try $0.save() }) throws -> EncryptedLibraryRepository {
        guard authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
        let store = try Store.create(at: root, domain: domain, key: key)
        do { return try Self(store: store, authorized: authorized, checkpoint: checkpoint, saveProjection: saveProjection) }
        catch { store.revoke(); throw error }
    }
    static func open(at root: URL, domain: Store.Domain, key: Data, authorized: @escaping () -> Bool) throws -> EncryptedLibraryRepository {
        guard authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
        let store = try Store.open(at: root, domain: domain, key: key)
        do { return try Self(store: store, authorized: authorized, checkpoint: { _ in }, saveProjection: { try $0.save() }) }
        catch { store.revoke(); throw error }
    }
    private init(store: Store, authorized: @escaping () -> Bool,
                 checkpoint: @escaping (Store.Checkpoint) throws -> Void,
                 saveProjection: @escaping (ModelContext) throws -> Void) throws {
        self.store = store; self.authorized = authorized; self.checkpoint = checkpoint; self.saveProjection = saveProjection
        let access = store.access(); try store.verifyAll(access)
        let state = try store.state(access)
        guard state.count <= MetadataModelCodec.maximumRecords else { throw Store.Failure.tooLarge }
        var rows: [Store.Record] = [], bytes = 0
        for offset in 0..<state.count {
            guard authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
            let row = try store.page(access, offset: offset, limit: 1, revision: state.revision).records[0]
            _ = try MetadataModelCodec.decode(row)
            guard row.payload.count <= MetadataModelCodec.maximumSnapshotBytes - bytes else { throw Store.Failure.tooLarge }
            bytes += row.payload.count; rows.append(row)
        }
        self.container = try MetadataModelCodec.memoryProjection(rows, authorized: authorized)
        self.committed = Dictionary(uniqueKeysWithValues: rows.map { (Self.identity($0), $0) })
        self.revision = state.revision
        self.lease = LibraryWriteCoordinator.bindEncrypted(self)
    }
    func save(_ context: ModelContext) throws {
        guard !closed, !committing, authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
        guard context === container.mainContext, !context.autosaveEnabled else { throw LibraryWriteCoordinator.Failure.foreignContext }
        guard try store.state(store.access()).revision == revision else {
            needsReconciliation = true; revoke(); throw Store.Failure.stale
        }
        committing = true; defer { committing = false }
        let rows = try MetadataModelCodec.capturePending(context, authorized: { !self.closed && self.authorized() })
        let next = Dictionary(uniqueKeysWithValues: rows.map { (Self.identity($0), $0) })
        var mutations: [Store.Mutation] = []
        for row in rows where committed[Self.identity(row)]?.payload != row.payload { mutations.append(.put(row)) }
        for (id, old) in committed where next[id] == nil { mutations.append(.remove(kind: old.kind, id: old.id)) }
        // Candidate transaction resource bound; not an enabled product import limit.
        guard mutations.count <= 128 else { throw Store.Failure.tooLarge }
        var durable = false
        do {
            if !mutations.isEmpty {
                let state = try store.apply(store.access(), revision: revision, mutations: mutations) { point in
                    try self.checkpoint(point)
                    guard !self.closed, self.authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
                }
                revision = state.revision; committed = next; durable = true
            }
            try saveProjection(context)
            guard !closed, authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
        } catch {
            if durable || (error as? Store.Failure) == .uncertainCommit {
                needsReconciliation = true; revoke(); throw Store.Failure.uncertainCommit
            }
            throw error
        }
    }
    func revoke() {
        closed = true; store.revoke(); committed.removeAll()
        if let lease { LibraryWriteCoordinator.revoke(lease) }
    }
    private static func identity(_ row: Store.Record) -> String { row.kind + ":" + row.id.uuidString }
}
