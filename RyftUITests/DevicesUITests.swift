import XCTest

/// "What do you wear?", the setup cards and Profile → Devices & sync in demo mode, where `devices.setup` is on:
/// the Debug screens (`-RyftScreen wear | tracker-setup | devices`) with a chosen set (`-RyftTrackers`). Elements
/// are found by identifier and English words (the launch pins the language). No snapshots.
final class DevicesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ screen: String?, trackers: String? = nil, tab: String = "today", flags: String? = nil) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        var arguments = ["-demoMode", "YES", "-coachMarks.today.done", "YES",
                         "-RyftTab", tab, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let screen { arguments += ["-RyftScreen", screen] }
        if let trackers { arguments += ["-RyftTrackers", trackers] }
        if let flags { arguments += ["-RyftFlags", flags] }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// A pushed page's title: `PushedHeader`'s one header element (`subpage.header`), by its label.
    private func header(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "subpage.header").matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Scrolls until `tile` sits above the pinned bar (`bar` is its top button): a tile under the bar still
    /// reports itself hittable, and a tap there lands on the bar.
    private func reveal(_ tile: XCUIElement, above bar: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where tile.frame.maxY >= bar.frame.minY { app.swipeUp() }
        XCTAssertLessThan(tile.frame.maxY, bar.frame.minY, "\(tile.identifier) clear of the pinned bar")
    }

    /// Several trackers at once; "Just my iPhone" clears them, any other tile clears it; Continue needs a choice.
    @MainActor
    func testThePickerTakesSeveralButJustMyIPhoneAlone() throws {
        let app = launch("wear")
        let garmin = app.buttons["wear.tile.garmin"]
        XCTAssertTrue(garmin.waitForExistence(timeout: 15), "the Garmin tile")
        let next = app.buttons["wear.continue"]
        XCTAssertFalse(next.isEnabled, "Continue waits for a choice")
        XCTAssertTrue(app.buttons["wear.skip"].isEnabled, "Skip never does")

        garmin.tap()
        app.buttons["wear.tile.oura"].tap()
        XCTAssertTrue(garmin.isSelected && app.buttons["wear.tile.oura"].isSelected, "a watch and a ring together")
        XCTAssertTrue(next.isEnabled)

        let iPhone = app.buttons["wear.tile.iphone"]
        reveal(iPhone, above: next, in: app)
        iPhone.tap()
        XCTAssertTrue(iPhone.isSelected)
        XCTAssertFalse(garmin.isSelected || app.buttons["wear.tile.oura"].isSelected, "Just my iPhone clears the others")

        // Back to the top, where Garmin's tile is clear of everything.
        app.swipeDown()
        app.swipeDown()
        garmin.tap()
        XCTAssertTrue(garmin.isSelected && !iPhone.isSelected, "another tile clears Just my iPhone")
    }

    /// Garmin's card: HRV is a fact ("Not shared"), not a fault; resting heart rate arrives; the features line says
    /// what Readiness needs; the store button is the App Store page.
    @MainActor
    func testGarminsCardSaysWhatDoesntReachRYFT() throws {
        let app = launch("tracker-setup", trackers: "garmin")
        XCTAssertTrue(element(app, "tracker.card.garmin").waitForExistence(timeout: 15), "Garmin's setup card")
        XCTAssertTrue(app.staticTexts["Set up your tracker"].exists, "the screen after Apple Health")
        let features = element(app, "tracker.features")
        XCTAssertTrue((features.label).contains("which Garmin Connect doesn't share"), "the features line: \(features.label)")
        let hrv = element(app, "tracker.capability.hrv")
        XCTAssertEqual(hrv.label, "Heart rate variability")
        XCTAssertTrue((hrv.value as? String ?? "").hasPrefix("Not shared"), "HRV: \(String(describing: hrv.value))")
        XCTAssertTrue((element(app, "tracker.capability.heart_rate").value as? String ?? "").hasPrefix("Arrives"))
        XCTAssertTrue((element(app, "tracker.capability.resting_hr").value as? String ?? "").hasPrefix("Arrives"))

        let store = app.buttons["tracker.open"]
        for _ in 0..<4 where !store.exists { app.swipeUp() }
        XCTAssertTrue(store.exists && store.label == "Garmin Connect in the App Store", "the App Store button: \(store.label)")
        XCTAssertTrue(app.buttons["trackerSetup.done"].exists && app.buttons["trackerSetup.later"].exists)
    }

    /// Fitbit, Garmin and Oura need setting up; the first card is open, the others collapsed to a row.
    @MainActor
    func testSeveralTrackersStackTheirCards() throws {
        let app = launch("tracker-setup", trackers: "apple_watch,garmin,oura")
        let garmin = element(app, "tracker.header.garmin")
        XCTAssertTrue(garmin.waitForExistence(timeout: 15), "Garmin's header")
        XCTAssertEqual(garmin.value as? String, "Expanded")
        XCTAssertEqual(element(app, "tracker.header.oura").value as? String, "Collapsed")
        XCTAssertFalse(element(app, "tracker.card.apple_watch").exists, "the Apple Watch needs no setup elsewhere")
        XCTAssertTrue(app.staticTexts["Set up your trackers"].exists)
    }

    /// Devices & sync: the choice, edited in the picker sheet; a tracker's card pushed from its row.
    @MainActor
    func testDevicesAndSyncEditsTheChoiceAndOpensACard() throws {
        let app = launch("devices", trackers: "garmin")
        let garmin = app.buttons["devices.row.garmin"]
        XCTAssertTrue(garmin.waitForExistence(timeout: 15), "Garmin's row")
        XCTAssertEqual(garmin.value as? String, "Not checked yet")
        XCTAssertTrue(element(app, "devices.seen").exists, "Seen in Apple Health")

        app.buttons["devices.edit"].tap()
        let oura = app.buttons["wear.tile.oura"]
        XCTAssertTrue(oura.waitForExistence(timeout: 5), "the picker sheet")
        oura.tap()
        app.buttons["wear.done"].tap()
        XCTAssertTrue(app.buttons["devices.row.oura"].waitForExistence(timeout: 5), "Oura joined the list")

        garmin.tap()
        XCTAssertTrue(element(app, "tracker.card.garmin").waitForExistence(timeout: 5), "Garmin's card, pushed")
        // The subpage frame (Nocturne): its own header, Back and the card's title (the pushed header's one element), no
        // navigation bar.
        XCTAssertTrue(app.buttons["subpage.back"].exists && header(app, "Garmin").exists)
    }

    /// Profile → Data's first row with `devices.setup` on (demo data's config): Devices & sync.
    @MainActor
    func testProfileLeadsToDevicesAndSync() throws {
        let app = launch(nil, tab: "profile", flags: "devices.setup")
        let row = app.buttons["profile.devices"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the Devices and sync row")
        for _ in 0..<6 where !row.isHittable || row.frame.maxY >= app.tabBar.frame.minY { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.buttons["subpage.back"].waitForExistence(timeout: 5), "the subpage frame's Back")
        XCTAssertTrue(header(app, "Devices & sync").exists, "its title")
        XCTAssertTrue(app.buttons["devices.row.apple_watch"].exists, "demo data wears an Apple Watch")
    }
}
