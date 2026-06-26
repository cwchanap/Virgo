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
    /// selector to appear. Uses the row button's frame to precisely locate the
    /// correct expand button, avoiding the global `firstMatch` race.
    ///
    /// On macOS, neither `.accessibilityIdentifier` nor `.accessibilityLabel`
    /// on inner SwiftUI Buttons are reliably exposed for predicate queries.
    /// This helper:
    /// 1. Finds the title text element and gets its center point
    /// 2. Finds the row button (identifier BEGINSWITH "downloaded-song-row-")
    ///    whose frame contains the title text's center
    /// 3. Finds the expand button (label MATCHES "N charts") whose frame
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

        let rowFrame = try findSongRowFrame(
            containing: songTitle, in: app,
            file: file, line: line
        )
        let expandButton = try findExpandButton(
            within: rowFrame, buttons: allExpandButtons,
            songTitle: songTitle,
            file: file, line: line
        )
        expandButton.tap()

        XCTAssertTrue(
            waitForStaticText(containing: "Select Difficulty", in: app, timeout: timeout),
            "Difficulty selector should appear after expanding \(songTitle)",
            file: file, line: line
        )
    }

    /// Finds the row button whose frame contains the song title text's center.
    private func findSongRowFrame(
        containing songTitle: String,
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) throws -> CGRect {
        let titlePredicate = textContainsPredicate(songTitle)
        let titleText = app.staticTexts.matching(titlePredicate).firstMatch
        guard titleText.exists else {
            XCTFail("Expected title text for \"\(songTitle)\" to exist", file: file, line: line)
            throw UITestFailure.elementNotFound("title text for \(songTitle)")
        }
        let titleCenter = CGPoint(x: titleText.frame.midX, y: titleText.frame.midY)

        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "downloaded-song-row-")
        let rowButtons = app.buttons.matching(rowPredicate)
        for i in 0..<rowButtons.count {
            let row = rowButtons.element(boundBy: i)
            if row.exists, row.frame.contains(titleCenter) {
                return row.frame
            }
        }

        // Fallback: expand the title frame to approximate the row bounds
        return titleText.frame.insetBy(dx: -200, dy: -60)
    }

    /// Finds the expand button whose frame overlaps with the given row frame.
    private func findExpandButton(
        within rowFrame: CGRect,
        buttons: XCUIElementQuery,
        songTitle: String,
        file: StaticString,
        line: UInt
    ) throws -> XCUIElement {
        for i in 0..<buttons.count {
            let button = buttons.element(boundBy: i)
            if button.exists {
                let buttonFrame = button.frame
                // Check if the button's frame overlaps with the row frame
                let overlapX = min(rowFrame.maxX, buttonFrame.maxX) - max(rowFrame.minX, buttonFrame.minX)
                let overlapY = min(rowFrame.maxY, buttonFrame.maxY) - max(rowFrame.minY, buttonFrame.minY)
                if overlapX > 0 && overlapY > 0 {
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
