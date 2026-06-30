//
//  UITestHelpers+SongRow.swift
//  VirgoUITests
//
//  Scoped song-row navigation helper that prevents the global `firstMatch`
//  race condition where multiple song rows are visible and `firstMatch`
//  resolves to the wrong song's expand button.
//

import XCTest

extension XCTestCase {
    /// Expands the song row matching `songTitle` and waits for the difficulty
    /// selector to appear.
    ///
    /// This helper waits for the song title text to appear (proving the search
    /// filter has applied and the correct song is visible), then waits for an
    /// expand button with loaded charts to appear, and taps it.
    ///
    /// On macOS, neither `.accessibilityIdentifier` nor `.accessibilityLabel`
    /// on inner SwiftUI Buttons are reliably exposed for predicate queries,
    /// and the row container is exposed as a StaticText (not a Button), making
    /// frame-based row scoping unreliable. However, since the search filter
    /// ensures only the matching song is visible, the single expand button
    /// that appears after filtering must be the correct one.
    ///
    /// To handle the async chart loading race (chartCount is seeded to 0 and
    /// loaded asynchronously), we wait for the title text first (proving the
    /// filter applied), then wait for an expand button with NON-ZERO chart
    /// count (proving charts have loaded), tap it, and wait for the difficulty
    /// selector. Waiting for non-zero charts is critical: if we tap before
    /// charts load, the expanded view receives an empty charts array and
    /// renders no difficulty buttons.
    func expandSongRow(
        containing songTitle: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        // Wait for the song title text to appear. This proves:
        // 1. The song data has loaded
        // 2. The search filter has applied (only matching songs are visible)
        guard waitForStaticText(containing: songTitle, in: app, timeout: timeout) else {
            XCTFail(
                "Expected song title \"\(songTitle)\" to appear in the list",
                file: file,
                line: line
            )
            throw UITestFailure.elementNotFound("song title \(songTitle)")
        }

        // Wide layouts (macOS / full-screen iPad) render a card grid: tap the
        // card's open button. Narrow layouts render rows with a "N charts"
        // expand button. Try the card path first, then fall back to rows.
        let openCardButton = app.buttons
            .matching(NSPredicate(format: "label == %@", "Open \(songTitle)"))
            .firstMatch
        if openCardButton.waitForExistence(timeout: 3) {
            openCardButton.tap()
        } else {
            let nonZeroChartCount = NSPredicate(format: "label MATCHES[c] %@", ".*[1-9][0-9]* charts.*")
            let expandButton = app.buttons.matching(nonZeroChartCount).firstMatch
            guard expandButton.waitForExistence(timeout: timeout) else {
                XCTFail(
                    "Expected card open button or expand button for song \"\(songTitle)\"",
                    file: file,
                    line: line
                )
                throw UITestFailure.elementNotFound("open/expand control for \(songTitle)")
            }
            expandButton.tap()
        }

        XCTAssertTrue(
            waitForStaticText(containing: "Select Difficulty", in: app, timeout: timeout),
            "Difficulty selector should appear after opening \(songTitle)",
            file: file, line: line
        )
    }
}
