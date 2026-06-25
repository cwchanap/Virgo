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
    /// `expectedCount` rows. The SwiftUI list filter is asynchronous relative to
    /// XCUITextField typing, so without this wait a global `firstMatch` query can
    /// resolve to the wrong (unfiltered) row before the filter propagates.
    ///
    /// Uses `descendants(matching: .any)` because macOS SwiftUI `List` rows are
    /// not exposed as `cells` (an iOS-only XCUI element type). On macOS the rows
    /// surface as `otherElements` or `buttons` depending on accessibility
    /// element merging, so a type-agnostic query is required.
    func waitForSearchFilterToApply(
        expectedCount: Int = 1,
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let rowPrefix = "downloaded-song-row-"
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH %@", rowPrefix)
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let visibleRowCount = app.descendants(matching: .any).matching(rowPredicate).count
            if visibleRowCount > 0 && visibleRowCount <= expectedCount {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let finalCount = app.descendants(matching: .any).matching(rowPredicate).count
        return finalCount > 0 && finalCount <= expectedCount
    }
}
