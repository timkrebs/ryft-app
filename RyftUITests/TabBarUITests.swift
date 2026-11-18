import XCTest

/// The dot tab bar (design.md §P5-2, §P5-12 tests 42 and 52), in demo mode: each tab opens under `-RyftTab <name>` (the
/// launch-argument contract), the bar reads as five buttons with their positions and replaces the system bar, a re-tap on
/// Strain with a pushed workout goes back to Strain's root while a switch away and back keeps the workout, and the
/// keyboard covers the bar instead of lifting it.
final class TabBarUITests: XCTestCase {
    private let wait: TimeInterval = 20
    private let tabs = ["Today", "Sleep", "Strain", "Insights", "Profile"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Something only that tab's root shows.
    private func marker(_ tab: String, in app: XCUIApplication) -> XCUIElement {
        switch tab {
        case "Today": return app.buttons["today.tile.sleep"]
        case "Sleep": return app.buttons["sleep.header.previous"]
        case "Profile": return app.staticTexts["Demo data"]
        default: return app.staticTexts[tab]
        }
    }

    private func waitUntilSelected(_ element: XCUIElement, _ message: String) {
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: wait), .completed, message)
    }

    /// Test 52: `-RyftTab <name>` opens that tab, its item selected.
    @MainActor
    func testEachTabOpensUnderItsLaunchArgument() throws {
        for name in tabs {
            let app = launchDemo(extra: ["-RyftTab", name.lowercased()])
            waitUntilSelected(app.tab(name), "\(name) selected at launch")
            XCTAssertTrue(marker(name, in: app).waitForExistence(timeout: wait), "\(name)'s screen")
            app.terminate()
        }
    }

    /// The bar: one container, five buttons in order with their positions, one selected at a time, no system bar.
    @MainActor
    func testTheBarSwitchesTabsAndReadsAsFiveTabs() throws {
        let app = launchDemo()
        XCTAssertTrue(app.tabBar.waitForExistence(timeout: wait), "the tab bar")
        XCTAssertEqual(app.tabBars.count, 0, "the system tab bar is hidden")
        for (index, name) in tabs.enumerated() {
            let tab = app.tab(name)
            XCTAssertTrue(tab.exists, name)
            XCTAssertEqual(tab.label, name)
            XCTAssertEqual(tab.value as? String, "Tab \(index + 1) of 5")
            XCTAssertGreaterThanOrEqual(tab.frame.width, 44, name)
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44, name)
        }
        for name in tabs.reversed() {
            app.tab(name).tap()
            waitUntilSelected(app.tab(name), "\(name) selected")
            XCTAssertTrue(marker(name, in: app).waitForExistence(timeout: wait), "\(name)'s screen")
            XCTAssertEqual(tabs.filter { app.tab($0).isSelected }, [name], "one selected tab")
        }
    }

    /// Test 42: a workout pushed from Strain's list stays while another tab shows, and a tap on the selected Strain returns
    /// to its root, scrolled to the top. (Not `-RyftOpenWorkout`: its one-shot flag lives in Strain's state, so the rebuilt
    /// tab would push the workout again.)
    @MainActor
    func testReTappingStrainReturnsAPushedWorkoutToTheRoot() throws {
        let app = launchDemo(extra: ["-RyftTab", "strain"])
        XCTAssertTrue(app.tabBar.waitForExistence(timeout: wait), "the tab bar")
        let barTop = app.tabBar.frame.minY
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "strain.row.workout.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: wait), "a workout row on Strain")
        for _ in 0..<10 where !(row.isHittable && row.frame.maxY < barTop) { app.swipeUp(velocity: .slow) }
        XCTAssertLessThan(row.frame.maxY, barTop, "the row above the bar")
        row.tap()
        let workout = app.navigationBars.firstMatch
        XCTAssertTrue(workout.waitForExistence(timeout: wait), "the workout, pushed")
        XCTAssertTrue(app.tab("Strain").isHittable, "the bar on a pushed screen")

        app.tab("Today").tap()
        XCTAssertTrue(marker("Today", in: app).waitForExistence(timeout: wait), "Today")
        app.tab("Strain").tap()
        XCTAssertTrue(workout.waitForExistence(timeout: wait), "Strain keeps its stack across a tab change")

        app.tab("Strain").tap()
        waitForAbsence(of: workout, timeout: wait, "the re-tap pops the workout")
        let title = marker("Strain", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: wait), "Strain's root")
        XCTAssertTrue(title.isHittable, "at the top again")
        XCTAssertTrue(app.tab("Strain").isSelected, "Strain stays selected")
    }

    /// The keyboard covers the bar, as it covered the system bar: the bar doesn't ride up on it (Profile's developer
    /// fields, Debug builds).
    @MainActor
    func testTheKeyboardCoversTheBar() throws {
        let app = launchDemo(extra: ["-RyftTab", "profile"])
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Same host as the API'")).firstMatch
        XCTAssertTrue(app.tabBar.waitForExistence(timeout: wait), "the tab bar")
        let barTop = app.tabBar.frame.minY
        for _ in 0..<12 where !(field.exists && field.isHittable && field.frame.maxY < barTop) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(field.isHittable, "the developer field")
        field.tap()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            throw XCTSkip("No software keyboard (the simulator has a hardware keyboard connected).")
        }
        XCTAssertGreaterThanOrEqual(app.tabBar.frame.minY, keyboard.frame.minY - 0.5,
                                    "the bar stays under the keyboard: bar \(app.tabBar.frame), keyboard \(keyboard.frame)")
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY + 0.5, "the focused field above the keyboard")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "keyboard-up"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
