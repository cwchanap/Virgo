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
    /// selector to appear. Uses coordinate-based matching to find the expand
    /// button that is in the same row as the song title text, avoiding the
    /// global `firstMatch` race.
    ///
    /// On macOS, neither `.accessibilityIdentifier` nor `.accessibilityLabel`
    /// on SwiftUI Buttons inside accessibility containers are reliably exposed
    /// for predicate-based queries. The only reliable query is the label regex
    /// `.*N charts.*` which matches all expand buttons but can't distinguish
    /// between them. This helper solves the problem by finding the title text's
    /// frame, then finding the expand button whose frame overlaps vertically.
    ///
    /// Uses `.*[0-9]+ charts.*` (matches 0 charts too) instead of
    /// `.*[1-9][0-9]* charts.*` because chart counts load asynchronously
    /// (seeded to 0). Matching 0 charts ensures the correct button is found
    /// even before chart counts load. After tapping, we wait for the
    /// difficulty buttons to appear, which handles the async loading.
    func expandSongRow(
        containing songTitle: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard waitForStaticText(containing: songTitle, in: app, timeout: timeout) else {
            XCTFail(
                "Expected song title \"\(songTitle)\" to appear in the list",
                file: file,
                line: line
            )
            throw UITestFailure.elementNotFound("song title \(songTitle)")
        }

        // Match any expand button (including 0 charts) so we can find the
        // correct button by frame overlap before chart counts load.
        let anyChartCount = NSPredicate(format: "label MATCHES[c] %@", ".*[0-9]+ charts.*")
        let allExpandButtons = app.buttons.matching(anyChartCount)
        guard allExpandButtons.firstMatch.waitForExistence(timeout: timeout) else {
            XCTFail("Expected at least one expand button to exist", file: file, line: line)
            throw UITestFailure.elementNotFound("expand button")
        }

        let expandButton = try requireExpandButtonNearTitle(
            songTitle, in: app, buttons: allExpandButtons,
            file: file, line: line
        )
        expandButton.tap()

        XCTAssertTrue(
            waitForStaticText(containing: "Select Difficulty", in: app, timeout: timeout),
            "Difficulty selector should appear after expanding \(songTitle)",
            file: file, line: line
        )
    }

    /// Finds the expand button whose frame overlaps vertically with the song
    /// title text (same row). This avoids the firstMatch race without relying
    /// on accessibility labels or identifiers.
    private func requireExpandButtonNearTitle(
        _ songTitle: String,
        in app: XCUIApplication,
        buttons: XCUIElementQuery,
        file: StaticString,
        line: UInt
    ) throws -> XCUIElement {
        let titlePredicate = textContainsPredicate(songTitle)
        let titleText = app.staticTexts.matching(titlePredicate).firstMatch
        guard titleText.exists else {
            XCTFail("Expected title text for \"\(songTitle)\" to exist", file: file, line: line)
            throw UITestFailure.elementNotFound("title text for \(songTitle)")
        }

        let titleFrame = titleText.frame
        for i in 0..<buttons.count {
            let button = buttons.element(boundBy: i)
            if button.exists {
                let buttonFrame = button.frame
                let overlap = min(titleFrame.maxY, buttonFrame.maxY) - max(titleFrame.minY, buttonFrame.minY)
                if overlap > 0 {
                    return button
                }
            }
        }

        XCTFail(
            "Expected expand button in the same row as \"\(songTitle)\" to exist",
            file: file, line: line
        )
        throw UITestFailure.elementNotFound("expand button for \(songTitle)")
    }
}
