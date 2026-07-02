//
//  AppShellCoverageTests.swift
//  VirgoTests
//

import Testing
import Foundation
@testable import Virgo

@Suite("App Shell Coverage Tests")
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

    // MARK: - ContentStartupPolicy.shouldImportBundledLocalDTXFixtures

    @Test("shouldImportBundledLocalDTXFixtures returns true for normal launches")
    func testShouldImportBundledLocalDTXFixturesForNormalLaunch() {
        let shouldImport = ContentStartupPolicy.shouldImportBundledLocalDTXFixtures(arguments: [])
        #expect(shouldImport == true)
    }

    @Test("shouldImportBundledLocalDTXFixtures returns false when skipSeed is present")
    func testShouldImportBundledLocalDTXFixturesRespectsSkipSeed() {
        let shouldImport = ContentStartupPolicy.shouldImportBundledLocalDTXFixtures(
            arguments: [LaunchArguments.uiTesting, LaunchArguments.skipSeed]
        )
        #expect(shouldImport == false)
    }

    // MARK: - ContentStartupPolicy.shouldUsePreviewPlayer

    @Test("shouldUsePreviewPlayer returns true for server-imported song with preview file")
    func testShouldUsePreviewPlayerTrueForDTXImportWithPreview() {
        let song = Song(
            title: "Test Song",
            artist: "Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            timeSignature: .fourFour,
            isServerImported: true
        )
        song.previewFilePath = "/some/preview.mp3"
        #expect(ContentStartupPolicy.shouldUsePreviewPlayer(for: song) == true)
    }

    @Test("shouldUsePreviewPlayer returns false for non-server-imported song")
    func testShouldUsePreviewPlayerFalseForNonDTXImport() {
        let song = Song(
            title: "Rock Song",
            artist: "Artist",
            bpm: 140,
            duration: "3:30",
            genre: "Rock",
            timeSignature: .fourFour,
            isServerImported: false
        )
        #expect(ContentStartupPolicy.shouldUsePreviewPlayer(for: song) == false)
    }

    @Test("shouldUsePreviewPlayer returns false for server-imported song without preview file")
    func testShouldUsePreviewPlayerFalseForDTXImportWithoutPreview() {
        let song = Song(
            title: "Test Song",
            artist: "Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            timeSignature: .fourFour,
            isServerImported: true
        )
        #expect(ContentStartupPolicy.shouldUsePreviewPlayer(for: song) == false)
    }

    @Test("shouldUsePreviewPlayer returns true for server-imported song with curated genre and preview file")
    func testShouldUsePreviewPlayerTrueForServerImportedWithCuratedGenre() {
        let song = Song(
            title: "Curated Song",
            artist: "Artist",
            bpm: 120,
            duration: "3:00",
            genre: "Rock",
            timeSignature: .fourFour,
            isServerImported: true
        )
        song.previewFilePath = "/some/preview.mp3"
        #expect(ContentStartupPolicy.shouldUsePreviewPlayer(for: song) == true)
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

    @Test("shouldDisableAnimations returns false when arguments lack uiTesting flag")
    func testShouldDisableAnimationsFalseForOtherArguments() {
        let result = VirgoAppLaunchBehavior.shouldDisableAnimations(
            arguments: [LaunchArguments.resetState]
        )
        #expect(result == false)
    }

    // MARK: - VirgoAppLaunchBehavior.shouldClearWindowRestorationState

    @Test("shouldClearWindowRestorationState returns true when uiTesting argument present")
    func testShouldClearWindowRestorationStateTrueForUITesting() {
        let result = VirgoAppLaunchBehavior.shouldClearWindowRestorationState(
            arguments: [LaunchArguments.uiTesting]
        )
        #expect(result == true)
    }

    @Test("shouldClearWindowRestorationState returns false when arguments are empty")
    func testShouldClearWindowRestorationStateFalseForEmptyArguments() {
        let result = VirgoAppLaunchBehavior.shouldClearWindowRestorationState(arguments: [])
        #expect(result == false)
    }

    @Test("shouldClearWindowRestorationState returns false when arguments lack uiTesting flag")
    func testShouldClearWindowRestorationStateFalseForOtherArguments() {
        let result = VirgoAppLaunchBehavior.shouldClearWindowRestorationState(
            arguments: [LaunchArguments.resetState]
        )
        #expect(result == false)
    }

    // MARK: - ReopenPolicy.shouldAppKitHandleReopen

    @Test("shouldAppKitHandleReopen returns false when a visible window exists")
    func testReopenPolicyReturnsFalseWhenWindowVisible() {
        // Existing window: delegate activates it itself, so AppKit default is not needed.
        #expect(ReopenPolicy.shouldAppKitHandleReopen(hasVisibleWindows: true) == false)
    }

    @Test("shouldAppKitHandleReopen returns true when no visible window exists")
    func testReopenPolicyReturnsTrueWhenNoWindow() {
        // Regression guard: File > New is disabled, so the only recovery path after
        // the user closes the last window is for SwiftUI's WindowGroup to create one.
        // Returning false here would leave the app running with no usable window.
        #expect(ReopenPolicy.shouldAppKitHandleReopen(hasVisibleWindows: false) == true)
    }
}
