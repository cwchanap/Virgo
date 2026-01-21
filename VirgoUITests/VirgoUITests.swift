//
//  VirgoUITests.swift
//  VirgoUITests
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import XCTest

final class VirgoUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testMainMenuNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify main menu elements are present
        XCTAssertTrue(app.staticTexts["VIRGO"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Music App"].exists)
        XCTAssertTrue(app.buttons["START"].exists)

        // Tap start button to navigate to content view
        app.buttons["START"].tap()

        // Wait for navigation to complete and verify we're in the songs view
        XCTAssertTrue(app.staticTexts["Songs"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["searchField"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDrumTracksListDisplay() throws {
        let app = XCUIApplication()
        app.launch()

        // Navigate to songs
        app.buttons["START"].tap()

        // Wait for tracks to load with longer timeout
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))

        // Verify sample tracks are displayed
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists)
        XCTAssertTrue(app.staticTexts["Rock Masters"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'BPM'"))
                .firstMatch
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Medium"].waitForExistence(timeout: 5))

        // Verify at least one play button exists
        XCTAssertTrue(app.buttons.matching(identifier: "play.circle.fill").firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSearchFunctionality() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()

        // Wait for tracks to load
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))

        let searchField = app.textFields["searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        // Test search by title
        searchField.tap()
        searchField.typeText("Thunder")

        // Wait for search results to update - Thunder Beat should still be visible
        let thunderBeatAfterSearch = app.staticTexts["Thunder Beat"]
        XCTAssertTrue(thunderBeatAfterSearch.waitForExistence(timeout: 5))

        // Clear search - try different approaches
        if app.buttons["Clear text"].exists {
            app.buttons["Clear text"].tap()
        } else {
            // Use the clear button with accessibility identifier
            let clearButton = app.buttons["clearSearchButton"]
            if clearButton.waitForExistence(timeout: 2) {
                clearButton.tap()
            } else {
                searchField.clearAndEnterText("")
            }
        }

        // Wait for all tracks to be visible again after clearing search
        let allTracksVisible = expectation(description: "All tracks visible after clear")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if app.staticTexts["Thunder Beat"].exists &&
                app.staticTexts["Jazz Groove"].exists {
                allTracksVisible.fulfill()
            }
        }
        wait(for: [allTracksVisible], timeout: 5)

        // Test search by artist - search for "Smooth" which exists in Jazz Groove
        searchField.typeText("Smooth")

        // Wait for search to filter results
        XCTAssertTrue(app.staticTexts["Jazz Groove"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testGameplayViewNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()

        // Wait for tracks to load
        XCTAssertTrue(app.staticTexts["Thunder Beat"].waitForExistence(timeout: 10))

        // Tap on first track to navigate to gameplay
        app.staticTexts["Thunder Beat"].tap()

        // Wait for gameplay view to load by checking for unique gameplay elements
        let gameplayLoadedPredicate = NSPredicate(format: "exists == true")
        let playButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        let backButton = app.buttons.matching(identifier: "chevron.left").firstMatch

        let gameplayLoaded = expectation(for: gameplayLoadedPredicate,
                                         evaluatedWith: playButton,
                                         handler: nil)
        wait(for: [gameplayLoaded], timeout: 10)

        // Verify we're in gameplay view - check for unique gameplay elements
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists) // Track title in header
        XCTAssertTrue(app.staticTexts["Rock Masters"].exists) // Artist name

        // Verify playback controls exist
        XCTAssertTrue(playButton.exists)
        XCTAssertTrue(app.buttons.matching(identifier: "backward.end.fill").firstMatch.exists)

        // Test back navigation
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()

        // Wait for navigation back to complete by checking for songs list
        XCTAssertTrue(app.staticTexts["Songs"].waitForExistence(timeout: 10))

        // Verify we're back on the tracks list by checking for search field
        XCTAssertTrue(app.textFields["searchField"].exists)
    }

    @MainActor
    func testTabNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()

        // Test tab navigation
        XCTAssertTrue(app.tabBars.buttons["Songs"].exists)
        XCTAssertTrue(app.tabBars.buttons["Metronome"].exists)
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)

        // Test switching tabs
        app.tabBars.buttons["Metronome"].tap()
        XCTAssertTrue(app.staticTexts["Metronome"].exists)

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Downloaded Songs"].exists)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].exists)

        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Profile"].exists)

        // Return to songs tab
        app.tabBars.buttons["Songs"].tap()
        XCTAssertTrue(app.staticTexts["Songs"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
