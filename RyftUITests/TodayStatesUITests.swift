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

    /// The gauge assembles at launch (design.md §10) without holding Today back: today's readiness is on screen soon
    /// after `launch()` returns, in demo mode on the scored day. The gauge's accessibility element carries the number
    /// from the first frame (VoiceOver isn't delayed by the entrance). The brief's budget is 1.5 s; XCUITest's own first
    /// query takes about 1.15 s on an idle simulator with or without the entrance (measured 2026-10-30), so the
    /// assertion allows `budget` for a loaded CI runner. The regression check is the launch profile against `main`
    /// (docs/work/2026-10-29-orbit-gauge/perf-*.md); the timing is attached for comparison.
    @MainActor
    func testReadinessIsOnScreenSoonAfterLaunch() throws {
        let budget: TimeInterval = 3
        let started = Date()
        let app = launchDemo()
        let launched = Date()
        let gauge = app.descendants(matching: .any)["today.readinessGauge"]
        let appeared = gauge.waitForExistence(timeout: budget)
        let found = Date()
        let timing = String(format: "launch() %.2f s, then the gauge %.2f s (%.2f s in all)",
                            launched.timeIntervalSince(started), found.timeIntervalSince(launched),
                            found.timeIntervalSince(started))
        let attachment = XCTAttachment(string: timing)
        attachment.name = "Today readiness after launch"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(appeared, "the readiness gauge within \(budget) s: \(timing)")
        let value = gauge.value as? String ?? ""
        XCTAssertTrue(value.first?.isNumber == true, "today's number, not a placeholder: \(value)")
        XCTAssertTrue(app.windows.firstMatch.frame.intersects(gauge.frame), "on screen: \(gauge.frame)")
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
        // One element, the sentence then the data's age (design.md §D3.5); the action is the second.
        let sentence = app.staticTexts.containing(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS 'Last data from Garmin Connect: '",
            "Your night hasn't reached Apple Health yet. Open Garmin Connect to sync it.")).firstMatch
        XCTAssertTrue(sentence.exists, "the sentence and the data's age")
        // Garmin Connect isn't installed on the simulator: canOpenURL says no, so the App Store page.
        assertHintElements(app, "today.nightHint", sentence: sentence, action: "Garmin Connect in the App Store")
        XCTAssertFalse(app.staticTexts["Scoring your latest data"].exists)
        XCTAssertFalse(app.staticTexts["Scoring your night"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Connect app'")).firstMatch.exists,
                       "never HealthKit's bare name")
        XCTAssertFalse(app.descendants(matching: .any)["today.watchHint"].exists, "one hint, never both")
        XCTAssertFalse(app.staticTexts["Last night hasn't reached RYFT yet."].exists, "the header says what the number is")
        XCTAssertTrue(app.staticTexts["Yesterday's readiness, until last night is scored."].exists)
    }

    /// A quiet Garmin Connect (14 h): the catalog's sentence on how it syncs replaces "Open the … app" (design.md §D3.4),
    /// and VoiceOver reads the sentence, then the action (§D3.5).
    @MainActor
    func testQuietTrackerHintSaysHowItSyncsThenOffersTheApp() throws {
        let app = launch("watch")
        let hint = app.descendants(matching: .any)["today.watchHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 15), "the quiet hint")
        let sentence = app.staticTexts.containing(NSPredicate(
            format: "label BEGINSWITH 'Nothing new from Garmin Connect since ' AND label CONTAINS %@",
            "Garmin Connect passes data to Apple Health only while it's open.")).firstMatch
        XCTAssertTrue(sentence.exists, "the sentence with the catalog's sync sentence")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Open the Garmin Connect app'"))
                        .firstMatch.exists, "the shipped tail is replaced")
        // Not installed on the simulator: the App Store page. "Open Garmin Connect" needs the app (a device check).
        assertHintElements(app, "today.watchHint", sentence: sentence, action: "Garmin Connect in the App Store")
    }

    /// Two VoiceOver elements: the sentence as static text, never a button; then exactly one button, the action.
    private func assertHintElements(_ app: XCUIApplication, _ id: String, sentence: XCUIElement, action label: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let action = app.buttons.matching(identifier: "\(id).action")
        XCTAssertEqual(action.count, 1, "one action", file: file, line: line)
        XCTAssertEqual(action.firstMatch.elementType, .button, file: file, line: line)
        XCTAssertEqual(action.firstMatch.label, label, file: file, line: line)
        XCTAssertEqual(sentence.elementType, .staticText, file: file, line: line)
        XCTAssertNotEqual(sentence.identifier, "\(id).action", "the sentence isn't the action", file: file, line: line)
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label == %@", sentence.label)).firstMatch.exists,
                       "the sentence isn't a button", file: file, line: line)
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
