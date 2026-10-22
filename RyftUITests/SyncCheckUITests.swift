import XCTest

/// Check sync on the Garmin-like mock (`-RyftScreen sync-check -RyftSyncCheck <scenario>`, demo mode): what each
/// row says and the fix, found by identifiers and words. No snapshots, no HealthKit.
final class SyncCheckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftScreen", "sync-check", "-RyftSyncCheck", scenario,
                               "-appearance", "dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func row(_ app: XCUIApplication, _ signal: String) -> XCUIElement {
        app.descendants(matching: .any)["check.row.\(signal)"]
    }

    /// Waits until the element's VoiceOver value matches `predicate` (the rows resolve one after the other).
    private func value(of element: XCUIElement, _ predicate: String) -> Bool {
        let resolved = expectation(for: NSPredicate(format: "value \(predicate)"), evaluatedWith: element)
        return XCTWaiter.wait(for: [resolved], timeout: 15) == .completed
    }

    @MainActor
    func testGarminShowsHRVAndRestingHeartRateAsNotShared() throws {
        let app = launch("garmin")
        // Steps is the last row to resolve: then every row has its result.
        XCTAssertTrue(value(of: row(app, "steps"), "BEGINSWITH 'Arriving'"), "the check finished")
        XCTAssertEqual(row(app, "hrv").value as? String, "Not shared by Garmin Connect, expected")
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
        let text = "No data from Garmin Connect yet. Open Garmin Connect and let it sync, then tap Check again."
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Garmin Connect in the App Store"].exists, "the App Store page, named as such")
        XCTAssertTrue(app.descendants(matching: .any)["check.permission"].exists, "the permission card, last")
    }

    @MainActor
    func testSleepThatShouldArriveShowsTheFix() throws {
        let app = launch("garminSleepOff")
        XCTAssertTrue(value(of: row(app, "sleep"), "== 'Should arrive, nothing yet. Fix available'"))
        XCTAssertTrue(value(of: row(app, "steps"), "BEGINSWITH 'Arriving'"), "the check finished")
        XCTAssertTrue(app.staticTexts["RYFT can read sleep, but none came from Garmin Connect in the last 2 days."].exists)
        XCTAssertTrue(app.staticTexts["3 of 4 expected signals are arriving. 1 needs a fix."].waitForExistence(timeout: 5),
                      "the summary")
        XCTAssertFalse(app.descendants(matching: .any)["check.mayNotRead"].exists, "RYFT sees sleep elsewhere")
    }

    @MainActor
    func testNothingReadableGivesTheStrongHint() throws {
        let app = launch("nothingReadable")
        let hint = "Even your iPhone's steps aren't arriving, so RYFT may not be allowed to read Health."
        XCTAssertTrue(app.staticTexts[hint].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Open Health"].exists)
    }
}
