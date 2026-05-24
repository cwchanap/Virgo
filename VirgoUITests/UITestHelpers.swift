//
//  UITestHelpers.swift
//  VirgoUITests
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import XCTest

enum UITestFailure: Error {
    case elementNotFound(String)
}

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

    /// Wait for element to exist and be hittable (requires test case context)
    func waitForExistenceAndHittable(on testCase: XCTestCase, timeout: TimeInterval = 10) -> Bool {
        let existsPredicate = NSPredicate(format: "exists == true")
        let hittablePredicate = NSPredicate(format: "hittable == true")
        let combinedPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [existsPredicate, hittablePredicate])

        let expectation = testCase.expectation(for: combinedPredicate, evaluatedWith: self, handler: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
    
    /// Wait for element to disappear
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}

extension XCTestCase {
    @discardableResult
    func waitForFirstExisting(_ elements: [XCUIElement], timeout: TimeInterval = 10) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if let element = elements.first(where: { $0.exists }) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return elements.first(where: { $0.exists })
    }

    @discardableResult
    func requireControl(
        named name: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let candidates = [
            app.buttons[name],
            app.radioButtons[name]
        ]

        if let element = waitForFirstExisting(candidates, timeout: timeout) {
            return element
        }

        XCTFail("Expected control named \(name) to exist", file: file, line: line)
        throw UITestFailure.elementNotFound(name)
    }

    @discardableResult
    func tapControl(
        named name: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let element = try requireControl(named: name, in: app, timeout: timeout, file: file, line: line)
        element.tap()
        return element
    }

    @discardableResult
    func requireButton(
        containing label: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
        if let element = waitForFirstExisting([button], timeout: timeout) {
            return element
        }

        XCTFail("Expected button containing \(label) to exist", file: file, line: line)
        throw UITestFailure.elementNotFound(label)
    }

    func openSongsView(
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        if !app.staticTexts["Songs"].waitForExistence(timeout: 1) {
            try tapControl(named: "START", in: app, timeout: timeout, file: file, line: line)
        }

        XCTAssertTrue(
            app.staticTexts["Songs"].waitForExistence(timeout: timeout),
            "Songs view should load",
            file: file,
            line: line
        )
    }

    func openGameplay(
        in app: XCUIApplication,
        songTitle: String = "Thunder Beat",
        artist: String = "Rock Masters",
        difficulty: String = "Easy",
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try openSongsView(in: app, timeout: timeout, file: file, line: line)

        let searchField = app.textFields["searchField"]
        if searchField.waitForExistence(timeout: 3) {
            searchField.clearAndEnterText(songTitle)
        }

        XCTAssertTrue(
            app.staticTexts[songTitle].waitForExistence(timeout: timeout),
            "\(songTitle) should be visible before opening gameplay",
            file: file,
            line: line
        )

        let chartButton = try requireButton(containing: "charts", in: app, timeout: timeout, file: file, line: line)
        chartButton.tap()

        XCTAssertTrue(
            app.staticTexts["Select Difficulty"].waitForExistence(timeout: timeout),
            "Difficulty selector should appear",
            file: file,
            line: line
        )

        let difficultyPredicate = NSPredicate(
            format: "label CONTAINS[c] %@ AND label CONTAINS[c] 'Level'",
            difficulty
        )
        let difficultyButton = app.buttons.matching(difficultyPredicate).firstMatch
        guard let difficultyElement = waitForFirstExisting([difficultyButton], timeout: timeout) else {
            XCTFail("Expected \(difficulty) difficulty button to exist", file: file, line: line)
            throw UITestFailure.elementNotFound(difficulty)
        }
        difficultyElement.tap()

        XCTAssertTrue(
            app.staticTexts[songTitle].waitForExistence(timeout: timeout),
            "\(songTitle) should be visible in gameplay",
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.staticTexts[artist].waitForExistence(timeout: timeout),
            "\(artist) should be visible in gameplay",
            file: file,
            line: line
        )
        try requireControl(named: "Play", in: app, timeout: timeout, file: file, line: line)
    }

    func tapBackFromGameplay(
        in app: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try tapControl(named: "Go back", in: app, timeout: timeout, file: file, line: line)
    }

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
        let songsTitle = app.staticTexts["Songs"]
        let firstTrack = app.staticTexts["Thunder Beat"]

        return waitForElements([songsTitle, firstTrack], timeout: timeout)
    }
    
    /// Navigate to Songs tab and wait for it to load
    func navigateToSongsTab(app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        try? openSongsView(in: app, timeout: timeout)
        return app.staticTexts["Songs"].waitForExistence(timeout: timeout)
    }
    
    /// Switch to Downloaded sub-tab in Songs tab
    func switchToDownloadedTab(app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        guard let downloadedTab = waitForFirstExisting([
            app.buttons["Downloaded"],
            app.radioButtons["Downloaded"]
        ], timeout: timeout) else { return false }
        
        if !downloadedTab.isSelected {
            downloadedTab.tap()
        }
        return downloadedTab.isSelected
    }
    
    /// Switch to Server sub-tab in Songs tab
    func switchToServerTab(app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        guard let serverTab = waitForFirstExisting([
            app.buttons["Server"],
            app.radioButtons["Server"]
        ], timeout: timeout) else { return false }
        
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
