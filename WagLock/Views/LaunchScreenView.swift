import SwiftUI

struct LaunchScreenView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { ColorTheme.primaryText }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [ColorTheme.brandBackgroundStart, ColorTheme.brandBackgroundEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 26) {
                        Image("AppIconDisplay")
                            .resizable()
                            .scaledToFit()
                            .frame(width: min(geometry.size.width * 0.28, 128), height: min(geometry.size.width * 0.28, 128))
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .shadow(color: .black.opacity(isDark ? 0.22 : 0.12), radius: 24, y: 12)

                        VStack(spacing: 10) {
                            Text(AppConstants.appName)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .tracking(0.4)
                            Text(AppConstants.tagline)
                                .font(.subheadline)
                                .foregroundStyle(ink.opacity(0.65))
                        }
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 32)
                    Spacer()
                    Text("EARLY TEST BUILD")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ink.opacity(0.4))
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 28) + 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("launch.brand")
    }
}

#Preview {
    LaunchScreenView()
}
