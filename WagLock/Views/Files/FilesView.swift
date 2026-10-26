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
    @State private var fileToDelete: MediaItem?
    @State private var deleteErrorMessage: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(guestModeManager.isGuestMode ? 0 : files.count) files · On this device")
                        .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    WagLockSearchField(title: "Search files", text: $searchText)
                }.padding(.horizontal, 24).padding(.bottom, 12)
                ZStack {
                // Always show the empty state in guest mode
                if guestModeManager.isGuestMode || files.isEmpty {
                    emptyStateView
                } else {
                    fileListView
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(ColorTheme.primaryBackground)
            .navigationTitle(String(localized: "files.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Hide the import button in guest mode
                    if guestModeManager.isOwnerMode {
                        Button {
                            showImportView = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                        }
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
            Section("RECENTLY ADDED") {
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
            }
            Section {
                WagLockInfoCard(title: "Your files, kept close", detail: "Open documents here. Choose Export when you want a copy outside WagLock.")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }
        .wagLockList()
    }

    // MARK: - Computed Properties

    private var filteredFiles: [MediaItem] {
        if searchText.isEmpty {
            return files
        }
        return files.filter { file in
            file.fileName.localizedCaseInsensitiveContains(searchText)
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
        HStack(spacing: 12) {
            fileIcon.font(.system(size: 22)).foregroundStyle(ColorTheme.accent).frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.fullFileName).font(.body.weight(.semibold)).foregroundStyle(ColorTheme.primaryText).lineLimit(2)
                Text("\(file.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()) · \(file.formattedFileSize)")
                    .font(.footnote).foregroundStyle(ColorTheme.secondaryText)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(ColorTheme.secondaryText).accessibilityHidden(true)
        }.frame(minHeight: 38)
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
