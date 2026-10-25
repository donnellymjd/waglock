import CryptoKit
import Darwin
import Foundation

@MainActor
protocol LibraryCommitAnchor: AnyObject {
    func loadCommitAnchor() throws -> Data?
    func saveCommitAnchor(_ data: Data, replacing expected: Data?) throws
}

struct LibraryCommitStamp: Codable, Equatable {
    let revision: UInt64
    let digest: Data
}

/// Device-only trust state. Filesystem rollback cannot roll this state back.
@MainActor
final class LibraryCommitProtection {
    nonisolated deinit {}
    enum Failure: Error { case rollback, unavailable, recoveryRequired }
    struct Pending: Codable {
        let from: LibraryCommitStamp
        let to: LibraryCommitStamp
        let journalHash: Data
    }
    struct State: Codable { let version: Int; let committed: LibraryCommitStamp; let pending: Pending? }
    let journalURL: URL
    private let anchor: any LibraryCommitAnchor
    init(anchor: any LibraryCommitAnchor, journalURL: URL) {
        self.anchor = anchor; self.journalURL = journalURL
    }
    func state() throws -> State? {
        guard let data = try anchor.loadCommitAnchor() else { return nil }
        guard data.count <= 4096 else { throw Failure.unavailable }
        let value = try JSONDecoder().decode(State.self, from: data)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(value) == data else { throw Failure.unavailable }
        guard value.version == 1, value.committed.digest.count == 32 else { throw Failure.unavailable }
        if let pending = value.pending {
            guard pending.from == value.committed, pending.from.revision < UInt64.max,
                  pending.to.revision == pending.from.revision + 1,
                  pending.to.digest.count == 32, pending.journalHash.count == 32 else { throw Failure.unavailable }
        }
        return value
    }
    private func save(_ state: State) throws {
        let old = try anchor.loadCommitAnchor()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try anchor.saveCommitAnchor(encoder.encode(state), replacing: old)
    }
    func enroll(_ stamp: LibraryCommitStamp) throws {
        guard try state() == nil else { throw Failure.unavailable }
        try save(State(version: 1, committed: stamp, pending: nil))
    }
    func prepare(from: LibraryCommitStamp, to: LibraryCommitStamp, journal: Data) throws {
        guard let current = try state(), current.pending == nil, current.committed == from else { throw Failure.rollback }
        // Exclusively own this exact file; never overwrite or remove an unknown file.
        let fd = Darwin.open(journalURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure.recoveryRequired }
        var complete = false
        defer { Darwin.close(fd); if !complete { try? FileManager.default.removeItem(at: journalURL) } }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: journalURL.path)
        try journal.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw Failure.unavailable }; offset += count
            }
        }
        guard fsync(fd) == 0 else { throw Failure.unavailable }
        try syncDirectory()
        complete = true // Preserve the complete recovery journal even if the Keychain result is uncertain.
        let pending = Pending(from: from, to: to, journalHash: Data(SHA256.hash(data: journal)))
        try save(State(version: 1, committed: from, pending: pending))
    }
    func finish(_ stamp: LibraryCommitStamp) throws {
        guard let current = try state(), current.pending?.to == stamp else { throw Failure.rollback }
        if FileManager.default.fileExists(atPath: journalURL.path) {
            let bytes = try readJournal()
            guard Data(SHA256.hash(data: bytes)) == current.pending?.journalHash else { throw Failure.recoveryRequired }
        }
        try save(State(version: 1, committed: stamp, pending: nil))
        // Source association was verified before the anchor update; only remove those same bytes.
        if let hash = current.pending?.journalHash { try removeJournal(matching: hash) }
    }
    func readJournal() throws -> Data {
        try FreshEncryptedLibrary.safe(journalURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: journalURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= 128 * 1024 * 1024 else { throw Failure.recoveryRequired }
        return try Data(contentsOf: journalURL)
    }
    func removeJournal(matching digest: Data) throws {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
        guard Data(SHA256.hash(data: try readJournal())) == digest else { throw Failure.recoveryRequired }
        try FileManager.default.removeItem(at: journalURL); try syncDirectory()
    }
    private func syncDirectory() throws {
        let fd = Darwin.open(journalURL.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.unavailable }; defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw Failure.unavailable }
    }
}
