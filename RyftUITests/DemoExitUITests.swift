import XCTest

/// P1b (ADR 0019, design §8 AC11): Profile → Demo data off with a demo workout in progress asks first. Keep leaves the
/// demo and its workout; Discard turns Demo data off, and with no account signed in (UI test simulators have none) that
/// is Welcome. A relaunch in the demo, keeping Train's store, finds no workout to resume: the discard took it, not
/// only the screen. Demo mode (no server, no HealthKit), English; every wait is on a condition, never a sleep.
final class DemoExitUITests: XCTestCase {
    private let patience: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// `resetTrain`: start without sessions or a queue. Without it Train keeps what the last launch stored.
    private func launch(resetTrain: Bool = true) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftTab", "strain", "-coachMarks.today.done", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            + (resetTrain ? ["-RyftResetTrain", "YES"] : [])
        app.launch()
        return app
    }

    /// Profile → the Demo data switch, scrolled until it sits above the tab bar: far down the page it reports itself
    /// hittable while still off screen (seen on 27.2, frame below the window), so its frame decides.
    private func demoSwitch(in app: XCUIApplication) -> XCUIElement {
        app.tabBars.buttons["Profile"].tap()
        let toggle = app.switches["profile.demoMode"]
        XCTAssertTrue(toggle.waitForExistence(timeout: patience), "Profile → Demo data")
        let bottom = app.tabBars.firstMatch.frame.minY
        for _ in 0..<15 where !toggle.isHittable || toggle.frame.maxY >= bottom { app.swipeUp() }
        XCTAssertLessThan(toggle.frame.maxY, bottom, "the switch is above the tab bar")
        return toggle
    }

    /// The switch itself, at the row's trailing end (the middle is its label).
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    /// A dialog button by its identifier, or by its English title where the system's sheet doesn't carry identifiers.
    private func dialogButton(_ app: XCUIApplication, id: String, title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, title)).firstMatch
    }

    /// Keep Demo data: the dialog's cancel button where the system shows one. Where it anchors the dialog to the switch
    /// as a popover it leaves the cancel out, and a tap outside is the cancel.
    private func cancel(_ app: XCUIApplication) {
        let keep = dialogButton(app, id: "profile.demo.keep", title: "Keep Demo data")
        let outside = app.otherElements["PopoverDismissRegion"]
        if keep.exists {
            keep.tap()
        } else if outside.exists {
            outside.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        }
    }

    @MainActor
    func testTurningDemoDataOffWithAWorkoutAsksThenKeepsOrDiscards() throws {
        let app = launch()
        let start = app.buttons["train.start"]
        XCTAssertTrue(start.waitForExistence(timeout: patience), "Start on Strain")
        app.reveal(start)
        start.tap()
        let empty = app.buttons["train.start.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: patience), "an empty workout")
        empty.tap()
        let minimise = app.buttons["Minimise"]
        XCTAssertTrue(minimise.waitForExistence(timeout: patience), "the session screen")
        minimise.tap()
        XCTAssertTrue(app.buttons["train.resume"].waitForExistence(timeout: patience), "the workout's banner")

        // Off → the dialog → Keep Demo data: still in the demo, with the workout.
        var toggle = demoSwitch(in: app)
        XCTAssertEqual(toggle.value as? String, "1", "Demo data on")
        flip(toggle)
        let discard = dialogButton(app, id: "profile.demo.discard", title: "Discard and turn off")
        XCTAssertTrue(discard.waitForExistence(timeout: patience), "the dialog's destructive button")
        XCTAssertTrue(app.staticTexts["Turn off Demo data?"].exists, "the dialog's title is visible")
        cancel(app)
        waitForAbsence(of: discard, timeout: patience, "the dialog closes")
        XCTAssertEqual(toggle.value as? String, "1", "Demo data stays on")
        app.tabBars.buttons["Strain"].tap()
        XCTAssertTrue(app.buttons["train.resume"].waitForExistence(timeout: patience), "the workout stays")

        // Off again → Discard and turn off: Demo data is off, and without an account that's Welcome.
        toggle = demoSwitch(in: app)
        flip(toggle)
        let again = dialogButton(app, id: "profile.demo.discard", title: "Discard and turn off")
        XCTAssertTrue(again.waitForExistence(timeout: patience), "the dialog again")
        again.tap()
        XCTAssertTrue(app.buttons["Log in"].waitForExistence(timeout: patience), "Welcome")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "no tabs without the demo or an account")

        // Demo data on again, Train's store kept: Start, and no workout to resume.
        app.terminate()
        let relaunched = launch(resetTrain: false)
        let startAgain = relaunched.buttons["train.start"]
        XCTAssertTrue(startAgain.waitForExistence(timeout: patience), "Start on Strain after the relaunch")
        XCTAssertFalse(relaunched.buttons["train.resume"].exists, "the discarded workout doesn't come back")
    }
}
