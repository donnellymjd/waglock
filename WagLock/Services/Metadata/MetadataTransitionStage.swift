import CryptoKit
import Foundation

/// Unused, explicit staging only. Never publishes a mount or removes source/staged data.
@MainActor
enum MetadataTransitionStage {
    typealias Store = EncryptedMetadataStore
    enum Failure: Error { case unauthorized, invalidSource, sourceChanged, corruptProgress }
    enum Mode { case create, resume }
    enum Checkpoint { case batchCommitted(Int), beforeVerification, verified }
    struct Result { let completed: Int; let revision: UInt64 }
    private enum Phase: String, Codable { case importing, verified }
    private struct Progress: Codable {
        let version: Int
        let scope: String
        let sourceID: UUID
        let fingerprint: Data
        let count: Int
        var completed: Int
        var commits: UInt64
        var phase: Phase
    }
    private static let progressID = UUID(uuidString: "77BA3142-4237-49A4-B6AA-C892C6982291")!
    private static let batchSize = 127 // Reserve one of the store's 128 mutations for progress.

    /// Resume requires the same immutable, independently captured source values and key.
    /// Caller authorization is rechecked at each batch and verification boundary.
    static func run(mode: Mode, root: URL, domain: Store.Domain, key: Data, sourceID: UUID,
                    records: [Store.Record], authorized: () -> Bool,
                    checkpoint: (Checkpoint) throws -> Void = { _ in }) throws -> Result {
        func check() throws {
            guard authorized() else { throw Failure.unauthorized }; try Task.checkCancellation()
        }
        try check()
        let ordered = try validate(records)
        let fingerprint = digest(ordered)
        let store: Store
        switch mode {
        case .create: store = try Store.create(at: root, domain: domain, key: key)
        case .resume: store = try Store.open(at: root, domain: domain, key: key)
        }
        defer { store.revoke() }
        let access = store.access()
        var progress: Progress
        switch mode {
        case .create:
            progress = Progress(version: 1, scope: "legacy-models-and-retained-key-only", sourceID: sourceID, fingerprint: fingerprint, count: ordered.count,
                                completed: 0, commits: 1, phase: .importing)
            try check()
            try store.apply(access, revision: 0, mutations: [.put(try record(progress))])
        case .resume:
            // Opaque token ordering deliberately has no special "first" metadata row.
            let state = try store.state(access)
            guard state.count > 0, state.count <= MetadataModelCodec.maximumRecords + 1 else { throw Failure.corruptProgress }
            var found: Progress?
            for offset in 0..<state.count {
                try check()
                let row = try store.page(access, offset: offset, limit: 1, revision: state.revision).records[0]
                if row.kind == "transition" {
                    guard row.id == progressID, found == nil else { throw Failure.corruptProgress }
                    found = try JSONDecoder().decode(Progress.self, from: row.payload)
                }
            }
            guard let saved = found, saved.version == 1, saved.scope == "legacy-models-and-retained-key-only", saved.count == ordered.count,
                  saved.sourceID == sourceID, saved.fingerprint == fingerprint else { throw Failure.sourceChanged }
            guard saved.completed >= 0, saved.completed <= ordered.count, saved.commits == state.revision,
                  state.count == saved.completed + 1,
                  saved.phase != .verified || saved.completed == ordered.count else { throw Failure.corruptProgress }
            progress = saved
            // Verify the full saved prefix before resuming any writes.
            try verify(store, access: access, progress: progress, ordered: ordered, check: check)
        }
        while progress.completed < ordered.count {
            try check()
            let end = min(progress.completed + batchSize, ordered.count)
            var next = progress; next.completed = end; next.commits += 1
            let mutations = ordered[progress.completed..<end].map(Store.Mutation.put) + [.put(try record(next))]
            try store.apply(access, revision: progress.commits, mutations: mutations)
            progress = next
            try checkpoint(.batchCommitted(end)); try check()
        }
        try checkpoint(.beforeVerification); try check()
        try verify(store, access: access, progress: progress, ordered: ordered, check: check)
        if progress.phase != .verified {
            var next = progress; next.phase = .verified; next.commits += 1
            try check()
            try store.apply(access, revision: progress.commits, mutations: [.put(try record(next))])
            progress = next
        }
        try verify(store, access: access, progress: progress, ordered: ordered, check: check)
        try checkpoint(.verified); try check()
        return Result(completed: progress.completed, revision: progress.commits)
    }

    private static func verify(_ store: Store, access: Store.Access, progress: Progress,
                               ordered: [Store.Record], check: () throws -> Void) throws {
        try check(); try store.verifyAll(access)
        let state = try store.state(access)
        guard state.revision == progress.commits, state.count == progress.completed + 1 else { throw Failure.corruptProgress }
        let expected = Dictionary(uniqueKeysWithValues: (Array(ordered.prefix(progress.completed)) + [try record(progress)])
            .map { ($0.kind + ":" + $0.id.uuidString, $0.payload) })
        var seen = Set<String>()
        for offset in 0..<state.count {
            try check()
            let row = try store.page(access, offset: offset, limit: 1, revision: state.revision).records[0]
            let name = row.kind + ":" + row.id.uuidString
            guard seen.insert(name).inserted, expected[name] == row.payload else { throw Failure.corruptProgress }
        }
        guard seen.count == expected.count else { throw Failure.corruptProgress }; try check()
    }
    private static func validate(_ records: [Store.Record]) throws -> [Store.Record] {
        guard records.count <= MetadataModelCodec.maximumRecords else { throw Failure.invalidSource }
        var seen = Set<String>(), bytes = 0, keys = 0
        for row in records {
            try Task.checkCancellation()
            guard row.payload.count <= Store.maximumPayloadBytes,
                  row.payload.count <= MetadataModelCodec.maximumSnapshotBytes - bytes,
                  seen.insert(row.kind + ":" + row.id.uuidString).inserted else { throw Failure.invalidSource }
            bytes += row.payload.count
            if row.kind == "retained-key" {
                keys += 1
                guard keys <= 1, !row.payload.isEmpty, row.payload.count <= 4096 else { throw Failure.invalidSource }
            } else { _ = try MetadataModelCodec.decode(row) }
        }
        return records.sorted { ($0.kind, $0.id.uuidString) < ($1.kind, $1.id.uuidString) }
    }
    private static func digest(_ records: [Store.Record]) -> Data {
        var hash = SHA256()
        hash.update(data: Data("waglock-staged-models-1:\(records.count):".utf8))
        for row in records {
            hash.update(data: Data("\(row.kind):\(row.id.uuidString):\(row.payload.count):".utf8))
            hash.update(data: row.payload)
        }
        return Data(hash.finalize())
    }
    private static func record(_ progress: Progress) throws -> Store.Record {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return .init(kind: "transition", id: progressID, payload: try encoder.encode(progress))
    }
}
