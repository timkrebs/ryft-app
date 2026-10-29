import XCTest

/// Replace an exercise through the card's ... menu, in demo mode (no server): the new name is shown, the old one is
/// gone, and Undo brings it back.
final class SessionReplaceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftTab", "strain", "-appearance", "dark",
                               "-coachMarks.today.done", "YES", "-RyftResetTrain", "YES"]
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            app.swipeUp()
            tries += 1
        }
    }

    @MainActor
    func testReplaceAnExerciseFromTheMenuAndUndo() throws {
        let app = launch()
        let start = app.buttons["train.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        reveal(start, in: app)
        start.tap()
        let fromPlan = app.buttons["train.start.today"]
        XCTAssertTrue(fromPlan.waitForExistence(timeout: 5), "demo mode has today's plan (Upper A)")
        fromPlan.tap()

        // Upper A starts with Bench press.
        let options = app.buttons["Options for Bench press"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        let replace = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Replace'")).firstMatch
        XCTAssertTrue(replace.waitForExistence(timeout: 3), "Replace is the menu's first entry")
        replace.tap()

        // The picker (AddExerciseSheet in replace mode): pick Cable fly.
        let pick = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Cable fly'")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5), "the exercise picker lists Cable fly")
        pick.tap()

        XCTAssertTrue(app.buttons["Options for Cable fly"].waitForExistence(timeout: 5), "the card has the new name")
        XCTAssertFalse(app.buttons["Options for Bench press"].exists, "and the old one is gone")

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "the toast offers Undo")
        undo.tap()
        XCTAssertTrue(app.buttons["Options for Bench press"].waitForExistence(timeout: 3), "Undo restores the exercise")
        XCTAssertFalse(app.buttons["Options for Cable fly"].exists)
    }
}
