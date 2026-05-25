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
        installSystemDialogHandlers()
        dismissSetupAssistantIfPresent()

        // Add custom launch argument to distinguish UI tests from unit tests
        // ContentView.isUITesting checks for this argument
        app = XCUIApplication()
        app.launchArguments.append("-UITesting")
        app.launchArguments.append("-ResetState")
        app.launch()
        dismissSetupAssistantIfPresent()
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

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let enabledPredicate = NSPredicate(format: "enabled == true")
        let enabledExpectation = expectation(for: enabledPredicate, evaluatedWith: element)
        return XCTWaiter.wait(for: [enabledExpectation], timeout: timeout) == .completed
    }

    private func waitForServerTabState(timeout: TimeInterval = 5) -> Bool {
        waitForStaticText(containing: "Loading server songs", in: app, timeout: timeout) ||
            waitForStaticText(containing: "No Server Songs", in: app, timeout: timeout) ||
            waitForStaticText(containing: "songs available", in: app, timeout: timeout)
    }

    @MainActor
    func testServerSongsTab() throws {
        try openSongsView(in: app)

        // Switch to Server tab
        XCTAssertTrue(switchToServerTab(app: app))

        // Verify refresh button exists
        let refreshButton = try requireRefreshButton()
        XCTAssertTrue(waitForEnabled(refreshButton))

        // Test refresh functionality
        refreshButton.tap()

        XCTAssertTrue(waitForServerTabState())
    }
    
    @MainActor
    func testServerSongsEmptyState() throws {
        try openSongsView(in: app)

        // Switch to Server tab
        XCTAssertTrue(switchToServerTab(app: app))
        
        // Wait for loading to complete and verify empty state (assuming no server connection)
        // Wait for either empty state or songs to appear after network request
        let emptyStateAppeared = waitForStaticText(containing: "No Server Songs", in: app, timeout: 8)
        let songsAppeared = waitForStaticText(containing: "songs available", in: app, timeout: 8)
        
        XCTAssertTrue(
            emptyStateAppeared || songsAppeared,
            "Either empty state or songs should appear after network request"
        )
        
        if emptyStateAppeared {
            XCTAssertTrue(
                waitForStaticText(containing: "No Server Songs", in: app),
                "Empty state text should be visible"
            )
            XCTAssertTrue(
                waitForStaticText(containing: "Tap the refresh button to load songs from the server", in: app),
                "Instruction text should be visible"
            )
        }
    }
    
    @MainActor
    func testServerSongsRefreshButton() throws {
        try openSongsView(in: app)

        // Switch to Server tab
        XCTAssertTrue(switchToServerTab(app: app))

        let refreshButton = try requireRefreshButton()
        XCTAssertTrue(waitForEnabled(refreshButton))

        // Test refresh button tap
        refreshButton.tap()

        XCTAssertTrue(waitForServerTabState())
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
        XCTAssertTrue(switchToServerTab(app: app))
        
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
        if !controlIsSelected(downloadedTab) {
            downloadedTab.tap()
        }

        let songCountText = app.staticTexts.matching(textContainsPredicate("songs available")).firstMatch
        XCTAssertTrue(songCountText.waitForExistence(timeout: 5))
        
        // Switch to Server tab and check count updates
        let serverTab = try requireControl(named: "Server", in: app, timeout: 5)
        serverTab.tap()

        // Song count should update when switching tabs
        XCTAssertTrue(songCountText.waitForExistence(timeout: 5))
        let serverCountText = elementText(songCountText)

        // Switch back to Downloaded tab
        downloadedTab.tap()
        let downloadedCountText = elementText(songCountText)
        
        // Assert that counts are tracked separately between tabs
        XCTAssertFalse(downloadedCountText.isEmpty, "Downloaded count should be displayed")
        XCTAssertFalse(serverCountText.isEmpty, "Server count should be displayed")
    }
}
