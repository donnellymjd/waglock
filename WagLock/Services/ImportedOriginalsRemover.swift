import CryptoKit
import Foundation

/// One file the person picked in Files and that WagLock imported and committed.
/// Captured as plain values at commit time; never a live model.
struct ImportedFileSource: Equatable, Sendable {
    let original: URL
    let encryptedPath: String
    let fileExtension: String
}

/// Deletes originals in Files only after the person asks, and only after the encrypted
/// copy in WagLock has been decrypted and found byte-for-byte identical to the original.
/// Anything that can't be checked or deleted is kept. Deletion prefers the provider's
/// Recently Deleted (trash) and falls back to permanent removal, as the confirmation says.
@MainActor
enum ImportedOriginalsRemover {
    struct Outcome: Equatable {
        var deleted = 0
        /// The copy couldn't be verified, or the location doesn't allow deleting.
        var kept = 0
    }

    typealias Decrypt = (_ path: String, _ ext: String) async throws -> URL
    typealias StillAuthorized = () -> Bool

    static func remove(_ sources: [ImportedFileSource], decrypt: Decrypt,
                       stillAuthorized: StillAuthorized) async -> Outcome {
        var outcome = Outcome()
        for source in sources {
            // Lock, background or session change stops at once; the rest is kept.
            guard stillAuthorized(), !Task.isCancelled else {
                outcome.kept += sources.count - outcome.deleted - outcome.kept
                break
            }
            if await removeOne(source, decrypt: decrypt, stillAuthorized: stillAuthorized) {
                outcome.deleted += 1
            } else {
                outcome.kept += 1
            }
        }
        return outcome
    }

    private static func removeOne(_ source: ImportedFileSource, decrypt: Decrypt,
                                  stillAuthorized: StillAuthorized) async -> Bool {
        let scoped = source.original.startAccessingSecurityScopedResource()
        defer { if scoped { source.original.stopAccessingSecurityScopedResource() } }
        guard let originalDigest = try? await digest(of: source.original) else { return false }
        let copy: URL
        do { copy = try await decrypt(source.encryptedPath, source.fileExtension) } catch { return false }
        defer { try? FileManager.default.removeItem(at: copy) }
        guard let copyDigest = try? await digest(of: copy), copyDigest == originalDigest,
              stillAuthorized() else { return false }
        return delete(source.original)
    }

    nonisolated static func digest(of url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                hash.update(data: chunk)
            }
            return Data(hash.finalize())
        }.value
    }

    /// Coordinated delete so file providers (iCloud Drive and others) see it.
    nonisolated static func delete(_ url: URL) -> Bool {
        var coordinationError: NSError?
        var deleted = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            if (try? FileManager.default.trashItem(at: target, resultingItemURL: nil)) != nil {
                deleted = true
            } else if (try? FileManager.default.removeItem(at: target)) != nil {
                deleted = true
            }
        }
        return coordinationError == nil && deleted
    }
}
