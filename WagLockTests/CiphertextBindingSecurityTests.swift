import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import WagLock

@MainActor
final class CiphertextBindingSecurityTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDown() { for root in roots { try? FileManager.default.removeItem(at: root) }; roots = [] }
    private func fixture() throws -> (URL, FileStorageService, EncryptedLibraryRepository, EncryptedMetadataStore.Domain, Data) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("file-binding-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); roots.append(root)
        let storage = FileStorageService(directory: root.appendingPathComponent("media"), availableCapacity: { _ in Int64.max })
        let domain = EncryptedMetadataStore.Domain(libraryID: UUID(), vaultID: UUID()), key = Data(repeating: 45, count: 32)
        let repository = try EncryptedLibraryRepository.create(at: root.appendingPathComponent("index"), domain: domain, key: key, authorized: { true })
        return (root, storage, repository, domain, key)
    }
    func testSwappedValidSameVaultFilesAreRejectedAcrossReopenAndOriginalsRemainRecoverable() async throws {
        let (root, storage, repository, domain, key) = try fixture()
        let password = "PUBLIC random data secret"
        let first = try storage.saveEncrypted(data: EncryptionService.shared.encrypt(data: Data("PUBLIC first".utf8), password: password))
        let second = try storage.saveEncrypted(data: EncryptionService.shared.encrypt(data: Data("PUBLIC second".utf8), password: password))
        try await repository.bindStorage(storage)
        let firstURL = try storage.getFileURL(for: first), original = try Data(contentsOf: firstURL)
        let other = try Data(contentsOf: storage.getFileURL(for: second))
        try other.write(to: firstURL)
        do { _ = try await storage.loadDecryptedDataAsync(path: first, password: password, preferredExtension: "txt"); XCTFail("Swapped ciphertext was accepted") } catch {}
        repository.revoke()
        let reopened = try EncryptedLibraryRepository.open(at: root.appendingPathComponent("index"), domain: domain, key: key, authorized: { true })
        defer { reopened.revoke() }; try await reopened.bindStorage(storage)
        do { _ = try await storage.loadDecryptedDataAsync(path: first, password: password, preferredExtension: "txt"); XCTFail("Reopen rebaselined changed ciphertext") } catch {}
        try original.write(to: firstURL)
        let recovered = try await storage.loadDecryptedDataAsync(path: first, password: password, preferredExtension: "txt")
        XCTAssertEqual(recovered, Data("PUBLIC first".utf8))
    }
    func testOwnedStreamWriteIsBoundBeforeCommitAndSharesRejectSubstitution() async throws {
        let (root, storage, repository, _, _) = try fixture()
        defer { repository.revoke() }
        try await repository.bindStorage(storage)
        let password = "PUBLIC stream data secret", source = root.appendingPathComponent("plain")
        try Data(repeating: 7, count: 512 * 1024).write(to: source)
        let path = try storage.saveEncryptedFile(from: source, password: password)
        let cipher = try storage.getFileURL(for: path), original = try Data(contentsOf: cipher)
        try Data(repeating: 9, count: 512 * 1024).write(to: source)
        let other = root.appendingPathComponent("other-cipher")
        try EncryptionService.shared.encryptFile(inputURL: source, to: other, password: password)
        try Data(contentsOf: other).write(to: cipher)
        XCTAssertThrowsError(try storage.createDecryptedTempFile(path: path, password: password, preferredExtension: "bin"))
        let model = MediaItem(fileName: "PUBLIC stream", fileExtension: "bin", fileSize: 512 * 1024, type: .document, encryptedPath: path)
        repository.container.mainContext.insert(model); try LibraryWriteCoordinator.save(repository.container.mainContext)
        let exports = ExportService(storage: storage, directory: root.appendingPathComponent("exports"))
        let session = UUID(); exports.beginSession(session)
        let result: Result<[URL], ExportError> = await withCheckedContinuation { continuation in
            _ = exports.exportItems([model], password: password, sessionID: session) { continuation.resume(returning: $0) }
        }
        if case .success = result { XCTFail("Share accepted substituted media") }
        exports.endSession()
        XCTAssertEqual(try Data(contentsOf: cipher), try Data(contentsOf: other))
        try original.write(to: cipher)
        let output = try storage.createDecryptedTempFile(path: path, password: password, preferredExtension: "bin")
        defer { try? FileManager.default.removeItem(at: output) }
        XCTAssertEqual(try Data(contentsOf: output), Data(repeating: 7, count: 512 * 1024))
    }
    func testStreamDigestMismatchPreservesExistingDestinationAndRawCiphertext() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stream-digest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); roots.append(root)
        let source = root.appendingPathComponent("plain"), cipher = root.appendingPathComponent("cipher"), destination = root.appendingPathComponent("destination")
        try Data(repeating: 6, count: 400_000).write(to: source)
        var digest: Data?
        try EncryptionService.shared.encryptFile(inputURL: source, to: cipher, password: "PUBLIC key", ciphertextDigest: { digest = $0 })
        XCTAssertEqual(digest, Data(SHA256.hash(data: try Data(contentsOf: cipher))))
        try Data("KEEP".utf8).write(to: destination)
        let before = try Data(contentsOf: cipher)
        XCTAssertThrowsError(try EncryptionService.shared.decryptFile(inputURL: cipher, to: destination, password: "PUBLIC key", expectedCiphertextDigest: Data(repeating: 0, count: 32)))
        XCTAssertEqual(try Data(contentsOf: destination), Data("KEEP".utf8)); XCTAssertEqual(try Data(contentsOf: cipher), before)
        try EncryptionService.shared.decryptFile(inputURL: cipher, to: destination, password: "PUBLIC key", expectedCiphertextDigest: digest)
        XCTAssertEqual(try Data(contentsOf: destination), try Data(contentsOf: source))
    }
}
