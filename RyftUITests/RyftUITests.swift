import XCTest

/// Start → log two sets → kill the app → resume → finish, in demo mode (no server).
final class TrainSessionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(resetTrain: Bool) -> XCUIApplication {
        // By bundle ID: the target has no TEST_TARGET_NAME (set it in Xcode to use `XCUIApplication()`).
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftTab", "strain", "-appearance", "dark"]
        if resetTrain { app.launchArguments += ["-RyftResetTrain", "YES"] }
        app.launch()
        return app
    }

    /// Scrolls the Strain tab until `element` is on screen.
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
    func testLogTwoSetsSurviveKillAndFinish() throws {
        var app = launch(resetTrain: true)

        let start = app.buttons["train.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        reveal(start, in: app)
        start.tap()

        let fromPlan = app.buttons["train.start.today"]
        XCTAssertTrue(fromPlan.waitForExistence(timeout: 5), "demo mode has today's plan (Upper A)")
        fromPlan.tap()

        let set1 = app.descendants(matching: .any)["set.0.1"]
        let set2 = app.descendants(matching: .any)["set.0.2"]
        XCTAssertTrue(set1.waitForExistence(timeout: 5))
        check(set1)
        check(set2)
        XCTAssertTrue(set1.label.contains("completed"), set1.label)
        XCTAssertTrue(set2.label.contains("completed"), set2.label)

        // Kill the app mid-workout; SwiftData keeps the session.
        app.terminate()
        app = launch(resetTrain: false)

        let resume = app.buttons["train.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "the workout in progress is offered again")
        reveal(resume, in: app)
        resume.tap()

        let restored1 = app.descendants(matching: .any)["set.0.1"]
        XCTAssertTrue(restored1.waitForExistence(timeout: 5))
        XCTAssertTrue(restored1.label.contains("completed"), restored1.label)
        XCTAssertTrue(app.descendants(matching: .any)["set.0.2"].label.contains("completed"))
        XCTAssertFalse(app.descendants(matching: .any)["set.0.3"].label.contains("completed"))

        app.buttons["session.finish"].tap()
        let confirm = app.buttons["Finish workout"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let done = app.buttons["summary.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()

        // Back on Strain: no workout in progress, Start is offered again.
        XCTAssertTrue(app.buttons["train.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["train.resume"].exists)
    }
}
