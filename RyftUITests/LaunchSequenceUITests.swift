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

    /// Hold the sequence in the simulator fixture so XCUITest can tap it even on a loaded runner.
    /// Natural completion and the fade duration are tested by the model's clock tests.
    @MainActor
    func testATapSkipsIt() {
        let app = launchDemo(extra: ["-RyftResetTrain", "YES", "-RyftLaunchSequence", "play", "-RyftHoldLaunchForTap"])
        let overlay = overlay(in: app)
        XCTAssertTrue(overlay.waitForExistence(timeout: 10))
        XCTAssertEqual(overlay.label, "Loading RYFT")
        overlay.tap()
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 8))
        XCTAssertTrue(gauge(in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(gauge(in: app).isHittable)
    }
}
