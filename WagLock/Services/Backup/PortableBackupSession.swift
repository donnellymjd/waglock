import Darwin
import Foundation
import SwiftData
internal import Combine

@MainActor
final class PortableBackupSession: ObservableObject {
    struct AlbumRow: Identifiable {
        let id: UUID
        let parentID: UUID?
        let name: String
        let policy: AlbumProtection
    }
    enum Failure: Error { case unavailable, credentials, changed }
    @Published private(set) var rows: [AlbumRow] = []
    @Published private(set) var isWorking = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var error: String?
    @Published private(set) var readyURL: URL?
    @Published private(set) var handingOff = false
    private var task: Task<Void, Never>?
    private var worker: Task<URL, Error>?
    private var lease: BackupLease?
    private var token = UUID()
    private var directory: URL?
    private var observation: AnyCancellable?
    private let authority: DocumentPreviewService
    private let albums: AlbumStore
    private let storage: FileStorageService

    init(authority: DocumentPreviewService? = nil, albums: AlbumStore = .shared, storage: FileStorageService = .shared) {
        self.albums = albums; self.storage = storage
        let service = authority ?? .shared
        self.authority = service
        observation = service.$revision.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.rows = []
            if !self.handingOff { self.cancel() }
        }
    }
    nonisolated deinit { task?.cancel(); worker?.cancel(); lease?.cancel() }

    func refresh(mounts: LibraryMountCoordinator, request: LibraryMountCoordinator.Request) {
        guard request.scope != .ephemeralGuest, authority.permits(request.sessionID, revision: authority.revision),
              let active = mounts.active, active.request == request else { rows = []; return }
        do {
            rows = try active.container.mainContext.fetch(FetchDescriptor<VaultAlbum>()).map {
                guard let policy = AlbumProtection(rawValue: $0.protectionRawValue) else { throw Failure.unavailable }
                return AlbumRow(id: $0.id, parentID: $0.parentID, name: $0.name, policy: policy)
            }.sorted { $0.id.uuidString < $1.id.uuidString }
        } catch { self.error = "Unable to read the full album inventory. Nothing was exported." }
    }

    func start(mounts: LibraryMountCoordinator, auth: AuthenticationViewModel,
               rootCredential: AgeFileWriter.Credential, passwords: [UUID: String], consent: Set<UUID>) {
        guard !handingOff else { return }
        cancel()
        BackupCleanup.retry()
        let id = token, revision = authority.revision
        let request = LibraryMountCoordinator.Request(sessionID: auth.librarySessionID, scope: auth.libraryScope)
        guard let mount = mounts.active, mount.request == request else { error = "Unlock WagLock and try again."; return }
        let mountID = mount.id
        func check() throws {
            guard token == id, auth.isAuthenticated, auth.librarySessionID == request.sessionID,
                  GuestModeManager.shared.isOwnerMode, mounts.active?.id == mountID,
                  authority.permits(request.sessionID, revision: revision), !Task.isCancelled else { throw CancellationError() }
        }
        isWorking = true; error = nil
        task = Task { [weak self] in
            guard let self else { return }
            var ownership: BackupLease?
            do {
                try check()
                if case .password(let password) = rootCredential {
                    guard password.count >= 12, password.utf8.count <= 16384 else { throw Failure.credentials }
                } else if case .recipient(let recipient) = rootCredential { _ = try AgeFileWriter.decodeRecipient(recipient) }
                let records = try mount.container.mainContext.fetch(FetchDescriptor<VaultAlbum>())
                // Copy the hierarchy before awaiting; never fault models after a revoked mount.
                let topology = try records.map { album -> AlbumRow in
                    guard let policy = AlbumProtection(rawValue: album.protectionRawValue) else { throw Failure.unavailable }
                    return .init(id: album.id, parentID: album.parentID, name: album.name, policy: policy)
                }
                var prepared = Set<UUID>(), pending = topology
                while !pending.isEmpty {
                    let available = pending.filter { $0.parentID == nil || prepared.contains($0.parentID!) }
                    guard !available.isEmpty else { throw Failure.unavailable }
                    for row in available {
                        try check()
                        guard let album = records.first(where: { $0.id == row.id }) else { throw Failure.changed }
                        if row.policy == .faceIDOnly {
                            guard consent.contains(row.id), let password = passwords[row.id], password.count >= 12 else { throw Failure.credentials }
                            try await self.albums.unlock(album, useBiometrics: true, albums: records)
                        } else {
                            guard row.policy == .inherited || !(passwords[row.id] ?? "").isEmpty else { throw Failure.credentials }
                            try await self.albums.unlock(album, password: passwords[row.id], albums: records)
                        }
                        try check(); prepared.insert(row.id)
                    }
                    pending.removeAll { prepared.contains($0.id) }
                }
                let collector = PortableExportSnapshotService(mounts: mounts, authority: authority,
                    albums: self.albums, storage: self.storage, isOwner: { auth.isAuthenticated && GuestModeManager.shared.isOwnerMode && auth.librarySessionID == request.sessionID })
                let snapshot = try collector.capture(request, approvedBiometricAlbums: consent)
                var credentials: [PortableExportSnapshot.DomainID: AgeFileWriter.Credential] = [.root: rootCredential]
                for row in topology where row.policy != .inherited {
                    guard let password = passwords[row.id] else { throw Failure.credentials }
                    credentials[.album(row.id)] = .password(password)
                }
                guard let key = auth.sessionPassword else { throw Failure.unavailable }
                let plan = try BackupPlanFactory.make(snapshot: snapshot, rootKey: key, albumStore: self.albums,
                    albums: records, credentials: credentials)
                try check(); try collector.validateAuthorization(snapshot)
                let root = Self.jobRoot
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                var resource = root
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try resource.setResourceValues(values)
                let folder = root.appendingPathComponent(id.uuidString)
                let lease = BackupLease(); self.lease = lease; ownership = lease
                let running = Task.detached(priority: .userInitiated) { [weak self] in
                    try BackupArchiveBuilder.build(plan, directory: folder, lease: lease, progress: { done, total in
                        Task { @MainActor [weak self] in
                            guard let self, self.token == id, self.isWorking else { return }
                            self.progress = Double(done) / Double(max(1, total))
                        }
                    })
                }
                worker = running
                let output = try await withTaskCancellationHandler { try await running.value } onCancel: { lease.cancel(); running.cancel() }
                try check(); try collector.validateUnchanged(snapshot)
                let leftovers = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                guard leftovers.count == 1, leftovers[0].standardizedFileURL == output.standardizedFileURL else { throw Failure.unavailable }
                let final = folder.appendingPathComponent("WagLock-Backup.tar.age")
                guard link(output.path, final.path) == 0 else { throw Failure.unavailable }
                try FileManager.default.removeItem(at: output)
                readyURL = final; directory = folder; ownership = nil
                worker = nil; self.lease = nil; isWorking = false; progress = 1
            } catch {
                if let owned = ownership?.ownedDirectory { BackupCleanup.remove(owned) }
                guard self.token == id else { return }
                worker = nil; self.lease = nil; isWorking = false
                if error is CancellationError { self.error = "Backup stopped. Unlock and start again." }
                else if case BackupArchiveBuilder.Failure.lowSpace = error { self.error = "There is not enough free space to prepare this backup. Your library is unchanged." }
                else if case BackupArchiveBuilder.Failure.legacyFileTooLarge = error { self.error = "An older large file needs a streaming recovery adapter before a complete backup can be made. Nothing was exported." }
                else { self.error = "Unable to create the complete backup. Check every album password, use different passwords for protected parent and child albums, and try again. Nothing was exported." }
            }
        }
    }

    nonisolated static func exportFilename(_ text: String) -> String? {
        var base = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [".tar.age", ".age", ".tar"] where base.lowercased().hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count)); break
        }
        guard !base.isEmpty, !base.hasPrefix("."), base.utf8.count <= 200,
              !base.contains("/"), !base.contains("\\"), !base.contains(":"),
              !base.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return base + ".tar.age"
    }

    func beginHandoff(filename: String = "WagLock-Backup") -> URL? {
        guard !isWorking, !handingOff, let current = readyURL, let directory else { return nil }
        guard let name = Self.exportFilename(filename) else {
            self.error = "Choose a shorter filename without slashes, colons or line breaks."; return nil
        }
        let readyURL = directory.appendingPathComponent(name)
        if readyURL.path != current.path {
            guard link(current.path, readyURL.path) == 0 else {
                self.error = "Unable to name this backup. Choose another filename and try again."; return nil
            }
            do { try FileManager.default.removeItem(at: current) }
            catch {
                try? FileManager.default.removeItem(at: readyURL)
                self.error = "Unable to name this backup. Try again."; return nil
            }
            self.readyURL = readyURL
        }
        // Only verified ciphertext remains. Let the system finish its copy after locking;
        // plaintext preparation continues to require complete file protection.
        #if os(iOS)
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: readyURL.path)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        } catch { self.error = "Unable to hand this encrypted copy to Files. Try again."; return nil }
        #endif
        error = nil; handingOff = true
        return readyURL
    }
    func finishHandoff() { handingOff = false; cancel() }
    func cancel() {
        guard !handingOff else { return } // Immutable ciphertext already handed to the system picker.
        token = UUID(); lease?.cancel(); task?.cancel(); worker?.cancel()
        task = nil; worker = nil; lease = nil; isWorking = false; progress = 0; readyURL = nil
        if let directory { BackupCleanup.remove(directory) }
        directory = nil
    }
    static func retryCleanup() { BackupCleanup.retry() }
    nonisolated static var jobRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("WagLockBackupJobs", isDirectory: true) }
    nonisolated static func cleanupAbandonedJobs() { try? FileManager.default.removeItem(at: jobRoot) }
}

/// Retries only paths whose job actually created them; never scans the media library.
@MainActor
private enum BackupCleanup {
    private static var pending = Set<URL>()
    static func remove(_ url: URL) {
        do { try FileManager.default.removeItem(at: url); pending.remove(url) }
        catch {
            if FileManager.default.fileExists(atPath: url.path) { pending.insert(url) }
            else { pending.remove(url) }
        }
    }
    static func retry() { for url in pending { remove(url) } }
}
