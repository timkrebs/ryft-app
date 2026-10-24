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

    /// `openDaysBack`: `-RyftOpenMyDay <n>` pushes the full screen on that day once Today has loaded (Debug).
    private func launch(openDaysBack: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        var arguments = ["-demoMode", "YES", "-RyftTab", "today", "-appearance", "dark", "-coachMarks.today.done", "YES",
                         "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let openDaysBack { arguments += ["-RyftOpenMyDay", "\(openDaysBack)"] }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func elements(_ app: XCUIApplication, identifierPrefix prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    /// Scrolls Today until `element` can be tapped.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.isHittable && tries < 10 {
            app.swipeUp()
            tries += 1
        }
    }

    /// `yyyy-MM-dd`, `back` days before today, in the device's time zone (as the app writes day strings).
    private func day(daysBack back: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: -back, to: Date()) ?? Date())
    }

    // MARK: the card

    @MainActor
    func testTheCardShowsTheMergedRunAsOneRowWithTwoBadges() throws {
        let app = launch()
        let card = element(app, "myday.card")
        XCTAssertTrue(card.waitForExistence(timeout: wait), "the My Day card on Today")

        let row = element(app, "myday.row.activity.\(mergedRun)")
        reveal(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: wait), "the merged run's row")
        let label = row.label
        XCTAssertTrue(label.hasPrefix("Running"), label)
        XCTAssertTrue(label.contains("Sources: Garmin Connect and RYFT, merged"), "two badges, the tracker first: \(label)")
    }

    @MainActor
    func testTheTitleOpensTheFullScreen() throws {
        let app = launch()
        let title = element(app, "myday.title")
        XCTAssertTrue(title.waitForExistence(timeout: wait))
        reveal(title, in: app)
        XCTAssertTrue(title.label.hasPrefix("My Day, "), "VoiceOver: the title and its date: \(title.label)")
        title.tap()

        XCTAssertTrue(element(app, "myday.view").waitForExistence(timeout: wait), "the full screen")
        XCTAssertTrue(element(app, "myday.view.header").waitForExistence(timeout: wait))
        XCTAssertTrue(element(app, "myday.view.row.activity.\(mergedRun)").waitForExistence(timeout: wait),
                      "today's rows, the merged run once")
        XCTAssertTrue(element(app, "datestrip.day.\(day(daysBack: 0))").exists, "the week strip")
    }

    @MainActor
    func testTheSleepRowOpensTheSleepTab() throws {
        let app = launch()
        let row = element(app, "myday.row.sleep.\(day(daysBack: 0))")
        XCTAssertTrue(row.waitForExistence(timeout: wait), "last night's row")
        reveal(row, in: app)
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
        XCTAssertTrue(element(app, "myday.view").waitForExistence(timeout: wait))
        XCTAssertTrue(element(app, "myday.view.row.activity.\(mergedRun)").waitForExistence(timeout: wait))

        let yesterday = element(app, "datestrip.day.\(day(daysBack: 1))")
        XCTAssertTrue(yesterday.waitForExistence(timeout: wait))
        yesterday.tap()
        let padelRow = element(app, "myday.view.row.activity.\(padel)")
        XCTAssertTrue(padelRow.waitForExistence(timeout: wait), "yesterday's padel")
        XCTAssertTrue(padelRow.label.hasPrefix("Padel"), padelRow.label)
        XCTAssertFalse(element(app, "myday.view.row.activity.\(mergedRun)").exists, "today's run is gone")

        element(app, "datestrip.day.\(day(daysBack: 2))").tap()
        XCTAssertTrue(element(app, "myday.view.row.activity.\(ride)").waitForExistence(timeout: wait), "the ride two days ago")
        XCTAssertFalse(padelRow.exists, "yesterday's padel is gone")

        element(app, "datestrip.day.\(day(daysBack: 0))").tap()
        XCTAssertTrue(element(app, "myday.view.row.activity.\(mergedRun)").waitForExistence(timeout: wait), "back on today")
    }

    @MainActor
    func testAWorkoutRowOpensItsDetail() throws {
        let app = launch(openDaysBack: 0)
        XCTAssertTrue(element(app, "myday.view").waitForExistence(timeout: wait))
        // The tracker's walk: the run beside it is merged into RYFT's row, so this is the day's only workout row.
        let rows = elements(app, identifierPrefix: "myday.view.row.workout.")
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
        XCTAssertTrue(element(app, "myday.view.row.activity.\(mergedRun)").waitForExistence(timeout: wait))

        let rows = elements(app, identifierPrefix: "myday.view.row.")
        XCTAssertGreaterThanOrEqual(rows.count, 4, "the night, the run, the walk, yoga at least")
        for index in 0..<rows.count {
            let row = rows.element(boundBy: index)
            XCTAssertFalse(row.label.isEmpty, "row \(row.identifier) has a label")
            XCTAssertTrue(row.label.contains(" to "), "\(row.identifier) says its times: \(row.label)")
            XCTAssertTrue(row.label.contains("Source"), "\(row.identifier) says where it came from: \(row.label)")
        }
        let sleep = element(app, "myday.view.row.sleep.\(day(daysBack: 0))")
        XCTAssertTrue(sleep.label.hasPrefix("Sleep"), sleep.label)
        XCTAssertTrue(sleep.label.contains("Source: Apple Health"), sleep.label)
    }
}
