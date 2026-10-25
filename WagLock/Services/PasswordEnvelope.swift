import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Versioned human-password wrapping; legacy native media formats remain unchanged.
nonisolated enum PasswordEnvelope {
    private static let magic = Data("WLPE".utf8)
    private static let rounds: UInt32 = 600_000
    private static let prefix = Data([87, 76, 80, 69, 1, 0, 9, 39, 192])
    private static let headerSize = 25
    enum Failure: Error { case invalidEnvelope, derivation, random }

    static func needsUpgrade(_ data: Data) -> Bool { !data.starts(with: prefix) }

    static func seal(_ plaintext: Data, password: String, context: String) throws -> Data {
        guard !password.isEmpty, plaintext.count <= 65_536 else { throw Failure.invalidEnvelope }
        var salt = Data(count: 16)
        guard salt.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }) == errSecSuccess else { throw Failure.random }
        let header = prefix + salt
        let key = try derive(password, salt: salt)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: header + Data(context.utf8))
        guard let combined = box.combined else { throw Failure.invalidEnvelope }
        return header + combined
    }

    static func open(_ data: Data, password: String, context: String) throws -> Data {
        guard data.starts(with: magic) else {
            return try EncryptionService.shared.decrypt(encryptedData: data, password: password)
        }
        guard data.count >= headerSize + 28, data.count <= headerSize + 28 + 65_536,
              data.starts(with: prefix) else { throw Failure.invalidEnvelope }
        let header = Data(data.prefix(headerSize))
        let key = try derive(password, salt: Data(header.suffix(16)))
        let box = try AES.GCM.SealedBox(combined: Data(data.dropFirst(headerSize)))
        return try AES.GCM.open(box, using: key, authenticating: header + Data(context.utf8))
    }

    /// Equal KDF work for a missing optional login credential; no verifier or key is stored.
    static func performDummyVerification(_ password: String) throws {
        _ = try derive(password, salt: Data(repeating: 0, count: 16))
    }

    private static func derive(_ password: String, salt: Data) throws -> SymmetricKey {
        var input = Data(password.utf8), output = Data(count: 32)
        defer { input.resetBytes(in: 0..<input.count); output.resetBytes(in: 0..<output.count) }
        let status = output.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { saltBytes in
                input.withUnsafeBytes { bytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), bytes.baseAddress?.assumingMemoryBound(to: Int8.self), input.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, out.baseAddress?.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.derivation }
        return SymmetricKey(data: output)
    }
}
