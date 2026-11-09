//
//  FilesView.swift
//  WagLock
//
//  Files view
//  Manages and previews file types (PDF, text, etc.)
//

import SwiftData
import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    // Query only file-type media
    @Query(
        filter: #Predicate<MediaItem> { item in
            item.typeRawValue == "document"
        },
        sort: \MediaItem.createdAt,
        order: .reverse
    )
    private var storedFiles: [MediaItem]

    private var files: [MediaItem] { storedFiles.filter { $0.type != .audio } }

    // MARK: - State

    @EnvironmentObject private var guestModeManager: GuestModeManager
    @State private var showImportView = false
    private struct PreviewSelection: Identifiable {
        let id = UUID()
        let pager: FilePagerView
    }
    @State private var selectedPreview: PreviewSelection?
    @State private var searchText = ""
    @State private var kind: FileKind = .all
    enum FileKind: String, CaseIterable, Identifiable {
        case all = "All", pdfs = "PDFs", documents = "Documents", other = "Other"
        var id: String { rawValue }
        func matches(_ ext: String) -> Bool {
            let ext = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let documents: Set<String> = ["doc", "docx", "txt", "md", "rtf", "pages", "odt", "xls", "xlsx", "csv", "numbers", "ppt", "pptx", "key"]
            switch self {
            case .all: return true
            case .pdfs: return ext == "pdf"
            case .documents: return documents.contains(ext)
            case .other: return ext != "pdf" && !documents.contains(ext)
            }
        }
    }
    @State private var fileToDelete: MediaItem?
    @State private var deleteErrorMessage: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        WagLockTitle(text: String(localized: "files.title"))
                        Text("\(guestModeManager.isGuestMode ? 0 : files.count) file\(files.count == 1 ? "" : "s") · On this device")
                            .font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textMuted)
                    }
                    WagLockSearchField(title: "Search files", text: $searchText)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FileKind.allCases) { option in
                                WagLockChip(title: option.rawValue, selected: kind == option) { kind = option }
                                    .accessibilityIdentifier("files.filter." + option.rawValue.lowercased())
                            }
                        }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 8)
                ZStack {
                // Always show the empty state in guest mode
                if guestModeManager.isGuestMode || files.isEmpty {
                    emptyStateView
                } else {
                    fileListView
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Graphite.base)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Hide the import button in guest mode
                    if guestModeManager.isOwnerMode {
                        WagLockRoundButton(symbol: "plus", label: "Add files", prominent: true) {
                            showImportView = true
                        }
                        .accessibilityIdentifier("files.import")
                    }
                }
            }
            .sheet(isPresented: $showImportView) {
                ImportButtonsView(onImportComplete: { items in
                })
                .environment(\.modelContext, modelContext)
                .environmentObject(authViewModel)
            }
            .sheet(item: $selectedPreview) { selection in
                NavigationStack {
                    // Paging container: swipe left/right between file previews
                    selection.pager
                }
                .environment(\.modelContext, modelContext)
                .environmentObject(authViewModel)
            }
            .alert(
                String(localized: "media.delete.title"),
                isPresented: Binding(
                    get: { fileToDelete != nil },
                    set: { if !$0 { fileToDelete = nil } }
                ),
                presenting: fileToDelete
            ) { file in
                Button(String(localized: "common.delete"), role: .destructive) {
                    deleteFile(file)
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: { _ in
                Text(String(localized: "media.delete.confirmation"))
            }
            .alert(
                String(localized: "common.error"),
                isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "")
            }

        }
    }

    // Missing ciphertext is an explicit read/recovery error. Never delete
    // library records automatically or inspect dismissed models in a late task.

    // MARK: - Empty State

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 24) {
                WagLockEmptyState(symbol: "folder", title: "A place for your files.", detail: "Add documents and files you want to keep close. Your originals stay where they are.")
                if guestModeManager.isOwnerMode {
                    Button("Add files") { showImportView = true }
                        .buttonStyle(WagLockPrimaryButtonStyle()).padding(.horizontal, 24)
                }
            }.padding(.vertical, 48)
        }
    }

    // MARK: - File List

    private var fileListView: some View {
        List {
            Section {
            ForEach(filteredFiles) { file in
                FileRowView(file: file)
                    .wagLockCardRow()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPreview = PreviewSelection(pager: FilePagerView(
                            files: filteredFiles, initialFile: file, sessionID: authViewModel.librarySessionID))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            fileToDelete = file
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    }
            }
            } header: { WagLockSectionLabel("Recently added") }
            Section {
                WagLockNote(kind: .info, text: "Files open right here. Choose Export when you want a copy outside WagLock.")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }
        .wagLockList()
    }

    // MARK: - Computed Properties

    private var filteredFiles: [MediaItem] {
        files.filter { file in
            kind.matches(file.fileExtension)
                && (searchText.isEmpty || file.fileName.localizedCaseInsensitiveContains(searchText))
        }
    }

    // MARK: - Methods

    private func deleteFile(_ file: MediaItem) {
        let encryptedPath = file.encryptedPath

        // Commit the database deletion first and delete files only after it succeeds,
        // so a failed save never leaves records pointing at deleted files
        modelContext.delete(file)
        do {
            try LibraryWriteCoordinator.save(modelContext)
        } catch {
            modelContext.rollback()
            deleteErrorMessage = String(
                format: String(localized: "gallery.error.deleteFailed"),
                error.localizedDescription)
            return
        }

        do {
            try vaultServices.storage.deleteFile(path: encryptedPath)
        } catch {
            // The record is gone; a failed file delete only leaves an unreferenced encrypted file
        }
    }
}

// MARK: - File Row View

struct FileRowView: View {
    let file: MediaItem

    var body: some View {
        HStack(spacing: 14) {
            fileIcon.font(.system(size: 18)).foregroundStyle(Graphite.accentText)
                .frame(width: 40, height: 40).background(Graphite.surface2, in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.fullFileName).font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary).lineLimit(2)
                Text("\(file.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()) · \(file.formattedFileSize) · \(file.createdAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.wlMeta).foregroundStyle(Graphite.textMuted)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x7D8597)).accessibilityHidden(true)
        }.frame(minHeight: 40)
    }

    private var fileIcon: Image {
        let ext = file.fileExtension.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        switch ext {
        case "pdf":
            return Image(systemName: "doc.text.fill")
        case "txt", "md":
            return Image(systemName: "doc.plaintext.fill")
        case "zip", "rar":
            return Image(systemName: "doc.zipper.fill")
        case "doc", "docx":
            return Image(systemName: "doc.richtext.fill")
        case "xls", "xlsx":
            return Image(systemName: "tablecells.fill")
        default:
            return Image(systemName: "doc.fill")
        }
    }

    private var fileIconGradient: LinearGradient {
        let ext = file.fileExtension.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        switch ext {
        case "pdf":
            return LinearGradient(
                colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "txt", "md":
            return LinearGradient(
                colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "zip", "rar":
            return LinearGradient(
                colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(
                colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppConstants.presentationLocale
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - File Pager View

/// File preview paging container: swipe left/right between files
struct FilePagerView: View {
    @EnvironmentObject private var authViewModel: AuthenticationViewModel

    private struct Entry: Identifiable {
        let id: UUID
        let detail: MediaDetailView
    }
    private let entries: [Entry]
    @State private var currentIndex: Int

    init(files: [MediaItem], initialFile: MediaItem, sessionID: UUID) {
        self.entries = files.map { Entry(id: $0.id, detail: MediaDetailView(mediaItem: $0, sessionID: sessionID)) }
        if let index = files.firstIndex(where: { $0.id == initialFile.id }) {
            _currentIndex = State(initialValue: index)
        } else {
            _currentIndex = State(initialValue: 0)
        }
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                entry.detail
                    .environmentObject(authViewModel)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

// MARK: - Preview

#Preview {
    FilesView()
        .modelContainer(for: MediaItem.self, inMemory: true)
        .environmentObject(AuthenticationViewModel())
}
