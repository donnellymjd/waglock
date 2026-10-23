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
    @EnvironmentObject private var auth: AuthenticationViewModel
    @EnvironmentObject private var guestModeManager: GuestModeManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft: SecretNoteDraft?
    private struct NewNotePresentation: Hashable { let id = UUID() }
    @State private var newNote: NewNotePresentation?

    private var draftManager: SecretNoteDraftManager { LibraryWriteCoordinator.draftManager(in: modelContext) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WagLockSubtitle(text: "A little room to think")
                notesContent.onAppear(perform: refreshDraft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ColorTheme.primaryBackground.ignoresSafeArea())
            .navigationTitle(String(localized: "secretSpace.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if guestModeManager.isOwnerMode {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("New") { newNote = NewNotePresentation() }
                    }
                }
            }
            .navigationDestination(item: $newNote) { _ in createNoteEditor() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshDraft() } }
    }

    private func refreshDraft() {
        guard auth.isAuthenticated, guestModeManager.isOwnerMode else { draft = nil; return }
        draft = draftManager.loadDraft()
    }

    @ViewBuilder
    private var notesContent: some View {
        if guestModeManager.isGuestMode || (notes.isEmpty && draft == nil) {
            emptyState
        } else {
            List {
                if let draft {
                    Section("Unfinished note") {
                        Button { newNote = NewNotePresentation() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Resume draft", systemImage: "square.and.pencil").font(.headline)
                                    Text(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled note" : draft.title)
                                        .foregroundStyle(ColorTheme.secondaryText).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(ColorTheme.secondaryText)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("notes.resumeDraft").wagLockCardRow()
                    }
                }
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
            .accessibilityIdentifier("notes.list")
            .accessibilityValue("\(notes.count) saved notes")
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
                    Button("New note") { newNote = NewNotePresentation() }
                        .buttonStyle(WagLockPrimaryButtonStyle()).padding(.horizontal, 24)
                }
            }.padding(.vertical, 48)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func createNoteEditor() -> some View {
        let session = auth.librarySessionID
        // This destination is created only after an explicit presentation request.
        // Seed text before constructing controls; later appearances never reload it.
        let storedDraft = mayWrite(session) ? draftManager.loadDraft() : nil
        NoteEditorView(
            initialTitle: storedDraft?.title ?? "",
            initialContent: storedDraft?.content ?? "",
            isNewNote: true,
            sessionID: session, maySave: { mayWrite(session) },
            onSave: { title, content in
                saveNote(existing: nil, title: title, content: content, clearDraft: true, session: session)
            },
            onAutoSave: { title, content in
                guard mayWrite(session) else { return false }
                let saved = draftManager.saveDraft(title: title, content: content)
                if saved { refreshDraft() }
                return saved
            }
        )
        .environment(\.modelContext, modelContext)
    }

    @ViewBuilder
    private func editNoteEditor(note: SecretNote) -> some View {
        let session = auth.librarySessionID
        NoteEditorView(
            initialTitle: note.title,
            initialContent: note.content,
            isNewNote: false,
            sessionID: session, maySave: { mayWrite(session) },
            onSave: { title, content in
                saveNote(existing: note, title: title, content: content, session: session)
            },
            onAutoSave: { title, content in
                saveNote(existing: note, title: title, content: content, session: session)
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
            try LibraryWriteCoordinator.save(modelContext)
        } catch {
            modelContext.rollback()
        }
    }

    private func saveNote(
        existing: SecretNote?, title: String, content: String, clearDraft: Bool = false, session: UUID
    ) -> Bool {
        guard mayWrite(session) else { return false }
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

        do {
            try LibraryWriteCoordinator.save(modelContext)
            if clearDraft { draftManager.clearDraft(); refreshDraft() }
            return true
        } catch {
            modelContext.rollback()
            return false
        }
    }

    private func mayWrite(_ session: UUID) -> Bool {
        auth.isAuthenticated && guestModeManager.isOwnerMode && auth.librarySessionID == session
            && DocumentPreviewService.shared.permits(session, revision: DocumentPreviewService.shared.revision)
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
                    try LibraryWriteCoordinator.save(modelContext)
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
                    try LibraryWriteCoordinator.save(modelContext)
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
