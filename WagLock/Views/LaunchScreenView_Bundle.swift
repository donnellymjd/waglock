//
//  LaunchScreenView_Bundle.swift
//  WagLock
//
//  Launch screen view using bundle resources (fallback approach)
//

import SwiftUI

struct LaunchScreenView_Bundle: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Option 1: load the image from the bundle
            if let uiImage = UIImage(named: "launch_screen") {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .opacity(isAnimating ? 1.0 : 0.0)
            } else {
                // If the image fails to load, show the fallback view
                FallbackLaunchView()
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.5)) {
                isAnimating = true
            }
        }
    }
}

// Fallback launch view (if the image fails to load)
struct FallbackLaunchView: View {
    var body: some View {
        ZStack {
            // Gradient background (matches the image's palette)
            LinearGradient(
                colors: [
                    Color(red: 0.66, green: 0.71, blue: 0.90),  // Light lavender
                    Color(red: 0.48, green: 0.56, blue: 0.82),  // Periwinkle blue
                    Color(red: 0.18, green: 0.24, blue: 0.44),  // Deep navy
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Broken-chain icon (simplified)
                ZStack {
                    // Left half of the chain
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 60, height: 24)
                        .offset(x: -20, y: 0)

                    // Right half of the chain
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.0, green: 0.9, blue: 1.0))
                        .frame(width: 60, height: 24)
                        .offset(x: 20, y: 0)
                }
                .frame(height: 100)

                // Text
                VStack(spacing: 12) {
                    Text(String(localized: "launch.subtitle.opensource"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))

                    Text(String(localized: "launch.subtitle.privacyFirst"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()
            }
        }
    }
}

#Preview {
    LaunchScreenView_Bundle()
}
