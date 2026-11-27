import XCTest

final class TodayQuickLogUITests: XCTestCase {
    @MainActor
    func testActivityAndWorkoutOpenFromToday() {
        continueAfterFailure = false
        let app = launchDemo(extra: ["-RyftResetTrain", "YES", "-RyftFlags",
                                     "today.my_day,activities.manual,train.enabled,nutrition.enabled"])
        let plus = app.buttons["today.quickLog"]
        XCTAssertTrue(plus.waitForExistence(timeout: 12))
        plus.tap()

        let activity = app.buttons["today.quickLog.activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["today.quickLog.meal"].exists, "Nutrition keeps its signed-in, non-demo gate")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Today Quick log"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        activity.tap()
        XCTAssertTrue(app.buttons["addActivity.save"].waitForExistence(timeout: 8))
        app.buttons["sheet.close"].tap()

        XCTAssertTrue(plus.waitForExistence(timeout: 8))
        plus.tap()
        let workout = app.buttons["today.quickLog.workout"]
        XCTAssertTrue(workout.waitForExistence(timeout: 8))
        XCTAssertEqual(workout.label, "Start workout")
        workout.tap()
        let empty = app.buttons["train.start.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 8))
        app.reveal(empty)
        empty.tap()
        let finish = app.buttons["session.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 8))
        app.buttons["Minimise"].tap()

        XCTAssertTrue(plus.waitForExistence(timeout: 8))
        XCTAssertTrue(app.tab("Today").isSelected)
        plus.tap()
        XCTAssertTrue(workout.waitForExistence(timeout: 8))
        XCTAssertEqual(workout.label, "Resume workout")
        workout.tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 8))
    }
}
