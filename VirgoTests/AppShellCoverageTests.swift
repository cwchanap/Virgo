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

    @Test("startupAction returns clearAndSeed when uiTesting+resetState with no missing fixtures")
    func testStartupActionClearAndSeed() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [LaunchArguments.uiTesting, LaunchArguments.resetState],
            missingFixtureTitles: []
        )
        #expect(action == .clearAndSeed)
    }

    @Test("startupAction returns clearOnly when uiTesting+resetState+skipSeed")
    func testStartupActionClearOnly() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [LaunchArguments.uiTesting, LaunchArguments.resetState, LaunchArguments.skipSeed],
            missingFixtureTitles: []
        )
        #expect(action == .clearOnly)
    }

    @Test("startupAction returns seedIfNeeded when uiTesting and missing fixtures present")
    func testStartupActionSeedIfNeeded() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [LaunchArguments.uiTesting],
            missingFixtureTitles: ["Thunder Beat"]
        )
        #expect(action == .seedIfNeeded)
    }

    @Test("startupAction returns noAction when not in UI testing mode")
    func testStartupActionNoActionWhenNotUITesting() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [],
            missingFixtureTitles: ["Thunder Beat"]
        )
        #expect(action == .noAction)
    }

    @Test("startupAction returns noAction when skipSeed set without resetState")
    func testStartupActionNoActionWhenSkipSeedAndNoReset() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [LaunchArguments.uiTesting, LaunchArguments.skipSeed],
            missingFixtureTitles: ["Thunder Beat"]
        )
        #expect(action == .noAction)
    }

    @Test("startupAction returns noAction when uiTesting but no missing fixtures")
    func testStartupActionNoActionWhenNoMissingFixtures() {
        let action = ContentStartupPolicy.startupAction(
            arguments: [LaunchArguments.uiTesting],
            missingFixtureTitles: []
        )
        #expect(action == .noAction)
    }

    // MARK: - ContentStartupPolicy.shouldUsePreviewPlayer

    @Test("shouldUsePreviewPlayer returns true for DTX Import genre with preview file")
    func testShouldUsePreviewPlayerTrueForDTXImportWithPreview() {
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

    @Test("shouldUsePreviewPlayer returns false for non-DTX Import genre")
    func testShouldUsePreviewPlayerFalseForNonDTXImport() {
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

    @Test("shouldUsePreviewPlayer returns false for DTX Import genre without preview file")
    func testShouldUsePreviewPlayerFalseForDTXImportWithoutPreview() {
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

    @Test("shouldDisableAnimations returns true when uiTesting argument present")
    func testShouldDisableAnimationsTrueForUITesting() {
        let result = VirgoAppLaunchBehavior.shouldDisableAnimations(
            arguments: [LaunchArguments.uiTesting]
        )
        #expect(result == true)
    }

    @Test("shouldDisableAnimations returns false when arguments are empty")
    func testShouldDisableAnimationsFalseForEmptyArguments() {
        let result = VirgoAppLaunchBehavior.shouldDisableAnimations(arguments: [])
        #expect(result == false)
    }
}
