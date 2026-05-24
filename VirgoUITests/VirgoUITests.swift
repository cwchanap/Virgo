//
//  VirgoUITests.swift
//  VirgoUITests
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import XCTest

final class VirgoUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // Add custom launch argument to distinguish UI tests from unit tests
        // ContentView.isUITesting checks for this argument
        app = XCUIApplication()
        app.launchArguments.append("-UITesting")
        app.launchArguments.append("-ResetState")

        // In UI tests it's important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testMainMenuNavigation() throws {
        app.launch()

        // Verify main menu elements are present
        XCTAssertTrue(app.staticTexts["VIRGO"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Music App"].exists)
        XCTAssertTrue(app.buttons["START"].exists)

        // Tap start button to navigate to content view
        try tapControl(named: "START", in: app)

        // Wait for navigation to complete and verify we're in the songs view
        XCTAssertTrue(app.staticTexts["Songs"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["searchField"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDrumTracksListDisplay() throws {
        app.launch()

        // Navigate to songs
        try openSongsView(in: app)

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
        try requireControl(named: "Play", in: app, timeout: 5)
    }

    @MainActor
    func testSearchFunctionality() throws {
        app.launch()
        try openSongsView(in: app)

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
        let thunderBeatVisible = app.staticTexts["Thunder Beat"].waitForExistence(timeout: 5)
        let jazzGrooveVisible = app.staticTexts["Jazz Groove"].waitForExistence(timeout: 5)
        XCTAssertTrue(thunderBeatVisible && jazzGrooveVisible, "All tracks should be visible after clearing search")

        // Test search by artist - search for "Smooth" which exists in Jazz Groove
        searchField.tap()
        searchField.typeText("Smooth")

        // Wait for search to filter results
        XCTAssertTrue(app.staticTexts["Jazz Groove"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testGameplayViewNavigation() throws {
        app.launch()
        try openGameplay(in: app)

        // Verify we're in gameplay view - check for unique gameplay elements
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists) // Track title in header
        XCTAssertTrue(app.staticTexts["Rock Masters"].exists) // Artist name

        // Verify playback controls exist
        try requireControl(named: "Play", in: app)
        try requireControl(named: "Restart", in: app)

        // Test back navigation
        try tapBackFromGameplay(in: app)

        // Wait for navigation back to complete by checking for songs list
        XCTAssertTrue(app.staticTexts["Songs"].waitForExistence(timeout: 10))

        // Verify we're back on the tracks list by checking for search field
        XCTAssertTrue(app.textFields["searchField"].exists)
    }

    @MainActor
    func testTabNavigation() throws {
        app.launch()
        try openSongsView(in: app)

        // Test tab navigation
        try requireControl(named: "Songs", in: app)
        try requireControl(named: "Metronome", in: app)
        try requireControl(named: "Library", in: app)
        try requireControl(named: "Settings", in: app)
        try requireControl(named: "Profile", in: app)

        // Test switching tabs
        try tapControl(named: "Metronome", in: app)
        XCTAssertTrue(app.staticTexts["Metronome"].exists)

        try tapControl(named: "Library", in: app)
        XCTAssertTrue(app.staticTexts["Downloaded Songs"].exists)

        try tapControl(named: "Settings", in: app)
        XCTAssertTrue(app.staticTexts["Settings"].exists)

        try tapControl(named: "Profile", in: app)
        XCTAssertTrue(app.staticTexts["Profile"].exists)

        // Return to songs tab
        try tapControl(named: "Songs", in: app)
        XCTAssertTrue(app.staticTexts["Songs"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            app.terminate()
        }
    }
}
