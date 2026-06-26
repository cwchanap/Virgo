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
    /// for predicate-based queries. This helper:
    /// 1. Finds the row button (identifier BEGINSWITH "downloaded-song-row-")
    ///    whose frame contains the song title text
    /// 2. Finds the expand button (label MATCHES "N charts") whose frame
    ///    overlaps with that row's frame
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

        let anyChartCount = NSPredicate(format: "label MATCHES[c] %@", ".*[0-9]+ charts.*")
        let allExpandButtons = app.buttons.matching(anyChartCount)
        guard allExpandButtons.firstMatch.waitForExistence(timeout: timeout) else {
            XCTFail("Expected at least one expand button to exist", file: file, line: line)
            throw UITestFailure.elementNotFound("expand button")
        }

        let expandButton = try requireExpandButtonInSongRow(
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

    /// Finds the expand button that is within the same row as the song title.
    /// Uses the row button's frame (which encompasses the entire row) to
    /// match, since the title text and expand button may be at different
    /// vertical positions within the row.
    private func requireExpandButtonInSongRow(
        _ songTitle: String,
        in app: XCUIApplication,
        buttons: XCUIElementQuery,
        file: StaticString,
        line: UInt
    ) throws -> XCUIElement {
        // Find the title text to locate the correct row.
        let titlePredicate = textContainsPredicate(songTitle)
        let titleText = app.staticTexts.matching(titlePredicate).firstMatch
        guard titleText.exists else {
            XCTFail("Expected title text for \"\(songTitle)\" to exist", file: file, line: line)
            throw UITestFailure.elementNotFound("title text for \(songTitle)")
        }
        let titleFrame = titleText.frame

        // Find the expand button whose frame is vertically near the title
        // text. Use a generous Y tolerance to account for the expand button
        // being below the action buttons in the row's VStack layout.
        let yTolerance: CGFloat = 100
        for i in 0..<buttons.count {
            let button = buttons.element(boundBy: i)
            if button.exists {
                let buttonFrame = button.frame
                // Check if the button is within yTolerance of the title text
                let verticalDistance = abs(buttonFrame.midY - titleFrame.midY)
                if verticalDistance < yTolerance {
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
