/*@ai:risk=2|deps=SwiftData|lines=80*/
//
//  SecretNote.swift
//  WagLock
//
//  Secret space note data model
//  Private notes with Markdown support
//

import Foundation
import SwiftData

@Model
final class SecretNote {

    // MARK: - Properties

    /// Note unique identifier
    var id: UUID

    /// Note title
    var title: String

    /// Note content (Markdown)
    var content: String

    /// Creation time
    var createdAt: Date

    /// Last modified time
    var modifiedAt: Date

    /// Whether the note is a favorite
    var isFavorite: Bool

    /// Tags (optional, for categorization)
    var tags: [String]

    // MARK: - Initialization

    init(
        title: String = String(localized: "secretNote.defaultTitle"),
        content: String = "",
        isFavorite: Bool = false,
        tags: [String] = []
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isFavorite = isFavorite
        self.tags = tags
    }

    // MARK: - Computed Properties

    /// Formatted creation date
    var formattedCreatedDate: String {
        let formatter = DateFormatter()
        formatter.locale = AppConstants.presentationLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Formatted modification date
    var formattedModifiedDate: String {
        let formatter = DateFormatter()
        formatter.locale = AppConstants.presentationLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedAt)
    }

    /// Note preview (first 100 characters)
    var preview: String {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanContent.isEmpty {
            return String(localized: "secretNote.empty")
        }
        return String(cleanContent.prefix(100))
    }

    /// Word count
    var wordCount: Int {
        return content.count
    }
}
