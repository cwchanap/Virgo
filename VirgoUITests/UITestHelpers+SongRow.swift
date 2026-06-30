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
    /// Reveals the difficulty selector for the song matching `songTitle` and
    /// waits for it to appear. Callers filter the list to this song first
    /// (`searchField`), so the single matching open/expand control is
    /// unambiguous and `firstMatch` is safe.
    ///
    /// Layout-aware: wide layouts (macOS / full-screen iPad) render a card grid
    /// whose tappable open control is a Button carrying the identifier
    /// `downloadedSongCardOpenButton` and accessibilityLabel "Open <title>".
    /// Narrow layouts render a row with a "N charts" expand Button — its count
    /// is seeded to 0 and loaded asynchronously, so the regex requires a
    /// NON-ZERO count to ensure charts have loaded before expanding (tapping too
    /// early yields an empty charts array and no difficulty buttons).
    ///
    /// macOS exposes SwiftUI Button accessibility attributes inconsistently
    /// (sometimes the identifier is hidden, sometimes the label), so — like
    /// `requireDifficultyButton` — we poll several candidates via
    /// `waitForFirstExisting` and tap whichever resolves. Both the card open
    /// button and the row expand button reveal the same `DifficultyExpansionView`
    /// ("Select Difficulty"), so the post-tap assertion is layout-independent.
    func expandSongRow(
        containing songTitle: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        // Card grid (wide): the open button, by identifier or "Open <title>" label.
        let openCardById = app.buttons["downloadedSongCardOpenButton"]
        let openCardByLabel = app.buttons
            .matching(NSPredicate(format: "label == %@", "Open \(songTitle)"))
            .firstMatch
        // Row list (narrow): the "N charts" expand button with a NON-ZERO count.
        let nonZeroChartCount = NSPredicate(format: "label MATCHES[c] %@", ".*[1-9][0-9]* charts.*")
        let rowExpandButton = app.buttons.matching(nonZeroChartCount).firstMatch

        guard let control = waitForFirstExisting(
            [openCardById, openCardByLabel, rowExpandButton],
            timeout: timeout
        ) else {
            XCTFail(
                "Expected a card open button or row expand button for song \"\(songTitle)\"",
                file: file,
                line: line
            )
            throw UITestFailure.elementNotFound("open/expand control for \(songTitle)")
        }
        control.tap()

        XCTAssertTrue(
            waitForStaticText(containing: "Select Difficulty", in: app, timeout: timeout),
            "Difficulty selector should appear after opening \(songTitle)",
            file: file, line: line
        )
    }
}
