import XCTest

/// Today's in-between states in demo mode (`-RyftScenario`): the first import's card and the
/// pending gauge, found by what they say and their identifiers. No snapshots.
final class TodayStatesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftTab", "today", "-appearance", "dark",
                               "-coachMarks.today.done", "YES", "-RyftScenario", scenario,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor
    func testFirstImportShowsTheSetupCardInsteadOfTheGauge() throws {
        let app = launch("import")
        XCTAssertTrue(app.staticTexts["Setting up RYFT"].waitForExistence(timeout: 15), "the import card")
        XCTAssertTrue(app.staticTexts["You can leave the app — RYFT keeps going in the background."].exists)
        XCTAssertTrue(app.staticTexts["Tell me when my first scores are ready"].exists, "the push question, here")
        XCTAssertTrue(app.staticTexts["Uploading 12,400 readings"].exists, "the status line")
        XCTAssertFalse(app.descendants(matching: .any)["today.pendingGauge"].exists)
    }

    @MainActor
    func testPendingNightShowsTheOutlineGaugeAndLastNightUnscored() throws {
        let app = launch("pending")
        let gauge = app.descendants(matching: .any)["today.pendingGauge"]
        XCTAssertTrue(gauge.waitForExistence(timeout: 15), "the pending gauge")
        XCTAssertTrue((gauge.value as? String ?? "").contains("Not scored yet"), "says it isn't scored")
        XCTAssertTrue(app.descendants(matching: .any)["today.rawNight"].exists, "last night from Apple Health")
        XCTAssertTrue(app.staticTexts["Scoring your night"].exists, "the status line")
        XCTAssertFalse(app.staticTexts["Setting up RYFT"].exists)
    }

    /// 09:12, Garmin Connect quiet since 23:24 (HealthKit's "Connect"): the night hint names the app, offers
    /// its App Store page, says it once (no gauge line under it), and nothing says it's scoring.
    @MainActor
    func testNightNotInAppleHealthNamesTheAppAndNeverSaysScoring() throws {
        let app = launch("nightGap")
        let hint = app.descendants(matching: .any)["today.nightHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 15), "the night hint")
        XCTAssertTrue(app.staticTexts["Your night hasn't reached Apple Health yet. Open Garmin Connect to sync it."].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Last data from Garmin Connect: '"))
                        .firstMatch.exists, "the data's age")
        let store = app.buttons["today.nightHint.action"]
        XCTAssertTrue(store.exists, "the App Store button")
        XCTAssertEqual(store.label, "Garmin Connect in the App Store")
        XCTAssertFalse(app.staticTexts["Scoring your latest data"].exists)
        XCTAssertFalse(app.staticTexts["Scoring your night"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Connect app'")).firstMatch.exists,
                       "never HealthKit's bare name")
        XCTAssertFalse(app.descendants(matching: .any)["today.watchHint"].exists, "one hint, never both")
        XCTAssertFalse(app.staticTexts["Last night hasn't reached RYFT yet."].exists, "the header says what the number is")
        XCTAssertTrue(app.staticTexts["Yesterday's readiness, until last night is scored."].exists)
    }

    /// Ten minutes against an estimate of 20 s: "Taking longer than usual · Details", the gauge static, and the
    /// line opens Sync details.
    @MainActor
    func testSlowScoringSaysTakingLongerWithDetails() throws {
        let app = launch("scoringSlow")
        let line = app.buttons["today.syncLine.line"]
        XCTAssertTrue(line.waitForExistence(timeout: 15), "the status line")
        XCTAssertTrue(app.staticTexts["Taking longer than usual · Details"].waitForExistence(timeout: 5), "line 5b")
        let gauge = app.descendants(matching: .any)["today.pendingGauge"]
        XCTAssertTrue((gauge.value as? String ?? "").contains("Still scoring your night"), "the gauge, in its own words")
        XCTAssertFalse(app.staticTexts["Scoring your night"].exists)
        line.tap()
        XCTAssertTrue(app.navigationBars["Sync details"].waitForExistence(timeout: 5), "Details: Sync details")
    }
}
