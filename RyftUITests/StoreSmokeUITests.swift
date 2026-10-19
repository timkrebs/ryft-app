import XCTest

/// The App Review walkthrough: Welcome → Log in → every tab → Profile → Delete account → Cancel.
///
/// The signed-in test needs the reviewer demo account and skips without it. Credentials
/// never live in the repo; pass them to the test runner, e.g.
/// `TEST_RUNNER_RYFT_DEMO_EMAIL=… TEST_RUNNER_RYFT_DEMO_PASSWORD=… xcodebuild test …`.
final class StoreSmokeUITests: XCTestCase {
    private let tabs = ["Today", "Sleep", "Strain", "Insights", "Profile"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(demo: Bool) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", demo ? "YES" : "NO", "-RyftTab", "today", "-appearance", "dark", "-coachMarks.today.done", "YES"]
        app.launch()
        return app
    }

    /// Visits every tab and checks it became the selected one.
    private func walkTabs(_ app: XCUIApplication) {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "signed in, tabs visible")
        for name in tabs {
            let tab = bar.buttons[name]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), name)
            tab.tap()
            XCTAssertTrue(tab.isSelected, "\(name) selected")
        }
    }

    /// Scrolls until `element` can be tapped.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.isHittable && tries < 10 {
            app.swipeUp()
            tries += 1
        }
    }

    /// No server needed: demo data drives every tab.
    @MainActor
    func testDemoTabsWalkthrough() throws {
        let app = launch(demo: true)
        walkTabs(app)
        XCTAssertTrue(app.staticTexts["Demo data"].waitForExistence(timeout: 5), "Profile shows the demo switch")
    }

    @MainActor
    func testReviewerWalkthroughCancelsDeletion() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["RYFT_DEMO_EMAIL"], !email.isEmpty,
              let password = env["RYFT_DEMO_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Set RYFT_DEMO_EMAIL and RYFT_DEMO_PASSWORD for the test runner.")
        }
        let app = launch(demo: false)

        // A stored session from an earlier run: log out to start at Welcome.
        let bar = app.tabBars.firstMatch
        if bar.waitForExistence(timeout: 5) {
            bar.buttons["Profile"].tap()
            let logOut = app.buttons["Log out"]
            reveal(logOut, in: app)
            logOut.tap()
            app.sheets.buttons["Log out"].firstMatch.tap()
        }

        let welcomeLogIn = app.buttons["Log in"]
        XCTAssertTrue(welcomeLogIn.waitForExistence(timeout: 10), "Welcome")
        welcomeLogIn.tap()

        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["Log in"].firstMatch.tap()

        // The Health explanation comes once per account; the simulator has no data anyway.
        let notNow = app.buttons["health.notNow"]
        if notNow.waitForExistence(timeout: 15) { notNow.tap() }

        walkTabs(app)

        let delete = app.buttons["Delete account"]
        reveal(delete, in: app)
        delete.tap()
        let alert = app.alerts["Delete your RYFT account?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()

        XCTAssertFalse(alert.exists)
        XCTAssertTrue(app.buttons["Delete account"].exists, "still signed in")
        XCTAssertTrue(bar.buttons["Profile"].isSelected)
    }
}
