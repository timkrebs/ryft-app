import XCTest

/// Start the demo plan, check off the first exercise: it collapses, the next exercise's first set is
/// under the pinned rest bar. Demo mode, no server.
final class JumpToNextUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            app.swipeUp()
            tries += 1
        }
    }

    /// Taps the set row's check button (the trailing 56 pt of the row).
    private func check(_ row: XCUIElement) {
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
    }

    @MainActor
    func testCheckingTheLastSetJumpsToTheNextExerciseUnderThePinnedRestBar() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftTab", "strain", "-appearance", "dark",
                               "-coachMarks.today.done", "YES", "-RyftResetTrain", "YES"]
        app.launch()

        let start = app.buttons["train.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        reveal(start, in: app)
        start.tap()
        let fromPlan = app.buttons["train.start.today"]
        XCTAssertTrue(fromPlan.waitForExistence(timeout: 5), "demo mode has today's plan (Upper A)")
        fromPlan.tap()

        // Upper A starts with four bench sets, then the row.
        let first = (1...4).map { app.descendants(matching: .any)["set.0.\($0)"] }
        XCTAssertTrue(first[0].waitForExistence(timeout: 5))
        for (i, row) in first.enumerated() {
            XCTAssertTrue(row.waitForExistence(timeout: 5), "set \(i + 1)")
            check(row)
            XCTAssertTrue(row.label.contains("completed") || i == 3, row.label)
        }

        // After 0.6 s the card collapses and the next exercise's first set sits under the rest bar.
        let nextFirst = app.descendants(matching: .any)["set.1.1"]
        XCTAssertTrue(nextFirst.waitForExistence(timeout: 5))
        let hittable = NSPredicate(format: "isHittable == true")
        expectation(for: hittable, evaluatedWith: nextFirst)
        waitForExpectations(timeout: 5)

        let restBar = app.descendants(matching: .any)["session.restBar"]
        XCTAssertTrue(restBar.waitForExistence(timeout: 5), "the rest bar stays visible")
        XCTAssertTrue(restBar.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["set.0.1"].isHittable, "the first card is collapsed")
    }
}
