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
        // The mock suggests 07:00 every day. Before then, set wake to midnight,
        // which leaves one hour from the suggested 23:00 bedtime.
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        if (now.hour ?? 0) * 60 + (now.minute ?? 0) < 7 * 60 - 5 {
            let dial = app.descendants(matching: .any)["checkin.dial"].firstMatch
            let wake = app.descendants(matching: .any)["checkin.dial.wake"].firstMatch
            XCTAssertTrue(wake.exists)
            let top = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: 22))
            wake.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: top)
        }

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
