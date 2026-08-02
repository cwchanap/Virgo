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
        XCTAssertTrue(
            app.descendants(matching: .any)["gameplayRoot"].exists,
            "Gameplay should remain mounted after dismissing the BGM failure alert"
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
            return candidate
        }
        return nil
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
        let scopedText = presentedAlert.descendants(matching: .any).matching(predicate).firstMatch
        if scopedText.waitForExistence(timeout: 5) {
            return
        }

        let appText = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(appText.waitForExistence(timeout: 5), failureMessage)
    }
}
