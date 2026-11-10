import SwiftUI

// Auto-lock and passcode-length choices for the encrypted builds (ADR-032). Like the
// storage modes, each option states its risk and the person decides. Both settings are
// app-wide and device-only, the same in every library, and say nothing about libraries.

/// One selectable option with its caveats, as on the storage step.
struct WagLockOptionCard: View {
    let selected: Bool
    let title: String
    var badge: String?
    let detail: String
    var caveats: [String] = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 20)).foregroundStyle(selected ? Graphite.accentText : Graphite.line)
                        .accessibilityHidden(true)
                    Text(title).font(.wlHeading).foregroundStyle(Graphite.textPrimary)
                    if let badge {
                        Text(badge).font(WagLockFonts.poppins(11, .semibold, relativeTo: .caption))
                            .foregroundStyle(Graphite.accentText).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Graphite.accentTint, in: Capsule())
                    }
                    Spacer()
                }
                Text(detail).font(.wlMeta).foregroundStyle(Graphite.textSecondary).fixedSize(horizontal: false, vertical: true)
                ForEach(caveats, id: \.self) { caveat in
                    Text("– " + caveat).font(.wlMeta).foregroundStyle(Graphite.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Graphite.accentText.opacity(0.6) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

extension AutoLockTimeout {
    /// Wording for the encrypted builds' option cards.
    var optionTitle: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
        case .never: "Only when you lock it"
        }
    }

    var optionDetail: String {
        switch self {
        case .immediately: "Locks the moment you switch apps or your screen turns off. Its key leaves memory at once."
        case .oneMinute, .fiveMinutes: "Switch to another app briefly and come back without entering your passcode."
        case .never: "Stays open in the background until you tap Lock WagLock or iOS closes it."
        }
    }

    var optionCaveats: [String] {
        switch self {
        case .immediately:
            return []
        case .oneMinute, .fiveMinutes:
            return ["Until the time runs out, anyone holding your unlocked iPhone can open WagLock without the passcode.",
                    "The library’s key stays in this iPhone’s memory while WagLock is in the background.",
                    "Albums, previews and exports still close as soon as you leave."]
        case .never:
            return ["Anyone who can unlock your iPhone can open WagLock without its passcode.",
                    "The library’s key stays in memory for as long as WagLock keeps running.",
                    "Albums, previews and exports still close as soon as you leave."]
        }
    }
}

/// The auto-lock option cards. Changing the choice takes effect the next time you leave.
struct AutoLockOptions: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AutoLockTimeout.allCases) { timeout in
                WagLockOptionCard(selected: settings.autoLockTimeout == timeout, title: timeout.optionTitle,
                                  badge: timeout == .immediately ? "Recommended" : nil,
                                  detail: timeout.optionDetail, caveats: timeout.optionCaveats) {
                    settings.autoLockTimeout = timeout
                }
                .accessibilityIdentifier("autoLock.\(timeout.rawValue)")
            }
        }
    }
}

/// The length option cards, for passcodes, album passwords and backup passwords.
/// Existing passcodes and passwords always keep working.
struct PasscodeLengthOptions: View {
    @State private var allowShort = PasscodePolicy.allowsShortPasscodes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WagLockOptionCard(selected: !allowShort, title: "Standard", badge: "Recommended",
                              detail: "Passcodes and album passwords: at least \(PasscodePolicy.standardMinimum) characters. Backup passwords: at least \(PasscodePolicy.standardBackupMinimum). Letters and numbers make them much harder to guess.") {
                set(false)
            }
            .accessibilityIdentifier("passcodeLength.standard")
            WagLockOptionCard(selected: allowShort, title: "Short",
                              detail: "Passcodes, album passwords and backup passwords can be as short as \(PasscodePolicy.shortMinimum) characters, such as a 4-digit PIN.",
                              caveats: ["A 4-digit PIN has only 10,000 possibilities.",
                                        "On this iPhone, the 30-second wait after each wrong guess slows guessing down. Someone with a full copy of the iPhone’s data could try every 4-digit passcode within an hour.",
                                        "A backup file has no wait at all. Anyone who gets a copy, for example from a cloud account, could try every 4-digit backup password within hours on an ordinary computer.",
                                        "Applies to new and changed passcodes and passwords in every library."]) {
                set(true)
            }
            .accessibilityIdentifier("passcodeLength.short")
        }
    }

    private func set(_ value: Bool) {
        PasscodePolicy.allowsShortPasscodes = value
        allowShort = value
    }
}

/// Onboarding: how quickly WagLock locks, and how short a passcode may be. Shown before
/// the passcode step so the length rule applies to the first passcode.
struct OnboardingLockingView: View {
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WagLockTitle(text: "How should WagLock lock?").padding(.top, 40)
                    Text("The recommended choices are the most private. You can change both later in Settings › Security & access.")
                        .font(.wlBody).foregroundStyle(Graphite.textMuted)
                    WagLockSectionLabel("Auto-lock").padding(.top, 4)
                    AutoLockOptions()
                    WagLockSectionLabel("Passcode & password length").padding(.top, 8)
                    PasscodeLengthOptions()
                }
            }
            Button("Continue", action: next)
                .buttonStyle(WagLockPrimaryButtonStyle()).accessibilityIdentifier("onboarding.locking.continue")
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
    }
}

/// Settings › Security & access › Auto-lock.
struct AutoLockSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WagLockTitle(text: "Auto-lock")
                Text("When WagLock locks after you leave it. This applies to all of WagLock.")
                    .font(.wlBody).foregroundStyle(Graphite.textMuted)
                AutoLockOptions()
                Text("WagLock always locks when you tap Lock WagLock, when your screen is recorded or mirrored, and when iOS closes it.")
                    .font(.wlMeta).foregroundStyle(Graphite.textMuted)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .background(Graphite.base)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings › Security & access › Passcode & password length.
struct PasscodeLengthSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WagLockTitle(text: "Passcode & password length")
                Text("The shortest passcode, album password or backup password WagLock accepts when you create or change one. Ones you already have keep working either way.")
                    .font(.wlBody).foregroundStyle(Graphite.textMuted)
                PasscodeLengthOptions()
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .background(Graphite.base)
        .navigationBarTitleDisplayMode(.inline)
    }
}
