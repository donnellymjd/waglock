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
        let blockedUntil: Date?
    }
    private let storage: any KeychainStorage
    private let account: String
    private let now: () -> Date

    init(storage: any KeychainStorage, scope: String, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.account = "waglock.password-attempts.v1." + SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        self.now = now
    }

    func status() throws -> (failures: Int, blockedUntil: Date?) {
        let value = try read()
        return (value.failures, value.blockedUntil)
    }

    /// Reserve durably before verification. A crash or cancelled task still consumes a guess.
    func reserve() throws -> Reservation {
        let old = try read(), date = now()
        if let until = old.blockedUntil, until > date {
            throw Failure.blocked(seconds: Int(ceil(min(3600, until.timeIntervalSince(date)))))
        }
        let count = min(old.failures + 1, 64)
        let delay = count < 5 ? 0 : min(3600, 300 * pow(2, Double(min(count - 5, 4))))
        let value = State(version: 1, id: UUID(), failures: count,
                          blockedUntil: delay == 0 ? nil : date.addingTimeInterval(delay))
        try write(value)
        return Reservation(id: value.id, failures: count, blockedUntil: value.blockedUntil)
    }

    /// An older successful request cannot erase a later request's reserved attempt.
    func recordSuccess(_ reservation: Reservation) throws {
        guard try read().id == reservation.id else { throw Failure.superseded }
        try write(State(version: 1, id: UUID(), failures: 0, blockedUntil: nil))
    }

    private func read() throws -> State {
        let data: Data
        do { data = try storage.read(account: account) }
        catch KeychainError.itemNotFound { return State(version: 1, id: UUID(), failures: 0, blockedUntil: nil) }
        catch { throw Failure.unavailable }
        do {
            guard data.count <= 512 else { throw Failure.unavailable }
            let value = try JSONDecoder().decode(State.self, from: data)
            guard value.version == 1, (0...64).contains(value.failures),
                  value.failures >= 5 || value.blockedUntil == nil,
                  value.failures < 5 || value.blockedUntil != nil else { throw Failure.unavailable }
            if let until = value.blockedUntil {
                guard until.timeIntervalSince1970.isFinite else { throw Failure.unavailable }
            }
            return value
        } catch { throw Failure.unavailable }
    }
    private func write(_ value: State) throws {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try storage.write(account: account, data: encoder.encode(value), createOnly: false)
        } catch { throw Failure.unavailable }
    }
}
