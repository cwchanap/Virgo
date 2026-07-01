//
//  SongsTabUITests.swift
//  VirgoUITests
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import XCTest

final class SongsTabUITests: XCTestCase {
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
        dismissSetupAssistantIfPresent(returningTo: app)
    }

    /// Launches the app with -SkipSeed flag for tests that need empty state
    private func launchAppSkippingSeed() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments.append("-UITesting")
        app.launchArguments.append("-ResetState")
        app.launchArguments.append("-SkipSeed")
        app.launch()
        dismissSetupAssistantIfPresent(returningTo: app)
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Helper Methods

    /// Waits for the START button to appear and taps it.
    /// Use this instead of directly calling app.buttons["START"].tap() to avoid flakiness.
    @MainActor
    private func tapStartButton() throws {
        try openSongsView(in: app)
    }

    // MARK: - Songs Tab Tests
    
    @MainActor
    func testSongsTabNavigation() throws {
        // Wait for START button to appear before tapping to avoid flakiness
        try tapStartButton()

        // Navigate to Songs tab via Content View (which shows SongsTabView)
        XCTAssertTrue(app.staticTexts["Songs"].waitForExistence(timeout: 10))
        
        // Verify sub-tab picker exists
        let downloadedTab = try requireControl(named: "Downloaded", in: app, timeout: 5)
        let serverTab = try requireControl(named: "Server", in: app, timeout: 5)
        
        // Test switching between sub-tabs
        serverTab.tap()
        XCTAssertTrue(switchToServerTab(app: app))

        downloadedTab.tap()
        XCTAssertTrue(switchToDownloadedTab(app: app))
    }
    
    @MainActor
    func testDownloadedSongsEmpty() throws {
        // This test needs empty state, so relaunch with -SkipSeed flag
        launchAppSkippingSeed()

        try tapStartButton()

        // Ensure we're on Downloaded tab (default)
        XCTAssertTrue(switchToDownloadedTab(app: app))

        // Verify empty state is shown
        XCTAssertTrue(waitForStaticText(containing: "No Downloaded Songs", in: app, timeout: 5))
        XCTAssertTrue(
            waitForStaticText(containing: "Download songs from the Server tab to see them here", in: app, timeout: 5)
        )
    }
    
    @MainActor
    func testDownloadedSongsWithData() throws {
        try tapStartButton()
        
        // Ensure we're on Downloaded tab
        XCTAssertTrue(switchToDownloadedTab(app: app))
        
        // Check if there are downloaded songs (DTX Import genre)
        // This test will pass if there are downloaded songs, or skip verification if empty
        let songCount = app.staticTexts.matching(textContainsPredicate("songs available")).firstMatch
        if songCount.waitForExistence(timeout: 5) {
            let countText = elementText(songCount)
            if !countText.hasPrefix("0 ") {
                // Verify downloaded songs list elements exist
                try requireControl(named: "Play", in: app, timeout: 5)
                let bookmarkPredicate = NSPredicate(
                    format: "identifier BEGINSWITH %@ OR label == %@ OR label == %@",
                    "downloadedSongBookmarkButton",
                    "Save song",
                    "Remove bookmark"
                )
                let bookmarkButton = app.buttons.matching(bookmarkPredicate).firstMatch
                XCTAssertTrue(bookmarkButton.waitForExistence(timeout: 5))
            }
        }
    }

    /// Regression guard for the stable downloaded-row accessibility identifier.
    /// `DownloadedSongsView.rowViewID(for:)` produces a canonical
    /// "downloaded-song-row-<stableID>" identifier that UI automation and
    /// accessibility clients use to locate a specific row. The identifier must
    /// actually be attached to the row container in the accessibility tree.
    @MainActor
    func testDownloadedSongsExposeStableRowAccessibilityIdentifier() throws {
        try tapStartButton()

        XCTAssertTrue(switchToDownloadedTab(app: app))

        // Skip when the seeded library has no downloaded songs; the assertion is
        // only meaningful when rows are actually rendered.
        guard hasDownloadedSongs(app: app) else {
            return
        }

        // Any row whose accessibility identifier begins with the canonical
        // prefix proves the rowViewID helper is attached to the row container.
        let rowIdentifierPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
            "downloaded-song-row-",
            "downloadedSongCard-"
        )
        let matchingRows = app.descendants(matching: .any).matching(rowIdentifierPredicate)
        XCTAssertTrue(
            matchingRows.firstMatch.waitForExistence(timeout: 5),
            "Downloaded songs must expose their stable accessibility identifier "
                + "(prefix 'downloaded-song-row-' for rows or 'downloadedSongCard-' for grid cards)"
        )
    }

    @MainActor
    func testDownloadedSongsPlayback() throws {
        try tapStartButton()
        
        // Ensure we're on Downloaded tab
        XCTAssertTrue(switchToDownloadedTab(app: app))
        
        // Find first play button if songs exist
        let playButton = app.buttons.matching(NSPredicate(format: "label == %@", "Play")).firstMatch
        if playButton.waitForExistence(timeout: 5) {
            // Test play functionality
            playButton.tap()
            
            // Verify play button changes to pause (may take a moment for audio to start)
            let pauseButton = app.buttons.matching(NSPredicate(format: "label == %@", "Pause")).firstMatch
            XCTAssertTrue(pauseButton.waitForExistence(timeout: 3))
            
            // Test pause functionality
            pauseButton.tap()
            XCTAssertTrue(playButton.waitForExistence(timeout: 3))
        }
    }
    
    @MainActor
    func testDownloadedSongExpansion() throws {
        try tapStartButton()

        XCTAssertTrue(switchToDownloadedTab(app: app))

        guard hasDownloadedSongs(app: app) else { return }

        // Once songs exist, a control MUST reveal the picker: the grid card's
        // open button (wide) or the row's "N charts" expand button (narrow).
        // Failing to find either is a real failure, not a vacuous skip.
        let openButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Open ")
        ).firstMatch
        let chartIndicator = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'charts'")
        ).firstMatch
        guard let control = waitForFirstExisting([openButton, chartIndicator], timeout: 5) else {
            XCTFail("Expected a card open button or row expand button when downloaded songs exist")
            return
        }
        control.tap()

        // The difficulty selector appears (same DifficultyExpansionView in both).
        XCTAssertTrue(waitForStaticText(containing: "Select Difficulty", in: app, timeout: 5))
        let difficultyButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "chartDifficulty")
        ).firstMatch
        XCTAssertTrue(difficultyButton.waitForExistence(timeout: 3))

        // Dismiss the picker sheet if present (grid path); harmless if absent.
        let done = app.buttons["difficultyPickerDoneButton"]
        if done.waitForExistence(timeout: 2) {
            done.tap()
            XCTAssertTrue(done.waitForNonExistence(timeout: 3), "Picker sheet should dismiss on Done")
        }
    }
    
    @MainActor
    func testDownloadedSongDeletion() throws {
        try tapStartButton()
        
        // Ensure we're on Downloaded tab
        XCTAssertTrue(switchToDownloadedTab(app: app))
        
        // Find delete button if songs exist
        let deleteButton = app.buttons.matching(NSPredicate(format: "label == %@", "Delete")).firstMatch
        if deleteButton.waitForExistence(timeout: 5) {
            // Count songs before deletion
            let songCountBefore = app.staticTexts.matching(textContainsPredicate("songs available")).firstMatch
            let beforeText = elementText(songCountBefore)
            
            // Tap delete button
            deleteButton.tap()
            
            // Verify deletion progress indicator appears
            let deletingText = app.staticTexts["Deleting..."]
            if deletingText.waitForExistence(timeout: 2) {
                // Wait for deletion to complete
                XCTAssertTrue(deletingText.waitForNonExistence(timeout: 10))
            }
            
            // Wait for the song count text to actually change (or empty state to appear).
            // `waitForExistence` alone is insufficient because the count element already
            // exists before deletion — it returns immediately without waiting for the
            // count value to update.
            let songCountAfter = app.staticTexts.matching(textContainsPredicate("songs available")).firstMatch
            let emptyState = app.staticTexts.matching(textContainsPredicate("No Downloaded Songs")).firstMatch

            let countChangedPredicate = NSPredicate { _, _ in
                if emptyState.exists { return true }
                guard songCountAfter.exists else { return false }
                return self.elementText(songCountAfter) != beforeText
            }
            let countChangedExpectation = expectation(
                for: countChangedPredicate,
                evaluatedWith: songCountAfter,
                handler: nil
            )
            let result = XCTWaiter.wait(for: [countChangedExpectation], timeout: 10)
            XCTAssertTrue(
                result == .completed,
                "Song count should change or empty state should appear after deletion"
            )

            // Gate on the same conditions the predicate used, so the assertion
            // matches the path that actually satisfied the waiter. Checking
            // `songCountAfter.exists` first would misroute cases where the
            // empty state appeared but the stale count label still exists.
            if emptyState.exists {
                XCTAssertTrue(emptyState.exists, "Empty state should be visible after all songs deleted")
            } else {
                XCTAssertTrue(songCountAfter.exists, "Song count element should exist when empty state is absent")
                let afterText = elementText(songCountAfter)
                XCTAssertNotEqual(beforeText, afterText, "Song count should change after deletion")
            }
        }
    }

    @MainActor
    func testDifficultyScoresButtonOpensScoresSheet() throws {
        try tapStartButton()

        XCTAssertTrue(switchToDownloadedTab(app: app))

        let searchField = app.textFields["searchField"]
        if searchField.waitForExistence(timeout: 3) {
            searchField.clearAndEnterText("Thunder Beat")
        }

        // Scope the expand button to the Thunder Beat row so we reveal the
        // correct song's charts (which include Easy difficulty).
        try expandSongRow(containing: "Thunder Beat", in: app, timeout: 10)

        _ = try requireDifficultyButton(named: "Easy", in: app, timeout: 5)
        try tapScoresButton(named: "Easy", in: app, timeout: 5)

        try requireStaticText(containing: "Scores", in: app, timeout: 5)
        try requireStaticText(containing: "BEST SCORE", in: app, timeout: 5)
        try requireStaticText(containing: "No attempts yet", in: app, timeout: 5)
    }

    @MainActor
    func testLibraryDeleteButtonRemovesDownloadedSong() throws {
        try tapStartButton()

        try tapControl(named: "Library", in: app, timeout: 5)
        try requireStaticText(containing: "Downloaded Songs", in: app, timeout: 5)
        try requireElement(containing: "Thunder Beat", in: app, timeout: 5)
        // The count includes the 7 seeded sample songs plus the bundled Soukyuu
        // DTX fixture (also server-imported), so expect 8 before deletion.
        try requireStaticText(containing: "8 songs downloaded", in: app, timeout: 5)

        let deleteButton = try requireButton(containing: "Delete Thunder Beat", in: app, timeout: 5)
        deleteButton.tap()

        XCTAssertTrue(
            waitForStaticText(containing: "7 songs downloaded", in: app, timeout: 10),
            "Library should update its downloaded-song count after deleting one fixture song"
        )
        XCTAssertTrue(
            waitForNoElement(containing: "Thunder Beat", in: app, timeout: 5),
            "Deleted song should no longer be listed in Library"
        )
    }
    
}
