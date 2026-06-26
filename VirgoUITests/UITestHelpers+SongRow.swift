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
    /// Waits for the search filter to reduce the visible song count to at most
    /// `expectedCount`. The SwiftUI list filter is asynchronous relative to
    /// XCUITextField typing, so without this wait a global `firstMatch` query
    /// can resolve to the wrong (unfiltered) row before the filter propagates.
    ///
    /// Uses the "N songs available" header text as the filter signal because it
    /// directly reflects the filtered `songs.count` / `filteredServerSongs.count`
    /// without being affected by the asynchronous chart-count loading race
    /// (chart counts are seeded to 0 and populated by `.loadSongRelationships`,
    /// so counting "N charts" buttons conflate filter state with chart loading).
    func waitForSearchFilterToApply(
        expectedCount: Int = 1,
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let songsAvailablePredicate = NSPredicate(format: "label MATCHES %@", "\(expectedCount) songs available")
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if app.staticTexts.matching(songsAvailablePredicate).firstMatch.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return app.staticTexts.matching(songsAvailablePredicate).firstMatch.exists
    }
}
