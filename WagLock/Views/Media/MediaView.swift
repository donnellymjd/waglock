//
//  MediaView.swift
//  WagLock
//
//  影音视图（合并视频与音频两个子标签）
//

import SwiftUI

struct MediaView: View {

    // MARK: - Environment

    @EnvironmentObject var authViewModel: AuthenticationViewModel

    // MARK: - State

    @State private var selectedSection = 0

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                WagLockSubtitle(text: "Your videos and audio")
                Picker("Media type", selection: $selectedSection) {
                    Text(String(localized: "tab.videos")).tag(0)
                    Text(String(localized: "tab.audio")).tag(1)
                }.pickerStyle(.segmented).padding(.horizontal, 24)
                ZStack {
                if selectedSection == 0 {
                    VideosView()
                        .environmentObject(authViewModel)
                } else {
                    AudioView()
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(ColorTheme.primaryBackground)
            .navigationTitle(String(localized: "tab.media"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Preview

#Preview {
    MediaView()
        .environmentObject(AuthenticationViewModel())
}
