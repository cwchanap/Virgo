//
//  ServerSongsUITests.swift
//  VirgoUITests
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import XCTest

final class ServerSongsUITests: XCTestCase {
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
        app?.terminate()
    }

    private func requireRefreshButton(timeout: TimeInterval = 5) throws -> XCUIElement {
        guard let button = waitForFirstExisting([
            app.buttons["refreshServerSongsButton"],
            app.buttons["Refresh server songs"],
            app.buttons["arrow.clockwise"]
        ], timeout: timeout) else {
            XCTFail("Refresh button should exist")
            throw UITestFailure.elementNotFound("Refresh server songs")
        }
        return button
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let enabledPredicate = NSPredicate(format: "enabled == true")
        let enabledExpectation = expectation(for: enabledPredicate, evaluatedWith: element)
        wait(for: [enabledExpectation], timeout: timeout)
    }

    @MainActor
    func testServerSongsTab() throws {
        try openSongsView(in: app)
        
        // Switch to Server tab
        let serverTab = try requireControl(named: "Server", in: app, timeout: 5)
        if !serverTab.isSelected {
            serverTab.tap()
        }
        XCTAssertTrue(serverTab.isSelected)
        
        // Verify refresh button exists
        let refreshButton = try requireRefreshButton()
        waitForEnabled(refreshButton)
        
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
        try openSongsView(in: app)
        
        // Switch to Server tab
        try tapControl(named: "Server", in: app, timeout: 5)
        
        // Wait for loading to complete and verify empty state (assuming no server connection)
        let emptyStateText = app.staticTexts["No Server Songs"]
        let instructionText = app.staticTexts["Tap the refresh button to load songs from the server"]
        
        // Wait for either empty state or songs to appear after network request
        let emptyStateAppeared = emptyStateText.waitForExistence(timeout: 8)
        let songsAppeared = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'songs available'"))
            .firstMatch.waitForExistence(timeout: 8)
        
        XCTAssertTrue(
            emptyStateAppeared || songsAppeared,
            "Either empty state or songs should appear after network request"
        )
        
        if emptyStateAppeared {
            XCTAssertTrue(emptyStateText.exists, "Empty state text should be visible")
            XCTAssertTrue(instructionText.exists, "Instruction text should be visible")
        }
    }
    
    @MainActor
    func testServerSongsRefreshButton() throws {
        try openSongsView(in: app)
        
        // Switch to Server tab
        try tapControl(named: "Server", in: app, timeout: 5)
        
        let refreshButton = try requireRefreshButton()
        waitForEnabled(refreshButton)
        
        // Test refresh button tap
        refreshButton.tap()
        
        // Refresh can finish quickly when the local server is unavailable, so wait for the final enabled state.
        waitForEnabled(refreshButton)
    }
    
    @MainActor
    func testSongsTabSearchFunctionality() throws {
        try openSongsView(in: app)
        
        // Test search in Downloaded tab
        XCTAssertTrue(switchToDownloadedTab(app: app))
        
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
        XCTAssertTrue(clearButton.waitForNonExistence(timeout: 3))
        
        // Test search in Server tab
        try tapControl(named: "Server", in: app, timeout: 5)
        
        // Search should work in server tab too
        searchField.tap()
        searchField.typeText("server")
        XCTAssertTrue(clearButton.waitForExistence(timeout: 3))
        
        clearButton.tap()
        XCTAssertTrue(clearButton.waitForNonExistence(timeout: 3))
    }
    
    @MainActor
    func testSongsTabSongCounter() throws {
        try openSongsView(in: app)
        
        // Check Downloaded tab song count
        let downloadedTab = try requireControl(named: "Downloaded", in: app, timeout: 5)
        if !downloadedTab.isSelected {
            downloadedTab.tap()
        }
        
        let songCountText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'songs available'")).firstMatch
        XCTAssertTrue(songCountText.waitForExistence(timeout: 5))
        
        // Switch to Server tab and check count updates
        let serverTab = try requireControl(named: "Server", in: app, timeout: 5)
        serverTab.tap()
        
        // Song count should update when switching tabs
        XCTAssertTrue(songCountText.waitForExistence(timeout: 5))
        let serverCountText = songCountText.label
        
        // Switch back to Downloaded tab
        downloadedTab.tap()
        let downloadedCountText = songCountText.label
        
        // Assert that counts are tracked separately between tabs
        XCTAssertFalse(downloadedCountText.isEmpty, "Downloaded count should be displayed")
        XCTAssertFalse(serverCountText.isEmpty, "Server count should be displayed")
    }
}
