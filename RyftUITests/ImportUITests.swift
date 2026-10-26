import XCTest

/// The training import end to end in demo mode (ui.md §12.2): demo's remote config has `train.import` on, the
/// platform is the in-memory fake, and `-uiTestImportFiles` hands the flow demo's synthetic files in place of the
/// system picker (which UI tests can't drive). English, pinned by the launch.
final class ImportUITests: XCTestCase {
    /// Generous: a cold simulator on CI loads Today first.
    private let wait: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// `-RyftResetTrain YES`: no saved import job and no remembered matches from an earlier run.
    private func launch(files: String) -> XCUIApplication {
        launchDemo(extra: ["-uiTestImportFiles", files, "-RyftResetTrain", "YES"])
    }

    /// Strain → My plans → New plan → Import from file, with both menu items there.
    private func openImport(_ app: XCUIApplication) {
        let strain = app.tabBars.buttons["Strain"]
        XCTAssertTrue(strain.waitForExistence(timeout: wait), "the Strain tab")
        strain.tap()
        let plans = app.buttons["train.plans"]
        XCTAssertTrue(plans.waitForExistence(timeout: wait), "My plans")
        app.reveal(plans)
        plans.tap()
        let newPlan = app.buttons["plans.newPlan"]
        XCTAssertTrue(newPlan.waitForExistence(timeout: wait), "New plan as a menu")
        app.reveal(newPlan)
        newPlan.tap()
        XCTAssertTrue(app.buttons["Start from scratch"].waitForExistence(timeout: wait), "the builder's item")
        let item = app.buttons["Import from file"]
        XCTAssertTrue(item.exists, "the import's item")
        item.tap()
        XCTAssertTrue(app.buttons["import.choose"].waitForExistence(timeout: wait), "step 1")
    }

    private func tapContinue(_ app: XCUIApplication, _ message: String) {
        let button = app.buttons["import.continue"]
        XCTAssertTrue(button.waitForExistence(timeout: wait), message)
        XCTAssertTrue(waitUntil(button, isEnabled: true), "\(message): Continue enabled")
        button.tap()
    }

    /// Scrolls until `element` sits clear of the pinned bottom bar (an element under a `safeAreaInset` bar still
    /// reports itself hittable, and the tap would land on the bar).
    private func revealAboveBar(_ element: XCUIElement, in app: XCUIApplication) {
        let limit = app.windows.firstMatch.frame.maxY - 220
        var tries = 0
        while element.frame.maxY > limit && tries < 10 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
    }

    private func waitUntil(_ element: XCUIElement, isEnabled: Bool) -> Bool {
        // Already there: no predicate wait (each one polls for about 2 s).
        if element.isEnabled == isEnabled { return true }
        let done = expectation(for: NSPredicate(format: "enabled == %@", NSNumber(value: isEnabled)), evaluatedWith: element)
        return XCTWaiter.wait(for: [done], timeout: wait) == .completed
    }

    /// Pick → detected → choose → map (with the bodyweight question) → preview → import → the result's counts.
    func testImportPlanAndHistoryFromDemoFiles() throws {
        let app = launch(files: "plans.csv,workouts.csv")
        openImport(app)
        app.buttons["import.choose"].tap()

        // Step 2: the counts first.
        let summary = app.otherElements["import.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: wait), "step 2's summary")
        XCTAssertTrue(summary.label.contains("1 plan, 2 days, 6 exercises"), summary.label)
        XCTAssertTrue(summary.label.contains("4 workouts"), summary.label)
        tapContinue(app, "step 2")

        // Step 3: demo data has an active plan, so the import doesn't replace it unless asked.
        let makeActive = app.switches["import.makeActive"]
        XCTAssertTrue(makeActive.waitForExistence(timeout: wait), "step 3's make-active switch")
        XCTAssertEqual(makeActive.value as? String, "0", "make active starts off with a plan active")
        tapContinue(app, "step 3")

        // Step 4: one likely match to check and one new exercise block Continue; the bodyweight question doesn't.
        let left = app.staticTexts["import.leftToCheck"]
        XCTAssertTrue(left.waitForExistence(timeout: wait), "step 4's left-to-check line")
        XCTAssertEqual(left.label, "2 left to check.")
        XCTAssertFalse(app.buttons["import.continue"].isEnabled, "Continue waits for the rows")
        let accept = app.buttons["import.accept"]
        XCTAssertTrue(accept.exists, "Accept 1 likely match")
        accept.tap()
        let muscle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'import.muscle.'")).firstMatch
        XCTAssertTrue(muscle.waitForExistence(timeout: wait), "the new row's muscle menu")
        revealAboveBar(muscle, in: app)
        muscle.tap()
        let hamstrings = app.buttons["Hamstrings"]
        XCTAssertTrue(hamstrings.waitForExistence(timeout: wait), "the muscle groups")
        hamstrings.tap()
        let added = app.buttons["import.bodyweight.added"]
        XCTAssertTrue(added.waitForExistence(timeout: wait), "the bodyweight question")
        revealAboveBar(added, in: app)
        added.tap()
        waitForAbsence(of: left, timeout: wait, "nothing left to check")
        tapContinue(app, "step 4")

        // Step 5: the duplicate of demo's own workout is flagged and off; the rest is sent.
        let importButton = app.buttons["import.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: wait), "step 5's Import")
        XCTAssertTrue(waitUntil(importButton, isEnabled: true), "Import enabled")
        XCTAssertEqual(importButton.label, "Import 1 plan and 3 workouts")
        importButton.tap()

        // Step 6: the result's sentence and counts.
        let result = app.staticTexts["import.result"]
        XCTAssertTrue(result.waitForExistence(timeout: wait), "step 6's result")
        XCTAssertTrue(result.label.hasPrefix("Imported 1 plan and 3 workouts"), result.label)
        XCTAssertTrue(result.label.contains("1 set skipped"), result.label)
        let openPlan = app.buttons["import.openPlan"]
        XCTAssertTrue(openPlan.exists, "Open plan")
        openPlan.tap()
        XCTAssertTrue(app.navigationBars["Upper/Lower Base"].waitForExistence(timeout: wait), "the imported plan on Strain")
    }

    /// D5: a file that isn't an export says so on step 2, with no Continue.
    func testUnsupportedFileSaysSo() {
        let app = launch(files: "garbage.txt")
        openImport(app)
        app.buttons["import.choose"].tap()
        XCTAssertTrue(app.staticTexts["import.unsupported"].waitForExistence(timeout: wait), "This isn't a supported format")
        XCTAssertFalse(app.buttons["import.continue"].exists)
        XCTAssertTrue(app.buttons["import.chooseAnother"].exists)
    }

    /// N1: Cancel from step 3 asks first; Discard closes the import.
    func testCancelAsksBeforeDiscarding() {
        let app = launch(files: "plans.csv,workouts.csv")
        openImport(app)
        app.buttons["import.choose"].tap()
        tapContinue(app, "step 2")
        XCTAssertTrue(app.switches["import.makeActive"].waitForExistence(timeout: wait), "step 3")
        app.buttons["import.cancel"].tap()
        let discard = app.alerts.buttons["Discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: wait), "the discard alert")
        discard.tap()
        XCTAssertTrue(app.buttons["plans.newPlan"].waitForExistence(timeout: wait), "back on My plans")
    }
}
