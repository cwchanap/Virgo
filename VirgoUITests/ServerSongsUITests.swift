//
//  ServerSongsUITests.swift
//  VirgoUITests
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import XCTest

final class ServerSongsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testServerSongsTab() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Switch to Server tab
        let serverTab = app.buttons["Server"]
        XCTAssertTrue(serverTab.waitForExistence(timeout: 5))
        serverTab.tap()
        XCTAssertTrue(serverTab.isSelected)
        
        // Verify refresh button exists
        let refreshButton = app.buttons["arrow.clockwise"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5))
        
        // Test refresh functionality
        refreshButton.tap()
        
        // Should see either loading state or server songs
        let loadingText = app.staticTexts["Loading server songs..."]
        let emptyStateIcon = app.images["cloud"]
        let emptyStateText = app.staticTexts["No Server Songs"]
        
        // One of these should appear
        XCTAssertTrue(
            loadingText.waitForExistence(timeout: 3) ||
            emptyStateIcon.waitForExistence(timeout: 3) ||
            emptyStateText.waitForExistence(timeout: 3)
        )
    }
    
    @MainActor
    func testServerSongsEmptyState() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Switch to Server tab
        let serverTab = app.buttons["Server"]
        XCTAssertTrue(serverTab.waitForExistence(timeout: 5))
        serverTab.tap()
        
        // Wait for loading to complete and verify empty state (assuming no server connection)
        let emptyStateIcon = app.images["cloud"]
        let emptyStateText = app.staticTexts["No Server Songs"]
        let instructionText = app.staticTexts["Tap the refresh button to load songs from the server"]
        
        // Wait a bit for network request to complete/timeout
        Thread.sleep(forTimeInterval: 2)
        
        if emptyStateIcon.waitForExistence(timeout: 5) {
            XCTAssertTrue(emptyStateText.exists)
            XCTAssertTrue(instructionText.exists)
        }
    }
    
    @MainActor
    func testServerSongsRefreshButton() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Switch to Server tab
        let serverTab = app.buttons["Server"]
        XCTAssertTrue(serverTab.waitForExistence(timeout: 5))
        serverTab.tap()
        
        let refreshButton = app.buttons["arrow.clockwise"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5))
        
        // Test refresh button tap
        refreshButton.tap()
        
        // Verify button becomes disabled during refresh
        XCTAssertFalse(refreshButton.isEnabled)
        
        // Wait for refresh to complete (button should become enabled again)
        let enabledPredicate = NSPredicate(format: "enabled == true")
        let buttonEnabledExpectation = expectation(for: enabledPredicate, evaluatedWith: refreshButton)
        wait(for: [buttonEnabledExpectation], timeout: 10)
    }
    
    @MainActor
    func testSongsTabSearchFunctionality() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Test search in Downloaded tab
        let downloadedTab = app.buttons["Downloaded"]
        XCTAssertTrue(downloadedTab.waitForExistence(timeout: 5))
        if !downloadedTab.isSelected {
            downloadedTab.tap()
        }
        
        let searchField = app.textFields["searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        // Test search functionality
        searchField.tap()
        searchField.typeText("test")
        
        // Verify clear button appears
        let clearButton = app.buttons["clearSearchButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 3))
        
        // Test clear functionality
        clearButton.tap()
        XCTAssertEqual(searchField.value as? String ?? "", "")
        
        // Test search in Server tab
        let serverTab = app.buttons["Server"]
        serverTab.tap()
        
        // Search should work in server tab too
        searchField.tap()
        searchField.typeText("server")
        XCTAssertTrue(clearButton.waitForExistence(timeout: 3))
        
        clearButton.tap()
        XCTAssertEqual(searchField.value as? String ?? "", "")
    }
    
    @MainActor
    func testSongsTabSongCounter() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["START"].tap()
        
        // Check Downloaded tab song count
        let downloadedTab = app.buttons["Downloaded"]
        XCTAssertTrue(downloadedTab.waitForExistence(timeout: 5))
        if !downloadedTab.isSelected {
            downloadedTab.tap()
        }
        
        let songCountText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'songs available'")).firstMatch
        XCTAssertTrue(songCountText.waitForExistence(timeout: 5))
        
        // Switch to Server tab and check count updates
        let serverTab = app.buttons["Server"]
        serverTab.tap()
        
        // Song count should update when switching tabs
        XCTAssertTrue(songCountText.waitForExistence(timeout: 5))
        let serverCountText = songCountText.label
        
        // Switch back to Downloaded tab
        downloadedTab.tap()
        let downloadedCountText = songCountText.label
        
        // Counts might be different between tabs
        print("Downloaded count: \(downloadedCountText), Server count: \(serverCountText)")
    }
}
