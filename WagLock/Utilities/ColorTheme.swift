//
//  ColorTheme.swift
//  WagLock
//
//  Created by Claude on 2025/11/15.
//  深色模式颜色主题系统
//

import SwiftUI

/// 应用颜色主题
struct ColorTheme {

    // Shared Figma tokens. Native SF Pro, SF Symbols and system presentations are retained.
    static let primaryBackground = Color("WagLockBackground")
    static let secondaryBackground = Color("WagLockSurface")
    static let tertiaryBackground = Color("WagLockSoft")
    static let groupedBackground = primaryBackground
    static let primaryText = Color("WagLockInk")
    static let secondaryText = Color("WagLockSecondary")
    static let tertiaryText = secondaryText.opacity(0.8)
    static let placeholderText = secondaryText
    static let accent = Color("AccentColor")
    static let onAccent = Color("WagLockOnAccent")
    static let brandBackgroundStart = primaryBackground
    static let brandBackgroundEnd = primaryBackground

    /// 危险操作色
    static let destructive = Color.red

    /// 成功色
    static let success = Color.green

    /// 警告色
    static let warning = Color.orange

    // MARK: - Border & Separator

    /// 边框色
    static let border = Color("WagLockBorder")

    /// 分隔线色
    static let separator = Color(light: Color(white: 0.9), dark: Color(white: 0.15))

    // MARK: - Special Components

    /// 计算器按钮背景色
    static let calculatorButtonBackground = secondaryBackground

    /// 计算器运算符按钮背景色
    static let calculatorOperatorBackground = accent

    /// 卡片阴影色
    static let cardShadow = Color(light: Color.black.opacity(0.1), dark: Color.white.opacity(0.05))

    /// 网格项背景色
    static let gridItemBackground = Color(light: Color(white: 0.95), dark: Color(white: 0.15))

    /// 加密指示器背景色
    static let encryptionIndicator = Color.green.opacity(0.2)

    // MARK: - Status Colors

    /// 已选中背景色
    static let selectedBackground = Color.blue.opacity(0.15)

    /// 悬停背景色
    static let hoverBackground = Color(
        light: Color.black.opacity(0.05), dark: Color.white.opacity(0.1))

    /// 禁用背景色
    static let disabledBackground = Color(light: Color(white: 0.95), dark: Color(white: 0.1))

    /// 禁用文本色
    static let disabledText = Color(light: Color(white: 0.7), dark: Color(white: 0.3))
}

// MARK: - Color Extension

extension Color {
    /// 根据亮暗模式返回不同颜色
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
