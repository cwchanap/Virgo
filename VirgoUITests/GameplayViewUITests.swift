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

        // 1. Tap Play on the hittable play/pause control.
        let playButton = try requirePlaybackButton()
        XCTAssertTrue(playButton.isHittable, "The play/pause control should be hittable while the session is paused")
        playButton.tap()

        // 2. Verify the session is playing: the control exposes its Pause label.
        try requireControl(named: "Pause", in: app, timeout: 3)

        // 3. Restart the PLAYING session: restartPlayback re-starts when
        // playing, so the control must expose its Pause label again — a
        // restart of an already-paused session is a control-state no-op
        // and proves nothing.
        let restartButton = try requireGameplayRestartControl(in: app)
        XCTAssertTrue(restartButton.isHittable)
        restartButton.tap()
        let resumedControl = try requireControl(named: "Pause", in: app, timeout: 3)
        XCTAssertTrue(resumedControl.isHittable, "Play should restart and keep playing after restart")

        // 4. Pause the restarted session and verify the paused state.
        try tapControl(named: "Pause", in: app, timeout: 3)
        let pausedControl = try requireControl(named: "Play", in: app, timeout: 3)
        XCTAssertTrue(pausedControl.isHittable, "The play/pause control should remain hittable after pausing")
    }
}
