import Darwin
import Foundation

/// Removes one deleted library's files and Keychain services after its slot was
/// crypto-erased, so everything left behind is already unreadable. Only that library's
/// exact roots and namespaces are touched; other libraries, backups, Photos, Files,
/// the Dev identity and unknown paths are never enumerated or removed.
@MainActor
enum LibraryContentRemover {
    struct Plan: Equatable {
        let roots: [URL]
        let services: [String]
        let recreate: [URL]
    }

    static func plan(for library: LibraryReference, namespace: String,
                     documents: URL, support: URL) -> Plan {
        switch library {
        case .independent(let id):
            let name = id.uuidString
            let libraries = support.appendingPathComponent("WagLockSecondaryLibraries", isDirectory: true)
            return Plan(roots: [
                documents.appendingPathComponent("WagLockSecondaryMedia", isDirectory: true)
                    .appendingPathComponent(name, isDirectory: true),
                libraries.appendingPathComponent(name, isDirectory: true),
                libraries.appendingPathComponent(name + ".creating", isDirectory: true),
            ], services: ["", ".album-biometrics", ".album-attempts"].map { namespace + ".vault." + name + $0 },
               recreate: [])
        case .legacyOwner:
            let media = documents.appendingPathComponent("EncryptedMedia", isDirectory: true)
            return Plan(roots: [
                media,
                support.appendingPathComponent("WagLockVault", isDirectory: true),
                support.appendingPathComponent("WagLockVault.creating", isDirectory: true),
            ], services: [namespace + ".album-attempts"], recreate: [media])
        }
    }

    static func remove(_ library: LibraryReference, namespace: String,
                       keychain: (any VaultResetKeychain)? = nil, reserve: StorageReserve? = nil) {
        let keychain = keychain ?? SystemVaultResetKeychain()
        let reserve = reserve ?? .shared
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
        let plan = plan(for: library, namespace: namespace, documents: documents, support: support)
        for service in plan.services { try? keychain.remove(service: service) }
        let roots = plan.roots, recreate = plan.recreate
        Task.detached(priority: .utility) {
            for root in roots {
                var attributes = stat()
                guard lstat(root.path, &attributes) == 0, (try? FreshEncryptedLibrary.safe(root)) != nil else { continue }
                try? FileManager.default.removeItem(at: root)
            }
            for directory in recreate {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
            }
            // Fixed-size storage: the freed space goes back into the reserve, so WagLock's
            // size doesn't drop and show that a library was deleted (ADR-030).
            reserve.invalidateUsage()
            NotificationCenter.default.post(name: .wagLockStorageChanged, object: nil)
        }
    }
}
