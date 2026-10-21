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
}
