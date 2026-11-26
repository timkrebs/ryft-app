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
        XCTAssertTrue(app.staticTexts["94,6 kcal"].exists)
        XCTAssertTrue(app.staticTexts["25,1 g"].exists)
        XCTAssertTrue(app.staticTexts["0,5 g"].exists)
        XCTAssertTrue(app.staticTexts["0,3 g"].exists)
        let small = app.buttons["nutrition.portion.small"]
        let medium = app.buttons["nutrition.portion.medium"]
        let large = app.buttons["nutrition.portion.large"]
        XCTAssertTrue(small.exists && medium.exists && large.exists)
        XCTAssertTrue(small.label.contains("Klein") && small.label.contains("149 g"))
        XCTAssertTrue(medium.label.contains("Mittel") && medium.label.contains("182 g"))
        XCTAssertTrue(large.label.contains("Groß") && large.label.contains("223 g"))
        let half = app.buttons["nutrition.quantity.multiplier.0.5"]
        XCTAssertEqual(half.label, "0,5×")
        XCTAssertEqual(app.buttons["nutrition.quantity.multiplier.1.0"].label, "1×")
        XCTAssertEqual(app.buttons["nutrition.quantity.multiplier.1.5"].label, "1,5×")
        XCTAssertEqual(app.buttons["nutrition.quantity.multiplier.2.0"].label, "2×")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Nutrition apple portions in German"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        large.tap()
        half.tap()
        XCTAssertTrue(app.staticTexts["111,5 g"].exists)
        XCTAssertTrue(app.staticTexts["58 kcal"].exists)
        app.buttons["nutrition.measure.grams"].tap()
        XCTAssertTrue(app.staticTexts["52 kcal"].exists)
        app.buttons["nutrition.quantity.increase"].tap()
        XCTAssertTrue(app.staticTexts["57,2 kcal"].exists)
        XCTAssertTrue(app.buttons["Zur Mahlzeit hinzufügen"].exists)
    }

    @MainActor
    func testQuickAddUndoEditAndReopenKeepsThePortionSnapshot() {
        continueAfterFailure = false
        let app = openGermanMealPicker()
        let query = app.textFields["nutrition.foodQuery"]
        query.tap()
        query.typeText("Apfe")
        let plus = app.buttons["nutrition.quickAdd.a7e40c6e-bfb4-47eb-ad64-aea61136db01"]
        XCTAssertTrue(plus.waitForExistence(timeout: 8))
        plus.tap()
        let undo = app.buttons["nutrition.undoQuickAdd"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertFalse(app.buttons["nutrition.reviewMeal"].exists)
        plus.tap()
        app.buttons["nutrition.editQuickAdd"].tap()

        let large = app.buttons["nutrition.portion.large"]
        XCTAssertTrue(large.waitForExistence(timeout: 8))
        large.tap()
        app.buttons["nutrition.quantity.decrease"].tap()
        app.buttons["Menge übernehmen"].tap()

        let review = app.buttons["nutrition.reviewMeal"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        review.tap()
        let snapshot = NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Großer Apfel", "111,5 g")
        XCTAssertTrue(app.buttons.containing(snapshot).firstMatch.exists)
        let save = app.buttons["nutrition.meal.save"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        save.tap()
        let meal = app.buttons["nutrition.meal.ea0ac98d-9c71-410d-ac6a-61ce6f97f092"]
        XCTAssertTrue(meal.waitForExistence(timeout: 10))
        meal.tap()
        let savedItem = app.buttons.containing(snapshot).firstMatch
        XCTAssertTrue(savedItem.waitForExistence(timeout: 8))
        let back = app.buttons["subpage.back"]
        app.buttons["nutrition.addFood"].tap()
        XCTAssertTrue(app.textFields["nutrition.foodQuery"].waitForExistence(timeout: 8))
        back.tap()
        XCTAssertTrue(savedItem.waitForExistence(timeout: 8))
        XCTAssertTrue(back.isHittable)
        back.tap()
        let logMeal = app.buttons["nutrition.logMeal"]
        XCTAssertTrue(logMeal.waitForExistence(timeout: 8))
        for _ in 0..<4 where !logMeal.isHittable { app.swipeUp() }
        logMeal.tap()
        cancelMealSearch(in: app)
        XCTAssertTrue(logMeal.waitForExistence(timeout: 8))
        XCTAssertTrue(meal.exists)
    }

    @MainActor
    func testQuickAddWithoutAReusableSelectionOpensAmounts() {
        continueAfterFailure = false
        let app = openGermanMealPicker()
        let query = app.textFields["nutrition.foodQuery"]
        query.tap()
        query.typeText("Kaka")
        let plus = app.buttons["nutrition.quickAdd.a7e40c6e-bfb4-47eb-ad64-aea61136db03"]
        XCTAssertTrue(plus.waitForExistence(timeout: 8))
        plus.tap()
        XCTAssertTrue(app.buttons["nutrition.measure.grams"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["nutrition.reviewMeal"].exists)
    }

    @MainActor
    private func openGermanMealPicker() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftScreen", "nutrition", "-RyftNutritionDiaryOnly",
                               "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        let log = app.buttons["nutrition.logMeal"]
        XCTAssertTrue(log.waitForExistence(timeout: 12))
        for _ in 0..<4 where !log.isHittable { app.swipeUp() }
        log.tap()
        XCTAssertTrue(app.textFields["nutrition.foodQuery"].waitForExistence(timeout: 8))
        return app
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
        cancelMealSearch(in: app)
        XCTAssertTrue(plus.waitForExistence(timeout: 8))
        XCTAssertTrue(plus.isHittable)
        plus.tap()
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
    private func cancelMealSearch(in app: XCUIApplication) {
        let query = app.textFields["nutrition.foodQuery"]
        XCTAssertTrue(query.waitForExistence(timeout: 8))
        query.tap()
        query.typeText("Apf")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let back = app.buttons["subpage.back"]
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(query.waitForNonExistence(timeout: 8))
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
