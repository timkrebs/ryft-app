import XCTest

/// Today and Sleep in Nocturne, in demo mode (docs/work/2026-11-16-nocturne/design.md §P4-11 test 51): Today shows the header,
/// the gauge, the ruler and the three tiles; the Sleep tile opens Sleep; Previous night, then Next night, returns to the
/// latest night and disables Next; Calendar opens My Day; and the launch ends with the lock-up in the header. Found by the
/// identifiers and the VoiceOver labels; no snapshots, and every wait is on a condition.
final class NocturneTodaySleepUITests: XCTestCase {
    /// Generous: a cold simulator on CI loads Today first.
    private let wait: TimeInterval = 45

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// The header lock-up: "RYFT", the only element with that label once the launch has ended.
    private func lockUp(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "RYFT")).firstMatch
    }

    /// Sleep's title: its value is the night ("Last night, …", "Yesterday, …"). The tab bar's "Sleep" has no such value.
    private func night(in app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND value BEGINSWITH %@", "Sleep", prefix)).firstMatch
    }

    // MARK: Today

    @MainActor
    func testTodayShowsTheHeaderTheGaugeTheRulerAndThreeTiles() throws {
        let app = launchDemo()
        XCTAssertTrue(element(app, "today.readinessGauge").waitForExistence(timeout: wait), "the gauge")
        XCTAssertTrue(lockUp(in: app).exists, "the lock-up in the header")
        XCTAssertTrue(app.buttons["today.header.calendar"].exists, "Calendar, with My Day on in demo")
        XCTAssertEqual(app.buttons["today.header.calendar"].label, "Calendar")
        XCTAssertTrue(element(app, "today.ruler").exists, "the ruler")
        for tile in ["recovery", "sleep", "strain"] {
            let element = app.buttons["today.tile.\(tile)"]
            app.reveal(element)
            XCTAssertTrue(element.waitForExistence(timeout: wait), "the \(tile) tile")
        }
    }

    @MainActor
    func testCalendarOpensMyDay() throws {
        let app = launchDemo()
        let calendar = app.buttons["today.header.calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: wait))
        calendar.tap()
        XCTAssertTrue(app.otherElements["myday.view"].waitForExistence(timeout: wait), "My Day opens on a push")
    }

    @MainActor
    func testTheSleepTileOpensSleep() throws {
        let app = launchDemo()
        let tile = app.buttons["today.tile.sleep"]
        XCTAssertTrue(tile.waitForExistence(timeout: wait))
        app.reveal(tile)
        tile.tap()
        let sleepTab = app.tab("Sleep")
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: sleepTab)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: wait), .completed, "the Sleep tab is selected")
        XCTAssertTrue(app.buttons["sleep.header.previous"].waitForExistence(timeout: wait), "Sleep's header")
    }

    // MARK: Sleep

    @MainActor
    func testPreviousThenNextNightReturnsToTheLatestAndDisablesNext() throws {
        let app = launchDemo(extra: ["-RyftTab", "sleep"])
        let previous = app.buttons["sleep.header.previous"], next = app.buttons["sleep.header.next"]
        XCTAssertTrue(previous.waitForExistence(timeout: wait), "Sleep's header")
        XCTAssertTrue(night(in: app, startingWith: "Last night").waitForExistence(timeout: wait), "the latest night")
        XCTAssertFalse(next.isEnabled, "no newer night than the latest")
        XCTAssertTrue(previous.isEnabled)

        previous.tap()
        XCTAssertTrue(night(in: app, startingWith: "Yesterday").waitForExistence(timeout: wait), "the night before")
        XCTAssertTrue(next.isEnabled, "a newer night to go back to")

        next.tap()
        XCTAssertTrue(night(in: app, startingWith: "Last night").waitForExistence(timeout: wait), "the latest night again")
        let disabled = expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: next)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: wait), .completed, "Next is disabled at the latest night")
        XCTAssertTrue(previous.isEnabled)
    }

    // MARK: the launch

    /// The launch is asked to play (`-RyftLaunchSequence play`) and, without a tap, ends with the mark moved into Today's
    /// header: the overlay is gone and the lock-up is there. The sequence lasts 5.2 s and the move 0.5 s on top. That it
    /// played is not asserted: on a loaded runner `launch()` returned after the whole sequence (seen in a full UISmoke run, three
    /// times in a row), so a wait for the overlay failed the test for a launch that had played. That the sequence plays and ends on
    /// a tap is `LaunchSequenceUITests.testATapSkipsIt`'s; the move's numbers are `LaunchMoveTests`'; this is the landing.
    @MainActor
    func testTheLaunchEndsWithTheLockUpInTheHeader() throws {
        let app = launchDemo(extra: ["-RyftLaunchSequence", "play"])
        waitForAbsence(of: element(app, "launch.sequence"), timeout: 30, "the launch ends by itself")
        XCTAssertTrue(lockUp(in: app).waitForExistence(timeout: 5), "the lock-up in Today's header")
        let gauge = element(app, "today.readinessGauge")
        XCTAssertTrue(gauge.waitForExistence(timeout: 10), "the gauge, after the move")
        XCTAssertTrue(gauge.isHittable, "nothing covers Today")
        XCTAssertTrue(app.buttons["today.header.calendar"].exists)
    }
}
