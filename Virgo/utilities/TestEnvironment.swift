//
//  TestEnvironment.swift
//  Virgo
//
//  Shared utility for detecting test environment to prevent audio/MIDI
//  initialization during unit tests.
//

import Foundation

/// Centralized test environment detection to avoid audio and hardware
/// initialization during unit tests which can cause crashes.
enum TestEnvironment {
    /// Cached result of test environment detection.
    /// Evaluated once at first access for performance.
    static let isRunningTests: Bool = {
        #if DEBUG
        // Method 1: XCTest detection (maintains backward compatibility)
        if ProcessInfo.processInfo.arguments.contains("XCTestConfigurationFilePath") {
            Logger.debug("Test environment detected via XCTestConfigurationFilePath argument")
            return true
        }

        // Method 2: Bundle identifier detection (most reliable for Swift Testing)
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           bundleIdentifier.hasSuffix("Tests") {
            Logger.debug("Test environment detected via bundle identifier: \(bundleIdentifier)")
            return true
        }

        // Method 3: Environment variables (both XCTest and Swift Testing)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            Logger.debug("Test environment detected via XCTestConfigurationFilePath environment variable")
            return true
        }

        // Method 4: Process name detection (catches various test runners)
        let processName = ProcessInfo.processInfo.processName.lowercased()
        if processName.contains("xctest") || processName.hasSuffix("tests") {
            Logger.debug("Test environment detected via process name: \(processName)")
            return true
        }
        #endif

        return false
    }()
}
