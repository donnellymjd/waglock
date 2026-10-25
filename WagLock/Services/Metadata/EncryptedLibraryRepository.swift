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
    private var fileBindings: [String: Data] = [:]
    private var bindingsEnrolled = false
    private var bindingRegistry: CiphertextBindings?
    private struct FileBinding: Codable { let version: Int; let path: String; let digest: Data }
    private static let bindingPolicyID = UUID(uuidString: "B40FCF98-9C63-4DCB-A6C7-D2C74142CC21")!
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
    static func open(at root: URL, domain: Store.Domain, key: Data, authorized: @escaping () -> Bool,
                     commitAnchor: (any LibraryCommitAnchor)? = nil) throws -> EncryptedLibraryRepository {
        guard authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
        let store = try Store.open(at: root, domain: domain, key: key)
        do {
            if let commitAnchor { try store.enableRollbackProtection(commitAnchor) }
            return try Self(store: store, authorized: authorized, checkpoint: { _ in }, saveProjection: { try $0.save() }) }
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
                if row.kind == "file-policy" {
                    guard row.id == Self.bindingPolicyID, row.payload == Data([1]), !bindingsEnrolled else { throw Store.Failure.corrupt }
                    bindingsEnrolled = true
                } else if row.kind == "file-binding" {
                    let value = try JSONDecoder().decode(FileBinding.self, from: row.payload)
                    guard value.version == 1, value.digest.count == 32, Self.validFileName(value.path),
                          row.id == Self.bindingID(value.path), fileBindings[value.path] == nil,
                          try Self.encode(value) == row.payload else { throw Store.Failure.corrupt }
                    fileBindings[value.path] = value.digest
                } else if row.kind == "draft" {
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
    private static func validFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.utf8.contains(0)
    }
    private static func bindingID(_ path: String) -> UUID {
        let h = Array(SHA256.hash(data: Data(path.utf8)))
        return UUID(uuid: (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8], h[9], h[10], h[11], h[12], h[13], h[14], h[15]))
    }
    private static func bindingRecord(_ path: String, _ digest: Data) throws -> Store.Record {
        guard validFileName(path), digest.count == 32 else { throw Store.Failure.corrupt }
        return Store.Record(kind: "file-binding", id: bindingID(path),
            payload: try encode(FileBinding(version: 1, path: path, digest: digest)))
    }
    /// One-time pre-release enrollment binds the existing ciphertext in place, without rewriting it.
    /// It cannot establish what a file contained before enrollment.
    func bindStorage(_ storage: FileStorageService) async throws {
        try checkRevision()
        if !bindingsEnrolled {
            guard fileBindings.isEmpty else { throw Store.Failure.corrupt }
            let snapshot = try await Task.detached(priority: .userInitiated) { try storage.bindingSnapshot() }.value
            try checkRevision()
            let records = try snapshot.map { Store.Mutation.put(try Self.bindingRecord($0.key, $0.value)) }
                + [.put(.init(kind: "file-policy", id: Self.bindingPolicyID, payload: Data([1])))]
            revision = try apply(records).revision
            fileBindings = snapshot; bindingsEnrolled = true
        }
        try checkRevision()
        let registry = CiphertextBindings(fileBindings)
        storage.installBindings(registry); bindingRegistry = registry
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
        let pending = try bindingRegistry?.snapshotPending() ?? [:]
        let bindings = try pending.map { Store.Mutation.put(try Self.bindingRecord($0.key, $0.value)) }
        let state = try store.apply(store.access(), revision: revision, mutations: mutations + bindings, checkpoint: { point in
            try self.checkpoint(point)
            guard !self.closed, self.authorized() else { throw LibraryWriteCoordinator.Failure.revoked }
        }, mutationLimit: Int.max)
        fileBindings.merge(pending) { _, new in new }
        bindingRegistry?.didCommit(pending)
        return state
    }
    private func uncertain() throws -> Never {
        needsReconciliation = true; revoke(); throw Store.Failure.uncertainCommit
    }
    func revoke() {
        closed = true; bindingRegistry?.revoke(); bindingRegistry = nil
        store.revoke(); committed.removeAll(); fileBindings.removeAll(); draft = nil
        if let lease { LibraryWriteCoordinator.revoke(lease) }
    }
    private static func identity(_ row: Store.Record) -> String { row.kind + ":" + row.id.uuidString }
    private static func digest(_ row: Store.Record) -> Data { Data(SHA256.hash(data: row.payload)) }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
}
