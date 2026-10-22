internal import Combine
import UIKit

@MainActor
protocol AppIconApplication {
    var alternateIconName: String? { get }
    var supportsAlternateIcons: Bool { get }
    func changeIcon(to name: String?) async throws
}

@MainActor
private struct SystemIconApplication: AppIconApplication {
    var alternateIconName: String? { UIApplication.shared.alternateIconName }
    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    func changeIcon(to name: String?) async throws {
        try await UIApplication.shared.setAlternateIconName(name)
    }
}

@MainActor
final class AppIconService: ObservableObject {
    enum IconError: LocalizedError {
        case unsupported

        var errorDescription: String? {
            switch self {
            case .unsupported: return String(localized: "appicon.error.unsupported")
            }
        }
    }

    @Published private(set) var selectedIconName: String?
    @Published private(set) var isChanging = false
    private let application: any AppIconApplication

    init(application: (any AppIconApplication)? = nil) {
        let application = application ?? SystemIconApplication()
        self.application = application
        selectedIconName = Self.pickerIconName(for: application.alternateIconName)
    }

    func refresh() {
        selectedIconName = Self.pickerIconName(for: application.alternateIconName)
    }

    private static func pickerIconName(for systemName: String?) -> String? {
        // Caught You Looking is a distinct alternate to the blue guardian default.
        systemName
    }

    func select(_ icon: AppIconOption) async throws {
        guard !isChanging else { return }
        refresh()
        guard selectedIconName != icon.iconName else { return }
        guard application.supportsAlternateIcons else { throw IconError.unsupported }

        isChanging = true
        defer {
            refresh()
            isChanging = false
        }
        try await application.changeIcon(to: icon.iconName)
    }
}
