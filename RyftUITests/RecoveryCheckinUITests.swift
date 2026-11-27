import XCTest

final class RecoveryCheckinUITests: XCTestCase {
    @MainActor
    func testDemoMorningCheckin() {
        continueAfterFailure = false
        let app = launchDemo(extra: ["-RyftFlags", "recovery.checkin"])
        let card = app.descendants(matching: .any)["checkin.card"].firstMatch
        let open = app.buttons["checkin.open"]
        XCTAssertTrue(card.waitForExistence(timeout: 12))
        app.reveal(open)
        open.tap()

        let sheet = app.descendants(matching: .any)["checkin.sheet"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        // The mock suggests 23:00 – 07:00; before 07:00 the wake starts at now (rounded down to 5 min), so the times are
        // valid at any hour (at least 60 min after 23:00) and the test doesn't depend on the clock.
        XCTAssertTrue(app.descendants(matching: .any)["checkin.dial.wake"].firstMatch.exists)

        let quality = app.buttons["checkin.quality.7"]
        let freshness = app.buttons["checkin.freshness.6"]
        app.reveal(quality)
        quality.tap()
        app.reveal(freshness)
        freshness.tap()
        let save = app.buttons["checkin.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let done = app.staticTexts["checkin.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        XCTAssertEqual(done.label, "Checked in")
    }
}
