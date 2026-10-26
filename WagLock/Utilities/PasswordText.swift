import Foundation

/// Confirmation follows the exact UTF-8 consumed by the KDF. Never normalize credentials.
/// This compares user-entered confirmation text, not stored secret verifiers.
nonisolated enum PasswordText {
    static func matches(_ first: String, _ second: String) -> Bool {
        first.utf8.elementsEqual(second.utf8)
    }
}
