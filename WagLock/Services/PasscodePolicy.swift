import Foundation

/// Minimum lengths for library passcodes, album passwords and backup passwords.
/// Standard: passcodes and album passwords 6+, backup passwords 12+. In the encrypted
/// builds the person can choose Short (4+ for all three) after reading the risks, in
/// onboarding or Settings › Security & access (ADR-032). The choice is app-wide and
/// device-only, applies to new and changed passwords, and never stops an existing one
/// working: unlocking never checks length.
enum PasscodePolicy {
    static let standardMinimum = 6
    static let standardBackupMinimum = 12
    static let shortMinimum = 4
    static let maximum = 128
    static let shortPasscodesKey = "allowShortPasscodes"

    /// Only the encrypted builds offer the choice; the legacy Dev build keeps 6+.
    static var isConfigurable: Bool { LibraryStoragePolicy.encryptedMetadata }

    static var allowsShortPasscodes: Bool {
        get { isConfigurable && UserDefaults.standard.bool(forKey: shortPasscodesKey) }
        set { UserDefaults.standard.set(newValue, forKey: shortPasscodesKey) }
    }

    static var minimumLength: Int { minimumLength(allowShort: allowsShortPasscodes) }

    static func minimumLength(allowShort: Bool) -> Int { allowShort ? shortMinimum : standardMinimum }

    /// Album passwords follow the passcode rule.
    static var albumPasswordMinimum: Int { minimumLength }

    /// Backup (age) passwords, including Face ID-only album export passwords.
    static var backupPasswordMinimum: Int { backupMinimum(allowShort: allowsShortPasscodes) }

    static func backupMinimum(allowShort: Bool) -> Int { allowShort ? shortMinimum : standardBackupMinimum }

    /// "6–128" or "4–128", for field placeholders.
    static var rangeText: String { "\(minimumLength)–\(maximum)" }

    /// Plain "too short" wording. Safe to show at any time: the rule is the same for every
    /// library and depends only on the setting shown in Security & access.
    static func tooShortMessage(minimum: Int) -> String {
        "Too short. Use at least \(minimum) characters."
    }

    /// The hint to show under a new-passcode or password field while it's too short, or nil.
    static func lengthHint(_ text: String, minimum: Int) -> String? {
        guard !text.isEmpty, text.count < minimum else { return nil }
        return tooShortMessage(minimum: minimum)
    }

    static func validate(_ passcode: String) -> (isValid: Bool, message: String?) {
        validate(passcode, minimum: minimumLength)
    }

    static func validate(_ passcode: String, minimum: Int) -> (isValid: Bool, message: String?) {
        if passcode.isEmpty { return (false, AppConstants.ErrorMessages.passwordEmpty) }
        if passcode.count < minimum {
            return (false, tooShortMessage(minimum: minimum))
        }
        if passcode.count > maximum { return (false, AppConstants.ErrorMessages.passwordTooLong) }
        return (true, nil)
    }
}
