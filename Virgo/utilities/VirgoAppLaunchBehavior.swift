//
//  VirgoAppLaunchBehavior.swift
//  Virgo
//
//  App-level launch behaviour helpers.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Pure helpers for VirgoApp startup decisions.
enum VirgoAppLaunchBehavior {

    /// Returns true when UI animations should be disabled (UI testing mode).
    static func shouldDisableAnimations(arguments: [String]) -> Bool {
        arguments.contains(LaunchArguments.uiTesting)
    }

}
