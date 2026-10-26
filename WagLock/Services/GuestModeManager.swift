//
//  GuestModeManager.swift
//  WagLock
//
//  Created by Claude on 2025-01-17.
//  Guest mode manager - tracks the authentication mode and content visibility
//

internal import Combine
import Foundation

/// Guest mode manager
/// Responsibilities:
/// 1. Track the current authentication mode (owner/guest/unauthenticated)
/// 2. Control content visibility
/// 3. Session-scoped state (authentication is required again after relaunch)
///
/// Security properties:
/// - Defaults to unauthenticated so nothing leaks after a relaunch
/// - @MainActor keeps access thread-safe
@MainActor
final class GuestModeManager: ObservableObject {

    // MARK: - Singleton

    static let shared = GuestModeManager()

    private init() {}

    // MARK: - Published Properties

    /// Current authentication mode
    @Published private(set) var currentMode: AuthenticationMode = .unauthenticated

    // MARK: - Public Methods

    /// Set the authentication mode
    /// - Parameter mode: Authentication mode (owner/guest/unauthenticated)
    func setAuthenticationMode(_ mode: AuthenticationMode) {
        currentMode = mode
    }

    /// Whether content should be shown
    /// - Returns: true in owner mode, false in guest mode
    var shouldShowContent: Bool {
        return currentMode == .owner || currentMode == .secondaryOwner
    }

    /// Whether guest mode is active
    var isGuestMode: Bool {
        return currentMode == .guest
    }

    /// Whether owner mode is active
    var isOwnerMode: Bool {
        return currentMode == .owner || currentMode == .secondaryOwner
    }

    /// Reset to unauthenticated (used on logout)
    func reset() {
        currentMode = .unauthenticated
    }
}
