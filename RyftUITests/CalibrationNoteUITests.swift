import XCTest

/// Today's note under a calibration that waiting won't end (design.md §7 rev. 2 §6), in demo mode with
/// `-RyftScenario blockedHRV` (API.md's example 3: Garmin Connect, no HRV, `devices.setup` on). The note is read
/// in the gauge's value, so the gauge is where its words are asserted; the link is its own button and opens the
/// tracker's card in a sheet with "Done". No snapshots.
final class CalibrationNoteUITests: XCTestCase {
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

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    @MainActor
    func testTheGaugeNamesGarminConnectAndTheSignalNotACounter() throws {
        let app = launch("blockedHRV")
        let gauge = element(app, "today.readinessGauge")
        XCTAssertTrue(gauge.waitForExistence(timeout: 60), "the readiness gauge")
        let value = gauge.value as? String ?? ""
        XCTAssertTrue(value.contains("Garmin Connect doesn't share HRV with Apple Health."), "the note, in the value: \(value)")
        XCTAssertFalse(value.contains("of 7"), "no counter: \(value)")
        XCTAssertFalse(app.staticTexts["Learning your baseline"].exists)
    }

    @MainActor
    func testTheLinkOpensGarminsCardAndDoneClosesIt() throws {
        let app = launch("blockedHRV")
        let link = app.buttons["today.gaugeNote.link"]
        XCTAssertTrue(link.waitForExistence(timeout: 60), "the link is a button of its own")
        XCTAssertEqual(link.label, "How to set up Garmin Connect")
        XCTAssertTrue(link.isHittable)
        link.tap()
        XCTAssertTrue(element(app, "tracker.card.garmin").waitForExistence(timeout: 30), "Garmin's card in the sheet")
        let done = app.buttons["today.calibrationSheet.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 30), "Done")
        done.tap()
        XCTAssertTrue(link.waitForExistence(timeout: 30) && link.isHittable, "back on Today")
        XCTAssertFalse(element(app, "tracker.card.garmin").exists, "the sheet is gone")
        XCTAssertFalse(done.exists)
    }

    /// No night yet: the empty gauge says what's missing, and the sentence is the night's; still no counter.
    @MainActor
    func testWithoutANightTheEmptyGaugeStillNamesTheSignal() throws {
        let app = launch("blockedNoNight")
        let gauge = element(app, "today.readinessGauge")
        XCTAssertTrue(gauge.waitForExistence(timeout: 60), "the readiness gauge")
        let value = gauge.value as? String ?? ""
        XCTAssertTrue(value.contains("No data") && value.contains("Garmin Connect"), "the empty gauge names it: \(value)")
        XCTAssertTrue(app.staticTexts["No readiness yet today. It appears once last night has synced."].exists)
        XCTAssertTrue(app.buttons["today.gaugeNote.link"].exists)
    }

    /// Learning, not blocked: the note counts its nights and has no link.
    @MainActor
    func testLearningHRVCountsNightsWithoutALink() throws {
        let app = launch("learningHRV")
        let gauge = element(app, "today.readinessGauge")
        XCTAssertTrue(gauge.waitForExistence(timeout: 60), "the readiness gauge")
        let value = gauge.value as? String ?? ""
        XCTAssertTrue(value.contains("Learning your HRV baseline: 0 of 7 nights."), "the note: \(value)")
        XCTAssertFalse(app.buttons["today.gaugeNote.link"].exists, "nothing to fix")
    }
}
