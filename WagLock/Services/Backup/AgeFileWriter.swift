import CryptoKit
import Darwin
import Foundation
import Security

/// Standard age v1 encryption only. No native-store format change or imported-file parser.
nonisolated final class AgeFileWriter {
    enum Failure: Error { case invalidCredential, invalidState, random, kdf, io, limit }
    enum Credential: Sendable { case password(String), recipient(String) }
    private static let kdfLock = NSLock()
    private let handle: FileHandle
    private let key: SymmetricKey
    private let check: @Sendable () throws -> Void
    private var buffer = Data()
    private var counter: UInt64 = 0
    private var finished = false
    private(set) var bytesWritten: Int64 = 0

    init(to url: URL, credential: Credential, check: @escaping @Sendable () throws -> Void = {}) throws {
        self.check = check
        try check()
        let fileKey = try Self.random(16)
        let wrapping: SymmetricKey
        let stanza: String
        switch credential {
        case .password(let password):
            guard !password.isEmpty, password.utf8.count <= 16384 else { throw Failure.invalidCredential }
            let salt = try Self.random(16)
            wrapping = SymmetricKey(data: try Self.scrypt(password: Data(password.utf8),
                salt: Data("age-encryption.org/v1/scrypt".utf8) + salt, n: 1 << 18, r: 8, p: 1, length: 32))
            stanza = "-> scrypt \(Self.b64(salt)) 18\n"
        case .recipient(let text):
            let recipient = try Self.decodeRecipient(text)
            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            let share = ephemeral.publicKey.rawRepresentation
            let shared = try ephemeral.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipient))
            wrapping = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: share + recipient,
                sharedInfo: Data("age-encryption.org/v1/X25519".utf8), outputByteCount: 32)
            stanza = "-> X25519 \(Self.b64(share))\n"
        }
        try check()
        let wrapped = try Self.seal(fileKey, key: wrapping, nonce: Data(count: 12))
        let unsigned = Data(("age-encryption.org/v1\n" + stanza + Self.b64(wrapped) + "\n---").utf8)
        let headerKey = Self.hkdf(fileKey, salt: Data(), info: "header")
        let mac = Data(HMAC<SHA256>.authenticationCode(for: unsigned, using: headerKey))
        let nonce = try Self.random(16)
        key = Self.hkdf(fileKey, salt: nonce, info: "payload")
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure.io }
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            #endif
            try handle.write(contentsOf: unsigned + Data((" " + Self.b64(mac) + "\n").utf8) + nonce)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw Failure.io
        }
    }

    func write(_ data: Data) throws {
        guard !finished else { throw Failure.invalidState }
        var offset = 0
        while offset < data.count {
            try check()
            if buffer.count == 65536 { try flush(final: false) }
            let count = min(65536 - buffer.count, data.count - offset)
            buffer.append(data.subdata(in: offset..<(offset + count)))
            offset += count
        }
    }

    func finish() throws {
        guard !finished else { throw Failure.invalidState }
        try check()
        try flush(final: true)
        try handle.synchronize()
        try handle.close()
        finished = true
    }

    private func flush(final: Bool) throws {
        try check()
        guard counter < UInt64.max else { throw Failure.limit }
        var nonce = Data(count: 12)
        for index in 0..<8 { nonce[10 - index] = UInt8(truncatingIfNeeded: counter >> (8 * index)) }
        nonce[11] = final ? 1 : 0
        let encrypted = try Self.seal(buffer, key: key, nonce: nonce)
        try handle.write(contentsOf: encrypted)
        bytesWritten += Int64(encrypted.count)
        buffer.removeAll(keepingCapacity: true)
        counter += 1
    }

    static func scrypt(password: Data, salt: Data, n: UInt64, r: UInt32, p: UInt32, length: Int) throws -> Data {
        guard (1...64).contains(length) else { throw Failure.kdf }
        kdfLock.lock(); defer { kdfLock.unlock() }
        var result = Data(count: length)
        let status = password.withUnsafeBytes { pw in salt.withUnsafeBytes { salt in result.withUnsafeMutableBytes { output in
            waglock_age_scrypt(pw.bindMemory(to: UInt8.self).baseAddress, pw.count,
                salt.bindMemory(to: UInt8.self).baseAddress, salt.count, n, r, p,
                output.bindMemory(to: UInt8.self).baseAddress, output.count)
        } } }
        guard status == 0 else { throw Failure.kdf }
        return result
    }

    private static func seal(_ data: Data, key: SymmetricKey, nonce: Data) throws -> Data {
        let box = try ChaChaPoly.seal(data, using: key, nonce: ChaChaPoly.Nonce(data: nonce))
        return box.ciphertext + box.tag
    }
    private static func hkdf(_ data: Data, salt: Data, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: data), salt: salt,
            info: Data(info.utf8), outputByteCount: 32)
    }
    private static func b64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "=", with: "") }
    private static func random(_ count: Int) throws -> Data {
        var result = Data(count: count)
        let status = result.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw Failure.random }
        return result
    }

    static func decodeRecipient(_ value: String) throws -> Data {
        guard value.utf8.count == 62, value == value.lowercased() || value == value.uppercased() else { throw Failure.invalidCredential }
        let text = value.lowercased()
        guard text.hasPrefix("age1") else { throw Failure.invalidCredential }
        let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l".utf8)
        let digits = try text.utf8.dropFirst(4).map { byte -> UInt8 in
            guard let index = alphabet.firstIndex(of: byte) else { throw Failure.invalidCredential }
            return UInt8(index)
        }
        var polymod: UInt32 = 1
        let hrp = Array("age".utf8)
        for value in hrp.map({ $0 >> 5 }) + [0] + hrp.map({ $0 & 31 }) + digits {
            let top = polymod >> 25
            polymod = ((polymod & 0x1ffffff) << 5) ^ UInt32(value)
            for (index, generator) in [UInt32(0x3b6a57b2), 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3].enumerated() {
                if ((top >> index) & 1) != 0 { polymod ^= generator }
            }
        }
        guard polymod == 1 else { throw Failure.invalidCredential }
        var accumulator: UInt32 = 0, bits = 0
        var bytes = Data()
        for digit in digits.dropLast(6) {
            accumulator = ((accumulator << 5) | UInt32(digit)) & 0xffff
            bits += 5
            if bits >= 8 { bits -= 8; bytes.append(UInt8(truncatingIfNeeded: accumulator >> bits)) }
        }
        guard bytes.count == 32, bits < 5, (accumulator & ((1 << bits) - 1)) == 0 else { throw Failure.invalidCredential }
        return bytes
    }
}
