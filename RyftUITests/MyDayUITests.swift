import XCTest

/// My Day on demo data (`-demoMode YES`, no server, no HealthKit): the card on Today, the full screen with its
/// week strip, and what a row opens. Found by identifiers and VoiceOver labels; no snapshots. The demo day:
/// a night, mobility at 06:00, the run RYFT recorded and the platform merged with Garmin Connect's workout
/// (06:40), a walk (12:15), yoga (13:05); yesterday padel; two days ago a ride.
final class MyDayUITests: XCTestCase {
    /// Generous: a cold simulator on CI loads Today, then the activities read.
    private let wait: TimeInterval = 45

    private let mergedRun = "00000000-0000-4000-8000-0000000A0001"
    private let padel = "00000000-0000-4000-8000-0000000A0004"
    private let ride = "00000000-0000-4000-8000-0000000A0005"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(openDaysBack: Int? = nil) -> XCUIApplication {
        launchDemo(openMyDayDaysBack: openDaysBack)
    }

    private func day(daysBack back: Int) -> String { dayString(daysBack: back) }

    // MARK: the card

    @MainActor
    func testTheCardShowsTheMergedRunAsOneRowWithTwoBadges() throws {
        let app = launch()
        let card = app.otherElements["myday.card"]
        XCTAssertTrue(card.waitForExistence(timeout: wait), "the My Day card on Today")

        let row = app.buttons["myday.row.activity.\(mergedRun)"]
        app.reveal(row)
        XCTAssertTrue(row.waitForExistence(timeout: wait), "the merged run's row")
        let label = row.label
        XCTAssertTrue(label.hasPrefix("Running"), label)
        XCTAssertTrue(label.contains("Sources: Garmin Connect and RYFT, merged"), "two badges, the tracker first: \(label)")
    }

    @MainActor
    func testTheTitleOpensTheFullScreen() throws {
        let app = launch()
        let title = app.buttons["myday.title"]
        XCTAssertTrue(title.waitForExistence(timeout: wait))
        app.reveal(title)
        XCTAssertTrue(title.label.hasPrefix("My Day, "), "VoiceOver: the title and its date: \(title.label)")
        title.tap()

        XCTAssertTrue(app.otherElements["myday.view"].waitForExistence(timeout: wait), "the full screen")
        XCTAssertTrue(app.staticTexts["myday.view.header"].waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["myday.view.row.activity.\(mergedRun)"].waitForExistence(timeout: wait),
                      "today's rows, the merged run once")
        XCTAssertTrue(app.buttons["datestrip.day.\(day(daysBack: 0))"].exists, "the week strip")
    }

    @MainActor
    func testTheSleepRowOpensTheSleepTab() throws {
        let app = launch()
        let row = app.buttons["myday.row.sleep.\(day(daysBack: 0))"]
        XCTAssertTrue(row.waitForExistence(timeout: wait), "last night's row")
        app.reveal(row)
        XCTAssertTrue(row.label.hasPrefix("Sleep"), row.label)
        row.tap()

        let sleepTab = app.tabBars.buttons["Sleep"]
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: sleepTab)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: wait), .completed, "the Sleep tab is selected")
    }

    // MARK: the full screen

    @MainActor
    func testTheStripSwitchesToAPastDayAndShowsItsRows() throws {
        let app = launch(openDaysBack: 0)
        XCTAssertTrue(app.otherElements["myday.view"].waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["myday.view.row.activity.\(mergedRun)"].waitForExistence(timeout: wait))

        let yesterday = app.buttons["datestrip.day.\(day(daysBack: 1))"]
        XCTAssertTrue(yesterday.waitForExistence(timeout: wait))
        yesterday.tap()
        let padelRow = app.buttons["myday.view.row.activity.\(padel)"]
        XCTAssertTrue(padelRow.waitForExistence(timeout: wait), "yesterday's padel")
        XCTAssertTrue(padelRow.label.hasPrefix("Padel"), padelRow.label)
        XCTAssertFalse(app.buttons["myday.view.row.activity.\(mergedRun)"].exists, "today's run is gone")

        app.buttons["datestrip.day.\(day(daysBack: 2))"].tap()
        XCTAssertTrue(app.buttons["myday.view.row.activity.\(ride)"].waitForExistence(timeout: wait), "the ride two days ago")
        XCTAssertFalse(padelRow.exists, "yesterday's padel is gone")

        app.buttons["datestrip.day.\(day(daysBack: 0))"].tap()
        XCTAssertTrue(app.buttons["myday.view.row.activity.\(mergedRun)"].waitForExistence(timeout: wait), "back on today")
    }

    @MainActor
    func testAWorkoutRowOpensItsDetail() throws {
        let app = launch(openDaysBack: 0)
        XCTAssertTrue(app.otherElements["myday.view"].waitForExistence(timeout: wait))
        // The tracker's walk: the run beside it is merged into RYFT's row, so this is the day's only workout row.
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "myday.view.row.workout."))
        let walk = rows.firstMatch
        XCTAssertTrue(walk.waitForExistence(timeout: wait), "a tracker workout row")
        XCTAssertEqual(rows.count, 1, "the merged run's workout is hidden")
        XCTAssertTrue(walk.label.hasPrefix("Walk"), walk.label)
        walk.tap()

        XCTAssertTrue(app.navigationBars["Walk"].waitForExistence(timeout: wait), "the workout's detail")
    }

    // MARK: VoiceOver

    @MainActor
    func testEveryRowHasAVoiceOverSentenceWithItsSources() throws {
        let app = launch(openDaysBack: 0)
        XCTAssertTrue(app.buttons["myday.view.row.activity.\(mergedRun)"].waitForExistence(timeout: wait))

        // One snapshot of the rows' identifiers; each row is then looked up by identifier (a live query's
        // `count` and `element(boundBy:)` re-snapshot the whole tree on every call).
        let ids = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "myday.view.row."))
            .allElementsBoundByIndex.map(\.identifier)
        XCTAssertGreaterThanOrEqual(ids.count, 4, "the night, the run, the walk, yoga at least")
        for id in ids {
            let label = app.buttons[id].label
            XCTAssertFalse(label.isEmpty, "row \(id) has a label")
            XCTAssertTrue(label.contains(" to "), "\(id) says its times: \(label)")
            XCTAssertTrue(label.contains("Source"), "\(id) says where it came from: \(label)")
        }
        let sleep = app.buttons["myday.view.row.sleep.\(day(daysBack: 0))"]
        XCTAssertTrue(sleep.label.hasPrefix("Sleep"), sleep.label)
        XCTAssertTrue(sleep.label.contains("Source: Apple Health"), sleep.label)
    }
}
