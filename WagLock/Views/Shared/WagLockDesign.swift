import CoreText
import SwiftUI

// MARK: - Typography

/// Bundled Poppins (SIL Open Font License; WagLock/Resources/Fonts). Every style is
/// relative to a system text style so it scales with Dynamic Type. If registration
/// fails, SwiftUI falls back to the system font at the same size.
enum WagLockFonts {
    static let faces = ["Poppins-Regular", "Poppins-Medium", "Poppins-SemiBold", "Poppins-Bold", "Poppins-ExtraBold"]

    /// Info.plist UIAppFonts covers the app; this also covers previews and test hosts.
    static func registerIfNeeded() {
        for face in faces where UIFont(name: face, size: 12) == nil {
            guard let url = Bundle.main.url(forResource: face, withExtension: "ttf")
                ?? Bundle.main.url(forResource: face, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    enum Weight: String {
        case regular = "Poppins-Regular", medium = "Poppins-Medium", semibold = "Poppins-SemiBold"
        case bold = "Poppins-Bold", extraBold = "Poppins-ExtraBold"
    }

    static func poppins(_ size: CGFloat, _ weight: Weight, relativeTo style: Font.TextStyle) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }
}

extension Font {
    /// 34 / 800 / +0.04em
    static let wlDisplay = WagLockFonts.poppins(34, .extraBold, relativeTo: .largeTitle)
    /// 30 / 800 / +0.03em
    static let wlTitle = WagLockFonts.poppins(30, .extraBold, relativeTo: .title)
    /// 26 / 800 / +0.02em
    static let wlSheetTitle = WagLockFonts.poppins(26, .extraBold, relativeTo: .title2)
    /// 16 / 700
    static let wlHeading = WagLockFonts.poppins(16, .bold, relativeTo: .headline)
    /// 14 / 600
    static let wlBodyStrong = WagLockFonts.poppins(14, .semibold, relativeTo: .body)
    /// 14 / 400 / 21
    static let wlBody = WagLockFonts.poppins(14, .regular, relativeTo: .body)
    /// 12 / 400 / 17
    static let wlMeta = WagLockFonts.poppins(12, .regular, relativeTo: .footnote)
    /// 12 / 600 caps +0.16em
    static let wlLabel = WagLockFonts.poppins(12, .semibold, relativeTo: .footnote)
    /// 15 / 700 caps +0.22em
    static let wlButton = WagLockFonts.poppins(15, .bold, relativeTo: .headline)
    /// 10 / 500 (600 active)
    static let wlTab = WagLockFonts.poppins(10, .medium, relativeTo: .caption2)
}

extension View {
    /// Display and title sizes stop growing at roughly 1.4x.
    func wlCappedDisplay() -> some View { dynamicTypeSize(...DynamicTypeSize.accessibility1) }
}

/// A screen title in the Graphite style.
struct WagLockTitle: View {
    let text: String
    var size: Kind = .title
    enum Kind { case display, title, sheet }
    var body: some View {
        Text(text)
            .font(size == .display ? .wlDisplay : size == .title ? .wlTitle : .wlSheetTitle)
            .tracking(size == .display ? 1.36 : size == .title ? 0.9 : 0.52)
            .foregroundStyle(Graphite.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .wlCappedDisplay()
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// THIS LIBRARY-style caps label.
struct WagLockSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.wlLabel).tracking(1.9).foregroundStyle(Graphite.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons

/// 54 pt primary: accent gradient, caps, glow. One per screen, bottom-anchored.
struct WagLockPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.wlButton).tracking(3.3).textCase(.uppercase)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(enabled ? Graphite.onAccent : Graphite.textMuted)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(enabled ? AnyShapeStyle(Graphite.accentGradient) : AnyShapeStyle(Graphite.surface2))
                    .shadow(color: enabled ? Graphite.accentStrong.opacity(0.30) : .clear, radius: 14, y: 12)
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Outlined destructive button (LOCK WAGLOCK, DELETE LIBRARY).
struct WagLockDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WagLockFonts.poppins(13, .bold, relativeTo: .headline)).tracking(2.6).textCase(.uppercase)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(enabled ? Graphite.danger : Graphite.textMuted)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(enabled ? Graphite.dangerLine : Graphite.line, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Secondary: surface fill with a line border.
struct WagLockSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.wlBodyStrong)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Graphite.textPrimary)
            .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Graphite.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Fields

/// Default / focus / error field with a leading icon.
struct WagLockField: View {
    let symbol: String
    let placeholder: String
    @Binding var text: String
    var secure = true
    var isError = false
    var numberPad = false
    var contentType: UITextContentType? = .password
    @FocusState private var focused: Bool
    @State private var reveal = false

    init(symbol: String, placeholder: String, text: Binding<String>, secure: Bool = true, isError: Bool = false,
         numberPad: Bool = false, contentType: UITextContentType? = .password) {
        self.symbol = symbol; self.placeholder = placeholder; _text = text
        self.secure = secure; self.isError = isError; self.numberPad = numberPad; self.contentType = contentType
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                .foregroundStyle(isError ? Graphite.danger : Graphite.textSecondary).accessibilityHidden(true)
            Group {
                if secure && !reveal { SecureField(placeholder, text: $text) }
                else { TextField(placeholder, text: $text) }
            }
            .font(WagLockFonts.poppins(16, .medium, relativeTo: .body))
            .foregroundStyle(Graphite.textPrimary)
            .textContentType(contentType)
            .keyboardType(numberPad ? .numberPad : .default)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($focused)
            .accessibilityLabel(placeholder)
            if secure {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye").foregroundStyle(Graphite.textSecondary)
                        .frame(width: 44, height: 44)
                }.accessibilityLabel(reveal ? "Hide passcode" : "Show passcode")
            }
        }
        .padding(.leading, 16).padding(.trailing, secure ? 6 : 16)
        .frame(minHeight: 54)
        .background(Graphite.input, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(isError ? Graphite.dangerLine : focused ? Graphite.accentText : .clear, lineWidth: 1.5))
        .shadow(color: isError ? Graphite.dangerLine.opacity(0.12) : .clear, radius: 4)
    }
}

/// Number pad / Full keyboard segmented choice.
struct WagLockKeyboardPicker: View {
    @Binding var numberPad: Bool
    var body: some View {
        HStack(spacing: 0) {
            segment("Number pad", selected: numberPad) { numberPad = true }
            segment("Full keyboard", selected: !numberPad) { numberPad = false }
        }
        .padding(4)
        .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain).accessibilityLabel("Passcode type")
    }
    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(selected ? .wlBodyStrong : WagLockFonts.poppins(14, .medium, relativeTo: .body))
                .foregroundStyle(selected ? Graphite.textPrimary : Graphite.textMuted)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(selected ? Graphite.line : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Rows

/// List row: icon tile, title, muted subtitle, chevron. Standard, destructive or dashed add.
struct WagLockRow: View {
    enum Kind { case standard, destructive, add }
    let symbol: String
    let title: String
    let detail: String?
    var kind: Kind = .standard
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                .foregroundStyle(kind == .destructive ? Graphite.danger : Graphite.accentText)
                .frame(width: 40, height: 40)
                .background(kind == .destructive ? Graphite.dangerTint : kind == .add ? Graphite.accentTint : Graphite.surface2,
                            in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.wlBodyStrong)
                    .foregroundStyle(kind == .destructive ? Graphite.danger : Graphite.textPrimary)
                if let detail {
                    Text(detail).font(.wlMeta).foregroundStyle(Graphite.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x7D8597)).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(minHeight: 44)
        .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if kind == .add {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Graphite.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Notes

/// Info, caution and error notes.
struct WagLockNote: View {
    enum Kind { case info, caution, error }
    let kind: Kind
    var title: String?
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind == .info ? "shield" : "exclamationmark.circle")
                .font(.system(size: 16)).foregroundStyle(tint).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title).font(.wlBodyStrong)
                        .foregroundStyle(kind == .error ? Color(hex: 0xFFC0C0) : Graphite.textPrimary)
                }
                Text(text).font(.wlMeta).foregroundStyle(Graphite.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: kind == .info ? 1 : 0))
        .accessibilityElement(children: .combine)
    }

    private var tint: Color { kind == .info ? Graphite.accentText : kind == .caution ? Graphite.warn : Graphite.danger }
    private var background: Color {
        kind == .info ? Graphite.accentStrong.opacity(0.06) : kind == .caution ? Graphite.warnTint : Graphite.dangerTint
    }
    private var border: Color { Graphite.accentText.opacity(0.16) }
}

/// Bottom-sheet header: grabber, Cancel, centered title.
struct WagLockSheetHeader: View {
    let title: String
    var cancelTitle = "Cancel"
    let cancel: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Capsule().fill(Graphite.line).frame(width: 40, height: 5).accessibilityHidden(true)
            ZStack {
                Text(title).font(.wlHeading).foregroundStyle(Graphite.textPrimary)
                HStack {
                    Button(cancelTitle, action: cancel)
                        .font(WagLockFonts.poppins(15, .medium, relativeTo: .body))
                        .foregroundStyle(Graphite.textSecondary).frame(minHeight: 44)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Existing components, restyled

struct WagLockInfoCard: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary)
            Text(detail).font(.wlMeta).foregroundStyle(Graphite.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WagLockNavigationRow: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        WagLockRow(symbol: symbol, title: title, detail: detail, showsChevron: false)
    }
}

struct WagLockSearchField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Graphite.textMuted)
            TextField(title, text: $text).textInputAutocapitalization(.never)
                .autocorrectionDisabled().accessibilityLabel(title)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Clear search").foregroundStyle(Graphite.textMuted)
            }
        }
        .font(.wlBody)
        .foregroundStyle(Graphite.textPrimary)
        .padding(12)
        .background(Graphite.input, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct WagLockSubtitle: View {
    let text: String
    var body: some View {
        Text(text).font(.wlMeta).foregroundStyle(Graphite.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.bottom, 12)
    }
}

struct WagLockListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Graphite.base)
            .tint(Graphite.accentText)
    }
}

extension View {
    func wagLockList() -> some View { modifier(WagLockListStyle()) }
}

struct WagLockEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(Graphite.accentText)
                .frame(width: 88, height: 88)
                .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Graphite.line, lineWidth: 1))
                .accessibilityHidden(true)
            Text(title).font(.wlSheetTitle).foregroundStyle(Graphite.textPrimary).wlCappedDisplay()
            Text(detail).font(.wlBody).foregroundStyle(Graphite.textMuted)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 22)
    }
}

/// Rounded rows retain native List navigation, swipe actions and accessibility.
struct WagLockCardRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .listRowBackground(RoundedRectangle(cornerRadius: 14)
                .fill(Graphite.surface1).padding(.vertical, 4))
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
            Text(title).font(.wlBodyStrong).foregroundStyle(Graphite.textPrimary)
            Text(detail).font(.wlMeta).foregroundStyle(Graphite.textMuted)
            if let progress {
                let value = min(max(progress, 0), 1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Graphite.surface2)
                        Capsule().fill(Graphite.accentGradient).frame(width: proxy.size.width * value)
                    }
                }.frame(height: 8).accessibilityLabel("Progress").accessibilityValue("\(Int(value * 100)) percent")
                Text("\(Int(value * 100))%").font(.wlMeta.monospacedDigit()).foregroundStyle(Graphite.accentText)
            } else { ProgressView().tint(Graphite.accentText) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - App-wide UIKit chrome

enum WagLockChrome {
    /// Tab bar, navigation bar and segmented controls in Graphite with Poppins.
    static func apply() {
        WagLockFonts.registerIfNeeded()
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Graphite.bar)
        tab.shadowColor = .clear
        let item = UITabBarItemAppearance()
        let tabFont = UIFont(name: "Poppins-Medium", size: 10) ?? .systemFont(ofSize: 10, weight: .medium)
        let tabActiveFont = UIFont(name: "Poppins-SemiBold", size: 10) ?? .systemFont(ofSize: 10, weight: .semibold)
        item.normal.iconColor = UIColor(Graphite.textMuted)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Graphite.textMuted), .font: tabFont]
        item.selected.iconColor = UIColor(Graphite.accentText)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(Graphite.accentText), .font: tabActiveFont]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = UIColor(Graphite.base)
        let titleFont = UIFont(name: "Poppins-SemiBold", size: 16) ?? .systemFont(ofSize: 16, weight: .semibold)
        let largeFont = UIFont(name: "Poppins-ExtraBold", size: 30) ?? .systemFont(ofSize: 30, weight: .heavy)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Graphite.textPrimary),
                                   .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: titleFont)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Graphite.textPrimary),
                                        .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: largeFont)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(Graphite.accentText)

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Graphite.line)
        UISegmentedControl.appearance().backgroundColor = UIColor(Graphite.surface1)
    }
}
