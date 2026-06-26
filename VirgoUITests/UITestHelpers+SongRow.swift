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
    /// On macOS, `.accessibilityLabel` modifiers on SwiftUI Buttons inside
    /// accessibility containers are not reliably exposed, so label-based
    /// queries cannot distinguish between expand buttons for different songs.
    /// Instead, this helper finds the title text's frame, then finds the
    /// expand button whose frame overlaps vertically (same row).
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

        let nonEmptyChartCount = NSPredicate(format: "label MATCHES[c] %@", ".*[1-9][0-9]* charts.*")
        let allExpandButtons = app.buttons.matching(nonEmptyChartCount)
        guard allExpandButtons.firstMatch.waitForExistence(timeout: timeout) else {
            XCTFail("Expected at least one loaded expand button to exist", file: file, line: line)
            throw UITestFailure.elementNotFound("loaded expand button")
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
    /// on accessibility labels.
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
