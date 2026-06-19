//
//  ContentStartupPolicy.swift
//  Virgo
//
//  Startup decision helpers for ContentView.
//

import Foundation

/// The action ContentView should take at startup based on launch arguments and data state.
enum ContentStartupAction: Equatable {
    /// Delete all existing songs then seed fresh fixture data.
    case clearAndSeed
    /// Delete all existing songs without seeding.
    case clearOnly
    /// Seed only the missing fixture songs (non-destructive).
    case seedIfNeeded
    /// No startup data manipulation needed.
    case noAction
}

/// Pure decision helpers for ContentView startup logic.
enum ContentStartupPolicy {

    /// Determines which startup action to perform based on launch arguments and missing fixture data.
    static func startupAction(arguments: [String], missingFixtureTitles: Set<String>) -> ContentStartupAction {
        guard arguments.contains(LaunchArguments.uiTesting) else { return .noAction }

        if arguments.contains(LaunchArguments.resetState) {
            return arguments.contains(LaunchArguments.skipSeed) ? .clearOnly : .clearAndSeed
        }

        if !arguments.contains(LaunchArguments.skipSeed) && !missingFixtureTitles.isEmpty {
            return .seedIfNeeded
        }

        return .noAction
    }

    /// Returns true when startup will delete persisted songs before the first app screen is ready.
    static func shouldPrepareBeforeFirstRender(arguments: [String]) -> Bool {
        arguments.contains(LaunchArguments.uiTesting) && arguments.contains(LaunchArguments.resetState)
    }

    /// Returns true when bundled local DTX fixtures should be imported during startup.
    static func shouldImportBundledLocalDTXFixtures(arguments: [String]) -> Bool {
        !arguments.contains(LaunchArguments.skipSeed)
    }

    /// Returns true when the song should use `AudioPlaybackService` (preview-file-backed playback).
    static func shouldUsePreviewPlayer(for song: Song) -> Bool {
        song.isServerImported && song.previewFilePath != nil
    }
}
