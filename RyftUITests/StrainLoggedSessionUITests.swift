import XCTest

/// A workout's "Logged session" row from Strain's root, on demo data: four days back in the week strip, the strength
/// workout that a Train session belongs to, then its session (review S2; My Day's full screen is `MyDayUITests`).
final class StrainLoggedSessionUITests: XCTestCase {
    /// Generous: a cold simulator on CI loads Strain, then the day's workouts.
    private let wait: TimeInterval = 45
    /// MockData's day index 85, workout 1: the tracker's strength workout with a Train session.
    private let loggedStrength = "00000000-0000-4000-8000-000000000851"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testALoggedSessionOpensFromAWorkoutOnStrain() throws {
        let app = launchDemo(extra: ["-RyftTab", "strain"])
        let day = app.buttons["datestrip.day.\(dayString(daysBack: 4))"]
        XCTAssertTrue(day.waitForExistence(timeout: wait), "four days back in Strain's week strip")
        day.tap()

        let strength = app.buttons["strain.row.workout.\(loggedStrength)"]
        XCTAssertTrue(strength.waitForExistence(timeout: wait), "the strength workout on that day")
        app.reveal(strength)
        strength.tap()

        let logged = app.buttons["workout.session"]
        XCTAssertTrue(logged.waitForExistence(timeout: wait), "the workout's Logged session row")
        app.reveal(logged)
        logged.tap()
        XCTAssertTrue(app.descendants(matching: .any)["sessionDetail.header"].waitForExistence(timeout: wait),
                      "the session detail")
    }
}
