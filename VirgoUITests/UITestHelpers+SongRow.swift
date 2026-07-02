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
    /// waits for it to appear.
    ///
    /// Layout-aware: wide layouts (macOS / full-screen iPad) render a card grid
    /// whose tappable open control is a Button carrying a per-card accessibility
    /// identifier and an aggregated label containing the song title.
    /// Narrow layouts render a row with a "N charts" expand Button — its count
    /// is seeded to 0 and loaded asynchronously, so the regex requires a
    /// NON-ZERO count to ensure charts have loaded before expanding (tapping too
    /// early yields an empty charts array and no difficulty buttons). The "N
    /// charts" label and `downloadedSongExpandButton` identifier are NOT unique
    /// per song, so the row expand control is scoped to the cell containing the
    /// requested title — a global `firstMatch` can resolve to a different song
    /// while the search filter is still applying or several rows remain visible.
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
        let openCard = downloadedSongCardOpenButton(containing: songTitle, in: app)
        let fallbackOpenCard = firstDownloadedSongCardOpenButton(in: app)
        // Row list (narrow): the "N charts" expand button with a NON-ZERO count.
        let nonZeroChartCount = NSPredicate(format: "label MATCHES[c] %@", ".*[1-9][0-9]* charts.*")

        // Wait for the requested title to be mounted before selecting any row
        // expand control. In grid mode the title is only exposed as the card
        // open button's label (not as a staticText), so we accept either form.
        // This confirms the search filter has applied and the target song is
        // present, so a stale row from the previous list contents can't be
        // expanded instead.
        let titleText = app.staticTexts
            .matching(NSPredicate(format: "label == %@", songTitle))
            .firstMatch
        let titleCard = downloadedSongCardTextElement(containing: songTitle, in: app)
        guard waitForFirstExisting([openCard, titleText, titleCard], timeout: timeout) != nil else {
            XCTFail(
                "Expected song title \"\(songTitle)\" to be visible before expanding its row",
                file: file,
                line: line
            )
            throw UITestFailure.elementNotFound("song title \(songTitle)")
        }

        // Scope the row expand button to the cell whose aggregated label
        // contains the requested title (SwiftUI List rows expose as cells in
        // XCUITest and their label aggregates their children's labels, the same
        // property `textElementCandidates` relies on).
        let rowContainingSong = app.cells
            .matching(NSPredicate(format: "label CONTAINS[c] %@", songTitle))
            .firstMatch
        let scopedRowExpandButton = rowContainingSong.buttons.matching(nonZeroChartCount).firstMatch

        // Last-resort fallback for layouts where the row does not expose as a
        // cell (some macOS configurations). Only reached after the title wait
        // above has confirmed the target row is present and the search filter
        // has reduced the visible set, so a global firstMatch is safer here than
        // it would be unconditionally.
        let globalRowExpandButton = app.buttons.matching(nonZeroChartCount).firstMatch

        guard let control = waitForFirstExisting(
            [openCard, scopedRowExpandButton, globalRowExpandButton, fallbackOpenCard],
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
