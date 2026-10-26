//
//  FileStorageService.swift
//  WagLock
//
//  File storage service
//  Saves, reads and deletes encrypted files
//

import Foundation
import CryptoKit

/// File storage error types
enum FileStorageError: Error {
    case directoryCreationFailed  // Directory creation failed
    case fileNotFound  // File not found
    case fileSaveFailed  // File save failed
    case fileDeleteFailed  // File delete failed
    case insufficientStorage  // Insufficient storage
    case fileTooLarge  // File too large
    case invalidPath  // Invalid path

    var localizedDescription: String {
        switch self {
        case .directoryCreationFailed:
            return String(localized: "fileStorage.error.directoryCreation")
        case .fileNotFound:
            return AppConstants.ErrorMessages.fileNotFound
        case .fileSaveFailed:
            return String(localized: "fileStorage.error.fileSave")
        case .fileDeleteFailed:
            return String(localized: "fileStorage.error.fileDelete")
        case .insufficientStorage:
            return AppConstants.ErrorMessages.storageInsufficient
        case .fileTooLarge:
            return AppConstants.ErrorMessages.fileTooLarge
        case .invalidPath:
            return String(localized: "fileStorage.error.invalidPath")
        }
    }
}

/// File storage service
nonisolated class FileStorageService: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = FileStorageService()

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let storageDirectoryName = AppConstants.encryptedMediaDirectory
    private let fileExtension = AppConstants.encryptedFileExtension
    private let encryptionService = EncryptionService.shared
    private let decryptionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.d2sci.waglock.media-decryption"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    // Storage directory URL
    private let storageDirectory: URL
    private let bindingLock = NSLock()
    private var bindings: CiphertextBindings?
    private let availableCapacity: @Sendable (URL) throws -> Int64

    // MARK: - Initialization

    private init() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageDirectory = documentsURL.appendingPathComponent(storageDirectoryName)
        availableCapacity = Self.readAvailableCapacity
        // Make sure the storage directory exists
        createStorageDirectoryIfNeeded()
    }

    convenience init(directory: URL) {
        self.init(directory: directory, availableCapacity: Self.readAvailableCapacity)
    }

    /// Disposable directories and injected capacity failures keep storage tests isolated.
    init(directory: URL, availableCapacity: @escaping @Sendable (URL) throws -> Int64) {
        storageDirectory = directory
        self.availableCapacity = availableCapacity
        createStorageDirectoryIfNeeded()
    }

    func installBindings(_ registry: CiphertextBindings) {
        bindingLock.lock(); let old = bindings; bindings = registry; bindingLock.unlock(); old?.revoke()
    }
    private func currentBindings() -> CiphertextBindings? {
        bindingLock.lock(); defer { bindingLock.unlock() }; return bindings
    }
    func expectedCiphertextDigest(path: String) throws -> Data? {
        try currentBindings()?.digest(getFileURL(for: path).lastPathComponent)
    }
    func bindingSnapshot() throws -> [String: Data] {
        var result: [String: Data] = [:]
        for path in getAllEncryptedFiles() {
            let url = try getFileURL(for: path), file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var hash = SHA256()
            while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
                try Task.checkCancellation(); hash.update(data: data)
            }
            result[url.lastPathComponent] = Data(hash.finalize())
        }
        return result
    }

    // MARK: - Public Methods

    /// Save encrypted data
    /// - Parameters:
    ///   - data: Encrypted data
    ///   - fileName: Original file name (optional; used to generate a unique name)
    /// - Returns: Relative path of the saved file (file name only)
    /// - Throws: FileStorageError
    func saveEncrypted(data: Data, originalFileName: String? = nil) throws -> String {
        let registry = currentBindings()
        // Check file size
        guard data.count <= AppConstants.maxFileSize else {
            throw FileStorageError.fileTooLarge
        }

        // Check storage space
        try checkStorageSpace(requiredBytes: Int64(data.count))

        // Generate a unique file name
        let fileName = generateUniqueFileName(originalName: originalFileName)
        let fileURL = try getFileURL(for: fileName)

        // Save the file
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try registry?.register(fileName, digest: Data(SHA256.hash(data: data)))
            // Return a relative path (file name only), not an absolute path
            return fileName
        } catch {
            throw FileStorageError.fileSaveFailed
        }
    }

    /// Save a large file (streaming encryption)
    func saveEncryptedFile(
        from sourceURL: URL,
        password: String,
        originalFileName: String? = nil
    ) throws -> String {
        let registry = currentBindings()
        let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        // Budget framing overhead before starting; actual write errors still propagate.
        guard fileSize >= 0 else { throw FileStorageError.fileTooLarge }
        let (required, overflow) = fileSize.addingReportingOverflow(max(128, fileSize / 100))
        guard !overflow else { throw FileStorageError.fileTooLarge }
        try checkStorageSpace(requiredBytes: required)

        let fileName = generateUniqueFileName(originalName: originalFileName)
        let destinationURL = try getFileURL(for: fileName)

        do {
            var digest: Data?
            try encryptionService.encryptFile(inputURL: sourceURL, to: destinationURL, password: password,
                ciphertextDigest: { digest = $0 })
            if let registry {
                guard let digest else { throw EncryptionError.dataCorrupted }
                try registry.register(fileName, digest: digest)
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }

        return fileName
    }

    /// Read encrypted data
    /// - Parameter path: Relative file path (file name)
    /// - Returns: Encrypted data
    /// - Throws: FileStorageError
    func loadEncrypted(path: String) throws -> Data {
        let fileURL = try getFileURL(for: path)

        // Check that the file exists
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw FileStorageError.fileNotFound
        }

        // Read the file
        do {
            let expected = try expectedCiphertextDigest(path: path)
            let data = try Data(contentsOf: fileURL)
            if let expected, Data(SHA256.hash(data: data)) != expected { throw EncryptionError.dataCorrupted }
            return data
        } catch {
            throw FileStorageError.fileNotFound
        }
    }

    /// Delete a file
    /// - Parameter path: Relative file path (file name)
    /// - Throws: FileStorageError
    func deleteFile(path: String) throws {
        let fileURL = try getFileURL(for: path)

        // Check that the file exists
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        // Delete the file
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw FileStorageError.fileDeleteFailed
        }
    }

    /// Get file size
    /// - Parameter path: Relative file path (file name)
    /// - Returns: File size (bytes)
    func getFileSize(path: String) -> Int64? {
        guard let fileURL = try? getFileURL(for: path) else { return nil }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }

    /// Check whether a file exists
    /// - Parameter path: Relative file path (file name)
    /// - Returns: Whether it exists
    func fileExists(path: String) -> Bool {
        guard let fileURL = try? getFileURL(for: path) else { return false }
        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Get the storage directory path
    /// - Returns: Storage directory URL
    func getStorageDirectory() -> URL {
        return storageDirectory
    }

    /// Calculate total storage size
    /// - Returns: Total size (bytes)
    func getTotalStorageSize() -> Int64 {
        var totalSize: Int64 = 0

        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: storageDirectory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            )

            for fileURL in fileURLs {
                let resources = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resources.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        } catch {
        }

        return totalSize
    }

    /// Get the list of all encrypted files
    /// - Returns: Array of file paths
    func getAllEncryptedFiles() -> [String] {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: storageDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )

            return
                fileURLs
                .filter {
                    $0.pathExtension
                        == fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                }
                .map { $0.lastPathComponent }
        } catch {
            return []
        }
    }

    /// Delete all encrypted files
    /// - Throws: FileStorageError
    func clearAllFiles() throws {
        let files = getAllEncryptedFiles()

        for filePath in files {
            try deleteFile(path: filePath)
        }

    }

    // MARK: - Private Methods

    /// Create the storage directory (if it doesn't exist)
    private func createStorageDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: storageDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: storageDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.complete]
                )
            } catch {
            }
        }
    }

    /// Generate a unique file name
    /// - Parameter originalName: Original file name (optional)
    /// - Returns: Unique file name
    private func generateUniqueFileName(originalName: String?) -> String {
        // Names/extensions remain in the catalog; ciphertext paths reveal neither.
        UUID().uuidString + fileExtension
    }

    /// Check storage space
    /// - Parameter requiredBytes: Number of bytes required
    /// - Throws: FileStorageError
    private func checkStorageSpace(requiredBytes: Int64) throws {
        let freeSpace = try availableCapacity(storageDirectory)
        let safetyMargin: Int64 = 100 * 1024 * 1024
        guard requiredBytes >= 0, freeSpace >= safetyMargin,
              requiredBytes <= freeSpace - safetyMargin else {
            throw FileStorageError.insufficientStorage
        }
    }

    private static func readAvailableCapacity(at directory: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        guard let capacity = attributes[.systemFreeSize] as? Int64 else {
            throw FileStorageError.insufficientStorage
        }
        return capacity
    }
}

// MARK: - Storage Statistics

nonisolated extension FileStorageService {

    /// Storage statistics
    struct StorageStatistics {
        let totalFiles: Int
        let totalSize: Int64
        let formattedSize: String
        let availableSpace: Int64
        let formattedAvailableSpace: String

        init(totalFiles: Int, totalSize: Int64, availableSpace: Int64) {
            self.totalFiles = totalFiles
            self.totalSize = totalSize
            self.formattedSize = ByteCountFormatter.string(
                fromByteCount: totalSize, countStyle: .file)
            self.availableSpace = availableSpace
            self.formattedAvailableSpace = ByteCountFormatter.string(
                fromByteCount: availableSpace, countStyle: .file)
        }
    }

    /// Get storage statistics
    /// - Returns: Storage statistics
    func getStorageStatistics() -> StorageStatistics {
        let files = getAllEncryptedFiles()
        let totalSize = getTotalStorageSize()

        var availableSpace: Int64 = 0
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(
                forPath: storageDirectory.path)
            availableSpace = systemAttributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
        }

        return StorageStatistics(
            totalFiles: files.count,
            totalSize: totalSize,
            availableSpace: availableSpace
        )
    }

    /// Get the full URL of a stored file
    func getFileURL(for path: String) throws -> URL {
        guard !path.isEmpty, !path.utf8.contains(0),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(".") else {
            throw FileStorageError.invalidPath
        }
        let root = storageDirectory.standardizedFileURL
        let rootAttributes = try fileManager.attributesOfItem(atPath: root.path)
        guard rootAttributes[.type] as? FileAttributeType == .typeDirectory else { throw FileStorageError.invalidPath }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        if !path.hasPrefix("/"), path.contains("/") { throw FileStorageError.invalidPath }
        let candidate = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
        // Keep legitimate old absolute paths only when they identify this same flat root.
        guard candidate.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == canonicalRoot.path,
              candidate.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL.path == canonicalRoot.path else {
            throw FileStorageError.invalidPath
        }
        if let attributes = try? fileManager.attributesOfItem(atPath: candidate.path),
           attributes[.type] as? FileAttributeType != .typeRegular { throw FileStorageError.invalidPath }
        return candidate
    }

    /// Decrypt an encrypted file to a temporary file
    func createDecryptedTempFile(
        path: String,
        password: String,
        preferredExtension: String
    ) throws -> URL {
        let sourceURL = try getFileURL(for: path)
        let tempURL = try ProtectedTemporaryFiles.fileURL(preferredExtension: sanitizedExtension(preferredExtension))
        do {
            try encryptionService.decryptFile(
                inputURL: sourceURL,
                to: tempURL,
                password: password,
                expectedCiphertextDigest: try expectedCiphertextDigest(path: path)
            )

            // Plaintext temporary files must use the strongest file protection so they can't be read while the device is locked
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: tempURL.path
            )

            return tempURL
        } catch {
            // On decryption failure, clean up any partial output
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    /// Decrypt media on a controlled background queue so paging or opening the player doesn't block the main thread.
    func createDecryptedTempFileAsync(
        path: String,
        password: String,
        preferredExtension: String
    ) async throws -> URL {
        try Task.checkCancellation()
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            decryptionQueue.addOperation {
                do {
                    continuation.resume(
                        returning: try self.createDecryptedTempFile(
                            path: path,
                            password: password,
                            preferredExtension: preferredExtension
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        do {
            try Task.checkCancellation()
            return url
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    /// Read and decrypt file data on a controlled background queue; supports both buffered and streaming formats.
    func loadDecryptedDataAsync(
        path: String,
        password: String,
        preferredExtension: String
    ) async throws -> Data {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            decryptionQueue.addOperation {
                do {
                    let sourceURL = try self.getFileURL(for: path)

                    // Read only the 4-byte magic to detect the format, without loading the whole encrypted file into memory
                    let handle = try FileHandle(forReadingFrom: sourceURL)
                    let magic = try handle.read(upToCount: 4) ?? Data()
                    try handle.close()
                    let chunkMagic = Data("ZNSC".utf8)

                    if magic == chunkMagic {
                        // Streaming format: decrypt to a temporary file, then read it (the temporary file is deleted right after)
                        let tempURL = try self.createDecryptedTempFile(
                            path: path,
                            password: password,
                            preferredExtension: preferredExtension
                        )
                        defer { try? FileManager.default.removeItem(at: tempURL) }
                        continuation.resume(returning: try Data(contentsOf: tempURL))
                    } else {
                        let encryptedData = try self.loadEncrypted(path: path)
                        continuation.resume(
                            returning: try self.encryptionService.decrypt(
                                encryptedData: encryptedData,
                                password: password
                            )
                        )
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Sanitize the file extension so illegal characters can't reach temporary file names (path traversal risk for future callers)
    private func sanitizedExtension(_ fileExtension: String) -> String {
        let cleaned = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .filter { $0.isLetter || $0.isNumber }
        return cleaned.isEmpty ? "" : "." + cleaned
    }
}
