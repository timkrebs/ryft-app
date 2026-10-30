import XCTest

/// Replace an exercise through the card's ... menu, in demo mode (no server): the new name is shown, the old one is
/// gone, and Undo brings it back.
final class SessionReplaceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(german: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftTab", "strain", "-appearance", "dark",
                               "-coachMarks.today.done", "YES", "-RyftResetTrain", "YES"]
        if german { app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"] }
        app.launch()
        return app
    }

    /// Today's plan (Upper A, Bench press first) from the Train tab.
    private func startTodaysPlan(in app: XCUIApplication) {
        let start = app.buttons["train.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        reveal(start, in: app)
        start.tap()
        let fromPlan = app.buttons["train.start.today"]
        XCTAssertTrue(fromPlan.waitForExistence(timeout: 5), "demo mode has today's plan (Upper A)")
        fromPlan.tap()
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
        startTodaysPlan(in: app)

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

    /// German: deleting a set with values asks first, from the swipe and from the context menu.
    @MainActor
    func testGermanDeleteOfASetWithValuesAsksFirst() throws {
        let app = launch(german: true)
        startTodaysPlan(in: app)

        let row = app.descendants(matching: .any)["set.0.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let check = row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        // Checked and unchecked again: the values stay, and an open row can be swiped.
        check.tap()
        check.tap()

        row.swipeLeft()
        check.tap() // the revealed delete button sits where the check was
        let title = app.staticTexts["Satz 1 löschen?"]
        XCTAssertTrue(title.waitForExistence(timeout: 3), "a set with values asks first (swipe)")
        XCTAssertTrue(app.buttons["Satz löschen"].exists)
        let cancel = app.buttons["Abbrechen"]
        if cancel.exists { cancel.tap() } else { app.otherElements["PopoverDismissRegion"].firstMatch.tap() }
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))

        row.press(forDuration: 1.0)
        let menuDelete = app.buttons["Satz löschen"]
        XCTAssertTrue(menuDelete.waitForExistence(timeout: 3), "the context menu's Delete set")
        menuDelete.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3), "a set with values asks first (context menu)")
        app.buttons["Satz löschen"].firstMatch.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))
        XCTAssertTrue(row.waitForExistence(timeout: 3), "the next set is set 1 now")
    }
}
