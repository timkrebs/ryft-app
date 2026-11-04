import XCTest

/// The Focused session layout end to end, in demo mode (no server, no HealthKit): today's plan (Upper A, five exercises,
/// the last two a superset) in the pager under the strip. Forced on with `-flags.overrides` (Debug: saved overrides beat
/// demo's remote config); without it the flag is absent, which is off. Every wait is on a condition, never a sleep.
final class FocusedSessionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private static let focusedOn = ["-flags.overrides", "<dict><key>train.focused_session</key><true/></dict>"]
    private let patience: TimeInterval = 20

    private func launch(extra: [String] = [], reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftTab", "strain", "-appearance", "dark",
                               "-coachMarks.today.done", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            + (reset ? ["-RyftResetTrain", "YES"] : []) + extra
        app.launch()
        // The first launch of a run now and then came up on Today with the coach marks, as if it had no launch arguments
        // (seen 3 times in 6 runs on a loaded Mac, pid of an earlier instance terminated by `launch`). The Strain tab
        // being selected proves the arguments arrived; if not, one relaunch.
        let strain = app.tabBars.buttons["Strain"]
        let selected = NSPredicate(format: "isSelected == true")
        let arrived = XCTNSPredicateExpectation(predicate: selected, object: strain)
        if XCTWaiter.wait(for: [arrived], timeout: 15) != .completed {
            app.terminate()
            app.launch()
        }
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Waits until `predicate` holds for `element`.
    private func wait(_ element: XCUIElement, until predicate: String, _ message: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: patience), .completed, message)
    }

    private func waitForAbsence(_ element: XCUIElement, _ message: String) {
        wait(element, until: "exists == false", message)
    }

    private func requireExists(_ element: XCUIElement, _ message: String) {
        XCTAssertTrue(element.waitForExistence(timeout: patience), message)
    }

    /// Strain → Start → today's plan; returns once the session is on screen (its Finish button).
    private func startTodaysPlan(in app: XCUIApplication) {
        let start = app.buttons["train.start"]
        requireExists(start, "the Start button on Strain")
        app.reveal(start)
        start.tap()
        let fromPlan = app.buttons["train.start.today"]
        requireExists(fromPlan, "demo mode has today's plan (Upper A)")
        fromPlan.tap()
        requireExists(app.buttons["session.finish"], "the session screen")
    }

    private func openFocused(extra: [String] = []) -> XCUIApplication {
        let app = launch(extra: Self.focusedOn + extra)
        startTodaysPlan(in: app)
        requireExists(element(app, "session.strip.0"), "the strip's first tile")
        return app
    }

    private func tile(_ app: XCUIApplication, _ n: Int) -> XCUIElement { element(app, "session.strip.\(n)") }

    /// A tile's label is "Name, progress".
    private func name(of tile: XCUIElement) -> String {
        tile.label.components(separatedBy: ", ").first ?? tile.label
    }

    /// A scrolled-away tile still exists, but its frame lies outside the window (`isHittable` can't tell for these).
    private func onScreen(_ tile: XCUIElement, in app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch.frame
        let f = tile.frame
        return tile.exists && f.minX >= window.minX && f.maxX <= window.maxX
    }

    private func title(_ app: XCUIApplication) -> XCUIElement { element(app, "session.page.title") }

    /// The page on screen is tile `n`'s: it is selected, and the page's title carries its name.
    private func assertPage(_ n: Int, named exerciseName: String, in app: XCUIApplication, _ message: String = "") {
        wait(tile(app, n), until: "isSelected == true", "tile \(n) is the current one. \(message)")
        wait(title(app), until: "label BEGINSWITH %@".replacingOccurrences(of: "%@", with: "'\(exerciseName)'"),
             "the page title names \(exerciseName). \(message)")
    }

    // MARK: the flag

    @MainActor
    func testWithTheFlagOffTheSessionIsTheList() throws {
        let app = launch()
        startTodaysPlan(in: app)
        requireExists(element(app, "set.0.1"), "List's first set row")
        XCTAssertFalse(element(app, "session.strip.0").exists, "no strip with the flag off")
        XCTAssertFalse(element(app, "session.page.title").exists, "no page")
    }

    @MainActor
    func testWithTheFlagOnTheSessionIsPagedUnderTheStrip() throws {
        let app = openFocused()
        for n in 0...4 { requireExists(tile(app, n), "tile \(n)") }
        XCTAssertFalse(tile(app, 5).exists, "Upper A has five exercises")
        requireExists(element(app, "session.strip.add"), "the + tile")
        let first = name(of: tile(app, 0))
        assertPage(0, named: first, in: app)
        requireExists(element(app, "set.0.1"), "the page's rows keep their identifiers")
        for id in ["session.chip.replace", "session.chip.targets", "session.chip.rest"] {
            requireExists(element(app, id), id)
        }
    }

    // MARK: paging

    @MainActor
    func testSwipingAndTappingATileChangeThePage() throws {
        let app = openFocused()
        let names = (0...3).map { name(of: tile(app, $0)) }
        let row = element(app, "set.0.1")
        requireExists(row, "a set row to swipe from")

        row.swipeLeft()
        assertPage(1, named: names[1], in: app, "a left swipe from a row pages")

        tile(app, 3).tap()
        assertPage(3, named: names[3], in: app, "a tile tap pages")

        let back = element(app, "set.3.1")
        requireExists(back, "the new page's rows")
        back.swipeRight()
        assertPage(2, named: name(of: tile(app, 2)), in: app, "a right swipe pages back")
    }

    @MainActor
    func testAVerticalDragFromARowScrollsThePageAndDoesNotPageIt() throws {
        let app = openFocused()
        let card = element(app, "session.lastTime")
        requireExists(card, "last time's card at the foot of the page")
        let row = element(app, "set.0.1")
        requireExists(row, "a set row")
        // Three more sets, so the page is taller than the screen on any device.
        let addSet = app.buttons["Add set"]
        for n in 5...7 {
            requireExists(addSet, "Add set")
            addSet.tap()
            requireExists(element(app, "set.0.\(n)"), "set \(n) was added")
        }
        let before = card.frame.minY

        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -320)))

        // Polled: `frame` is read fresh each time.
        let deadline = Date().addingTimeInterval(patience)
        while card.frame.minY > before - 100, Date() < deadline { _ = card.waitForExistence(timeout: 0.25) }
        XCTAssertLessThan(card.frame.minY, before - 100, "the page scrolled under the finger (was \(before))")
        XCTAssertTrue(tile(app, 0).isSelected, "a vertical drag from a row stays on the page")
    }

    @MainActor
    func testALongPressOnATileOpensTheReorderSheet() throws {
        let app = openFocused()
        requireExists(tile(app, 1), "a tile")
        tile(app, 1).press(forDuration: 1.0)
        let sheet = app.navigationBars["Reorder"]
        requireExists(sheet, "the reorder sheet")
        app.buttons["Done"].tap()
        waitForAbsence(sheet, "the sheet closes")
        XCTAssertTrue(tile(app, 0).isSelected, "reordering from the strip leaves the page")
    }

    /// C2: Reorder moves the current tile without changing the page, and the strip follows it.
    @MainActor
    func testMovingTheCurrentExerciseToTheEndKeepsItsTileOnTheStrip() throws {
        let app = openFocused()
        // Upper A has five tiles; four more make the strip wider than the screen.
        for n in 5...8 {
            requireExists(element(app, "session.strip.add"), "the + tile")
            element(app, "session.strip.add").tap()
            let pick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'exercise.pick.'")).firstMatch
            requireExists(pick, "the picker")
            pick.tap()
            requireExists(tile(app, n), "tile \(n) was added")
        }
        // The first exercise is the page; the strip may have followed the added ones, so scroll it back.
        let strip = element(app, "session.strip")
        var tries = 0
        while !onScreen(tile(app, 0), in: app) && tries < 6 {
            strip.swipeRight()
            tries += 1
        }
        let first = name(of: tile(app, 0))
        tile(app, 0).tap()
        assertPage(0, named: first, in: app)
        XCTAssertFalse(onScreen(tile(app, 8), in: app), "the strip is long enough to scroll: the last tile is off screen")

        tile(app, 0).press(forDuration: 1.0)
        requireExists(app.navigationBars["Reorder"], "the reorder sheet")
        // The sheet opens at medium height and shows five rows: pull it up so the last handle is in reach.
        let bar = app.navigationBars["Reorder"]
        let grip = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.1, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: -400)))
        let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'"))
        wait(handles.element(boundBy: 8), until: "isHittable == true", "a reorder handle per exercise, all in reach")
        let from = handles.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = handles.element(boundBy: 8).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        from.press(forDuration: 1.0, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.5)
        app.buttons["Done"].tap()

        // The moved exercise is now the last one, and still the page.
        wait(tile(app, 8), until: "label BEGINSWITH %@".replacingOccurrences(of: "%@", with: "'\(first)'"),
             "the first exercise moved to the end")
        wait(tile(app, 8), until: "isSelected == true", "and is still the current one")
        let deadline = Date().addingTimeInterval(patience)
        while !onScreen(tile(app, 8), in: app), Date() < deadline { _ = tile(app, 8).waitForExistence(timeout: 0.25) }
        XCTAssertTrue(onScreen(tile(app, 8), in: app), "the strip scrolled to keep its tile in view: \(tile(app, 8).frame)")
    }

    // MARK: chips

    @MainActor
    func testTheReplaceChipOpensThePickerAndUndoBringsTheExerciseBack() throws {
        let app = openFocused()
        let original = name(of: tile(app, 0))
        requireExists(element(app, "session.chip.replace"), "the equipment chip")
        element(app, "session.chip.replace").tap()

        let pick = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Cable fly'")).firstMatch
        requireExists(pick, "the picker lists Cable fly")
        pick.tap()
        assertPage(0, named: "Cable fly", in: app, "an in-place replace keeps the page")

        let undo = app.buttons["Undo"]
        requireExists(undo, "the toast offers Undo")
        undo.tap()
        assertPage(0, named: original, in: app, "Undo brings the exercise back on its page")
    }

    @MainActor
    func testTheTargetChipOpensTheEditTargetsSheet() throws {
        let app = openFocused()
        requireExists(element(app, "session.chip.targets"), "the target chip")
        element(app, "session.chip.targets").tap()
        let done = element(app, "editTargets.done")
        requireExists(done, "the Edit targets sheet")
        done.tap()
        waitForAbsence(done, "the sheet closes")
        requireExists(element(app, "session.chip.targets"), "back on the page")
    }

    @MainActor
    func testTheRestChipSetsTheExercisesRest() throws {
        let app = openFocused()
        let chip = element(app, "session.chip.rest")
        requireExists(chip, "the rest chip")
        XCTAssertTrue(chip.label.contains("3 minutes"), "Bench rests 3:00 in the demo plan: \(chip.label)")
        chip.tap()
        let choice = element(app, "restChoice.60")
        requireExists(choice, "the rest choices")
        choice.tap()
        wait(chip, until: "label CONTAINS '1 minute'", "the chip shows the new rest")
    }

    // MARK: warm-ups

    @MainActor
    func testTheWarmUpPillFoldsAndOpensTheGroup() throws {
        let app = openFocused()
        XCTAssertFalse(element(app, "session.warmups").exists, "no warm-ups in the plan: no pill")
        let options = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Options for'")).firstMatch
        requireExists(options, "the page's menu")
        options.tap()
        let add = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add warm-up'")).firstMatch
        requireExists(add, "Add warm-up set in the menu")
        add.tap()

        let pill = element(app, "session.warmups")
        requireExists(pill, "the pill once there is a warm-up")
        wait(pill, until: "value == 'expanded'", "a warm-up added from the menu shows at once")
        requireExists(element(app, "warmup.0.1"), "a warm-up row has its own identifier")
        requireExists(element(app, "set.0.1"), "the first working set keeps its own")
        pill.tap()
        wait(pill, until: "value == 'collapsed'", "the pill folds the group")
        pill.tap()
        wait(pill, until: "value == 'expanded'", "and opens it again")
    }

    // MARK: auto-advance

    /// T2: Upper A (17 sets over five exercises, the last two a superset) logged with ✓ taps alone. Each tap is on the row
    /// VoiceOver calls "Next set." (the active row), and the next one must be a different row: the page follows the planner
    /// on its own, including the superset's flips. It ends on a Finish button the user can reach.
    @MainActor
    func testAWholeSessionWithOnlyCheckTapsEndsOnFinish() throws {
        let app = openFocused()
        let activeRow = app.descendants(matching: .any).matching(NSPredicate(format: "value == 'Next set.'")).firstMatch
        let finish = element(app, "session.allDone.finish")
        var seen: [String] = []

        while !finish.exists {
            XCTAssertLessThan(seen.count, 17, "Upper A has 17 sets: still not done after \(seen.count) checks")
            if seen.count >= 17 { break }
            requireExists(activeRow, "an active row after \(seen.count) checks")
            let id = activeRow.identifier
            XCTAssertFalse(seen.contains(id), "\(id) was the active row twice: the last ✓ did not move on")
            seen.append(id)
            activeRow.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
            // Moved on: another row is active (the page may have changed, 0.6 s later), or the session is done.
            let deadline = Date().addingTimeInterval(patience)
            while Date() < deadline, !finish.exists, !(activeRow.exists && activeRow.identifier != id) {
                _ = activeRow.waitForExistence(timeout: 0.25)
            }
        }

        XCTAssertEqual(seen.count, 17, "every set was checked once: \(seen)")
        requireExists(finish, "the All sets done card")
        var scrolls = 0
        while !finish.isHittable && scrolls < 4 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(finish.isHittable, "Finish can be tapped")
        for n in 0...4 {
            XCTAssertTrue(tile(app, n).label.hasSuffix("done"), "tile \(n): \(tile(app, n).label)")
        }
    }

    // MARK: relaunch and remove

    @MainActor
    func testARelaunchRestoresThePage() throws {
        var app = openFocused()
        let third = name(of: tile(app, 2))
        tile(app, 2).tap()
        assertPage(2, named: third, in: app)

        app.terminate()
        app = launch(extra: Self.focusedOn, reset: false)
        let resume = app.buttons["train.resume"]
        requireExists(resume, "the workout in progress is offered again")
        app.reveal(resume)
        resume.tap()
        requireExists(tile(app, 2), "the strip is back")
        assertPage(2, named: third, in: app, "the page is where it was left")
    }

    @MainActor
    func testRemovingTheCurrentExerciseMovesToTheNextOne() throws {
        let app = openFocused()
        let names = (0...4).map { name(of: tile(app, $0)) }
        tile(app, 1).tap()
        assertPage(1, named: names[1], in: app)

        let options = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Options for'")).firstMatch
        requireExists(options, "the page's menu")
        options.tap()
        let remove = app.buttons["Remove exercise"]
        requireExists(remove, "Remove exercise in the menu")
        remove.tap()
        // The confirmation's button has the same label as the menu item.
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Remove exercise'")).firstMatch
        requireExists(confirm, "the confirmation")
        confirm.tap()

        waitForAbsence(tile(app, 4), "four exercises are left")
        assertPage(1, named: names[2], in: app, "the page is the one that followed")
        let remaining = (0...3).map { name(of: tile(app, $0)) }
        XCTAssertEqual(remaining, [names[0], names[2], names[3], names[4]], "the removed exercise left the strip")
    }
}
