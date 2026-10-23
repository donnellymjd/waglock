import Foundation

/// Unused draft transition adapter. Reads explicit sources; never migrates or clears them.
@MainActor
enum MetadataDraftCodec {
    enum Failure: Error { case unauthorized, unavailable, invalidRecord, tooLarge }
    enum Origin: String, Codable, CaseIterable {
        case keychain, legacyPreferences
        var id: UUID {
            switch self {
            case .keychain: return UUID(uuidString: "7603320B-A1A6-4381-96C9-9A0F6636CA61")!
            case .legacyPreferences: return UUID(uuidString: "D722D424-CBBE-4E28-B7B0-3C820B028F0C")!
            }
        }
    }
    struct Entry: Codable {
        let version: Int
        let origin: Origin
        let present: Bool
        let serialized: Data?
    }
    static let maximumDraftBytes = 8 * 1024 * 1024 - 4096

    static func capture(keychain: KeychainService, defaults: UserDefaults,
                        authorized: () -> Bool) throws -> [EncryptedMetadataStore.Record] {
        try capture(read: { origin in
            switch origin {
            case .keychain: return try keychain.loadSecretNoteDraftChecked()
            case .legacyPreferences:
                let value = defaults.object(forKey: "secretSpace.draft")
                guard value == nil || value is Data else { throw Failure.unavailable }
                return value as? Data
            }
        }, authorized: authorized)
    }

    /// Two records, including explicit absence, prevent silent source selection/omission.
    static func capture(read: (Origin) throws -> Data?, authorized: () -> Bool) throws -> [EncryptedMetadataStore.Record] {
        var records: [EncryptedMetadataStore.Record] = []
        for origin in Origin.allCases {
            try check(authorized)
            let raw: Data?
            do { raw = try read(origin) } catch { throw Failure.unavailable }
            try check(authorized)
            if let raw { _ = try value(raw) }
            let entry = Entry(version: 1, origin: origin, present: raw != nil, serialized: raw)
            let payload = try encode(entry)
            guard payload.count <= EncryptedMetadataStore.maximumPayloadBytes else { throw Failure.tooLarge }
            records.append(.init(kind: "draft", id: origin.id, payload: payload))
        }
        try check(authorized); return records
    }
    static func decode(_ row: EncryptedMetadataStore.Record) throws -> Entry {
        guard row.kind == "draft", row.payload.count <= EncryptedMetadataStore.maximumPayloadBytes else { throw Failure.invalidRecord }
        let entry: Entry
        do { entry = try JSONDecoder().decode(Entry.self, from: row.payload) } catch { throw Failure.invalidRecord }
        guard entry.version == 1, entry.origin.id == row.id, entry.present == (entry.serialized != nil),
              try encode(entry) == row.payload else { throw Failure.invalidRecord }
        if let raw = entry.serialized { _ = try value(raw) }
        return entry
    }
    static func value(_ serialized: Data) throws -> SecretNoteDraft {
        guard serialized.count <= maximumDraftBytes else { throw Failure.tooLarge }
        do {
            guard let object = try JSONSerialization.jsonObject(with: serialized) as? [String: Any],
                  Set(object.keys) == ["title", "content", "updatedAt"] else { throw Failure.invalidRecord }
            return try JSONDecoder().decode(SecretNoteDraft.self, from: serialized)
        } catch { throw Failure.invalidRecord }
    }
    private static func check(_ authorized: () -> Bool) throws {
        guard authorized() else { throw Failure.unauthorized }; try Task.checkCancellation()
    }
    private static func encode(_ entry: Entry) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(entry)
    }
}
