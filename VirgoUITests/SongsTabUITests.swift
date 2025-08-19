//
//  SongsTabUITests.swift
//  VirgoUITests
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import XCTest

final class SongsTabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - Songs Tab Tests
    
    @MainActor
    func testSongsTabNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Navigate to Songs tab via Content View (which shows SongsTabView)
        XCTAssertTrue(app.staticTexts["Songs"].waitForExistence(timeout: 10))
        
        // Verify sub-tab picker exists
        let downloadedTab = app.buttons["Downloaded"]
        let serverTab = app.buttons["Server"]
        
        XCTAssertTrue(downloadedTab.waitForExistence(timeout: 5))
        XCTAssertTrue(serverTab.exists)
        
        // Test switching between sub-tabs
        serverTab.tap()
        XCTAssertTrue(serverTab.isSelected)
        
        downloadedTab.tap()
        XCTAssertTrue(downloadedTab.isSelected)
    }
    
    @MainActor
    func testDownloadedSongsEmpty() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Ensure we're on Downloaded tab (default)
        let downloadedTab = app.buttons["Downloaded"]
        XCTAssertTrue(downloadedTab.waitForExistence(timeout: 5))
        if !downloadedTab.isSelected {
            downloadedTab.tap()
        }
        
        // Verify empty state is shown
        XCTAssertTrue(app.images["arrow.down.circle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Downloaded Songs"].exists)
        XCTAssertTrue(app.staticTexts["Download songs from the Server tab to see them here"].exists)
    }
    
    @MainActor
    func testDownloadedSongsWithData() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Ensure we're on Downloaded tab
        let downloadedTab = app.buttons["Downloaded"]
        XCTAssertTrue(downloadedTab.waitForExistence(timeout: 5))
        if !downloadedTab.isSelected {
            downloadedTab.tap()
        }
        
        // Check if there are downloaded songs (DTX Import genre)
        // This test will pass if there are downloaded songs, or skip verification if empty
        let songCount = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'songs available'")).firstMatch
        if songCount.waitForExistence(timeout: 5) {
            let countText = songCount.label
            if !countText.hasPrefix("0 ") {
                // Verify downloaded songs list elements exist
                XCTAssertTrue(
                    app.buttons.matching(identifier: "play.circle.fill").firstMatch.waitForExistence(timeout: 5)
                )
                XCTAssertTrue(
                    app.buttons.matching(identifier: "bookmark").firstMatch.waitForExistence(timeout: 5) ||
                    app.buttons.matching(identifier: "bookmark.fill").firstMatch.exists
                )
            }
        }
    }
    
    @MainActor
    func testDownloadedSongsPlayback() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Ensure we're on Downloaded tab
        let downloadedTab = app.buttons["Downloaded"]
        XCTAssertTrue(downloadedTab.waitForExistence(timeout: 5))
        if !downloadedTab.isSelected {
            downloadedTab.tap()
        }
        
        // Find first play button if songs exist
        let playButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        if playButton.waitForExistence(timeout: 5) {
            // Test play functionality
            playButton.tap()
            
            // Verify play button changes to pause (may take a moment for audio to start)
            let pauseButton = app.buttons.matching(identifier: "pause.circle.fill").firstMatch
            XCTAssertTrue(pauseButton.waitForExistence(timeout: 3))
            
            // Test pause functionality
            pauseButton.tap()
            XCTAssertTrue(playButton.waitForExistence(timeout: 3))
        }
    }
    
    @MainActor
    func testDownloadedSongExpansion() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Ensure we're on Downloaded tab
        let downloadedTab = app.buttons["Downloaded"]
        XCTAssertTrue(downloadedTab.waitForExistence(timeout: 5))
        if !downloadedTab.isSelected {
            downloadedTab.tap()
        }
        
        // Find first chart count indicator if songs exist
        let chartIndicator = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'charts'")).firstMatch
        if chartIndicator.waitForExistence(timeout: 5) {
            // Tap to expand
            chartIndicator.tap()
            
            // Verify expansion content (difficulty badges should appear)
            let difficultyButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'Easy' OR label CONTAINS 'Medium' OR label CONTAINS 'Hard'")
            ).firstMatch
            XCTAssertTrue(difficultyButton.waitForExistence(timeout: 3))
            
            // Tap again to collapse
            chartIndicator.tap()
            
            // Wait for collapse animation
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
    
    @MainActor
    func testDownloadedSongDeletion() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Ensure we're on Downloaded tab
        let downloadedTab = app.buttons["Downloaded"]
        XCTAssertTrue(downloadedTab.waitForExistence(timeout: 5))
        if !downloadedTab.isSelected {
            downloadedTab.tap()
        }
        
        // Find delete button if songs exist
        let deleteButton = app.buttons["Delete"]
        if deleteButton.waitForExistence(timeout: 5) {
            // Count songs before deletion
            let songCountBefore = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'songs available'")
            ).firstMatch
            let beforeText = songCountBefore.label
            
            // Tap delete button
            deleteButton.tap()
            
            // Verify deletion progress indicator appears
            let deletingText = app.staticTexts["Deleting..."]
            if deletingText.waitForExistence(timeout: 2) {
                // Wait for deletion to complete
                XCTAssertTrue(deletingText.waitForNonExistence(timeout: 10))
            }
            
            // Verify song count decreased or empty state appears
            Thread.sleep(forTimeInterval: 1)
            let songCountAfter = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'songs available'")
            ).firstMatch
            if songCountAfter.exists {
                let afterText = songCountAfter.label
                XCTAssertNotEqual(beforeText, afterText, "Song count should change after deletion")
            } else {
                // Empty state should appear if all songs deleted
                XCTAssertTrue(app.staticTexts["No Downloaded Songs"].waitForExistence(timeout: 5))
            }
        }
    }
    
}
