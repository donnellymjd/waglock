import CryptoKit
import Darwin
import Foundation
import SQLite3

/// Candidate mutable index. No production mount/login caller or legacy-store conversion.
/// SQLite receives opaque tokens and authenticated ciphertext, never decoded model values.
@MainActor
final class EncryptedMetadataStore {
    enum Failure: Error, Equatable { case locked, stale, busy, corrupt, storage, exists, unsafePath, tooLarge, uncertainCommit }
    struct Domain: Codable, Equatable { let libraryID: UUID; let vaultID: UUID }
    struct Record: Codable, Equatable { let kind: String; let id: UUID; let payload: Data }
    struct Access { fileprivate let owner: UUID; fileprivate let epoch: UUID }
    struct State: Equatable { let revision: UInt64; let count: Int }
    struct Page { let state: State; let records: [Record] }
    enum Mutation { case put(Record); case remove(kind: String, id: UUID) }
    enum Checkpoint { case afterRecords, beforeCommit, afterCommit }
    private struct Head: Codable { var revision: UInt64; var count: Int; var buckets: [Data] }
    private struct Bucket: Codable { var entries: [String: Data] }
    private enum Value { case integer(Int64), bytes(Data) }
    nonisolated static let maximumRecordBytes = 16 * 1024 * 1024
    nonisolated static let maximumPayloadBytes = 12 * 1024 * 1024 - 1024
    nonisolated static let maximumPageBytes = 32 * 1024 * 1024
    nonisolated private static let maximumBucketBytes = 4 * 1024 * 1024
    nonisolated private static let maximumHeadBytes = 32 * 1024
    private static let tables = [
        "CREATE TABLE head (id INTEGER PRIMARY KEY CHECK(id=0), body BLOB NOT NULL)",
        "CREATE TABLE buckets (id INTEGER PRIMARY KEY CHECK(id>=0 AND id<256), body BLOB NOT NULL)",
        "CREATE TABLE records (token BLOB PRIMARY KEY NOT NULL, body BLOB NOT NULL) WITHOUT ROWID"
    ]
    private let domain: Domain
    private let connection: MetadataSQLiteConnection
    private let owner = UUID()
    private var epoch = UUID()
    private var encryptionKey: SymmetricKey?
    private var tokenKey: SymmetricKey?
    private var busy = false
    private(set) var decodedRecords = 0

    // Avoid the isolated-deinit backdeployment path on older supported iOS runtimes.
    // Connection cleanup is nonisolated and owns no plaintext model references.
    nonisolated deinit { }

    static func create(at root: URL, domain: Domain, key: Data) throws -> EncryptedMetadataStore {
        guard key.count == 32 else { throw Failure.corrupt }
        let root = try checked(root)
        guard mkdir(root.path, S_IRWXU) == 0 else { throw errno == EEXIST ? Failure.exists : Failure.storage }
        do {
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
            #endif
            let file = root.appendingPathComponent("metadata.sqlite")
            let descriptor = Darwin.open(file.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw Failure.storage }
            Darwin.close(descriptor)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
            #endif
            let store = try EncryptedMetadataStore(file: file, domain: domain, key: key)
            try store.initializeEmpty()
            return store
        } catch {
            // The invocation exclusively created this directory; no source/media scan.
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    /// Resume only a never-published fresh bootstrap. No tables are dropped/reset.
    static func resumeUnpublishedEmpty(at root: URL, domain: Domain, key: Data) throws -> EncryptedMetadataStore {
        guard key.count == 32 else { throw Failure.corrupt }
        let root = try checked(root)
        let file = root.appendingPathComponent("metadata.sqlite")
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
        guard names.isSubset(of: ["metadata.sqlite", "metadata.sqlite-journal"]) else { throw Failure.corrupt }
        if !FileManager.default.fileExists(atPath: file.path) {
            guard names.isEmpty else { throw Failure.corrupt }
            let fd = Darwin.open(file.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw Failure.storage }; Darwin.close(fd)
        }
        _ = try checked(file)
        guard try FileManager.default.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType == .typeRegular else { throw Failure.unsafePath }
        let store = try EncryptedMetadataStore(file: file, domain: domain, key: key)
        do {
            guard try store.schema().isEmpty, try store.scalar("PRAGMA user_version") == 0,
                  try store.scalar("PRAGMA application_id") == 0 else { throw Failure.corrupt }
            try store.initializeEmpty(); return store
        } catch { store.revoke(); throw error }
    }
    private func initializeEmpty() throws {
        try self.execute("PRAGMA journal_mode=DELETE")
        try self.execute("BEGIN IMMEDIATE")
        do {
            for sql in Self.tables { try self.execute(sql) }
            try self.execute("PRAGMA application_id=1464681521")
            try self.execute("PRAGMA user_version=1")
            var hashes: [Data] = []
            for index in 0..<256 {
                let bytes = try self.seal(self.encode(Bucket(entries: [:])), purpose: "bucket-\(index)")
                hashes.append(Data(SHA256.hash(data: bytes)))
                try self.execute("INSERT INTO buckets VALUES (?,?)", [.integer(Int64(index)), .bytes(bytes)])
            }
            let head = Head(revision: 0, count: 0, buckets: hashes)
            try self.execute("INSERT INTO head VALUES (0,?)", [.bytes(try self.seal(self.encode(head), purpose: "head"))])
            try self.execute("COMMIT")
        } catch { try? self.execute("ROLLBACK"); throw error }
        _ = try self.state(self.access())
    }

    static func open(at root: URL, domain: Domain, key: Data) throws -> EncryptedMetadataStore {
        guard key.count == 32 else { throw Failure.corrupt }
        let root = try checked(root), file = try checked(root.appendingPathComponent("metadata.sqlite"))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure.unsafePath }
        let store = try EncryptedMetadataStore(file: file, domain: domain, key: key)
        guard try store.scalar("PRAGMA application_id") == 1464681521,
              try store.scalar("PRAGMA user_version") == 1 else { throw Failure.corrupt }
        let schema = try store.schema()
        guard schema == Set(tables) else { throw Failure.corrupt }
        _ = try store.state(store.access())
        return store
    }

    private init(file: URL, domain: Domain, key: Data) throws {
        self.domain = domain
        let input = SymmetricKey(data: key)
        let salt = Data((domain.libraryID.uuidString + ":" + domain.vaultID.uuidString).utf8)
        encryptionKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: input, salt: salt,
            info: Data("waglock-metadata-aead-1".utf8), outputByteCount: 32)
        tokenKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: input, salt: salt,
            info: Data("waglock-metadata-token-1".utf8), outputByteCount: 32)
        connection = try MetadataSQLiteConnection(file: file)
        sqlite3_limit(connection.handle, SQLITE_LIMIT_LENGTH, Int32(Self.maximumRecordBytes + 1024 * 1024))
        sqlite3_limit(connection.handle, SQLITE_LIMIT_SQL_LENGTH, 8192)
        try execute("PRAGMA synchronous=FULL")
        try execute("PRAGMA fullfsync=ON")
        try execute("PRAGMA temp_store=MEMORY")
        try execute("PRAGMA mmap_size=0")
    }

    func access() -> Access { Access(owner: owner, epoch: epoch) }
    func revoke() {
        encryptionKey = nil; tokenKey = nil; epoch = UUID()
        if !busy { connection.close() }
    }
    private func check(_ access: Access) throws {
        guard access.owner == owner, access.epoch == epoch, encryptionKey != nil,
              tokenKey != nil, connection.handle != nil else { throw Failure.locked }
        try Task.checkCancellation()
    }
    private func transaction<T>(_ access: Access, _ work: () throws -> T) throws -> T {
        try check(access)
        guard !busy else { throw Failure.busy }
        busy = true
        defer { busy = false; if encryptionKey == nil { connection.close() } }
        try execute("BEGIN")
        do {
            let result = try work(); try check(access); try execute("COMMIT"); return result
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func state(_ access: Access) throws -> State {
        try transaction(access) { let head = try readHead(); return State(revision: head.revision, count: head.count) }
    }
    func page(_ access: Access, offset: Int, limit: Int, revision: UInt64? = nil, byteLimit: Int = maximumPageBytes) throws -> Page {
        guard offset >= 0, limit > 0, limit <= 128, byteLimit > 0, byteLimit <= Self.maximumPageBytes else { throw Failure.tooLarge }
        return try transaction(access) {
            let head = try readHead()
            guard revision == nil || revision == head.revision else { throw Failure.stale }
            guard offset <= head.count else { throw Failure.tooLarge }
            let statement = try prepare("SELECT token,body FROM records ORDER BY token LIMIT ? OFFSET ?", [.integer(Int64(limit)), .integer(Int64(offset))])
            defer { sqlite3_finalize(statement) }
            var records: [Record] = [], buckets: [Int: Bucket] = [:], decodedBytes = 0
            while try step(statement) {
                let token = try column(statement, 0, maximum: 32)
                guard token.count == 32, let first = token.first else { throw Failure.corrupt }
                let slot = Int(first)
                if buckets[slot] == nil { buckets[slot] = try readBucket(slot, head: head) }
                let ciphertext = try column(statement, 1, maximum: Self.maximumRecordBytes + 64)
                guard buckets[slot]?.entries[token.base64EncodedString()] == Data(SHA256.hash(data: ciphertext)) else { throw Failure.corrupt }
                guard ciphertext.count <= byteLimit - decodedBytes else { throw Failure.tooLarge }
                decodedBytes += ciphertext.count
                let record = try JSONDecoder().decode(Record.self, from: open(ciphertext, purpose: "record", token: token))
                guard try self.token(kind: record.kind, id: record.id) == token else { throw Failure.corrupt }
                decodedRecords += 1; records.append(record)
            }
            guard records.count == min(limit, head.count - offset) else { throw Failure.corrupt }
            return Page(state: State(revision: head.revision, count: head.count), records: records)
        }
    }

    /// Full ciphertext inventory verification; required before accepting a staged transition.
    func verifyAll(_ access: Access) throws {
        try transaction(access) {
            let head = try readHead()
            var count = 0
            for index in 0..<256 {
                let bucket = try readBucket(index, head: head)
                for (encoded, hash) in bucket.entries {
                    guard let token = Data(base64Encoded: encoded), token.count == 32, token.first == UInt8(index) else { throw Failure.corrupt }
                    let bytes = try blob("SELECT body FROM records WHERE token=?", [.bytes(token)], maximum: Self.maximumRecordBytes + 64)
                    guard Data(SHA256.hash(data: bytes)) == hash else { throw Failure.corrupt }
                    count += 1
                }
            }
            guard count == head.count else { throw Failure.corrupt }
        }
    }

    @discardableResult
    func apply(_ access: Access, revision: UInt64, mutations: [Mutation],
               checkpoint: (Checkpoint) throws -> Void = { _ in }, mutationLimit: Int = 128) throws -> State {
        try check(access)
        guard !busy, mutationLimit > 0, mutations.count <= mutationLimit else { throw Failure.busy }
        busy = true
        defer { busy = false; if encryptionKey == nil { connection.close() } }
        try execute("BEGIN IMMEDIATE")
        var commitAttempted = false, committed = false
        do {
            var head = try readHead()
            guard head.revision == revision, head.revision < UInt64.max else { throw Failure.stale }
            var buckets: [Int: Bucket] = [:], touched = Set<Data>()
            for mutation in mutations {
                try check(access)
                let token: Data, ciphertext: Data?
                switch mutation {
                case .put(let record):
                    guard record.payload.count <= Self.maximumPayloadBytes else { throw Failure.tooLarge }
                    token = try self.token(kind: record.kind, id: record.id)
                    let bytes = try encode(record)
                    guard bytes.count <= Self.maximumRecordBytes else { throw Failure.tooLarge }
                    ciphertext = try seal(bytes, purpose: "record", token: token)
                case .remove(let kind, let id): token = try self.token(kind: kind, id: id); ciphertext = nil
                }
                guard touched.insert(token).inserted, let first = token.first else { throw Failure.corrupt }
                let slot = Int(first), name = token.base64EncodedString()
                if buckets[slot] == nil { buckets[slot] = try readBucket(slot, head: head) }
                var bucket = buckets[slot]!
                if let expected = bucket.entries[name] {
                    let existing = try blob("SELECT body FROM records WHERE token=?", [.bytes(token)], maximum: Self.maximumRecordBytes + 64)
                    guard Data(SHA256.hash(data: existing)) == expected else { throw Failure.corrupt }
                } else {
                    guard try scalar("SELECT count(*) FROM records WHERE token=?", [.bytes(token)]) == 0 else { throw Failure.corrupt }
                }
                if let ciphertext {
                    if bucket.entries[name] == nil { head.count += 1 }
                    bucket.entries[name] = Data(SHA256.hash(data: ciphertext))
                    try execute("INSERT OR REPLACE INTO records VALUES (?,?)", [.bytes(token), .bytes(ciphertext)])
                } else {
                    guard bucket.entries.removeValue(forKey: name) != nil else { throw Failure.corrupt }
                    head.count -= 1
                    try execute("DELETE FROM records WHERE token=?", [.bytes(token)])
                }
                buckets[slot] = bucket
            }
            try checkpoint(.afterRecords); try check(access)
            for (slot, bucket) in buckets {
                let encoded = try encode(bucket)
                guard encoded.count <= Self.maximumBucketBytes else { throw Failure.tooLarge }
                let ciphertext = try seal(encoded, purpose: "bucket-\(slot)")
                head.buckets[slot] = Data(SHA256.hash(data: ciphertext))
                try execute("UPDATE buckets SET body=? WHERE id=?", [.bytes(ciphertext), .integer(Int64(slot))])
            }
            head.revision += 1
            try execute("UPDATE head SET body=? WHERE id=0", [.bytes(try seal(encode(head), purpose: "head"))])
            guard try scalar("SELECT count(*) FROM records") == Int64(head.count) else { throw Failure.corrupt }
            try checkpoint(.beforeCommit); try check(access)
            commitAttempted = true; try execute("COMMIT"); committed = true
            try checkpoint(.afterCommit); try check(access)
            return State(revision: head.revision, count: head.count)
        } catch {
            if !committed { try? execute("ROLLBACK") }
            if commitAttempted {
                // The caller must reopen/reconcile; never infer permission to delete media.
                revoke(); throw Failure.uncertainCommit
            }
            throw error
        }
    }

    private func readHead() throws -> Head {
        let head = try JSONDecoder().decode(Head.self, from: open(blob("SELECT body FROM head WHERE id=0", maximum: Self.maximumHeadBytes), purpose: "head"))
        guard head.buckets.count == 256, head.count >= 0,
              head.buckets.allSatisfy({ $0.count == 32 }), try scalar("SELECT count(*) FROM records") == Int64(head.count),
              try scalar("SELECT count(*) FROM buckets") == 256, try scalar("SELECT count(*) FROM head") == 1 else { throw Failure.corrupt }
        return head
    }
    private func readBucket(_ slot: Int, head: Head) throws -> Bucket {
        let ciphertext = try blob("SELECT body FROM buckets WHERE id=?", [.integer(Int64(slot))], maximum: Self.maximumBucketBytes + 64)
        guard Data(SHA256.hash(data: ciphertext)) == head.buckets[slot] else { throw Failure.corrupt }
        let bucket = try JSONDecoder().decode(Bucket.self, from: open(ciphertext, purpose: "bucket-\(slot)"))
        guard bucket.entries.allSatisfy({ key, value in
            guard let token = Data(base64Encoded: key) else { return false }
            return token.count == 32 && token.first == UInt8(slot) && value.count == 32
        }) else { throw Failure.corrupt }
        return bucket
    }
    private func token(kind: String, id: UUID) throws -> Data {
        guard let key = tokenKey else { throw Failure.locked }
        guard ["media", "note", "album", "draft", "settings", "retained-key", "transition"].contains(kind) else { throw Failure.corrupt }
        return Data(HMAC<SHA256>.authenticationCode(for: Data((kind + ":" + id.uuidString).utf8), using: key))
    }
    private func aad(_ purpose: String, _ token: Data) -> Data {
        Data(("waglock-metadata-1:" + domain.libraryID.uuidString + ":" + domain.vaultID.uuidString + ":" + purpose + ":").utf8) + token
    }
    private func seal(_ data: Data, purpose: String, token: Data = Data()) throws -> Data {
        guard let key = encryptionKey else { throw Failure.locked }
        guard let bytes = try AES.GCM.seal(data, using: key, authenticating: aad(purpose, token)).combined else { throw Failure.corrupt }
        return bytes
    }
    private func open(_ data: Data, purpose: String, token: Data = Data()) throws -> Data {
        guard let key = encryptionKey else { throw Failure.locked }
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: aad(purpose, token)) }
        catch { throw Failure.corrupt }
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
    private static func checked(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw Failure.unsafePath }
        var path = url.standardizedFileURL.path
        // Foundation may abbreviate these OS-owned aliases. Expand only their
        // known system destinations; reject every other symlink component.
        for alias in ["/var", "/tmp"] where path == alias || path.hasPrefix(alias + "/") {
            if let pointer = realpath(alias, nil) {
                let target = String(cString: pointer); free(pointer)
                if target == "/private" + alias { path = target + path.dropFirst(alias.count) }
            }
        }
        var current = ""
        for component in path.split(separator: "/") {
            current += "/" + component
            var info = stat()
            if lstat(current, &info) == 0 {
                guard info.st_mode & S_IFMT != S_IFLNK else { throw Failure.unsafePath }
            } else if errno != ENOENT { throw Failure.storage }
        }
        return URL(fileURLWithPath: path)
    }
    private func prepare(_ sql: String, _ values: [Value] = []) throws -> OpaquePointer {
        guard let db = connection.handle else { throw Failure.locked }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement); throw Failure.storage
        }
        do {
            for (index, value) in values.enumerated() {
                let status: Int32
                switch value {
                case .integer(let number): status = sqlite3_bind_int64(statement, Int32(index + 1), number)
                case .bytes(let bytes): status = bytes.withUnsafeBytes { raw in
                    sqlite3_bind_blob(statement, Int32(index + 1), raw.baseAddress, Int32(raw.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
                }
                guard status == SQLITE_OK else { throw Failure.storage }
            }
            return statement
        } catch { sqlite3_finalize(statement); throw error }
    }
    private func step(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) { case SQLITE_ROW: return true; case SQLITE_DONE: return false; default: throw Failure.storage }
    }
    private func execute(_ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        while try step(statement) { }
    }
    private func column(_ statement: OpaquePointer, _ index: Int32, maximum: Int) throws -> Data {
        let size = Int(sqlite3_column_bytes(statement, index))
        guard size > 0, size <= maximum, let pointer = sqlite3_column_blob(statement, index) else { throw Failure.corrupt }
        return Data(bytes: pointer, count: size)
    }
    private func blob(_ sql: String, _ values: [Value] = [], maximum: Int) throws -> Data {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        guard try step(statement) else { throw Failure.corrupt }
        let bytes = try column(statement, 0, maximum: maximum)
        guard try !step(statement) else { throw Failure.corrupt }
        return bytes
    }
    private func scalar(_ sql: String, _ values: [Value] = []) throws -> Int64 {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        guard try step(statement) else { throw Failure.corrupt }
        return sqlite3_column_int64(statement, 0)
    }
    private func schema() throws -> Set<String> {
        let statement = try prepare("SELECT sql FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'"); defer { sqlite3_finalize(statement) }
        var result = Set<String>()
        while try step(statement) {
            guard let value = sqlite3_column_text(statement, 0) else { throw Failure.corrupt }
            result.insert(String(cString: value))
        }
        return result
    }
}

/// Lifetime wrapper only; the owning store serializes every operation on MainActor.
nonisolated private final class MetadataSQLiteConnection: @unchecked Sendable {
    private(set) var handle: OpaquePointer?
    init(file: URL) throws {
        // Foundation canonicalizes system aliases differently for existing files.
        // Resolve the already-validated file with POSIX before NOFOLLOW open.
        guard let canonical = realpath(file.path, nil) else { throw EncryptedMetadataStore.Failure.storage }
        defer { free(canonical) }
        var db: OpaquePointer?
        guard sqlite3_open_v2(canonical, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK else {
            sqlite3_close(db); throw EncryptedMetadataStore.Failure.storage
        }
        handle = db
        sqlite3_busy_timeout(db, 1000)
    }
    func close() { if let handle { sqlite3_close_v2(handle); self.handle = nil } }
    deinit { close() }
}
