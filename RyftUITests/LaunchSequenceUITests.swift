import XCTest

/// The launch sequence in the app (ADR 0017, plan.md criterion 4, launch-design.md §6.3 and §10): a UI test launches with
/// arguments, and any argument skips the sequence, so Today is there at once and nothing swallows a first tap.
final class LaunchSequenceUITests: XCTestCase {
    /// The sequence and its hand-off: the overlay is gone 5.6 s after it starts (`LaunchSequence.Timing.full`: the 5.2 s
    /// timeline, then the 0.4 s hand-off). A UI test can't import the app, so the numbers are repeated here.
    private static let sequence: TimeInterval = 5.2 + 0.4
    /// What a loaded runner adds to that before a check sees the overlay: `launch()`'s idle wait (2 s seen) and a snapshot
    /// per check (1 s seen, five in a row).
    private static let margin: TimeInterval = 5
    /// Launches tried before the test gives up on seeing the sequence play.
    private static let launches = 3

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
        let (app, overlay) = try XCTUnwrap(launchSeeingTheSequence(),
                                           "the launch sequence plays with -RyftLaunchSequence play (\(Self.launches) launches)")
        XCTAssertEqual(overlay.label, "Loading RYFT")
        overlay.tap()
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 4), "a tap ends the launch long before its natural end")
        XCTAssertTrue(gauge(in: app).waitForExistence(timeout: 4), "Today is there")
        XCTAssertTrue(gauge(in: app).isHittable)
    }

    /// Launches with `-RyftLaunchSequence play` until a check sees the overlay: it waits the sequence plus the runner's margin,
    /// so a launch that plays is never missed because the check came late. On a loaded runner `launch()` can return after the
    /// whole sequence (`NocturneTodaySleepUITests.testTheLaunchEndsWithTheLockUpInTheHeader`'s note): its overlay is gone
    /// before the first check, so that launch is tried again. Nil when no launch showed it.
    @MainActor
    private func launchSeeingTheSequence() -> (XCUIApplication, XCUIElement)? {
        for _ in 1...Self.launches {
            let app = launchDemo(extra: ["-RyftLaunchSequence", "play"])
            let overlay = overlay(in: app)
            if overlay.waitForExistence(timeout: Self.sequence + Self.margin) { return (app, overlay) }
        }
        return nil
    }
}
