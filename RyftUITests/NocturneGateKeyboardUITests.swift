import XCTest

/// Nocturne gate G3 with real touches (docs/work/2026-11-20-nocturne-gate/design.md §2.5 D5, §2.9 D9 row 5, §5.3): Report a
/// problem's Done and Send in the pinned bar above the keyboard; Add activity's Save with the keyboard up; About you's birth
/// year chosen from its menu row at AX3. Demo mode (no server), US English; every wait is on a condition.
final class NocturneGateKeyboardUITests: XCTestCase {
    private let wait: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// `element` is hittable and wholly above the software keyboard, which is up.
    private func assertAboveTheKeyboard(_ element: XCUIElement, _ keyboard: XCUIElement, _ name: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.isHittable, "\(name) is hittable", file: file, line: line)
        XCTAssertTrue(keyboard.exists, "the keyboard is up", file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxY, keyboard.frame.minY + 0.5,
                                 "\(name) \(element.frame) above the keyboard \(keyboard.frame)", file: file, line: line)
    }

    /// Waits for the software keyboard after a field took focus; skips the test when none shows (the simulator's hardware
    /// keyboard is connected), so it never passes without proving where the bar sits against the keyboard.
    private func softwareKeyboard(_ app: XCUIApplication) throws -> XCUIElement {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            throw XCTSkip("No software keyboard showed (the simulator's hardware keyboard is connected: I/O → Keyboard → "
                + "Connect Hardware Keyboard off), so the test can't prove the controls sit above it.")
        }
        return keyboard
    }

    // MARK: D5: Report a problem

    /// AX3 for a launch: the content size the hosted tests call `.accessibility3`.
    private static let ax3 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]

    /// Type → the bar is Done · Send, both above the keyboard, and the keyboard has no Done of its own; Done closes the
    /// keyboard and Send stands alone; typing again and tapping Send with the keyboard up sends.
    @MainActor
    func testReportDoneAndSendRideTheKeyboard() throws {
        try reportDoneAndSend(stacked: false, shot: "report-keyboard-up")
    }

    /// The same at AX3, where the pills stack: Send above Done.
    @MainActor
    func testReportDoneAndSendRideTheKeyboardAtAX3() throws {
        try reportDoneAndSend(extra: Self.ax3, stacked: true, shot: "report-keyboard-up-ax3")
    }

    @MainActor
    private func reportDoneAndSend(extra: [String] = [], stacked: Bool, shot: String) throws {
        let app = launchDemo(extra: ["-RyftScreen", "report-problem"] + extra)
        let message = element(app, "report.message")
        XCTAssertTrue(message.waitForExistence(timeout: wait), "the message field")
        let send = app.buttons["report.send"], done = app.buttons["report.done"]
        XCTAssertTrue(send.waitForExistence(timeout: wait), "Send in the bar")
        XCTAssertFalse(done.exists, "no Done before the message has focus")

        message.tap()
        let keyboard = try softwareKeyboard(app)
        message.typeText("The sleep chart is empty")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Done joins Send while the message has focus")
        assertAboveTheKeyboard(done, keyboard, "Done")
        assertAboveTheKeyboard(send, keyboard, "Send")
        if stacked {
            XCTAssertLessThanOrEqual(send.frame.maxY, done.frame.minY + 0.5, "Send above Done: \(send.frame) \(done.frame)")
        } else {
            XCTAssertLessThan(done.frame.maxX, send.frame.minX, "Done leading, Send trailing: \(done.frame) \(send.frame)")
        }
        XCTAssertEqual(app.toolbars.buttons["Done"].exists, false, "no keyboard toolbar")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Done'")).count, 1, "one Done: the bar's")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = shot
        attachment.lifetime = .keepAlways
        add(attachment)

        done.tap()
        waitForAbsence(of: keyboard, timeout: 5, "Done closes the keyboard")
        waitForAbsence(of: done, timeout: 5, "Send alone once the message has no focus")
        XCTAssertTrue(send.isHittable)
        XCTAssertEqual(message.value as? String, "The sleep chart is empty", "what was typed stays")

        message.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "the keyboard again")
        message.typeText(", twice")
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        assertAboveTheKeyboard(send, keyboard, "Send")
        send.tap()
        XCTAssertTrue(element(app, "report.sent").waitForExistence(timeout: wait), "Send with the keyboard up sends")
    }

    // MARK: Add activity

    /// Add activity keeps its Save in the header and the keyboard's Done (nothing pinned sits above the keyboard there):
    /// with the keyboard up in Notes, Save is hittable.
    @MainActor
    func testAddActivitySaveIsHittableWithTheKeyboardUp() throws {
        let app = launchDemo(openMyDayDaysBack: 0)
        let plus = app.buttons["myday.add"]
        XCTAssertTrue(plus.waitForExistence(timeout: wait), "the plus menu")
        plus.tap()
        let entry = app.buttons["myday.add.activity"]
        XCTAssertTrue(entry.waitForExistence(timeout: wait), "Add activity in the plus menu")
        entry.tap()
        XCTAssertTrue(app.otherElements["addActivity.sheet"].waitForExistence(timeout: wait), "the Add activity sheet")
        let notes = app.textViews["addActivity.notes"].waitForExistence(timeout: 5)
            ? app.textViews["addActivity.notes"] : app.textFields["addActivity.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: wait), "Notes")
        notes.tap()
        let keyboard = try softwareKeyboard(app)
        notes.typeText("Easy spin")
        let save = app.buttons["addActivity.save"]
        XCTAssertTrue(save.exists)
        assertAboveTheKeyboard(save, keyboard, "Save")
    }

    // MARK: D9 row 5: About you at AX3

    /// At AX3 the birth year is a menu row: a year chosen from its menu shows as the row's value and lets Continue go.
    @MainActor
    func testAboutYouBirthYearFromTheMenuRowAtAX3() throws {
        let app = launchDemo(extra: ["-RyftScreen", "aboutYou"] + Self.ax3)
        let row = app.buttons["aboutYou.year"]
        XCTAssertTrue(row.waitForExistence(timeout: wait), "the Birth year row")
        // With the status bar and the home indicator the row starts above the pinned bar; a short scroll brings it whole.
        app.reveal(row)
        XCTAssertTrue(row.isHittable, "the row above the pinned bar")
        XCTAssertEqual(app.pickerWheels.count, 0, "no wheel at AX3")
        let save = app.buttons["aboutYou.save"]
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled, "Continue waits for a year")
        row.tap()
        let year = app.buttons.matching(NSPredicate(format: "label MATCHES '^[0-9]{4}$'")).firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 5), "the years in the menu")
        let chosen = year.label
        year.tap()
        let shown = expectation(for: NSPredicate(format: "value == %@", chosen), evaluatedWith: row)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 5), .completed,
                       "the row shows \(chosen): '\(row.label)' '\(String(describing: row.value))'")
        XCTAssertTrue(save.isEnabled, "Continue once a year is chosen")
    }
}
