//
//  LoadingOverlay.swift
//  WagLock
//
//  全局加载等待层
//  提供统一的加载提示UI
//

import SwiftUI

/// 加载等待层视图
struct LoadingOverlay: View {
    let message: String
    let progress: Double?  // 0.0 到 1.0，nil 表示不确定进度

    init(message: String = String(localized: "common.loading"), progress: Double? = nil) {
        self.message = message
        self.progress = progress
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            WagLockProgressCard(title: message, detail: "Keep this screen open", progress: progress)
                .frame(maxWidth: 360).padding(24)
                .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - View Extension

extension View {
    /// 显示加载等待层
    /// - Parameters:
    ///   - isShowing: 是否显示
    ///   - message: 提示文字
    ///   - progress: 进度（0.0-1.0，nil表示不确定）
    func loadingOverlay(
        isShowing: Bool,
        message: String = String(localized: "common.loading"),
        progress: Double? = nil
    ) -> some View {
        ZStack {
            self

            if isShowing {
                LoadingOverlay(message: message, progress: progress)
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isShowing)
    }
}

// MARK: - Preview

#Preview("Indeterminate Progress") {
    VStack {
        Text("Content Area")
    }
    .loadingOverlay(isShowing: true, message: String(localized: "common.processing"))
}

#Preview("Determinate Progress") {
    VStack {
        Text("Content Area")
    }
    .loadingOverlay(
        isShowing: true, message: String(localized: "common.importing.photos"), progress: 0.65)
}
