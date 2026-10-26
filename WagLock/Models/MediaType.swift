//
//  MediaType.swift
//  WagLock
//
//  Media type enum
//  Defines the supported media types: photo, video, document
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Media type
enum MediaType: String, Codable, CaseIterable {
    case photo  // Photo (jpg, png, heic, etc.)
    case video  // Video (mp4, mov, etc.)
    case audio
    case document  // Document (pdf, doc, txt, etc.)

    // MARK: - Display Properties

    /// Display name for the type
    var displayName: String {
        switch self {
        case .photo:
            return String(localized: "mediaType.photo")
        case .video:
            return String(localized: "mediaType.video")
        case .audio:
            return String(localized: "tab.audio")
        case .document:
            return String(localized: "mediaType.document")
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .photo:
            return "photo.fill"
        case .video:
            return "video.fill"
        case .audio:
            return "waveform"
        case .document:
            return "doc.fill"
        }
    }

    /// Icon color
    var iconColor: Color {
        switch self {
        case .photo:
            return .blue
        case .video:
            return .purple
        case .audio:
            return .red
        case .document:
            return .orange
        }
    }

    static let supportedAudioFormats: Set<String> = [
        "m4a", "mp3", "wav", "aiff", "aif", "aac", "caf", "flac", "mp4a"
    ]

    // MARK: - File Extension Detection

    /// Infer the media type from a file extension
    /// - Parameter fileExtension: File extension (e.g. "jpg", "mp4")
    /// - Returns: The media type, or document if it can't be identified
    static func from(fileExtension: String) -> MediaType {
        let ext = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // Image formats
        if AppConstants.supportedImageFormats.contains(ext) {
            return .photo
        }

        // Video formats
        if AppConstants.supportedVideoFormats.contains(ext) {
            return .video
        }

        if supportedAudioFormats.contains(ext) { return .audio }

        // Other documents
        return .document
    }

    /// Infer the media type from a UTType
    /// - Parameter utType: UTType
    /// - Returns: The media type
    static func from(utType: UTType) -> MediaType {
        if utType.conforms(to: .image) {
            return .photo
        } else if utType.conforms(to: .movie) || utType.conforms(to: .video) {
            return .video
        } else if utType.conforms(to: .audio) {
            return .audio
        } else {
            return .document
        }
    }

    /// Infer the media type from a MIME type
    /// - Parameter mimeType: MIME type (e.g. "image/jpeg")
    /// - Returns: The media type
    static func from(mimeType: String) -> MediaType {
        if mimeType.hasPrefix("image/") {
            return .photo
        } else if mimeType.hasPrefix("video/") {
            return .video
        } else if mimeType.hasPrefix("audio/") {
            return .audio
        } else {
            return .document
        }
    }

    // MARK: - File Validation

    /// Check whether a file matches this media type
    /// - Parameter fileExtension: File extension
    /// - Returns: Whether it matches
    func matches(fileExtension: String) -> Bool {
        let ext = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        switch self {
        case .photo:
            return AppConstants.supportedImageFormats.contains(ext)
        case .video:
            return AppConstants.supportedVideoFormats.contains(ext)
        case .audio:
            return Self.supportedAudioFormats.contains(ext)
        case .document:
            return !Self.supportedAudioFormats.contains(ext)
                && !AppConstants.supportedImageFormats.contains(ext)
                && !AppConstants.supportedVideoFormats.contains(ext)
        }
    }

    // MARK: - Quick Look Support

    /// Whether Quick Look preview is supported
    var supportsQuickLook: Bool {
        // All types support Quick Look
        return true
    }

    /// Whether decryption is required before preview
    var requiresDecryptionForPreview: Bool {
        // All types require decryption
        return true
    }
}

// MARK: - Identifiable

extension MediaType: Identifiable {
    var id: String { rawValue }
}

// MARK: - Sorting Helper

extension MediaType: Comparable {
    static func < (lhs: MediaType, rhs: MediaType) -> Bool {
        // Sort order: photo < video < document
        let order: [MediaType] = [.photo, .video, .audio, .document]
        guard let lhsIndex = order.firstIndex(of: lhs),
            let rhsIndex = order.firstIndex(of: rhs)
        else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}
