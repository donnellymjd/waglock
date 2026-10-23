import Foundation
import SwiftData

/// Every app model save crosses this boundary. Unmanaged fixture contexts retain normal saves.
/// Revoked managed containers keep a tombstone until their last context is released.
@MainActor
enum LibraryWriteCoordinator {
    enum Failure: Error { case revoked, foreignContext }
    private final class Entry {
        nonisolated deinit { }
        weak var container: ModelContainer?
        weak var mainContext: ModelContext?
        let id = UUID()
        let encrypted: Bool
        var save: ((ModelContext) throws -> Void)?
        var mayDiscard: (() -> Bool)?
        var readDraft: (() throws -> Data?)?
        var writeDraft: ((Data?) throws -> Void)?
        init(_ container: ModelContainer, encrypted: Bool) { self.container = container; self.mainContext = container.mainContext; self.encrypted = encrypted }
    }
    struct Lease { fileprivate let containerID: ObjectIdentifier; fileprivate let id: UUID }
    private static var entries: [ObjectIdentifier: Entry] = [:]
    private static var contextEntries: [ObjectIdentifier: Entry] = [:]

    static func bindLegacy(_ container: ModelContainer, authorized: @escaping () -> Bool,
                           saveContext: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }) throws -> Lease {
        if let entry = entries[ObjectIdentifier(container)], entry.container === container, entry.encrypted {
            throw Failure.foreignContext
        }
        container.mainContext.autosaveEnabled = false
        var failedSave = false
        return bind(container, save: { context in
            guard authorized() else { throw Failure.revoked }
            try Task.checkCancellation()
            do { try saveContext(context) } catch { failedSave = true; throw error }
            // A synchronous completed save must not be reclassified as uncommitted.
        }, mayDiscard: { authorized() && !failedSave })
    }
    static func bindEncrypted(_ repository: EncryptedLibraryRepository) -> Lease {
        let lease = bind(repository.container, encrypted: true, save: { [weak repository] context in
            guard let repository else { throw Failure.revoked }
            try repository.save(context)
        }, mayDiscard: { [weak repository] in repository?.mayDiscardUncommittedResources == true })
        let entry = entries[lease.containerID]!
        entry.readDraft = { [weak repository] in
            guard let repository else { throw Failure.revoked }; return try repository.loadDraft()
        }
        entry.writeDraft = { [weak repository] data in
            guard let repository else { throw Failure.revoked }; try repository.saveDraft(data)
        }
        return lease
    }
    static func draftManager(in context: ModelContext) -> SecretNoteDraftManager {
        guard let entry = managedEntry(for: context) else { return .shared }
        if !entry.encrypted, entry.container != nil, entry.save != nil { return .shared }
        return SecretNoteDraftManager(read: {
            guard entry.container != nil, let read = entry.readDraft else { throw Failure.revoked }; return try read()
        }, write: { data in
            guard entry.container != nil, let write = entry.writeDraft else { throw Failure.revoked }; try write(data)
        })
    }
    private static func bind(_ container: ModelContainer, encrypted: Bool = false, save: @escaping (ModelContext) throws -> Void,
                             mayDiscard: @escaping () -> Bool) -> Lease {
        entries = entries.filter { $0.value.container != nil }
        contextEntries = contextEntries.filter { $0.value.mainContext != nil }
        let entry = Entry(container, encrypted: encrypted); entry.save = save; entry.mayDiscard = mayDiscard
        let key = ObjectIdentifier(container); entries[key] = entry
        contextEntries[ObjectIdentifier(container.mainContext)] = entry
        return Lease(containerID: key, id: entry.id)
    }
    static func revoke(_ lease: Lease) {
        guard let entry = entries[lease.containerID], entry.id == lease.id else { return }
        entry.save = nil; entry.mayDiscard = nil; entry.readDraft = nil; entry.writeDraft = nil
    }
    static func save(_ context: ModelContext) throws {
        if let entry = managedEntry(for: context) {
            guard entry.container != nil, let save = entry.save else { throw Failure.revoked }
            try save(context)
        } else { try context.save() }
    }
    private static func managedEntry(for context: ModelContext) -> Entry? {
        // SwiftData contexts do not keep their container alive. Recognize managed
        // main contexts before touching context.container after unmount/release.
        if let entry = contextEntries[ObjectIdentifier(context)], entry.mainContext === context { return entry }
        let container = context.container
        guard let entry = entries[ObjectIdentifier(container)], entry.container === container else { return nil }
        return entry
    }
    /// On an uncertain/revoked save, preserve resources for reconciliation rather than guessing.
    static func mayDiscardUncommittedResources(in context: ModelContext) -> Bool {
        guard let entry = managedEntry(for: context) else { return true }
        guard entry.container != nil else { return false }
        return entry.mayDiscard?() == true
    }
}
