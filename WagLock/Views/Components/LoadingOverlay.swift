//
//  LoadingOverlay.swift
//  WagLock
//
//  Global loading overlay
//  Shared loading indicator UI
//

import SwiftUI

/// Loading overlay view
struct LoadingOverlay: View {
    let message: String
    let progress: Double?  // 0.0 to 1.0; nil means indeterminate

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
    /// Show the loading overlay
    /// - Parameters:
    ///   - isShowing: Whether to show it
    ///   - message: Message text
    ///   - progress: Progress (0.0-1.0; nil means indeterminate)
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
