import XCTest

/// End-to-end organiser journey on the iPhone app. Each run starts from empty data
/// (`-reset-data`) in a temporary folder, so it never touches real tournaments.
final class OrganiserJourneyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + (reset ? ["-reset-data"] : [])
        app.launch()
        return app
    }

    /// Finds any element by accessibility identifier, whatever its element type.
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Finds any element whose accessibility label contains the text.
    private func element(_ app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCreateScoreUndoFinishStandingsRelaunchResume() throws {
        var app = launch(reset: true)
        screenshot(app, "01-home-empty")

        // 1. Create a tournament.
        app.buttons["createTournamentButton"].tap()
        XCTAssertTrue(app.textFields["tournamentNameField"].waitForExistence(timeout: 5))
        screenshot(app, "02-create")

        // 2. Add players.
        app.buttons["addPlayersButton"].tap()
        let field = app.textFields["playerNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        for name in ["Alex", "Lisa", "Johan", "Maja", "Erik", "Daniel", "Sofia", "Fredrik"] {
            field.typeText(name + "\n")
        }
        screenshot(app, "03-players")
        app.buttons["playersContinueButton"].tap()

        // 3. Generate a valid schedule.
        let start = app.buttons["startTournamentButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isEnabled)
        start.tap()

        // 4. Start a match.
        let openScore = app.buttons["openScore-court1"]
        XCTAssertTrue(openScore.waitForExistence(timeout: 5))
        screenshot(app, "04-tournament-live")
        openScore.tap()

        // 5. Register points and 6. undo one.
        let pointA = app.buttons["pointTeamA"]
        XCTAssertTrue(pointA.waitForExistence(timeout: 5))
        pointA.tap()
        pointA.tap()
        pointA.tap()
        app.buttons["pointTeamB"].tap()
        XCTAssertEqual(element(app, "scoreLabel").label, "Score 3 to 1")
        app.buttons["undoButton"].tap()
        XCTAssertEqual(element(app, "scoreLabel").label, "Score 3 to 0")
        screenshot(app, "05-scoring")

        // 7. Finish the match by entering the final result (3–21 for a 24-point match).
        app.buttons["setScoreButton"].tap()
        let save = app.buttons["saveResultButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.buttons["correctResultButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "scoreLabel").label, "Score 3 to 21")
        screenshot(app, "06-match-finished")
        app.buttons["backToTournamentButton"].tap()

        // 8. Verify standings.
        let tabs = app.segmentedControls["tournamentTabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["Standings"].tap()
        XCTAssertTrue(element(app, labelContaining: "21 points").waitForExistence(timeout: 5), "the winners' 21 points appear in the standings")
        screenshot(app, "07-standings")

        // 9. Close and 10. reopen the app: the tournament can be resumed.
        app.terminate()
        app = launch(reset: false)
        let resume = app.buttons["resumeButton"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        screenshot(app, "08-home-resume")
        resume.tap()

        // 11. Correct a result.
        let schedule = app.segmentedControls["tournamentTabs"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        let reopenScore = app.buttons["openScore-court1"]
        XCTAssertTrue(reopenScore.waitForExistence(timeout: 5))
        let enterResult = app.buttons["enterResult-court2"]
        XCTAssertTrue(enterResult.exists, "court 2 has not been played yet")
        enterResult.tap()
        XCTAssertTrue(app.buttons["saveResultButton"].waitForExistence(timeout: 5))
        app.buttons["saveResultButton"].tap()

        // Standings now include both matches; sharing is available.
        schedule.buttons["Standings"].tap()
        let share = app.buttons["shareResultsButton"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        screenshot(app, "09-standings-share")
    }

    func testInvalidConfigurationIsExplained() throws {
        let app = launch(reset: true)
        app.buttons["createTournamentButton"].tap()
        app.buttons["addPlayersButton"].tap()
        let field = app.textFields["playerNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        for name in ["Alex", "Lisa", "Johan"] { field.typeText(name + "\n") }
        app.buttons["playersContinueButton"].tap()
        // Three players cannot fill a court: the primary action still asks for players.
        XCTAssertTrue(app.buttons["addPlayersButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startTournamentButton"].exists)
        // The explanation sits at the end of the form; scroll it into view (rows load lazily).
        let explanation = element(app, labelContaining: "needs at least 4 players")
        for _ in 0..<4 where !explanation.exists { app.swipeUp() }
        XCTAssertTrue(explanation.exists)
    }

    func testMainScreensExposeAccessibleControls() throws {
        let app = launch(reset: true)
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertEqual(settings.label, "Settings", "icon-only button has a spoken label")
        XCTAssertTrue(app.buttons["createTournamentButton"].isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        screenshot(app, "10-settings")
    }

    func testGamesAndSetsScoringWithLiveActivity() throws {
        let app = launch(reset: true)
        app.buttons["createTournamentButton"].tap()
        // The scoring options sit below the seven formats; rows load lazily, so scroll.
        let scoring = app.segmentedControls["scoringModePicker"]
        XCTAssertTrue(app.textFields["tournamentNameField"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !scoring.exists { app.swipeUp() }
        XCTAssertTrue(scoring.exists)
        scoring.buttons["Games & sets"].tap()
        screenshot(app, "11-create-sets")

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
        XCTAssertTrue(pointA.waitForExistence(timeout: 5))
        pointA.tap()
        XCTAssertEqual(element(app, "scoreLabel").label, "Points 15 to 0. Games 0 to 0.")
        pointA.tap()
        pointA.tap()
        app.buttons["pointTeamB"].tap()
        XCTAssertEqual(element(app, "scoreLabel").label, "Points 40 to 15. Games 0 to 0.")
        pointA.tap()
        XCTAssertEqual(element(app, "scoreLabel").label, "Points 0 to 0. Games 1 to 0.")
        app.buttons["undoButton"].tap()
        XCTAssertEqual(element(app, "scoreLabel").label, "Points 40 to 15. Games 0 to 0.")
        screenshot(app, "12-scoring-sets")

        // Enter a full result set by set.
        app.buttons["setScoreButton"].tap()
        let save = app.buttons["saveResultButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        screenshot(app, "13-sets-result-entry")
        save.tap()
        XCTAssertTrue(app.buttons["correctResultButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "setsSummary").label.contains("6-4"))
        screenshot(app, "14-sets-finished")
    }

    func testLiveActivityAppearsOutsideTheApp() throws {
        let app = launch(reset: true)
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
        XCTAssertTrue(pointA.waitForExistence(timeout: 5))
        for _ in 0..<5 { pointA.tap() }
        app.buttons["pointTeamB"].tap()
        XCTAssertEqual(element(app, "scoreLabel").label, "Score 5 to 1")
        sleep(2)
        // Leave the app: the Live Activity is now shown in the Dynamic Island.
        XCUIDevice.shared.press(.home)
        sleep(5)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "15-dynamic-island"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.activate()
        XCTAssertTrue(app.buttons["pointTeamA"].waitForExistence(timeout: 5))
    }
}
