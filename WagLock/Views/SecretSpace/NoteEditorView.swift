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
            VStack(alignment: .leading, spacing: 12) {
                Label(autosave.lastSavedAt == nil ? (isNewNote ? "Drafts save automatically" : "Changes save automatically") : "Saved · encrypted",
                      systemImage: autosave.lastSavedAt == nil ? "lock" : "checkmark.circle")
                    .font(.wlMeta).foregroundStyle(autosave.lastSavedAt == nil ? Graphite.textMuted : Color(hex: 0x7FD8A4))
                TextField(String(localized: "note.title.placeholder"), text: Binding(get: { title }, set: { value in
                    guard value != title else { return }
                    title = value; scheduleAutoSave(title: value, content: content)
                }))
                    .font(.wlSheetTitle).foregroundStyle(Graphite.textPrimary)
                    .textInputAutocapitalization(.sentences)
                    .focused($focusedField, equals: .title)
                    .accessibilityIdentifier("note.title")
                Text(Date().formatted(.dateTime.weekday(.wide).hour().minute()))
                    .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                TextEditor(text: Binding(get: { content }, set: { value in
                    guard value != content else { return }
                    content = value; scheduleAutoSave(title: title, content: value)
                }))
                    .font(WagLockFonts.poppins(16, .regular, relativeTo: .body)).foregroundStyle(Graphite.textPrimary)
                    .lineSpacing(6).focused($focusedField, equals: .content)
                    .scrollContentBackground(.hidden).frame(minHeight: 320)
                    .accessibilityIdentifier("note.content")
                if let error = autosave.error {
                    WagLockNote(kind: .error, text: error)
                        .accessibilityIdentifier("note.save.error")
                }
                Button("Save note", action: saveAndDismiss)
                    .buttonStyle(WagLockPrimaryButtonStyle()).disabled(isEmpty)
                    .accessibilityIdentifier("note.save")
            }.padding(.horizontal, 22).padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) { formatBar }
        .scrollDismissesKeyboard(.interactively)
        .background(Graphite.base.ignoresSafeArea())
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

    /// Formatting bar. Notes are plain text: each tool starts a new line with its marker.
    private var formatBar: some View {
        HStack(spacing: 4) {
            formatButton("textformat.size", "Heading", "# ")
            formatButton("list.bullet", "List", "• ")
            formatButton("checklist", "Checklist", "☐ ")
            Spacer()
            Text("\(content.count) characters").font(.wlMeta).foregroundStyle(Graphite.textMuted)
                .padding(.trailing, 10)
        }
        .padding(6)
        .background(Graphite.bar, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 16).padding(.bottom, 6)
    }

    private func formatButton(_ symbol: String, _ label: String, _ marker: String) -> some View {
        Button {
            let prefix = content.isEmpty || content.hasSuffix("\n") ? "" : "\n"
            content += prefix + marker
            scheduleAutoSave(title: title, content: content)
            focusedField = .content
        } label: {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Graphite.textPrimary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
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
