import CryptoKit
import Foundation

/// Immutable committed expectations plus owned pending writes for one mounted session.
nonisolated final class CiphertextBindings: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var expected: [String: Data]
    private var pending: [String: Data] = [:]
    init(_ expected: [String: Data]) { self.expected = expected }
    func digest(_ name: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard active, let digest = expected[name] else { throw EncryptionError.dataCorrupted }
        return digest
    }
    func register(_ name: String, digest: Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard active, digest.count == 32, expected[name] == nil else { throw EncryptionError.dataCorrupted }
        expected[name] = digest; pending[name] = digest
    }
    func snapshotPending() throws -> [String: Data] {
        lock.lock(); defer { lock.unlock() }
        guard active else { throw EncryptionError.dataCorrupted }; return pending
    }
    func didCommit(_ values: [String: Data]) {
        lock.lock(); defer { lock.unlock() }
        for (name, digest) in values where pending[name] == digest { pending.removeValue(forKey: name) }
    }
    func revoke() { lock.lock(); active = false; expected.removeAll(); pending.removeAll(); lock.unlock() }
}
