//
//  EncryptionService.swift
//  WagLock
//
//  File encryption/decryption service
//  Uses AES-256-GCM
//

import Darwin
import CommonCrypto
import CryptoKit
import Foundation

/// Encryption error types
enum EncryptionError: Error {
    case randomGenerationFailed
    case invalidPassword  // Invalid password
    case encryptionFailed(underlying: Error?)  // Encryption failed (with underlying error)
    case decryptionFailed(underlying: Error?)  // Decryption failed (with underlying error)
    case invalidData  // Invalid data
    case keyDerivationFailed  // Key derivation failed
    case dataCorrupted  // Data corrupted or tampered with
    case fileTooLarge(size: Int64, limit: Int64)  // File too large
    case fileNotFound(path: String)  // File not found
    case fileAccessDenied(path: String)  // Insufficient file access permission
    case insufficientStorage  // Insufficient storage
    case ioError(underlying: Error)  // I/O error

    var localizedDescription: String {
        switch self {
        case .randomGenerationFailed:
            return "Secure random generation failed. Nothing was saved."
        case .invalidPassword:
            return String(localized: "encryptionError.invalidPassword")
        case .encryptionFailed(let error):
            if let error = error {
                return String(
                    format: String(localized: "encryptionError.encryptFailedWithReason"),
                    error.localizedDescription)
            }
            return String(localized: "encryptionError.encryptFailed")
        case .decryptionFailed(let error):
            if let error = error {
                return String(
                    format: String(localized: "encryptionError.decryptFailedWithReason"),
                    error.localizedDescription)
            }
            return String(localized: "encryptionError.decryptFailed")
        case .invalidData:
            return String(localized: "encryptionError.invalidData")
        case .keyDerivationFailed:
            return String(localized: "encryptionError.keyDerivationFailed")
        case .dataCorrupted:
            return String(localized: "encryptionError.dataCorrupted")
        case .fileTooLarge(let size, let limit):
            let sizeMB = Double(size) / (1024 * 1024)
            let limitMB = Double(limit) / (1024 * 1024)
            return String(
                format: String(localized: "encryptionError.fileTooLargeDetail"),
                sizeMB,
                limitMB)
        case .fileNotFound(let path):
            return String(
                format: String(localized: "encryptionError.fileNotFound"),
                path)
        case .fileAccessDenied(let path):
            return String(
                format: String(localized: "encryptionError.accessDenied"),
                path)
        case .insufficientStorage:
            return String(localized: "encryptionError.storageInsufficient")
        case .ioError(let error):
            return String(
                format: String(localized: "encryptionError.ioError"),
                error.localizedDescription)
        }
    }
}

/// Encryption service
/// Provides AES-256-GCM encryption and decryption
nonisolated class EncryptionService: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = EncryptionService()
    private let randomBytes: @Sendable (Int) throws -> Data

    private init() { randomBytes = Self.secureRandomBytes }

    /// Failure injection for tests; production always uses checked system randomness.
    init(randomBytes: @escaping @Sendable (Int) throws -> Data) {
        self.randomBytes = randomBytes
    }

    // MARK: - Constants

    private let saltLength = AppConstants.saltLength  // 16 bytes
    private let ivLength = AppConstants.ivLength  // 12 bytes (recommended for GCM)
    private let tagLength = AppConstants.tagLength  // 16 bytes
    private let iterations = AppConstants.pbkdf2Iterations  // 100,000 iterations
    private let chunkMagic = "ZNSC".data(using: .utf8)!
    private let chunkVersion: UInt8 = 2
    private let maximumChunkSize = 16 * 1024 * 1024
    private let maximumLegacyChunkSize = 64 * 1024 * 1024
    private let chunkSize = 4 * 1024 * 1024  // 4MB
    private let maxFileSize: Int64 = 500 * 1024 * 1024  // 500 MB (per-file limit)
    private let minFreeSpace: Int64 = 100 * 1024 * 1024  // 100 MB (minimum free space)

    // MARK: - Public Methods

    /// Encrypt data
    /// - Parameters:
    ///   - data: Plaintext data
    ///   - password: User password
    /// - Returns: Encrypted data (format: salt + IV + tag + ciphertext)
    /// - Throws: EncryptionError
    func encrypt(data: Data, password: String) throws -> Data {
        guard !password.isEmpty else {
            throw EncryptionError.invalidPassword
        }

        // 1. Generate a random salt
        let salt = try generateSalt()

        // 2. Derive the encryption key from the password
        let key = try deriveKey(from: password, salt: salt)

        // 3. Generate a random IV (initialization vector)
        let iv = try generateIV()

        // 4. Encrypt with AES-GCM
        do {
            let sealedBox = try AES.GCM.seal(
                data,
                using: key,
                nonce: AES.GCM.Nonce(data: iv)
            )

            guard let ciphertext = sealedBox.ciphertext.withUnsafeBytes({ Data($0) }) as Data?,
                let tag = sealedBox.tag.withUnsafeBytes({ Data($0) }) as Data?
            else {
                throw EncryptionError.encryptionFailed(underlying: nil)
            }

            // 5. Combine: salt(16) + IV(12) + tag(16) + ciphertext(N)
            var encryptedData = Data()
            encryptedData.append(salt)
            encryptedData.append(iv)
            encryptedData.append(tag)
            encryptedData.append(ciphertext)

            return encryptedData

        } catch {
            throw EncryptionError.encryptionFailed(underlying: error)
        }
    }

    /// Decrypt data
    /// - Parameters:
    ///   - encryptedData: Encrypted data
    ///   - password: User password
    /// - Returns: Decrypted plaintext
    /// - Throws: EncryptionError
    func decrypt(encryptedData: Data, password: String) throws -> Data {
        guard !password.isEmpty else {
            throw EncryptionError.invalidPassword
        }

        // Validate data length
        let minLength = saltLength + ivLength + tagLength
        guard encryptedData.count >= minLength else {
            throw EncryptionError.invalidData
        }

        // 1. Parse the encrypted data: salt + IV + tag + ciphertext
        let salt = encryptedData.subdata(in: 0..<saltLength)
        let iv = encryptedData.subdata(in: saltLength..<(saltLength + ivLength))
        let tag = encryptedData.subdata(
            in: (saltLength + ivLength)..<(saltLength + ivLength + tagLength))
        let ciphertext = encryptedData.subdata(
            in: (saltLength + ivLength + tagLength)..<encryptedData.count)

        // 2. Derive the key from the password (same salt)
        let key = try deriveKey(from: password, salt: salt)

        // 3. Decrypt with AES-GCM
        do {
            let sealedBox = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: iv),
                ciphertext: ciphertext,
                tag: tag
            )

            let decryptedData = try AES.GCM.open(sealedBox, using: key)

            return decryptedData

        } catch CryptoKitError.authenticationFailure {
            // Authentication failed - wrong password or tampered data
            throw EncryptionError.dataCorrupted
        } catch {
            throw EncryptionError.decryptionFailed(underlying: error)
        }
    }

    // MARK: - Convenience Methods

    /// Encrypt a file
    /// - Parameters:
    ///   - fileURL: File URL
    ///   - password: Password
    /// - Returns: Encrypted data
    /// - Throws: EncryptionError
    func encryptFile(at fileURL: URL, password: String) throws -> Data {
        // 1. Check that the file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw EncryptionError.fileNotFound(path: fileURL.path)
        }

        // 2. Check that the file is readable
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw EncryptionError.fileAccessDenied(path: fileURL.path)
        }

        // 3. Check the file size
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            if fileSize > maxFileSize {
                throw EncryptionError.fileTooLarge(size: fileSize, limit: maxFileSize)
            }

            // 4. Check storage space (encrypted output is slightly larger)
            let requiredSpace = Int64(Double(fileSize) * 1.1) + minFreeSpace
            if let freeSpace = try? getFreeSpace(), freeSpace < requiredSpace {
                throw EncryptionError.insufficientStorage
            }
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.ioError(underlying: error)
        }

        // 5. Read and encrypt
        do {
            let data = try Data(contentsOf: fileURL)
            return try encrypt(data: data, password: password)
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.ioError(underlying: error)
        }
    }

    /// Decrypt and save to a file
    /// - Parameters:
    ///   - encryptedData: Encrypted data
    ///   - fileURL: Destination file URL
    ///   - password: Password
    /// - Throws: EncryptionError
    func decryptAndSave(encryptedData: Data, to fileURL: URL, password: String) throws {
        // 1. Decrypt the data
        let decryptedData = try decrypt(encryptedData: encryptedData, password: password)

        // 2. Check storage space
        let requiredSpace = Int64(decryptedData.count) + minFreeSpace
        if let freeSpace = try? getFreeSpace(), freeSpace < requiredSpace {
            throw EncryptionError.insufficientStorage
        }

        // 3. Check that the destination directory is writable
        let parentDir = fileURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDir.path) else {
            throw EncryptionError.fileAccessDenied(path: parentDir.path)
        }

        // 4. Write the file
        do {
            try withAtomicOutput(to: fileURL) { try $0.write(contentsOf: decryptedData) }
        } catch {
            throw EncryptionError.ioError(underlying: error)
        }
    }

    /// ZNSC v2 binds the complete header, record index and length to every GCM tag.
    /// An authenticated zero-length final record proves completion, even for empty files.
    func encryptFile(
        inputURL: URL,
        to outputURL: URL,
        password: String,
        preferredChunkSize: Int? = nil,
        ciphertextDigest: ((Data) -> Void)? = nil
    ) throws {
        guard !password.isEmpty else { throw EncryptionError.invalidPassword }
        try ensureDifferentFiles(inputURL, outputURL)
        let size = min(max(256 * 1024, preferredChunkSize ?? chunkSize), maximumChunkSize) / 1024 * 1024
        let salt = try generateSalt()
        let key = try deriveKey(from: password, salt: salt)
        let noncePrefix = try randomData(count: 4)
        var header = chunkMagic
        header.append(chunkVersion)
        header.append(0)
        header.append(UInt16(size / 1024).bigEndianData)
        header.append(salt)
        header.append(noncePrefix)

        let reader = try FileHandle(forReadingFrom: inputURL)
        defer { try? reader.close() }
        var hash = SHA256()
        try withAtomicOutput(to: outputURL) { writer in
            func write(_ bytes: Data) throws { hash.update(data: bytes); try writer.write(contentsOf: bytes) }
            try write(header)
            var index: UInt64 = 0
            while true {
                try Task.checkCancellation()
                let finished = try autoreleasepool { () throws -> Bool in
                    let chunk = try reader.read(upToCount: size) ?? Data()
                    let length = UInt32(chunk.count).bigEndianData
                    // Counter nonces cannot repeat within this per-file key domain.
                    let iv = noncePrefix + index.bigEndianData
                    let authenticated = header + index.bigEndianData + length
                    let sealed = try AES.GCM.seal(chunk, using: key,
                        nonce: AES.GCM.Nonce(data: iv), authenticating: authenticated)
                    try write(length)
                    try write(iv)
                    try write(sealed.tag)
                    try write(sealed.ciphertext)
                    return chunk.isEmpty
                }
                if finished { break }
                let (next, overflow) = index.addingReportingOverflow(1)
                guard !overflow else { throw EncryptionError.invalidData }
                index = next
            }
        }
        ciphertextDigest?(Data(hash.finalize()))
    }

    /// Retains buffered and ZNSC v1 readers. No destination is published until all
    /// available authentication/framing checks pass; any existing output survives failure.
    func decryptFile(inputURL: URL, to outputURL: URL, password: String,
                     allowLegacyStreams: Bool = !LibraryStoragePolicy.encryptedMetadata,
                     expectedCiphertextDigest: Data? = nil) throws {
        guard !password.isEmpty else { throw EncryptionError.invalidPassword }
        try ensureDifferentFiles(inputURL, outputURL)
        let reader = try CiphertextReader(inputURL)
        defer { try? reader.close() }
        let magic = try reader.read(upToCount: chunkMagic.count) ?? Data()
        guard magic == chunkMagic else {
            let encrypted = magic + (try reader.readToEnd() ?? Data())
            try reader.verify(expectedCiphertextDigest)
            let plaintext = try decrypt(encryptedData: encrypted, password: password)
            try withAtomicOutput(to: outputURL) { try $0.write(contentsOf: plaintext) }
            return
        }

        let fields = try readExactly(4, from: reader)
        let version = fields[0]
        guard (version == chunkVersion || (version == 1 && allowLegacyStreams)), fields[1] == 0 else {
            throw EncryptionError.invalidData
        }
        let indicator = UInt16(bigEndianData: Data(fields.suffix(2)))
        guard indicator > 0 else { throw EncryptionError.invalidData }
        let size = Int(indicator) * 1024
        if version == chunkVersion && size > maximumChunkSize { throw EncryptionError.invalidData }
        let salt = try readExactly(saltLength, from: reader)
        let prefix = version == chunkVersion ? try readExactly(4, from: reader) : Data()
        let header = magic + fields + salt + prefix
        let key = try deriveKey(from: password, salt: salt)
        try withAtomicOutput(to: outputURL) { writer in
            var index: UInt64 = 0
            while true {
                try Task.checkCancellation()
                let finished = try autoreleasepool { () throws -> Bool in
                    let lengthBytes = try readExactly(4, from: reader)
                    let length = UInt32(bigEndianData: lengthBytes)
                    if version == 1 && length == 0 {
                        try requireEndOfFile(reader)
                        return true
                    }
                    let limit = version == 1 ? maximumLegacyChunkSize : size
                    guard UInt64(length) <= UInt64(limit) else { throw EncryptionError.invalidData }
                    let iv = try readExactly(ivLength, from: reader)
                    let tag = try readExactly(tagLength, from: reader)
                    let ciphertext = try readExactly(Int(length), from: reader)
                    let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
                    let plaintext: Data
                    if version == chunkVersion {
                        guard iv == prefix + index.bigEndianData else { throw EncryptionError.dataCorrupted }
                        plaintext = try AES.GCM.open(box, using: key,
                            authenticating: header + index.bigEndianData + lengthBytes)
                    } else {
                        plaintext = try AES.GCM.open(box, using: key)
                    }
                    if length == 0 {
                        try requireEndOfFile(reader)
                        return true
                    }
                    try writer.write(contentsOf: plaintext)
                    return false
                }
                if finished { break }
                let (next, overflow) = index.addingReportingOverflow(1)
                guard !overflow else { throw EncryptionError.invalidData }
                index = next
            }
            try reader.verify(expectedCiphertextDigest)
        }
    }

    private final class CiphertextReader {
        private let file: FileHandle
        private var hash = SHA256()
        init(_ url: URL) throws { file = try FileHandle(forReadingFrom: url) }
        func read(upToCount count: Int) throws -> Data? {
            let data = try file.read(upToCount: count)
            if let data { hash.update(data: data) }; return data
        }
        func readToEnd() throws -> Data? {
            let data = try file.readToEnd()
            if let data { hash.update(data: data) }; return data
        }
        func close() throws { try file.close() }
        func verify(_ expected: Data?) throws {
            if let expected {
                guard expected.count == 32, Data(hash.finalize()) == expected else { throw EncryptionError.dataCorrupted }
            }
        }
    }

    private func ensureDifferentFiles(_ input: URL, _ output: URL) throws {
        guard input.standardizedFileURL.resolvingSymlinksInPath()
                != output.standardizedFileURL.resolvingSymlinksInPath() else {
            throw EncryptionError.invalidData
        }
    }

    private func readExactly(_ count: Int, from reader: CiphertextReader) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let bytes = try reader.read(upToCount: count - result.count), !bytes.isEmpty else {
                throw EncryptionError.dataCorrupted
            }
            result.append(bytes)
        }
        return result
    }

    private func requireEndOfFile(_ reader: CiphertextReader) throws {
        guard (try reader.read(upToCount: 1) ?? Data()).isEmpty else { throw EncryptionError.dataCorrupted }
    }

    /// Same-filesystem protected staging followed by one atomic rename. Failed or
    /// cancelled operations remove staging and never truncate a pre-existing destination.
    private func withAtomicOutput(to output: URL, write: (FileHandle) throws -> Void) throws {
        let manager = FileManager.default
        let directory = output.deletingLastPathComponent()
            .appendingPathComponent(".vaultito-stage-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        defer { try? manager.removeItem(at: directory) }
        let staged = directory.appendingPathComponent("output")
        guard manager.createFile(atPath: staged.path, contents: nil,
                                 attributes: [.protectionKey: FileProtectionType.complete]) else {
            throw EncryptionError.fileAccessDenied(path: output.path)
        }
        let writer = try FileHandle(forWritingTo: staged)
        defer { try? writer.close() }
        try write(writer)
        try Task.checkCancellation()
        try writer.synchronize()
        try writer.close()
        let status = staged.path.withCString { source in
            output.path.withCString { destination in Darwin.rename(source, destination) }
        }
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// Only scan app-owned directories at process startup, before any writer is active.
    func removeAbandonedStagingFiles(in root: URL) {
        let manager = FileManager.default
        let entries = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for entry in entries where entry.lastPathComponent.hasPrefix(".vaultito-stage-") {
            let suffix = String(entry.lastPathComponent.dropFirst(".vaultito-stage-".count))
            if UUID(uuidString: suffix) != nil,
               (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try? manager.removeItem(at: entry)
            }
        }
    }

    // MARK: - Private Methods

    /// Get available storage space
    private func getFreeSpace() throws -> Int64 {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return capacity
            }
            // Fallback to volumeAvailableCapacityKey
            let fallbackValues = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return Int64(fallbackValues.volumeAvailableCapacity ?? 0)
        } catch {
            throw EncryptionError.ioError(underlying: error)
        }
    }

    private static func secureRandomBytes(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw EncryptionError.randomGenerationFailed }
        return data
    }

    private func randomData(count: Int) throws -> Data {
        let data = try randomBytes(count)
        guard data.count == count else { throw EncryptionError.randomGenerationFailed }
        return data
    }

    private func generateSalt() throws -> Data { try randomData(count: saltLength) }
    private func generateIV() throws -> Data { try randomData(count: ivLength) }

    /// Derive an encryption key from a password (PBKDF2)
    /// - Parameters:
    ///   - password: User password
    ///   - salt: Salt
    /// - Returns: 256-bit symmetric key
    /// - Throws: EncryptionError
    private func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw EncryptionError.invalidPassword
        }

        // Derive the key with PBKDF2
        // Parameters: 100,000 iterations, SHA-256, 32-byte (256-bit) output
        let derivedKey = try deriveKeyPBKDF2(
            password: passwordData,
            salt: salt,
            iterations: iterations,
            keyLength: 32
        )

        return SymmetricKey(data: derivedKey)
    }

    /// PBKDF2 key derivation
    private func deriveKeyPBKDF2(
        password: Data,
        salt: Data,
        iterations: Int,
        keyLength: Int
    ) throws -> Data {
        var derivedKeyData = Data(count: keyLength)

        let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw EncryptionError.keyDerivationFailed
        }

        return derivedKeyData
    }
}

nonisolated private extension FixedWidthInteger {
    var bigEndianData: Data {
        var value = bigEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }

    init(bigEndianData data: Data) {
        let count = Swift.min(data.count, MemoryLayout<Self>.size)
        var value: Self = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            buffer.copyBytes(from: data.prefix(count))
        }
        self = Self(bigEndian: value)
    }
}

// CCKeyDerivationPBKDF requires CommonCrypto
// (used in the implementation above)
