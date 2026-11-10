import XCTest
@testable import WagLock

/// ADR-032: short passcodes are an informed choice. Unlock never checks length, so
/// passcodes created under either rule keep working when the rule changes.
@MainActor
final class PasscodePolicyTests: XCTestCase {
    private var keychain: KeychainService!
    private var elapsed: Double = 0
    private var minimum = PasscodePolicy.standardMinimum

    override func setUp() async throws {
        // Disposable in-memory Keychain, as in LibrarySlotTableTests.
        keychain = KeychainService(service: "test." + UUID().uuidString, storage: InMemoryAttemptStorage(),
                                   makeDataPassword: { try FreshEncryptedLibrary.randomSecret() },
                                   allowLegacyCredentials: false)
        elapsed = 0
        minimum = PasscodePolicy.standardMinimum
    }

    private func makeService() -> LibraryPasscodeService {
        let limiter = keychain.passwordAttemptLimiter(now: { Date(timeIntervalSince1970: 1_900_000_000) },
                                                      elapsedTime: { [unowned self] in self.elapsed }, epoch: UUID())
        return LibraryPasscodeService(keychain: keychain, table: keychain.librarySlotTable(logN: 10), limiter: limiter,
                                      minimumDuration: .zero, minimumLength: { [unowned self] in self.minimum })
    }

    func testLengthRules() {
        XCTAssertEqual(PasscodePolicy.minimumLength(allowShort: false), 6)
        XCTAssertEqual(PasscodePolicy.minimumLength(allowShort: true), 4)
        XCTAssertFalse(PasscodePolicy.validate("12345", minimum: 6).isValid)
        XCTAssertTrue(PasscodePolicy.validate("123456", minimum: 6).isValid)
        XCTAssertTrue(PasscodePolicy.validate("1234", minimum: 4).isValid)
        XCTAssertFalse(PasscodePolicy.validate("123", minimum: 4).isValid)
        XCTAssertFalse(PasscodePolicy.validate("", minimum: 4).isValid)
        XCTAssertEqual(PasscodePolicy.lengthHint("123", minimum: 4), "Too short. Use at least 4 characters.")
        XCTAssertNil(PasscodePolicy.lengthHint("", minimum: 4), "No hint before typing")
        XCTAssertNil(PasscodePolicy.lengthHint("1234", minimum: 4))
        XCTAssertFalse(PasscodePolicy.validate(String(repeating: "a", count: 129), minimum: 4).isValid)
        XCTAssertTrue(PasscodePolicy.validate(String(repeating: "a", count: 128), minimum: 4).isValid)
        // Backup passwords: 12+ by default, 4+ only with the Short choice.
        XCTAssertEqual(PasscodePolicy.backupMinimum(allowShort: false), 12)
        XCTAssertEqual(PasscodePolicy.backupMinimum(allowShort: true), 4)
    }

    func testTheLegacyDevBuildCannotAllowShortPasscodes() {
        // The test host is the legacy Dev identity, which never offers the choice.
        XCTAssertFalse(LibraryStoragePolicy.encryptedMetadata)
        let previous = UserDefaults.standard.object(forKey: PasscodePolicy.shortPasscodesKey)
        defer { UserDefaults.standard.set(previous, forKey: PasscodePolicy.shortPasscodesKey) }
        UserDefaults.standard.set(true, forKey: PasscodePolicy.shortPasscodesKey)
        XCTAssertFalse(PasscodePolicy.allowsShortPasscodes)
        XCTAssertEqual(PasscodePolicy.minimumLength, 6)
        XCTAssertEqual(PasscodePolicy.albumPasswordMinimum, 6)
        XCTAssertEqual(PasscodePolicy.backupPasswordMinimum, 12)
    }

    func testShortPasscodesNeedTheChoiceAndKeepWorkingAfterItIsTurnedOff() async throws {
        let service = makeService()
        do { _ = try await service.createFirstLibrary(passcode: "1234"); XCTFail("short accepted under Standard") }
        catch { XCTAssertEqual(error as? LibraryPasscodeService.Failure, .tooShort(minimum: 6)) }

        minimum = PasscodePolicy.shortMinimum
        let (first, _) = try await service.createFirstLibrary(passcode: "1234")
        do { try await service.addLibrary(passcode: "123"); XCTFail("3 characters accepted") }
        catch { XCTAssertEqual(error as? LibraryPasscodeService.Failure, .tooShort(minimum: 4)) }
        // No attempt used and no wait: the next proposal goes straight through.
        try await service.addLibrary(passcode: "9876")

        // Back to Standard: existing short passcodes still open their libraries...
        minimum = PasscodePolicy.standardMinimum
        let outcome = await service.unlock("1234")
        guard case .opened(let library, _) = outcome else { return XCTFail("short passcode stopped working") }
        XCTAssertEqual(library, first)
        let second = await service.unlock("9876")
        guard case .opened = second else { return XCTFail("second short passcode stopped working") }
        // ...but new ones must meet the Standard rule again.
        do { try await service.addLibrary(passcode: "5555"); XCTFail("short accepted after switching back") }
        catch { XCTAssertEqual(error as? LibraryPasscodeService.Failure, .tooShort(minimum: 6)) }
        do { try await service.addLibrary(passcode: String(repeating: "x", count: 129)); XCTFail("129 accepted") }
        catch { XCTAssertEqual(error as? LibraryPasscodeService.Failure, .tooLong(maximum: 128)) }
    }
}
