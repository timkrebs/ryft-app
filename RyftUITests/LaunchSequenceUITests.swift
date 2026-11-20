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
    /// How much sooner than the untouched sequence a tapped one must be gone: three times its own 0.4 s fade. Untouched
    /// sequences on one runner a launch apart stayed within 0.06 s of each other after the first check.
    private static let gap: TimeInterval = 1.2
    /// The least an untouched sequence must stay after the first check sees it to tell a tap from its own end: the tap and
    /// its 0.25 s fade took 1.6-1.8 s from the first check in real runs (XCUITest waits for an idle app, which the timeline
    /// keeps busy), then `gap`.
    private static let shortest: TimeInterval = 3
    /// Pairs of launches tried before the test gives up.
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
    /// Today is there. The proof is a launch nothing taps, on the same runner just before: XCUITest's `launch()` returns late
    /// in the sequence and the first check comes later still (5.5-6.5 s, then 1.2 s, in real runs), so what is left of the
    /// sequence when a check first sees it is measured, not assumed. The tapped launch must be gone `gap` sooner than the
    /// untouched one, each counted from its own first sighting: without the tap it would have stayed about as long. A pair
    /// whose untouched sequence is seen too late to tell (under `shortest`), whose overlay is never seen, or whose tapped
    /// overlay is still there at the bound, is tried again; when no pair shows it, the test fails with every pair's times.
    /// The 0.25 s fade itself is `LaunchSequenceModelTests`'. The overlay is a Button to XCUITest (tap gesture plus default
    /// action), so it is found among all descendants. That the mark, wordmark and tagline are hidden is not asserted here:
    /// XCUITest lists "RYFT", the tagline and the root beneath as present whatever the modifiers say (it does not honour
    /// `accessibilityHidden`); `LaunchAccessibilityTests` reads the real tree.
    @MainActor
    func testATapSkipsIt() throws {
        var pairs: [String] = []
        for _ in 1...Self.launches {
            // Nothing taps: how long this runner shows the overlay after first seeing it.
            guard let (_, alone, seenAlone) = launchSeeingTheSequence() else { continue }
            XCTAssertTrue(alone.waitForNonExistence(timeout: Self.sequence + Self.margin), "the sequence ends by itself")
            let untouched = Date().timeIntervalSince(seenAlone)
            guard untouched >= Self.shortest else {
                pairs.append("untouched \(untouched) s: seen too late")
                continue
            }

            guard let (app, overlay, seen) = launchSeeingTheSequence() else { continue }
            XCTAssertEqual(overlay.label, "Loading RYFT")
            overlay.tap()
            let bound = untouched - Self.gap
            let gone = overlay.waitForNonExistence(timeout: max(bound - Date().timeIntervalSince(seen), 0))
            let tapped = Date().timeIntervalSince(seen)
            let times = "untouched \(untouched) s, tapped \(tapped) s"
            guard gone, tapped <= bound else {
                pairs.append("\(times): still there")
                continue
            }
            XCTContext.runActivity(named: "The tap ended it: \(times) from the first check") { _ in }
            XCTAssertTrue(gauge(in: app).waitForExistence(timeout: 4), "Today is there")
            XCTAssertTrue(gauge(in: app).isHittable)
            return
        }
        XCTFail("no tapped launch was gone \(Self.gap) s before an untouched one, from the first check: \(pairs)")
    }

    /// Launches with `-RyftLaunchSequence play` until a check sees the overlay, and when it did: the check waits the sequence
    /// plus the runner's margin, so a launch that plays is never missed because the check came late. On a loaded runner
    /// `launch()` can return after the whole sequence (`NocturneTodaySleepUITests.testTheLaunchEndsWithTheLockUpInTheHeader`'s
    /// note): its overlay is gone before the first check, so that launch is tried again. Nil when no launch showed it.
    @MainActor
    private func launchSeeingTheSequence() -> (XCUIApplication, XCUIElement, Date)? {
        for _ in 1...Self.launches {
            let app = launchDemo(extra: ["-RyftLaunchSequence", "play"])
            let overlay = overlay(in: app)
            if overlay.waitForExistence(timeout: Self.sequence + Self.margin) { return (app, overlay, Date()) }
        }
        return nil
    }
}
