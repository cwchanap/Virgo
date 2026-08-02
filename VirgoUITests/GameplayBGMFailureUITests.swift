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

        // Verify dismissal via the OK button and sentinel text rather than the
        // container itself. The window fallback in `waitForPresentedBGMAlert`
        // uses `containing`, which can match the persistent gameplay window when
        // the alert is presented beneath its accessibility tree on macOS;
        // requiring that container to cease existing would wait for the gameplay
        // window to disappear and fail on the very path the fallback supports.
        // The OK button and sentinel text are scoped to the alert and reliably
        // disappear once it dismisses, regardless of which container candidate
        // was returned.
        XCTAssertTrue(
            okButton.waitForNonExistence(timeout: 5),
            "The BGM failure alert OK button should disappear after tapping OK"
        )
        let sentinelText = presentedAlert
            .descendants(matching: .any)
            .matching(bgmFailureSentinelPredicate())
            .firstMatch
        XCTAssertTrue(
            sentinelText.waitForNonExistence(timeout: 5),
            "The BGM failure sentinel text should disappear after dismissing the alert"
        )

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
        // Filter each container query by the BGM failure sentinel before
        // selecting firstMatch. An unfiltered `firstMatch` only ever inspects
        // the first presentation of each type, so it would miss the BGM alert
        // when an unrelated sheet/dialog is presented first; and a generic
        // firstMatch query can retarget to a different presentation after the
        // BGM alert dismisses, making waitForNonExistence fail. The
        // sentinel-filtered query finds the correct presentation regardless of
        // ordering and stays semantically tied to the BGM failure across
        // dismissal.
        let sentinelPredicate = bgmFailureSentinelPredicate()
        let candidates = [
            app.alerts.containing(sentinelPredicate).firstMatch,
            app.sheets.containing(sentinelPredicate).firstMatch,
            app.dialogs.containing(sentinelPredicate).firstMatch,
            app.windows.containing(sentinelPredicate).firstMatch
        ]
        let candidateTimeout = timeout / Double(candidates.count)

        for candidate in candidates where candidate.waitForExistence(timeout: candidateTimeout) {
            return candidate
        }
        return nil
    }

    /// The BGM failure sentinel predicate — matches any element whose label or
    /// value contains the UI-test-injected failure string. Shared by the
    /// presentation lookup and the dismissal verification so both stay tied to
    /// the same sentinel.
    private func bgmFailureSentinelPredicate() -> NSPredicate {
        NSPredicate(
            format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
            "UI test injected failure",
            "UI test injected failure"
        )
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
