import Foundation

/// New plaintext previews/shares live only in marked, protected, exclusively created jobs.
/// Startup cleanup never scans anonymous files or traverses symlinks/unknown directories.
nonisolated enum ProtectedTemporaryFiles {
    private static let lock = NSLock()
    private static let marker = ".waglock-plaintext-owner"
    private static let signature = Data("waglock-plaintext-v1".utf8)
    static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("WagLockPlaintextJobs", isDirectory: true) }

    static func createDirectory(in root: URL = root) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        if fm.fileExists(atPath: root.path) {
            guard isDirectory(root) else { throw FileStorageError.invalidPath }
            if !isOwned(root) {
                guard try fm.contentsOfDirectory(atPath: root.path).isEmpty else { throw FileStorageError.invalidPath }
                try signature.write(to: root.appendingPathComponent(marker), options: [.atomic, .completeFileProtection])
            }
        } else {
            try fm.createDirectory(at: root, withIntermediateDirectories: false,
                                   attributes: [.protectionKey: FileProtectionType.complete])
            try signature.write(to: root.appendingPathComponent(marker), options: [.atomic, .completeFileProtection])
        }
        let job = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: job, withIntermediateDirectories: false,
                               attributes: [.protectionKey: FileProtectionType.complete])
        do { try signature.write(to: job.appendingPathComponent(marker), options: [.atomic, .completeFileProtection]) }
        catch { try? fm.removeItem(at: job); throw error }
        return job
    }

    static func fileURL(preferredExtension: String, in root: URL = root) throws -> URL {
        let suffix = String(preferredExtension.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(16))
        return try createDirectory(in: root).appendingPathComponent("preview").appendingPathExtension(suffix.isEmpty ? "bin" : suffix)
    }

    static func removeAbandonedJobs(in root: URL = root) {
        lock.lock(); defer { lock.unlock() }
        guard isOwned(root), let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for child in children where UUID(uuidString: child.lastPathComponent) != nil && isOwned(child) {
            try? FileManager.default.removeItem(at: child)
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory
    }
    private static func isOwned(_ url: URL) -> Bool {
        guard isDirectory(url) else { return false }
        let file = url.appendingPathComponent(marker)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue == signature.count else { return false }
        return (try? Data(contentsOf: file)) == signature
    }
}
