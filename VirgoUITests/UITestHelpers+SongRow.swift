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
    /// selector to appear. Scopes the expand button to the row containing the
    /// title text so the correct song's charts are revealed, even when multiple
    /// songs are visible and the search filter hasn't reduced the list.
    ///
    /// On macOS, SwiftUI `List` rows are exposed as `Button` elements with
    /// identifiers beginning with `downloaded-song-row-`. This helper finds
    /// the row button whose contained static text matches the song title,
    /// then taps the `downloadedSongExpandButton` within that row.
    func expandSongRow(
        containing songTitle: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        // Wait for the song title text to appear (proves the song is loaded).
        guard waitForStaticText(containing: songTitle, in: app, timeout: timeout) else {
            XCTFail(
                "Expected song title \"\(songTitle)\" to appear in the list",
                file: file,
                line: line
            )
            throw UITestFailure.elementNotFound("song title \(songTitle)")
        }

        let row = try requireSongRow(
            containing: songTitle,
            in: app,
            timeout: timeout,
            file: file,
            line: line
        )
        let expandButton = try requireExpandButton(
            in: row,
            timeout: timeout,
            file: file,
            line: line
        )
        expandButton.tap()

        XCTAssertTrue(
            waitForStaticText(containing: "Select Difficulty", in: app, timeout: timeout),
            "Difficulty selector should appear after expanding \(songTitle)",
            file: file,
            line: line
        )
    }

    /// Finds the downloaded-song row button whose contained static text matches
    /// `songTitle`. On macOS, rows are exposed as `Button` elements with
    /// identifiers beginning with `downloaded-song-row-`.
    private func requireSongRow(
        containing songTitle: String,
        in app: XCUIApplication,
        timeout: TimeInterval,
        file: StaticString,
        line: UInt
    ) throws -> XCUIElement {
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "downloaded-song-row-")

        // Primary: match by staticText identifier (exact title text).
        let row = app.buttons
            .matching(rowPredicate)
            .containing(.staticText, identifier: songTitle)
            .firstMatch

        if row.waitForExistence(timeout: timeout) {
            return row
        }

        // Fallback: label-based predicate for macOS accessibility variations
        // where the staticText identifier doesn't match exactly.
        let titlePredicate = textContainsPredicate(songTitle)
        let fallbackRow = app.buttons
            .matching(rowPredicate)
            .containing(titlePredicate)
            .firstMatch

        if fallbackRow.waitForExistence(timeout: 5) {
            return fallbackRow
        }

        XCTFail(
            "Expected a downloaded song row containing \"\(songTitle)\" to exist",
            file: file,
            line: line
        )
        throw UITestFailure.elementNotFound("song row containing \(songTitle)")
    }

    /// Returns the expand button scoped to a specific song row, avoiding the
    /// global `firstMatch` race that can select a different song's row.
    private func requireExpandButton(
        in row: XCUIElement,
        timeout: TimeInterval,
        file: StaticString,
        line: UInt
    ) throws -> XCUIElement {
        let expandButton = row.buttons["downloadedSongExpandButton"]

        guard expandButton.waitForExistence(timeout: timeout) else {
            XCTFail(
                "Expected expand button in song row",
                file: file,
                line: line
            )
            throw UITestFailure.elementNotFound("expand button in song row")
        }

        return expandButton
    }
}
