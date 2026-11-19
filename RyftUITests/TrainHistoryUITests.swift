import XCTest

/// History, the session detail and the exercise page on demo data (T6B.5, PR 6 B §7): Strain → History → a session → an
/// exercise → back twice, by identifiers and VoiceOver labels. The pages hide the navigation bar, so Back is each header's
/// circle; no snapshots.
final class TrainHistoryUITests: XCTestCase {
    /// Generous: a cold simulator on CI loads Strain, then Train's library.
    private let wait: TimeInterval = 45

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftTab", "strain", "-RyftResetTrain", "YES",
                               "-coachMarks.today.done", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        // As `FocusedSessionUITests`: the Strain tab being selected proves the arguments arrived; if not, one relaunch.
        let arrived = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: app.tab("Strain"))
        if XCTWaiter.wait(for: [arrived], timeout: 15) != .completed {
            app.terminate()
            app.launch()
        }
        return app
    }

    @MainActor
    func testHistoryOpensASessionAndItsExercise() throws {
        let app = launch()
        let history = app.buttons["train.history"]
        XCTAssertTrue(history.waitForExistence(timeout: wait), "Strain's History row")
        app.reveal(history)
        history.tap()

        // History: the header, then the rows (the activity row with its load).
        XCTAssertTrue(app.buttons["history.back"].waitForExistence(timeout: wait), "History's own Back")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: wait), "a session row")
        XCTAssertTrue(row.label.contains("Muscular load") || row.label.hasSuffix("No muscular load"), row.label)
        row.tap()

        // The session detail: Back, the strain numeral, the tiles and an exercise card.
        XCTAssertTrue(app.buttons["sessionDetail.back"].waitForExistence(timeout: wait), "the session's Back")
        let exercise = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sessionDetail.exercise.' AND identifier ENDSWITH '.open'"))
            .firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: wait), "an exercise card's name")
        app.reveal(exercise)
        exercise.tap()

        // The exercise page: its e1RM numeral leads.
        XCTAssertTrue(app.buttons["exerciseDetail.back"].waitForExistence(timeout: wait), "the exercise page's Back")
        let hero = app.descendants(matching: .any)["exerciseDetail.numeral"]
        XCTAssertTrue(hero.waitForExistence(timeout: wait), "the estimated 1RM")
        XCTAssertEqual(hero.label, "Estimated 1RM")

        // Back twice: the session, then History.
        app.buttons["exerciseDetail.back"].tap()
        XCTAssertTrue(app.buttons["sessionDetail.back"].waitForExistence(timeout: wait))
        app.buttons["sessionDetail.back"].tap()
        XCTAssertTrue(app.buttons["history.back"].waitForExistence(timeout: wait))
    }
}
