import Foundation
import CryptoKit
import ImageIO
import Security
import SwiftData
import UIKit
internal import Combine

private struct AlbumKeyMaterial: Codable {
    let albumID: UUID
    let secret: String
}

@MainActor
final class AlbumStore: ObservableObject {
    nonisolated deinit {}
    static let shared = AlbumStore()
    @Published private(set) var revision = 0
    private var vaultKey: SecureBytes?
    private var albumKeys: [UUID: SecureBytes] = [:]
    private var generation = UUID()
    private let biometrics: any BiometricSecretStoring
    private let attemptStorage: any KeychainStorage
    private let attemptNow: () -> Date
    private let crypto = EncryptionService.shared
    private let storage: FileStorageService
    private let mediaLoader: MediaLoaderService
    private let thumbnails: ThumbnailImageLoader

    init(biometrics: any BiometricSecretStoring = BiometricSecretStore.shared,
         attemptStorage: (any KeychainStorage)? = nil, attemptNow: @escaping () -> Date = Date.init,
         storage: FileStorageService = .shared, mediaLoader: MediaLoaderService = .shared,
         thumbnails: ThumbnailImageLoader = .shared) {
        self.storage = storage
        self.mediaLoader = mediaLoader
        self.thumbnails = thumbnails
        self.biometrics = biometrics
        self.attemptStorage = attemptStorage ?? SystemKeychainStorage(service: AppConstants.bundleIdentifier + ".album-attempts")
        self.attemptNow = attemptNow
    }

    /// Called once at process startup, before any live album import or preview exists.
    static func removeAbandonedTemporaryFiles() {
        let root = FileManager.default.temporaryDirectory
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for url in entries {
            let prefixes = ["WagLockAlbumImport-", "WagLockAlbumPreview-"]
            guard let prefix = prefixes.first(where: { url.lastPathComponent.hasPrefix($0) }),
                  UUID(uuidString: String(url.lastPathComponent.dropFirst(prefix.count))) != nil,
                  (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func beginSession(vaultSecret: String) {
        endSession()
        vaultKey = SecureBytes(vaultSecret)
    }

    func endSession() {
        generation = UUID()
        vaultKey?.wipe()
        vaultKey = nil
        for key in albumKeys.values { key.wipe() }
        albumKeys.removeAll()
        revision += 1
    }

    func isUnlocked(_ album: VaultAlbum, albums: [VaultAlbum]) -> Bool {
        guard vaultKey != nil, albumKeys[album.id] != nil else { return false }
        return (try? parentKey(for: album, albums: albums)) != nil
    }

    private func parentKey(for album: VaultAlbum, albums: [VaultAlbum]) throws -> String {
        guard let vaultSecret = vaultKey?.string else { throw VaultAccessError.locked }
        var visited: Set<UUID> = [album.id]
        var parentID = album.parentID
        var immediateKey: String?
        while let id = parentID {
            guard visited.insert(id).inserted,
                  let parent = albums.first(where: { $0.id == id }) else {
                throw VaultAccessError.invalidAlbum
            }
            guard let key = albumKeys[id]?.string else { throw VaultAccessError.locked }
            if immediateKey == nil { immediateKey = key }
            parentID = parent.parentID
        }
        return immediateKey ?? vaultSecret
    }

    private func key(for album: VaultAlbum, albums: [VaultAlbum]) throws -> String {
        _ = try parentKey(for: album, albums: albums)
        guard let key = albumKeys[album.id]?.string else { throw VaultAccessError.locked }
        return key
    }

    static func randomSecret() throws -> String {
        var data = Data(count: 32)
        let status = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw VaultAccessError.invalidData }
        return data.base64EncodedString()
    }

    func create(name: String, parent: VaultAlbum?, protection: AlbumProtection,
                password: String, albums: [VaultAlbum], context: ModelContext) async throws -> VaultAlbum {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { throw VaultAccessError.invalidAlbum }
        guard !protection.requiresPassword || KeychainService.validatePasswordStrength(password).isValid else {
            throw VaultAccessError.invalidPassword
        }
        let parentSecret: String
        if let parent {
            parentSecret = try key(for: parent, albums: albums)
        } else {
            guard let value = vaultKey?.string else { throw VaultAccessError.locked }
            parentSecret = value
        }
        let id = UUID()
        let biometricAccount = UUID().uuidString
        let token = generation
        let secret = try Self.randomSecret()
        let factor = protection == .faceIDOnly ? try Self.randomSecret() : password
        var envelope = try JSONEncoder().encode(AlbumKeyMaterial(albumID: id, secret: secret))
        if protection != .inherited {
            envelope = try PasswordEnvelope.seal(envelope, password: factor, context: "album:" + id.uuidString)
        }
        let wrappedKey = try crypto.encrypt(data: envelope, password: parentSecret)
        let catalog = try crypto.encrypt(data: JSONEncoder().encode([AlbumAsset]()), password: secret)
        if protection.usesBiometrics {
            try await biometrics.store(factor, account: biometricAccount)
        }
        do {
            guard generation == token else { throw CancellationError() }
            if let parent { _ = try key(for: parent, albums: albums) }
            let album = VaultAlbum(id: id, parentID: parent?.id, name: name,
                                   protection: protection, wrappedKey: wrappedKey, encryptedCatalog: catalog,
                                   biometricAccount: protection.usesBiometrics ? biometricAccount : nil)
            context.insert(album)
            do { try LibraryWriteCoordinator.save(context) } catch { context.delete(album); throw error }
            albumKeys[id] = SecureBytes(secret)
            revision += 1
            return album
        } catch {
            if protection.usesBiometrics, LibraryWriteCoordinator.mayDiscardUncommittedResources(in: context) { biometrics.remove(account: biometricAccount) }
            throw error
        }
    }

    func unlock(_ album: VaultAlbum, password: String? = nil, useBiometrics: Bool = false,
                albums: [VaultAlbum]) async throws {
        guard let protection = AlbumProtection(rawValue: album.protectionRawValue) else {
            throw VaultAccessError.invalidAlbum
        }
        let parentSecret = try parentKey(for: album, albums: albums)
        let token = generation
        var factor = password
        if useBiometrics {
            guard protection.usesBiometrics else { throw VaultAccessError.invalidAlbum }
            guard let account = album.biometricAccount else { throw VaultAccessError.invalidData }
            factor = try await biometrics.read(account: account, reason: "Unlock this album")
        }
        guard token == generation else { throw CancellationError() }
        _ = try parentKey(for: album, albums: albums)
        let limiter = PasswordAttemptLimiter(storage: attemptStorage, scope: album.id.uuidString, now: attemptNow)
        let reservation: PasswordAttemptLimiter.Reservation?
        if protection.requiresPassword && !useBiometrics {
            guard factor != nil else { throw VaultAccessError.locked }
            reservation = try limiter.reserve()
        } else { reservation = nil }
        var envelope = try crypto.decrypt(encryptedData: album.wrappedKey, password: parentSecret)
        if protection != .inherited {
            guard let factor, protection != .faceIDOnly || useBiometrics else { throw VaultAccessError.locked }
            do { envelope = try PasswordEnvelope.open(envelope, password: factor, context: "album:" + album.id.uuidString) }
            catch { throw VaultAccessError.invalidPassword }
        }
        let material = try JSONDecoder().decode(AlbumKeyMaterial.self, from: envelope)
        guard material.albumID == album.id else { throw VaultAccessError.invalidData }
        let secret = material.secret
        // Validate catalog before granting access; an invalid wrapper never creates an unlocked session.
        _ = try JSONDecoder().decode([AlbumAsset].self, from: crypto.decrypt(
            encryptedData: album.encryptedCatalog, password: secret))
        if let reservation { try limiter.recordSuccess(reservation) }
        albumKeys[album.id]?.wipe()
        albumKeys[album.id] = SecureBytes(secret)
        revision += 1
    }

    func lock(_ album: VaultAlbum, albums: [VaultAlbum]) {
        // Invalidate all pending requests, including reads of descendants.
        generation = UUID()
        var ids: Set<UUID> = [album.id]
        var changed = true
        while changed {
            changed = false
            for candidate in albums where candidate.parentID.map(ids.contains) == true {
                if ids.insert(candidate.id).inserted { changed = true }
            }
        }
        for id in ids { albumKeys.removeValue(forKey: id)?.wipe() }
        revision += 1
    }

    func changeProtection(of album: VaultAlbum, to protection: AlbumProtection,
                          password: String, albums: [VaultAlbum], context: ModelContext) async throws {
        let secret = try key(for: album, albums: albums)
        let parentSecret = try parentKey(for: album, albums: albums)
        guard !protection.requiresPassword || KeychainService.validatePasswordStrength(password).isValid else {
            throw VaultAccessError.invalidPassword
        }
        let token = generation
        let factor = protection == .faceIDOnly ? try Self.randomSecret() : password
        var envelope = try JSONEncoder().encode(AlbumKeyMaterial(albumID: album.id, secret: secret))
        if protection != .inherited { envelope = try PasswordEnvelope.seal(envelope, password: factor, context: "album:" + album.id.uuidString) }
        let wrapped = try crypto.encrypt(data: envelope, password: parentSecret)
        let account = UUID().uuidString
        if protection.usesBiometrics { try await biometrics.store(factor, account: account) }
        let previous = (album.wrappedKey, album.protectionRawValue, album.biometricAccount)
        do {
            guard token == generation else { throw CancellationError() }
            _ = try key(for: album, albums: albums)
            album.wrappedKey = wrapped
            album.protectionRawValue = protection.rawValue
            album.biometricAccount = protection.usesBiometrics ? account : nil
            do { try LibraryWriteCoordinator.save(context) } catch {
                album.wrappedKey = previous.0
                album.protectionRawValue = previous.1
                album.biometricAccount = previous.2
                throw error
            }
            if let old = previous.2 { biometrics.remove(account: old) }
            lock(album, albums: albums)
        } catch {
            if protection.usesBiometrics, LibraryWriteCoordinator.mayDiscardUncommittedResources(in: context) { biometrics.remove(account: account) }
            throw error
        }
    }

    func assets(in album: VaultAlbum, albums: [VaultAlbum]) throws -> [AlbumAsset] {
        let secret = try key(for: album, albums: albums)
        return try JSONDecoder().decode([AlbumAsset].self, from: crypto.decrypt(
            encryptedData: album.encryptedCatalog, password: secret))
    }

    /// Read capability for the checked backup job. The key is never serialized into an archive.
    func sourceKeyForBackup(albumID: UUID, albums: [VaultAlbum], expectedRevision: Int) throws -> String {
        guard revision == expectedRevision, let album = albums.first(where: { $0.id == albumID }) else {
            throw VaultAccessError.locked
        }
        return try key(for: album, albums: albums)
    }

    /// Snapshot capture must not silently drop catalog fields it cannot preserve.
    /// Normal gallery readers retain their existing compatibility behavior.
    func assetsForPortableSnapshot(in album: VaultAlbum, albums: [VaultAlbum]) throws -> [AlbumAsset] {
        let secret = try key(for: album, albums: albums)
        let data = try crypto.decrypt(encryptedData: album.encryptedCatalog, password: secret)
        guard let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw VaultAccessError.invalidData
        }
        let required: Set<String> = ["id", "fileName", "encryptedPath", "fileSize", "type", "createdAt"]
        let supported = required.union(["thumbnail"])
        for record in records {
            let keys = Set(record.keys)
            guard required.isSubset(of: keys), keys.isSubset(of: supported) else { throw VaultAccessError.invalidData }
        }
        return try JSONDecoder().decode([AlbumAsset].self, from: data)
    }

    @discardableResult
    func importFile(_ url: URL, into album: VaultAlbum, albums: [VaultAlbum], context: ModelContext,
                    originalName: String? = nil) async throws -> AlbumAsset {
        let secret = try key(for: album, albums: albums)
        let token = generation
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = originalName ?? url.lastPathComponent
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let type = MediaType.from(fileExtension: url.pathExtension)
        // Existing streaming reader/writer retained; omit original names from ciphertext paths.
        let storage = self.storage
        let path = try await Task.detached(priority: .userInitiated) {
            try storage.saveEncryptedFile(from: url, password: secret)
        }.value
        do {
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            _ = try key(for: album, albums: albums)
            var thumbnail: Data?
            if type == .photo, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 300,
               ] as CFDictionary) {
                thumbnail = UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
            }
            var catalog = try assets(in: album, albums: albums)
            let asset = AlbumAsset(id: UUID(), fileName: name, encryptedPath: path,
                                   fileSize: Int64(size), type: type, thumbnail: thumbnail, createdAt: Date())
            catalog.append(asset)
            let encrypted = try crypto.encrypt(data: JSONEncoder().encode(catalog), password: secret)
            let previous = album.encryptedCatalog
            album.encryptedCatalog = encrypted
            do { try LibraryWriteCoordinator.save(context) } catch { album.encryptedCatalog = previous; throw error }
            revision += 1
            return asset
        } catch {
            if LibraryWriteCoordinator.mayDiscardUncommittedResources(in: context) {
                try? storage.deleteFile(path: path)
            }
            throw error
        }
    }

    func preview(_ asset: AlbumAsset, in album: VaultAlbum, albums: [VaultAlbum]) async throws -> URL {
        let secret = try key(for: album, albums: albums)
        let catalog = try assets(in: album, albums: albums)
        guard catalog.contains(where: { $0.id == asset.id && $0.encryptedPath == asset.encryptedPath }) else {
            throw VaultAccessError.invalidData
        }
        let token = generation
        let directory = try ProtectedTemporaryFiles.createDirectory()
        let suffix = asset.fileExtension.filter { $0.isLetter || $0.isNumber }
        let url = directory.appendingPathComponent("preview").appendingPathExtension(suffix)
        let source = try storage.getFileURL(for: asset.encryptedPath)
        do {
            try await Task.detached(priority: .userInitiated) {
                try EncryptionService.shared.decryptFile(inputURL: source, to: url, password: secret)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        guard token == generation, isUnlocked(album, albums: albums), !Task.isCancelled else {
            try? FileManager.default.removeItem(at: directory)
            throw CancellationError()
        }
        return url
    }

    func moveFromLibrary(_ media: MediaItem, into album: VaultAlbum,
                         albums: [VaultAlbum], context: ModelContext) async throws {
        guard let root = vaultKey?.string else { throw VaultAccessError.locked }
        _ = try key(for: album, albums: albums)
        let token = generation
        let sourcePath = media.encryptedPath
        let source = try await storage.createDecryptedTempFileAsync(
            path: sourcePath, password: root, preferredExtension: media.fileExtension)
        defer { try? FileManager.default.removeItem(at: source) }
        guard token == generation else { throw CancellationError() }
        let imported = try await importFile(source, into: album, albums: albums,
                                            context: context, originalName: media.fullFileName)
        let verification = try await preview(imported, in: album, albums: albums)
        defer { try? FileManager.default.removeItem(at: verification.deletingLastPathComponent()) }
        let matches = try await Task.detached {
            try Self.fileDigest(source) == Self.fileDigest(verification)
        }.value
        guard matches, token == generation else { throw VaultAccessError.invalidData }
        _ = try key(for: album, albums: albums)
        // Destination is committed and verified before the original record or ciphertext is removed.
        context.delete(media)
        do { try LibraryWriteCoordinator.save(context) } catch { context.rollback(); throw error }
        try? storage.deleteFile(path: sourcePath)
        mediaLoader.clearCache(forPath: sourcePath)
        thumbnails.clearAll()
        revision += 1
    }

    nonisolated private static func fileDigest(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return Data(hash.finalize())
    }

    func delete(_ asset: AlbumAsset, from album: VaultAlbum, albums: [VaultAlbum], context: ModelContext) throws {
        let secret = try key(for: album, albums: albums)
        var catalog = try assets(in: album, albums: albums)
        guard let index = catalog.firstIndex(where: { $0.id == asset.id }) else { throw VaultAccessError.invalidData }
        let removed = catalog.remove(at: index)
        let previous = album.encryptedCatalog
        album.encryptedCatalog = try crypto.encrypt(data: JSONEncoder().encode(catalog), password: secret)
        do { try LibraryWriteCoordinator.save(context) } catch { album.encryptedCatalog = previous; throw error }
        try? storage.deleteFile(path: removed.encryptedPath)
        revision += 1
    }

    func rename(_ album: VaultAlbum, name: String, albums: [VaultAlbum], context: ModelContext) throws {
        _ = try key(for: album, albums: albums)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { throw VaultAccessError.invalidAlbum }
        let previous = album.name
        album.name = name
        do { try LibraryWriteCoordinator.save(context) } catch { album.name = previous; throw error }
        revision += 1
    }

    func deleteEmpty(_ album: VaultAlbum, albums: [VaultAlbum], context: ModelContext) throws {
        _ = try key(for: album, albums: albums)
        guard !albums.contains(where: { $0.parentID == album.id }),
              try assets(in: album, albums: albums).isEmpty else { throw VaultAccessError.albumNotEmpty }
        let account = album.biometricAccount
        lock(album, albums: albums)
        context.delete(album)
        do { try LibraryWriteCoordinator.save(context) } catch { context.rollback(); throw error }
        if let account { biometrics.remove(account: account) }
    }
}
