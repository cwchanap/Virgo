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
    /// selector to appear. Finds the expand button whose accessibility label
    /// contains both the song title and a non-zero chart count, ensuring the
    /// correct song's charts are revealed even when multiple songs are visible.
    ///
    /// The expand button's accessibility label is set to
    /// `"{songTitle} - {chartCount} charts"` in `DownloadedSongsView`. Querying
    /// by label (not identifier) is required because macOS SwiftUI accessibility
    /// container merging can hide inner button identifiers when the parent view
    /// has its own `.accessibilityIdentifier`.
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

        // Find the expand button by label. The label is
        // "{songTitle} - {chartCount} charts", so matching both the song
        // title AND a non-zero chart count uniquely identifies the correct
        // button. We use label (not identifier) because macOS accessibility
        // container merging can hide inner button identifiers.
        let labelPredicate = NSPredicate(
            format: "label CONTAINS[c] %@ AND label MATCHES[c] %@",
            songTitle, ".*[1-9][0-9]* charts.*"
        )
        let expandButton = app.buttons.matching(labelPredicate).firstMatch

        guard expandButton.waitForExistence(timeout: timeout) else {
            XCTFail(
                "Expected expand button for song \"\(songTitle)\" to exist",
                file: file,
                line: line
            )
            throw UITestFailure.elementNotFound("expand button for \(songTitle)")
        }

        expandButton.tap()

        XCTAssertTrue(
            waitForStaticText(containing: "Select Difficulty", in: app, timeout: timeout),
            "Difficulty selector should appear after expanding \(songTitle)",
            file: file,
            line: line
        )
    }
}
