import XCTest

final class HomeSyncIndicatorUITests: XCTestCase {
    @MainActor
    func testTapSyncsAndProfileShowsTheSameAge() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftTab", "today", "-coachMarks.today.done", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let sync = app.buttons["today.header.sync"]
        XCTAssertTrue(sync.waitForExistence(timeout: 15))
        XCTAssertTrue((sync.value as? String)?.contains("never synced") == true)
        sync.tap()
        let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@ OR value BEGINSWITH %@",
                                                                       "Syncing", "Up to date"), object: sync)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 10), .completed)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@",
                                                                         "Up to date, synced "), object: sync)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 10), .completed)
        let age = (sync.value as? String ?? "").replacingOccurrences(of: "Up to date, synced ", with: "")
        XCTAssertFalse(age.isEmpty)

        app.buttons["tab.profile"].tap()
        let devices = app.buttons["profile.devices"]
        XCTAssertTrue(devices.waitForExistence(timeout: 5))
        let bottom = app.tabBar.frame.minY
        for _ in 0..<4 where !devices.isHittable || devices.frame.maxY >= bottom { app.swipeUp() }
        devices.tap()
        let lastSync = app.descendants(matching: .any)["profile.lastSync"].firstMatch
        XCTAssertTrue(lastSync.waitForExistence(timeout: 5))
        for _ in 0..<8 where !lastSync.isHittable || lastSync.frame.maxY >= bottom { app.swipeUp() }
        XCTAssertTrue(lastSync.exists)
        XCTAssertEqual(lastSync.value as? String, age)
    }
}
