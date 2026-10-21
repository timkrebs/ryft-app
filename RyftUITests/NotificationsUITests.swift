import XCTest

/// Profile → Notifications while `push.enabled` hasn't reached the account (demo mode): what
/// will come, as words, and no switch that looks on.
final class NotificationsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRollingOutShowsNoSwitches() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftScreen", "notifications", "-appearance", "dark",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let notice = app.descendants(matching: .any)["notifications.rollingOut"]
        XCTAssertTrue(notice.waitForExistence(timeout: 15), "the rollout notice")
        XCTAssertTrue(app.staticTexts["Morning score"].exists, "what will come, as a list")
        XCTAssertEqual(app.switches.count, 0, "no switch while nothing can be sent")
        XCTAssertFalse(app.descendants(matching: .any)["notifications.denied"].exists)
    }
}
