//
//  Logger.swift
//  Virgo
//
//  Created by Chan Wai Chan on 12/7/2025.
//

import Foundation
import os

/// A logging utility that leverages iOS's unified logging system (os_log)
/// This provides structured logging with categories, subsystems, and proper
/// integration with Console.app and Instruments for debugging and monitoring.
struct Logger {

    // MARK: - Subsystem and Categories
    private static let subsystem = "com.cwchanap.Virgo"

    // Different categories for different parts of the app
    static let general = os.Logger(subsystem: subsystem, category: "General")
    static let database = os.Logger(subsystem: subsystem, category: "Database")
    static let audio = os.Logger(subsystem: subsystem, category: "Audio")
    static let ui = os.Logger(subsystem: subsystem, category: "UI")
    static let network = os.Logger(subsystem: subsystem, category: "Network")

    // MARK: - Convenience Methods

    /// Log database operations
    static func database(_ message: String) {
        database.info("\(message, privacy: .public)")
    }

    /// Log database errors
    static func databaseError(_ error: Error) {
        database.error("Database error: \(error.localizedDescription, privacy: .public)")
    }

    /// Log audio playback events
    static func audioPlayback(_ message: String) {
        audio.info("Playback: \(message, privacy: .public)")
    }

    /// Log UI interactions
    static func userAction(_ action: String) {
        ui.info("User action: \(action, privacy: .public)")
    }

    /// Log general debug information (only in debug builds)
    static func debug(_ message: String) {
        #if DEBUG
        general.debug("🐛 \(message, privacy: .public)")
        #endif
    }

    /// Log general information
    static func info(_ message: String) {
        general.info("ℹ️ \(message, privacy: .public)")
    }

    /// Log warnings
    static func warning(_ message: String) {
        general.notice("⚠️ \(message, privacy: .public)")
    }

    /// Log errors
    static func error(_ message: String) {
        general.error("❌ \(message, privacy: .public)")
    }

    /// Log critical errors
    static func critical(_ message: String) {
        general.critical("🚨 \(message, privacy: .public)")
    }
}

// MARK: - Usage Examples (commented out)
/*
 Usage examples:

 // Database operations
 Logger.database("Loading sample data...")
 Logger.databaseError(saveError)

 // Audio playback
 Logger.audioPlayback("Started track: \(track.title)")
 Logger.audioPlayback("Progress: \(progress)%")

 // UI interactions
 Logger.userAction("Tapped play button")
 Logger.userAction("Selected track: \(track.title)")

 // General logging
 Logger.debug("Debugging specific issue")  // Only shows in debug builds
 Logger.info("App launched successfully")
 Logger.warning("Unexpected condition occurred")
 Logger.error("Failed to save data")
 Logger.critical("Critical system error")

 Benefits of iOS unified logging system:
 - Structured logging with subsystem and category organization
 - Automatic integration with Console.app for debugging
 - Performance optimized (logs are stored efficiently)
 - Privacy-aware (can mark sensitive data as private)
 - Works with Instruments for performance analysis
 - Automatic log rotation and storage management
 - Different log levels automatically filtered by system
 - Can be viewed in real-time during development and testing

 To view logs:
 1. Open Console.app on Mac
 2. Connect your iOS device or simulator
 3. Filter by subsystem: "com.cwchanap.Virgo"
 4. Filter by category: "Database", "Audio", "UI", etc.
 */
