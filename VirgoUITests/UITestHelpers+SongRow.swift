//
//  UITestHelpers+SongRow.swift
//  VirgoUITests
//
//  Search-filter synchronization helper that prevents the global `firstMatch`
//  race condition where a search-filtered list query can resolve to the wrong
//  song's row before the SwiftUI filter propagates.
//

import XCTest

extension XCTestCase {
    /// Waits for the search filter to reduce the downloaded-songs list to at most
    /// `expectedCount` expand buttons. The SwiftUI list filter is asynchronous
    /// relative to XCUITextField typing, so without this wait a global
    /// `firstMatch` query can resolve to the wrong (unfiltered) row before the
    /// filter propagates.
    ///
    /// Counts expand buttons by their "N charts" accessibility label (the same
    /// query `requireLoadedChartExpansionButton` uses) rather than by row
    /// identifier, because macOS SwiftUI `List` rows do not reliably expose
    /// the `downloaded-song-row-*` accessibility identifier in the XCUITest
    /// element tree.
    func waitForSearchFilterToApply(
        expectedCount: Int = 1,
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let nonEmptyChartCount = NSPredicate(format: "label MATCHES[c] %@", ".*[1-9][0-9]* charts.*")
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let visibleButtonCount = app.buttons.matching(nonEmptyChartCount).count
            if visibleButtonCount > 0 && visibleButtonCount <= expectedCount {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let finalCount = app.buttons.matching(nonEmptyChartCount).count
        return finalCount > 0 && finalCount <= expectedCount
    }
}
