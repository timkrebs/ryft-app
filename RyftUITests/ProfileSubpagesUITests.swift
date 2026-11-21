import XCTest

/// C1 (PR 6 C §4.3, §4.8) with real touches, where a hosted window can't stand in: the keyboard's Done on Report a problem,
/// Journal's swipe to delete, and a finger on a habit's trash that must not flip its switch. Demo mode (no server), US
/// English; every wait is on a condition, never a sleep.
final class ProfileSubpagesUITests: XCTestCase {
    private let wait: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    // MARK: Report a problem

    /// The keyboard's Done closes the keyboard, with the page's own header in place of the navigation bar.
    @MainActor
    func testReportKeyboardDoneClosesTheKeyboard() throws {
        let app = launchDemo(extra: ["-RyftScreen", "report-problem"])
        let message = element(app, "report.message")
        XCTAssertTrue(message.waitForExistence(timeout: wait), "the message field")
        message.tap()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            throw XCTSkip("No software keyboard (the simulator has a hardware keyboard connected).")
        }
        message.typeText("The sleep chart is empty")
        let done = app.toolbars.buttons["Done"].exists ? app.toolbars.buttons["Done"] : app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Done above the keyboard")
        done.tap()
        waitForAbsence(of: keyboard, timeout: 5, "the keyboard went away")
        XCTAssertEqual(message.value as? String, "The sleep chart is empty", "what was typed stays")
    }

    // MARK: Journal

    /// Profile → Journal, its habits loaded; the user's own habit's trash and switch (identified by its id, `N5`). Today
    /// first: it loads the journal, and Profile lists Journal once it's live.
    private func openJournal() -> (app: XCUIApplication, trash: XCUIElement, toggle: XCUIElement) {
        let app = launchDemo()
        XCTAssertTrue(app.tabBar.waitForExistence(timeout: wait), "the tab bar")
        app.tab("Profile").tap()
        let row = app.buttons["profile.journal"]
        _ = row.waitForExistence(timeout: wait)
        let bottom = app.tabBar.frame.minY
        for _ in 0..<15 where !(row.exists && row.isHittable && row.frame.maxY < bottom) { app.swipeUp() }
        XCTAssertTrue(row.isHittable, "Profile → Journal")
        row.tap()
        XCTAssertTrue(app.switches["journal.habit.alcohol"].waitForExistence(timeout: wait), "the habits")
        // The list loads its rows as they come into view: the user's own group is last.
        let trash = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'journal.delete.'")).firstMatch
        for _ in 0..<10 where !(trash.exists && trash.isHittable && trash.frame.maxY < app.frame.maxY - 40) { app.swipeUp() }
        XCTAssertTrue(trash.exists && trash.isHittable, "a habit of the user's own")
        let key = trash.identifier.replacingOccurrences(of: "journal.delete.", with: "")
        let toggle = app.switches["journal.habit.\(key)"]
        XCTAssertTrue(toggle.exists, "its switch, by the same id")
        return (app, trash, toggle)
    }

    /// A finger on the trash asks to delete: the switch under it stays as it was.
    @MainActor
    func testTheTrashTakesItsOwnTap() throws {
        let (app, trash, toggle) = openJournal()
        let before = toggle.value as? String
        // Its upper edge, where the old 44 pt target ended above the glyph on a taller row.
        trash.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the dialog asks first")
        XCTAssertEqual(toggle.value as? String, before, "the switch didn't flip")
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.tap()
        } else {
            app.otherElements["PopoverDismissRegion"].tap()
        }
        waitForAbsence(of: delete, timeout: 5, "the dialog went away")
        XCTAssertEqual(toggle.value as? String, before, "still as it was")
        XCTAssertTrue(trash.exists, "nothing deleted")
    }

    /// Swiping the user's own habit to the left offers Delete; tapping it deletes the habit, without a second question.
    @MainActor
    func testSwipeToDelete() throws {
        let (app, trash, toggle) = openJournal()
        toggle.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the swipe's Delete")
        delete.tap()
        waitForAbsence(of: toggle, timeout: 10, "the habit is gone")
        XCTAssertFalse(trash.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'RYFT'")).firstMatch.exists,
                       "no failure notice")
    }
}
