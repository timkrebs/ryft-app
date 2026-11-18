import XCTest

/// The launch sequence in the app (ADR 0017, plan.md criterion 4, launch-design.md §6.3 and §10): a UI test launches with
/// arguments, and any argument skips the sequence, so Today is there at once and nothing swallows a first tap.
final class LaunchSequenceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func overlay(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["launch.sequence"]
    }

    private func gauge(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["today.readinessGauge"]
    }

    /// A normal UI-test launch (demo mode, arguments) shows no launch element and Today is on screen and hittable at once.
    /// The sequence lasts 5.2 s: if it played, the gauge (hidden from the accessibility tree beneath it) would not exist
    /// within the budget and `launch.sequence` would.
    @MainActor
    func testUITestLaunchesSkipIt() throws {
        let app = launchDemo()
        let overlay = overlay(in: app)
        XCTAssertFalse(overlay.exists, "no launch sequence in a UI test")
        let gauge = gauge(in: app)
        XCTAssertTrue(gauge.waitForExistence(timeout: 3), "Today's gauge right after launch")
        XCTAssertTrue(gauge.isHittable, "Today takes taps: nothing covers it")
        XCTAssertFalse(overlay.exists, "still no launch sequence")
        XCTAssertFalse(app.staticTexts["Loading RYFT"].exists)
    }

    /// With `-RyftLaunchSequence play` the overlay is on screen ("Loading RYFT", the root hidden beneath it), a tap ends it, and
    /// Today is there. The 0.25 s fade measured 1.56 s tap-to-gone in a real run, because XCUITest waits for the app to be
    /// idle and the `TimelineView` runs until the fade ends; so the bound is generous (4 s, under the natural 5.2 s end), and
    /// the 0.25 s itself is `LaunchSequenceModelTests`'. The overlay is a Button to XCUITest (tap gesture plus default
    /// action), so it is found among all descendants. That the mark, wordmark and tagline are hidden is not asserted here:
    /// XCUITest lists "RYFT", the tagline and the root beneath as present whatever the modifiers say (it does not honour
    /// `accessibilityHidden`), so "hidden" is not asserted; `LaunchAccessibilityTests`
    /// reads the real tree.
    @MainActor
    func testATapSkipsIt() throws {
        let app = launchDemo(extra: ["-RyftLaunchSequence", "play"])
        let overlay = overlay(in: app)
        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "the launch sequence plays with -RyftLaunchSequence play")
        XCTAssertEqual(overlay.label, "Loading RYFT")
        overlay.tap()
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 4), "a tap ends the launch long before its natural end")
        XCTAssertTrue(gauge(in: app).waitForExistence(timeout: 4), "Today is there")
        XCTAssertTrue(gauge(in: app).isHittable)
    }
}
