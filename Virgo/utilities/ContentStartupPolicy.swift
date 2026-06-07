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

    /// Returns true when the song should use `AudioPlaybackService` (preview-file-backed playback).
    static func shouldUsePreviewPlayer(for song: Song) -> Bool {
        song.isServerImported && song.previewFilePath != nil
    }
}
