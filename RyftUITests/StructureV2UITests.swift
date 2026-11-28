import XCTest

final class StructureV2UITests: XCTestCase {
    @MainActor
    func testTabsProfileAndQuickLogInDemo() {
        continueAfterFailure = false
        let app = launchDemo(extra: ["-RyftFlags", "app.structure_v2", "-RyftResetTrain", "YES"])
        XCTAssertTrue(app.tabBar.waitForExistence(timeout: 12))
        for (index, tab) in ["today", "sleep", "strain", "nutrition", "insights"].enumerated() {
            XCTAssertTrue(app.tab(tab).exists, tab)
            XCTAssertEqual(app.tab(tab).value as? String, "Tab \(index + 1) of 5")
        }
        XCTAssertEqual(app.tab("strain").label, "Fitness")
        XCTAssertFalse(app.tab("profile").exists)
        XCTAssertFalse(app.buttons["today.quickLog"].exists)
        XCTAssertFalse(app.buttons["today.header.sync"].exists)

        app.buttons["header.avatar"].tap()
        let identity = app.descendants(matching: .any)["profile.identity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 6))
        app.buttons["profile.done"].tap()
        waitForAbsence(of: identity, timeout: 6, "Profile closes")

        app.buttons["header.quickLog"].tap()
        let workout = app.buttons["quickLog.workout"]
        XCTAssertTrue(workout.waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["quickLog.meal"].exists)
        XCTAssertFalse(app.buttons["quickLog.barcode"].exists)
        workout.tap()
        XCTAssertTrue(app.buttons["train.start.empty"].waitForExistence(timeout: 6))
        app.buttons["sheet.close"].tap()
        waitForAbsence(of: app.buttons["train.start.empty"], timeout: 6, "Start workout closes")

        app.tab("nutrition").tap()
        XCTAssertTrue(app.staticTexts["Nutrition isn't part of Demo data."].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["header.quickLog"].exists)
        XCTAssertTrue(app.buttons["header.avatar"].exists)
    }

    @MainActor
    func testNutritionAndProfileSheetLaunchArguments() {
        continueAfterFailure = false
        let app = launchDemo(extra: ["-RyftFlags", "app.structure_v2", "-RyftTab", "nutrition", "-RyftProfileSheet", "YES"])
        let done = app.buttons["profile.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 12))
        done.tap()
        waitForAbsence(of: done, timeout: 6, "Profile opens once")
        XCTAssertTrue(app.staticTexts["Nutrition isn't part of Demo data."].waitForExistence(timeout: 6))
        XCTAssertTrue(app.tab("nutrition").isSelected)
    }
}
