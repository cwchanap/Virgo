//
//  ReopenPolicy.swift
//  Virgo
//
//  Pure decision helper for the macOS app reopen flow.
//

import Foundation

/// Pure helper that decides how the macOS reopen event should be handled.
///
/// `NSApplicationDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)`
/// returns `true` to let AppKit perform its default reopen handling, or `false`
/// to signal that the app has handled the reopen itself. For a SwiftUI
/// `WindowGroup` app, AppKit's default path creates a new window from the group
/// when none exist — which is essential here because `File > New` is disabled
/// to enforce single-window behaviour. Suppressing that default (returning
/// `false` when no windows are visible) would leave the app running with no
/// usable window until relaunch.
enum ReopenPolicy {

    /// Returns whether AppKit should perform its default reopen handling.
    ///
    /// - When visible windows exist, returns `false`: the delegate activates an
    ///   existing window itself, so AppKit's default is unnecessary.
    /// - When no visible windows exist, returns `true` so SwiftUI's
    ///   `WindowGroup` creates a new window. This is the only recovery path
    ///   available to the user after closing the last window.
    static func shouldAppKitHandleReopen(hasVisibleWindows flag: Bool) -> Bool {
        !flag
    }
}
