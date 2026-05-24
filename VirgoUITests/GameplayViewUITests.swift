//
//  GameplayViewUITests.swift
//  VirgoUITests
//
//  Created by Chan Wai Chan on 20/8/2025.
//

import XCTest

final class GameplayViewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Add custom launch argument to distinguish UI tests from unit tests
        // ContentView.isUITesting checks for this argument
        app = XCUIApplication()
        app.launchArguments.append("-UITesting")
        app.launchArguments.append("-ResetState")
        app.launch()
    }

    override func tearDownWithError() throws {
        // Safely terminate app only if it was successfully initialized in setUpWithError
        app?.terminate()
    }

    @discardableResult
    private func requirePlaybackButton(timeout: TimeInterval = 3) throws -> XCUIElement {
        guard let button = waitForFirstExisting([
            app.buttons["Play"],
            app.buttons["Pause"]
        ], timeout: timeout) else {
            XCTFail("Expected Play or Pause button to exist")
            throw UITestFailure.elementNotFound("Play or Pause")
        }
        return button
    }

    @MainActor
    func testGameplayViewNavigation() throws {
        try openGameplay(in: app)

        // Test back navigation
        try tapBackFromGameplay(in: app)

        // Verify we're back on the songs list
        XCTAssertTrue(app.staticTexts["Songs"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testGameplayViewPlaybackControls() throws {
        try openGameplay(in: app)
        let playButton = try requireControl(named: "Play", in: app)

        // Test play button exists and is tappable
        XCTAssertTrue(playButton.isHittable)

        // Test restart button exists
        let restartButton = try requireControl(named: "Restart", in: app)
        XCTAssertTrue(restartButton.isHittable)

        // Test play button tap
        playButton.tap()

        let playbackButton = try requirePlaybackButton(timeout: 2)

        // Test that we can tap the button again (whether it's play or pause)
        XCTAssertTrue(playbackButton.isHittable)

        // Test restart functionality
        restartButton.tap()

        // After restart, should have play button available
        try requireControl(named: "Play", in: app, timeout: 3)
    }

    @MainActor
    func testGameplayViewHeaderElements() throws {
        try openGameplay(in: app)

        // Test header contains track information
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists, "Track title should be displayed")
        XCTAssertTrue(app.staticTexts["Rock Masters"].exists, "Artist name should be displayed")

        // Test back button exists and is accessible
        let backButton = try requireControl(named: "Go back", in: app)
        XCTAssertTrue(backButton.isHittable, "Back button should be tappable")
    }

    @MainActor
    func testGameplayViewSheetMusicArea() throws {
        try openGameplay(in: app)

        // The sheet music area should be present (this is the main content area)
        // We can't easily test for specific musical notation elements, but we can test
        // that the main scrollable area exists by checking that the screen has loaded properly

        // Verify the view has loaded by checking for both header and control elements
        try requireControl(named: "Play", in: app)

        // The fact that we can see the play button and track info suggests the sheet music area
        // has also loaded (since they're part of the same view hierarchy)
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists)
    }

    @MainActor
    func testGameplayViewControlsArea() throws {
        try openGameplay(in: app)
        let playButton = try requireControl(named: "Play", in: app)

        // Test that control elements are present and accessible
        XCTAssertTrue(playButton.isHittable, "Play button should be accessible")

        let restartButton = try requireControl(named: "Restart", in: app)
        XCTAssertTrue(restartButton.isHittable, "Restart button should be accessible")

        // Controls should be in the bottom area of the screen
        // We can verify this by checking that controls exist alongside the main content
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists && playButton.exists, 
                     "Both header and controls should be visible simultaneously")
    }

    @MainActor
    func testGameplayViewPlaybackSequence() throws {
        try openGameplay(in: app)
        let playButton = try requireControl(named: "Play", in: app)

        // Test complete playback sequence
        // 1. Initial state - should have play button
        XCTAssertTrue(playButton.exists, "Should start with play button")

        // 2. Start playback
        playButton.tap()

        // 3. During playback - button state might change.
        try requirePlaybackButton(timeout: 2)

        // 4. Test restart functionality
        let restartButton = try requireControl(named: "Restart", in: app)
        restartButton.tap()

        // 5. After restart - should return to initial state
        try requireControl(named: "Play", in: app, timeout: 3)
    }

    @MainActor
    func testGameplayViewAccessibility() throws {
        try openGameplay(in: app)

        // Test that key interactive elements are accessible
        let playButton = try requireControl(named: "Play", in: app)
        XCTAssertTrue(playButton.isHittable, "Play button should be accessible")

        let restartButton = try requireControl(named: "Restart", in: app)
        XCTAssertTrue(restartButton.isHittable, "Restart button should be accessible")

        let backButton = try requireControl(named: "Go back", in: app)
        XCTAssertTrue(backButton.isHittable, "Back button should be accessible")

        // Test that text elements are readable
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists, "Track title should be accessible")
        XCTAssertTrue(app.staticTexts["Rock Masters"].exists, "Artist should be accessible")
    }

    @MainActor
    func testGameplayViewMultipleTracksNavigation() throws {
        // Test navigation to first track
        try openGameplay(in: app)

        // Navigate back
        try tapBackFromGameplay(in: app)
        XCTAssertTrue(app.staticTexts["Songs"].waitForExistence(timeout: 10))

        // Test navigation to second track.
        try openGameplay(in: app, songTitle: "Jazz Groove", artist: "Smooth Collective")
        XCTAssertTrue(app.staticTexts["Jazz Groove"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Smooth Collective"].waitForExistence(timeout: 10))

        // Navigate back again
        try tapBackFromGameplay(in: app)
        XCTAssertTrue(app.staticTexts["Songs"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testGameplayViewStabilityDuringInteraction() throws {
        try openGameplay(in: app)

        // Rapid interaction test - ensure UI remains stable
        let restartButton = try requireControl(named: "Restart", in: app)

        // Multiple rapid interactions
        for _ in 0..<3 {
            try requirePlaybackButton(timeout: 1).tap()
            // Wait for button to be responsive after tap
            XCTAssertTrue(restartButton.waitForExistence(timeout: 1.0), "Restart button should remain available")
            restartButton.tap()
            // Wait for button to be responsive after tap
            try requireControl(named: "Play", in: app, timeout: 1)
        }

        // Verify UI is still functional after rapid interactions
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists, "Track title should still be visible")
        XCTAssertTrue(app.buttons["Play"].exists, "Play button should still be functional")
        XCTAssertTrue(restartButton.exists, "Restart button should still be functional")

        // Test final navigation back
        try tapBackFromGameplay(in: app)
        XCTAssertTrue(app.staticTexts["Songs"].waitForExistence(timeout: 10))
    }
}
