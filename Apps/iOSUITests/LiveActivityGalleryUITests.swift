import XCTest

/// Screenshots of the match Live Activity outside the app: the Dynamic Island (compact
/// and expanded), Notification Center and the Lock Screen, live and once the match is
/// won. Visual review only, so it runs only when the "Watch and Live Activity
/// screenshots" workflow asks for it (`TEST_RUNNER_CAPTURE_LIVE_ACTIVITY=1`).
final class LiveActivityGalleryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_LIVE_ACTIVITY"] == "1", "Screenshot-only test")
    }

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "pause")], timeout: seconds)
    }

    /// Long-presses the Dynamic Island so it expands.
    private func expandIsland() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 24))
            .press(forDuration: 1.2)
        pause(1.5)
    }

    private func dismissIsland() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap()
        pause(1)
    }

    private func lockAndCapture(_ name: String) {
        let device = XCUIDevice.shared
        let lock = NSSelectorFromString("pressLockButton")
        guard device.responds(to: lock) else { return }
        device.perform(lock)
        pause(2)
        // Wake the screen: the Lock Screen shows the activity.
        XCUIDevice.shared.press(.home)
        pause(2.5)
        capture(name)
    }

    func testCaptureLiveActivity() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-data"]
        app.launch()
        app.buttons["createTournamentButton"].tap()
        app.buttons["addPlayersButton"].tap()
        let field = app.textFields["playerNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        for name in ["Alex", "Lisa", "Johan", "Maja"] { field.typeText(name + "\n") }
        app.buttons["playersContinueButton"].tap()
        app.buttons["startTournamentButton"].tap()
        let openScore = app.buttons["openScore-court1"]
        XCTAssertTrue(openScore.waitForExistence(timeout: 5))
        openScore.tap()
        let pointA = app.buttons["pointTeamA"]
        let pointB = app.buttons["pointTeamB"]
        XCTAssertTrue(pointA.waitForExistence(timeout: 5))
        for side in [pointA, pointA, pointB, pointA, pointB, pointA, pointA, pointB, pointA, pointA, pointB, pointB] { side.tap() }
        pause(2)

        // Live: compact island, expanded island, Notification Center, Lock Screen.
        XCUIDevice.shared.press(.home)
        pause(4)
        capture("la-01-island-compact")
        expandIsland()
        capture("la-02-island-expanded")
        dismissIsland()
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0)).withOffset(CGVector(dx: 0, dy: 2))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))
        pause(2)
        capture("la-03-notification-center")
        XCUIDevice.shared.press(.home)
        pause(1)
        lockAndCapture("la-04-lock-screen")

        // Won: score until the total is reached, then look again.
        app.activate()
        XCTAssertTrue(pointA.waitForExistence(timeout: 10))
        for _ in 0..<40 where pointA.isHittable && pointA.isEnabled { pointA.tap() }
        pause(2)
        XCUIDevice.shared.press(.home)
        pause(4)
        capture("la-05-island-compact-won")
        expandIsland()
        capture("la-06-island-expanded-won")
        dismissIsland()
        lockAndCapture("la-07-lock-screen-won")
    }
}
