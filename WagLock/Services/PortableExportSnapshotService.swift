import Foundation
import SwiftData

/// Read-only export groundwork, not a serialized format or a portable backup.
/// Values contain sensitive plaintext metadata: never log or persist the whole snapshot.
struct PortableExportSnapshot: Equatable {
    enum DomainID: Hashable { case root, album(UUID) }
    struct Source: Equatable {
        let url: URL
        let ciphertextBytes: Int64
        let modifiedAt: Date
        let fileNumber: UInt64
    }
    struct Asset: Equatable {
        let id: UUID
        let albumID: UUID?
        let name: String
        let fileExtension: String
        let storedType: String
        let effectiveType: MediaType
        let bytes: Int64
        let thumbnail: Data?
        let createdAt: Date
        let modifiedAt: Date?
        let width: Int?
        let height: Int?
        let duration: Double?
        let source: Source
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id && lhs.albumID == rhs.albumID && lhs.bytes == rhs.bytes
                && sameExportText([lhs.name, lhs.fileExtension, lhs.storedType], [rhs.name, rhs.fileExtension, rhs.storedType])
                && lhs.effectiveType == rhs.effectiveType && lhs.thumbnail == rhs.thumbnail
                && lhs.createdAt == rhs.createdAt && lhs.modifiedAt == rhs.modifiedAt
                && lhs.width == rhs.width && lhs.height == rhs.height && lhs.duration == rhs.duration && lhs.source == rhs.source
        }
    }
    struct Album: Equatable {
        let id: UUID
        let parentID: UUID?
        let name: String
        let protection: AlbumProtection
        let createdAt: Date
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id && lhs.parentID == rhs.parentID && lhs.protection == rhs.protection
                && lhs.createdAt == rhs.createdAt && sameExportText([lhs.name], [rhs.name])
        }
    }
    struct Note: Equatable {
        let id: UUID
        let title: String
        let content: String
        let createdAt: Date
        let modifiedAt: Date
        let isFavorite: Bool
        let tags: [String]
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id && lhs.createdAt == rhs.createdAt && lhs.modifiedAt == rhs.modifiedAt
                && lhs.isFavorite == rhs.isFavorite && sameExportText([lhs.title, lhs.content], [rhs.title, rhs.content])
                && sameExportText(lhs.tags, rhs.tags)
        }
    }
    struct Draft: Equatable {
        enum Origin: String { case keychain, legacyPreferences }
        let origin: Origin
        let title: String
        let content: String
        let updatedAt: Date
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.origin == rhs.origin && lhs.updatedAt == rhs.updatedAt
                && sameExportText([lhs.title, lhs.content], [rhs.title, rhs.content])
        }
    }
    struct Domain: Equatable {
        let id: DomainID
        let parent: DomainID?
        // Child references are opaque. Child names/catalogs belong in the child domain.
        let children: Set<DomainID>
        let albums: [Album]
        let assets: [Asset]
        let notes: [Note]
        let drafts: [Draft]
    }
    struct Content: Equatable {
        let domains: [Domain]
        // No Trash model exists yet. Unknown future schemas must not silently omit it.
        let trashNotImplemented = true
        let deviceSettingsNotCaptured = true
    }
    fileprivate let collectorID: UUID
    fileprivate let session: LibraryMountCoordinator.Request
    fileprivate let mountID: UUID
    fileprivate let authorityRevision: UUID
    fileprivate let albumRevision: Int
    let content: Content
}

@MainActor
final class PortableExportSnapshotService {
    enum Failure: Error, Equatable {
        case unauthorized, dirtyContext, unsupportedSchema, invalidInventory, changed
        case albumLocked(UUID), biometricRecoveryRequired(UUID), metadataLimit, draftUnavailable
    }
    typealias DraftReader = @MainActor () throws -> [PortableExportSnapshot.Draft]
    private let id = UUID()
    private let mounts: LibraryMountCoordinator
    private let authority: DocumentPreviewService
    private let albums: AlbumStore
    private let storage: FileStorageService
    private let isOwner: @MainActor () -> Bool
    private let readDrafts: DraftReader
    private let metadataLimit: Int

    init(mounts: LibraryMountCoordinator, authority: DocumentPreviewService,
         albums: AlbumStore, storage: FileStorageService,
         metadataLimit: Int = 64 * 1024 * 1024,
         isOwner: @escaping @MainActor () -> Bool,
         readDrafts: DraftReader? = nil) {
        self.mounts = mounts
        self.authority = authority
        self.albums = albums
        self.storage = storage
        self.metadataLimit = metadataLimit
        self.isOwner = isOwner
        self.readDrafts = readDrafts ?? { try Self.drafts(keychain: .shared, defaults: .standard) }
    }

    /// Synchronous MainActor capture: no live SwiftData records escape to a worker.
    /// Does not save the context, unlock albums, read media plaintext or write an export.
    func capture(_ request: LibraryMountCoordinator.Request) throws -> PortableExportSnapshot {
        do { return try captureContent(request) }
        catch let failure as Failure { throw failure }
        catch is CancellationError { throw CancellationError() }
        catch { throw Failure.invalidInventory }
    }

    private func captureContent(_ request: LibraryMountCoordinator.Request) throws -> PortableExportSnapshot {
        try Task.checkCancellation()
        let revision = authority.revision
        let mount = try authorizedMount(request, revision: revision)
        let context = mount.container.mainContext
        try checkContext(context)
        // Read both draft stores without running the legacy migration or deleting either.
        let drafts: [PortableExportSnapshot.Draft]
        do { drafts = try readDrafts() } catch { throw Failure.draftUnavailable }
        _ = try authorizedMount(request, revision: revision, mountID: mount.id)
        try checkContext(context)
        let media = try context.fetch(FetchDescriptor<MediaItem>())
        let notes = try context.fetch(FetchDescriptor<SecretNote>())
        let records = try context.fetch(FetchDescriptor<VaultAlbum>())
        guard Set(records.map(\.id)).count == records.count,
              Set(notes.map(\.id)).count == notes.count else { throw Failure.invalidInventory }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var protection: [UUID: AlbumProtection] = [:]
        for album in records {
            guard let policy = AlbumProtection(rawValue: album.protectionRawValue) else { throw Failure.invalidInventory }
            protection[album.id] = policy
        }
        func domain(for albumID: UUID?) throws -> PortableExportSnapshot.DomainID {
            var current = albumID
            var seen = Set<UUID>()
            var nearest: UUID?
            while let currentID = current {
                guard seen.insert(currentID).inserted, let album = byID[currentID],
                      let policy = protection[currentID] else { throw Failure.invalidInventory }
                if policy != .inherited, nearest == nil { nearest = currentID }
                current = album.parentID
            }
            return nearest.map(PortableExportSnapshot.DomainID.album) ?? .root
        }
        // Validate the complete hierarchy even when a node starts a new password domain.
        for album in records { _ = try domain(for: album.id) }
        for album in records.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            if protection[album.id] == .faceIDOnly { throw Failure.biometricRecoveryRequired(album.id) }
            guard albums.isUnlocked(album, albums: records) else { throw Failure.albumLocked(album.id) }
        }
        var budget = 0
        func charge(_ amount: Int) throws {
            guard amount >= 0, metadataLimit >= 0, amount <= metadataLimit - budget else { throw Failure.metadataLimit }
            budget += amount
        }
        func strings(_ values: [String]) throws { for value in values { try charge(value.utf8.count) } }
        func date(_ value: Date) throws { guard value.timeIntervalSince1970.isFinite else { throw Failure.invalidInventory } }
        typealias DomainID = PortableExportSnapshot.DomainID
        var albumRows: [DomainID: [PortableExportSnapshot.Album]] = [:]
        var assetRows: [DomainID: [PortableExportSnapshot.Asset]] = [:]
        var parents: [DomainID: DomainID] = [:]
        var assetIDs = Set<UUID>()
        func add(_ asset: PortableExportSnapshot.Asset, to domain: DomainID) throws {
            guard assetIDs.insert(asset.id).inserted, asset.bytes >= 0,
                  MediaType(rawValue: asset.storedType) != nil,
                  asset.width.map({ $0 > 0 }) ?? true, asset.height.map({ $0 > 0 }) ?? true,
                  asset.duration.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw Failure.invalidInventory }
            try charge(256) // Account for fixed fields as well as variable payloads.
            try strings([asset.name, asset.fileExtension, asset.storedType])
            try charge(asset.thumbnail?.count ?? 0)
            try date(asset.createdAt)
            if let modified = asset.modifiedAt { try date(modified) }
            assetRows[domain, default: []].append(asset)
        }
        for item in media {
            try add(.init(id: item.id, albumID: nil, name: item.fileName, fileExtension: item.fileExtension,
                          storedType: item.typeRawValue, effectiveType: item.type, bytes: item.fileSize,
                          thumbnail: item.thumbnailData, createdAt: item.createdAt, modifiedAt: item.modifiedAt,
                          width: item.width, height: item.height, duration: item.duration,
                          source: try source(item.encryptedPath)), to: .root)
        }
        let albumRevision = albums.revision
        for album in records {
            let ownDomain = try domain(for: album.id)
            if protection[album.id] != .inherited { parents[ownDomain] = try domain(for: album.parentID) }
            try charge(256)
            try strings([album.name])
            try date(album.createdAt)
            albumRows[ownDomain, default: []].append(.init(id: album.id, parentID: album.parentID,
                name: album.name, protection: protection[album.id]!, createdAt: album.createdAt))
            for item in try albums.assetsForPortableSnapshot(in: album, albums: records) {
                try add(.init(id: item.id, albumID: album.id, name: item.fileName, fileExtension: item.fileExtension,
                              storedType: item.type.rawValue, effectiveType: item.type, bytes: item.fileSize,
                              thumbnail: item.thumbnail, createdAt: item.createdAt, modifiedAt: nil,
                              width: nil, height: nil, duration: nil, source: try source(item.encryptedPath)), to: ownDomain)
            }
        }
        var noteRows: [PortableExportSnapshot.Note] = []
        for note in notes {
            try charge(128)
            try strings([note.title, note.content] + note.tags)
            try date(note.createdAt); try date(note.modifiedAt)
            noteRows.append(.init(id: note.id, title: note.title, content: note.content,
                                 createdAt: note.createdAt, modifiedAt: note.modifiedAt,
                                 isFavorite: note.isFavorite, tags: note.tags))
        }
        guard Set(drafts.map(\.origin)).count == drafts.count else { throw Failure.invalidInventory }
        for draft in drafts {
            try charge(64); try strings([draft.title, draft.content]); try date(draft.updatedAt)
        }
        _ = try authorizedMount(request, revision: revision, mountID: mount.id)
        guard albums.revision == albumRevision else { throw Failure.changed }
        try Task.checkCancellation()
        let domainIDs = Set(parents.keys).union([.root])
        let domains = domainIDs.sorted { Self.order($0) < Self.order($1) }.map { domainID in
            PortableExportSnapshot.Domain(id: domainID, parent: parents[domainID],
                children: Set(parents.filter { $0.value == domainID }.map(\.key)),
                albums: (albumRows[domainID] ?? []).sorted { $0.id.uuidString < $1.id.uuidString },
                assets: (assetRows[domainID] ?? []).sorted { $0.id.uuidString < $1.id.uuidString },
                notes: domainID == .root ? noteRows.sorted { $0.id.uuidString < $1.id.uuidString } : [],
                drafts: domainID == .root ? drafts.sorted { $0.origin.rawValue < $1.origin.rawValue } : [])
        }
        return .init(collectorID: id, session: request, mountID: mount.id, authorityRevision: revision,
                     albumRevision: albumRevision, content: .init(domains: domains))
    }

    /// Call across each await in a future writer; it never refreshes an old capability.
    func validateAuthorization(_ snapshot: PortableExportSnapshot) throws {
        guard snapshot.collectorID == id else { throw Failure.unauthorized }
        _ = try authorizedMount(snapshot.session, revision: snapshot.authorityRevision, mountID: snapshot.mountID)
        guard albums.revision == snapshot.albumRevision else { throw Failure.changed }
        try Task.checkCancellation()
    }

    /// Recapture before future publication: metadata, drafts and source stat changes fail closed.
    /// Source hashes and immutable read handles are still required by the future streaming writer.
    func validateUnchanged(_ snapshot: PortableExportSnapshot) throws {
        try validateAuthorization(snapshot)
        guard try capture(snapshot.session).content == snapshot.content else { throw Failure.changed }
    }

    private func authorizedMount(_ request: LibraryMountCoordinator.Request, revision: UUID,
                                 mountID: UUID? = nil) throws -> LibraryMountCoordinator.Mount {
        guard request.scope == .legacyOwner, isOwner(), authority.permits(request.sessionID, revision: revision),
              let active = mounts.active, active.request == request,
              mountID == nil || active.id == mountID else { throw Failure.unauthorized }
        return active
    }

    private func checkContext(_ context: ModelContext) throws {
        guard !context.hasChanges else { throw Failure.dirtyContext }
        // Explicit field inventory: adding a model OR a persisted field requires review.
        let supported: [String: Set<String>] = [
            "MediaItem": ["id", "fileName", "fileExtension", "fileSize", "typeRawValue", "encryptedPath",
                          "thumbnailData", "createdAt", "modifiedAt", "width", "height", "duration"],
            "SecretNote": ["id", "title", "content", "createdAt", "modifiedAt", "isFavorite", "tags"],
            "VaultAlbum": ["id", "parentID", "name", "protectionRawValue", "wrappedKey", "encryptedCatalog",
                           "biometricAccount", "createdAt"]]
        let entities = context.container.schema.entities
        guard entities.count == supported.count else { throw Failure.unsupportedSchema }
        for entity in entities {
            guard let fields = supported[entity.name], Set(entity.properties.map(\.name)) == fields else {
                throw Failure.unsupportedSchema
            }
        }
    }

    private func source(_ path: String) throws -> PortableExportSnapshot.Source {
        let configuredRoot = storage.getStorageDirectory().standardizedFileURL
        guard let rootAttributes = try? FileManager.default.attributesOfItem(atPath: configuredRoot.path),
              rootAttributes[.type] as? FileAttributeType == .typeDirectory else { throw Failure.invalidInventory }
        let root = configuredRoot.resolvingSymlinksInPath().standardizedFileURL
        let url = storage.getFileURL(for: path).standardizedFileURL
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              url.resolvingSymlinksInPath().path == root.appendingPathComponent(url.lastPathComponent).path,
              let size = attributes[.size] as? NSNumber, let number = attributes[.systemFileNumber] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { throw Failure.invalidInventory }
        return .init(url: url, ciphertextBytes: size.int64Value, modifiedAt: modified, fileNumber: number.uint64Value)
    }

    static func drafts(keychain: KeychainService, defaults: UserDefaults) throws -> [PortableExportSnapshot.Draft] {
        do {
            let legacyValue = defaults.object(forKey: "secretSpace.draft")
            guard legacyValue == nil || legacyValue is Data else { throw Failure.draftUnavailable }
            let entries: [(PortableExportSnapshot.Draft.Origin, Data?)] = [
                (.keychain, try keychain.loadSecretNoteDraftChecked()),
                (.legacyPreferences, legacyValue as? Data)]
            return try entries.compactMap { origin, data in
                guard let data else { return nil }
                guard data.count <= 64 * 1024 * 1024,
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      Set(object.keys) == ["title", "content", "updatedAt"] else { throw Failure.draftUnavailable }
                let draft = try JSONDecoder().decode(SecretNoteDraft.self, from: data)
                return .init(origin: origin, title: draft.title, content: draft.content, updatedAt: draft.updatedAt)
            }
        } catch { throw Failure.draftUnavailable }
    }

    private static func order(_ domain: PortableExportSnapshot.DomainID) -> String {
        switch domain { case .root: return ""; case .album(let id): return id.uuidString }
    }
}

// Swift String equality treats canonically equivalent encodings as equal. Recovery
// consistency must preserve the original UTF-8 spelling without normalizing it.
private func sameExportText(_ lhs: [String], _ rhs: [String]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.utf8.elementsEqual($1.utf8) }
}
