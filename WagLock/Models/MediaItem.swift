//
//  MediaItem.swift
//  WagLock
//
//  Media item data model (SwiftData)
//  Stores metadata for media files
//

import Foundation
import SwiftData

/// Media item model
@Model
@MainActor
final class MediaItem {

    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// Original file name (e.g. "IMG_1234.jpg")
    var fileName: String

    /// File extension (e.g. ".jpg")
    var fileExtension: String

    /// File size (bytes)
    var fileSize: Int64

    /// Media type (photo/video/document)
    var typeRawValue: String

    /// Full path of the encrypted file
    var encryptedPath: String

    /// Raw thumbnail bytes in the legacy database; not vault-encrypted (audit A01).
    var thumbnailData: Data?

    /// Import time
    var createdAt: Date

    /// Last modified time
    var modifiedAt: Date

    /// Image/video width (pixels)
    var width: Int?

    /// Image/video height (pixels)
    var height: Int?

    /// Video duration (seconds)
    var duration: Double?

    // MARK: - Computed Properties

    /// Media type (computed property)
    @Transient
    var type: MediaType {
        get {
            let storedType = MediaType(rawValue: typeRawValue) ?? .document
            if storedType == .document && MediaType.from(fileExtension: fileExtension) == .audio {
                return .audio
            }
            return storedType
        }
        set {
            typeRawValue = newValue.rawValue
        }
    }

    /// Full file name (with extension)
    @Transient
    var fullFileName: String {
        fileName + fileExtension
    }

    /// Formatted file size
    @Transient
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Formatted creation date
    @Transient
    var formattedCreatedDate: String {
        let formatter = DateFormatter()
        formatter.locale = AppConstants.presentationLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Whether dimensions are available
    @Transient
    var hasDimensions: Bool {
        width != nil && height != nil
    }

    /// Formatted dimensions
    @Transient
    var formattedDimensions: String? {
        guard let width = width, let height = height else {
            return nil
        }
        return "\(width) × \(height)"
    }

    /// Formatted video duration
    @Transient
    var formattedDuration: String? {
        guard let duration = duration else {
            return nil
        }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60

        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        fileName: String,
        fileExtension: String,
        fileSize: Int64,
        type: MediaType,
        encryptedPath: String,
        thumbnailData: Data? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        width: Int? = nil,
        height: Int? = nil,
        duration: Double? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.typeRawValue = type.rawValue
        self.encryptedPath = encryptedPath
        self.thumbnailData = thumbnailData
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.width = width
        self.height = height
        self.duration = duration
    }

    // MARK: - Methods

    /// Update the last modified time
    func touch() {
        modifiedAt = Date()
    }

    /// Set dimensions
    func setDimensions(width: Int, height: Int) {
        self.width = width
        self.height = height
        touch()
    }

    /// Set video duration
    func setDuration(_ duration: Double) {
        self.duration = duration
        touch()
    }

    /// Update thumbnail
    func updateThumbnail(_ data: Data?) {
        self.thumbnailData = data
        touch()
    }
}

// MARK: - Comparable

extension MediaItem: Comparable {
    static func < (lhs: MediaItem, rhs: MediaItem) -> Bool {
        // Default: creation date descending (newest first)
        lhs.createdAt > rhs.createdAt
    }
}

// MARK: - Sorting Options

extension MediaItem {

    /// Sort order options
    enum SortOrder: String, CaseIterable, Identifiable {
        case dateNewest
        case dateOldest
        case nameAZ
        case nameZA
        case sizeSmallest
        case sizeLargest
        case typeGrouped

        var id: String { rawValue }

        /// Localized display name
        var displayName: String {
            switch self {
            case .dateNewest:
                return String(localized: "sort.dateNewest")
            case .dateOldest:
                return String(localized: "sort.dateOldest")
            case .nameAZ:
                return String(localized: "sort.nameAZ")
            case .nameZA:
                return String(localized: "sort.nameZA")
            case .sizeSmallest:
                return String(localized: "sort.sizeSmallest")
            case .sizeLargest:
                return String(localized: "sort.sizeLargest")
            case .typeGrouped:
                return String(localized: "sort.typeGrouped")
            }
        }

        /// Sort descriptors
        var sortDescriptor: [SortDescriptor<MediaItem>] {
            switch self {
            case .dateNewest:
                return [SortDescriptor(\MediaItem.createdAt, order: .reverse)]
            case .dateOldest:
                return [SortDescriptor(\MediaItem.createdAt, order: .forward)]
            case .nameAZ:
                return [SortDescriptor(\MediaItem.fileName, order: .forward)]
            case .nameZA:
                return [SortDescriptor(\MediaItem.fileName, order: .reverse)]
            case .sizeSmallest:
                return [SortDescriptor(\MediaItem.fileSize, order: .forward)]
            case .sizeLargest:
                return [SortDescriptor(\MediaItem.fileSize, order: .reverse)]
            case .typeGrouped:
                return [
                    SortDescriptor(\MediaItem.typeRawValue, order: .forward),
                    SortDescriptor(\MediaItem.createdAt, order: .reverse),
                ]
            }
        }

        /// SF Symbol icon
        var icon: String {
            switch self {
            case .dateNewest:
                return "calendar.badge.clock"
            case .dateOldest:
                return "calendar"
            case .nameAZ:
                return "textformat.abc"
            case .nameZA:
                return "textformat.abc"
            case .sizeSmallest:
                return "arrow.up.circle"
            case .sizeLargest:
                return "arrow.down.circle"
            case .typeGrouped:
                return "square.grid.2x2"
            }
        }
    }
}
