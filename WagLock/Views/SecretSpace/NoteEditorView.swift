/*@ai:risk=2|deps=SecretNote|lines=160*/
//
//  NoteEditorView.swift
//  WagLock
//
//  简洁的笔记编辑界面
//

import SwiftUI

struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var title: String
    @State private var content: String
    @State private var lastAutoSaved: Date?
    @State private var autoSaveTask: Task<Void, Never>?

    let isNewNote: Bool
    let onSave: (String, String) -> Void
    let onAutoSave: (String, String) -> Void

    init(
        initialTitle: String, initialContent: String, isNewNote: Bool,
        onSave: @escaping (String, String) -> Void,
        onAutoSave: @escaping (String, String) -> Void
    ) {
        self._title = State(initialValue: initialTitle)
        self._content = State(initialValue: initialContent)
        self.isNewNote = isNewNote
        self.onSave = onSave
        self.onAutoSave = onAutoSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Changes are saved automatically").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                Text("Title").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                TextField(String(localized: "note.title.placeholder"), text: $title)
                    .font(.body).textInputAutocapitalization(.sentences)
                    .focused($focusedField, equals: .title).padding(16)
                    .background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.border))
                    .accessibilityIdentifier("note.title")
                TextEditor(text: $content)
                    .font(.body).lineSpacing(6).focused($focusedField, equals: .content)
                    .scrollContentBackground(.hidden).padding(12).frame(minHeight: 320)
                    .background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("note.content")
                bottomToolbar
                Button("Save note") { onSave(title, content); dismiss() }
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
                Button("Done") { onSave(title, content); dismiss() }.disabled(isEmpty)
            }
        }
        .onAppear {
            focusedField = .content
        }
        .onChange(of: title) { _ in scheduleAutoSave() }
        .onChange(of: content) { _ in scheduleAutoSave() }
    }

    // MARK: - View Components

    private var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 底部工具栏
    private var bottomToolbar: some View {
        HStack {
            // 字数统计
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.caption2)
                Text(String(format: String(localized: "note.wordCount"), content.count))
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            Spacer()

            // 自动保存状态
            if let lastSaved = lastAutoSaved {
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

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task.detached(priority: .background) { [title, content] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                onAutoSave(title, content)
                lastAutoSaved = Date()
            }
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
            onSave: { _, _ in },
            onAutoSave: { _, _ in }
        )
    }
}
