import XCTest

/// Check sync on the Garmin-like mock (`-RyftScreen syncCheck -RyftSyncCheck <scenario>`, demo mode): what each
/// row says and the fix, found by identifiers and words. No snapshots, no HealthKit.
final class SyncCheckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftScreen", "syncCheck", "-RyftSyncCheck", scenario,
                               "-appearance", "dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func row(_ app: XCUIApplication, _ signal: String) -> XCUIElement {
        app.descendants(matching: .any)["check.row.\(signal)"]
    }

    /// Waits for the check to finish: Check again is enabled again.
    private func finished(_ app: XCUIApplication) -> Bool {
        let run = app.buttons["check.run"]
        guard run.waitForExistence(timeout: 15) else { return false }
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: run)
        return XCTWaiter.wait(for: [enabled], timeout: 15) == .completed
    }

    @MainActor
    func testGarminShowsHRVAndRestingHeartRateAsNotShared() throws {
        let app = launch("garmin")
        XCTAssertTrue(finished(app), "the check finished")
        let hrv = row(app, "hrv")
        XCTAssertTrue(hrv.waitForExistence(timeout: 5))
        XCTAssertEqual(hrv.value as? String, "Not shared by Garmin Connect, expected")
        XCTAssertEqual(row(app, "resting_hr").value as? String, "Not shared by Garmin Connect, expected")
        XCTAssertTrue((row(app, "heart_rate").value as? String ?? "").hasPrefix("Arriving"), "heart rate arrives")
        XCTAssertTrue((row(app, "sleep").value as? String ?? "").hasPrefix("Arriving"), "sleep arrives")
        XCTAssertTrue(app.staticTexts["That's normal."].exists)
        XCTAssertFalse(app.descendants(matching: .any)["check.fix"].exists, "nothing to fix")
        XCTAssertFalse(app.descendants(matching: .any)["check.permission"].exists)
    }

    @MainActor
    func testASilentTrackerSaysToOpenItsApp() throws {
        let app = launch("garminSilent")
        XCTAssertTrue(finished(app), "the check finished")
        let text = "No data from Garmin Connect yet. Open Garmin Connect and let it sync, then tap Check again."
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Garmin Connect"].exists, "the App Store page")
        XCTAssertTrue(app.descendants(matching: .any)["check.permission"].exists, "the permission card, last")
    }

    @MainActor
    func testSleepThatShouldArriveShowsTheFix() throws {
        let app = launch("garminSleepOff")
        XCTAssertTrue(finished(app), "the check finished")
        let sleep = row(app, "sleep")
        XCTAssertTrue(sleep.waitForExistence(timeout: 5))
        XCTAssertEqual(sleep.value as? String, "Should arrive, nothing yet. Fix available")
        XCTAssertTrue(app.staticTexts["RYFT can read sleep, but none came from Garmin Connect in the last 2 days."].exists)
        XCTAssertTrue(app.staticTexts["3 of 4 expected signals are arriving. 1 needs a fix."].exists, "the summary")
        XCTAssertFalse(app.descendants(matching: .any)["check.mayNotRead"].exists, "RYFT sees sleep elsewhere")
    }

    @MainActor
    func testNothingReadableGivesTheStrongHint() throws {
        let app = launch("nothingReadable")
        XCTAssertTrue(finished(app), "the check finished")
        let hint = "Even your iPhone's steps aren't arriving, so RYFT may not be allowed to read Health."
        XCTAssertTrue(app.staticTexts[hint].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Health permissions"].exists)
    }
}
