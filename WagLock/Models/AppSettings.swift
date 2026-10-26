//
//  AppSettings.swift
//  WagLock
//
//  App settings (UserDefaults wrapper)
//  Manages user preferences
//

internal import Combine
import Foundation
import SwiftUI

/// Auto-lock delay after leaving the app
enum AutoLockTimeout: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case never = -1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .immediately: return String(localized: "settings.autoLock.immediately")
        case .oneMinute: return String(localized: "settings.autoLock.after1min")
        case .fiveMinutes: return String(localized: "settings.autoLock.after5min")
        case .never: return String(localized: "settings.autoLock.never")
        }
    }
}

/// App settings manager
class AppSettings: ObservableObject {

    // MARK: - Singleton

    static let shared = AppSettings()

    // MARK: - UserDefaults

    private let defaults = UserDefaults.standard

    // MARK: - Published Properties

    /// Sort order
    @Published var sortOrder: MediaItem.SortOrder {
        didSet {
            defaults.set(sortOrder.rawValue, forKey: AppConstants.UserDefaultsKeys.sortOrder)
        }
    }

    /// Grid column count
    @Published var gridColumns: Int {
        didSet {
            // Keep within the valid range
            let validColumns = min(
                max(gridColumns, AppConstants.gridColumnsRange.lowerBound),
                AppConstants.gridColumnsRange.upperBound)
            if validColumns != gridColumns {
                gridColumns = validColumns
            }
            defaults.set(gridColumns, forKey: AppConstants.UserDefaultsKeys.gridColumns)
        }
    }

    /// Whether this is the first launch
    @Published var isFirstLaunch: Bool {
        didSet {
            defaults.set(isFirstLaunch, forKey: AppConstants.UserDefaultsKeys.isFirstLaunch)
        }
    }

    /// Last access time
    @Published var lastAccessTime: Date {
        didSet {
            defaults.set(lastAccessTime, forKey: AppConstants.UserDefaultsKeys.lastAccessTime)
        }
    }

    /// Whether guest mode is enabled
    @Published var guestModeEnabled: Bool {
        didSet {
            defaults.set(guestModeEnabled, forKey: AppConstants.UserDefaultsKeys.guestModeEnabled)
        }
    }

    /// Auto-lock delay after leaving the app
    @Published var autoLockTimeout: AutoLockTimeout {
        didSet {
            defaults.set(
                autoLockTimeout.rawValue, forKey: AppConstants.UserDefaultsKeys.autoLockTimeout)
        }
    }

    // MARK: - Initialization

    private init() {
        // Read settings from UserDefaults
        if let sortOrderString = defaults.string(forKey: AppConstants.UserDefaultsKeys.sortOrder),
            let sortOrder = MediaItem.SortOrder(rawValue: sortOrderString)
        {
            self.sortOrder = sortOrder
        } else {
            self.sortOrder = .dateNewest  // Default: newest first
        }

        let savedColumns = defaults.integer(forKey: AppConstants.UserDefaultsKeys.gridColumns)
        self.gridColumns = savedColumns > 0 ? savedColumns : AppConstants.defaultGridColumns

        self.isFirstLaunch =
            defaults.object(forKey: AppConstants.UserDefaultsKeys.isFirstLaunch) == nil
            ? true : defaults.bool(forKey: AppConstants.UserDefaultsKeys.isFirstLaunch)

        if let lastAccess = defaults.object(forKey: AppConstants.UserDefaultsKeys.lastAccessTime)
            as? Date
        {
            self.lastAccessTime = lastAccess
        } else {
            self.lastAccessTime = Date()
        }

        self.guestModeEnabled = defaults.bool(
            forKey: AppConstants.UserDefaultsKeys.guestModeEnabled)

        // When unset, default to "lock immediately" (privacy first)
        if defaults.object(forKey: AppConstants.UserDefaultsKeys.autoLockTimeout) == nil {
            self.autoLockTimeout = .immediately
        } else {
            self.autoLockTimeout =
                AutoLockTimeout(
                    rawValue: defaults.integer(forKey: AppConstants.UserDefaultsKeys.autoLockTimeout)
                ) ?? .immediately
        }

    }

    // MARK: - Public Methods

    /// Reset all settings to defaults
    func resetToDefaults() {
        sortOrder = .dateNewest
        gridColumns = AppConstants.defaultGridColumns
        isFirstLaunch = false
        lastAccessTime = Date()

    }

    /// Update the last access time
    func updateLastAccessTime() {
        lastAccessTime = Date()
    }

    /// Mark first launch as completed
    func completeFirstLaunch() {
        isFirstLaunch = false
    }

    // MARK: - Grid Settings

    /// Increase grid column count
    func increaseGridColumns() {
        if gridColumns < AppConstants.gridColumnsRange.upperBound {
            gridColumns += 1
        }
    }

    /// Decrease grid column count
    func decreaseGridColumns() {
        if gridColumns > AppConstants.gridColumnsRange.lowerBound {
            gridColumns -= 1
        }
    }

    /// Grid item width (computed from screen width and column count)
    func gridItemWidth(containerWidth: CGFloat) -> CGFloat {
        let spacing = AppConstants.gridSpacing * CGFloat(gridColumns - 1)
        let padding: CGFloat = 32  // 16 on each side
        let availableWidth = containerWidth - spacing - padding
        return availableWidth / CGFloat(gridColumns)
    }

    // MARK: - Statistics

    /// Days the app has been in use (since first launch)
    var daysSinceFirstLaunch: Int {
        if isFirstLaunch {
            return 0
        }
        return Calendar.current.dateComponents([.day], from: lastAccessTime, to: Date()).day ?? 0
    }
}

// MARK: - Preview Helper

#if DEBUG
    extension AppSettings {
        /// Mock settings for previews
        static var preview: AppSettings {
            let settings = AppSettings.shared
            settings.sortOrder = .dateNewest
            settings.gridColumns = 3
            return settings
        }
    }
#endif
