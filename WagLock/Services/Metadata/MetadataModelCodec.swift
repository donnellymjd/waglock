import Foundation
import SwiftData

/// Unused transition adapter. No default context, Keychain access or persistent writer.
@MainActor
enum MetadataModelCodec {
    enum Failure: Error { case unauthorized, dirtyContext, unsupportedSchema, invalidRecord, tooLarge }
    private struct Envelope<T: Codable>: Codable { let version: Int; let value: T }
    struct Media: Codable {
        let id: UUID, fileName: String, fileExtension: String, fileSize: Int64, typeRawValue: String
        let encryptedPath: String, thumbnailData: Data?, createdAt: Date, modifiedAt: Date
        let width: Int?, height: Int?, duration: Double?
        init(_ x: MediaItem) {
            id = x.id; fileName = x.fileName; fileExtension = x.fileExtension; fileSize = x.fileSize
            typeRawValue = x.typeRawValue; encryptedPath = x.encryptedPath; thumbnailData = x.thumbnailData
            createdAt = x.createdAt; modifiedAt = x.modifiedAt; width = x.width; height = x.height; duration = x.duration
        }
    }
    struct Note: Codable {
        let id: UUID, title: String, content: String, createdAt: Date, modifiedAt: Date, isFavorite: Bool, tags: [String]
        init(_ x: SecretNote) {
            id = x.id; title = x.title; content = x.content; createdAt = x.createdAt
            modifiedAt = x.modifiedAt; isFavorite = x.isFavorite; tags = x.tags
        }
    }
    struct Album: Codable {
        let id: UUID, parentID: UUID?, name: String, protectionRawValue: String
        let wrappedKey: Data, encryptedCatalog: Data, biometricAccount: String?, createdAt: Date
        init(_ x: VaultAlbum) {
            id = x.id; parentID = x.parentID; name = x.name; protectionRawValue = x.protectionRawValue
            wrappedKey = x.wrappedKey; encryptedCatalog = x.encryptedCatalog
            biometricAccount = x.biometricAccount; createdAt = x.createdAt
        }
    }
    enum Value { case media(Media), note(Note), album(Album) }
    static let maximumRecords = 20_000
    static let maximumSnapshotBytes = 64 * 1024 * 1024

    /// Caller must quiesce all writers. This does not establish a live WAL snapshot.
    static func capture(_ context: ModelContext, authorized: () -> Bool) throws -> [EncryptedMetadataStore.Record] {
        try check(context, authorized: authorized)
        let counts = [try context.fetchCount(FetchDescriptor<MediaItem>()),
                      try context.fetchCount(FetchDescriptor<SecretNote>()),
                      try context.fetchCount(FetchDescriptor<VaultAlbum>())]
        var total = 0
        for count in counts {
            guard count >= 0, count <= maximumRecords - total else { throw Failure.tooLarge }; total += count
        }
        var records: [EncryptedMetadataStore.Record] = [], bytes = 0
        func append<T: Codable>(_ value: T, kind: String, id: UUID) throws {
            guard authorized() else { throw Failure.unauthorized }
            try Task.checkCancellation()
            let payload = try encode(Envelope(version: 1, value: value))
            guard records.count < maximumRecords, payload.count <= EncryptedMetadataStore.maximumPayloadBytes,
                  payload.count <= maximumSnapshotBytes - bytes else { throw Failure.tooLarge }
            bytes += payload.count; records.append(.init(kind: kind, id: id, payload: payload))
        }
        try context.enumerate(FetchDescriptor<MediaItem>(), batchSize: 128) { item in try append(Media(item), kind: "media", id: item.id) }
        try context.enumerate(FetchDescriptor<SecretNote>(), batchSize: 128) { item in try append(Note(item), kind: "note", id: item.id) }
        try context.enumerate(FetchDescriptor<VaultAlbum>(), batchSize: 128) { item in try append(Album(item), kind: "album", id: item.id) }
        try check(context, authorized: authorized)
        guard Set(records.map { $0.kind + ":" + $0.id.uuidString }).count == records.count else { throw Failure.invalidRecord }
        return records.sorted { ($0.kind, $0.id.uuidString) < ($1.kind, $1.id.uuidString) }
    }

    static func decode(_ record: EncryptedMetadataStore.Record) throws -> Value {
        guard record.payload.count <= EncryptedMetadataStore.maximumPayloadBytes else { throw Failure.tooLarge }
        func open<T: Codable>(_ type: T.Type) throws -> T {
            let envelope = try JSONDecoder().decode(Envelope<T>.self, from: record.payload)
            // Canonical byte equality rejects unknown fields/versions instead of silently losing them.
            guard envelope.version == 1, try encode(envelope) == record.payload else { throw Failure.invalidRecord }
            return envelope.value
        }
        switch record.kind {
        case "media": let x = try open(Media.self); guard x.id == record.id else { throw Failure.invalidRecord }; return .media(x)
        case "note": let x = try open(Note.self); guard x.id == record.id else { throw Failure.invalidRecord }; return .note(x)
        case "album": let x = try open(Album.self); guard x.id == record.id else { throw Failure.invalidRecord }; return .album(x)
        default: throw Failure.invalidRecord
        }
    }

    /// Read adapter rehearsal only: always creates its own memory-only projection.
    /// It cannot save decoded values into the existing persistent source.
    static func memoryProjection(_ records: [EncryptedMetadataStore.Record], authorized: () -> Bool) throws -> ModelContainer {
        guard records.count <= maximumRecords else { throw Failure.tooLarge }
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext; context.autosaveEnabled = false
        var seen = Set<String>(), bytes = 0
        for record in records {
            guard authorized() else { throw Failure.unauthorized }
            try Task.checkCancellation()
            guard seen.insert(record.kind + ":" + record.id.uuidString).inserted else { throw Failure.invalidRecord }
            guard record.payload.count <= maximumSnapshotBytes - bytes else { throw Failure.tooLarge }
            bytes += record.payload.count
            switch try decode(record) {
            case .media(let x):
                let item = MediaItem(id: x.id, fileName: x.fileName, fileExtension: x.fileExtension, fileSize: x.fileSize,
                    type: .document, encryptedPath: x.encryptedPath, thumbnailData: x.thumbnailData,
                    createdAt: x.createdAt, modifiedAt: x.modifiedAt, width: x.width, height: x.height, duration: x.duration)
                item.typeRawValue = x.typeRawValue; context.insert(item)
            case .note(let x):
                let item = SecretNote(title: x.title, content: x.content, isFavorite: x.isFavorite, tags: x.tags)
                item.id = x.id; item.createdAt = x.createdAt; item.modifiedAt = x.modifiedAt; context.insert(item)
            case .album(let x):
                let item = VaultAlbum(id: x.id, parentID: x.parentID, name: x.name, protection: .inherited,
                    wrappedKey: x.wrappedKey, encryptedCatalog: x.encryptedCatalog, biometricAccount: x.biometricAccount)
                item.protectionRawValue = x.protectionRawValue; item.createdAt = x.createdAt; context.insert(item)
            }
        }
        guard authorized() else { throw Failure.unauthorized }
        try Task.checkCancellation(); try context.save()
        return container
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
    private static func check(_ context: ModelContext, authorized: () -> Bool) throws {
        guard authorized() else { throw Failure.unauthorized }
        try Task.checkCancellation()
        guard !context.hasChanges else { throw Failure.dirtyContext }
        let fields: [String: Set<String>] = [
            "MediaItem": ["id", "fileName", "fileExtension", "fileSize", "typeRawValue", "encryptedPath", "thumbnailData", "createdAt", "modifiedAt", "width", "height", "duration"],
            "SecretNote": ["id", "title", "content", "createdAt", "modifiedAt", "isFavorite", "tags"],
            "VaultAlbum": ["id", "parentID", "name", "protectionRawValue", "wrappedKey", "encryptedCatalog", "biometricAccount", "createdAt"]]
        let entities = context.container.schema.entities
        guard entities.count == fields.count, entities.allSatisfy({ fields[$0.name] == Set($0.properties.map(\.name)) }) else { throw Failure.unsupportedSchema }
    }
}
