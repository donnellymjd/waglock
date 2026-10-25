import Foundation
import UIKit
internal import Combine

enum ExportError: Error {
    case noItemsSelected, decryptionFailed, exportFailed, invalidPassword, tempDirectoryError, cancelled
    var localizedDescription: String {
        switch self {
        case .noItemsSelected: return String(localized: "exportError.noSelection")
        case .decryptionFailed: return AppConstants.ErrorMessages.decryptionFailed
        case .exportFailed: return String(localized: "export.failed")
        case .invalidPassword: return AppConstants.ErrorMessages.passwordIncorrect
        case .tempDirectoryError: return String(localized: "exportError.tempDirectory")
        case .cancelled: return String(localized: "importError.cancelled")
        }
    }
}

/// A selected-vault export boundary activated only by its authenticated session.
/// Every operation owns its directory and snapshots metadata before background work.
@MainActor
final class ExportService: ObservableObject {
    nonisolated deinit {}
    static let shared = ExportService(
        storage: FileStorageService.shared,
        directory: FileManager.default.temporaryDirectory.appendingPathComponent("WagLockExport", isDirectory: true))

    typealias Removal = @Sendable (URL) throws -> Void
    typealias Decryptor = @Sendable (URL, URL, String) async throws -> Void
    @Published private(set) var revision: UInt64 = 0
    private var sessionID: UUID?
    private var jobs: [UUID: Job] = [:]
    private let storage: FileStorageService
    private let directory: URL
    private let decrypt: Decryptor
    private let remove: Removal
    private var pendingCleanup: Set<URL> = []

    private struct Job {
        let sessionID: UUID
        let directory: URL
        let lease: Lease
        var task: Task<Void, Never>?
        var ready = false
        var urls: [URL] = []
        var progress: ((Int, Int) -> Void)?
        var completion: ((Result<[URL], ExportError>) -> Void)?
    }
    nonisolated private final class Lease: @unchecked Sendable {
        private let lock = NSLock()
        private var revoked = false
        func cancel() { lock.lock(); revoked = true; lock.unlock() }
        func check() throws {
            lock.lock(); let invalid = revoked; lock.unlock()
            if invalid || Task.isCancelled { throw ExportError.cancelled }
        }
    }
    nonisolated private struct Item: Sendable {
        let source: URL
        let name: String
    }

    init(storage: FileStorageService, directory: URL, remove: Removal? = nil, decrypt: Decryptor? = nil) {
        self.storage = storage
        self.directory = directory.standardizedFileURL
        self.remove = remove ?? { url in
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        self.decrypt = decrypt ?? { source, destination, password in
            try EncryptionService.shared.decryptFile(inputURL: source, to: destination, password: password,
                expectedCiphertextDigest: try storage.expectedCiphertextDigest(path: source.path))
        }
    }

    func beginSession(_ id: UUID) {
        retryCleanup()
        guard sessionID != id else { return }
        endSession()
        sessionID = id
    }

    @discardableResult
    func endSession(matching expected: UUID? = nil) -> [Task<Void, Never>] {
        if let expected, sessionID != expected { return [] }
        sessionID = nil
        let previous = jobs
        jobs.removeAll()
        for job in previous.values {
            job.lease.cancel()
            job.task?.cancel()
            // A running writer owns cleanup until it stops. Ready output can be removed now.
            if job.ready { cleanupOwned(job.directory) }
        }
        revision &+= 1
        return previous.values.compactMap(\.task)
    }

    @discardableResult
    func exportItems(_ items: [MediaItem], password: String, sessionID expected: UUID,
                     progressHandler: ((Int, Int) -> Void)? = nil,
                     completion: @escaping (Result<[URL], ExportError>) -> Void) -> UUID? {
        guard sessionID == expected else { completion(.failure(.cancelled)); return nil }
        guard !items.isEmpty else { completion(.failure(.noItemsSelected)); return nil }
        guard !password.isEmpty else { completion(.failure(.invalidPassword)); return nil }
        let snapshots: [Item]
        do { snapshots = try items.map { try snapshot($0) } }
        catch { completion(.failure(.exportFailed)); return nil }
        let id = UUID()
        let output = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        let lease = Lease()
        jobs[id] = Job(sessionID: expected, directory: output, lease: lease,
                       progress: progressHandler, completion: completion)
        let root = directory
        let decrypt = decrypt
        let remove = remove
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let result = await Self.run(snapshots, password: password, root: root,
                                        directory: output, lease: lease, decrypt: decrypt, remove: remove) { processed, total in
                await self?.report(id, processed: processed, total: total)
            }
            guard let self else { if result.ownsDirectory { try? remove(output) }; return }
            await self.finish(id, output: output, result: result)
        }
        jobs[id]?.task = task
        return id
    }

    @discardableResult
    func cancelExport(_ id: UUID) -> Task<Void, Never>? {
        guard let job = jobs.removeValue(forKey: id) else { return nil }
        job.lease.cancel()
        job.task?.cancel()
        if job.ready { cleanupOwned(job.directory) }
        revision &+= 1
        if sessionID == job.sessionID { job.completion?(.failure(.cancelled)) }
        return job.task
    }

    func isReady(_ id: UUID) -> Bool {
        guard let job = jobs[id] else { return false }
        return job.ready && job.sessionID == sessionID
    }

    func jobID(for urls: [URL]) -> UUID? {
        guard !urls.isEmpty else { return nil }
        return jobs.first { _, job in job.ready && job.urls == urls && job.sessionID == sessionID }?.key
    }

    /// Cleanup can only remove outputs minted by this instance, never an unrelated share.
    func cleanupExportedFiles(_ urls: [URL]) {
        let ids = jobs.compactMap { id, job in
            job.ready && job.urls.contains(where: urls.contains) ? id : nil
        }
        for id in ids { cancelExport(id) }
    }

    func cleanupAfterSharing(_ urls: [URL]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.cleanupExportedFiles(urls) }
    }

    func containsManagedURL(_ urls: [URL]) -> Bool {
        urls.contains { $0.standardizedFileURL.path.hasPrefix(directory.path + "/") }
    }

    /// Startup-only cleanup of known plaintext export caches, never encrypted media.
    func cleanupAbandonedExports() {
        guard jobs.isEmpty else { return }
        try? remove(directory)
        // Old builds used this separate plaintext export cache.
        if directory.lastPathComponent == "WagLockExport" {
            try? remove(directory.deletingLastPathComponent().appendingPathComponent("ZeroNetExport"))
        }
    }

    /// Retry only known, revoked job directories; never sweep arbitrary temporary files.
    func retryCleanup() {
        for url in pendingCleanup { cleanupOwned(url) }
    }

    private func cleanupOwned(_ url: URL) {
        do { try remove(url); pendingCleanup.remove(url) }
        catch { pendingCleanup.insert(url) }
    }

    private func snapshot(_ item: MediaItem) throws -> Item {
        let root = storage.getStorageDirectory().resolvingSymlinksInPath().standardizedFileURL
        let source = try storage.getFileURL(for: item.encryptedPath).standardizedFileURL
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              source.resolvingSymlinksInPath().path == root.appendingPathComponent(source.lastPathComponent).path else {
            throw ExportError.exportFailed
        }
        let name = item.fullFileName.map { character -> Character in
            if character == "/" || character == "\\" || character == ":"
                || character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) { return "_" }
            return character
        }
        let safeName = String(name)
        return Item(source: source, name: safeName.isEmpty || safeName == "." || safeName == ".." ? "export" : safeName)
    }

    private func report(_ id: UUID, processed: Int, total: Int) {
        guard let job = jobs[id], job.sessionID == sessionID else { return }
        job.progress?(processed, total)
    }

    private func finish(_ id: UUID, output: URL, result outcome: Outcome) {
        let result = outcome.result
        guard var job = jobs[id], job.sessionID == sessionID else {
            if outcome.ownsDirectory { cleanupOwned(output) }
            return
        }
        let completion = job.completion
        switch result {
        case .success(let urls):
            job.task = nil
            job.completion = nil
            job.progress = nil
            job.ready = true
            job.urls = urls
            jobs[id] = job
        case .failure:
            jobs.removeValue(forKey: id)
            if outcome.ownsDirectory { cleanupOwned(output) }
        }
        revision &+= 1
        completion?(result)
    }

    nonisolated private struct Outcome: Sendable {
        let result: Result<[URL], ExportError>
        let ownsDirectory: Bool
    }

    nonisolated private static func run(_ items: [Item], password: String, root: URL, directory: URL,
                                       lease: Lease, decrypt: Decryptor, remove: Removal,
                                       progress: @Sendable (Int, Int) async -> Void) async -> Outcome {
        var succeeded = false
        var ownsDirectory = false
        defer { if ownsDirectory && !succeeded { try? remove(directory) } }
        do {
            try lease.check()
            let fm = FileManager.default
            try fm.createDirectory(at: root, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: FileProtectionType.complete])
            // Avoid URL resource-value caches and reject a redirected leaf directory.
            let rootType = try fm.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType
            let expectedRoot = root.deletingLastPathComponent().resolvingSymlinksInPath()
                .appendingPathComponent(root.lastPathComponent, isDirectory: true)
            guard rootType == .typeDirectory, root.resolvingSymlinksInPath().path == expectedRoot.path else {
                throw ExportError.tempDirectoryError
            }
            try fm.createDirectory(at: directory, withIntermediateDirectories: false,
                                   attributes: [.protectionKey: FileProtectionType.complete])
            ownsDirectory = true
            var urls: [URL] = []
            var names: Set<String> = []
            for item in items {
                try lease.check()
                var name = item.name
                var suffix = 2
                while names.contains(name.lowercased()) || fm.fileExists(atPath: directory.appendingPathComponent(name).path) {
                    let original = item.name as NSString
                    name = original.deletingPathExtension + " (\(suffix))"
                    if !original.pathExtension.isEmpty { name += "." + original.pathExtension }
                    suffix += 1
                }
                names.insert(name.lowercased())
                let output = directory.appendingPathComponent(name)
                do { try await decrypt(item.source, output, password) }
                catch { try lease.check(); throw ExportError.decryptionFailed }
                try lease.check()
                let attributes = try fm.attributesOfItem(atPath: output.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ExportError.exportFailed }
                try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: output.path)
                urls.append(output)
                await progress(urls.count, items.count)
            }
            try lease.check()
            succeeded = true
            return Outcome(result: .success(urls), ownsDirectory: true)
        } catch let error as ExportError { return Outcome(result: .failure(error), ownsDirectory: ownsDirectory) }
        catch { return Outcome(result: .failure(.exportFailed), ownsDirectory: ownsDirectory) }
    }

    func createShareController(for urls: [URL]) -> UIActivityViewController {
        let service = self
        let valid = !service.containsManagedURL(urls) || service.jobID(for: urls) != nil
        let controller = UIActivityViewController(activityItems: valid ? urls : [], applicationActivities: nil)
        controller.excludedActivityTypes = [.assignToContact, .addToReadingList, .postToFlickr, .postToVimeo]
        controller.completionWithItemsHandler = { _, completed, _, _ in
            // Let successful receivers finish opening the file; cancellation needs no grace period.
            if completed {
                service.cleanupAfterSharing(urls)
            } else { service.cleanupExportedFiles(urls) }
        }
        return controller
    }
}
