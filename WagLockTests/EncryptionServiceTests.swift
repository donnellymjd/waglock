import Foundation
import CommonCrypto
import CryptoKit
import Testing

@testable import WagLock

struct EncryptionServiceTests {
    private let password = "integrity-fixture-password"
    private let crypto = EncryptionService.shared

    private func fixture(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func ciphertext(for data: Data, in directory: URL) throws -> Data {
        let source = directory.appendingPathComponent("source")
        let encrypted = directory.appendingPathComponent("encrypted")
        try data.write(to: source)
        try crypto.encryptFile(inputURL: source, to: encrypted, password: password, preferredChunkSize: 256 * 1024)
        return try Data(contentsOf: encrypted)
    }

    private func records(in data: Data) throws -> (Data, [Data]) {
        let headerSize = data[4] == 1 ? 24 : 28
        guard data.count >= headerSize else { throw EncryptionError.invalidData }
        var offset = headerSize
        var records: [Data] = []
        while offset < data.count {
            guard offset + 4 <= data.count else { throw EncryptionError.invalidData }
            let length = data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let recordSize = length == 0 && data[4] == 1 ? 4 : 4 + 12 + 16 + Int(length)
            guard offset + recordSize <= data.count else { throw EncryptionError.invalidData }
            records.append(data.subdata(in: offset..<(offset + recordSize)))
            offset += recordSize
        }
        return (Data(data.prefix(headerSize)), records)
    }

    private func expectRejected(_ data: Data, in directory: URL, password: String? = nil) throws {
        let input = directory.appendingPathComponent("tampered")
        let output = directory.appendingPathComponent("plaintext")
        try data.write(to: input)
        #expect(throws: (any Error).self) {
            try crypto.decryptFile(inputURL: input, to: output, password: password ?? self.password)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test
    func truncatedStreamNeverPublishesPartialPlaintext() throws {
        try fixture { directory in
            let data = try ciphertext(for: Data(repeating: 0x41, count: 300_000), in: directory)
            let (header, chunks) = try records(in: data)
            try expectRejected(chunks.dropLast().reduce(header, +), in: directory)
        }
    }

    @Test
    func chunkOrderChangesAreRejected() throws {
        try fixture { directory in
            let plain = Data(repeating: 0x41, count: 256 * 1024) + Data(repeating: 0x42, count: 256 * 1024)
            let data = try ciphertext(for: plain, in: directory)
            let (header, chunks) = try records(in: data)
            try expectRejected(header + chunks[1] + chunks[0] + chunks[2], in: directory)
        }
    }

    @Test
    func emptyStreamStillAuthenticatesThePassword() throws {
        try fixture { directory in
            let data = try ciphertext(for: Data(), in: directory)
            try expectRejected(data, in: directory, password: "wrong-password")
        }
    }

    @Test
    func roundTripsEmptyAndChunkBoundarySizes() throws {
        try fixture { directory in
            for count in [0, 1, 44, 262_143, 262_144, 262_145, 524_297] {
                let original = Data((0..<count).map { UInt8($0 % 251) })
                let data = try ciphertext(for: original, in: directory)
                #expect(data[4] == 2)
                let output = directory.appendingPathComponent("restored")
                try crypto.decryptFile(inputURL: directory.appendingPathComponent("encrypted"),
                                       to: output, password: password)
                #expect(try Data(contentsOf: output) == original)
            }
        }
    }

    @Test
    func rejectsDuplicateOmittedCorruptedAndTrailingRecords() throws {
        try fixture { directory in
            let data = try ciphertext(for: Data(repeating: 0x41, count: 300_000), in: directory)
            let (header, chunks) = try records(in: data)
            try expectRejected(header + chunks[0] + chunks[0] + chunks[1] + chunks[2], in: directory)
            try expectRejected(header + chunks[0] + chunks[2], in: directory)
            try expectRejected(header + Data(repeating: 0, count: 4), in: directory)
            try expectRejected(data + Data([0]), in: directory)
            var changed = data
            changed[header.count + 32] ^= 1
            try expectRejected(changed, in: directory)
            changed = data
            changed.replaceSubrange(header.count..<(header.count + 4), with: [255, 255, 255, 255])
            try expectRejected(changed, in: directory)
        }
    }

    @Test
    func authenticatesHeadersAndRejectsShortReads() throws {
        try fixture { directory in
            let data = try ciphertext(for: Data("small fixture".utf8), in: directory)
            for offset in [0, 4, 5, 6, 7, 8, 24] {
                var changed = data
                changed[offset] ^= 1
                try expectRejected(changed, in: directory)
            }
            for count in [0, 3, 4, 5, 7, 8, 23, 24, 27, 28, 30, data.count - 1] {
                try expectRejected(Data(data.prefix(count)), in: directory)
            }
        }
    }

    @Test
    func lateAuthenticationFailurePreservesExistingOutputAndRemovesStaging() throws {
        try fixture { directory in
            var data = try ciphertext(for: Data(repeating: 7, count: 300_000), in: directory)
            data[data.count - 1] ^= 1 // Fail only after writing authenticated data chunks to staging.
            let input = directory.appendingPathComponent("corrupted")
            let output = directory.appendingPathComponent("existing")
            let marker = Data("do not overwrite".utf8)
            try data.write(to: input)
            try marker.write(to: output)
            #expect(throws: (any Error).self) {
                try crypto.decryptFile(inputURL: input, to: output, password: password)
            }
            #expect(try Data(contentsOf: output) == marker)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix(".vaultito-stage-") }.isEmpty)
        }
    }

    @Test
    func failedPublicationDoesNotDestroyTheDestination() throws {
        try fixture { directory in
            let input = directory.appendingPathComponent("source")
            let destination = directory.appendingPathComponent("existing-directory")
            try Data("source bytes".utf8).write(to: input)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            let marker = destination.appendingPathComponent("keep")
            try Data("keep".utf8).write(to: marker)
            #expect(throws: (any Error).self) {
                try crypto.encryptFile(inputURL: input, to: destination, password: password)
            }
            #expect(try Data(contentsOf: marker) == Data("keep".utf8))
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix(".vaultito-stage-") }.isEmpty)
        }
    }

    @Test
    func sameFileInputAndOutputAreRejectedWithoutDataLoss() throws {
        try fixture { directory in
            let url = directory.appendingPathComponent("only-copy")
            let original = Data("the only original".utf8)
            try original.write(to: url)
            #expect(throws: (any Error).self) { try crypto.encryptFile(inputURL: url, to: url, password: password) }
            #expect(throws: (any Error).self) { try crypto.decryptFile(inputURL: url, to: url, password: password) }
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test
    func randomFailureOrInvalidRandomBytesNeverPublishesCiphertext() throws {
        try fixture { directory in
            let input = directory.appendingPathComponent("source")
            let output = directory.appendingPathComponent("existing")
            let original = Data("existing ciphertext".utf8)
            try Data("source".utf8).write(to: input)
            try original.write(to: output)
            for service in [EncryptionService(randomBytes: { _ in throw EncryptionError.randomGenerationFailed }),
                            EncryptionService(randomBytes: { _ in Data([0]) })] {
                #expect(throws: (any Error).self) { try service.encrypt(data: Data([1]), password: password) }
                #expect(throws: (any Error).self) {
                    try service.encryptFile(inputURL: input, to: output, password: password)
                }
                #expect(try Data(contentsOf: output) == original)
            }
        }
    }

    @Test
    func cancelledWriterLeavesNoOutputOrStaging() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source")
        let output = directory.appendingPathComponent("output")
        try Data(repeating: 1, count: 300_000).write(to: input)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try crypto.encryptFile(inputURL: input, to: output, password: password)
        }
        do { try await task.value; Issue.record("Cancelled encryption succeeded") }
        catch is CancellationError {} catch { Issue.record("Unexpected cancellation error: \(error)") }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".vaultito-stage-") }.isEmpty)
    }

    @Test
    func startupCleanupRemovesOnlyRecognizedStagingDirectories() throws {
        try fixture { directory in
            let abandoned = directory.appendingPathComponent(".vaultito-stage-" + UUID().uuidString)
            let unrelated = directory.appendingPathComponent(".vaultito-stage-not-a-uuid")
            try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: false)
            try Data("partial".utf8).write(to: abandoned.appendingPathComponent("output"))
            try Data("keep".utf8).write(to: unrelated)
            crypto.removeAbandonedStagingFiles(in: directory)
            #expect(!FileManager.default.fileExists(atPath: abandoned.path))
            #expect(try Data(contentsOf: unrelated) == Data("keep".utf8))
        }
    }

    @Test
    func readsValidLegacyV1AndBufferedFilesWithoutConversion() throws {
        try fixture { directory in
            let chunks = [Data("first legacy chunk".utf8), Data("second legacy chunk".utf8)]
            let legacy = try legacyV1(chunks: chunks)
            let input = directory.appendingPathComponent("legacy")
            let output = directory.appendingPathComponent("restored")
            try legacy.write(to: input)
            try crypto.decryptFile(inputURL: input, to: output, password: password)
            #expect(try Data(contentsOf: output) == chunks.reduce(Data(), +))
            #expect(try Data(contentsOf: input) == legacy)
            for original in [Data(), Data("buffered legacy content".utf8)] {
                try crypto.encrypt(data: original, password: password).write(to: input)
                try crypto.decryptFile(inputURL: input, to: output, password: password)
                #expect(try Data(contentsOf: output) == original)
            }
        }
    }

    @Test
    func legacyTruncationAndOversizedLengthsFailWithoutPlaintext() throws {
        try fixture { directory in
            let legacy = try legacyV1(chunks: [Data("legacy fixture".utf8)])
            try expectRejected(Data(legacy.dropLast(4)), in: directory)
            try expectRejected(legacy + Data([0]), in: directory)
            var oversized = legacy
            oversized.replaceSubrange(24..<28, with: [255, 255, 255, 255])
            try expectRejected(oversized, in: directory)
        }
    }

    /// Independent fixture encoder for the exact pre-hardening format, not the v2 writer.
    private func legacyV1(chunks: [Data]) throws -> Data {
        let salt = Data((0..<16).map(UInt8.init))
        let bytes = Data(password.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBuffer in
                bytes.withUnsafeBytes { passwordBuffer in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress!.assumingMemoryBound(to: Int8.self), bytes.count,
                        saltBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 100_000,
                        output.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw EncryptionError.keyDerivationFailed }
        let key = SymmetricKey(data: derived)
        var result = Data("ZNSC".utf8) + Data([1, 0, 1, 0]) + salt
        for (index, chunk) in chunks.enumerated() {
            let iv = Data(repeating: UInt8(index), count: 12)
            let sealed = try AES.GCM.seal(chunk, using: key, nonce: AES.GCM.Nonce(data: iv))
            var length = UInt32(chunk.count).bigEndian
            result.append(withUnsafeBytes(of: &length) { Data($0) })
            result.append(iv)
            result.append(sealed.tag)
            result.append(sealed.ciphertext)
        }
        result.append(Data(repeating: 0, count: 4))
        return result
    }
}
