import CryptoKit
import Foundation
import XCTest
@testable import WagLock

final class PortableBackupTests: XCTestCase {
    func testExportFilenamePreservesNamesAndRejectsUnsafePaths() {
        for (input, expected) in [("Holiday backup", "Holiday backup.tar.age"), ("café 家族", "café 家族.tar.age"),
            ("Backup.tar.age", "Backup.tar.age"), ("Backup.AGE", "Backup.tar.age"), ("Backup.tar", "Backup.tar.age")] {
            XCTAssertEqual(PortableBackupSession.exportFilename(input), expected)
        }
        for invalid in ["", "   ", ".", "..", "../other", "a/b", "a\\b", "a:b", "a\nother", String(repeating: "x", count: 201)] {
            XCTAssertNil(PortableBackupSession.exportFilename(invalid))
        }
    }

    func testScryptRFC7914AndUnsafeParametersFailClosed() throws {
        let derived = try AgeFileWriter.scrypt(password: Data(), salt: Data(), n: 16, r: 1, p: 1, length: 64)
        XCTAssertEqual(derived.map { String(format: "%02x", $0) }.joined(), "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906")
        for n: UInt64 in [0, 1, 3, 1 << 19] {
            XCTAssertThrowsError(try AgeFileWriter.scrypt(password: Data("fixture".utf8), salt: Data(), n: n, r: 8, p: 1, length: 32))
        }
        XCTAssertThrowsError(try AgeFileWriter.scrypt(password: Data(), salt: Data(), n: 16, r: 0, p: 1, length: 32))
        XCTAssertThrowsError(try AgeFileWriter.scrypt(password: Data(), salt: Data(), n: 16, r: 1, p: 0, length: 32))
    }

    func testRecipientChecksumCaseAndInvalidKeys() throws {
        let key = "age1zvkyg2lqzraa2lnjvqej32nkuu0ues2s82hzrye869xeexvn73equnujwj"
        XCTAssertEqual(try AgeFileWriter.decodeRecipient(key).count, 32)
        XCTAssertEqual(try AgeFileWriter.decodeRecipient(key), try AgeFileWriter.decodeRecipient(key.uppercased()))
        for bad in [key + " ", key.dropLast() + "x", "Age" + key.dropFirst(3), "age1", "ssh-ed25519 fixture"] {
            XCTAssertThrowsError(try AgeFileWriter.decodeRecipient(bad))
        }
    }

    func testExistingOutputSurvivesAndCancelledWriterCannotFinish() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("keep.age")
        try Data("keep".utf8).write(to: output)
        let recipient = "age1zvkyg2lqzraa2lnjvqej32nkuu0ues2s82hzrye869xeexvn73equnujwj"
        XCTAssertThrowsError(try AgeFileWriter(to: output, credential: .recipient(recipient)))
        XCTAssertEqual(try Data(contentsOf: output), Data("keep".utf8))
        let lease = BackupLease()
        let writer = try AgeFileWriter(to: root.appendingPathComponent("cancel.age"), credential: .recipient(recipient), check: { try lease.check() })
        try writer.write(Data(repeating: 7, count: 65537))
        lease.cancel()
        XCTAssertThrowsError(try writer.finish())
    }

    func testFailureLowSpaceAndCancellationNeverRemoveSourcesOrUnownedDirectories() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let original = try EncryptionService.shared.encrypt(data: Data("fixture".utf8), password: "correct")
        try original.write(to: source)
        let recipient = AgeFileWriter.Credential.recipient("age1zvkyg2lqzraa2lnjvqej32nkuu0ues2s82hzrye869xeexvn73equnujwj")
        func plan(_ key: String) -> BackupWorkPlan {
            .init(domains: [.init(id: "root", children: [], metadata: Data("{}".utf8),
                assets: [.init(id: UUID(), source: source, sourceBytes: Int64(original.count), key: key, thumbnail: nil)], credential: recipient)], requiredBytes: 1024)
        }
        let output = base.appendingPathComponent("job")
        XCTAssertThrowsError(try BackupArchiveBuilder.build(plan("correct"), directory: output, lease: BackupLease(), capacity: { _ in 0 }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertThrowsError(try BackupArchiveBuilder.build(plan("wrong"), directory: output, lease: BackupLease()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let lease = BackupLease()
        XCTAssertThrowsError(try BackupArchiveBuilder.build(plan("correct"), directory: output, lease: lease, progress: { _, _ in lease.cancel() }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let keep = output.appendingPathComponent("keep"); try Data("unowned".utf8).write(to: keep)
        let unowned = BackupLease()
        XCTAssertThrowsError(try BackupArchiveBuilder.build(plan("correct"), directory: output, lease: unowned))
        XCTAssertNil(unowned.ownedDirectory)
        XCTAssertEqual(try Data(contentsOf: keep), Data("unowned".utf8))
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testBackupRejectsValidSameKeyCiphertextWhenBoundDigestDoesNotMatch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bound-backup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("cipher")
        let original = try EncryptionService.shared.encrypt(data: Data("PUBLIC original".utf8), password: "PUBLIC key")
        let substituted = try EncryptionService.shared.encrypt(data: Data("PUBLIC different".utf8), password: "PUBLIC key")
        try substituted.write(to: source)
        let asset = BackupWorkPlan.Asset(id: UUID(), source: source, sourceBytes: Int64(substituted.count), key: "PUBLIC key",
            thumbnail: nil, ciphertextDigest: Data(SHA256.hash(data: original)))
        let plan = BackupWorkPlan(domains: [.init(id: "root", children: [], metadata: Data("{}".utf8), assets: [asset],
            credential: .recipient("age1zvkyg2lqzraa2lnjvqej32nkuu0ues2s82hzrye869xeexvn73equnujwj"))], requiredBytes: 1024)
        let output = root.appendingPathComponent("owned-job")
        XCTAssertThrowsError(try BackupArchiveBuilder.build(plan, directory: output, lease: BackupLease()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: source), substituted)
    }

    func testTarRecordIsAcceptedByStandardHeaderLayoutAndRejectsUnsafeNames() throws {
        var data = Data()
        let tar = BackupTarWriter(sink: { data.append($0) }, check: {})
        let payload = Data((0..<65573).map { UInt8($0 % 251) })
        let entry = try tar.add(payload, path: "metadata.json")
        XCTAssertEqual(entry.bytes, Int64(payload.count))
        XCTAssertEqual(entry.sha256, SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(data.subdata(in: 257..<263), Data("ustar\0".utf8))
        XCTAssertThrowsError(try tar.add(Data(), path: "../escape"))
        XCTAssertThrowsError(try tar.add(Data(), path: "metadata.json"))
        try tar.finish()
        XCTAssertEqual(data.count % 512, 0)
        XCTAssertEqual(data.suffix(1024), Data(count: 1024))
    }
}
