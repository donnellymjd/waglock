import Foundation
internal import Combine

/// Device-only scheduling preferences for one immutable vault namespace, never a credential cache.
@MainActor
final class BackupReminderStore: ObservableObject {
    nonisolated deinit {}
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case daily, weekly, monthly, quarterly, off
        var id: String { rawValue }
        var title: String {
            switch self {
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            case .quarterly: "Every 3 months"
            case .off: "Off"
            }
        }
        func next(after date: Date) -> Date? {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            switch self {
            case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
            case .weekly: return calendar.date(byAdding: .day, value: 7, to: date)
            case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
            case .quarterly: return calendar.date(byAdding: .month, value: 3, to: date)
            case .off: return nil
            }
        }
    }
    private struct State: Codable {
        var version = 1
        var frequency: Frequency = .monthly
        let started: Date
        var saved: Date?
        var prompted: Date?
        var snoozed: Date?
    }
    enum Failure: Error { case invalid, changed }
    private let storage: any KeychainStorage
    private let now: () -> Date
    private let account = "waglock.backup-reminders.v1"
    @Published private var state: State?
    @Published private(set) var error: String?
    var frequency: Frequency { state?.frequency ?? .monthly }
    var lastSaved: Date? { state?.saved }
    var nextReminder: Date? { state.flatMap(Self.due) }

    init(storage: any KeychainStorage, now: @escaping () -> Date = Date.init) {
        self.storage = storage; self.now = now
    }
    private func read() throws -> (State?, Data?) {
        let data: Data
        do { data = try storage.read(account: account) }
        catch KeychainError.itemNotFound { return (nil, nil) }
        guard data.count <= 4096 else { throw Failure.invalid }
        let value = try JSONDecoder().decode(State.self, from: data)
        guard value.version == 1,
              [value.started, value.saved, value.prompted, value.snoozed].compactMap({ $0 })
                .allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }) else { throw Failure.invalid }
        return (value, data)
    }
    private static func due(_ state: State) -> Date? {
        guard let scheduled = state.frequency.next(after: state.saved ?? state.started) else { return nil }
        if let snoozed = state.snoozed { return max(scheduled, snoozed) }
        if let prompted = state.prompted, let later = state.frequency.next(after: prompted) { return max(scheduled, later) }
        return scheduled
    }
    private func change(_ edit: (inout State) -> Void) throws {
        let (previous, source) = try read()
        var value = previous ?? State(started: now())
        edit(&value)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        let (_, current) = try read()
        guard source == current else { throw Failure.changed }
        try storage.write(account: account, data: data, createOnly: source == nil)
        guard try storage.read(account: account) == data else { throw Failure.changed }
        state = value; error = nil
    }
    func refresh() {
        do { try change { _ in } }
        catch { fail() }
    }
    /// Mark before presentation so ordinary dismissal/relaunch does not nag at every unlock.
    func claimDuePrompt() -> Bool {
        do {
            let (value, _) = try read()
            guard let value else { try change { _ in }; return false }
            state = value; error = nil
            guard let due = Self.due(value), now() >= due else { return false }
            try change { $0.prompted = now(); $0.snoozed = nil }
            return true
        } catch { fail(); return false }
    }
    func setFrequency(_ frequency: Frequency) {
        do { try change { $0.frequency = frequency; $0.snoozed = nil } }
        catch { fail() }
    }
    func remindInAWeek() {
        do { try change { $0.snoozed = Frequency.weekly.next(after: now()) } }
        catch { fail() }
    }
    /// Call only after a successful Files callback from the originating live vault context.
    func recordSavedToFiles() {
        do { try change { $0.saved = now(); $0.prompted = nil; $0.snoozed = nil } }
        catch { fail() }
    }
    func clearCachedState() { state = nil; error = nil }
    private func fail() { error = "Unable to update backup reminders. Your library is unchanged; you can still make a backup." }
}
