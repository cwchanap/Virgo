//
//  UITestHelpers.swift
//  VirgoUITests
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import XCTest

// MARK: - Helper Extensions
extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        guard let stringValue = self.value as? String else {
            XCTFail("Tried to clear and enter text into a non-string value")
            return
        }

        self.tap()

        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
        self.typeText(text)
    }

    /// Wait for element to exist and be hittable
    func waitForExistenceAndHittable(timeout: TimeInterval = 10) -> Bool {
        let existsPredicate = NSPredicate(format: "exists == true")
        let hittablePredicate = NSPredicate(format: "hittable == true")
        let combinedPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [existsPredicate, hittablePredicate])

        let expectation = XCTestCase().expectation(for: combinedPredicate, evaluatedWith: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}

extension XCTestCase {
    /// Wait for multiple elements to exist
    func waitForElements(_ elements: [XCUIElement], timeout: TimeInterval = 10) -> Bool {
        let expectations = elements.map { element in
            expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: element)
        }
        let result = XCTWaiter.wait(for: expectations, timeout: timeout)
        return result == .completed
    }

    /// Wait for app to finish loading with data
    func waitForDataLoad(app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        // Wait for both UI elements and data to be present
        let drumTracksTitle = app.staticTexts["Drum Tracks"]
        let firstTrack = app.staticTexts["Thunder Beat"]

        return waitForElements([drumTracksTitle, firstTrack], timeout: timeout)
    }
    
    /// Navigate to Songs tab and wait for it to load
    func navigateToSongsTab(app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        app.buttons["START"].tap()
        return app.staticTexts["Songs"].waitForExistence(timeout: timeout)
    }
    
    /// Switch to Downloaded sub-tab in Songs tab
    func switchToDownloadedTab(app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let downloadedTab = app.buttons["Downloaded"]
        guard downloadedTab.waitForExistence(timeout: timeout) else { return false }
        
        if !downloadedTab.isSelected {
            downloadedTab.tap()
        }
        return downloadedTab.isSelected
    }
    
    /// Switch to Server sub-tab in Songs tab
    func switchToServerTab(app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let serverTab = app.buttons["Server"]
        guard serverTab.waitForExistence(timeout: timeout) else { return false }
        
        if !serverTab.isSelected {
            serverTab.tap()
        }
        return serverTab.isSelected
    }
    
    /// Check if there are any downloaded songs available
    func hasDownloadedSongs(app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let songCount = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'songs available'")).firstMatch
        guard songCount.waitForExistence(timeout: timeout) else { return false }
        
        let countText = songCount.label
        return !countText.hasPrefix("0 ")
    }
    
    /// Verify Songs tab empty state for Downloaded tab
    func verifyDownloadedSongsEmptyState(app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let emptyIcon = app.images["arrow.down.circle"]
        let emptyTitle = app.staticTexts["No Downloaded Songs"]
        let emptyMessage = app.staticTexts["Download songs from the Server tab to see them here"]
        
        return waitForElements([emptyIcon, emptyTitle, emptyMessage], timeout: timeout)
    }
    
    /// Verify Songs tab empty state for Server tab
    func verifyServerSongsEmptyState(app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let emptyIcon = app.images["cloud"]
        let emptyTitle = app.staticTexts["No Server Songs"]
        let emptyMessage = app.staticTexts["Tap the refresh button to load songs from the server"]
        
        return waitForElements([emptyIcon, emptyTitle, emptyMessage], timeout: timeout)
    }
}
