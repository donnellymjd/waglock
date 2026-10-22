import Foundation
import Testing

@testable import WagLock

struct FileStorageSecurityTests {
    private let margin: Int64 = 100 * 1024 * 1024

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("storage-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func newCiphertextNamesDoNotExposeOriginalNamesOrExtensions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileStorageService(directory: directory, availableCapacity: { _ in Int64.max })
        let original = Data("private document".utf8)
        let ciphertext = try EncryptionService.shared.encrypt(data: original, password: "fixture-password")
        for name in ["medical-result.pdf", "family-trip.heic", "../../unexpected/path.jpg"] {
            let path = try storage.saveEncrypted(data: ciphertext, originalFileName: name)
            #expect(UUID(uuidString: String(path.dropLast(AppConstants.encryptedFileExtension.count))) != nil)
            #expect(!path.contains(name))
            #expect(storage.getFileURL(for: path).deletingLastPathComponent().path == directory.path)
            #expect(try EncryptionService.shared.decrypt(encryptedData: storage.loadEncrypted(path: path), password: "fixture-password") == original)
        }
        #expect(storage.getAllEncryptedFiles().count == 3)
    }

    @Test
    func lowSpaceRejectsBufferedAndStreamedWritesBeforeCreatingFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("encrypted")
        let capacity = margin + 31
        let storage = FileStorageService(directory: directory, availableCapacity: { _ in capacity })
        let original = root.appendingPathComponent("sample.txt")
        try Data(repeating: 42, count: 32).write(to: original)
        #expect(throws: FileStorageError.insufficientStorage) {
            try storage.saveEncrypted(data: Data(repeating: 42, count: 32), originalFileName: "sample.txt")
        }
        #expect(throws: FileStorageError.insufficientStorage) {
            try storage.saveEncryptedFile(from: original, password: "fixture-password")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(try Data(contentsOf: original).count == 32)
    }

    @Test
    func capacityLookupFailureDoesNotSilentlyContinueWriting() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("encrypted")
        let storage = FileStorageService(directory: directory, availableCapacity: { _ in throw CocoaError(.fileReadNoPermission) })
        let original = root.appendingPathComponent("sample.txt")
        try Data([1, 2, 3]).write(to: original)
        #expect(throws: (any Error).self) { try storage.saveEncrypted(data: Data([1, 2, 3])) }
        #expect(throws: (any Error).self) { try storage.saveEncryptedFile(from: original, password: "fixture-password") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test
    func streamedPreflightBudgetsEncryptionOverhead() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("sample.mov")
        try Data(repeating: 42, count: 128).write(to: source)
        let capacity = margin + 128
        let directory = root.appendingPathComponent("encrypted")
        let storage = FileStorageService(directory: directory, availableCapacity: { _ in capacity })
        #expect(throws: FileStorageError.insufficientStorage) {
            try storage.saveEncryptedFile(from: source, password: "fixture-password", originalFileName: "sample.mov")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test
    func opaqueStreamedPathStillProducesAReadableProtectedFile() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("private-video.mov")
        let original = Data(repeating: 42, count: 300_000)
        try original.write(to: source)
        let storage = FileStorageService(directory: root.appendingPathComponent("encrypted"), availableCapacity: { _ in Int64.max })
        let path = try storage.saveEncryptedFile(from: source, password: "fixture-password", originalFileName: source.lastPathComponent)
        #expect(!path.contains("private-video"))
        #expect(!path.contains("mov"))
        let recovered = try storage.createDecryptedTempFile(path: path, password: "fixture-password", preferredExtension: ".mov")
        defer { try? FileManager.default.removeItem(at: recovered) }
        #expect(try Data(contentsOf: recovered) == original)
        #if !targetEnvironment(simulator)
        let protection = try FileManager.default.attributesOfItem(atPath: storage.getFileURL(for: path).path)[.protectionKey] as? FileProtectionType
        #expect(protection == .complete)
        #endif
    }

    @Test
    func legacyNamedFilesRemainReadableWithoutRenaming() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyName = UUID().uuidString + "_legacy-name.pdf" + AppConstants.encryptedFileExtension
        let data = try EncryptionService.shared.encrypt(data: Data("legacy content".utf8), password: "fixture-password")
        try data.write(to: directory.appendingPathComponent(legacyName))
        let storage = FileStorageService(directory: directory, availableCapacity: { _ in Int64.max })
        #expect(try storage.loadEncrypted(path: legacyName) == data)
        #expect(storage.getAllEncryptedFiles() == [legacyName])
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(legacyName).path))
    }
}
