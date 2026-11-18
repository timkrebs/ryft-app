import XCTest

/// PR 6 A in the running app: Welcome's ways in, the pushed forms with their own header (the navigation bar is hidden, the
/// back swipe still pops), and consent's tick before Agree. On the Debug screens (`-RyftScreen welcome-parked | consent`) in
/// demo mode: no server, no session. Elements are found by identifier and English words (the launch pins the language).
final class SignedOutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-RyftScreen", screen, "-coachMarks.today.done", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// "Have an account? Log in" opens Log in (its header, the two fields, Back); the edge swipe brings Welcome back.
    @MainActor
    func testLogInOpensAndTheBackSwipePopsIt() throws {
        let app = launch("welcome-parked")
        let logIn = app.buttons["welcome.logIn"]
        XCTAssertTrue(logIn.waitForExistence(timeout: 15), "Welcome's Log in")
        XCTAssertTrue(app.buttons["welcome.createAccount"].exists)
        app.reveal(logIn)
        logIn.tap()

        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "Log in's email field")
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        XCTAssertTrue(app.buttons["subpage.back"].exists, "the header's Back")
        XCTAssertFalse(app.buttons["logIn.submit"].isEnabled, "nothing typed yet")

        // The system's back swipe, from the left edge at mid-height, with the bar hidden and the keyboard up (Email has it).
        // A slow drag: it's the one a scroll view's pan used to take before the edge swipe could (`InteractivePopGestureKeeper`).
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        waitForAbsence(of: email, timeout: 5, "the swipe popped Log in")
        XCTAssertTrue(logIn.waitForExistence(timeout: 5), "back on Welcome")
    }

    /// Create account: three fields, Back pops it.
    @MainActor
    func testCreateAccountHasItsThreeFields() throws {
        let app = launch("welcome-parked")
        let create = app.buttons["welcome.createAccount"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        app.reveal(create)
        create.tap()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Email"].exists && app.secureTextFields["Password"].exists)
        XCTAssertTrue(app.buttons["createAccount.submit"].exists)
        app.buttons["subpage.back"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5), "back on Welcome")
    }

    /// Consent: Agree waits for the tick; the tick is a button with the selected state.
    @MainActor
    func testConsentAgreeWaitsForTheTick() throws {
        let app = launch("consent")
        let box = app.descendants(matching: .any)["consent.checkbox"]
        XCTAssertTrue(box.waitForExistence(timeout: 15), "the checkbox")
        let agree = app.buttons["consent.agree"]
        app.reveal(agree)
        XCTAssertFalse(agree.isEnabled, "not before the tick")
        app.reveal(box)
        box.tap()
        XCTAssertTrue(agree.isEnabled, "ticked")
        XCTAssertTrue(app.descendants(matching: .any)["consent.minimumAge"].exists)
    }
}
