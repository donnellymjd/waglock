/*@ai:risk=2|deps=SecretNote|lines=200*/
//
//  SecretSpaceView.swift
//  WagLock
//
//  隐藏空间记事本列表
//  轻量级的私密笔记体验
//

import SwiftData
import SwiftUI

struct SecretSpaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SecretNote.modifiedAt, order: .reverse) private var notes: [SecretNote]
    @EnvironmentObject private var guestModeManager: GuestModeManager

    private let draftManager = SecretNoteDraftManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WagLockSubtitle(text: "A little room to think")
                notesContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ColorTheme.primaryBackground.ignoresSafeArea())
            .navigationTitle(String(localized: "secretSpace.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if guestModeManager.isOwnerMode {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink {
                            createNoteEditor()
                        } label: {
                            Text("New")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notesContent: some View {
        if guestModeManager.isGuestMode || notes.isEmpty {
            emptyState
        } else {
            List {
                if !pinnedNotes.isEmpty {
                    Section(String(localized: "secretSpace.section.pinned")) {
                        ForEach(pinnedNotes) { note in
                            NavigationLink {
                                editNoteEditor(note: note)
                            } label: {
                                NoteRow(note: note)
                            }.wagLockCardRow()
                        }
                        .onDelete { indexSet in
                            delete(indices: indexSet, from: pinnedNotes)
                        }
                    }
                }
                Section(String(localized: "secretSpace.section.notes")) {
                    ForEach(regularNotes) { note in
                        NavigationLink {
                            editNoteEditor(note: note)
                        } label: {
                            NoteRow(note: note)
                        }.wagLockCardRow()
                    }
                    .onDelete { delete(indices: $0, from: regularNotes) }
                }
            }
            .wagLockList()
        }
    }

    private var pinnedNotes: [SecretNote] {
        notes.filter { $0.isFavorite }
    }

    private var regularNotes: [SecretNote] {
        notes.filter { !$0.isFavorite }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                WagLockEmptyState(symbol: "note.text", title: "A little room to think.", detail: "Keep the thoughts you want to come back to.")
                if guestModeManager.isOwnerMode {
                    NavigationLink { createNoteEditor() } label: { Text("New note") }
                        .buttonStyle(WagLockPrimaryButtonStyle()).padding(.horizontal, 24)
                }
            }.padding(.vertical, 48)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func createNoteEditor() -> some View {
        let draft = draftManager.loadDraft()
        NoteEditorView(
            initialTitle: draft?.title ?? "",
            initialContent: draft?.content ?? "",
            isNewNote: true,
            onSave: { title, content in
                saveNote(existing: nil, title: title, content: content, clearDraft: true)
            },
            onAutoSave: { title, content in
                draftManager.saveDraft(title: title, content: content)
            }
        )
        .environment(\.modelContext, modelContext)
    }

    @ViewBuilder
    private func editNoteEditor(note: SecretNote) -> some View {
        NoteEditorView(
            initialTitle: note.title,
            initialContent: note.content,
            isNewNote: false,
            onSave: { title, content in
                saveNote(existing: note, title: title, content: content)
            },
            onAutoSave: { title, content in
                saveNote(existing: note, title: title, content: content)
            }
        )
        .environment(\.modelContext, modelContext)
    }

    private func delete(at offsets: IndexSet) {
        withAnimation {
            offsets.map { notes[$0] }.forEach(modelContext.delete)
            saveOrRollback()
        }
    }

    private func delete(indices: IndexSet, from subset: [SecretNote]) {
        withAnimation {
            indices.map { subset[$0] }.forEach(modelContext.delete)
            saveOrRollback()
        }
    }

    /// 保存失败时回滚，保证 UI（@Query）与持久化状态一致
    private func saveOrRollback() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }

    private func saveNote(
        existing: SecretNote?, title: String, content: String, clearDraft: Bool = false
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? String(localized: "note.title.placeholder") : trimmed
        let now = Date()

        if let note = existing {
            note.title = finalTitle
            note.content = content
            note.modifiedAt = now
        } else {
            let newNote = SecretNote()
            newNote.title = finalTitle
            newNote.content = content
            newNote.createdAt = now
            newNote.modifiedAt = now
            modelContext.insert(newNote)
        }

        if clearDraft {
            draftManager.clearDraft()
        }

        do {
            try modelContext.save()
        } catch {
        }
    }

}

// MARK: - Note Row

private struct NoteRow: View {
    @Environment(\.modelContext) private var modelContext
    let note: SecretNote
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                if note.isFavorite {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Text(note.preview)
                .font(.body)
                .foregroundStyle(ColorTheme.secondaryText)
                .lineLimit(2)

            HStack {
                Text("Updated \(note.formattedModifiedDate) · On this device")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: String(localized: "note.wordCount"), note.wordCount))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 0)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                note.isFavorite.toggle()
                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                }
            } label: {
                Label(
                    note.isFavorite
                        ? String(localized: "secretSpace.unpin")
                        : String(localized: "secretSpace.pin"),
                    systemImage: note.isFavorite ? "pin.slash" : "pin"
                )
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                modelContext.delete(note)
                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                }
            } label: {
                Label(String(localized: "common.delete"), systemImage: "trash")
            }
        }
    }
}

#Preview {
    SecretSpaceView()
        .modelContainer(for: SecretNote.self, inMemory: true)
}
