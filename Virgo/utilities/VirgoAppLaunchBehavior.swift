//
//  VirgoAppLaunchBehavior.swift
//  Virgo
//
//  App-level launch behaviour helpers.
//

import Foundation

/// Pure helpers for VirgoApp startup decisions.
enum VirgoAppLaunchBehavior {

    /// Returns true when UI animations should be disabled (UI testing mode).
    static func shouldDisableAnimations(arguments: [String]) -> Bool {
        arguments.contains(LaunchArguments.uiTesting)
    }

    /// Returns true when macOS window restoration state should be cleared before
    /// SwiftUI's WindowGroup attempts to restore it. UI tests launch and
    /// terminate the app in rapid succession; after 2+ cycles the saved state
    /// can fail to restore (window=0x0), leaving the app windowless. Clearing
    /// it on every UI-test launch ensures a fresh window.
    static func shouldClearWindowRestorationState(arguments: [String]) -> Bool {
        arguments.contains(LaunchArguments.uiTesting)
    }

}
