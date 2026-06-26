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
    /// selector to appear. Finds the expand button by its unique accessibility
    /// identifier, which includes the song title, ensuring the correct song's
    /// charts are revealed even when multiple songs are visible.
    ///
    /// The expand button's accessibility identifier is set to
    /// `downloadedSongExpandButton_{songTitle}` in `DownloadedSongsView`, so a
    /// direct identifier lookup uniquely identifies the correct button without
    /// relying on row scoping or search-filter propagation timing.
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

        // Find the expand button by its unique identifier, which includes
        // the song title. This avoids the global firstMatch race.
        let expandButton = app.buttons["downloadedSongExpandButton_\(songTitle)"]

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
