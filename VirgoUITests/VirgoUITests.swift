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
        XCTAssertTrue(app.staticTexts["VIRGO"].exists)
        XCTAssertTrue(app.staticTexts["Music App"].exists)
        XCTAssertTrue(app.buttons["START"].exists)
        
        // Tap start button to navigate to content view
        app.buttons["START"].tap()
        
        // Verify we're now in the drum tracks view
        XCTAssertTrue(app.staticTexts["Drum Tracks"].exists)
        XCTAssertTrue(app.searchFields["Search songs or artists..."].exists)
    }
    
    @MainActor
    func testDrumTracksListDisplay() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to drum tracks
        app.buttons["START"].tap()
        
        // Wait for tracks to load
        let tracksListPredicate = NSPredicate(format: "exists == true")
        expectation(for: tracksListPredicate, evaluatedWith: app.staticTexts["Thunder Beat"], handler: nil)
        waitForExpectations(timeout: 3, handler: nil)
        
        // Verify sample tracks are displayed
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists)
        XCTAssertTrue(app.staticTexts["DrumMaster Pro"].exists)
        XCTAssertTrue(app.staticTexts["120 BPM"].exists)
        XCTAssertTrue(app.staticTexts["Medium"].exists)
        
        // Verify at least one play button exists
        XCTAssertTrue(app.buttons.matching(identifier: "play.circle.fill").firstMatch.exists)
    }
    
    @MainActor
    func testSearchFunctionality() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Wait for tracks to load
        sleep(1)
        
        let searchField = app.searchFields["Search songs or artists..."]
        XCTAssertTrue(searchField.exists)
        
        // Test search by title
        searchField.tap()
        searchField.typeText("Thunder")
        
        // Should show Thunder Beat track
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists)
        
        // Clear search
        if app.buttons["Clear text"].exists {
            app.buttons["Clear text"].tap()
        } else {
            searchField.clearAndEnterText("")
        }
        
        // Test search by artist
        searchField.typeText("Jazz")
        
        // Should show tracks containing "Jazz"
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'jazz'")).firstMatch.exists)
    }
    
    @MainActor
    func testGameplayViewNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Wait for tracks to load
        sleep(1)
        
        // Tap on first track to navigate to gameplay
        app.staticTexts["Thunder Beat"].tap()
        
        // Verify we're in gameplay view
        XCTAssertTrue(app.staticTexts["Thunder Beat"].exists) // Track title in header
        XCTAssertTrue(app.staticTexts["DrumMaster Pro"].exists) // Artist name
        XCTAssertTrue(app.staticTexts["120 BPM"].exists)
        XCTAssertTrue(app.staticTexts["Medium"].exists)
        
        // Verify playback controls exist
        XCTAssertTrue(app.buttons.matching(identifier: "play.circle.fill").firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(identifier: "backward.end.fill").firstMatch.exists)
        
        // Test back navigation
        app.buttons.matching(identifier: "chevron.left").firstMatch.tap()
        
        // Should return to drum tracks list
        XCTAssertTrue(app.staticTexts["Drum Tracks"].exists)
    }
    
    @MainActor
    func testTabNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Test tab navigation
        XCTAssertTrue(app.tabBars.buttons["Drums"].exists)
        XCTAssertTrue(app.tabBars.buttons["Practice"].exists)
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
        
        // Test switching tabs
        app.tabBars.buttons["Practice"].tap()
        XCTAssertTrue(app.staticTexts["Practice Tab"].exists)
        
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Library Tab"].exists)
        
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Profile Tab"].exists)
        
        // Return to drums tab
        app.tabBars.buttons["Drums"].tap()
        XCTAssertTrue(app.staticTexts["Drum Tracks"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

// MARK: - Helper Extensions
extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        guard let stringValue = self.value as? String else {
            XCTFail("Tried to clear and enter text into a non-string value")
            return
        }
        
        self.tap()
        
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
        self.typeText(text)
    }
}
