import CryptoKit
import XCTest
@testable import WagLock

/// The vector is a disposable PUBLIC test key generated with rage (pyrage) on 2026-11-09.
final class AgeRecoveryKeyTests: XCTestCase {
    private let raw = Data((0..<32).map { index -> UInt8 in
        let hex = Array("1b137545565ccf450b078f717fde98fd35cf4ebca2c4ea06ecbe158bde959362")
        return UInt8(String(hex[index * 2..<index * 2 + 2]), radix: 16)!
    })

    func testEncodingMatchesTheReferenceAgeImplementation() throws {
        let key = AgeRecoveryKey(privateKey: try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw))
        XCTAssertEqual(key.identity, "AGE-SECRET-KEY-1RVFH232KTN852ZC83ACHLH5CL56U7N4U5TZW5PHVHC2CHH54JD3QZQGP34")
        XCTAssertEqual(key.recipient, "age1jypzkasph0kxgzd2jqa32quw8525xnzgap3n9a704kgvvdwdrqes9q5mt5")
        XCTAssertEqual(try AgeFileWriter.decodeRecipient(key.recipient), try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw).publicKey.rawRepresentation)
        XCTAssertEqual(key.groupedIdentity.joined(), String(key.identity.dropFirst("AGE-SECRET-KEY-1".count)))
        XCTAssertTrue(key.identityFileText.contains("\n" + key.identity + "\n"))
    }

    func testGeneratedKeysAreFreshAndAcceptedAsRecipients() throws {
        let first = AgeRecoveryKey.generate(), second = AgeRecoveryKey.generate()
        XCTAssertNotEqual(first.identity, second.identity)
        XCTAssertEqual(try AgeFileWriter.decodeRecipient(first.recipient).count, 32)
    }
}
