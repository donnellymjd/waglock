import Foundation
import SwiftData

@MainActor
enum BackupPlanFactory {
    enum Failure: Error { case credentials, capacity }
    static func make(snapshot: PortableExportSnapshot, rootKey: String, albumStore: AlbumStore,
                     albums: [VaultAlbum], credentials: [PortableExportSnapshot.DomainID: AgeFileWriter.Credential]) throws -> BackupWorkPlan {
        typealias ID = PortableExportSnapshot.DomainID
        guard !rootKey.isEmpty, Set(credentials.keys) == Set(snapshot.content.domains.map(\.id)) else { throw Failure.credentials }
        let domains = Dictionary(uniqueKeysWithValues: snapshot.content.domains.map { ($0.id, $0) })
        func label(_ id: ID) -> String { switch id { case .root: return "root"; case .album(let id): return id.uuidString } }
        func depth(_ id: ID) throws -> Int {
            var seen = Set<ID>(), current: ID? = id
            while let value = current {
                guard seen.insert(value).inserted, let domain = domains[value] else { throw Failure.credentials }
                current = domain.parent
            }
            return seen.count - 1
        }
        let order = try snapshot.content.domains.map { ($0, try depth($0.id)) }.sorted {
            $0.1 == $1.1 ? label($0.0.id) < label($1.0.id) : $0.1 > $1.1
        }
        let revision = albumStore.revision
        var result: [BackupWorkPlan.Domain] = []
        var required: Int64 = 16 * 1024 * 1024, largest: Int64 = 0
        var metadataBytes = 0
        func charge(_ bytes: Int64, copies: Int) throws {
            let (total, overflow) = bytes.multipliedReportingOverflow(by: Int64(copies))
            let (sum, overflow2) = required.addingReportingOverflow(total)
            guard bytes >= 0, !overflow, !overflow2 else { throw Failure.capacity }; required = sum
        }
        func optional<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }
        for (domain, depth) in order {
            guard let credential = credentials[domain.id] else { throw Failure.credentials }
            if domain.id != .root, case .recipient = credential { throw Failure.credentials }
            // A separate-password child must not become readable with its parent's password.
            if let parent = domain.parent, case .password(let own) = credential,
               case .password(let outer) = credentials[parent], Data(own.utf8) == Data(outer.utf8) { throw Failure.credentials }
            let assetRows: [[String: Any]] = domain.assets.map { item in [
                "id": item.id.uuidString, "albumID": optional(item.albumID?.uuidString), "name": item.name,
                "fileExtension": item.fileExtension, "storedType": item.storedType, "effectiveType": item.effectiveType.rawValue,
                "declaredBytes": item.bytes, "createdAt": item.createdAt.timeIntervalSince1970,
                "modifiedAt": optional(item.modifiedAt?.timeIntervalSince1970), "width": optional(item.width), "height": optional(item.height),
                "duration": optional(item.duration), "payload": "media/" + item.id.uuidString,
                "thumbnail": item.thumbnail == nil ? NSNull() : "thumbnails/" + item.id.uuidString] }
            let metadata: [String: Any] = [
                "schema": "waglock-backup-metadata-1", "domain": label(domain.id), "parent": optional(domain.parent.map(label)),
                "assets": assetRows,
                "albums": domain.albums.map { ["id": $0.id.uuidString, "parentID": optional($0.parentID?.uuidString), "name": $0.name,
                    "protection": $0.protection.rawValue, "createdAt": $0.createdAt.timeIntervalSince1970] },
                "notes": domain.notes.map { ["id": $0.id.uuidString, "title": $0.title, "content": $0.content,
                    "createdAt": $0.createdAt.timeIntervalSince1970, "modifiedAt": $0.modifiedAt.timeIntervalSince1970,
                    "isFavorite": $0.isFavorite, "tags": $0.tags] },
                "drafts": domain.drafts.map { ["origin": $0.origin.rawValue, "title": $0.title,
                    "content": $0.content, "updatedAt": $0.updatedAt.timeIntervalSince1970] },
                "children": domain.children.map(label).sorted(),
                "notIncluded": ["deviceSettings", "FaceIDRegistrations", "nativeKeychainCredentials"], "trash": "notImplemented"]
            let encoded = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
            guard encoded.count <= 64 * 1024 * 1024 - metadataBytes else { throw Failure.capacity }
            metadataBytes += encoded.count
            try charge(Int64(encoded.count) + 4096, copies: depth + 1)
            var work: [BackupWorkPlan.Asset] = []
            for asset in domain.assets {
                let key = try asset.albumID.map { try albumStore.sourceKeyForBackup(albumID: $0, albums: albums, expectedRevision: revision) } ?? rootKey
                work.append(.init(id: asset.id, source: asset.source.url, sourceBytes: asset.source.ciphertextBytes, key: key, thumbnail: asset.thumbnail,
                    ciphertextDigest: asset.source.ciphertextDigest))
                let bytes = asset.source.ciphertextBytes
                guard bytes >= 0, bytes < Int64.max / 2 else { throw Failure.capacity }
                try charge(bytes + bytes / 4096 + 4096 + Int64(asset.thumbnail?.count ?? 0), copies: depth + 1)
                largest = max(largest, bytes)
            }
            result.append(.init(id: label(domain.id), children: domain.children.map(label).sorted(), metadata: encoded, assets: work, credential: credential))
        }
        try charge(largest, copies: 1)
        return .init(domains: result, requiredBytes: required)
    }
}
