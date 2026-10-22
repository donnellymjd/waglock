import CryptoKit
import Foundation
import SwiftData
@testable import WagLock

/// Disposable migration rehearsal only. Never called by production or given a live app root.
/// This is not a portable vault format, a media migration, or a production database adapter.
@MainActor
final class LegacyMetadataTransitionPrototype {
    enum Failure: Error { case corrupt, unsafePath, duplicate, tooLarge, locked }
    struct Domain: Codable, Equatable {
        let libraryID: UUID
        let vaultID: UUID
    }
    struct Record: Codable, Equatable {
        let kind: String
        let id: UUID
        let payload: Data
    }
    private struct Binding: Encodable {
        let version = 1
        let domain: Domain
        let purpose: String
        let fileID: UUID?
    }
    private struct Reference: Codable {
        let kind: String
        let id: UUID
        let fileID: UUID
        let hash: Data
    }
    private struct Manifest: Codable {
        let domain: Domain
        let legacyDataSecret: Data
        let records: [Reference]
    }
    typealias Writer = (Data, URL) throws -> Void
    typealias Publisher = (URL, URL) throws -> Void
    static let maxRecords = 20_000
    static let maxRecordBytes = 4 * 1_024 * 1_024
    private static let maxManifestBytes = 8 * 1_024 * 1_024

    /// Reads the three existing model types without saving, renaming paths or unwrapping album keys.
    /// The caller must provide a quiescent disposable source snapshot, not the running app context.
    static func capture(_ context: ModelContext) throws -> [Record] {
        var records: [Record] = []
        func append<T: Encodable>(_ value: T, kind: String, id: UUID) throws {
            guard records.count < maxRecords else { throw Failure.tooLarge }
            let payload = try JSONEncoder().encode(value)
            guard payload.count <= maxRecordBytes else { throw Failure.tooLarge }
            records.append(Record(kind: kind, id: id, payload: payload))
        }
        for x in try context.fetch(FetchDescriptor<MediaItem>()) {
            try append(Media(x), kind: "media", id: x.id)
        }
        for x in try context.fetch(FetchDescriptor<SecretNote>()) {
            try append(Note(x), kind: "note", id: x.id)
        }
        for x in try context.fetch(FetchDescriptor<VaultAlbum>()) {
            try append(Album(x), kind: "album", id: x.id)
        }
        return records.sorted { ($0.kind, $0.id.uuidString) < ($1.kind, $1.id.uuidString) }
    }

    /// Stages a new encrypted destination, verifies every record, then publishes by directory rename.
    /// Failure cleanup is confined to this invocation's newly created staging directory.
    static func stage(_ records: [Record], legacyDataSecret: Data, domain: Domain,
                      key: SymmetricKey, outputRoot: URL,
                      writer: Writer = { try $0.write(to: $1, options: [.atomic, .completeFileProtection]) },
                      publish: Publisher = { try FileManager.default.moveItem(at: $0, to: $1) }) throws -> URL {
        guard records.count <= maxRecords, legacyDataSecret.count <= 4_096 else { throw Failure.tooLarge }
        guard Set(records.map { $0.kind + ":" + $0.id.uuidString }).count == records.count else { throw Failure.duplicate }
        let root = try checked(outputRoot)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure.unsafePath
        }
        let staging = root.appendingPathComponent("pending-" + UUID().uuidString)
        let destination = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                               attributes: [.protectionKey: FileProtectionType.complete])
        defer { try? FileManager.default.removeItem(at: staging) }
        var references: [Reference] = []
        for record in records {
            let encoded = try JSONEncoder().encode(record)
            guard encoded.count <= maxRecordBytes else { throw Failure.tooLarge }
            let fileID = UUID()
            let ciphertext = try seal(encoded, key: key, domain: domain, purpose: "record", fileID: fileID)
            try writer(ciphertext, staging.appendingPathComponent(fileID.uuidString + ".enc"))
            references.append(Reference(kind: record.kind, id: record.id, fileID: fileID,
                                        hash: Data(SHA256.hash(data: ciphertext))))
        }
        let manifest = Manifest(domain: domain, legacyDataSecret: legacyDataSecret, records: references)
        let encodedManifest = try JSONEncoder().encode(manifest)
        guard encodedManifest.count <= maxManifestBytes else { throw Failure.tooLarge }
        try writer(seal(encodedManifest, key: key, domain: domain, purpose: "manifest", fileID: nil),
                   staging.appendingPathComponent("manifest.enc"))
        let reader = try Reader(root: staging, domain: domain, key: key)
        defer { reader.lock() }
        guard try reader.legacyDataSecret() == legacyDataSecret else { throw Failure.corrupt }
        for offset in stride(from: 0, to: records.count, by: 32) {
            let end = min(offset + 32, records.count)
            guard try reader.page(offset: offset, limit: 32) == Array(records[offset..<end]) else { throw Failure.corrupt }
        }
        // If a publisher reports failure after moving, preserve the published encrypted copy.
        // Never delete destination/unknown files based solely on a thrown error.
        try publish(staging, destination)
        return destination
    }

    @MainActor
    final class Reader {
        private let root: URL
        private let domain: Domain
        private var key: SymmetricKey?
        private var manifest: Manifest?
        private(set) var decodedRecords = 0

        init(root: URL, domain: Domain, key: SymmetricKey) throws {
            self.root = try checked(root)
            self.domain = domain
            let bytes = try read(self.root.appendingPathComponent("manifest.enc"), maximum: maxManifestBytes + 128)
            let opened = try open(bytes, key: key, domain: domain, purpose: "manifest", fileID: nil)
            let manifest = try JSONDecoder().decode(Manifest.self, from: opened)
            guard manifest.domain == domain, manifest.records.count <= maxRecords,
                  Set(manifest.records.map(\.fileID)).count == manifest.records.count,
                  Set(manifest.records.map { $0.kind + ":" + $0.id.uuidString }).count == manifest.records.count,
                  manifest.legacyDataSecret.count <= 4_096 else { throw Failure.corrupt }
            self.manifest = manifest
            self.key = key
        }

        var count: Int? { manifest?.records.count }

        func legacyDataSecret() throws -> Data {
            guard key != nil, let manifest else { throw Failure.locked }
            return manifest.legacyDataSecret
        }

        func page(offset: Int, limit: Int) throws -> [Record] {
            guard let key, let manifest else { throw Failure.locked }
            guard offset >= 0, offset <= manifest.records.count, limit > 0, limit <= 128 else { throw Failure.tooLarge }
            let end = offset + min(limit, manifest.records.count - offset)
            return try manifest.records[offset..<end].map { reference in
                let ciphertext = try read(root.appendingPathComponent(reference.fileID.uuidString + ".enc"),
                                          maximum: maxRecordBytes + 128)
                guard Data(SHA256.hash(data: ciphertext)) == reference.hash else { throw Failure.corrupt }
                let bytes = try open(ciphertext, key: key, domain: domain, purpose: "record", fileID: reference.fileID)
                let record = try JSONDecoder().decode(Record.self, from: bytes)
                guard record.kind == reference.kind, record.id == reference.id else { throw Failure.corrupt }
                decodedRecords += 1
                return record
            }
        }

        func lock() { key = nil; manifest = nil }
    }

    private static func checked(_ url: URL) throws -> URL {
        let normal = url.standardizedFileURL
        guard normal == normal.resolvingSymlinksInPath().standardizedFileURL else { throw Failure.unsafePath }
        return normal
    }

    private static func read(_ url: URL, maximum: Int) throws -> Data {
        let path = try checked(url)
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.int64Value <= Int64(maximum) else { throw Failure.tooLarge }
        return try Data(contentsOf: path)
    }

    private static func aad(domain: Domain, purpose: String, fileID: UUID?) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Binding(domain: domain, purpose: purpose, fileID: fileID))
    }
    private static func seal(_ data: Data, key: SymmetricKey, domain: Domain, purpose: String, fileID: UUID?) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key,
                                             authenticating: aad(domain: domain, purpose: purpose, fileID: fileID)).combined else {
            throw Failure.corrupt
        }
        return combined
    }
    private static func open(_ data: Data, key: SymmetricKey, domain: Domain, purpose: String, fileID: UUID?) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key,
                         authenticating: aad(domain: domain, purpose: purpose, fileID: fileID))
    }

    struct Media: Codable, Equatable {
        let id: UUID, fileName: String, fileExtension: String, fileSize: Int64, typeRawValue: String
        let encryptedPath: String, thumbnailData: Data?, createdAt: Date, modifiedAt: Date
        let width: Int?, height: Int?, duration: Double?
        @MainActor init(_ x: MediaItem) {
            id = x.id; fileName = x.fileName; fileExtension = x.fileExtension; fileSize = x.fileSize
            typeRawValue = x.typeRawValue; encryptedPath = x.encryptedPath; thumbnailData = x.thumbnailData
            createdAt = x.createdAt; modifiedAt = x.modifiedAt; width = x.width; height = x.height; duration = x.duration
        }
    }
    struct Note: Codable, Equatable {
        let id: UUID, title: String, content: String, createdAt: Date, modifiedAt: Date, isFavorite: Bool, tags: [String]
        @MainActor init(_ x: SecretNote) {
            id = x.id; title = x.title; content = x.content; createdAt = x.createdAt
            modifiedAt = x.modifiedAt; isFavorite = x.isFavorite; tags = x.tags
        }
    }
    struct Album: Codable, Equatable {
        let id: UUID, parentID: UUID?, name: String, protectionRawValue: String
        let wrappedKey: Data, encryptedCatalog: Data, biometricAccount: String?, createdAt: Date
        @MainActor init(_ x: VaultAlbum) {
            id = x.id; parentID = x.parentID; name = x.name; protectionRawValue = x.protectionRawValue
            wrappedKey = x.wrappedKey; encryptedCatalog = x.encryptedCatalog
            biometricAccount = x.biometricAccount; createdAt = x.createdAt
        }
    }
}
