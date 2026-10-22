import Foundation

/// Local advisory heuristic, not entropy, a crack-time prediction or a breached-password lookup.
/// This never validates, normalizes, stores or changes the credential.
nonisolated struct PasswordAssessment: Equatable {
    let score: Int
    var label: String {
        switch score {
        case ..<20: return "Very weak"
        case ..<40: return "Weak"
        case ..<60: return "Fair"
        case ..<80: return "Good"
        default: return "Strong"
        }
    }

    init(_ password: String) {
        let sample = String(password.prefix(129))
        let chars = Array(sample)
        guard !chars.isEmpty else { score = 0; return }
        let length = chars.count
        let unique = Set(chars).count
        let hasLetters = sample.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        let hasNumbers = chars.contains(where: \.isNumber)
        let hasOther = sample.unicodeScalars.contains { !CharacterSet.alphanumerics.contains($0) }
        let classes = [hasLetters, hasNumbers, hasOther].filter { $0 }.count
        var result = min(80, length * 3) + min(10, unique) + max(0, classes - 1) * 5
        if length < 6 { result = min(result, 15) }
        if chars.allSatisfy(\.isNumber) { result = min(result, length <= 8 ? 25 : 65) }
        if unique <= 2 { result = min(result, 10) }
        if length >= 4 {
            for period in 1...((length + 1) / 2) {
                if chars.indices.allSatisfy({ chars[$0] == chars[$0 % period] }) {
                    result = min(result, 15)
                    break
                }
            }
        }
        let lower = sample.lowercased()
        let letters = lower.filter(\.isLetter)
        let common = Set(["password", "qwerty", "letmein", "welcome", "admin", "iloveyou", "abc", "abcdef"])
        if common.contains(letters) { result = min(result, 15) }
        let sequences = ["01234567890123456789", "98765432109876543210", "abcdefghijklmnopqrstuvwxyz",
                         "zyxwvutsrqponmlkjihgfedcba"]
        if length >= 4 && sequences.contains(where: { $0.contains(lower) }) { result = min(result, 15) }
        score = max(0, min(100, result))
    }
}
