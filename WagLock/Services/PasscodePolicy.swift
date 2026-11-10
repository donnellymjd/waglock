import Foundation

/// Library passcode length. Standard is 6–128 characters. In the encrypted builds the
/// person can choose to allow short passcodes (4–128) after reading the risk, in
/// onboarding or Settings › Security & access. The choice is app-wide and device-only,
/// applies to new and changed passcodes, and never stops an existing passcode working:
/// unlock never checks length. Album and backup passwords keep their own 6+ rule.
enum PasscodePolicy {
    static let standardMinimum = 6
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

    /// "6–128" or "4–128", for field placeholders.
    static var rangeText: String { "\(minimumLength)–\(maximum)" }

    static func validate(_ passcode: String) -> (isValid: Bool, message: String?) {
        validate(passcode, minimum: minimumLength)
    }

    static func validate(_ passcode: String, minimum: Int) -> (isValid: Bool, message: String?) {
        if passcode.isEmpty { return (false, AppConstants.ErrorMessages.passwordEmpty) }
        if passcode.count < minimum {
            return (false, String(format: String(localized: "error.passwordTooShort"), minimum))
        }
        if passcode.count > maximum { return (false, AppConstants.ErrorMessages.passwordTooLong) }
        return (true, nil)
    }
}
