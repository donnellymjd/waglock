/*@ai:risk=3|deps=ExportService,MediaItem|lines=400*/
//
//  BatchExportView.swift
//  WagLock
//
//  批量导出视图
//  选择文件并导出到系统分享界面
//

import SwiftData
import SwiftUI

struct BatchExportView: View {
    @EnvironmentObject private var vaultServices: VaultSessionContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    @Query private var allItems: [MediaItem]

    @State private var selectedItems: Set<UUID> = []
    @State private var isExporting: Bool = false
    @State private var showShareSheet: Bool = false
    @Environment(\.scenePhase) private var exportScenePhase
    @State private var exportJobID: UUID?
    @State private var exportedURLs: [URL] = []
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var exportTotalCount: Int = 0
    @State private var exportedCount: Int = 0
    @State private var exportStatusText: String = ""
    @State private var exportErrorWasCancellation: Bool = false

    init(initialSelection: Set<UUID> = []) {
        _selectedItems = State(initialValue: initialSelection)
    }

    private var exportService: ExportService { vaultServices.exports }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isExporting {
                    exportingView
                } else {
                    selectionView
                }
            }
            .background(ColorTheme.primaryBackground)
            .navigationTitle(String(localized: "export.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        if isExporting {
                            cancelExportOperation()
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.export")) {
                        startExport()
                    }
                    .disabled(selectedItems.isEmpty || isExporting)
                }
            }
            .onChange(of: exportScenePhase) { _, phase in
                if phase == .background { isExporting = false; showShareSheet = false }
            }
            .onDisappear {
                if !showShareSheet, let exportJobID { exportService.cancelExport(exportJobID) }
            }
            .sheet(isPresented: $showShareSheet, onDismiss: {
                exportService.cleanupAfterSharing(exportedURLs)
                exportedURLs = []
                exportJobID = nil
            }) {
                ShareSheet(items: exportedURLs)
            }
            .alert(String(localized: "export.failed"), isPresented: $showError) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                if let error = errorMessage, !exportErrorWasCancellation {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Selection View

    private var selectionView: some View {
        VStack(spacing: 12) {
            WagLockInfoCard(title: "Export creates unencrypted copies", detail: "Recipients and destination apps can keep the files you share. Your vault originals stay in WagLock.")
                .padding(.horizontal, 24).padding(.top, 16)
            // 选择统计
            HStack {
                Text(String(format: String(localized: "export.selectedCount"), selectedItems.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if !selectedItems.isEmpty {
                    Button {
                        selectedItems.removeAll()
                    } label: {
                        Text(String(localized: "export.clear"))
                            .font(.subheadline)
                    }
                }

                Button {
                    selectAll()
                } label: {
                    Text(
                        selectedItems.count == allItems.count
                            ? String(localized: "export.deselectAll")
                            : String(localized: "common.selectAll")
                    )
                    .font(.subheadline)
                }
            }
            .padding()
            .background(ColorTheme.primaryBackground)

            Divider()

            // 文件列表
            if allItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(allItems) { item in
                            ExportItemRow(
                                item: item,
                                isSelected: selectedItems.contains(item.id)
                            ) {
                                toggleSelection(item)
                            }

                            Divider()
                        }
                    }
                }
            }
            Button("Prepare \(selectedItems.count) files") { startExport() }
                .buttonStyle(WagLockPrimaryButtonStyle()).disabled(selectedItems.isEmpty || isExporting)
                .padding(24).accessibilityIdentifier("export.prepare")
        }
    }

    // MARK: - Exporting View

    private var exportingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(exportTotalCount) selected items").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                WagLockProgressCard(title: "Preparing copies for sharing", detail: exportStatusText, progress: exportProgressValue)
                WagLockInfoCard(title: "Copies will leave the vault", detail: "Prepared exports are unencrypted. Choose your destination carefully in the iOS share sheet.")
            }.padding(24)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text(String(localized: "export.empty.title"))
                .font(.title3)
                .fontWeight(.medium)

            Text(String(localized: "export.empty.subtitle"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func toggleSelection(_ item: MediaItem) {
        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }
    }

    private func selectAll() {
        if selectedItems.count == allItems.count {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(allItems.map { $0.id })
        }
    }

    private func startExport() {
        guard !selectedItems.isEmpty else { return }

        // 获取选中的媒体项
        let itemsToExport = allItems.filter { selectedItems.contains($0.id) }

        // 开始导出
        isExporting = true
        exportTotalCount = itemsToExport.count
        exportedCount = 0
        exportStatusText =
            exportTotalCount > 0
            ? String(
                format: String(localized: "export.decryptingProgress"),
                1,
                exportTotalCount)
            : ""

        // 获取当前密码
        guard let password = authViewModel.sessionPassword else {
            errorMessage = String(localized: "export.error.noPassword")
            showError = true
            isExporting = false
            return
        }

        // 执行导出
        exportErrorWasCancellation = false

        let exportSessionID = authViewModel.librarySessionID
        exportJobID = exportService.exportItems(
            itemsToExport,
            password: password,
            sessionID: exportSessionID,
            progressHandler: { processed, total in
                guard authViewModel.isAuthenticated, authViewModel.librarySessionID == exportSessionID else { return }
                exportedCount = processed
                if processed < total {
                    exportStatusText = String(format: String(localized: "export.decryptingProgress"), processed + 1, total)
                } else { exportStatusText = String(localized: "export.preparingShare") }
            }
        ) { result in
            guard authViewModel.isAuthenticated, authViewModel.librarySessionID == exportSessionID else { return }
            switch result {
            case .success(let urls):
                exportedURLs = urls
                exportedCount = exportTotalCount

                // 延迟显示分享界面
                let readyJob = exportService.jobID(for: urls)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let readyJob, exportService.isReady(readyJob), authViewModel.isAuthenticated,
                          authViewModel.librarySessionID == exportSessionID else { return }
                    isExporting = false
                    showShareSheet = true
                }

            case .failure(let error):
                isExporting = false
                exportedCount = 0
                exportTotalCount = 0
                exportStatusText = ""
                if case .cancelled = error {
                    exportErrorWasCancellation = true
                } else {
                    exportErrorWasCancellation = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private var exportProgressValue: Double {
        guard exportTotalCount > 0 else { return 0 }
        return Double(exportedCount) / Double(exportTotalCount)
    }
}

extension BatchExportView {
    private func cancelExportOperation() {
        if let exportJobID { exportService.cancelExport(exportJobID) }
        exportJobID = nil
        exportErrorWasCancellation = true
        exportStatusText = ""
        exportedCount = 0
        exportTotalCount = 0
        isExporting = false
    }
}

// MARK: - Export Item Row

struct ExportItemRow: View {
    let item: MediaItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 选择标记
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)

                // 文件图标
                Image(systemName: item.type.iconName)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 40)

                // 文件信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fileName)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack {
                        Text(item.type.rawValue.capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text(item.formattedFileSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Share Sheet

struct ShareSheet: View {
    let items: [Any]
    @EnvironmentObject private var exports: ExportService
    @Environment(\.dismiss) private var dismiss
    private var urls: [URL] { items.compactMap { $0 as? URL } }

    var body: some View {
        ActivitySheet(items: urls)
            .onAppear { dismissIfRevoked() }
            .onChange(of: exports.revision) { _, _ in dismissIfRevoked() }
            .onDisappear { exports.cleanupAfterSharing(urls) }
    }
    private func dismissIfRevoked() {
        if exports.containsManagedURL(urls), exports.jobID(for: urls) == nil { dismiss() }
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    @EnvironmentObject private var exports: ExportService
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = exports.createShareController(for: items)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

#Preview {
    BatchExportView()
        .modelContainer(for: MediaItem.self, inMemory: true)
        .environmentObject(AuthenticationViewModel())
}
