import Foundation
import SwiftData
import Testing

@testable import WagLock

@MainActor
@Suite(.serialized)
struct ImportLifecycleTests {
    private func owner() async throws -> (AuthenticationViewModel, KeychainService) {
        let keychain = KeychainService(service: "import-lifecycle-" + UUID().uuidString)
        try keychain.savePassword("fixture-password")
        let auth = AuthenticationViewModel(keychainService: keychain, manageInstallationState: false)
        auth.password = "fixture-password"
        auth.login()
        while auth.isProcessing { try await Task.sleep(for: .milliseconds(1)) }
        #expect(auth.isAuthenticated)
        return (auth, keychain)
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: MediaItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func item() -> MediaItem {
        MediaItem(fileName: "fixture", fileExtension: ".jpg", fileSize: 1, type: .photo,
                  encryptedPath: UUID().uuidString + ".encrypted")
    }

    private func storage() throws -> (FileStorageService, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("import-output-" + UUID().uuidString)
        return (FileStorageService(directory: root, availableCapacity: { _ in Int64.max }), root)
    }

    private func output(in storage: FileStorageService) throws -> MediaItem {
        let data = try EncryptionService.shared.encrypt(data: Data("fixture media".utf8), password: "fixture-password")
        return MediaItem(fileName: "fixture", fileExtension: ".txt", fileSize: 13, type: .document,
                         encryptedPath: try storage.saveEncrypted(data: data))
    }

    @Test
    func databaseFailureRollsBackAndDeletesOnlyUncommittedOutputs() async throws {
        let (auth, keychain) = try await owner()
        let (files, root) = try storage()
        defer { auth.logout(); keychain.clearAllKeychainData(); try? FileManager.default.removeItem(at: root) }
        let db = try container()
        let importer = ImportViewModel(storage: files, saveContext: { _ in throw ImportError.saveFailed })
        importer.authViewModel = auth
        importer.modelContext = db.mainContext
        let fresh = try output(in: files)
        let freshPath = fresh.encryptedPath
        var callbacks = 0
        importer.onImportComplete = { _ in callbacks += 1 }
        await importer.performImport(operation: { _ in [fresh] }, encryptedInput: true)
        #expect(try db.mainContext.fetchCount(FetchDescriptor<MediaItem>()) == 0)
        #expect(!files.fileExists(path: freshPath))
        #expect(importer.errorMessage != nil)
        #expect(importer.importedCount == 0)
        #expect(callbacks == 0)
        #expect(!importer.isImporting)
        #expect(!importer.showEncryptedPasswordInput)
    }

    @Test
    func uncertainSaveOutcomePreservesAnActuallyCommittedFile() async throws {
        let (auth, keychain) = try await owner()
        let (files, root) = try storage()
        defer { auth.logout(); keychain.clearAllKeychainData(); try? FileManager.default.removeItem(at: root) }
        let db = try container()
        let importer = ImportViewModel(storage: files, saveContext: { context in
            try context.save()
            throw ImportError.saveFailed
        })
        importer.authViewModel = auth
        importer.modelContext = db.mainContext
        let fresh = try output(in: files)
        let path = fresh.encryptedPath
        var callbacks = 0
        importer.onImportComplete = { _ in callbacks += 1 }
        await importer.performImport { _ in [fresh] }
        #expect(try ModelContext(db).fetchCount(FetchDescriptor<MediaItem>()) == 1)
        #expect(files.fileExists(path: path))
        #expect(callbacks == 0)
        #expect(importer.errorMessage != nil)
    }

    @Test
    func staleCancelledRunCannotClearANewerImportOrKeepItsFile() async throws {
        let (auth, keychain) = try await owner()
        let (files, root) = try storage()
        defer { auth.logout(); keychain.clearAllKeychainData(); try? FileManager.default.removeItem(at: root) }
        let db = try container()
        let importer = ImportViewModel(storage: files)
        importer.authViewModel = auth
        importer.modelContext = db.mainContext
        let oldGate = PausedImport()
        let newGate = PausedImport()
        let old = try output(in: files)
        let oldPath = old.encryptedPath
        let new = try output(in: files)
        let newPath = new.encryptedPath
        var completed: [UUID] = []
        importer.onImportComplete = { completed.append(contentsOf: $0.map(\.id)) }
        let first = Task { await importer.performImport { _ in await oldGate.pause(); return [old] } }
        try await oldGate.waitUntilStarted()
        importer.cancelImport()
        let second = Task { await importer.performImport { _ in await newGate.pause(); return [new] } }
        try await newGate.waitUntilStarted()
        oldGate.release()
        await first.value
        #expect(importer.isImporting)
        #expect(!files.fileExists(path: oldPath))
        #expect(files.fileExists(path: newPath))
        newGate.release()
        await second.value
        #expect(completed == [new.id])
        #expect(try db.mainContext.fetchCount(FetchDescriptor<MediaItem>()) == 1)
        #expect(!importer.isImporting)
    }

    @Test
    func loggingBackInWithTheSamePasswordDoesNotReviveAnOldImport() async throws {
        let (auth, keychain) = try await owner()
        let (files, root) = try storage()
        defer { auth.logout(); keychain.clearAllKeychainData(); try? FileManager.default.removeItem(at: root) }
        let db = try container()
        let importer = ImportViewModel(storage: files)
        importer.authViewModel = auth
        importer.modelContext = db.mainContext
        let gate = PausedImport()
        let late = try output(in: files)
        let path = late.encryptedPath
        let pending = Task { await importer.performImport { _ in await gate.pause(); return [late] } }
        try await gate.waitUntilStarted()
        auth.logout()
        auth.password = "fixture-password"
        auth.login()
        while auth.isProcessing { try await Task.sleep(for: .milliseconds(1)) }
        gate.release()
        await pending.value
        #expect(auth.isAuthenticated)
        #expect(try db.mainContext.fetchCount(FetchDescriptor<MediaItem>()) == 0)
        #expect(!files.fileExists(path: path))
    }

    @Test
    func missingContextOrOwnerAuthorizationPreventsTheOperation() async throws {
        let (auth, keychain) = try await owner()
        defer { auth.logout(); keychain.clearAllKeychainData() }
        let importer = ImportViewModel()
        importer.authViewModel = auth
        var calls = 0
        await importer.performImport { _ in calls += 1; return [] }
        #expect(calls == 0)
        let db = try container()
        importer.modelContext = db.mainContext
        GuestModeManager.shared.setAuthenticationMode(.guest)
        await importer.performImport { _ in calls += 1; return [] }
        #expect(calls == 0)
        #expect(try db.mainContext.fetchCount(FetchDescriptor<MediaItem>()) == 0)
    }

    @Test
    func successfulImportPublishesOnlyAfterDurableDatabaseSave() async throws {
        let (auth, keychain) = try await owner()
        let (files, root) = try storage()
        defer { auth.logout(); keychain.clearAllKeychainData(); try? FileManager.default.removeItem(at: root) }
        let db = try container()
        let importer = ImportViewModel(storage: files)
        importer.authViewModel = auth
        importer.modelContext = db.mainContext
        let fresh = try output(in: files)
        var callbackCount = 0
        importer.onImportComplete = { items in
            callbackCount += 1
            #expect(items.count == 1)
            #expect((try? ModelContext(db).fetchCount(FetchDescriptor<MediaItem>())) == 1)
            #expect(files.fileExists(path: fresh.encryptedPath))
        }
        await importer.performImport { _ in [fresh] }
        #expect(callbackCount == 1)
        #expect(importer.importedCount == 1)
        #expect(!importer.isImporting)
    }

    @Test
    func batchCancellationDeletesEarlierOutputsWithoutTouchingSource() async throws {
        let (files, root) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MediaImportService(storage: files)
        let source = root.appendingPathComponent("original.txt")
        try Data("keep original".utf8).write(to: source)
        let fresh = try output(in: files)
        let path = fresh.encryptedPath
        do {
            _ = try await service.importBatch([0, 1]) { index in
                if index == 1 { throw CancellationError() }
                return fresh
            }
            Issue.record("Batch cancellation did not propagate")
        } catch is CancellationError { }
        #expect(!files.fileExists(path: path))
        #expect(try Data(contentsOf: source) == Data("keep original".utf8))
    }

    @Test
    func ordinaryItemFailureRetainsSuccessfulSiblings() async throws {
        let (files, root) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MediaImportService(storage: files)
        let fresh = try output(in: files)
        let results = try await service.importBatch([0, 1]) { index in
            if index == 1 { throw ImportError.loadFailed }
            return fresh
        }
        #expect(results.map(\.id) == [fresh.id])
        #expect(files.fileExists(path: fresh.encryptedPath))
    }

    @Test
    func cancellationAfterTheLastBatchOutputStillDiscardsIt() async throws {
        let (files, root) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MediaImportService(storage: files)
        let fresh = try output(in: files)
        let path = fresh.encryptedPath
        let pending = Task {
            _ = try await service.importBatch([0]) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return fresh
            }
        }
        do { _ = try await pending.value; Issue.record("Late batch cancellation was ignored") }
        catch is CancellationError { }
        #expect(!files.fileExists(path: path))
    }

    @Test
    func cancelledImportCannotCommitLateResults() async throws {
        let (auth, keychain) = try await owner()
        defer { auth.logout(); keychain.clearAllKeychainData() }
        let db = try container()
        let importer = ImportViewModel()
        importer.modelContext = db.mainContext
        importer.authViewModel = auth
        let gate = PausedImport()
        let late = item()
        var callbacks = 0
        importer.onImportComplete = { _ in callbacks += 1 }
        let pending = Task { await importer.performImport { _ in await gate.pause(); return [late] } }
        try await gate.waitUntilStarted()
        importer.cancelImport()
        gate.release()
        await pending.value
        #expect(try db.mainContext.fetchCount(FetchDescriptor<MediaItem>()) == 0)
        #expect(callbacks == 0)
        #expect(importer.importedCount == 0)
    }

    @Test
    func cancellingTheEncryptedPasswordSheetRevokesALateImport() async throws {
        let (auth, keychain) = try await owner()
        let (files, root) = try storage()
        defer { auth.logout(); keychain.clearAllKeychainData(); try? FileManager.default.removeItem(at: root) }
        let db = try container()
        let importer = ImportViewModel(storage: files)
        importer.authViewModel = auth
        importer.modelContext = db.mainContext
        importer.showEncryptedPasswordInput = true
        let late = try output(in: files)
        let path = late.encryptedPath
        let gate = PausedImport()
        let pending = Task {
            await importer.performImport(operation: { _ in await gate.pause(); return [late] }, encryptedInput: true)
        }
        try await gate.waitUntilStarted()
        importer.cancelEncryptedFilePasswordInput()
        let cancellationMessage = importer.errorMessage
        gate.release()
        await pending.value
        #expect(try db.mainContext.fetchCount(FetchDescriptor<MediaItem>()) == 0)
        #expect(!files.fileExists(path: path))
        #expect(!importer.showEncryptedPasswordInput)
        #expect(!importer.isImporting)
        #expect(importer.errorMessage == cancellationMessage)
    }

    @Test
    func logoutRevokesAnAlreadyRunningImport() async throws {
        let (auth, keychain) = try await owner()
        defer { auth.logout(); keychain.clearAllKeychainData() }
        let db = try container()
        let importer = ImportViewModel()
        importer.modelContext = db.mainContext
        importer.authViewModel = auth
        let gate = PausedImport()
        let late = item()
        var callbacks = 0
        importer.onImportComplete = { _ in callbacks += 1 }
        let pending = Task { await importer.performImport { _ in await gate.pause(); return [late] } }
        try await gate.waitUntilStarted()
        auth.logout()
        gate.release()
        await pending.value
        #expect(try db.mainContext.fetchCount(FetchDescriptor<MediaItem>()) == 0)
        #expect(callbacks == 0)
        #expect(importer.importedCount == 0)
    }
}

@MainActor
private final class PausedImport {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false

    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
        }
    }

    func waitUntilStarted() async throws {
        let deadline = Date().addingTimeInterval(5)
        while !started, Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        #expect(started)
    }

    func release() { continuation?.resume(); continuation = nil }
}
