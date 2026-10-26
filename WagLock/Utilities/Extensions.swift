//
//  Extensions.swift
//  WagLock
//
//  Common extensions
//

import Foundation
import SwiftUI
import UIKit

// MARK: - View Extensions

extension View {
    /// Apply a modifier conditionally
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Hide the keyboard
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Add corner radius and shadow
    func cardStyle(cornerRadius: CGFloat = 12, shadowRadius: CGFloat = 5) -> some View {
        self
            .background(Color(.systemBackground))
            .cornerRadius(cornerRadius)
            .shadow(radius: shadowRadius)
    }
}

// MARK: - Date Extensions

extension Date {
    /// Relative time description
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppConstants.presentationLocale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Short date format
    var shortDate: String {
        let formatter = DateFormatter()
        formatter.locale = AppConstants.presentationLocale
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    /// Detailed date and time format
    var detailedDateTime: String {
        let formatter = DateFormatter()
        formatter.locale = AppConstants.presentationLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: self)
    }
}

// MARK: - Int64 Extensions

extension Int64 {
    /// Formatted file size
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

// MARK: - String Extensions

extension String {
    /// File extension
    var fileExtension: String {
        (self as NSString).pathExtension
    }

    /// File name without extension
    var fileNameWithoutExtension: String {
        (self as NSString).deletingPathExtension
    }
}

// MARK: - Color Extensions

extension Color {
    /// Create a color from a hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - UIImage Extensions

extension UIImage {
    /// Resize the image
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Generate a thumbnail
    func thumbnail(maxSize: CGFloat) -> UIImage? {
        let aspectRatio = self.size.width / self.size.height
        var thumbnailSize: CGSize

        if aspectRatio > 1 {
            // Landscape image
            thumbnailSize = CGSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            // Portrait image
            thumbnailSize = CGSize(width: maxSize * aspectRatio, height: maxSize)
        }

        return resized(to: thumbnailSize)
    }

    /// Compress to JPEG data
    func compressedJPEGData(quality: CGFloat = 0.7) -> Data? {
        return self.jpegData(compressionQuality: quality)
    }
}

// MARK: - Data Extensions

extension Data {
    /// Convert to UIImage
    var asUIImage: UIImage? {
        return UIImage(data: self)
    }
}
