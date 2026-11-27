import XCTest

/// Pull to refresh in demo mode with injected faults (`-RyftFault`, DEBUG only): a failing read is
/// silent while data is on screen, and one pass with nothing cached shows the calm card. Elements are
/// found by identifier; the status line's words are checked in English (the launch pins it).
final class RefreshResilienceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(fault: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftTab", "today",
                               "-coachMarks.today.done", "YES", "-RyftFault", fault,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// The status line's button (inside the `today.syncLine` container); its label is the line's text.
    private func line(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'today.syncLine.'")).firstMatch
    }

    private func pullToRefresh(_ app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
    }

    private func wait(for predicate: String, on element: XCUIElement, timeout: TimeInterval, _ message: String) {
        let done = expectation(for: NSPredicate(format: predicate), evaluatedWith: element)
        XCTWaiter().wait(for: [done], timeout: timeout) == .completed ? () : XCTFail(message)
    }

    /// Criteria 1, 4, 7, 8: `/v1/me` answers 429 on every call, the other reads succeed. The pull ends
    /// with the numbers where they were, no card and no "Couldn't load" line, and "Up to date".
    @MainActor
    func testAFailingReadIsSilentAndTheLineEndsUpToDate() throws {
        let app = launch(fault: "/v1/me=429")
        let gauge = app.otherElements.matching(NSPredicate(format: "label == 'Overall readiness'")).firstMatch
        XCTAssertTrue(gauge.waitForExistence(timeout: 15), "the readiness gauge")
        wait(for: "label CONTAINS 'Up to date'", on: line(app), timeout: 15, "settled before the pull")
        let readiness = gauge.value as? String
        let sleep = app.buttons["today.tile.sleep"].value as? String
        XCTAssertNotNil(readiness)
        XCTAssertNotNil(sleep)

        pullToRefresh(app)

        // Nothing flashes while the pull and the line's steps run (each is held 600 ms).
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            XCTAssertFalse(element(app, "today.refreshIssue").exists, "no error card")
            XCTAssertFalse(line(app).label.contains("Couldn't load"), "no 'Couldn't load' line")
            usleep(250_000)
        }
        wait(for: "label CONTAINS 'Up to date'", on: line(app), timeout: 15, "the line ends at Up to date")
        XCTAssertEqual(gauge.value as? String, readiness, "the numbers stay")
        XCTAssertEqual(app.buttons["today.tile.sleep"].value as? String, sleep, "the numbers stay")
        XCTAssertFalse(element(app, "today.refreshIssue").exists)
    }

    /// Criteria 7, 8, 9: nothing cached and today and history both answer 503. After one pass the card
    /// shows, the line reads "Couldn't load today · Details", tapping it scrolls to the card, and Details
    /// opens the sheet with its request ID.
    @MainActor
    func testNothingCachedAndFailingShowsTheCardAndItsDetails() throws {
        let app = launch(fault: "/v1/days/today=503,/v1/days=503")
        let card = element(app, "today.refreshIssue")

        // The line and the card are containers: their buttons keep their own identifiers.
        let issueLine = app.buttons["today.syncLine.issue"]
        XCTAssertTrue(issueLine.waitForExistence(timeout: 20), "the line points to the card")
        wait(for: "label BEGINSWITH \"Couldn't load today\"", on: issueLine, timeout: 5, "the line's words")

        XCTAssertTrue(issueLine.label.contains("Details"), issueLine.label)

        // The card is last on Today: below the fold until the line is tapped.
        issueLine.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the card")
        // Try again and Details are separate buttons (what VoiceOver reaches too).
        XCTAssertTrue(app.buttons["refreshIssue.retry"].exists, "Try again")
        let details = app.buttons["refreshIssue.details"]
        wait(for: "isHittable == true", on: details, timeout: 5, "the card scrolled into view")

        details.tap()
        let requestID = element(app, "refreshDetails.requestID")
        XCTAssertTrue(requestID.waitForExistence(timeout: 5), "the sheet's request ID row")
        XCTAssertTrue(requestID.label.contains("fault-"), requestID.label)
    }

    /// Demo data with a 401 (only fault injection makes one there): no Sign in on Today's card or on Sleep → Day's
    /// failed night, since Sign in signs out and demo data needs no account (`RefreshIssue.Reason.action(isDemo:)`).
    /// Details stays on both.
    @MainActor
    func testADemo401OffersNoSignInOnTodayOrSleep() throws {
        let app = launch(fault: "/v1/days/today=401,/v1/days=401")
        let issueLine = app.buttons["today.syncLine.issue"]
        XCTAssertTrue(issueLine.waitForExistence(timeout: 20), "the line points to the card")
        wait(for: "label BEGINSWITH \"You're signed out\"", on: issueLine, timeout: 5, "the line's words")
        issueLine.tap()
        wait(for: "isHittable == true", on: app.buttons["refreshIssue.details"], timeout: 5, "the card's Details")
        XCTAssertFalse(app.buttons["refreshIssue.retry"].exists, "no Sign in on Today's card")

        app.tab("Sleep").tap()
        let message = app.staticTexts["You're signed out, so new data can't load."]
        XCTAssertTrue(message.waitForExistence(timeout: 20), "Sleep → Day's failed night")
        XCTAssertFalse(app.buttons["sleep.failure.retry"].exists, "no Sign in on Sleep")
        XCTAssertTrue(app.buttons["Details"].exists, "Sleep's Details")
    }

    /// The Details sheet's "Send to RYFT" (Report a problem is wired on the root view) is reachable at the
    /// opening detent and opens Report a problem pre-filled: a bug report about today and its status. Diagnostics are
    /// opt-in, so the request ID joins the chip (and the report) only once "Include diagnostics" is on.
    @MainActor
    func testSendToRYFTOpensReportAProblemPrefilled() throws {
        let app = launch(fault: "/v1/days/today=503,/v1/days=503")
        let issueLine = app.buttons["today.syncLine.issue"]
        XCTAssertTrue(issueLine.waitForExistence(timeout: 20), "the line points to the card")
        issueLine.tap()
        let details = app.buttons["refreshIssue.details"]
        wait(for: "isHittable == true", on: details, timeout: 5, "the card scrolled into view")
        details.tap()

        let send = app.buttons["refreshDetails.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Send to RYFT shows once Report a problem is wired")
        XCTAssertTrue(send.isHittable, "reachable at the opening detent")
        send.tap()

        let chip = element(app, "report.context")
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the context chip")
        XCTAssertEqual(chip.label, "About: Today · 503", "no request ID while diagnostics are off")
        XCTAssertEqual(element(app, "report.message").value as? String, "Refreshing Today didn't work.")
        XCTAssertTrue(element(app, "report.category.bug").isSelected, "a bug report")

        let diagnostics = app.switches["report.diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5), "Include diagnostics")
        XCTAssertEqual(diagnostics.value as? String, "0", "diagnostics are opt-in")
        for _ in 0..<5 where !diagnostics.isHittable { app.swipeUp() }
        // The switch itself, at the row's trailing end (the middle is its label).
        diagnostics.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        wait(for: "value == '1'", on: diagnostics, timeout: 5, "diagnostics on")
        wait(for: "label BEGINSWITH 'About: Today · 503 · request fault-'", on: chip, timeout: 5,
             "the chip carries the request ID once diagnostics are on")
    }
}
