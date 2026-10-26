import SwiftUI
import UIKit

enum PasswordKeyboard: String, CaseIterable, Identifiable {
    case numberPad, fullKeyboard
    static let preferenceKey = "waglock.passwordKeyboard"
    var id: String { rawValue }
    var title: String { self == .numberPad ? "Number pad" : "Full keyboard" }
    var keyboardType: UIKeyboardType { self == .numberPad ? .numberPad : .default }
}

struct PasswordKeyboardPicker: View {
    @Binding var selection: PasswordKeyboard
    var body: some View {
        Picker("Password keyboard", selection: $selection) {
            Text("Number pad").tag(PasswordKeyboard.numberPad)
                .accessibilityIdentifier("password.keyboard.number")
            Text("Full keyboard").tag(PasswordKeyboard.fullKeyboard)
                .accessibilityIdentifier("password.keyboard.full")
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("password.keyboard.picker")
    }
}

struct PasswordStrengthView: View {
    let password: String
    private var assessment: PasswordAssessment { PasswordAssessment(password) }
    private var color: Color { assessment.score < 40 ? .red : assessment.score < 70 ? .orange : .green }
    var body: some View {
        if !password.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Estimated strength: \(assessment.label) · \(assessment.score)/100")
                    .font(.caption).foregroundStyle(color)
                    .accessibilityIdentifier("password.strength")
                ProgressView(value: Double(assessment.score), total: 100).tint(color)
                    .accessibilityLabel("Estimated password strength")
                    .accessibilityValue("\(assessment.label), \(assessment.score) out of 100")
                Text("Local estimate only; not a guarantee or breach check.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Explicit confirmation for providers that fill only the focused password field.
/// No typing/paste heuristic, clipboard access, automatic mirroring or submission.
struct PasswordConfirmationButton: View {
    let password: String
    @Binding var confirmation: String
    let identifier: String

    var body: some View {
        Button {
            confirmation = password
            hideKeyboard()
        } label: {
            Label("Use entered password", systemImage: "checkmark")
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(identifier)
        .accessibilityHint("Fill confirmation with the password above. This does not save it.")
        .disabled(password.isEmpty || password.utf8.elementsEqual(confirmation.utf8))
    }
}

/// Reloads the live keyboard without recreating the field, filtering text or losing its selection.
struct SwitchablePasswordField: UIViewRepresentable {
    let title: String
    @Binding var text: String
    let keyboard: PasswordKeyboard
    var secure = true
    var contentType: UITextContentType = .password
    var identifier: String?
    var submitTitle = "Unlock"
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.placeholder = title
        field.accessibilityLabel = title
        field.accessibilityIdentifier = identifier ?? title
        field.textContentType = contentType
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.clearsOnBeginEditing = false
        field.returnKeyType = .go
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.textContentType = contentType
        field.isEnabled = context.environment.isEnabled
        let changedKeyboard = field.keyboardType != keyboard.keyboardType
        let changedSecurity = field.isSecureTextEntry != secure
        let start = field.selectedTextRange.map { field.offset(from: field.beginningOfDocument, to: $0.start) }
        let end = field.selectedTextRange.map { field.offset(from: field.beginningOfDocument, to: $0.end) }
        field.keyboardType = keyboard.keyboardType
        field.isSecureTextEntry = secure
        if changedSecurity || !(field.text ?? "").utf8.elementsEqual(text.utf8) {
            // Reset UIKit's secure-entry buffer while preserving exact Unicode bytes.
            if changedSecurity { field.text = nil }
            field.text = text
            if let start, let end,
               let first = field.position(from: field.beginningOfDocument, offset: min(start, text.utf16.count)),
               let last = field.position(from: field.beginningOfDocument, offset: min(end, text.utf16.count)) {
                field.selectedTextRange = field.textRange(from: first, to: last)
            }
        }
        if keyboard == .numberPad {
            let toolbar = UIToolbar()
            let submit = UIBarButtonItem(title: submitTitle, style: .done, target: context.coordinator,
                                         action: #selector(Coordinator.submit))
            submit.accessibilityIdentifier = "password.keyboard.submit"
            toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace), submit]
            toolbar.sizeToFit()
            field.inputAccessoryView = toolbar
        } else { field.inputAccessoryView = nil }
        if field.isFirstResponder && (changedKeyboard || changedSecurity) { field.reloadInputViews() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SwitchablePasswordField
        weak var field: UITextField?
        init(_ parent: SwitchablePasswordField) { self.parent = parent }
        @objc func changed(_ sender: UITextField) {
            field = sender
            parent.text = sender.text ?? ""
        }
        func textFieldDidBeginEditing(_ textField: UITextField) { field = textField }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            field = textField
            submit()
            return true
        }
        @objc func submit() { field?.resignFirstResponder(); parent.onSubmit() }
    }
}
