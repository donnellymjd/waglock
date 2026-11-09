//
//  ColorTheme.swift
//  WagLock
//
//  Created by Claude on 2025/11/15.
//  Color theme system with dark mode support
//

import SwiftUI

/// Graphite tokens (dark only). Names match the handover spec board; the older
/// ColorTheme names below map onto them so every existing screen re-skins at once.
enum Graphite {
    static let base = Color(hex: 0x1A1E29)          // bg/base
    static let scrim = Color(hex: 0x0E1118)         // bg/scrim
    static let media = Color(hex: 0x0A0C11)         // bg/media
    static let bar = Color(hex: 0x242936)           // surface/bar
    static let surface1 = Color(hex: 0x262B38)      // surface/1
    static let input = Color(hex: 0x2C3140)         // surface/input
    static let surface2 = Color(hex: 0x2F3544)      // surface/2
    static let line = Color(hex: 0x3A4152)          // line
    static let textPrimary = Color(hex: 0xF3F5F9)   // text/primary
    static let textSecondary = Color(hex: 0xC1C7D3) // text/secondary
    static let textMuted = Color(hex: 0xA7AEBD)     // text/muted
    static let accentText = Color(hex: 0x8DBEFF)    // accent/text
    static let accentLight = Color(hex: 0xA9CEFF)   // accent/light
    static let accentStrong = Color(hex: 0x4C8DFF)  // accent/strong
    static let onAccent = Color(hex: 0x0A1530)      // on-accent
    static let warn = Color(hex: 0xFFC46B)          // warn
    static let danger = Color(hex: 0xFF9C9C)        // danger
    static let dangerLine = Color(hex: 0xFF8A8A)    // danger/line
    static let accentTint = Color(hex: 0x4C8DFF).opacity(0.14)
    static let warnTint = Color(hex: 0xFFC46B).opacity(0.14)
    static let dangerTint = Color(hex: 0xFF8A8A).opacity(0.12)
    static let accentGradient = LinearGradient(colors: [accentLight, accentStrong],
                                               startPoint: .leading, endPoint: .trailing)
}

/// App color theme
struct ColorTheme {
    static let primaryBackground = Graphite.base
    static let secondaryBackground = Graphite.surface1
    static let tertiaryBackground = Graphite.surface2
    static let groupedBackground = primaryBackground
    static let primaryText = Graphite.textPrimary
    static let secondaryText = Graphite.textMuted
    static let tertiaryText = Graphite.textMuted
    static let placeholderText = Graphite.textMuted
    static let accent = Graphite.accentText
    static let onAccent = Graphite.onAccent
    static let brandBackgroundStart = primaryBackground
    static let brandBackgroundEnd = primaryBackground
    static let destructive = Graphite.danger
    static let success = Color(hex: 0x7FD8A4)
    static let warning = Graphite.warn
    static let border = Graphite.line
    static let separator = Graphite.line
    static let calculatorButtonBackground = secondaryBackground
    static let calculatorOperatorBackground = accent
    static let cardShadow = Color.black.opacity(0.35)
    static let gridItemBackground = Graphite.surface2
    static let encryptionIndicator = Color(hex: 0x7FD8A4).opacity(0.2)
    static let selectedBackground = Graphite.accentTint
    static let hoverBackground = Color.white.opacity(0.08)
    static let disabledBackground = Graphite.surface2
    static let disabledText = Graphite.textMuted
}

// MARK: - Color Extension

extension Color {
    /// sRGB color from 0xRRGGBB.
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: 1)
    }

    /// Returns a different color for light and dark mode
    init(light: Color, dark: Color) {
        self.init(
            UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(dark)
                default:
                    return UIColor(light)
                }
            })
    }

}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // Background Colors
            VStack(alignment: .leading, spacing: 10) {
                Text("Background Colors")
                    .font(.headline)

                HStack(spacing: 15) {
                    ColorPreviewBox(color: ColorTheme.primaryBackground, title: "Primary")
                    ColorPreviewBox(color: ColorTheme.secondaryBackground, title: "Secondary")
                    ColorPreviewBox(color: ColorTheme.tertiaryBackground, title: "Tertiary")
                }
            }

            // Text Colors
            VStack(alignment: .leading, spacing: 10) {
                Text("Text Colors")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Primary Text").foregroundStyle(ColorTheme.primaryText)
                    Text("Secondary Text").foregroundStyle(ColorTheme.secondaryText)
                    Text("Tertiary Text").foregroundStyle(ColorTheme.tertiaryText)
                    Text("Placeholder Text").foregroundStyle(ColorTheme.placeholderText)
                }
                .padding()
                .background(ColorTheme.secondaryBackground)
                .cornerRadius(10)
            }

            // Accent Colors
            VStack(alignment: .leading, spacing: 10) {
                Text("Accent Colors")
                    .font(.headline)

                HStack(spacing: 15) {
                    ColorPreviewBox(color: ColorTheme.accent, title: "Accent")
                    ColorPreviewBox(color: ColorTheme.destructive, title: "Destructive")
                    ColorPreviewBox(color: ColorTheme.success, title: "Success")
                    ColorPreviewBox(color: ColorTheme.warning, title: "Warning")
                }
            }
        }
        .padding()
    }
    .background(ColorTheme.primaryBackground)
}

struct ColorPreviewBox: View {
    let color: Color
    let title: String

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 80, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ColorTheme.border, lineWidth: 1)
                )

            Text(title)
                .font(.caption)
                .foregroundStyle(ColorTheme.secondaryText)
        }
    }
}
