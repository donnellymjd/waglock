import CryptoKit
import Foundation

/// A standard age X25519 key pair for recovery-key backups. The public recipient
/// (`age1…`) encrypts the backup; the identity (`AGE-SECRET-KEY-1…`) is shown to the
/// person once and never stored, copied to the clipboard or logged by WagLock.
/// Both strings are Bech32 (BIP-173) as the age specification requires, so the
/// official `age -d -i key.txt` can decrypt without WagLock.
nonisolated struct AgeRecoveryKey: Sendable {
    let recipient: String
    let identity: String

    static func generate() -> AgeRecoveryKey { AgeRecoveryKey(privateKey: Curve25519.KeyAgreement.PrivateKey()) }

    init(privateKey key: Curve25519.KeyAgreement.PrivateKey) {
        recipient = Self.bech32Encode(hrp: "age", data: key.publicKey.rawRepresentation)
        identity = Self.bech32Encode(hrp: "age-secret-key-", data: key.rawRepresentation).uppercased()
    }

    /// The identity in groups of four for reading aloud or copying by hand.
    var groupedIdentity: [String] {
        let body = Array(identity.dropFirst("AGE-SECRET-KEY-1".count))
        return stride(from: 0, to: body.count, by: 4).map { String(body[$0..<min($0 + 4, body.count)]) }
    }

    /// The text written by Print / Save to Files: the standard age identity-file layout.
    var identityFileText: String {
        "# WagLock backup recovery key. Anyone with this key can open backups made with it.\n"
            + "# public key: \(recipient)\n\(identity)\n"
    }

    // MARK: Bech32 (BIP-173), lower-case output

    private static let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let generators: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

    static func bech32Encode(hrp: String, data: Data) -> String {
        let values = convertTo5Bit(data)
        let hrpBytes = Array(hrp.utf8)
        let expanded = hrpBytes.map { $0 >> 5 } + [0] + hrpBytes.map { $0 & 31 }
        let polymod = self.polymod(expanded + values + [0, 0, 0, 0, 0, 0]) ^ 1
        let checksum = (0..<6).map { UInt8((polymod >> (5 * (5 - UInt32($0)))) & 31) }
        return hrp + "1" + String((values + checksum).map { alphabet[Int($0)] })
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var checksum: UInt32 = 1
        for value in values {
            let top = checksum >> 25
            checksum = ((checksum & 0x1ffffff) << 5) ^ UInt32(value)
            for (index, generator) in generators.enumerated() where ((top >> index) & 1) != 0 {
                checksum ^= generator
            }
        }
        return checksum
    }

    private static func convertTo5Bit(_ data: Data) -> [UInt8] {
        var accumulator: UInt32 = 0, bits = 0
        var result: [UInt8] = []
        for byte in data {
            accumulator = (accumulator << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                result.append(UInt8((accumulator >> UInt32(bits)) & 31))
            }
            accumulator &= (1 << UInt32(bits)) - 1
        }
        if bits > 0 { result.append(UInt8((accumulator << UInt32(5 - bits)) & 31)) }
        return result
    }
}
