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

private let systemDialogButtonLabels = [
    "Continue",
    "Not Now",
    "Skip",
    "Set Up Later",
    "Don't Share",
    "Don’t Share",
    "OK",
    "Allow",
    "Close"
]

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
    func installSystemDialogHandlers() {
        addUIInterruptionMonitor(withDescription: "System setup and permission dialogs") { element in
            self.tapFirstSystemDialogButton(in: element)
        }
    }

    @discardableResult
    func dismissSetupAssistantIfPresent(timeout: TimeInterval = 2) -> Bool {
        let setupAssistant = XCUIApplication(bundleIdentifier: "com.apple.SetupAssistant")
        guard setupAssistant.state != .notRunning else { return false }

        setupAssistant.activate()
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if tapFirstSystemDialogButton(in: setupAssistant) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        return false
    }

    private func tapFirstSystemDialogButton(in root: XCUIElement) -> Bool {
        for label in systemDialogButtonLabels {
            let button = root.buttons[label]
            if button.exists {
                button.tap()
                return true
            }
        }

        let continueButton = root.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Continue")
        ).firstMatch
        if continueButton.exists {
            continueButton.tap()
            return true
        }

        return false
    }

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

    func textContainsPredicate(_ text: String) -> NSPredicate {
        NSPredicate(
            format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
            text,
            text
        )
    }

    @discardableResult
    func requireStaticText(
        containing text: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let staticText = app.staticTexts.matching(textContainsPredicate(text)).firstMatch
        if let element = waitForFirstExisting([staticText], timeout: timeout) {
            return element
        }

        XCTFail("Expected static text containing \(text) to exist", file: file, line: line)
        throw UITestFailure.elementNotFound(text)
    }

    func waitForStaticText(
        containing text: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10
    ) -> Bool {
        app.staticTexts.matching(textContainsPredicate(text)).firstMatch.waitForExistence(timeout: timeout)
    }

    func controlIsSelected(_ element: XCUIElement) -> Bool {
        if element.isSelected {
            return true
        }

        if let value = element.value as? String {
            return value == "1" || value.localizedCaseInsensitiveContains("selected")
        }

        if let value = element.value as? NSNumber {
            return value.intValue == 1
        }

        return false
    }

    func elementText(_ element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }

        return element.label
    }

    @discardableResult
    func requireControl(
        named name: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let exactMatch = NSPredicate(format: "identifier == %@ OR label == %@", name, name)
        let candidates = [
            app.buttons.matching(exactMatch).firstMatch,
            app.radioButtons.matching(exactMatch).firstMatch
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

    @discardableResult
    func requireDifficultyButton(
        named difficulty: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let identifier = "chartDifficulty\(difficulty)"
        let labelPredicate = NSPredicate(
            format: "label CONTAINS[c] %@ AND (label CONTAINS[c] 'difficulty' OR label CONTAINS[c] 'Level')",
            difficulty
        )
        let candidates = [
            app.buttons[identifier],
            app.buttons.matching(labelPredicate).firstMatch
        ]

        if let element = waitForFirstExisting(candidates, timeout: timeout) {
            return element
        }

        XCTFail("Expected \(difficulty) difficulty button to exist", file: file, line: line)
        throw UITestFailure.elementNotFound(difficulty)
    }

    func openSongsView(
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        dismissSetupAssistantIfPresent(timeout: 1)

        if !waitForStaticText(containing: "Songs", in: app, timeout: 1) &&
            !app.textFields["searchField"].waitForExistence(timeout: 1) {
            try tapControl(named: "START", in: app, timeout: timeout, file: file, line: line)
        }

        XCTAssertTrue(
            waitForStaticText(containing: "Songs", in: app, timeout: timeout) ||
                app.textFields["searchField"].waitForExistence(timeout: timeout),
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

        try requireStaticText(containing: songTitle, in: app, timeout: timeout, file: file, line: line)

        let chartButton = try requireButton(containing: "charts", in: app, timeout: timeout, file: file, line: line)
        chartButton.tap()

        XCTAssertTrue(
            waitForStaticText(containing: "Select Difficulty", in: app, timeout: timeout),
            "Difficulty selector should appear",
            file: file,
            line: line
        )

        let difficultyElement = try requireDifficultyButton(
            named: difficulty,
            in: app,
            timeout: timeout,
            file: file,
            line: line
        )
        difficultyElement.tap()

        try requireStaticText(containing: songTitle, in: app, timeout: timeout, file: file, line: line)
        try requireStaticText(containing: artist, in: app, timeout: timeout, file: file, line: line)
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

        if !controlIsSelected(downloadedTab) {
            downloadedTab.tap()
        }

        return waitForStaticText(containing: "songs available", in: app, timeout: timeout) ||
            waitForStaticText(containing: "No Downloaded Songs", in: app, timeout: timeout)
    }
    
    /// Switch to Server sub-tab in Songs tab
    func switchToServerTab(app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        guard let serverTab = waitForFirstExisting([
            app.buttons["Server"],
            app.radioButtons["Server"]
        ], timeout: timeout) else { return false }

        if !controlIsSelected(serverTab) {
            serverTab.tap()
        }

        return app.buttons["refreshServerSongsButton"].waitForExistence(timeout: timeout) ||
            app.buttons["Refresh server songs"].waitForExistence(timeout: timeout)
    }
    
    /// Check if there are any downloaded songs available
    func hasDownloadedSongs(app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let songCount = app.staticTexts.matching(textContainsPredicate("songs available")).firstMatch
        guard songCount.waitForExistence(timeout: timeout) else { return false }
        
        let countText = elementText(songCount)
        return !countText.hasPrefix("0 ")
    }
    
    /// Verify Songs tab empty state for Downloaded tab
    func verifyDownloadedSongsEmptyState(app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let emptyIcon = app.images["arrow.down.circle"]

        return emptyIcon.waitForExistence(timeout: timeout) &&
            waitForStaticText(containing: "No Downloaded Songs", in: app, timeout: timeout) &&
            waitForStaticText(
                containing: "Download songs from the Server tab to see them here",
                in: app,
                timeout: timeout
            )
    }
    
    /// Verify Songs tab empty state for Server tab
    func verifyServerSongsEmptyState(app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let emptyIcon = app.images["cloud"]

        return emptyIcon.waitForExistence(timeout: timeout) &&
            waitForStaticText(containing: "No Server Songs", in: app, timeout: timeout) &&
            waitForStaticText(
                containing: "Tap the refresh button to load songs from the server",
                in: app,
                timeout: timeout
            )
    }
}
