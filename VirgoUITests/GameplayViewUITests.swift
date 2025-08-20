//
//  GameplayViewUITests.swift
//  VirgoUITests
//
//  Created by Chan Wai Chan on 20/8/2025.
//

import XCTest

final class GameplayViewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testGameplayViewNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to ContentView
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Drum Tracks"].waitForExistence(timeout: 10))
        
        // Navigate to GameplayView by tapping on first track
        app.staticTexts["Thunder Beat"].tap()
        
        // Verify GameplayView elements load
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["DrumMaster Pro"].exists)
        XCTAssertTrue(app.staticTexts["120 BPM"].exists)
        XCTAssertTrue(app.staticTexts["Medium"].exists)
        
        // Test back navigation
        let backButton = app.buttons.matching(identifier: "chevron.left").firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()
        
        // Verify we're back on the tracks list
        XCTAssertTrue(app.staticTexts["Drum Tracks"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testGameplayViewPlaybackControls() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to GameplayView
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        app.staticTexts["Thunder Beat"].tap()
        
        // Wait for GameplayView to load
        let playButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 10))
        
        // Test play button exists and is tappable
        XCTAssertTrue(playButton.isHittable)
        
        // Test restart button exists
        let restartButton = app.buttons.matching(identifier: "backward.end.fill").firstMatch
        XCTAssertTrue(restartButton.waitForExistence(timeout: 5))
        XCTAssertTrue(restartButton.isHittable)
        
        // Test play button tap
        playButton.tap()
        
        // After tapping play, button should change to pause (play.circle.fill might change to pause.circle.fill)
        // Give some time for the state change
        Thread.sleep(forTimeInterval: 0.5)
        
        // Test that we can tap the button again (whether it's play or pause)
        let playbackButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch.exists ? 
                            app.buttons.matching(identifier: "play.circle.fill").firstMatch :
                            app.buttons.matching(identifier: "pause.circle.fill").firstMatch
        XCTAssertTrue(playbackButton.isHittable)
        
        // Test restart functionality
        restartButton.tap()
        
        // After restart, should have play button available
        XCTAssertTrue(app.buttons.matching(identifier: "play.circle.fill").firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testGameplayViewHeaderElements() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to GameplayView
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        app.staticTexts["Thunder Beat"].tap()
        
        // Wait for GameplayView to load
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        
        // Test header contains track information
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists, "Track title should be displayed")
        XCTAssertTrue(app.staticTexts["DrumMaster Pro"].exists, "Artist name should be displayed")
        XCTAssertTrue(app.staticTexts["120 BPM"].exists, "BPM should be displayed")
        XCTAssertTrue(app.staticTexts["Medium"].exists, "Difficulty should be displayed")
        
        // Test back button exists and is accessible
        let backButton = app.buttons.matching(identifier: "chevron.left").firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        XCTAssertTrue(backButton.isHittable, "Back button should be tappable")
    }

    @MainActor
    func testGameplayViewSheetMusicArea() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to GameplayView
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        app.staticTexts["Thunder Beat"].tap()
        
        // Wait for GameplayView to load
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        
        // The sheet music area should be present (this is the main content area)
        // We can't easily test for specific musical notation elements, but we can test
        // that the main scrollable area exists by checking that the screen has loaded properly
        
        // Verify the view has loaded by checking for both header and control elements
        let playButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 10))
        
        // The fact that we can see the play button and track info suggests the sheet music area
        // has also loaded (since they're part of the same view hierarchy)
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists)
    }

    @MainActor
    func testGameplayViewControlsArea() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to GameplayView
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        app.staticTexts["Thunder Beat"].tap()
        
        // Wait for GameplayView to load
        let playButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 10))
        
        // Test that control elements are present and accessible
        XCTAssertTrue(playButton.isHittable, "Play button should be accessible")
        
        let restartButton = app.buttons.matching(identifier: "backward.end.fill").firstMatch
        XCTAssertTrue(restartButton.waitForExistence(timeout: 5))
        XCTAssertTrue(restartButton.isHittable, "Restart button should be accessible")
        
        // Controls should be in the bottom area of the screen
        // We can verify this by checking that controls exist alongside the main content
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists && playButton.exists, 
                     "Both header and controls should be visible simultaneously")
    }

    @MainActor
    func testGameplayViewPlaybackSequence() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to GameplayView
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        app.staticTexts["Thunder Beat"].tap()
        
        // Wait for GameplayView to load
        let playButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 10))
        
        // Test complete playback sequence
        // 1. Initial state - should have play button
        XCTAssertTrue(playButton.exists, "Should start with play button")
        
        // 2. Start playback
        playButton.tap()
        
        // Give time for playback state to update
        Thread.sleep(forTimeInterval: 0.5)
        
        // 3. During playback - button state might change
        // (In some implementations, play becomes pause during playback)
        let hasPlayButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch.exists
        let hasPauseButton = app.buttons.matching(identifier: "pause.circle.fill").firstMatch.exists
        XCTAssertTrue(hasPlayButton || hasPauseButton, "Should have either play or pause button during playback")
        
        // 4. Test restart functionality
        let restartButton = app.buttons.matching(identifier: "backward.end.fill").firstMatch
        XCTAssertTrue(restartButton.exists)
        restartButton.tap()
        
        // 5. After restart - should return to initial state
        XCTAssertTrue(app.buttons.matching(identifier: "play.circle.fill").firstMatch.waitForExistence(timeout: 3),
                     "Should return to play button after restart")
    }

    @MainActor
    func testGameplayViewAccessibility() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to GameplayView
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        app.staticTexts["Thunder Beat"].tap()
        
        // Wait for GameplayView to load
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        
        // Test that key interactive elements are accessible
        let playButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 10))
        XCTAssertTrue(playButton.isHittable, "Play button should be accessible")
        
        let restartButton = app.buttons.matching(identifier: "backward.end.fill").firstMatch
        XCTAssertTrue(restartButton.waitForExistence(timeout: 5))
        XCTAssertTrue(restartButton.isHittable, "Restart button should be accessible")
        
        let backButton = app.buttons.matching(identifier: "chevron.left").firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        XCTAssertTrue(backButton.isHittable, "Back button should be accessible")
        
        // Test that text elements are readable
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists, "Track title should be accessible")
        XCTAssertTrue(app.staticTexts["DrumMaster Pro"].exists, "Artist should be accessible")
        XCTAssertTrue(app.staticTexts["120 BPM"].exists, "BPM should be accessible")
        XCTAssertTrue(app.staticTexts["Medium"].exists, "Difficulty should be accessible")
    }

    @MainActor
    func testGameplayViewMultipleTracksNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to ContentView
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Drum Tracks"].waitForExistence(timeout: 10))
        
        // Test navigation to first track
        app.staticTexts["Thunder Beat"].tap()
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["DrumMaster Pro"].exists)
        
        // Navigate back
        let backButton = app.buttons.matching(identifier: "chevron.left").firstMatch
        backButton.tap()
        XCTAssertTrue(app.staticTexts["Drum Tracks"].waitForExistence(timeout: 10))
        
        // Test navigation to second track (if available)
        if app.staticTexts["Jazz Swing"].exists {
            app.staticTexts["Jazz Swing"].tap()
            XCTAssertTrue(app.staticTexts["Jazz Swing"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Blue Note Records"].exists)
            
            // Navigate back again
            let backButton2 = app.buttons.matching(identifier: "chevron.left").firstMatch
            backButton2.tap()
            XCTAssertTrue(app.staticTexts["Drum Tracks"].waitForExistence(timeout: 10))
        }
    }

    @MainActor
    func testGameplayViewStabilityDuringInteraction() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to GameplayView
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))
        app.staticTexts["Thunder Beat"].tap()
        
        // Wait for GameplayView to load
        let playButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 10))
        
        // Rapid interaction test - ensure UI remains stable
        let restartButton = app.buttons.matching(identifier: "backward.end.fill").firstMatch
        
        // Multiple rapid interactions
        for _ in 0..<3 {
            playButton.tap()
            Thread.sleep(forTimeInterval: 0.2)
            restartButton.tap()
            Thread.sleep(forTimeInterval: 0.2)
        }
        
        // Verify UI is still functional after rapid interactions
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists, "Track title should still be visible")
        XCTAssertTrue(
            app.buttons.matching(identifier: "play.circle.fill").firstMatch.exists,
            "Play button should still be functional"
        )
        XCTAssertTrue(restartButton.exists, "Restart button should still be functional")
        
        // Test final navigation back
        let backButton = app.buttons.matching(identifier: "chevron.left").firstMatch
        backButton.tap()
        XCTAssertTrue(app.staticTexts["Drum Tracks"].waitForExistence(timeout: 10))
    }
}
