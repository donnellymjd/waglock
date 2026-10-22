import Foundation

enum AppIconOption: String, CaseIterable, Identifiable {
    case primary, caughtYouLooking, spectrum, watchfulHusky, paper, calculator, pebble, ruler

    var id: String { rawValue }

    var iconName: String? {
        switch self {
        case .primary: return nil
        case .caughtYouLooking: return "AppIcon-CaughtYouLooking"
        case .spectrum: return "AppIcon-Spectrum"
        case .watchfulHusky: return "AppIcon-WatchfulHusky"
        case .paper: return "AppIcon-Paper"
        case .calculator: return "AppIcon-Calculator"
        case .pebble: return "AppIcon-Pebble"
        case .ruler: return "AppIcon-Ruler"
        }
    }

    var previewAsset: String {
        switch self {
        case .primary: return "AppIconDisplay"
        case .caughtYouLooking: return "IconPreview-CaughtYouLooking"
        case .spectrum: return "IconPreview-Spectrum"
        case .watchfulHusky: return "IconPreview-WatchfulHusky"
        case .paper: return "IconPreview-Paper"
        case .calculator: return "IconPreview-Calculator"
        case .pebble: return "IconPreview-Pebble"
        case .ruler: return "IconPreview-Ruler"
        }
    }

    var title: String {
        switch self {
        case .primary: return String(localized: "appicon.name.primary")
        case .caughtYouLooking: return String(localized: "appicon.name.caughtYouLooking")
        case .spectrum: return String(localized: "appicon.name.spectrum")
        case .watchfulHusky: return String(localized: "appicon.name.watchfulHusky")
        case .paper: return String(localized: "appicon.name.paper")
        case .calculator: return String(localized: "appicon.name.calculator")
        case .pebble: return String(localized: "appicon.name.pebble")
        case .ruler: return String(localized: "appicon.name.ruler")
        }
    }

    var subtitle: String {
        switch self {
        case .primary: return String(localized: "appicon.description.primary")
        case .caughtYouLooking: return String(localized: "appicon.description.caughtYouLooking")
        case .spectrum: return String(localized: "appicon.description.spectrum")
        case .watchfulHusky: return String(localized: "appicon.description.watchfulHusky")
        case .paper: return String(localized: "appicon.description.paper")
        case .calculator: return String(localized: "appicon.description.calculator")
        case .pebble: return String(localized: "appicon.description.pebble")
        case .ruler: return String(localized: "appicon.description.ruler")
        }
    }
}
