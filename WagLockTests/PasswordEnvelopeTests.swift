import XCTest
import CryptoKit
@testable import WagLock

final class PasswordEnvelopeTests: XCTestCase {
    func testCandidatePreservesExactPasswordBytesAndBindsPurpose() throws {
        let password = "PUBLIC-test *._+ é🔑\0end"
        let plain = Data("PUBLIC random-data-key fixture".utf8)
        let wrapped = try PasswordEnvelope.seal(plain, password: password, context: "owner:public-test")
        XCTAssertEqual(try PasswordEnvelope.open(wrapped, password: password, context: "owner:public-test"), plain)
        XCTAssertThrowsError(try PasswordEnvelope.open(wrapped, password: password + "x", context: "owner:public-test"))
        XCTAssertThrowsError(try PasswordEnvelope.open(wrapped, password: password, context: "album:public-test"))
        for offset in [0, 4, 5, 8, 9, 24, 25, wrapped.count - 1] {
            var tampered = wrapped; tampered[offset] ^= 1
            XCTAssertThrowsError(try PasswordEnvelope.open(tampered, password: password, context: "owner:public-test"))
        }
        for count in [0, 4, 9, 24, 25, wrapped.count - 1] {
            XCTAssertThrowsError(try PasswordEnvelope.open(Data(wrapped.prefix(count)), password: password, context: "owner:public-test"))
        }
    }

    func testIndependentPythonOpenSSL600000RoundFixture() throws {
        // hashlib.pbkdf2_hmac('sha256', password.encode(), bytes(range(16)), 600000).
        let password = "PUBLIC independent *._é\0password"
        let keyHex = "dfbd3a4953da241e587767a478cfbbb0c1fd091a749177544ae63b68a5035d62"
        let keyBytes = stride(from: 0, to: keyHex.count, by: 2).map { offset -> UInt8 in
            let start = keyHex.index(keyHex.startIndex, offsetBy: offset)
            return UInt8(keyHex[start..<keyHex.index(start, offsetBy: 2)], radix: 16)!
        }
        let header = Data([87, 76, 80, 69, 1, 0, 9, 39, 192]) + Data(0..<16)
        let plain = Data("PUBLIC independent fixture".utf8)
        let nonce = try AES.GCM.Nonce(data: Data(0..<12))
        let box = try AES.GCM.seal(plain, using: SymmetricKey(data: keyBytes), nonce: nonce,
                                   authenticating: header + Data("owner:fixture".utf8))
        let wrapped = header + (try XCTUnwrap(box.combined))
        XCTAssertEqual(try PasswordEnvelope.open(wrapped, password: password, context: "owner:fixture"), plain)
    }

    func testCandidateReadsLegacyWithoutChangingBytesAndRejectsUnknownParameters() throws {
        let password = "PUBLIC legacy wrapper password"
        let plain = Data("PUBLIC legacy payload".utf8)
        let legacy = try EncryptionService.shared.encrypt(data: plain, password: password)
        XCTAssertEqual(try PasswordEnvelope.open(legacy, password: password, context: "owner:test"), plain)
        XCTAssertEqual(try EncryptionService.shared.decrypt(encryptedData: legacy, password: password), plain)
        XCTAssertThrowsError(try PasswordEnvelope.open(legacy, password: "wrong", context: "owner:test"))
        var newer = try PasswordEnvelope.seal(plain, password: password, context: "owner:test")
        newer[5] = 255
        XCTAssertThrowsError(try PasswordEnvelope.open(newer, password: password, context: "owner:test"))
        XCTAssertThrowsError(try PasswordEnvelope.seal(plain, password: "", context: "owner:test"))
    }
}
