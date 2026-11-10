import CryptoKit
import Foundation
import XCTest
@testable import WagLock

/// Disposable in-memory Keychain only. Small scrypt cost (2^10) keeps tests fast; the
/// cost is part of the authenticated header, so production records use 2^16.
@MainActor
final class LibrarySlotTableTests: XCTestCase {
    private var storage: InMemoryAttemptStorage!
    private var keychain: KeychainService!
    private var date = Date(timeIntervalSince1970: 1_900_000_000)
    private var elapsed: Double = 0

    override func setUp() async throws {
        storage = InMemoryAttemptStorage()
        keychain = KeychainService(service: "test." + UUID().uuidString, storage: storage,
                                   makeDataPassword: { try FreshEncryptedLibrary.randomSecret() },
                                   allowLegacyCredentials: false)
        date = Date(timeIntervalSince1970: 1_900_000_000)
        elapsed = 0
    }

    private func makeTable() -> LibrarySlotTable {
        keychain.librarySlotTable(logN: 10, now: { [unowned self] in self.date })
    }

    private func makeService() -> LibraryPasscodeService {
        let limiter = keychain.passwordAttemptLimiter(now: { [unowned self] in self.date },
                                                      elapsedTime: { [unowned self] in self.elapsed }, epoch: UUID())
        return LibraryPasscodeService(keychain: keychain, table: makeTable(), limiter: limiter, minimumDuration: .zero)
    }

    private func opened(_ outcome: LibraryPasscodeService.UnlockOutcome) -> LibraryReference? {
        if case .opened(let library, _) = outcome { return library }
        return nil
    }

    func testFreshTableHasSixteenUniformSlotsAndOnlyTheRightPasscodeOpensIt() async throws {
        let service = makeService()
        let (library, secret) = try await service.createFirstLibrary(passcode: "first-passcode")
        XCTAssertNotNil(library.independentID, "New libraries are never a privileged legacy owner")
        let record = try XCTUnwrap(try makeTable().record())
        XCTAssertEqual(record.count, LibrarySlotCrypto.recordSize)
        XCTAssertLessThan(record.count, 8_000, "A few kilobytes")
        let match = try XCTUnwrap(try makeTable().evaluate(passcode: "first-passcode"))
        XCTAssertEqual(match.payload.secret, secret)
        XCTAssertNil(try makeTable().evaluate(passcode: "first-passcodE"))
        XCTAssertEqual(try makeTable().allocation().count, 1)

        // Every slot is the same length and none but the used one authenticates.
        let header = try LibrarySlotHeader(parsing: record)
        let key = try LibrarySlotCrypto.deriveKey(passcode: "first-passcode", header: header, namespace: makeTable().namespace)
        let opening = (0..<16).filter {
            LibrarySlotCrypto.open(LibrarySlotCrypto.slot(record, at: $0), key: key, header: header,
                                   index: $0, namespace: makeTable().namespace) != nil
        }
        XCTAssertEqual(opening, [match.index])
        XCTAssertTrue((0..<16).allSatisfy { LibrarySlotCrypto.slot(record, at: $0).count == LibrarySlotCrypto.slotSize })
    }

    func testTamperedHeaderOrTruncatedRecordOpensNothingAndIsNeverReset() async throws {
        let service = makeService()
        _ = try await service.createFirstLibrary(passcode: "first-passcode")
        var record = try XCTUnwrap(storage.values[LibrarySlotTable.tableAccount])
        let original = record
        record[20] ^= 0x01 // salt byte, authenticated as associated data
        storage.values[LibrarySlotTable.tableAccount] = record
        XCTAssertNil(try makeTable().evaluate(passcode: "first-passcode"))
        storage.values[LibrarySlotTable.tableAccount] = original.prefix(original.count - 1)
        XCTAssertThrowsError(try makeTable().evaluate(passcode: "first-passcode"))
        storage.values[LibrarySlotTable.tableAccount] = original
        XCTAssertNotNil(try makeTable().evaluate(passcode: "first-passcode"))
        // Moving a slot to another index breaks its authentication.
        let match = try XCTUnwrap(try makeTable().evaluate(passcode: "first-passcode"))
        let other = (match.index + 1) % 16
        var swapped = try LibrarySlotCrypto.replacing(original, slot: LibrarySlotCrypto.slot(original, at: match.index), at: other)
        swapped = try LibrarySlotCrypto.replacing(swapped, slot: LibrarySlotCrypto.slot(original, at: other), at: match.index)
        storage.values[LibrarySlotTable.tableAccount] = swapped
        XCTAssertNil(try makeTable().evaluate(passcode: "first-passcode"))
    }

    func testAddRejectsCollisionsWeakAndFullTablesWithOneGenericFailureAndWait() async throws {
        let service = makeService()
        let (first, _) = try await service.createFirstLibrary(passcode: "first-passcode")
        do { try await service.addLibrary(passcode: "first-passcode"); XCTFail("collision accepted") }
        catch { XCTAssertEqual(error as? LibraryPasscodeService.Failure, .rejected) }
        // The rejection imposed a wait; nothing else can be proposed until it passes.
        do { try await service.addLibrary(passcode: "second-passcode"); XCTFail("wait skipped") }
        catch { XCTAssertEqual(error as? LibraryPasscodeService.Failure, .blocked(seconds: 30)) }
        elapsed += 31
        // Too short is the public length rule: said plainly, with no attempt used and no wait.
        do { try await service.addLibrary(passcode: "short"); XCTFail("weak accepted") }
        catch { XCTAssertEqual(error as? LibraryPasscodeService.Failure, .tooShort(minimum: 6)) }
        try await service.addLibrary(passcode: "second-passcode")
        let outcome1 = await service.unlock("second-passcode")
        let second = try XCTUnwrap(opened(outcome1))
        XCTAssertNotEqual(second, first)
        let outcome2 = await service.unlock("first-passcode")
        XCTAssertEqual(opened(outcome2), first)

        for index in 3...16 {
            elapsed += 1000
            _ = await service.unlock("first-passcode") // Reset the shared counter between adds.
            try await service.addLibrary(passcode: "library-passcode-\(index)")
        }
        XCTAssertEqual(try makeTable().allocation().count, 16)
        elapsed += 1000
        _ = await service.unlock("first-passcode")
        do { try await service.addLibrary(passcode: "library-passcode-17"); XCTFail("17th accepted") }
        catch { XCTAssertEqual(error as? LibraryPasscodeService.Failure, .rejected) }
    }

    func testAcceptedAddGivesItsAttemptBackSoTriesLeftStayAccurate() async throws {
        let service = makeService()
        _ = try await service.createFirstLibrary(passcode: "first-passcode")
        try await service.addLibrary(passcode: "second-passcode")
        // The next wrong passcode is the first failure, not the second.
        let outcome = await service.unlock("never-a-passcode")
        XCTAssertEqual(outcome, .wrong(failures: 1))
    }

    func testChangeRewritesOnlyThisLibraryAndKeepsItsSecret() async throws {
        let service = makeService()
        let (first, secret) = try await service.createFirstLibrary(passcode: "first-passcode")
        try await service.addLibrary(passcode: "second-passcode")
        let outcome3 = await service.unlock("second-passcode")
        let second = try XCTUnwrap(opened(outcome3))
        // Another library's passcode does not authorize changing this one.
        do { try await service.change(current: "second-passcode", to: "new-first-passcode", library: first); XCTFail() }
        catch { XCTAssertEqual(error as? LibraryPasscodeService.Failure, .wrongPasscode(failures: 1)) }
        // Changing to another library's passcode is a generic rejection, never an open.
        do { try await service.change(current: "first-passcode", to: "second-passcode", library: first); XCTFail() }
        catch { XCTAssertEqual(error as? LibraryPasscodeService.Failure, .rejected) }
        elapsed += 31
        try await service.change(current: "first-passcode", to: "new-first-passcode", library: first)
        let outcome4 = await service.unlock("new-first-passcode")
        XCTAssertEqual(outcome4, .opened(first, secret: secret))
        let outcome5 = await service.unlock("first-passcode")
        XCTAssertNil(opened(outcome5))
        let outcome6 = await service.unlock("second-passcode")
        XCTAssertEqual(opened(outcome6), second)
    }

    func testTimeLockBehavesLikeWrongPasscodeCannotBeShortenedByRollbackAndLeavesNoTrace() async throws {
        let service = makeService()
        let (first, _) = try await service.createFirstLibrary(passcode: "first-passcode")
        try await service.timeLock(passcode: "first-passcode", library: first, until: date.addingTimeInterval(3600))
        let outcome7 = await service.unlock("first-passcode")
        XCTAssertEqual(outcome7, .wrong(failures: 1))
        let outcome8 = await service.unlock("never-a-passcode")
        XCTAssertEqual(outcome8, .wrong(failures: 2))
        date = date.addingTimeInterval(1800)
        let outcome9 = await service.unlock("first-passcode")
        XCTAssertEqual(outcome9, .wrong(failures: 3))
        date = date.addingTimeInterval(-7200) // Rollback: the high-water clock keeps the later time.
        let outcome10 = await service.unlock("first-passcode")
        XCTAssertEqual(outcome10, .wrong(failures: 4))
        date = date.addingTimeInterval(7200 + 1801)
        let outcome11 = await service.unlock("first-passcode")
        XCTAssertEqual(opened(outcome11), first)
        XCTAssertNil(try makeTable().evaluate(passcode: "first-passcode")?.payload.timeLockUntil)
    }

    func testDestroyCryptoErasesOnlyThisSlotAndFreesIt() async throws {
        let service = makeService()
        let (first, _) = try await service.createFirstLibrary(passcode: "first-passcode")
        try await service.addLibrary(passcode: "second-passcode")
        let outcome12 = await service.unlock("second-passcode")
        let second = try XCTUnwrap(opened(outcome12))
        let before = try XCTUnwrap(try makeTable().record())
        try await service.destroy(passcode: "second-passcode", library: second)
        let after = try XCTUnwrap(try makeTable().record())
        XCTAssertEqual(before.count, after.count, "Deleting never changes the table size")
        let outcome13 = await service.unlock("second-passcode")
        XCTAssertNil(opened(outcome13))
        let outcome14 = await service.unlock("first-passcode")
        XCTAssertEqual(opened(outcome14), first)
        XCTAssertEqual(try makeTable().allocation().count, 1)
    }

    func testPreSlotOwnerEnrollsOnceAndItsOldWrapperIsRetired() async throws {
        let legacySecret = try keychain.savePassword("legacy-passcode")
        let service = makeService()
        let outcome15 = await service.unlock("legacy-passcode")
        XCTAssertEqual(outcome15, .opened(.legacyOwner, secret: legacySecret))
        XCTAssertNil(try keychain.legacyOwnerSnapshot(), "The verified slot replaces the old wrapper")
        XCTAssertEqual(try makeTable().evaluate(passcode: "legacy-passcode")?.payload.library, .legacyOwner)
        let outcome16 = await service.unlock("legacy-passcode")
        XCTAssertEqual(outcome16, .opened(.legacyOwner, secret: legacySecret))
        XCTAssertEqual(try makeTable().allocation().count, 1, "No duplicate enrollment")
    }

    func testUnavailableKeychainIsNeverAWrongPasscodeOrSetupInvitation() async throws {
        let service = makeService()
        _ = try await service.createFirstLibrary(passcode: "first-passcode")
        storage.unavailable = true
        let outcome17 = await service.unlock("first-passcode")
        XCTAssertEqual(outcome17, .unavailable)
        XCTAssertTrue(service.hasTable)
        storage.unavailable = false
        let outcome18 = await service.unlock("first-passcode")
        XCTAssertNotNil(opened(outcome18))
    }
}
