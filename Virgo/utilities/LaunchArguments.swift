//
//  LaunchArguments.swift
//  Virgo
//
//  Shared launch arguments used by the app and tests.
//

import Foundation

enum LaunchArguments {
    static let uiTesting = "-UITesting"
    static let resetState = "-ResetState"
    /// Skip seeding sample data after reset - used for tests that assert empty state
    static let skipSeed = "-SkipSeed"
}
