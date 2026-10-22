import CryptoKit
import Foundation
import SwiftData
import SQLite3
import Testing
@testable import WagLock

@MainActor
@Suite(.serialized)
struct LegacyMetadataTransitionTests {
    private typealias Snapshot = LegacyMetadataTransitionPrototype
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("metadata-transition-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func domain() -> Snapshot.Domain { .init(libraryID: UUID(), vaultID: UUID()) }
    private func samples(_ count: Int = 3) -> [Snapshot.Record] {
        (0..<count).map { .init(kind: "note", id: UUID(), payload: Data("sensitive-fixture-note-\($0)-家族-café".utf8)) }
    }
    private func recordFiles(_ root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "enc" && $0.lastPathComponent != "manifest.enc" }
    }

    @Test func readOnlyLegacyFixtureRetainsEveryModelFieldAndOriginalDataSecret() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = Bundle(for: RenameCompatibilityTests.self)
        let fixture = try #require(bundle.url(forResource: "legacy-model", withExtension: "sqlite"))
        let source = root.appendingPathComponent("source.store")
        let fixtureBytes = try Data(contentsOf: fixture)
        try FileManager.default.copyItem(at: fixture, to: source)
        // The self-contained fixture retains a WAL-mode header but no sidecars.
        // Prepare only this disposable clone for a genuinely read-only open.
        var sqlite: OpaquePointer?
        guard sqlite3_open_v2(source.path, &sqlite, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(sqlite)
            throw Snapshot.Failure.corrupt
        }
        let journalResult = sqlite3_exec(sqlite, "PRAGMA journal_mode=DELETE", nil, nil, nil)
        sqlite3_close(sqlite)
        #expect(journalResult == SQLITE_OK)
        let original = try Data(contentsOf: source)
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        let configuration = ModelConfiguration(schema: schema, url: source, allowsSave: false)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let records = try Snapshot.capture(context)
        #expect(records.count == 3)
        let output = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let key = SymmetricKey(size: .bits256), domain = domain()
        let legacySecret = Data("retained-synthetic-original-data-key".utf8)
        let published = try Snapshot.stage(records, legacyDataSecret: legacySecret, domain: domain, key: key, outputRoot: output)
        let reader = try Snapshot.Reader(root: published, domain: domain, key: key)
        #expect(try reader.page(offset: 0, limit: 32) == records)
        #expect(try reader.legacyDataSecret() == legacySecret)
        let media = try JSONDecoder().decode(Snapshot.Media.self, from: #require(records.first { $0.kind == "media" }).payload)
        let sourceMedia = try #require(context.fetch(FetchDescriptor<MediaItem>()).first)
        #expect(media == Snapshot.Media(sourceMedia))
        #expect(media.encryptedPath == "retained-original-ciphertext.encrypted")
        #expect(media.thumbnailData == Data([10, 20, 30]))
        #expect(Array(media.fileName.utf8) == Array("家族–café".utf8))
        let note = try JSONDecoder().decode(Snapshot.Note.self, from: #require(records.first { $0.kind == "note" }).payload)
        #expect(note == Snapshot.Note(try #require(context.fetch(FetchDescriptor<SecretNote>()).first)))
        let album = try JSONDecoder().decode(Snapshot.Album.self, from: #require(records.first { $0.kind == "album" }).payload)
        #expect(album == Snapshot.Album(try #require(context.fetch(FetchDescriptor<VaultAlbum>()).first)))
        #expect(album.wrappedKey == Data([40, 50]))
        #expect(album.encryptedCatalog == Data([60, 70]))
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: fixture) == fixtureBytes)
    }

    @Test func thousandRecordSnapshotPagesWithoutDecryptingTheEntireCatalog() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = samples(1_000), key = SymmetricKey(size: .bits256), domain = domain()
        let published = try Snapshot.stage(records, legacyDataSecret: Data([1, 2, 3]), domain: domain, key: key, outputRoot: root)
        let reader = try Snapshot.Reader(root: published, domain: domain, key: key)
        #expect(reader.count == 1_000)
        #expect(reader.decodedRecords == 0)
        #expect(try reader.page(offset: 400, limit: 32) == Array(records[400..<432]))
        #expect(reader.decodedRecords == 32)
        #expect(try reader.page(offset: 999, limit: 32) == [records[999]])
        #expect(try reader.page(offset: 1_000, limit: 32).isEmpty)
        #expect(throws: (any Error).self) { try reader.page(offset: -1, limit: 32) }
        #expect(throws: (any Error).self) { try reader.page(offset: 0, limit: Int.max) }
    }

    @Test func wrongKeysAndWrongVaultOrLibraryBindingsRejectTheManifest() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = SymmetricKey(size: .bits256), domain = domain()
        let published = try Snapshot.stage(samples(), legacyDataSecret: Data([1]), domain: domain, key: key, outputRoot: root)
        #expect(throws: (any Error).self) { try Snapshot.Reader(root: published, domain: domain, key: SymmetricKey(size: .bits256)) }
        let otherVault = Snapshot.Domain(libraryID: domain.libraryID, vaultID: UUID())
        let otherLibrary = Snapshot.Domain(libraryID: UUID(), vaultID: domain.vaultID)
        #expect(throws: (any Error).self) { try Snapshot.Reader(root: published, domain: otherVault, key: key) }
        #expect(throws: (any Error).self) { try Snapshot.Reader(root: published, domain: otherLibrary, key: key) }
    }

    @Test func recordRemovalTruncationAndSubstitutionFailInsteadOfReturningPartialSuccess() throws {
        for mutation in 0..<3 {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let key = SymmetricKey(size: .bits256), domain = domain()
            let published = try Snapshot.stage(samples(), legacyDataSecret: Data([1]), domain: domain, key: key, outputRoot: root)
            let files = try recordFiles(published)
            switch mutation {
            case 0: try FileManager.default.removeItem(at: files[0])
            case 1: try Data([0, 1]).write(to: files[0])
            default: try Data(contentsOf: files[1]).write(to: files[0])
            }
            let reader = try Snapshot.Reader(root: published, domain: domain, key: key)
            #expect(throws: (any Error).self) { try reader.page(offset: 0, limit: 32) }
        }
    }

    @Test func diskFullAndVerificationFailuresRemoveOnlyOwnedStagingFiles() throws {
        for failure in 0..<2 {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let sentinel = root.appendingPathComponent("unknown-existing-file")
            try Data([9, 8, 7]).write(to: sentinel)
            var writes = 0
            #expect(throws: (any Error).self) {
                try Snapshot.stage(samples(), legacyDataSecret: Data([1]), domain: domain(), key: SymmetricKey(size: .bits256), outputRoot: root) { data, url in
                    writes += 1
                    if failure == 0 && writes == 2 { throw CocoaError(.fileWriteOutOfSpace) }
                    let bytes = failure == 1 && writes == 1 ? Data([0, 1]) : data
                    try bytes.write(to: url, options: [.atomic])
                }
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [sentinel.lastPathComponent])
            #expect(try Data(contentsOf: sentinel) == Data([9, 8, 7]))
        }
    }

    @Test func reportedFailureAfterPublicationPreservesTheVerifiedEncryptedCopy() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = SymmetricKey(size: .bits256), domain = domain(), records = samples()
        #expect(throws: (any Error).self) {
            try Snapshot.stage(records, legacyDataSecret: Data([3]), domain: domain, key: key, outputRoot: root,
                               publish: { source, destination in
                try FileManager.default.moveItem(at: source, to: destination)
                throw CocoaError(.fileWriteUnknown)
            })
        }
        let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        #expect(children.count == 1)
        let reader = try Snapshot.Reader(root: #require(children.first), domain: domain, key: key)
        #expect(try reader.page(offset: 0, limit: 32) == records)
    }

    @Test func noKnownMetadataOrRetainedSecretIsWrittenInPlaintextAndReaderLockRevokesAccess() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = SymmetricKey(size: .bits256), domain = domain()
        let secret = Data("retained-legacy-secret-distinct".utf8)
        let published = try Snapshot.stage(samples(), legacyDataSecret: secret, domain: domain, key: key, outputRoot: root)
        for file in try FileManager.default.contentsOfDirectory(at: published, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: file)
            #expect(bytes.range(of: secret) == nil)
            #expect(bytes.range(of: Data("sensitive-fixture-note".utf8)) == nil)
            #expect(bytes.range(of: Data("家族".utf8)) == nil)
        }
        let reader = try Snapshot.Reader(root: published, domain: domain, key: key)
        _ = try reader.page(offset: 0, limit: 1)
        reader.lock()
        #expect(reader.count == nil)
        #expect(throws: Snapshot.Failure.self) { try reader.page(offset: 0, limit: 1) }
        #expect(throws: Snapshot.Failure.self) { try reader.legacyDataSecret() }
    }

    @Test func duplicateRecordsOversizedPayloadsAndSymlinkRootsAreRejected() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sample = try #require(samples(1).first)
        let key = SymmetricKey(size: .bits256), domain = domain()
        #expect(throws: Snapshot.Failure.self) {
            try Snapshot.stage([sample, sample], legacyDataSecret: Data(), domain: domain, key: key, outputRoot: root)
        }
        let large = Snapshot.Record(kind: "note", id: UUID(), payload: Data(repeating: 0, count: Snapshot.maxRecordBytes + 1))
        #expect(throws: Snapshot.Failure.self) {
            try Snapshot.stage([large], legacyDataSecret: Data(), domain: domain, key: key, outputRoot: root)
        }
        let alias = root.appendingPathComponent("alias")
        let target = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        #expect(throws: Snapshot.Failure.self) {
            try Snapshot.stage([sample], legacyDataSecret: Data(), domain: domain, key: key, outputRoot: alias)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }
}
