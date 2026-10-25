import CryptoKit
import Darwin
import Foundation

nonisolated final class BackupLease: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var owned: URL?
    func recordOwnership(_ url: URL) { lock.lock(); owned = url; lock.unlock() }
    var ownedDirectory: URL? { lock.lock(); defer { lock.unlock() }; return owned }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped || Task.isCancelled { throw CancellationError() }
    }
}

nonisolated struct BackupWorkPlan: Sendable {
    struct Asset: Sendable {
        let id: UUID
        let source: URL
        let sourceBytes: Int64
        let key: String
        let thumbnail: Data?
        var ciphertextDigest: Data? = nil
    }
    struct Domain: Sendable {
        let id: String
        let children: [String]
        let metadata: Data
        let assets: [Asset]
        let credential: AgeFileWriter.Credential
    }
    let domains: [Domain] // Children before parents; root last.
    let requiredBytes: Int64
}

nonisolated final class BackupTarWriter {
    struct Entry: Codable, Sendable { let path: String; let bytes: Int64; let sha256: String }
    enum Failure: Error { case malformedPath, changedSource, tooLarge }
    private let sink: (Data) throws -> Void
    private let check: () throws -> Void
    private var names = Set<String>()
    init(sink: @escaping (Data) throws -> Void, check: @escaping () throws -> Void) { self.sink = sink; self.check = check }

    func add(_ data: Data, path: String) throws -> Entry {
        try header(path, size: Int64(data.count))
        var hash = SHA256()
        var offset = 0
        while offset < data.count {
            try check()
            let end = min(data.count, offset + 65536), chunk = data.subdata(in: offset..<min(data.count, offset + 65536))
            try sink(chunk); hash.update(data: chunk); offset = end
        }
        try padding(Int64(data.count))
        return .init(path: path, bytes: Int64(data.count), sha256: Self.hex(hash.finalize()))
    }
    func add(file: URL, path: String) throws -> Entry {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let value = attributes[.size] as? NSNumber, value.int64Value >= 0 else { throw Failure.changedSource }
        let size = value.int64Value
        try header(path, size: size)
        let input = try FileHandle(forReadingFrom: file); defer { try? input.close() }
        var remaining = size, hash = SHA256()
        while remaining > 0 {
            try check()
            let chunk = try input.read(upToCount: Int(min(65536, remaining))) ?? Data()
            guard !chunk.isEmpty else { throw Failure.changedSource }
            hash.update(data: chunk); try sink(chunk); remaining -= Int64(chunk.count)
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw Failure.changedSource }
        try padding(size)
        return .init(path: path, bytes: size, sha256: Self.hex(hash.finalize()))
    }
    func finish() throws { try check(); try sink(Data(count: 1024)) }
    private func header(_ path: String, size: Int64) throws {
        try check()
        guard path.utf8.count < 100, path.unicodeScalars.allSatisfy({ $0.isASCII }),
              !path.hasPrefix("/"), path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              names.insert(path).inserted, size >= 0 else { throw Failure.malformedPath }
        if size > 0o77777777777 {
            let body = Self.pax("size=\(size)\n")
            try sink(Self.record("PaxHeaders/size", size: Int64(body.count), type: 120))
            try sink(body); try padding(Int64(body.count))
        }
        try sink(Self.record(path, size: size > 0o77777777777 ? 0 : size, type: 48))
    }
    private func padding(_ size: Int64) throws { let count = Int((512 - size % 512) % 512); if count > 0 { try sink(Data(count: count)) } }
    private static func record(_ path: String, size: Int64, type: UInt8) -> Data {
        var bytes = [UInt8](repeating: 0, count: 512)
        func put(_ value: String, _ offset: Int) { for (index, byte) in value.utf8.enumerated() { bytes[offset + index] = byte } }
        func octal(_ value: Int64, _ width: Int) -> String {
            let text = String(value, radix: 8); return String(repeating: "0", count: width - 1 - text.count) + text + "\0"
        }
        put(path, 0); put("0000600\0", 100); put("0000000\0", 108); put("0000000\0", 116)
        put(octal(size, 12), 124); put("00000000000\0", 136)
        for index in 148..<156 { bytes[index] = 32 }; bytes[156] = type
        put("ustar\0", 257); put("00", 263)
        let sum = bytes.reduce(0) { $0 + Int64($1) }
        let text = String(sum, radix: 8)
        put(String(repeating: "0", count: 6 - text.count) + text + "\0 ", 148)
        return Data(bytes)
    }
    private static func pax(_ text: String) -> Data {
        var size = text.utf8.count + 2
        while true {
            let value = "\(size) " + text
            if value.utf8.count == size { return Data(value.utf8) }
            size = value.utf8.count
        }
    }
    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
}

nonisolated enum BackupArchiveBuilder {
    enum Failure: Error { case lowSpace, legacyFileTooLarge, invalidPlan }
    static func build(_ plan: BackupWorkPlan, directory: URL, lease: BackupLease,
                      capacity: @Sendable (URL) throws -> Int64 = availableCapacity,
                      progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) throws -> URL {
        try lease.check()
        guard plan.domains.last?.id == "root", Set(plan.domains.map(\.id)).count == plan.domains.count,
              plan.requiredBytes >= 0, plan.domains.allSatisfy({ $0.id == "root" || UUID(uuidString: $0.id)?.uuidString == $0.id }) else { throw Failure.invalidPlan }
        guard try capacity(directory.deletingLastPathComponent()) >= plan.requiredBytes else { throw Failure.lowSpace }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        lease.recordOwnership(directory)
        do {
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
            #endif
            let total = plan.domains.reduce(0) { $0 + $1.assets.count } + plan.domains.count
            var completed = 0, outputs: [String: URL] = [:]
            for domain in plan.domains {
                try lease.check()
                let output = directory.appendingPathComponent(domain.id + ".building.age")
                let encrypted = try AgeFileWriter(to: output, credential: domain.credential, check: { try lease.check() })
                let tar = BackupTarWriter(sink: encrypted.write, check: { try lease.check() })
                var entries: [BackupTarWriter.Entry] = []
                entries.append(try tar.add(domain.metadata, path: "metadata.json"))
                for asset in domain.assets {
                    try lease.check()
                    let attributes = try FileManager.default.attributesOfItem(atPath: asset.source.path)
                    guard attributes[.type] as? FileAttributeType == .typeRegular,
                          let size = attributes[.size] as? NSNumber, size.int64Value == asset.sourceBytes else { throw Failure.invalidPlan }
                    let source = try FileHandle(forReadingFrom: asset.source)
                    let magic = try source.read(upToCount: 4); try source.close()
                    if magic != Data("ZNSC".utf8), asset.sourceBytes > 64 * 1024 * 1024 { throw Failure.legacyFileTooLarge }
                    let plaintext = directory.appendingPathComponent("working-media")
                    do {
                        try EncryptionService.shared.decryptFile(inputURL: asset.source, to: plaintext, password: asset.key,
                            expectedCiphertextDigest: asset.ciphertextDigest)
                        try lease.check()
                        entries.append(try tar.add(file: plaintext, path: "media/" + asset.id.uuidString))
                        try FileManager.default.removeItem(at: plaintext)
                    } catch {
                        try? FileManager.default.removeItem(at: plaintext); throw error
                    }
                    if let thumbnail = asset.thumbnail { entries.append(try tar.add(thumbnail, path: "thumbnails/" + asset.id.uuidString)) }
                    completed += 1; progress(completed, total)
                }
                for child in domain.children {
                    guard let file = outputs[child] else { throw Failure.invalidPlan }
                    entries.append(try tar.add(file: file, path: "protected/" + child + ".tar.age"))
                }
                let manifest: [String: Any] = ["schema": "waglock-backup-manifest-1",
                    "files": try entries.map { entry -> [String: Any] in
                        guard entry.bytes >= 0 else { throw Failure.invalidPlan }
                        return ["path": entry.path, "bytes": entry.bytes, "sha256": entry.sha256]
                    }, "nested": domain.children.map { "protected/" + $0 + ".tar.age" }]
                _ = try tar.add(JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]), path: "manifest.json")
                try tar.finish(); try encrypted.finish(); try lease.check()
                outputs[domain.id] = output
                completed += 1; progress(completed, total)
            }
            guard let result = outputs["root"] else { throw Failure.invalidPlan }
            for (id, url) in outputs where id != "root" { try FileManager.default.removeItem(at: url) }
            try lease.check()
            return result
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    static func availableCapacity(_ url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: url.path)
        guard let value = attrs[.systemFreeSize] as? NSNumber else { throw Failure.lowSpace }
        return value.int64Value
    }
}
