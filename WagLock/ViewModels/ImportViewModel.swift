//
//  ImportViewModel.swift
//  WagLock
//
//  导入视图模型
//  管理媒体导入流程
//

internal import Combine
import Foundation
import PhotosUI
import SwiftData
import SwiftUI

/// 导入视图模型
@MainActor
class ImportViewModel: ObservableObject {
    // MARK: - Published Properties

    /// 是否正在导入
    @Published var isImporting: Bool = false

    /// 导入进度
    @Published var importProgress: ImportProgress?

    /// 错误消息
    @Published var errorMessage: String?

    /// 是否显示照片选择器
    @Published var showPhotoPicker: Bool = false

    /// 是否显示文件选择器
    @Published var showFilePicker: Bool = false

    /// 是否显示音频选择器
    @Published var showAudioPicker: Bool = false

    /// 导入成功的数量
    @Published var importedCount: Int = 0

    /// 是否显示加密文件密码输入对话框
    @Published var showEncryptedPasswordInput: Bool = false

    /// 当前待处理的加密文件信息
    @Published var pendingEncryptedFile: (fileName: String, url: URL)?

    // MARK: - Services

    private let importService: MediaImportService

    // MARK: - Properties

    var modelContext: ModelContext?
    var onImportComplete: (([MediaItem]) -> Void)?

    /// 认证视图模型（用于获取会话密码）
    var authViewModel: AuthenticationViewModel?

    private var currentImportTask: Task<Void, Never>?
    private var importGeneration = UUID()
    private let storage: FileStorageService
    private let saveContext: @MainActor (ModelContext) throws -> Void

    init(storage: FileStorageService = .shared,
         saveContext: @escaping @MainActor (ModelContext) throws -> Void = { try LibraryWriteCoordinator.save($0) }) {
        self.storage = storage
        importService = MediaImportService(storage: storage)
        self.saveContext = saveContext
    }

    // MARK: - Public Methods

    /// 从照片库导入
    func importFromPhotoLibrary(results: [PHPickerResult]) {
        guard !isImporting else { return }
        guard !results.isEmpty else { return }

        errorMessage = nil
        isImporting = true
        importedCount = 0

        startImportTask { password, progress in
            try await self.importService.importMedia(from: results, password: password, progress: progress)
        }
    }

    /// 从文件导入
    func importFromFiles(urls: [URL]) {
        guard !isImporting else { return }
        guard !urls.isEmpty else { return }

        // 检测是否有加密文件
        let encryptedFiles = urls.filter { $0.pathExtension.lowercased() == "encrypted" }

        if !encryptedFiles.isEmpty {
            guard !LibraryStoragePolicy.encryptedMetadata else {
                errorMessage = "Native encrypted-file import is unavailable in this release. Recover originals with the documented recovery tools, then import them through Photos or Files. Your source files are unchanged."
                return
            }
            // 如果有加密文件，优先处理第一个加密文件
            let firstEncryptedFile = encryptedFiles[0]
            pendingEncryptedFile = (
                fileName: firstEncryptedFile.lastPathComponent,
                url: firstEncryptedFile
            )
            isImporting = true
            showEncryptedPasswordInput = true

            // 如果有多个文件，暂时只处理加密文件
            // TODO: 可以支持批量处理混合文件类型
            return
        }

        // 正常导入非加密文件
        errorMessage = nil
        isImporting = true
        importedCount = 0

        startImportTask { password, progress in
            try await self.importService.importFiles(from: urls, password: password, progress: progress)
        }
    }

    /// 显示照片选择器
    func selectPhotos() {
        showPhotoPicker = true
    }

    /// 显示文件选择器
    func selectFiles() {
        showFilePicker = true
    }

    /// 显示音频选择器
    func selectAudio() {
        showAudioPicker = true
    }

    /// 取消导入
    func cancelImport() {
        importGeneration = UUID()
        currentImportTask?.cancel()
        currentImportTask = nil
        isImporting = false
        importProgress = nil
        errorMessage = nil
        importedCount = 0
        pendingEncryptedFile = nil
        showEncryptedPasswordInput = false
    }

    // MARK: - Private Methods

    private func startImportTask(
        encryptedInput: Bool = false,
        operation: @escaping (_ password: String, _ progress: @escaping (ImportProgress) -> Void) async throws -> [MediaItem]
    ) {
        currentImportTask?.cancel()
        importGeneration = UUID()
        let token = importGeneration
        let report: (ImportProgress) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, self.importGeneration == token, self.isImporting,
                      self.authViewModel?.isAuthenticated == true,
                      GuestModeManager.shared.isOwnerMode else { return }
                self.importProgress = progress
            }
        }
        currentImportTask = Task { [weak self] in
            guard let self else { return }
            await self.performImport(operation: { password in
                try await operation(password, report)
            }, generation: token, encryptedInput: encryptedInput)
        }
    }

    /// One commit boundary for Photos, Files and re-encrypted imports. Operations
    /// return newly created files; no success callback occurs before database save.
    func performImport(
        operation: @escaping (_ password: String) async throws -> [MediaItem],
        generation: UUID? = nil,
        encryptedInput: Bool = false
    ) async {
        let token = generation ?? importGeneration
        let context = modelContext
        var createdPaths: [String] = []
        var committed = false
        defer {
            if !committed, let context { removeUncommittedFiles(createdPaths, context: context) }
            if token == importGeneration {
                currentImportTask = nil
                isImporting = false
                importProgress = nil
                if encryptedInput { showEncryptedPasswordInput = false }
            }
        }
        do {
            try Task.checkCancellation()
            guard token == importGeneration else { throw CancellationError() }
            errorMessage = nil
            importedCount = 0
            guard let context else { throw ImportError.saveFailed }
            guard let auth = authViewModel, auth.isAuthenticated,
                  GuestModeManager.shared.isOwnerMode,
                  let session = auth.sessionPasswordData, let password = session.string else {
                throw ImportError.permissionDenied
            }
            isImporting = true
            let items = try await operation(password)
            createdPaths = items.map(\.encryptedPath)
            try Task.checkCancellation()
            guard token == importGeneration, auth.isAuthenticated,
                  auth.sessionPasswordData === session, GuestModeManager.shared.isOwnerMode else {
                throw CancellationError()
            }
            for item in items { context.insert(item) }
            do { try saveContext(context) }
            catch { context.rollback(); throw error }
            committed = true
            importedCount = items.count
            isImporting = false
            importProgress = nil
            onImportComplete?(items)
        } catch is CancellationError {
            if token == importGeneration { errorMessage = nil }
        } catch {
            if token == importGeneration {
                if encryptedInput, error is EncryptionError {
                    errorMessage = String(localized: "import.encryptedFile.wrongPassword")
                } else {
                    errorMessage = String(format: String(localized: "import.error.failedWithReason"),
                                          error.localizedDescription)
                }
            }
        }
    }

    private func removeUncommittedFiles(_ paths: [String], context: ModelContext) {
        guard LibraryWriteCoordinator.mayDiscardUncommittedResources(in: context) else { return }
        // A fresh context sees committed state, not this import's rolled-back inserts.
        // Preserve files on an uncertain save outcome or failed verification query.
        let committedContext = ModelContext(context.container)
        for path in Set(paths) {
            let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.encryptedPath == path })
            guard let count = try? committedContext.fetchCount(descriptor), count == 0 else { continue }
            try? storage.deleteFile(path: path)
        }
    }

}

// MARK: - Import Progress Extension

extension ImportViewModel {
    /// 格式化的进度文本
    var progressText: String {
        guard let progress = importProgress else {
            return isImporting ? String(localized: "import.status.preparing") : ""
        }
        return String(
            format: String(localized: "import.status.progress"),
            progress.current,
            progress.total,
            progress.currentFileName)
    }

    /// 进度百分比
    var progressPercentage: Double {
        importProgress?.percentage ?? 0
    }
}

// MARK: - Encrypted File Password Handling

extension ImportViewModel {
    /// 处理加密文件密码输入确认
    func handleEncryptedFilePassword(_ password: String) {
        guard let pendingFile = pendingEncryptedFile else { return }

        // 清空待处理文件
        pendingEncryptedFile = nil

        // 使用输入的密码重新导入文件
        importEncryptedFileWithPassword(url: pendingFile.url, originalPassword: password)
    }

    /// 取消加密文件密码输入
    func cancelEncryptedFilePasswordInput() {
        cancelImport()
        errorMessage = String(localized: "import.encryptedFile.cancelled")
    }

    /// Security-scoped access spans the actual async read, with the same commit
    /// and cancellation rules as every other main-library import.
    private func importEncryptedFileWithPassword(url: URL, originalPassword: String) {
        isImporting = true
        errorMessage = nil
        importedCount = 0
        startImportTask(encryptedInput: true) { password, _ in
            guard url.startAccessingSecurityScopedResource() else { throw ImportError.permissionDenied }
            defer { url.stopAccessingSecurityScopedResource() }
            return try await self.importService.importEncryptedFileWithReencryption(
                url: url, originalPassword: originalPassword, newPassword: password)
        }
    }
}
