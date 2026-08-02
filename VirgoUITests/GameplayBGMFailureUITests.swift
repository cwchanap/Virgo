//
//  GameplayBGMFailureUITests.swift
//  VirgoUITests
//

import XCTest

final class GameplayBGMFailureUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        installSystemDialogHandlers()
        dismissSetupAssistantIfPresent()

        app = XCUIApplication()
        app.launchArguments.append("-UITesting")
        app.launchArguments.append("-ResetState")
        app.launchArguments.append("-UITestingBGMFailure")
        app.launch()
        activateLaunchedAppWindow(in: app)
        dismissSetupAssistantIfPresent(returningTo: app)
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    @MainActor
    func testGameplayPresentsBGMFailureAlert() throws {
        try openGameplay(in: app)

        guard let presentedAlert = waitForPresentedBGMAlert(timeout: 10) else {
            XCTFail("Expected a presented BGM failure element. Snapshot: \(app.debugDescription)")
            return
        }

        assertAccessibleText(
            containing: "Background Music Unavailable",
            in: presentedAlert,
            failureMessage: "The BGM failure alert title should be visible"
        )
        assertAccessibleText(
            containing: "UI test injected failure",
            in: presentedAlert,
            failureMessage: "The injected BGM failure should be visible in the alert"
        )
        assertAccessibleText(
            containing: "Playing with the metronome only.",
            in: presentedAlert,
            failureMessage: "The metronome-only fallback should be visible in the alert"
        )

        let okButton = presentedAlert.buttons["OK"]
        XCTAssertTrue(okButton.waitForExistence(timeout: 5), "The BGM failure alert should expose an OK button")
        okButton.tap()

        XCTAssertTrue(presentedAlert.waitForNonExistence(timeout: 5), "The BGM failure alert should dismiss")

        // Scope the gameplay-mounted check to a single Virgo window on macOS so a
        // stale/secondary window can't satisfy the assertion, matching the
        // sibling test in GameplayViewUITests.testGameplayDoesNotRenderTabShellSimultaneously.
        #if os(macOS)
        let gameplayWindows = app.windows.containing(.any, identifier: "gameplayRoot")
        XCTAssertEqual(
            gameplayWindows.count,
            1,
            "Gameplay should be mounted in exactly one Virgo window on macOS after dismissing the BGM failure alert"
        )
        let gameplayRoot = gameplayWindows.firstMatch.descendants(matching: .any)["gameplayRoot"]
        XCTAssertTrue(
            gameplayRoot.waitForExistence(timeout: 5),
            "Gameplay should remain mounted after dismissing the BGM failure alert"
        )
        #else
        XCTAssertTrue(
            app.descendants(matching: .any)["gameplayRoot"].waitForExistence(timeout: 5),
            "Gameplay should remain mounted after dismissing the BGM failure alert"
        )
        #endif

        XCTAssertFalse(
            app.otherElements["appTabShell"].exists,
            "Tab shell should not remain mounted after dismissing the BGM failure alert"
        )
        XCTAssertFalse(
            app.tabBars.firstMatch.exists,
            "Tab bar should not remain visible after dismissing the BGM failure alert"
        )
    }

    private func waitForPresentedBGMAlert(timeout: TimeInterval) -> XCUIElement? {
        let candidates = [
            app.alerts.firstMatch,
            app.sheets.firstMatch,
            app.dialogs.firstMatch,
            app.windows["Background Music Unavailable"]
        ]
        let candidateTimeout = timeout / Double(candidates.count)

        for candidate in candidates where candidate.waitForExistence(timeout: candidateTimeout) {
            if containsBGMFailureContent(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Validates that a candidate presentation actually contains the injected
    /// BGM failure sentinel before treating it as the BGM alert. Without this,
    /// an unrelated system sheet/dialog (the suite already handles setup
    /// assistants and system dialogs) could be selected and the test would
    /// prove the wrong presentation dismissed.
    private func containsBGMFailureContent(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(
            format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
            "UI test injected failure",
            "UI test injected failure"
        )
        return element.descendants(matching: .any)
            .matching(predicate)
            .firstMatch
            .waitForExistence(timeout: 2)
    }

    private func assertAccessibleText(
        containing substring: String,
        in presentedAlert: XCUIElement,
        failureMessage: String
    ) {
        let predicate = NSPredicate(
            format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
            substring,
            substring
        )
        // Search strictly beneath the validated presentation. An app-wide
        // fallback could find the sentinel in a different presentation and
        // produce a false positive when an unrelated sheet is also present.
        let scopedText = presentedAlert.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(scopedText.waitForExistence(timeout: 5), failureMessage)
    }
}
