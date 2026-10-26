/*@ai:risk=2|deps=SecretNote|lines=160*/
//
//  NoteEditorView.swift
//  WagLock
//
//  Simple note editor
//

import SwiftUI

struct NoteEditorView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var title: String
    @State private var content: String
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var autosave = NoteAutosaveCoordinator()
    @State private var savedExplicitly = false

    let isNewNote: Bool
    let sessionID: UUID?
    let maySave: @MainActor () -> Bool
    let onSave: (String, String) -> Bool
    let onAutoSave: (String, String) -> Bool

    init(
        initialTitle: String, initialContent: String, isNewNote: Bool,
        sessionID: UUID? = nil, maySave: @escaping @MainActor () -> Bool = { false },
        onSave: @escaping (String, String) -> Bool,
        onAutoSave: @escaping (String, String) -> Bool
    ) {
        self._title = State(initialValue: initialTitle)
        self._content = State(initialValue: initialContent)
        self.isNewNote = isNewNote
        self.sessionID = sessionID
        self.maySave = maySave
        self.onSave = onSave
        self.onAutoSave = onAutoSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(isNewNote ? "Drafts are saved automatically" : "Changes are saved automatically").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                Text("Title").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                TextField(String(localized: "note.title.placeholder"), text: Binding(get: { title }, set: { value in
                    guard value != title else { return }
                    title = value; scheduleAutoSave(title: value, content: content)
                }))
                    .font(.body).textInputAutocapitalization(.sentences)
                    .focused($focusedField, equals: .title).padding(16)
                    .background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.border))
                    .accessibilityIdentifier("note.title")
                TextEditor(text: Binding(get: { content }, set: { value in
                    guard value != content else { return }
                    content = value; scheduleAutoSave(title: title, content: value)
                }))
                    .font(.body).lineSpacing(6).focused($focusedField, equals: .content)
                    .scrollContentBackground(.hidden).padding(12).frame(minHeight: 320)
                    .background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("note.content")
                bottomToolbar
                if let error = autosave.error {
                    Text(error).font(.footnote).foregroundStyle(ColorTheme.destructive)
                        .accessibilityIdentifier("note.save.error")
                }
                Button("Save note", action: saveAndDismiss)
                    .buttonStyle(WagLockPrimaryButtonStyle()).disabled(isEmpty)
                    .accessibilityIdentifier("note.save")
            }.padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ColorTheme.primaryBackground.ignoresSafeArea())
        .navigationTitle(isNewNote ? "New note" : "Edit note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: saveAndDismiss).disabled(isEmpty)
            }
        }
        .onAppear {
            autosave.bind(to: vaultServices.documents)
            // Text is seeded at presentation. Reappearing after a keyboard,
            // navigation or scene transition must not overwrite current edits.
            focusedField = .content
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { autosave.flush() } }
        .onDisappear {
            if savedExplicitly { autosave.cancel() } else { autosave.flush() }
        }
    }

    // MARK: - View Components

    private var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Bottom toolbar
    private var bottomToolbar: some View {
        HStack {
            // Word count
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.caption2)
                Text(String(format: String(localized: "note.wordCount"), content.count))
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            Spacer()

            // Autosave status
            if let lastSaved = autosave.lastSavedAt {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text(
                        String(
                            format: String(localized: "note.lastSaved"),
                            formatted(date: lastSaved))
                    )
                    .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)

    }

    private func scheduleAutoSave(title: String, content: String) {
        guard let sessionID else { return }
        autosave.schedule(session: sessionID, authorize: maySave) {
            onAutoSave(title, content)
        }
    }

    private func saveAndDismiss() {
        guard let sessionID else { return }
        let title = title, content = content
        if autosave.saveNow(session: sessionID, authorize: maySave, commit: { onSave(title, content) }) {
            savedExplicitly = true
            dismiss()
        }
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppConstants.presentationLocale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private enum Field {
        case title
        case content
    }
}

#Preview {
    NavigationStack {
        NoteEditorView(
            initialTitle: "",
            initialContent: "",
            isNewNote: true,
            onSave: { _, _ in true },
            onAutoSave: { _, _ in true }
        )
    }
}
