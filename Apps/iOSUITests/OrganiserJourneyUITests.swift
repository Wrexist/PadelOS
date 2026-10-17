import XCTest

/// End-to-end organiser journey on the iPhone app. Each run starts from empty data
/// (`-reset-data`) in a temporary folder, so it never touches real tournaments.
final class OrganiserJourneyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The app, in the language CI asks for (`TEST_RUNNER_UITEST_LANGUAGE=es`), else the
    /// simulator's language.
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        if let language = ProcessInfo.processInfo.environment["UITEST_LANGUAGE"], !language.isEmpty {
            let locale = ProcessInfo.processInfo.environment["UITEST_LOCALE"] ?? language
            app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        }
        return app
    }

    private func launch(reset: Bool) -> XCUIApplication {
        let app = makeApp()
        app.launchArguments += ["-ui-testing"] + (reset ? ["-reset-data"] : [])
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

    /// Lets an animation settle before a screenshot.
    private func settle(_ seconds: TimeInterval = 1.5) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }

    func testOnboardingPagesAndGetStarted() throws {
        let app = makeApp()
        app.launchArguments += ["-ui-testing", "-reset-data", "-show-onboarding"]
        app.launch()
        let next = element(app, "onboardingContinue")
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "onboardingSkip").exists)
        for page in 1...4 {
            settle()
            screenshot(app, "onboarding-\(page)")
            element(app, "onboardingContinue").tap()
        }
        let getStarted = element(app, "onboardingGetStarted")
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "onboardingSkip").exists)
        settle()
        screenshot(app, "onboarding-5")
        getStarted.tap()
        XCTAssertTrue(app.buttons["createTournamentButton"].waitForExistence(timeout: 5))
    }

    func testPlayoffBracketIsShown() throws {
        let app = makeApp()
        app.launchArguments += ["-ui-testing", "-reset-data", "-demo-playoffs"]
        app.launch()
        let row = element(app, labelContaining: "Friday Playoffs")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        settle(1)
        screenshot(app, "playoffs-live")
        // Segments are mirrored in right-to-left languages, so find the standings tab by
        // what it shows rather than by position.
        let bracket = element(app, "bracket")
        for index in 0..<tabs.buttons.count where !bracket.exists {
            tabs.buttons.element(boundBy: index).tap()
            _ = bracket.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(bracket.waitForExistence(timeout: 5))
        settle(1)
        screenshot(app, "playoffs-bracket")
    }

    func testPlayerStatsLeaderboardAndHistory() throws {
        let app = makeApp()
        app.launchArguments += ["-ui-testing", "-reset-data", "-demo-playoffs"]
        app.launch()
        XCTAssertTrue(element(app, labelContaining: "Friday Playoffs").waitForExistence(timeout: 10))
        let players = app.buttons["playersButton"]
        XCTAssertTrue(players.waitForExistence(timeout: 5))
        for _ in 0..<4 where !players.isHittable { app.swipeUp() }
        players.tap()

        // Leaderboard of the demo's eight players, sortable.
        XCTAssertTrue(element(app, "playersLeaderboard").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "playerRow-8").exists, "all eight demo players are listed")
        XCTAssertTrue(element(app, "playersSortPicker").exists)
        settle(1)
        screenshot(app, "16-players-leaderboard")

        // Player screen: stats, form and the tournament in the history.
        element(app, "playerRow-1").tap()
        XCTAssertTrue(element(app, "playerDetailHeader").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "playerForm").exists)
        settle(1)
        screenshot(app, "17-player-detail")
        let history = element(app, "playerHistory")
        for _ in 0..<4 where !history.isHittable { app.swipeUp() }
        XCTAssertTrue(history.exists)
        screenshot(app, "18-player-history")
        let tournament = history.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Friday Playoffs")).firstMatch
        XCTAssertTrue(tournament.exists)
        tournament.tap()
        XCTAssertTrue(app.segmentedControls["tournamentTabs"].waitForExistence(timeout: 5), "the history links to the tournament")
    }

    func testOnboardingCanBeSkipped() throws {
        let app = makeApp()
        app.launchArguments += ["-ui-testing", "-reset-data", "-show-onboarding"]
        app.launch()
        let skip = element(app, "onboardingSkip")
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(app.buttons["createTournamentButton"].waitForExistence(timeout: 5))
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

    // MARK: - App Store screenshots

    /// Demo tournament names per language for the App Store screenshots.
    private static let storeDemoNames: [String: (live: String, playoff: String, history: String)] = [
        "en": ("Thursday Padel", "Club Finals", "Mexicano Night|Sunday Americano"),
        "es": ("Americano del jueves", "Final del club", "Noche Mexicano|Americano del domingo"),
        "sv": ("Torsdagspadel", "Klubbfinal", "Mexicanokväll|Söndagsamericano"),
        "fr": ("Padel du jeudi", "Finale du club", "Soirée Mexicano|Americano du dimanche"),
        "de": ("Padel am Donnerstag", "Clubfinale", "Mexicano-Abend|Sonntags-Americano"),
        "it": ("Padel del giovedì", "Finale del club", "Serata Mexicano|Americano della domenica"),
        "pt-BR": ("Padel de quinta", "Final do clube", "Noite Mexicano|Americano de domingo"),
        "nl": ("Padel op donderdag", "Clubfinale", "Mexicano-avond|Zondag-americano"),
    ]

    /// Raw screens for the App Store screenshots (`scripts/store/compose_screenshots.py`).
    /// Runs only from the Store screenshots workflow (`STORE_SCREENSHOTS=1`). Each screen is
    /// opened by the app itself from `-demoScreen <name>`, so this test does not depend on
    /// the layout and keeps working after a redesign.
    func testStoreScreenshots() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["STORE_SCREENSHOTS"] == "1", "Only run by the Store screenshots workflow")
        let language = environment["UITEST_LANGUAGE"] ?? "en"
        let names = Self.storeDemoNames[language] ?? Self.storeDemoNames[String(language.prefix(2))] ?? Self.storeDemoNames["en"]!
        var screens = (environment["STORE_SCREENS"] ?? "").split(separator: " ").map(String.init)
        if screens.isEmpty {
            screens = ["home", "live", "schedule", "standings", "invite", "leaderboard", "playoffs", "players", "player", "create", "scoring"]
        }

        for screen in screens {
            let app = makeApp()
            app.launchArguments += ["-ui-testing", "-reset-data", "-demo-store", "-demoScreen", screen,
                                    "-demoLiveName", names.live, "-demoPlayoffName", names.playoff,
                                    "-demoHistoryNames", names.history, "-demoPlayer", "Sofia"]
            app.launch()
            settle(["playoffs", "invite", "leaderboard", "player"].contains(screen) ? 4 : 3)
            screenshot(app, "store-\(screen)")
            if screen == "scoring" {
                captureLiveActivity(app)
            }
            app.terminate()
        }
    }

    /// The scoring screen started a Live Activity: capture it in the Dynamic Island (compact
    /// and expanded) and on the Lock Screen. Best effort; nothing here fails the test.
    private func captureLiveActivity(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        sleep(3)
        // The first activity asks for permission in Notification Center: allow it there.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0)).withOffset(CGVector(dx: 0, dy: 2))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))
        sleep(2)
        let allowFirst = springboard.buttons["Allow"]
        if allowFirst.waitForExistence(timeout: 3) { allowFirst.tap() }
        sleep(1)
        XCUIDevice.shared.press(.home)
        sleep(3)
        screenshotScreen("store-island")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).press(forDuration: 1.5)
        sleep(2)
        screenshotScreen("store-island-expanded")
        XCUIDevice.shared.press(.home)
        sleep(2)
        let lock = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: lock) else { return }
        XCUIDevice.shared.perform(lock)
        sleep(3)
        screenshotScreen("store-lock")
        // Wake the screen without unlocking: the Lock Screen with the activity.
        XCUIDevice.shared.perform(lock)
        sleep(3)
        screenshotScreen("store-lock-wake")
        // A fresh simulator asks to allow Live Activities and shows a welcome notification;
        // answer and clear them, then lock and wake again for a clean Lock Screen.
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) {
            allow.tap()
            sleep(2)
        }
        let notice = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Apple Intelligence")).firstMatch
        if notice.exists && notice.isHittable {
            notice.swipeLeft()
            let clear = springboard.buttons["Clear"]
            if clear.waitForExistence(timeout: 2) { clear.tap() }
            sleep(2)
        }
        XCUIDevice.shared.perform(lock)
        sleep(2)
        XCUIDevice.shared.perform(lock)
        sleep(3)
        screenshotScreen("store-lock-clean")
    }

    private func screenshotScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
