import XCTest

final class NutritionUITests: XCTestCase {
    @MainActor
    func testReviewScoreSearchAndSaveMeal() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftScreen", "nutrition", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Logged nutrients"].waitForExistence(timeout: 12))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Nutrition diary with incomplete coverage"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let score = app.buttons["nutrition.score"]
        if !score.isHittable { app.swipeUp() }
        score.tap()
        XCTAssertTrue(app.staticTexts["Daily scores"].waitForExistence(timeout: 8))
        app.buttons["subpage.back"].tap()

        let log = app.buttons["nutrition.logMeal"]
        for _ in 0..<4 where !log.isHittable { app.swipeUp() }
        XCTAssertTrue(log.waitForExistence(timeout: 8))
        XCTAssertTrue(log.isEnabled)
        log.tap()
        searchAndSaveMeal(in: app)
    }

    @MainActor
    func testGermanDiaryFindsApfelAndPreviewsMeasuredPortion() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftScreen", "nutrition", "-RyftNutritionDiaryOnly",
                               "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Erfasste Nährstoffe"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["nutrition.score"].exists)
        let log = app.buttons["nutrition.logMeal"]
        for _ in 0..<4 where !log.isHittable { app.swipeUp() }
        XCTAssertTrue(log.exists && log.isHittable)
        log.tap()
        let query = app.textFields["nutrition.foodQuery"]
        XCTAssertTrue(query.waitForExistence(timeout: 8))
        query.tap()
        query.typeText("Apf")
        let match = app.buttons["nutrition.food.a7e40c6e-bfb4-47eb-ad64-aea61136db01"]
        XCTAssertTrue(match.waitForExistence(timeout: 8))
        XCTAssertTrue(match.label.contains("Apfel"))
        match.tap()
        XCTAssertTrue(app.staticTexts["Für diese Menge"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["78 kcal"].exists)
        XCTAssertTrue(app.staticTexts["150 g"].exists)
        XCTAssertTrue(app.buttons["Zur Mahlzeit hinzufügen"].exists)
    }

    @MainActor
    func testTodayQuickLogOpensMealEditorAndReturnsToDiaryAfterSave() {
        continueAfterFailure = false
        let app = launchDemo(extra: ["-RyftScreen", "nutrition", "-RyftNutritionQuickLog"])
        let plus = app.buttons["today.quickLog"]
        XCTAssertTrue(plus.waitForExistence(timeout: 12))
        XCTAssertLessThanOrEqual(plus.frame.maxY, app.tabBar.frame.minY)
        plus.tap()

        let log = app.buttons["today.quickLog.meal"]
        XCTAssertTrue(log.waitForExistence(timeout: 8))
        log.tap()
        searchAndSaveMeal(in: app)
        XCTAssertTrue(app.buttons["nutrition.logMeal"].exists)
        XCTAssertFalse(plus.isHittable)

        app.buttons["subpage.back"].tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 8))
        XCTAssertTrue(plus.isHittable)
    }

    @MainActor
    private func searchAndSaveMeal(in app: XCUIApplication) {
        let query = app.textFields["nutrition.foodQuery"]
        XCTAssertTrue(query.waitForExistence(timeout: 8))
        query.tap()
        query.typeText("a")
        let match = app.buttons["nutrition.food.a7e40c6e-bfb4-47eb-ad64-aea61136db01"]
        XCTAssertFalse(match.exists)
        query.typeText("pple")
        XCTAssertTrue(match.waitForExistence(timeout: 8))
        let quickAdd = app.buttons["nutrition.quickAdd.a7e40c6e-bfb4-47eb-ad64-aea61136db02"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 8))
        quickAdd.tap()
        XCTAssertTrue(app.staticTexts["Foods in meal: 1"].exists)
        match.tap()
        let include = app.buttons["Add to meal"]
        XCTAssertTrue(include.waitForExistence(timeout: 8))
        include.tap()
        let review = app.buttons["nutrition.reviewMeal"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Foods in meal: 2"].exists)
        review.tap()

        XCTAssertTrue(app.buttons["Remove Apple Juice"].exists)
        XCTAssertTrue(app.buttons["Remove Apple"].exists)

        let save = app.buttons["nutrition.meal.save"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        save.tap()
        XCTAssertTrue(app.buttons["nutrition.meal.ea0ac98d-9c71-410d-ac6a-61ce6f97f092"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testPendingMealCanBeRetriedAndRestoresLogMealAction() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftScreen", "nutrition", "-RyftNutritionPendingMeal",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let retry = app.buttons["nutrition.pending.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 12))
        let log = app.buttons["nutrition.logMeal"]
        XCTAssertFalse(log.exists)
        for _ in 0..<4 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.isEnabled)
        retry.tap()

        XCTAssertTrue(app.buttons["nutrition.meal.ea0ac98d-9c71-410d-ac6a-61ce6f97f092"].waitForExistence(timeout: 10))
        XCTAssertTrue(log.waitForExistence(timeout: 8))
        XCTAssertTrue(log.isEnabled)
        XCTAssertFalse(retry.exists)
    }
}
