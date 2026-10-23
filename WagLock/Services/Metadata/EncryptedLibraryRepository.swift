import CryptoKit
import Foundation
import SwiftData

/// Password-keyed metadata persistence with a revocable, memory-only UI projection.
/// Existing legacy sources are never opened or converted by this repository.
@MainActor
final class EncryptedLibraryRepository {
    typealias Store = EncryptedMetadataStore
    let container: ModelContainer
    private let store: Store
    private let authorized: () -> Bool
    private let checkpoint: (Store.Checkpoint) throws -> Void
    private let saveProjection: (ModelContext) throws -> Void
    private var committed: [String: Data] = [:]
    private var revision: UInt64
    private var closed = false
    private var committing = false
    private var lease: LibraryWriteCoordinator.Lease?
    private var draft: Data?
    private static let draftID = UUID(uuidString: "1E89C554-6638-48DB-BB9A-93587C72D562")!
    private struct DraftEnvelope: Codable { let version: Int; let serialized: Data? }
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
        self.revision = state.revision
        self.container = try MetadataModelCodec.memoryProjection([], authorized: authorized)
        let context = container.mainContext
        var offset = 0
        while offset < state.count {
            guard authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
            try Task.checkCancellation()
            let page: Store.Page
            do { page = try store.page(access, offset: offset, limit: min(64, state.count - offset), revision: state.revision) }
            catch Store.Failure.tooLarge { page = try store.page(access, offset: offset, limit: 1, revision: state.revision) }
            for row in page.records {
                if row.kind == "draft" {
                    guard row.id == Self.draftID else { throw Store.Failure.corrupt }
                    let value = try JSONDecoder().decode(DraftEnvelope.self, from: row.payload)
                    guard value.version == 1, try Self.encode(value) == row.payload else { throw Store.Failure.corrupt }
                    if let serialized = value.serialized { _ = try MetadataDraftCodec.value(serialized) }
                    draft = value.serialized
                } else {
                    try MetadataModelCodec.insert(row, into: context)
                    committed[Self.identity(row)] = Self.digest(row)
                }
            }
            offset += page.records.count
        }
        guard authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
        try context.save()
        self.lease = LibraryWriteCoordinator.bindEncrypted(self)
    }
    private func checkRevision() throws {
        guard !closed, !committing, authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
        try Task.checkCancellation()
        guard try store.state(store.access()).revision == revision else {
            needsReconciliation = true; revoke(); throw Store.Failure.stale
        }
    }
    func save(_ context: ModelContext) throws {
        try checkRevision()
        guard context === container.mainContext, !context.autosaveEnabled else { throw LibraryWriteCoordinator.Failure.foreignContext }
        committing = true; defer { committing = false }
        context.processPendingChanges()
        var changed: [String: Store.Record] = [:], deleted: [String: Store.Record] = [:]
        for model in context.deletedModelsArray {
            let row = try MetadataModelCodec.record(model); deleted[Self.identity(row)] = row
        }
        for model in context.insertedModelsArray + context.changedModelsArray {
            let row = try MetadataModelCodec.record(model)
            let id = Self.identity(row)
            if deleted[id] == nil, committed[id] != Self.digest(row) { changed[id] = row }
        }
        let removals = deleted.filter { committed[$0.key] != nil }
        let mutations = changed.values.map(Store.Mutation.put)
            + removals.values.map { Store.Mutation.remove(kind: $0.kind, id: $0.id) }
        var durable = false
        do {
            if !mutations.isEmpty {
                revision = try apply(mutations).revision; durable = true
                for (id, row) in changed { committed[id] = Self.digest(row) }
                for id in removals.keys { committed.removeValue(forKey: id) }
            }
            try saveProjection(context)
            guard !closed, authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
        } catch {
            if durable || (error as? Store.Failure) == .uncertainCommit { try uncertain() }
            throw error
        }
    }
    func loadDraft() throws -> Data? { try checkRevision(); return draft }
    func saveDraft(_ serialized: Data?) throws {
        try checkRevision()
        if let serialized { _ = try MetadataDraftCodec.value(serialized) }
        let payload = try Self.encode(DraftEnvelope(version: 1, serialized: serialized))
        guard payload.count <= Store.maximumPayloadBytes else { throw Store.Failure.tooLarge }
        committing = true; defer { committing = false }
        do {
            revision = try apply([.put(.init(kind: "draft", id: Self.draftID, payload: payload))]).revision
            draft = serialized
        } catch {
            if (error as? Store.Failure) == .uncertainCommit { try uncertain() }
            throw error
        }
    }
    private func apply(_ mutations: [Store.Mutation]) throws -> Store.State {
        // One atomic transaction, not a series of partially published import batches.
        // Payload/page/bucket bounds remain enforced by the ciphertext engine.
        try store.apply(store.access(), revision: revision, mutations: mutations, checkpoint: { point in
            try self.checkpoint(point)
            guard !self.closed, self.authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
        }, mutationLimit: Int.max)
    }
    private func uncertain() throws -> Never {
        needsReconciliation = true; revoke(); throw Store.Failure.uncertainCommit
    }
    func revoke() {
        closed = true; store.revoke(); committed.removeAll(); draft = nil
        if let lease { LibraryWriteCoordinator.revoke(lease) }
    }
    private static func identity(_ row: Store.Record) -> String { row.kind + ":" + row.id.uuidString }
    private static func digest(_ row: Store.Record) -> Data { Data(SHA256.hash(data: row.payload)) }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
}
