import CryptoKit
import Foundation
import Security

/// Which on-device library a passcode opens. Every library created through the
/// slot table is `.independent`; `.legacyOwner` exists only for an install that
/// enrolled its pre-slot library, so that library keeps its original roots and keys.
nonisolated enum LibraryReference: Codable, Hashable, Sendable {
    case legacyOwner
    case independent(UUID)

    var independentID: UUID? {
        if case .independent(let id) = self { return id }
        return nil
    }

    /// Device-only Face ID ownership marker. "primary" is the pre-slot spelling and is
    /// kept only so existing enrollments keep resolving; it is never shown in the UI.
    var biometricOwnerMarker: String { independentID?.uuidString ?? "primary" }
}

/// Encrypted contents of one used slot. Plaintext is padded to a fixed size.
nonisolated struct LibrarySlotPayload: Codable, Equatable, Sendable {
    let version: Int
    let library: LibraryReference
    let secret: String
    /// While set and in the future (by the high-water clock), this slot rejects its passcode.
    var timeLockUntil: Date?

    init(library: LibraryReference, secret: String, timeLockUntil: Date? = nil) {
        self.version = 1
        self.library = library
        self.secret = secret
        self.timeLockUntil = timeLockUntil
    }
}

nonisolated struct LibrarySlotMatch: Equatable, Sendable {
    let index: Int
    let payload: LibrarySlotPayload
}

nonisolated enum LibrarySlotFailure: Error, Equatable {
    /// One undifferentiated rejection for collisions, weak passcodes, a full table,
    /// time-locked passcodes and wrong passcodes.
    case rejected
    /// Keychain unavailable or a write could not be confirmed. Never a reset signal.
    case unavailable
    /// The record exists but is malformed. Never a reset signal either.
    case corrupt
}

/// Fixed-size header. All of it is authenticated as AEAD associated data, so a changed
/// parameter makes every slot fail instead of silently weakening derivation.
nonisolated struct LibrarySlotHeader: Equatable, Sendable {
    static let magic = Data("WLKS".utf8)
    static let size = 41
    let logN: UInt8
    let r: UInt8
    let p: UInt8
    let salt: Data

    init(logN: UInt8, r: UInt8 = 8, p: UInt8 = 1, salt: Data) {
        self.logN = logN; self.r = r; self.p = p; self.salt = salt
    }

    init(parsing record: Data) throws {
        guard record.count == LibrarySlotCrypto.recordSize, record.starts(with: Self.magic) else {
            throw LibrarySlotFailure.corrupt
        }
        let bytes = [UInt8](record.subdata(in: 0..<Self.size))
        guard bytes[4] == 1, bytes[5] == 1, (10...20).contains(bytes[6]),
              (1...16).contains(bytes[7]), bytes[8] == 1 else { throw LibrarySlotFailure.corrupt }
        logN = bytes[6]; r = bytes[7]; p = bytes[8]
        salt = Data(bytes[9..<Self.size])
    }

    /// magic(4) · format version(1) · KDF id 1 = scrypt(1) · log2 N(1) · r(1) · p(1) · salt(32)
    var bytes: Data { Self.magic + Data([1, 1, logN, r, p]) + salt }
}

/// Pure crypto for the slot table. Design sketch pending the crypto reviewer; see
/// docs/portable-vault/library-slots.md. Parameters are versioned in the header.
nonisolated enum LibrarySlotCrypto {
    static let slotCount = 16
    static let payloadSize = 384
    static let slotSize = 12 + payloadSize + 16
    static let recordSize = LibrarySlotHeader.size + slotCount * slotSize
    /// scrypt N = 2^16, r = 8, p = 1 (64 MiB). Tests pass a smaller value through the header.
    static let productionLogN: UInt8 = 16

    static func random(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        guard count == 0 || bytes.withUnsafeMutableBytes({
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }) == errSecSuccess else { throw LibrarySlotFailure.unavailable }
        return bytes
    }

    static func randomIndex(from candidates: [Int]) throws -> Int? {
        guard !candidates.isEmpty else { return nil }
        let value = try random(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return candidates[Int(value % UInt32(candidates.count))]
    }

    /// One memory-hard derivation per passcode, shared by all 16 trial unwraps.
    static func deriveKey(passcode: String, header: LibrarySlotHeader, namespace: String) throws -> SymmetricKey {
        var material: Data
        do {
            material = try AgeFileWriter.scrypt(password: Data(passcode.utf8),
                salt: Data("waglock.library-slots.v1".utf8) + header.salt,
                n: UInt64(1) << UInt64(header.logN), r: UInt32(header.r), p: UInt32(header.p), length: 32)
        } catch { throw LibrarySlotFailure.unavailable }
        defer { material.resetBytes(in: 0..<material.count) }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: material), salt: header.bytes,
            info: Data(("waglock.slot-key:" + namespace).utf8), outputByteCount: 32)
    }

    static func associatedData(_ header: LibrarySlotHeader, index: Int, namespace: String) -> Data {
        header.bytes + Data([UInt8(index)]) + Data(namespace.utf8)
    }

    static func slot(_ record: Data, at index: Int) -> Data {
        let start = LibrarySlotHeader.size + index * slotSize
        return record.subdata(in: start..<(start + slotSize))
    }

    static func replacing(_ record: Data, slot: Data, at index: Int) throws -> Data {
        guard record.count == recordSize, slot.count == slotSize, (0..<slotCount).contains(index) else {
            throw LibrarySlotFailure.corrupt
        }
        let start = LibrarySlotHeader.size + index * slotSize
        var result = record
        result.replaceSubrange(start..<(start + slotSize), with: slot)
        return result
    }

    static func seal(_ payload: LibrarySlotPayload, key: SymmetricKey, header: LibrarySlotHeader,
                     index: Int, namespace: String) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var json = try encoder.encode(payload)
        defer { json.resetBytes(in: 0..<json.count) }
        guard json.count <= payloadSize - 2 else { throw LibrarySlotFailure.corrupt }
        var plaintext = Data([UInt8(json.count >> 8), UInt8(json.count & 0xff)]) + json
        plaintext += try random(payloadSize - plaintext.count)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: random(12)),
            authenticating: associatedData(header, index: index, namespace: namespace))
        guard let combined = box.combined, combined.count == slotSize else { throw LibrarySlotFailure.corrupt }
        return combined
    }

    static func open(_ slot: Data, key: SymmetricKey, header: LibrarySlotHeader,
                     index: Int, namespace: String) -> LibrarySlotPayload? {
        guard let box = try? AES.GCM.SealedBox(combined: slot),
              var plaintext = try? AES.GCM.open(box, using: key,
                authenticating: associatedData(header, index: index, namespace: namespace)) else { return nil }
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        guard plaintext.count == payloadSize else { return nil }
        let bytes = [UInt8](plaintext.prefix(2))
        let length = Int(bytes[0]) << 8 | Int(bytes[1])
        guard length > 0, length <= payloadSize - 2,
              let payload = try? JSONDecoder().decode(LibrarySlotPayload.self, from: plaintext.subdata(in: 2..<(2 + length))),
              payload.version == 1, !payload.secret.isEmpty else { return nil }
        return payload
    }

    /// Always attempts every slot, so the work done does not depend on which one matched.
    static func evaluate(passcode: String, record: Data, namespace: String) throws -> LibrarySlotMatch? {
        let header = try LibrarySlotHeader(parsing: record)
        let key = try deriveKey(passcode: passcode, header: header, namespace: namespace)
        var found: LibrarySlotMatch?
        for index in 0..<slotCount {
            let payload = open(slot(record, at: index), key: key, header: header, index: index, namespace: namespace)
            if found == nil, let payload { found = LibrarySlotMatch(index: index, payload: payload) }
        }
        return found
    }

    /// A fresh record: header plus 16 slots of random bytes, indistinguishable from sealed ones.
    static func emptyRecord(logN: UInt8) throws -> Data {
        let header = LibrarySlotHeader(logN: logN, salt: try random(32))
        return header.bytes + (try random(slotCount * slotSize))
    }
}

/// The one Keychain-held slot table for this install, plus its allocation map and
/// high-water clock. Every write is verified by read-back; failures never trigger
/// rollback or deletion of other slots.
@MainActor
final class LibrarySlotTable {
    nonisolated deinit {}
    static let tableAccount = "waglock.library-slots.v1"
    static let allocationAccount = "waglock.library-slot-allocation.v1"
    static let clockAccount = "waglock.library-clock.v1"

    let namespace: String
    private let storage: any KeychainStorage
    private let now: () -> Date
    private let logN: UInt8

    init(storage: any KeychainStorage, namespace: String, now: @escaping () -> Date = Date.init,
         logN: UInt8 = LibrarySlotCrypto.productionLogN) {
        self.storage = storage
        self.namespace = namespace
        self.now = now
        self.logN = logN
    }

    /// Checked absence only; an unavailable item is never treated as "no table".
    func record() throws -> Data? {
        do { return try storage.read(account: Self.tableAccount) }
        catch KeychainError.itemNotFound { return nil }
        catch { throw LibrarySlotFailure.unavailable }
    }

    func requireRecord() throws -> Data {
        guard let record = try record() else { throw LibrarySlotFailure.unavailable }
        _ = try LibrarySlotHeader(parsing: record)
        return record
    }

    func exists() throws -> Bool { try record() != nil }

    /// Synchronous evaluation for callers that already run off the UI path (tests, read-back).
    func evaluate(passcode: String) throws -> LibrarySlotMatch? {
        try LibrarySlotCrypto.evaluate(passcode: passcode, record: requireRecord(), namespace: namespace)
    }

    /// Creates the table with its first library. Fails if any table already exists.
    @discardableResult
    func initialize(passcode: String, payload: LibrarySlotPayload) throws -> Int {
        guard try record() == nil else { throw LibrarySlotFailure.unavailable }
        let empty = try LibrarySlotCrypto.emptyRecord(logN: logN)
        guard let index = try LibrarySlotCrypto.randomIndex(from: Array(0..<LibrarySlotCrypto.slotCount)) else {
            throw LibrarySlotFailure.unavailable
        }
        let header = try LibrarySlotHeader(parsing: empty)
        let key = try LibrarySlotCrypto.deriveKey(passcode: passcode, header: header, namespace: namespace)
        let sealed = try LibrarySlotCrypto.seal(payload, key: key, header: header, index: index, namespace: namespace)
        let full = try LibrarySlotCrypto.replacing(empty, slot: sealed, at: index)
        // Allocation first: a crash in between leaves a wasted random slot, never an
        // unallocated live slot that a later add could overwrite.
        try writeAllocation([index], createOnly: true)
        try write(Self.tableAccount, full, createOnly: true)
        return index
    }

    /// Adds a library in a random free slot. The caller has already run the collision check.
    @discardableResult
    func add(passcode: String, payload: LibrarySlotPayload) throws -> Int {
        let original = try requireRecord()
        var used = try allocation()
        let free = (0..<LibrarySlotCrypto.slotCount).filter { !used.contains($0) }
        guard let index = try LibrarySlotCrypto.randomIndex(from: free) else { throw LibrarySlotFailure.rejected }
        let header = try LibrarySlotHeader(parsing: original)
        let key = try LibrarySlotCrypto.deriveKey(passcode: passcode, header: header, namespace: namespace)
        let sealed = try LibrarySlotCrypto.seal(payload, key: key, header: header, index: index, namespace: namespace)
        used.insert(index)
        try writeAllocation(used, createOnly: false)
        guard try requireRecord() == original else { throw LibrarySlotFailure.unavailable }
        try write(Self.tableAccount, try LibrarySlotCrypto.replacing(original, slot: sealed, at: index), createOnly: false)
        return index
    }

    /// Rewrites one slot in place, only if the table is byte-identical to what the caller verified.
    func rewrite(index: Int, verifiedRecord: Data, passcode: String, payload: LibrarySlotPayload) throws {
        let header = try LibrarySlotHeader(parsing: verifiedRecord)
        let key = try LibrarySlotCrypto.deriveKey(passcode: passcode, header: header, namespace: namespace)
        let sealed = try LibrarySlotCrypto.seal(payload, key: key, header: header, index: index, namespace: namespace)
        guard try requireRecord() == verifiedRecord else { throw LibrarySlotFailure.unavailable }
        try write(Self.tableAccount, try LibrarySlotCrypto.replacing(verifiedRecord, slot: sealed, at: index), createOnly: false)
    }

    /// Crypto-erase: overwrite the slot with fresh random bytes, then release its allocation.
    func destroy(index: Int, verifiedRecord: Data) throws {
        guard try requireRecord() == verifiedRecord else { throw LibrarySlotFailure.unavailable }
        let replacement = try LibrarySlotCrypto.replacing(verifiedRecord,
            slot: try LibrarySlotCrypto.random(LibrarySlotCrypto.slotSize), at: index)
        try write(Self.tableAccount, replacement, createOnly: false)
        var used = try allocation()
        used.remove(index)
        try writeAllocation(used, createOnly: false)
    }

    // MARK: Allocation map

    /// Version byte plus a 16-bit used mask. This is the only record of how many slots
    /// are used. It is never shown in the UI; see the reviewer note in library-slots.md.
    func allocation() throws -> Set<Int> {
        let data: Data
        do { data = try storage.read(account: Self.allocationAccount) }
        catch KeychainError.itemNotFound { throw LibrarySlotFailure.unavailable }
        catch { throw LibrarySlotFailure.unavailable }
        let bytes = [UInt8](data)
        guard bytes.count == 3, bytes[0] == 1 else { throw LibrarySlotFailure.corrupt }
        let mask = UInt16(bytes[1]) << 8 | UInt16(bytes[2])
        return Set((0..<LibrarySlotCrypto.slotCount).filter { mask & (1 << UInt16($0)) != 0 })
    }

    private func writeAllocation(_ used: Set<Int>, createOnly: Bool) throws {
        let mask = used.reduce(UInt16(0)) { $0 | (1 << UInt16($1)) }
        try write(Self.allocationAccount, Data([1, UInt8(mask >> 8), UInt8(mask & 0xff)]), createOnly: createOnly)
    }

    // MARK: High-water clock

    /// The latest wall time this install has observed. Rolling the clock back cannot shorten
    /// a time lock; rolling it forward can (documented reviewer item).
    func trustedNow() throws -> Date {
        let current = now()
        var highWater: Date?
        do {
            let data = try storage.read(account: Self.clockAccount)
            guard data.count == 8 else { throw LibrarySlotFailure.corrupt }
            let bits = data.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let value = Double(bitPattern: bits)
            guard value.isFinite else { throw LibrarySlotFailure.corrupt }
            highWater = Date(timeIntervalSince1970: value)
        } catch KeychainError.itemNotFound {
            highWater = nil
        } catch let failure as LibrarySlotFailure {
            throw failure
        } catch { throw LibrarySlotFailure.unavailable }
        if let highWater, highWater >= current { return highWater }
        let bits = current.timeIntervalSince1970.bitPattern
        let data = Data((0..<8).reversed().map { UInt8((bits >> (UInt64($0) * 8)) & 0xff) })
        try write(Self.clockAccount, data, createOnly: false)
        return current
    }

    private func write(_ account: String, _ data: Data, createOnly: Bool) throws {
        do { try storage.write(account: account, data: data, createOnly: createOnly) }
        catch { throw LibrarySlotFailure.unavailable }
        // An uncertain outcome is reported, never rolled back.
        guard (try? storage.read(account: account)) == data else { throw LibrarySlotFailure.unavailable }
    }
}
