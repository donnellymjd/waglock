import CryptoKit
import Foundation

/// Online guessing control only; this does not prevent attacks on extracted ciphertext.
@MainActor
final class PasswordAttemptLimiter {
    nonisolated deinit { }
    enum Failure: Error, LocalizedError {
        case blocked(seconds: Int), unavailable, superseded
        nonisolated var errorDescription: String? {
            switch self {
            case .blocked(let seconds): return "Too many attempts. Try again in \(seconds) seconds."
            case .unavailable: return "Unable to verify password protection. Unlock your device and try again."
            case .superseded: return "This unlock attempt is no longer current. Try again."
            }
        }
    }
    struct Reservation { fileprivate let id: UUID; let failures: Int; let blockedUntil: Date? }
    private struct State: Codable {
        let version: Int
        let id: UUID
        let failures: Int
        let blockedUntil: Date? // v1 reader only; never an authority for v2 waits
        let remaining: Double?
        let checkpoint: Double?
        let epoch: UUID?
    }
    private static let processEpoch = UUID()
    private static let clock = ContinuousClock()
    private static let origin = clock.now
    private static func elapsed() -> Double {
        let duration = origin.duration(to: clock.now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }
    private let storage: any KeychainStorage
    private let account: String
    private let now: () -> Date
    private let elapsedTime: () -> Double
    private let epoch: UUID

    init(storage: any KeychainStorage, scope: String, now: @escaping () -> Date = Date.init,
         elapsedTime: (() -> Double)? = nil, epoch: UUID? = nil) {
        self.storage = storage
        self.account = "waglock.password-attempts.v1." + SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        self.now = now
        self.elapsedTime = elapsedTime ?? { Self.elapsed() }
        self.epoch = epoch ?? Self.processEpoch
    }

    func status() throws -> (failures: Int, blockedUntil: Date?) {
        let value = try read()
        return (value.failures, displayDeadline(value))
    }

    /// Reserve durably before verification. A crash or cancelled task still consumes a guess.
    func reserve() throws -> Reservation {
        let old = try read()
        if let remaining = old.remaining, remaining > 0 {
            throw Failure.blocked(seconds: Int(ceil(remaining)))
        }
        let count = min(old.failures + 1, 64)
        let value = State(version: 2, id: UUID(), failures: count, blockedUntil: nil,
                          remaining: Self.delay(count), checkpoint: elapsedTime(), epoch: epoch)
        try write(value)
        return Reservation(id: value.id, failures: count, blockedUntil: displayDeadline(value))
    }

    /// An older successful request cannot erase a later request's reserved attempt.
    func recordSuccess(_ reservation: Reservation) throws {
        guard try read().id == reservation.id else { throw Failure.superseded }
        try write(State(version: 2, id: UUID(), failures: 0, blockedUntil: nil,
                        remaining: 0, checkpoint: elapsedTime(), epoch: epoch))
    }

    private static func delay(_ failures: Int) -> Double {
        failures < 5 ? 0 : min(3600, 300 * pow(2, Double(min(failures - 5, 4))))
    }
    private func displayDeadline(_ value: State) -> Date? {
        guard let remaining = value.remaining, remaining > 0 else { return nil }
        return now().addingTimeInterval(remaining)
    }

    /// Only monotonic elapsed time in this process earns cooldown credit. A new process
    /// resumes the last persisted remaining wait; changing Date or restarting cannot skip it.
    /// Restarting before the next checkpoint may conservatively extend the wait.
    private func read() throws -> State {
        let elapsed = elapsedTime()
        guard elapsed.isFinite, elapsed >= 0 else { throw Failure.unavailable }
        let data: Data
        do { data = try storage.read(account: account) }
        catch KeychainError.itemNotFound {
            return State(version: 2, id: UUID(), failures: 0, blockedUntil: nil,
                         remaining: 0, checkpoint: elapsed, epoch: epoch)
        }
        catch { throw Failure.unavailable }
        do {
            guard data.count <= 512 else { throw Failure.unavailable }
            let value = try JSONDecoder().decode(State.self, from: data)
            guard (0...64).contains(value.failures) else { throw Failure.unavailable }
            let remaining: Double
            if value.version == 1 {
                guard value.failures >= 5 || value.blockedUntil == nil,
                      value.failures < 5 || value.blockedUntil != nil,
                      value.blockedUntil?.timeIntervalSince1970.isFinite != false else { throw Failure.unavailable }
                // Legacy wall time cannot prove a cooldown elapsed. Resume one bounded wait.
                remaining = Self.delay(value.failures)
            } else {
                guard value.version == 2, let saved = value.remaining, saved.isFinite, (0...3600).contains(saved),
                      let checkpoint = value.checkpoint, checkpoint.isFinite, checkpoint >= 0,
                      value.epoch != nil, value.failures >= 5 || saved == 0 else { throw Failure.unavailable }
                if value.epoch == epoch {
                    guard elapsed >= checkpoint else { throw Failure.unavailable }
                    remaining = max(0, saved - (elapsed - checkpoint))
                } else { remaining = saved }
            }
            let updated = State(version: 2, id: value.id, failures: value.failures, blockedUntil: nil,
                                remaining: remaining, checkpoint: elapsed, epoch: epoch)
            try write(updated)
            return updated
        } catch { throw Failure.unavailable }
    }
    private func write(_ value: State) throws {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try storage.write(account: account, data: encoder.encode(value), createOnly: false)
        } catch { throw Failure.unavailable }
    }
}
