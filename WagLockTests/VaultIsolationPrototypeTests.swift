import Foundation
import Testing

@testable import WagLock

@MainActor
@Suite(.serialized)
struct VaultIsolationPrototypeTests {
    private typealias Store = VaultIsolationPrototype
    private let firstPassword = "first-disposable-passcode"
    private let secondPassword = "second-disposable-passcode"

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vault-isolation-" + UUID().uuidString)
            .resolvingSymlinksInPath()
    }

    private func importSample(_ store: Store, _ context: Store.Context, name: String = "private-name-uniquely-sensitive") async throws -> Store.Reference {
        try await store.importAsset(name: name, albumPath: ["Sensitive parent", "Sensitive child"],
                                    thumbnail: Data("private-thumbnail-unique".utf8), note: "private-note-unique", in: context) {
            Data("original-media-bytes-unique".utf8)
        }
    }

    @Test func twoPopulatedVaultsKeepMetadataSettingsAndContentSeparateAcrossReopen() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        let first = try store.provision(password: firstPassword)
        let second = try store.provision(password: secondPassword)
        #expect(first != second)
        let a = try store.unlock(password: firstPassword)
        let reference = try await importSample(store, a)
        try store.setSetting("first-theme-secret", for: "theme", in: a)
        #expect(try store.entries(in: a).count == 1) // populate the cache before revocation
        let b = try store.unlock(password: secondPassword)
        #expect(a.cachedEntriesForTesting == nil)
        #expect(throws: Store.Failure.locked) { try store.entries(in: a) }
        #expect(try store.entries(in: b).isEmpty)
        #expect(try store.settings(in: b).isEmpty)
        let other = try await importSample(store, b, name: "different-private-name")
        try store.setSetting("second-theme-secret", for: "theme", in: b)
        #expect(throws: Store.Failure.wrongDomain) { try store.exportAsset(reference, in: b) }
        #expect(throws: Store.Failure.wrongDomain) { try store.deleteAsset(reference, in: b) }
        #expect(try store.exportAsset(other, in: b) == Data("original-media-bytes-unique".utf8))
        store.lock()
        let reopened = try Store(root: root)
        let restored = try reopened.unlock(password: firstPassword)
        #expect(try reopened.settings(in: restored)["theme"] == "first-theme-secret")
        #expect(try reopened.entries(in: restored).first?.albumPath == ["Sensitive parent", "Sensitive child"])
        #expect(try reopened.entries(in: restored).first?.note == "private-note-unique")
        #expect(try reopened.exportAsset(reference, in: restored) == Data("original-media-bytes-unique".utf8))
        let secondary = try reopened.unlock(password: secondPassword)
        try reopened.deleteAsset(other, in: secondary)
        #expect(try reopened.entries(in: secondary).isEmpty)
        let primary = try reopened.unlock(password: firstPassword)
        #expect(try reopened.exportAsset(reference, in: primary) == Data("original-media-bytes-unique".utf8))
    }

    @Test func noNamesNotesThumbnailsSettingsOrOriginalBytesAppearInPersistentFiles() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        _ = try store.provision(password: firstPassword)
        let context = try store.unlock(password: firstPassword)
        _ = try await importSample(store, context)
        try store.setSetting("private-theme-value-unique", for: "theme", in: context)
        store.lock()
        let secrets = ["private-name-uniquely-sensitive", "Sensitive parent", "private-note-unique",
                       "private-thumbnail-unique", "original-media-bytes-unique", "private-theme-value-unique", firstPassword]
        for file in try regularFiles(root) {
            let data = try Data(contentsOf: file)
            for secret in secrets {
                #expect(data.range(of: Data(secret.utf8)) == nil)
                #expect(!file.path.contains(secret))
            }
        }
    }

    @Test func duplicatePasscodesAreRejectedAndWrongPasscodeHasGenericFailure() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        _ = try store.provision(password: firstPassword)
        #expect(throws: Store.Failure.duplicatePassword) { try store.provision(password: firstPassword) }
        #expect(throws: Store.Failure.authentication) { try store.unlock(password: "wrong-passcode") }
        _ = try store.provision(password: secondPassword)
        #expect(throws: Store.Failure.authentication) { try store.unlock(password: "wrong-passcode") }
    }

    @Test func contextCannotBeUsedByAnotherStoreInstanceEvenForTheSameRoot() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        _ = try store.provision(password: firstPassword)
        let context = try store.unlock(password: firstPassword)
        let another = try Store(root: root)
        #expect(throws: Store.Failure.wrongDomain) { try another.entries(in: context) }
    }

    @Test func swappedVaultCiphertextCannotDecryptUnderTheOtherRandomKey() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        _ = try store.provision(password: firstPassword)
        _ = try store.provision(password: secondPassword)
        let a = try store.unlock(password: firstPassword)
        let first = try await importSample(store, a)
        let b = try store.unlock(password: secondPassword)
        let second = try await importSample(store, b)
        // Inspect only our disposable key envelopes, independently of context routing.
        let firstKey = try fixtureKey(first.vaultID, password: firstPassword, root: root)
        let secondKey = try fixtureKey(second.vaultID, password: secondPassword, root: root)
        #expect(firstKey != secondKey)
        #expect(Data(base64Encoded: firstKey)?.count == 32)
        #expect(Data(base64Encoded: secondKey)?.count == 32)
        let ciphertext = try Data(contentsOf: asset(first, root: root))
        #expect(throws: (any Error).self) {
            try EncryptionService.shared.decrypt(encryptedData: ciphertext, password: secondKey)
        }
        try ciphertext.write(to: asset(second, root: root))
        #expect(throws: (any Error).self) { try store.exportAsset(second, in: b) }
    }

    @Test func swappedAssetsWithinOneVaultFailAuthenticatedIdentityChecks() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        _ = try store.provision(password: firstPassword)
        let context = try store.unlock(password: firstPassword)
        let first = try await importSample(store, context)
        let second = try await importSample(store, context)
        try Data(contentsOf: asset(first, root: root)).write(to: asset(second, root: root))
        #expect(throws: Store.Failure.corrupt) { try store.exportAsset(second, in: context) }
    }

    @Test func swappedIndexFailsBeforeAContextIsPublished() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        let first = try store.provision(password: firstPassword)
        let second = try store.provision(password: secondPassword)
        try Data(contentsOf: root.appendingPathComponent(first.uuidString + "/index.enc"))
            .write(to: root.appendingPathComponent(second.uuidString + "/index.enc"))
        #expect(throws: Store.Failure.authentication) { try store.unlock(password: secondPassword) }
        #expect(try store.unlock(password: firstPassword).vaultID == first)
    }

    @Test func symlinkAssetCannotReadOrDeleteOutsideTheVault() async throws {
        let root = root()
        let outside = root.deletingLastPathComponent().appendingPathComponent("untouched-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try Data("outside-content".utf8).write(to: outside)
        let store = try Store(root: root)
        _ = try store.provision(password: firstPassword)
        let context = try store.unlock(password: firstPassword)
        let reference = try await importSample(store, context)
        let file = asset(reference, root: root)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        #expect(throws: Store.Failure.unsafePath) { try store.exportAsset(reference, in: context) }
        #expect(throws: Store.Failure.unsafePath) { try store.deleteAsset(reference, in: context) }
        #expect(try Data(contentsOf: outside) == Data("outside-content".utf8))
        #expect(try store.entries(in: context).count == 1)
    }

    @Test func lateImportCannotCommitAfterSwitchOrAfterReloginToTheSameVault() async throws {
        for sameVault in [false, true] {
            let root = root()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try Store(root: root)
            _ = try store.provision(password: firstPassword)
            _ = try store.provision(password: secondPassword)
            let original = try store.unlock(password: firstPassword)
            let gate = PrototypeImportGate()
            let task = Task {
                try await store.importAsset(name: "late", albumPath: [], thumbnail: Data(), note: "", in: original) {
                    await gate.pause()
                    return Data("late data".utf8)
                }
            }
            try await gate.waitUntilStarted()
            let current = try store.unlock(password: sameVault ? firstPassword : secondPassword)
            gate.resume()
            do { _ = try await task.value; Issue.record("Stale import committed") }
            catch { #expect(error as? Store.Failure == .locked) }
            #expect(try store.entries(in: current).isEmpty)
            #expect(try store.entries(in: store.unlock(password: firstPassword)).isEmpty)
            #expect(try encryptedAssets(root).isEmpty)
        }
    }

    @Test func cancelledImportCreatesNoFilesAndDoesNotInvalidateCurrentSession() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        _ = try store.provision(password: firstPassword)
        let context = try store.unlock(password: firstPassword)
        let gate = PrototypeImportGate()
        let task = Task {
            try await store.importAsset(name: "cancelled", albumPath: [], thumbnail: Data(), note: "", in: context) {
                await gate.pause(); return Data("cancelled".utf8)
            }
        }
        try await gate.waitUntilStarted()
        task.cancel(); gate.resume()
        do { _ = try await task.value; Issue.record("Cancelled import committed") }
        catch { #expect(error is CancellationError) }
        #expect(try store.entries(in: context).isEmpty)
        #expect(try encryptedAssets(root).isEmpty)
    }

    @Test func failedProvisioningDoesNotChangeExistingVaultOrPublishHalfAVault() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let fault = PrototypeWriterFault()
        let store = try Store(root: root, writer: fault.write)
        _ = try store.provision(password: firstPassword)
        let context = try store.unlock(password: firstPassword)
        let first = try await importSample(store, context)
        fault.failIndex = true
        #expect(throws: PrototypeWriterFault.Failure.injected) { try store.provision(password: secondPassword) }
        fault.failIndex = false
        #expect(throws: Store.Failure.authentication) { try store.unlock(password: secondPassword) }
        let restored = try store.unlock(password: firstPassword)
        #expect(try store.exportAsset(first, in: restored) == Data("original-media-bytes-unique".utf8))
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.filter { UUID(uuidString: $0) != nil }.count == 1)
        #expect(!names.contains { $0.hasPrefix("pending-") })
    }

    @Test func saveFailureCleansOnlyUncommittedFilesAndPreservesUncertainCommits() async throws {
        for afterCommit in [false, true] {
            let root = root()
            defer { try? FileManager.default.removeItem(at: root) }
            let fault = PrototypeWriterFault()
            let store = try Store(root: root, writer: fault.write)
            _ = try store.provision(password: firstPassword)
            let context = try store.unlock(password: firstPassword)
            #expect(try store.entries(in: context).isEmpty)
            fault.failIndex = true
            fault.failAfterWrite = afterCommit
            do { _ = try await importSample(store, context); Issue.record("Injected save succeeded") }
            catch { #expect(error is PrototypeWriterFault.Failure) }
            fault.failIndex = false
            #expect(try store.entries(in: context).count == (afterCommit ? 1 : 0))
            #expect(try encryptedAssets(root).count == (afterCommit ? 1 : 0))
            if let entry = try store.entries(in: context).first {
                #expect(try store.exportAsset(.init(vaultID: context.vaultID, assetID: entry.id), in: context)
                        == Data("original-media-bytes-unique".utf8))
            }
        }
    }

    @Test func missingStoreMarkerNeverReinitializesAnExistingVault() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        _ = try store.provision(password: firstPassword)
        let context = try store.unlock(password: firstPassword)
        let reference = try await importSample(store, context)
        let marker = root.appendingPathComponent("store.json")
        let saved = try Data(contentsOf: marker)
        try FileManager.default.removeItem(at: marker)
        #expect(throws: Store.Failure.corrupt) { try Store(root: root) }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        try saved.write(to: marker)
        let reopened = try Store(root: root)
        let restored = try reopened.unlock(password: firstPassword)
        #expect(try reopened.exportAsset(reference, in: restored) == Data("original-media-bytes-unique".utf8))
    }

    @Test func secondaryLoginDoesNotOpenPrimaryIndex() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        let first = try store.provision(password: firstPassword)
        let second = try store.provision(password: secondPassword)
        try Data("damaged primary index".utf8).write(to: root.appendingPathComponent(first.uuidString + "/index.enc"))
        let context = try store.unlock(password: secondPassword)
        #expect(context.vaultID == second)
        #expect(try store.entries(in: context).isEmpty)
        #expect(throws: Store.Failure.authentication) { try store.unlock(password: firstPassword) }
    }

    @Test func oversizedImportIsRejectedWithoutPublishingAnAsset() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        _ = try store.provision(password: firstPassword)
        let context = try store.unlock(password: firstPassword)
        do {
            _ = try await store.importAsset(name: "large", albumPath: [], thumbnail: Data(), note: "", in: context) {
                Data(repeating: 42, count: Store.maxBufferSize + 1)
            }
            Issue.record("Oversized import succeeded")
        } catch { #expect(error as? Store.Failure == .tooLarge) }
        #expect(try store.entries(in: context).isEmpty)
        #expect(try encryptedAssets(root).isEmpty)
    }

    @Test func diskFullAtCatalogCommitPreservesExistingDataAndRemovesOnlyNewOutput() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let fault = PrototypeWriterFault()
        let store = try Store(root: root, writer: fault.write)
        _ = try store.provision(password: firstPassword)
        let context = try store.unlock(password: firstPassword)
        let existing = try await importSample(store, context)
        fault.failIndex = true
        fault.injectedError = CocoaError(.fileWriteOutOfSpace)
        do { _ = try await importSample(store, context); Issue.record("Disk-full import succeeded") }
        catch { #expect((error as? CocoaError)?.code == .fileWriteOutOfSpace) }
        fault.failIndex = false
        #expect(try encryptedAssets(root).count == 1)
        #expect(try store.entries(in: context).count == 1)
        #expect(try store.exportAsset(existing, in: context) == Data("original-media-bytes-unique".utf8))
    }

    @Test func unicodePasscodesNamesAlbumsAndBinaryMediaRoundTripWithoutNormalization() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        let password = "épreuve-密码-7391"
        _ = try store.provision(password: password)
        let context = try store.unlock(password: password)
        let name = "家庭–café📷.heic"
        let albums = ["私密", "Ångström"]
        let original = Data([0, 255, 0, 1, 128])
        let reference = try await store.importAsset(name: name, albumPath: albums, thumbnail: Data([0, 200]),
                                                   note: "cafe\u{301}", in: context) { original }
        store.lock()
        let fresh = try Store(root: root)
        let restored = try fresh.unlock(password: password)
        let entry = try #require(fresh.entries(in: restored).first)
        #expect(Array(entry.name.utf8) == Array(name.utf8))
        #expect(entry.albumPath == albums)
        #expect(Array(entry.note.utf8) == Array("cafe\u{301}".utf8))
        #expect(try fresh.exportAsset(reference, in: restored) == original)
    }

    private func fixtureKey(_ id: UUID, password: String, root: URL) throws -> String {
        let bytes = try Data(contentsOf: root.appendingPathComponent(id.uuidString + "/key.enc"))
        let plaintext = try EncryptionService.shared.decrypt(encryptedData: bytes, password: password)
        let object = try #require(JSONSerialization.jsonObject(with: plaintext) as? [String: Any])
        let encoded = try #require(object["payload"] as? String)
        let secret = try #require(Data(base64Encoded: encoded))
        return try #require(String(data: secret, encoding: .utf8))
    }

    private func regularFiles(_ root: URL) throws -> [URL] {
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        return try files.compactMap { $0 as? URL }.filter {
            try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }
    }

    private func asset(_ reference: Store.Reference, root: URL) -> URL {
        root.appendingPathComponent(reference.vaultID.uuidString).appendingPathComponent(reference.assetID.uuidString + ".enc")
    }

    private func encryptedAssets(_ root: URL) throws -> [URL] {
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return files.compactMap { $0 as? URL }.filter { $0.pathExtension == "enc" && !["key.enc", "index.enc"].contains($0.lastPathComponent) }
    }
}

@MainActor
private final class PrototypeWriterFault {
    enum Failure: Error { case injected }
    var failIndex = false
    var injectedError: any Error = Failure.injected
    var failAfterWrite = false
    func write(_ data: Data, _ url: URL) throws {
        let fail = failIndex && url.lastPathComponent == "index.enc"
        if fail && !failAfterWrite { throw injectedError }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        if fail { throw injectedError }
    }
}

@MainActor
private final class PrototypeImportGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false
    func pause() async { await withCheckedContinuation { continuation = $0; started = true } }
    func waitUntilStarted() async throws {
        let deadline = Date().addingTimeInterval(5)
        while !started && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        #expect(started)
    }
    func resume() { continuation?.resume(); continuation = nil }
}
