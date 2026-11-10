internal import Combine
import Foundation

/// Drives the reserve on the main actor: mode changes, allocation progress for the
/// Switching storage screen, and quiet regrowth after deletions. App-wide and identical in
/// every library; it never reports how much any library or WagLock as a whole uses.
@MainActor
final class StorageReserveCoordinator: ObservableObject {
    nonisolated deinit {}
    static let shared = StorageReserveCoordinator(reserve: .shared)

    enum Phase: Equatable { case idle, allocating, paused, failed(String) }

    @Published private(set) var mode: StorageReserve.Mode = .standard
    @Published private(set) var targetBytes: Int64 = 0
    @Published private(set) var phase: Phase = .idle
    /// 0...1 while allocating; only a percentage is ever shown.
    @Published private(set) var progress: Double = 0
    @Published private(set) var secondsLeft: Int?
    /// True while a user-visible allocation (a mode change or resize) is in progress.
    @Published private(set) var showsSwitching = false

    /// Growth below this is done silently (e.g. after deleting items).
    static let visibleGrowth: Int64 = 512 * 1_048_576

    let reserve: StorageReserve
    private var task: Task<Void, Never>?
    private var stopFlag = StopFlag()
    private var observers: [NSObjectProtocol] = []

    init(reserve: StorageReserve) {
        self.reserve = reserve
        refresh()
        observers.append(NotificationCenter.default.addObserver(forName: .wagLockStorageChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRegrowth() }
        })
    }

    func refresh() {
        if let config = try? reserve.config() {
            mode = config.mode; targetBytes = config.targetBytes
        }
    }

    var targetGigabytes: Int { Int(targetBytes / StorageReserve.gigabyte) }

    /// Switch to Fixed size, or change the fixed size. Allocation starts at once and
    /// resumes after an interruption.
    func useFixedSize(gigabytes: Int) throws {
        try reserve.setFixed(targetBytes: Int64(gigabytes) * StorageReserve.gigabyte)
        refresh()
        start(visible: true)
    }

    func useStandard() throws {
        stop()
        try reserve.setStandard()
        refresh()
        phase = .idle; showsSwitching = false; progress = 0
    }

    /// Called at launch, on foreground and after unlock: finish any interrupted allocation.
    func resume() {
        refresh()
        guard mode == .fixed, task == nil else { return }
        let pending = reserve.pendingGrowth()
        guard pending > 0 else { return }
        start(visible: pending >= Self.visibleGrowth)
    }

    /// Chosen during onboarding; applied once the first library has opened.
    var pendingFixedGigabytes: Int?

    func applyPendingChoice() {
        guard let gigabytes = pendingFixedGigabytes else { return }
        pendingFixedGigabytes = nil
        try? useFixedSize(gigabytes: gigabytes)
    }

    func pause() {
        stop()
        if showsSwitching { phase = .paused }
    }

    func dismissSwitching() { showsSwitching = false }

    private func scheduleRegrowth() {
        guard mode == .fixed, task == nil else { return }
        start(visible: false)
    }

    private func start(visible: Bool) {
        stop()
        let flag = StopFlag(); stopFlag = flag
        phase = .allocating; progress = 0; secondsLeft = nil
        if visible { showsSwitching = true }
        let reserve = self.reserve
        let begin = Date()
        task = Task.detached(priority: .utility) { [weak self] in
            var lastReport = Date.distantPast
            let result: Result<Void, Error> = Result {
                try reserve.grow(shouldStop: { flag.isSet || Task.isCancelled }) { written, total in
                    let now = Date()
                    guard now.timeIntervalSince(lastReport) > 0.25 || written == total else { return }
                    lastReport = now
                    let fraction = total > 0 ? Double(written) / Double(total) : 1
                    let elapsed = now.timeIntervalSince(begin)
                    let left = fraction > 0.02 ? Int(elapsed / fraction - elapsed) : nil
                    Task { @MainActor in self?.report(fraction, left) }
                }
            }
            await self?.finish(result, stopped: flag.isSet)
        }
    }

    private func report(_ fraction: Double, _ left: Int?) {
        guard phase == .allocating else { return }
        progress = fraction; secondsLeft = left
    }

    private func finish(_ result: Result<Void, Error>, stopped: Bool) {
        task = nil
        switch result {
        case .success:
            if stopped { phase = showsSwitching ? .paused : .idle; return }
            progress = 1; phase = .idle; showsSwitching = false
        case .failure(let error):
            phase = .failed((error as? StorageReserve.Failure) == .insufficientDevice
                ? "This iPhone ran out of free space. WagLock’s data is unchanged; free some space and resume."
                : "Reserving space stopped. WagLock’s data is unchanged; it picks up where it stopped next time you unlock.")
        }
    }

    private func stop() {
        stopFlag.set()
        task?.cancel(); task = nil
    }
}

/// Thread-safe stop signal read by the detached allocation loop.
nonisolated final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}
