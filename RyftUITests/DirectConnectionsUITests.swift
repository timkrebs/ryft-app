import XCTest

final class DirectConnectionsUITests: XCTestCase {
    @MainActor
    func testLocalGarminScreenRejectsPublicPairingHost() {
        continueAfterFailure = false
        let app = launchDemo(extra: ["-RyftScreen", "devices"])
        let row = app.buttons["devices.garminLocal"]
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        app.reveal(row)
        row.tap()
        let link = app.secureTextFields["devices.garminLocal.pairing"]
        XCTAssertTrue(link.waitForExistence(timeout: 8))
        link.tap()
        link.typeText("https://api.ryftlab.de:8785")
        app.buttons["devices.garminLocal.fetch"].tap()
        XCTAssertTrue(app.staticTexts["Paste the complete pairing link printed by the local API."].waitForExistence(timeout: 8))
    }

    @MainActor
    func testOnboardingOffersSignInForTheSelectedTracker() {
        continueAfterFailure = false
        let app = launchDemo(extra: ["-RyftScreen", "wear", "-RyftOnboardingConnectionsFixture"])
        let garmin = app.buttons["wear.tile.garmin"]
        XCTAssertTrue(garmin.waitForExistence(timeout: 12))
        garmin.tap()
        app.buttons["wear.continue"].tap()

        let signIn = app.buttons["wear.connect.garmin"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["wear.connect.status.suunto"].exists)
        signIn.tap()
        let status = app.descendants(matching: .any)["wear.connect.status.garmin"]
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Connected · Waiting for data"),
                                                   object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 8), .completed)
        XCTAssertFalse(signIn.exists)
        XCTAssertTrue(app.buttons["wear.connect.continue"].isEnabled)
    }

    @MainActor
    func testOnboardingLetsUnconfiguredTrackerContinue() {
        continueAfterFailure = false
        let app = launchDemo(extra: ["-RyftScreen", "wear", "-RyftOnboardingConnectionsFixture"])
        let suunto = app.buttons["wear.tile.suunto"]
        XCTAssertTrue(suunto.waitForExistence(timeout: 12))
        app.reveal(suunto)
        suunto.tap()
        app.buttons["wear.continue"].tap()

        let status = app.descendants(matching: .any)["wear.connect.status.suunto"]
        let comingSoon = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Coming soon"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [comingSoon], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["wear.connect.suunto"].exists)
        app.buttons["wear.connect.continue"].tap()
        XCTAssertTrue(suunto.waitForExistence(timeout: 8))
    }

    @MainActor
    func testProviderStatusAndExplicitDisconnect() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        app.launchArguments = ["-demoMode", "YES", "-coachMarks.today.done", "YES", "-RyftScreen", "devices",
                               "-RyftDirectConnectionsFixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let garmin = app.buttons["devices.direct.garmin"]
        for _ in 0..<6 where !(garmin.exists && garmin.isHittable) { app.swipeUp() }
        XCTAssertTrue(garmin.waitForExistence(timeout: 12))
        garmin.tap()
        let status = app.descendants(matching: .any)["devices.direct.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        XCTAssertEqual(status.value as? String, "Coming soon")
        XCTAssertFalse(app.buttons["devices.direct.connect"].exists)
        capture(app, name: "Garmin partner onboarding")

        app.buttons["subpage.back"].tap()
        let suunto = app.buttons["devices.direct.suunto"]
        for _ in 0..<6 where !(suunto.exists && suunto.isHittable) { app.swipeUp() }
        XCTAssertTrue(suunto.waitForExistence(timeout: 8))
        suunto.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        XCTAssertEqual(status.value as? String, "Connected")
        XCTAssertTrue(app.staticTexts["Last data received"].exists)
        capture(app, name: "Suunto connected")

        let disconnect = app.buttons["devices.direct.disconnect"]
        XCTAssertTrue(disconnect.waitForExistence(timeout: 8))
        disconnect.tap()
        let delete = app.buttons["Disconnect and delete direct data"]
        XCTAssertTrue(delete.waitForExistence(timeout: 8))
        delete.tap()
        let connect = app.buttons["devices.direct.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 8))
        XCTAssertEqual(status.value as? String, "Available to connect")
        connect.tap()
        XCTAssertTrue(app.staticTexts["The provider couldn't complete the connection. Try again later."].waitForExistence(timeout: 8))
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
