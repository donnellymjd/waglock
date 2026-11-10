import Foundation

/// Every passcode operation for the multi-library model: unlock, collision check,
/// add, change, time lock and delete. Each one runs one memory-hard derivation, tries
/// all 16 slots, advances the one shared attempt counter and is padded to the same
/// minimum duration, so its outcome is the only thing that differs.
///
/// Design sketch pending crypto review: docs/portable-vault/library-slots.md.
@MainActor
final class LibraryPasscodeService {
    nonisolated deinit {}

    enum UnlockOutcome: Equatable {
        case opened(LibraryReference, secret: String)
        /// Same outcome for wrong, time-locked and unknown passcodes.
        case wrong(failures: Int)
        case blocked(seconds: Int)
        case unavailable
    }

    enum Failure: Error, Equatable {
        case wrongPasscode(failures: Int)
        /// Collision or no free slot. Always followed by a 30-second wait.
        case rejected
        /// Outside the public length rule (PasscodePolicy). Checked before anything else, so
        /// it uses no attempt, has no wait and says nothing about any library.
        case tooShort(minimum: Int)
        case tooLong(maximum: Int)
        case blocked(seconds: Int)
        case unavailable
    }

    let table: LibrarySlotTable
    private let keychain: KeychainService
    private let limiter: PasswordAttemptLimiter
    private let minimumDuration: Duration
    private let makeSecret: () throws -> String
    /// Minimum length for new and changed passcodes (PasscodePolicy). Unlock never checks length.
    private let minimumLength: () -> Int

    init(keychain: KeychainService, table: LibrarySlotTable? = nil, limiter: PasswordAttemptLimiter,
         minimumDuration: Duration = .milliseconds(1500),
         makeSecret: (() throws -> String)? = nil,
         minimumLength: @escaping () -> Int = { PasscodePolicy.minimumLength }) {
        self.minimumLength = minimumLength
        self.keychain = keychain
        self.table = table ?? keychain.librarySlotTable()
        self.limiter = limiter
        self.minimumDuration = minimumDuration
        self.makeSecret = makeSecret ?? { try FreshEncryptedLibrary.randomSecret() }
    }

    /// An unreadable table counts as configured: setup must never mask a Keychain failure.
    var hasTable: Bool { (try? table.exists()) ?? true }

    // MARK: - Setup

    /// First run: creates the table and the first library. Every library made here is independent.
    func createFirstLibrary(passcode: String) async throws -> (LibraryReference, String) {
        try checkLength(passcode)
        guard try !table.exists() else { throw Failure.unavailable }
        let library = LibraryReference.independent(UUID())
        let payload = LibrarySlotPayload(library: library, secret: try makeSecret())
        do {
            try table.initialize(passcode: passcode, payload: payload)
            guard try await evaluate(passcode)?.payload == payload else { throw Failure.unavailable }
        } catch let failure as Failure { throw failure } catch { throw Failure.unavailable }
        keychain.retireLegacyPresentationGuest()
        return (library, payload.secret)
    }

    // MARK: - Unlock

    func unlock(_ passcode: String) async -> UnlockOutcome {
        let reservation: PasswordAttemptLimiter.Reservation
        do { reservation = try limiter.reserve() }
        catch PasswordAttemptLimiter.Failure.blocked(let seconds) { return .blocked(seconds: seconds) }
        catch { return .unavailable }
        let start = ContinuousClock.now
        let outcome = await unlockReserved(passcode, reservation: reservation)
        await pad(from: start)
        return outcome
    }

    private func unlockReserved(_ passcode: String, reservation: PasswordAttemptLimiter.Reservation) async -> UnlockOutcome {
        do {
            if try table.exists(), let match = try await evaluate(passcode) {
                let now = try table.trustedNow()
                if let until = match.payload.timeLockUntil {
                    // A time-locked passcode is indistinguishable from a wrong one.
                    guard now >= until else { return .wrong(failures: reservation.failures) }
                    // Expired: remove every trace of the lock before opening.
                    var cleared = match.payload; cleared.timeLockUntil = nil
                    if let record = try table.record() {
                        try? table.rewrite(index: match.index, verifiedRecord: record, passcode: passcode, payload: cleared)
                    }
                }
                try? retireLegacyRecords(for: match.payload.library)
                try limiter.recordSuccess(reservation)
                return .opened(match.payload.library, secret: match.payload.secret)
            }
            if let legacy = try legacyUnlock(passcode) {
                enroll(passcode, library: legacy.0, secret: legacy.1)
                try limiter.recordSuccess(reservation)
                return .opened(legacy.0, secret: legacy.1)
            }
            return .wrong(failures: reservation.failures)
        } catch { return .unavailable }
    }

    // MARK: - Management (all require being inside the library)

    /// Confirms `passcode` opens exactly `library`. Success resets the shared counter.
    @discardableResult
    func verify(_ passcode: String, library: LibraryReference) async throws -> (LibrarySlotMatch, Data) {
        let reservation = try reserve()
        let start = ContinuousClock.now
        do {
            let record = try table.requireRecord()
            let match: LibrarySlotMatch?
            do { match = try await evaluate(passcode, record: record) }
            catch { await pad(from: start); throw error }
            await pad(from: start)
            guard let match, match.payload.library == library else {
                throw Failure.wrongPasscode(failures: reservation.failures)
            }
            try limiter.recordSuccess(reservation)
            return (match, record)
        } catch let failure as Failure { throw failure } catch { throw Failure.unavailable }
    }

    /// The collision check. It is the unlock path itself, so it costs and reveals exactly what
    /// an unlock does, shares the counter and never opens anything. A rejection always waits 30 s.
    private func propose(_ passcode: String) async throws {
        let reservation = try reserve()
        let start = ContinuousClock.now
        var acceptable = PasscodePolicy.validate(passcode, minimum: minimumLength()).isValid
        do {
            let record = try table.requireRecord()
            if try await evaluate(passcode, record: record) != nil { acceptable = false }
            if try legacyMatches(passcode) { acceptable = false }
            if try table.allocation().count >= LibrarySlotCrypto.slotCount { acceptable = false }
        } catch {
            await pad(from: start)
            throw Failure.unavailable
        }
        await pad(from: start)
        // A rejected proposal stays counted and adds the 30-second wait. An accepted one
        // gives its attempt back: the person is inside a library and could reset the counter
        // by verifying their own passcode anyway, so this adds nothing to probing, and it
        // keeps the lock screen's "tries left" accurate after an add or change.
        guard acceptable else {
            try? limiter.imposeWait()
            throw Failure.rejected
        }
        try? limiter.recordSuccess(reservation)
    }

    /// The length rule is the same for every library and shown in the app, so a too-short
    /// or too-long passcode is reported plainly, before any attempt is used.
    private func checkLength(_ passcode: String) throws {
        let minimum = minimumLength()
        if passcode.count < minimum { throw Failure.tooShort(minimum: minimum) }
        if passcode.count > PasscodePolicy.maximum { throw Failure.tooLong(maximum: PasscodePolicy.maximum) }
    }

    /// Adds another library. It opens on the next unlock with that passcode.
    func addLibrary(passcode: String) async throws {
        try checkLength(passcode)
        try await propose(passcode)
        let payload = LibrarySlotPayload(library: .independent(UUID()), secret: try makeSecret())
        do {
            try table.add(passcode: passcode, payload: payload)
            guard try await evaluate(passcode)?.payload == payload else { throw Failure.unavailable }
        } catch LibrarySlotFailure.rejected {
            try? limiter.imposeWait(); throw Failure.rejected
        } catch let failure as Failure { throw failure } catch { throw Failure.unavailable }
    }

    /// Verifies only this library's passcode, runs the same collision check and rewrites
    /// this library's slot in place. Keys and data are unchanged.
    func change(current: String, to new: String, library: LibraryReference) async throws {
        try checkLength(new)
        let (match, record) = try await verify(current, library: library)
        do { try retireLegacyRecords(for: library) } catch { throw Failure.unavailable }
        try await propose(new)
        var payload = match.payload; payload.timeLockUntil = nil
        do {
            try table.rewrite(index: match.index, verifiedRecord: record, passcode: new, payload: payload)
            guard try await evaluate(new)?.payload == payload else { throw Failure.unavailable }
        } catch let failure as Failure { throw failure } catch { throw Failure.unavailable }
    }

    /// The passcode stops working until `until`. Nothing can end it early.
    func timeLock(passcode: String, library: LibraryReference, until: Date) async throws {
        let (match, record) = try await verify(passcode, library: library)
        do {
            guard until > (try table.trustedNow()) else { throw Failure.unavailable }
            try retireLegacyRecords(for: library)
            var payload = match.payload; payload.timeLockUntil = until
            try table.rewrite(index: match.index, verifiedRecord: record, passcode: passcode, payload: payload)
        } catch let failure as Failure { throw failure } catch { throw Failure.unavailable }
    }

    /// Crypto-erases this library's slot. The caller then removes its now-unreadable files.
    func destroy(passcode: String, library: LibraryReference) async throws {
        let (match, record) = try await verify(passcode, library: library)
        do {
            try retireLegacyRecords(for: library)
            try table.destroy(index: match.index, verifiedRecord: record)
        } catch { throw Failure.unavailable }
    }

    // MARK: - Helpers

    private func reserve() throws -> PasswordAttemptLimiter.Reservation {
        do { return try limiter.reserve() }
        catch PasswordAttemptLimiter.Failure.blocked(let seconds) { throw Failure.blocked(seconds: seconds) }
        catch { throw Failure.unavailable }
    }

    private func evaluate(_ passcode: String, record: Data? = nil) async throws -> LibrarySlotMatch? {
        let record = try record ?? table.requireRecord()
        let namespace = table.namespace
        return try await Task.detached(priority: .userInitiated) {
            try LibrarySlotCrypto.evaluate(passcode: passcode, record: record, namespace: namespace)
        }.value
    }

    private func pad(from start: ContinuousClock.Instant) async {
        try? await Task.sleep(until: start + minimumDuration, clock: .continuous)
    }

    /// Pre-slot credentials stay readable until their library has a verified slot.
    /// The independent record keeps priority, matching earlier collision behavior.
    private func legacyUnlock(_ passcode: String) throws -> (LibraryReference, String)? {
        if try keychain.legacyIndependentSnapshot() != nil,
           let credential = try? keychain.unlockIndependentGuest(password: passcode) {
            return (.independent(credential.vaultID), credential.dataPassword)
        }
        if try keychain.legacyOwnerSnapshot() != nil,
           let secret = try? keychain.retrieveDataPassword(using: passcode) {
            return (.legacyOwner, secret)
        }
        return nil
    }

    private func legacyMatches(_ passcode: String) throws -> Bool {
        if try legacyUnlock(passcode) != nil { return true }
        return keychain.isGuestPasswordSet() && keychain.verifyGuestPassword(passcode)
    }

    /// Best effort: on any failure the pre-slot record stays and login still proceeds.
    private func enroll(_ passcode: String, library: LibraryReference, secret: String) {
        let payload = LibrarySlotPayload(library: library, secret: secret)
        do {
            if try table.exists() { try table.add(passcode: passcode, payload: payload) }
            else { try table.initialize(passcode: passcode, payload: payload) }
            guard try table.evaluate(passcode: passcode)?.payload == payload else { return }
            try retireLegacyRecords(for: library)
            keychain.retireLegacyPresentationGuest()
        } catch {}
    }

    /// A slot-verified session for a library is authority to drop that library's own
    /// pre-slot wrapper (it wraps the same secret), so an old passcode cannot outlive a change.
    private func retireLegacyRecords(for library: LibraryReference) throws {
        switch library {
        case .legacyOwner:
            if let snapshot = try keychain.legacyOwnerSnapshot() {
                try keychain.retireLegacyOwnerRecord(matching: snapshot)
            }
        case .independent(let id):
            if let snapshot = try keychain.legacyIndependentSnapshot(),
               (try? keychain.independentGuestVaultID()) == id {
                try keychain.retireLegacyIndependentRecord(matching: snapshot)
            }
        }
    }
}
