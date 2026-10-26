import Foundation
import XCTest
@testable import WagLock

@MainActor
final class BackupReminderTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "T12:00:00Z")! }

    func testMonthlyDefaultWaitsAMonthAndPromptDismissalSurvivesRelaunch() throws {
        let storage = InMemoryAttemptStorage()
        var now = date("2026-01-15")
        let first = BackupReminderStore(storage: storage, now: { now })
        XCTAssertFalse(first.claimDuePrompt()); XCTAssertEqual(first.frequency, .monthly)
        XCTAssertEqual(first.nextReminder, date("2026-02-15")); XCTAssertNil(first.lastSaved)
        now = date("2026-02-15")
        XCTAssertTrue(first.claimDuePrompt()); XCTAssertFalse(first.claimDuePrompt())
        let reopened = BackupReminderStore(storage: storage, now: { now })
        XCTAssertFalse(reopened.claimDuePrompt()); XCTAssertEqual(reopened.nextReminder, date("2026-03-15"))
        XCTAssertNil(reopened.lastSaved, "A displayed prompt is not a saved backup")
    }
    func testFilesSuccessResetsScheduleAndFrequencyAndOffPersistIndependently() {
        let primary = InMemoryAttemptStorage(), other = InMemoryAttemptStorage()
        var now = date("2026-01-15")
        let first = BackupReminderStore(storage: primary, now: { now })
        first.refresh(); now = date("2026-02-16")
        first.recordSavedToFiles()
        XCTAssertEqual(first.lastSaved, now); XCTAssertEqual(first.nextReminder, date("2026-03-16"))
        first.setFrequency(.weekly); XCTAssertEqual(first.nextReminder, date("2026-02-23"))
        first.setFrequency(.quarterly); XCTAssertEqual(first.nextReminder, date("2026-05-16"))
        first.setFrequency(.off); XCTAssertNil(first.nextReminder)
        now = date("2027-02-16")
        let reopened = BackupReminderStore(storage: primary, now: { now })
        XCTAssertFalse(reopened.claimDuePrompt()); XCTAssertEqual(reopened.frequency, .off)
        let separate = BackupReminderStore(storage: other, now: { now })
        separate.refresh(); XCTAssertEqual(separate.frequency, .monthly); XCTAssertNil(separate.lastSaved)
        XCTAssertEqual(separate.nextReminder, date("2027-03-16"))
    }
    func testExplicitSnoozeIsAWeekAndDoesNotMarkBackupSaved() {
        let storage = InMemoryAttemptStorage()
        var now = date("2026-01-15")
        let store = BackupReminderStore(storage: storage, now: { now }); store.refresh()
        now = date("2026-02-15"); XCTAssertTrue(store.claimDuePrompt())
        store.remindInAWeek(); XCTAssertEqual(store.nextReminder, date("2026-02-22"))
        XCTAssertFalse(store.claimDuePrompt()); XCTAssertNil(store.lastSaved)
        now = date("2026-02-22"); XCTAssertTrue(store.claimDuePrompt())
        XCTAssertFalse(store.claimDuePrompt()); XCTAssertEqual(store.nextReminder, date("2026-03-22"))
    }
    func testUnavailableCorruptOrUnwrittenStateCannotBeReplacedWithDefaults() {
        let storage = InMemoryAttemptStorage()
        let store = BackupReminderStore(storage: storage, now: { self.date("2026-01-15") })
        storage.unavailable = true; XCTAssertFalse(store.claimDuePrompt()); XCTAssertNotNil(store.error)
        XCTAssertTrue(storage.values.isEmpty)
        storage.unavailable = false; storage.failWrites = true
        store.refresh(); XCTAssertNotNil(store.error); XCTAssertNil(store.nextReminder); XCTAssertTrue(storage.values.isEmpty)
        storage.failWrites = false; store.refresh(); XCTAssertNil(store.error)
        let account = storage.values.keys.first!
        storage.values[account] = Data("PUBLIC corrupt preferences".utf8)
        let old = storage.values
        store.setFrequency(.off); XCTAssertNotNil(store.error); XCTAssertEqual(storage.values, old)
        XCTAssertFalse(store.claimDuePrompt()); XCTAssertEqual(storage.values, old)
    }
    func testCalendarBoundariesDailyAndClockChangesAreOnlyAdvisory() {
        let storage = InMemoryAttemptStorage()
        var now = date("2026-01-31")
        let store = BackupReminderStore(storage: storage, now: { now }); store.refresh()
        XCTAssertEqual(store.nextReminder, date("2026-02-28"))
        now = date("2025-01-01"); XCTAssertFalse(store.claimDuePrompt())
        now = date("2026-03-01"); XCTAssertTrue(store.claimDuePrompt())
        store.recordSavedToFiles(); store.setFrequency(.daily)
        XCTAssertEqual(store.nextReminder, date("2026-03-02"))
        store.clearCachedState(); store.refresh(); XCTAssertEqual(store.frequency, .daily)
        XCTAssertEqual(store.lastSaved, now)
    }
}
