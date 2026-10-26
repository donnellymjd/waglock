//
//  AppConstants.swift
//  WagLock
//
//  Global constants
//

import Foundation

/// App-wide constants
nonisolated enum AppConstants {

    // MARK: - App Info

    /// App name
    static let appName = "WagLock"

    /// Presentation language for the English-only beta; never normalize user content.
    static let presentationLocale = Locale(identifier: "en_US")
    static let tagline = "We Always Guard"
    static let developmentNotice = "Early test build. Use sample media only. Portable recovery and security hardening are still in development."

    /// App version (read from Info.plist; follows MARKETING_VERSION so it never goes stale)
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.8"
    }

    /// Build number (follows CURRENT_PROJECT_VERSION)
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "21"
    }

    /// Bundle Identifier
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.d2sci.vaultito.dev"

    /// GitHub repository URL
    static let githubRepositoryURL = "https://github.com/donnellymjd/waglock"
    static let privacyPolicyURL = URL(string: "https://github.com/donnellymjd/waglock/blob/main/PRIVACY_POLICY.md")!
    static let supportURL = URL(string: "https://github.com/donnellymjd/waglock/blob/main/docs/release/support.md")!

    // MARK: - Security

    /// Minimum password length
    static let minPasswordLength = 6

    /// Maximum password length
    static let maxPasswordLength = 128

    /// Password verification delay (brute-force mitigation, seconds)
    static let passwordVerificationDelay: Double = 0.5

    /// PBKDF2 iteration count (key derivation)
    static let pbkdf2Iterations = 100_000

    /// Salt length (bytes)
    static let saltLength = 16

    /// AES-GCM IV length (bytes)
    static let ivLength = 12

    /// AES-GCM tag length (bytes)
    static let tagLength = 16

    // MARK: - Storage

    /// Encrypted file storage directory name
    static let encryptedMediaDirectory = "EncryptedMedia"

    /// Encrypted file extension
    static let encryptedFileExtension = ".encrypted"

    /// Maximum thumbnail size (pixels)
    static let thumbnailMaxSize: CGFloat = 300

    /// Preview decode limit, so high-resolution photos don't strain memory and the main thread while paging
    static let previewImageMaxPixelSize: CGFloat = 3_072

    /// Thumbnail JPEG compression quality (0.0-1.0)
    static let thumbnailCompressionQuality: CGFloat = 0.7

    /// Maximum file size (bytes, 500 MB)
    static let maxFileSize: Int64 = 500 * 1024 * 1024

    // MARK: - UI

    /// Grid column count (default)
    static let defaultGridColumns = 3

    /// Grid column count range
    static let gridColumnsRange = 2...4

    /// Grid spacing
    static let gridSpacing: CGFloat = 8

    /// Animation duration
    static let animationDuration: Double = 0.3

    // MARK: - Media

    /// Supported image formats
    static let supportedImageFormats = ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff"]

    /// Supported video formats
    static let supportedVideoFormats = ["mp4", "mov", "m4v", "avi", "mkv"]

    /// Video thumbnail time offset (seconds)
    static let videoThumbnailTime: Double = 1.0

    // MARK: - Notifications

    /// Media import finished notification
    static let mediaImportedNotification = "MediaImportedNotification"

    /// Media deleted notification
    static let mediaDeletedNotification = "MediaDeletedNotification"

    /// Storage full notification
    static let storageFullNotification = "StorageFullNotification"
}

// MARK: - UserDefaults Keys

extension AppConstants {

    /// UserDefaults keys
    enum UserDefaultsKeys {
        /// Sort order
        static let sortOrder = "sortOrder"

        /// Grid column count
        static let gridColumns = "gridColumns"

        /// First launch
        static let isFirstLaunch = "isFirstLaunch"

        /// Last access time
        static let lastAccessTime = "lastAccessTime"

        /// Disguise (calculator) mode enabled
        static let disguiseModeEnabled = "disguiseModeEnabled"

        /// Disguise (calculator) mode password sequence
        static let disguisePasswordSequence = "disguisePasswordSequence"

        /// Whether unlimited imports were unlocked

        /// Guest mode enabled
        static let guestModeEnabled = "guestModeEnabled"

        /// Auto-lock delay after leaving the app (seconds)
        static let autoLockTimeout = "autoLockTimeout"

        /// App has finished initialization (used to detect uninstall/reinstall)
        static let appInitialized = "appInitialized"
    }
}

// MARK: - Error Messages

extension AppConstants {

    /// Error messages
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
