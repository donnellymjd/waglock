import SwiftUI

/// App-owned components from the approved Figma design; system chrome stays native.
struct WagLockPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(ColorTheme.onAccent)
            .background(ColorTheme.accent.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45),
                        in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WagLockInfoCard: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(ColorTheme.primaryText)
            Text(detail).font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(ColorTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WagLockNavigationRow: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22)).frame(width: 22)
                .foregroundStyle(ColorTheme.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(ColorTheme.primaryText)
                Text(detail).font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 42)
        .padding(14)
        .background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct WagLockSearchField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(ColorTheme.secondaryText)
            TextField(title, text: $text).textInputAutocapitalization(.never)
                .autocorrectionDisabled().accessibilityLabel(title)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Clear search").foregroundStyle(ColorTheme.secondaryText)
            }
        }
        .font(.body)
        .padding(12)
        .background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct WagLockSubtitle: View {
    let text: String
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(ColorTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.bottom, 12)
    }
}

struct WagLockListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ColorTheme.primaryBackground)
            .tint(ColorTheme.accent)
    }
}

extension View {
    func wagLockList() -> some View { modifier(WagLockListStyle()) }
}

enum WagLockAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let preferenceKey = "waglock.appearance"
    var id: String { rawValue }
    var title: String { switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" } }
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

struct WagLockEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(ColorTheme.accent)
                .accessibilityHidden(true)
            Text(title).font(.title2.bold()).foregroundStyle(ColorTheme.primaryText)
            Text(detail).font(.body).foregroundStyle(ColorTheme.secondaryText)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 24)
    }
}

/// Rounded rows retain native List navigation, swipe actions and accessibility.
struct WagLockCardRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            .listRowBackground(RoundedRectangle(cornerRadius: 14)
                .fill(ColorTheme.secondaryBackground).padding(.vertical, 3))
    }
}

extension View {
    func wagLockCardRow() -> some View { modifier(WagLockCardRow()) }
}

struct WagLockProgressCard: View {
    let title: String
    let detail: String
    let progress: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(ColorTheme.primaryText)
            Text(detail).font(.footnote).foregroundStyle(ColorTheme.secondaryText)
            if let progress {
                ProgressView(value: min(max(progress, 0), 1)).tint(ColorTheme.accent)
                Text("\(Int(min(max(progress, 0), 1) * 100))%")
                    .font(.footnote.monospacedDigit()).foregroundStyle(ColorTheme.accent)
            } else { ProgressView().tint(ColorTheme.accent) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(ColorTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}
