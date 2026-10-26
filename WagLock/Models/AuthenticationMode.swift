//
//  AuthenticationMode.swift
//  WagLock
//
//  Created by Claude on 2025-01-17.
//

import Foundation

/// User authentication mode
enum AuthenticationMode {
    /// Owner mode - full access
    case owner
    case secondaryOwner

    /// Guest mode - restricted access (all content hidden)
    case guest

    /// Unauthenticated - default state; login required
    case unauthenticated
}
