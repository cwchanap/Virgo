//
//  AppShellCoverageTests.swift
//  VirgoTests
//

import Testing
import Foundation
@testable import Virgo

@Suite("App Shell Coverage Tests", .serialized)
@MainActor
struct AppShellCoverageTests {

    // MARK: - ContentStartupPolicy.startupAction

    @Test func testStartupActionClearAndSeed() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [LaunchArguments.uiTesting, LaunchArguments.resetState],
            missingFixtureTitles: []
        )
        #expect(action == .clearAndSeed)
    }

    @Test func testStartupActionClearOnly() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [LaunchArguments.uiTesting, LaunchArguments.resetState, LaunchArguments.skipSeed],
            missingFixtureTitles: []
        )
        #expect(action == .clearOnly)
    }

    @Test func testStartupActionSeedIfNeeded() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [LaunchArguments.uiTesting],
            missingFixtureTitles: ["Thunder Beat"]
        )
        #expect(action == .seedIfNeeded)
    }

    @Test func testStartupActionNoActionWhenNotUITesting() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [],
            missingFixtureTitles: ["Thunder Beat"]
        )
        #expect(action == .noAction)
    }

    @Test func testStartupActionNoActionWhenSkipSeedAndNoReset() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [LaunchArguments.uiTesting, LaunchArguments.skipSeed],
            missingFixtureTitles: ["Thunder Beat"]
        )
        #expect(action == .noAction)
    }

    @Test func testStartupActionNoActionWhenNoMissingFixtures() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [LaunchArguments.uiTesting],
            missingFixtureTitles: []
        )
        #expect(action == .noAction)
    }

    // MARK: - ContentStartupPolicy.shouldUsePreviewPlayer

    @Test func testShouldUsePreviewPlayerTrueForDTXImportWithPreview() {
        let song = Song(
            title: "Test Song",
            artist: "Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            timeSignature: .fourFour
        )
        song.previewFilePath = "/some/preview.mp3"
        #expect(ContentStartupPolicy.shouldUsePreviewPlayer(for: song) == true)
    }

    @Test func testShouldUsePreviewPlayerFalseForNonDTXImport() {
        let song = Song(
            title: "Rock Song",
            artist: "Artist",
            bpm: 140,
            duration: "3:30",
            genre: "Rock",
            timeSignature: .fourFour
        )
        #expect(ContentStartupPolicy.shouldUsePreviewPlayer(for: song) == false)
    }

    @Test func testShouldUsePreviewPlayerFalseForDTXImportWithoutPreview() {
        let song = Song(
            title: "Test Song",
            artist: "Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            timeSignature: .fourFour
        )
        #expect(ContentStartupPolicy.shouldUsePreviewPlayer(for: song) == false)
    }

    // MARK: - VirgoAppLaunchBehavior.shouldDisableAnimations

    @Test func testShouldDisableAnimationsTrueForUITesting() {
        let result = VirgoAppLaunchBehavior.shouldDisableAnimations(
            arguments: [LaunchArguments.uiTesting]
        )
        #expect(result == true)
    }

    @Test func testShouldDisableAnimationsFalseForEmptyArguments() {
        let result = VirgoAppLaunchBehavior.shouldDisableAnimations(arguments: [])
        #expect(result == false)
    }
}
