//
//  AppConstants.swift
//  WagLock
//
//  全局常量配置
//

import Foundation

/// 应用全局常量
nonisolated enum AppConstants {

    // MARK: - App Info

    /// 应用名称
    static let appName = "WagLock"

    /// Presentation language for the English-only beta; never normalize user content.
    static let presentationLocale = Locale(identifier: "en_US")
    static let tagline = "We Always Guard"
    static let developmentNotice = "Early test build. Use sample media only. Portable recovery and security hardening are still in development."

    /// 应用版本（从 Info.plist 读取，跟随 MARKETING_VERSION，避免手写过期）
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.8"
    }

    /// 构建号（跟随 CURRENT_PROJECT_VERSION）
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "21"
    }

    /// Bundle Identifier
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.d2sci.vaultito.dev"

    /// GitHub仓库地址
    static let githubRepositoryURL = "https://github.com/donnellymjd/zeroNet_Space"

    // MARK: - Security

    /// 最小密码长度
    static let minPasswordLength = 6

    /// 最大密码长度
    static let maxPasswordLength = 128

    /// 密码验证延迟（防暴力破解，秒）
    static let passwordVerificationDelay: Double = 0.5

    /// PBKDF2迭代次数（密钥派生）
    static let pbkdf2Iterations = 100_000

    /// 盐值长度（字节）
    static let saltLength = 16

    /// AES-GCM IV长度（字节）
    static let ivLength = 12

    /// AES-GCM 标签长度（字节）
    static let tagLength = 16

    // MARK: - Storage

    /// 加密文件存储目录名
    static let encryptedMediaDirectory = "EncryptedMedia"

    /// 加密文件扩展名
    static let encryptedFileExtension = ".encrypted"

    /// 缩略图最大尺寸（像素）
    static let thumbnailMaxSize: CGFloat = 300

    /// 预览图片解码上限，避免高像素照片在翻页时造成内存和主线程压力
    static let previewImageMaxPixelSize: CGFloat = 3_072

    /// 缩略图JPEG压缩质量（0.0-1.0）
    static let thumbnailCompressionQuality: CGFloat = 0.7

    /// 最大文件大小（字节，500MB）
    static let maxFileSize: Int64 = 500 * 1024 * 1024

    // MARK: - UI

    /// 网格列数（默认）
    static let defaultGridColumns = 3

    /// 网格列数范围
    static let gridColumnsRange = 2...4

    /// 网格间距
    static let gridSpacing: CGFloat = 8

    /// 动画时长
    static let animationDuration: Double = 0.3

    // MARK: - Media

    /// 支持的图片格式
    static let supportedImageFormats = ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff"]

    /// 支持的视频格式
    static let supportedVideoFormats = ["mp4", "mov", "m4v", "avi", "mkv"]

    /// 视频缩略图时间点（秒）
    static let videoThumbnailTime: Double = 1.0

    // MARK: - Notifications

    /// 媒体导入完成通知
    static let mediaImportedNotification = "MediaImportedNotification"

    /// 媒体删除通知
    static let mediaDeletedNotification = "MediaDeletedNotification"

    /// 存储空间不足通知
    static let storageFullNotification = "StorageFullNotification"
}

// MARK: - UserDefaults Keys

extension AppConstants {

    /// UserDefaults键
    enum UserDefaultsKeys {
        /// 排序方式
        static let sortOrder = "sortOrder"

        /// 网格列数
        static let gridColumns = "gridColumns"

        /// 首次启动
        static let isFirstLaunch = "isFirstLaunch"

        /// 最后访问时间
        static let lastAccessTime = "lastAccessTime"

        /// 伪装模式启用状态
        static let disguiseModeEnabled = "disguiseModeEnabled"

        /// 伪装模式密码序列
        static let disguisePasswordSequence = "disguisePasswordSequence"

        /// 是否已解锁无限导入

        /// 访客模式启用状态
        static let guestModeEnabled = "guestModeEnabled"

        /// 离开后自动锁定时长（秒）
        static let autoLockTimeout = "autoLockTimeout"

        /// 应用已完成初始化（用于检测卸载重装）
        static let appInitialized = "appInitialized"
    }
}

// MARK: - Error Messages

extension AppConstants {

    /// 错误消息
    enum ErrorMessages {
        static var passwordTooShort: String {
            String(
                format: String(localized: "error.passwordTooShort"),
                AppConstants.minPasswordLength)
        }

        static var passwordTooLong: String {
            String(
                format: String(localized: "error.passwordTooLong"),
                AppConstants.maxPasswordLength)
        }

        static let passwordMismatch = String(localized: "error.passwordMismatch")
        static let passwordIncorrect = String(localized: "error.passwordIncorrect")
        static let passwordEmpty = String(localized: "error.passwordEmpty")

        static let encryptionFailed = String(localized: "error.encryptionFailed")
        static let decryptionFailed = String(localized: "error.decryptionFailed")
        static let fileNotFound = String(localized: "error.fileNotFound")
        static var fileTooLarge: String {
            String(
                format: String(localized: "error.fileTooLarge"),
                AppConstants.maxFileSize / (1024 * 1024))
        }
        static let storageInsufficient = String(localized: "error.storageInsufficient")

        static let importFailed = String(localized: "error.importFailed")
        static let deleteFailed = String(localized: "error.deleteFailed")
        static let saveFailed = String(localized: "error.saveFailed")

        static let permissionDenied = String(localized: "error.permissionDenied")
        static let photoLibraryAccessDenied = String(
            localized: "error.photoLibraryAccessDenied")
    }
}
