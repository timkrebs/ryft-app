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
        app.launchArguments = ["-demoMode", "YES", "-RyftTab", "today", "-appearance", "dark",
                               "-coachMarks.today.done", "YES", "-RyftFault", fault,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// The status line is one button; its label is the line's text.
    private func line(_ app: XCUIApplication) -> XCUIElement { app.buttons["today.syncLine"] }

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
        let sleep = app.buttons["Sleep"].firstMatch.value as? String
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
        XCTAssertEqual(app.buttons["Sleep"].firstMatch.value as? String, sleep, "the numbers stay")
        XCTAssertFalse(element(app, "today.refreshIssue").exists)
    }

    /// Criteria 7, 8, 9: nothing cached and today and history both answer 503. After one pass the card
    /// shows, the line reads "Couldn't load today · Details", tapping it scrolls to the card, and Details
    /// opens the sheet with its request ID.
    @MainActor
    func testNothingCachedAndFailingShowsTheCardAndItsDetails() throws {
        let app = launch(fault: "/v1/days/today=503,/v1/days=503")
        let card = element(app, "today.refreshIssue")

        // The line's own identifier wins over the `.issue` case's inner one, so it is found by its text.
        let issueLine = line(app)
        wait(for: "label BEGINSWITH \"Couldn't load today\"", on: issueLine, timeout: 20, "the line points to the card")

        XCTAssertTrue(issueLine.label.contains("Details"), issueLine.label)

        // The card is last on Today: below the fold until the line is tapped.
        issueLine.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the card")
        // The card's identifier replaces its children's (`refreshIssue.details` is not exposed), so its
        // buttons are "today.refreshIssue" in order: Try again, Details.
        let cardButtons = app.buttons.matching(identifier: "today.refreshIssue")
        XCTAssertEqual(cardButtons.count, 2, "Try again and Details")
        let details = cardButtons.element(boundBy: 1)
        wait(for: "isHittable == true", on: details, timeout: 5, "the card scrolled into view")

        details.tap()
        let requestID = element(app, "refreshDetails.requestID")
        XCTAssertTrue(requestID.waitForExistence(timeout: 5), "the sheet's request ID row")
        XCTAssertTrue(requestID.label.contains("fault-"), requestID.label)
    }
}
