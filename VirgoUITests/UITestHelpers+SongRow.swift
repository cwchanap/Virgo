//
//  UITestHelpers+SongRow.swift
//  VirgoUITests
//
//  Scoped song-row navigation helpers that prevent the global `firstMatch`
//  race condition where a search-filtered list query can resolve to the
//  wrong song's row before the SwiftUI filter propagates.
//

import XCTest

extension XCTestCase {
    /// Waits for the search filter to reduce the downloaded-songs list to at most
    /// `expectedCount` rows. The SwiftUI list filter is asynchronous relative to
    /// XCUITextField typing, so without this wait a global `firstMatch` query can
    /// resolve to the wrong (unfiltered) row before the filter propagates.
    func waitForSearchFilterToApply(
        expectedCount: Int = 1,
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let rowPrefix = "downloaded-song-row-"
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH %@", rowPrefix)
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let visibleRowCount = app.cells.matching(rowPredicate).count
            if visibleRowCount > 0 && visibleRowCount <= expectedCount {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let finalCount = app.cells.matching(rowPredicate).count
        return finalCount > 0 && finalCount <= expectedCount
    }

    /// Finds the downloaded-song row whose cell contains the given title text.
    /// Scoping to the title-matching cell prevents `firstMatch` from resolving
    /// to a different song's row (which may lack the requested difficulty chart).
    func requireSongRow(
        containing songTitle: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH 'downloaded-song-row-'")
        let titlePredicate = textContainsPredicate(songTitle)
        let row = app.cells
            .matching(rowPredicate)
            .containing(.staticText, identifier: songTitle)
            .firstMatch

        if let element = waitForFirstExisting([row], timeout: timeout) {
            return element
        }

        // Fallback: the staticText identifier matching can differ from label on
        // some macOS accessibility configurations, so retry with a label predicate.
        let fallbackRow = app.cells
            .matching(rowPredicate)
            .containing(titlePredicate)
            .firstMatch
        if let element = waitForFirstExisting([fallbackRow], timeout: 2) {
            return element
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
    func requireExpandButton(
        in row: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let expandButton = row.buttons["downloadedSongExpandButton"]

        if let element = waitForFirstExisting([expandButton], timeout: timeout) {
            return element
        }

        XCTFail(
            "Expected downloaded song expand button to exist within the song row",
            file: file,
            line: line
        )
        throw UITestFailure.elementNotFound("expand button in song row")
    }

    /// Expands the song row matching `songTitle` and waits for the difficulty
    /// selector to appear. Scopes the expand button to the title-matching row
    /// so the correct song's charts are revealed.
    func expandSongRow(
        containing songTitle: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
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
}
