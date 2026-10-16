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
        installSystemDialogHandlers()
        dismissSetupAssistantIfPresent()

        // Add custom launch argument to distinguish UI tests from unit tests
        // ContentView.isUITesting checks for this argument
        app = XCUIApplication()
        app.launchArguments.append("-UITesting")
        app.launchArguments.append("-ResetState")
        app.launch()
        activateLaunchedAppWindow(in: app)
        dismissSetupAssistantIfPresent(returningTo: app)
    }

    override func tearDownWithError() throws {
        // Safely terminate app only if it was successfully initialized in setUpWithError
        app?.terminate()
    }

    @discardableResult
    private func requirePlaybackButton(timeout: TimeInterval = 3) throws -> XCUIElement {
        try requireGameplayPlayPauseControl(in: app, timeout: timeout)
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
    func testGameplayOpensImportedSoukyuuFixture() throws {
        try openGameplay(
            in: app,
            songTitle: "蒼穹への翔歌",
            artist: "hapadona feat. Suno AI",
            difficulty: "Easy",
            timeout: 15
        )
    }

    @MainActor
    func testGameplayDoesNotRenderTabShellSimultaneously() throws {
        try openGameplay(in: app)

        #if os(macOS)
        XCTAssertEqual(
            app.windows.containing(.any, identifier: "gameplayRoot").count,
            1,
            "Gameplay should be mounted in exactly one Virgo window on macOS"
        )
        #endif
        XCTAssertTrue(
            waitForFirstExisting([
                app.buttons["gameplayMainPlayPauseButton"],
                app.buttons["gameplayHeaderPlayPauseButton"],
                app.buttons["gameplayPlayPauseButton"]
            ], timeout: 3) != nil,
            "Gameplay controls should be present after chart selection"
        )
        XCTAssertFalse(
            app.otherElements["appTabShell"].exists,
            "Tab shell should not remain mounted while gameplay is active"
        )
        XCTAssertFalse(
            app.tabBars.firstMatch.exists,
            "Tab bar should not remain visible while gameplay is active"
        )
    }

    @MainActor
    func testGameplayViewPlaybackControls() throws {
        try openGameplay(in: app)
        let playButton = try requirePlaybackButton()

        // Test play button exists and is tappable
        XCTAssertTrue(playButton.isHittable)

        // Test restart button exists
        let restartButton = try requireGameplayRestartControl(in: app)
        XCTAssertTrue(restartButton.isHittable)

        // Test play button tap
        playButton.tap()

        let playbackButton = try requirePlaybackButton(timeout: 2)

        // Test that we can tap the button again (whether it's play or pause)
        XCTAssertTrue(playbackButton.isHittable)

        // Test restart functionality
        restartButton.tap()

        // After restart, should have play button available
        try requirePlaybackButton(timeout: 3)
    }
}
