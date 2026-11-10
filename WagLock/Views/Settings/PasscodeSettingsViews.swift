import SwiftUI

// Multi-library passcode screens. Every screen here renders identically in every
// library, including an install with a single passcode: none of them reads, counts or
// names other libraries, and every rejection uses the same text and 30-second wait.
// A too-short passcode is said plainly: the length rule is public and the same everywhere.

/// Clears entered secrets when the app leaves the foreground or the view disappears.
private struct ClearsSecretsModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let clear: () -> Void
    func body(content: Content) -> some View {
        content
            .onDisappear(perform: clear)
            .onChange(of: scenePhase) { _, phase in if phase == .background { clear() } }
    }
}

private extension View {
    func clearsSecrets(_ clear: @escaping () -> Void) -> some View { modifier(ClearsSecretsModifier(clear: clear)) }
}

/// Bottom-anchored primary button that shows the shared wait after a rejection.
private struct RetryingPrimaryButton: View {
    let title: String
    let retryAt: Date?
    let enabled: Bool
    let busy: Bool
    let action: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = retryAt.map { max(0, Int(ceil($0.timeIntervalSince(context.date)))) } ?? 0
            Button(action: action) {
                if busy { ProgressView().tint(Graphite.onAccent) }
                else if remaining > 0 { Text(String(format: "Try again in %d:%02d", remaining / 60, remaining % 60)) }
                else { Text(title) }
            }
            .buttonStyle(WagLockPrimaryButtonStyle())
            .disabled(!enabled || busy || remaining > 0)
        }
    }
}

private func rejectionNote(_ message: String) -> some View {
    let rejected = message.hasPrefix("That passcode can")
    return WagLockNote(kind: .error, title: rejected ? "This passcode can’t be used" : nil,
                       text: rejected ? "Choose another one. You can try again in 30 seconds." : message)
}

private func isRejection(_ error: Error) -> Bool {
    (error as? LibraryPasscodeService.Failure) == .rejected
}

// MARK: - Security & access

struct SecurityAccessView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel
    @ObservedObject private var settings = AppSettings.shared
    @State private var confirmLock = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WagLockTitle(text: "Security & access")
                HStack(spacing: 12) {
                    // Each status card opens its setting.
                    NavigationLink { AutoLockSettingsView() } label: {
                        statCard("timer", "Auto-lock", settings.autoLockTimeout.optionTitle,
                                 tint: settings.autoLockTimeout == .immediately ? Graphite.accentText : Graphite.warn)
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.autoLock.card")
                    NavigationLink { LibraryFaceIDView() } label: {
                        statCard("faceid", "Face ID", auth.isBiometricAssignedHere ? "On" : "Off", tint: Color(hex: 0xC9CFDB))
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.faceID.card")
                }
                WagLockSectionLabel("Unlocking").padding(.top, 6)
                VStack(spacing: 10) {
                    NavigationLink { LibraryFaceIDView() } label: {
                        WagLockRow(symbol: "faceid", title: "Face ID",
                                   detail: auth.isBiometricAssignedHere ? "On for this library" : "Off for this library")
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.faceID")
                    NavigationLink { PasscodesView() } label: {
                        WagLockRow(symbol: "key", title: "Passcodes", detail: "Change this passcode or add another")
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.passcodes")
                    NavigationLink { TimeLockView() } label: {
                        WagLockRow(symbol: "hourglass", title: "Time lock", detail: "Off · Keep this library closed for a set time")
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.timeLock")
                }
                WagLockSectionLabel("Locking").padding(.top, 6)
                VStack(spacing: 10) {
                    NavigationLink { AutoLockSettingsView() } label: {
                        WagLockRow(symbol: "timer", title: "Auto-lock", detail: settings.autoLockTimeout.optionTitle)
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.autoLock")
                    NavigationLink { PasscodeLengthSettingsView() } label: {
                        WagLockRow(symbol: "textformat.123", title: "Passcode & password length",
                                   detail: PasscodePolicy.allowsShortPasscodes ? "Short allowed · \(PasscodePolicy.shortMinimum) or more" : "Standard")
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.passcodeLength")
                }
                (Text("Keep your passcode safe. ").font(.wlMeta.weight(.semibold)).foregroundColor(Color(hex: 0xE3E7EF))
                 + Text("There is no passcode reset. Keep independent originals.").font(.wlMeta).foregroundColor(Graphite.textMuted))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Lock WagLock") { confirmLock = true }
                    .buttonStyle(WagLockDestructiveButtonStyle())
                    .accessibilityIdentifier("settings.lock")
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .background(Graphite.base)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Lock WagLock?", isPresented: $confirmLock) {
            Button("Lock WagLock", role: .destructive) { auth.logout() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func statCard(_ symbol: String, _ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(tint)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x7D8597))
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased()).font(WagLockFonts.poppins(11, .semibold, relativeTo: .caption))
                    .tracking(1.5).foregroundStyle(Graphite.textMuted)
                Text(value).font(WagLockFonts.poppins(17, .bold, relativeTo: .headline)).foregroundStyle(Graphite.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Passcodes

struct PasscodesView: View {
    @State private var sheet: Sheet?
    enum Sheet: String, Identifiable { case change, add, delete; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    WagLockTitle(text: "Passcodes")
                    Text("Each passcode opens its own library. Up to 16 on this iPhone.")
                        .font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textMuted)
                }
                WagLockSectionLabel("This library").padding(.top, 4)
                VStack(spacing: 8) {
                    Button { sheet = .change } label: {
                        WagLockRow(symbol: "key", title: "Change this passcode", detail: "Verify the current passcode first")
                    }.buttonStyle(.plain).accessibilityIdentifier("passcodes.change")
                    NavigationLink { TimeLockView() } label: {
                        WagLockRow(symbol: "hourglass", title: "Time lock", detail: "Off · This passcode stops working until the time ends")
                    }.buttonStyle(.plain).accessibilityIdentifier("passcodes.timeLock")
                    Button { sheet = .delete } label: {
                        WagLockRow(symbol: "trash", title: "Delete this library", detail: "Its contents and passcode", kind: .destructive)
                    }.buttonStyle(.plain).accessibilityIdentifier("passcodes.delete")
                }
                WagLockSectionLabel("On this phone").padding(.top, 4)
                Button { sheet = .add } label: {
                    WagLockRow(symbol: "plus", title: "Add another passcode", detail: "Creates a new, separate library", kind: .add)
                }.buttonStyle(.plain).accessibilityIdentifier("passcodes.add")
                WagLockNote(kind: .info, text: "This screen looks the same in every library, whether or not other passcodes exist. Wrong attempts count toward one shared limit.")
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .background(Graphite.base)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { which in
            switch which {
            case .change: ChangeLibraryPasscodeView()
            case .add: AddPasscodeView()
            case .delete: DeleteLibraryView()
            }
        }
    }
}

// MARK: - Change this passcode

struct ChangeLibraryPasscodeView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PasswordKeyboard.preferenceKey) private var keyboardRaw = PasswordKeyboard.numberPad.rawValue
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var retryAt: Date?
    @State private var busy = false
    private var numberPad: Binding<Bool> {
        Binding(get: { keyboardRaw == PasswordKeyboard.numberPad.rawValue },
                set: { keyboardRaw = ($0 ? PasswordKeyboard.numberPad : .fullKeyboard).rawValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WagLockSheetHeader(title: "Change this passcode") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WagLockTitle(text: "A new key for this library", size: .sheet)
                    Text("Only this library’s passcode changes. Its contents, backups and Face ID setting stay as they are.")
                        .font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textSecondary)
                    WagLockKeyboardPicker(numberPad: numberPad)
                    WagLockField(symbol: "lock", placeholder: "Current passcode", text: $current, numberPad: numberPad.wrappedValue)
                    WagLockField(symbol: "key", placeholder: "New passcode (\(PasscodePolicy.rangeText) characters)", text: $new,
                                 isError: error != nil, numberPad: numberPad.wrappedValue, contentType: .newPassword)
                    WagLockField(symbol: "checkmark", placeholder: "Confirm passcode", text: $confirm,
                                 numberPad: numberPad.wrappedValue, contentType: .newPassword)
                    if let hint = PasscodePolicy.lengthHint(new, minimum: PasscodePolicy.minimumLength) {
                        Text(hint).font(.wlMeta).foregroundStyle(Graphite.warn).accessibilityIdentifier("passcodes.change.tooShort")
                    }
                    PasswordConfirmationButton(password: new, confirmation: $confirm, identifier: "passcodes.change.useEntered")
                    if !confirm.isEmpty && !PasswordText.matches(new, confirm) {
                        Text("The new passcodes don’t match.").font(.wlMeta).foregroundStyle(Graphite.danger)
                    }
                    if let error { rejectionNote(error) }
                }
            }
            RetryingPrimaryButton(title: "Change passcode", retryAt: retryAt,
                                  enabled: !current.isEmpty && new.count >= PasscodePolicy.minimumLength && PasswordText.matches(new, confirm),
                                  busy: busy, action: submit)
                .accessibilityIdentifier("passcodes.change.submit")
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
        .background(Graphite.base)
        .presentationDragIndicator(.hidden)
        .clearsSecrets { current = ""; new = ""; confirm = "" }
    }

    private func submit() {
        let (old, value) = (current, new)
        let session = auth.librarySessionID
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await auth.changeLibraryPasscode(current: old, new: value)
                guard session == auth.librarySessionID else { return }
                dismiss()
            } catch {
                guard session == auth.librarySessionID else { return }
                self.error = AuthenticationViewModel.message(for: error)
                if isRejection(error) { retryAt = Date().addingTimeInterval(PasswordAttemptLimiter.rejectionWait) }
                current = ""
            }
        }
    }
}

// MARK: - Add a passcode

struct AddPasscodeView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PasswordKeyboard.preferenceKey) private var keyboardRaw = PasswordKeyboard.numberPad.rawValue
    @State private var passcode = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var retryAt: Date?
    @State private var busy = false
    @State private var created = false
    private var numberPad: Binding<Bool> {
        Binding(get: { keyboardRaw == PasswordKeyboard.numberPad.rawValue },
                set: { keyboardRaw = ($0 ? PasswordKeyboard.numberPad : .fullKeyboard).rawValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WagLockSheetHeader(title: "Add a passcode", cancelTitle: created ? "Done" : "Cancel") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WagLockTitle(text: "A new library,\nits own key")
                    VStack(alignment: .leading, spacing: 10) {
                        point("square.on.square", "Separate content and keys. Nothing here moves over.")
                        point("lock", "To open it, lock WagLock and enter this passcode on the usual screen.")
                        point("icloud", "Back it up on its own. No passcode can reset another.")
                    }
                    .padding(14).background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
                    if created {
                        WagLockNote(kind: .info, title: "Library created",
                                    text: "Lock WagLock and enter the new passcode to open it.")
                    } else {
                        WagLockKeyboardPicker(numberPad: numberPad)
                        WagLockField(symbol: "lock", placeholder: "New passcode (\(PasscodePolicy.rangeText) characters)", text: $passcode,
                                     isError: error != nil, numberPad: numberPad.wrappedValue, contentType: .newPassword)
                        WagLockField(symbol: "checkmark", placeholder: "Confirm passcode", text: $confirm,
                                     numberPad: numberPad.wrappedValue, contentType: .newPassword)
                        if let hint = PasscodePolicy.lengthHint(passcode, minimum: PasscodePolicy.minimumLength) {
                            Text(hint).font(.wlMeta).foregroundStyle(Graphite.warn).accessibilityIdentifier("passcodes.add.tooShort")
                        }
                        PasswordConfirmationButton(password: passcode, confirmation: $confirm, identifier: "passcodes.add.useEntered")
                        if let error { rejectionNote(error) }
                        else {
                            Text("If a passcode can’t be used, you’ll just be asked to choose another.")
                                .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                        }
                    }
                }
            }
            if !created {
                RetryingPrimaryButton(title: "Create library", retryAt: retryAt,
                                      enabled: passcode.count >= PasscodePolicy.minimumLength && PasswordText.matches(passcode, confirm),
                                      busy: busy, action: submit)
                    .accessibilityIdentifier("passcodes.add.submit")
            }
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
        .background(Graphite.base)
        .clearsSecrets { passcode = ""; confirm = "" }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: { Image(systemName: symbol).foregroundStyle(Graphite.accentText) }
    }

    private func submit() {
        let value = passcode
        let session = auth.librarySessionID
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await auth.addLibraryPasscode(value)
                guard session == auth.librarySessionID else { return }
                passcode = ""; confirm = ""; created = true
            } catch {
                guard session == auth.librarySessionID else { return }
                self.error = AuthenticationViewModel.message(for: error)
                if isRejection(error) { retryAt = Date().addingTimeInterval(PasswordAttemptLimiter.rejectionWait) }
            }
        }
    }
}

// MARK: - Time lock

struct TimeLockView: View {
    enum Preset: String, CaseIterable, Identifiable {
        case hour = "1 hour", day = "24 hours", threeDays = "3 days", custom = "Custom"
        var id: String { rawValue }
        var interval: TimeInterval? {
            switch self { case .hour: 3600; case .day: 86_400; case .threeDays: 259_200; case .custom: nil }
        }
    }

    @EnvironmentObject private var auth: AuthenticationViewModel
    @State private var preset: Preset = .day
    @State private var custom = Date().addingTimeInterval(7 * 86_400)
    @State private var passcode = ""
    @State private var error: String?
    @State private var busy = false
    @State private var confirming = false

    private var until: Date { preset.interval.map { Date().addingTimeInterval($0) } ?? custom }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    WagLockTitle(text: "Close this library for a while", size: .sheet)
                    Text("Until the time ends, this passcode won’t open this library. Entering it looks exactly like a wrong passcode.")
                        .font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Preset.allCases) { option in
                        Button { preset = option } label: {
                            Text(option.rawValue).font(preset == option ? .wlBodyStrong : .wlBody)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(preset == option ? Graphite.onAccent : Graphite.textPrimary)
                                .background(preset == option ? AnyShapeStyle(Graphite.accentGradient) : AnyShapeStyle(Graphite.surface1),
                                            in: RoundedRectangle(cornerRadius: 10))
                        }.accessibilityAddTraits(preset == option ? .isSelected : [])
                    }
                }
                if preset == .custom {
                    DatePicker("Opens again", selection: $custom, in: Date().addingTimeInterval(600)...,
                               displayedComponents: [.date, .hourAndMinute])
                        .font(.wlBody).foregroundStyle(Graphite.textPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    WagLockSectionLabel("Opens again")
                    Text(until.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(.wlHeading).foregroundStyle(Graphite.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
                WagLockNote(kind: .caution, text: "It can’t be ended early, from any library. Make sure nothing you need is only in here. Attempts during the lock count toward the shared limit. If Face ID opens this library, it is turned off.")
                WagLockSectionLabel("This library’s passcode")
                WagLockField(symbol: "lock", placeholder: "Confirm with this library’s passcode", text: $passcode, isError: error != nil)
                if let error { WagLockNote(kind: .error, text: error) }
                Button("Start time lock") { confirming = true }
                    .buttonStyle(WagLockPrimaryButtonStyle())
                    .disabled(passcode.isEmpty || busy)
                    .accessibilityIdentifier("timeLock.start")
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .background(Graphite.base)
        .navigationTitle("Time lock").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Start the time lock?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Start time lock", role: .destructive, action: start)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WagLock locks now. This passcode won’t work until the time ends.")
        }
        .clearsSecrets { passcode = "" }
    }

    private func start() {
        let value = passcode, end = until
        let session = auth.librarySessionID
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await auth.timeLockLibrary(passcode: value, until: end) }
            catch {
                guard session == auth.librarySessionID else { return }
                self.error = AuthenticationViewModel.message(for: error); passcode = ""
            }
        }
    }
}

// MARK: - Delete this library

struct DeleteLibraryView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var understood = false
    @State private var passcode = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WagLockSheetHeader(title: "") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WagLockTitle(text: "Delete this library", size: .sheet)
                    Text("Permanently deletes this library’s photos, videos, audio, files and notes, and its passcode.")
                        .font(.wlBody).foregroundStyle(Graphite.textSecondary).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 10) {
                        bullet("Nothing else on this iPhone changes.")
                        bullet("Backups and originals saved elsewhere are kept.")
                        bullet("Its key is overwritten. It can’t be recovered on this iPhone.")
                    }
                    .padding(14).background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
                    Toggle(isOn: $understood) {
                        Text("I understand this can’t be undone").font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary)
                    }
                    .tint(Graphite.dangerLine).accessibilityIdentifier("deleteLibrary.understood")
                    WagLockSectionLabel("This library’s passcode")
                    WagLockField(symbol: "lock", placeholder: "This library’s passcode", text: $passcode, isError: error != nil)
                    if let error { WagLockNote(kind: .error, text: error) }
                }
            }
            Button("Delete library", action: delete)
                .buttonStyle(WagLockDestructiveButtonStyle())
                .disabled(!understood || passcode.isEmpty || busy)
                .accessibilityIdentifier("deleteLibrary.confirm")
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
        .background(Graphite.base)
        .clearsSecrets { passcode = ""; understood = false }
    }

    private func bullet(_ text: String) -> some View {
        Label {
            Text(text).font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textSecondary)
        } icon: { Image(systemName: "info.circle").foregroundStyle(Graphite.textMuted) }
    }

    private func delete() {
        let value = passcode
        let session = auth.librarySessionID
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await auth.deleteLibrary(passcode: value) }
            catch {
                guard session == auth.librarySessionID else { return }
                self.error = AuthenticationViewModel.message(for: error); passcode = ""
            }
        }
    }
}

// MARK: - Face ID

/// Face ID can open one library and always opens that one. Unassigned libraries show
/// "Off for this library" and never say where Face ID is assigned.
struct LibraryFaceIDView: View {
    @EnvironmentObject private var auth: AuthenticationViewModel
    @State private var passcode = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "faceid").font(.system(size: 26)).foregroundStyle(Graphite.accentText)
                        .frame(width: 56, height: 56).background(Graphite.surface2, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.isBiometricAssignedHere ? "On for this library" : "Off for this library")
                            .font(.wlHeading).foregroundStyle(Graphite.textPrimary)
                        Text("This library’s passcode always works").font(.wlMeta).foregroundStyle(Graphite.textMuted)
                    }
                }
                WagLockNote(kind: .caution, text: "Face ID can open one library. It always opens that one, so anyone who has you unlock with your face will see it. Choose the library you’re comfortable showing.")
                if auth.isBiometricAssignedHere {
                    Button("Turn off Face ID") { auth.disableBiometricUnlock() }
                        .buttonStyle(WagLockDestructiveButtonStyle())
                        .accessibilityIdentifier("vault.faceID.disable")
                } else {
                    WagLockSectionLabel("This library’s passcode")
                    WagLockField(symbol: "lock", placeholder: "This library’s passcode", text: $passcode, isError: error != nil)
                        .accessibilityIdentifier("vault.faceID.password")
                    Text("If Face ID is set for another passcode, it moves here.")
                        .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                    if let error { WagLockNote(kind: .error, text: error) }
                    Button("Use Face ID here", action: enable)
                        .buttonStyle(WagLockPrimaryButtonStyle())
                        .disabled(passcode.isEmpty || busy)
                        .accessibilityIdentifier("vault.faceID.enable")
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .background(Graphite.base)
        .navigationTitle("Face ID").navigationBarTitleDisplayMode(.inline)
        .clearsSecrets { passcode = "" }
    }

    private func enable() {
        let value = passcode
        let session = auth.librarySessionID
        passcode = ""; busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await auth.enableBiometricUnlock(password: value) }
            catch {
                guard auth.isAuthenticated, session == auth.librarySessionID else { return }
                if case .invalidPassword? = error as? VaultAccessError { self.error = "Wrong passcode." }
                else { self.error = "Face ID was cancelled or unavailable. Try again." }
            }
        }
    }
}
