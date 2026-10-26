import XCTest

/// Add activity, Add sleep and the activity detail on demo data (`-demoMode YES`: no server, no HealthKit; demo's
/// remote config has `today.my_day` and `activities.manual` on). Driven from the full My Day screen
/// (`-RyftOpenMyDay 0`) and found by identifiers; the words asserted are English because the launch pins the
/// language. The demo day: a night from Apple Health, mobility, the merged run, a walk, yoga.
///
/// Times come from the real clock. The form's default window is the last hour ending now, so in the first hour after
/// midnight it starts yesterday: those tests skip then (`openAddActivity`).
final class AddActivityUITests: XCTestCase {
    /// Generous: a cold simulator on CI loads Today, then the activities read.
    private let wait: TimeInterval = 45

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        launchDemo(openMyDayDaysBack: 0, extra: extra)
    }

    /// `activities.manual` off for this launch (Debug: the saved overrides, which beat demo's remote config).
    private static let manualOff = ["-flags.overrides", "<dict><key>activities.manual</key><false/></dict>"]

    private func day(daysBack back: Int) -> String { dayString(daysBack: back) }

    private func waitForAbsence(of element: XCUIElement, _ message: String) {
        waitForAbsence(of: element, timeout: wait, message)
    }

    // MARK: My Day

    /// Waits for the full screen with today's night loaded.
    private func openMyDay(extra: [String] = []) -> XCUIApplication {
        let app = launch(extra: extra)
        XCTAssertTrue(app.otherElements["myday.view"].waitForExistence(timeout: wait), "the full My Day screen")
        XCTAssertTrue(app.buttons["myday.view.row.sleep.\(day(daysBack: 0))"].waitForExistence(timeout: wait), "today's night")
        return app
    }

    /// ＋ → Add activity, with the sheet open and its default window inside today.
    private func openAddActivity(_ app: XCUIApplication) throws {
        let plus = app.buttons["myday.add"]
        XCTAssertTrue(plus.waitForExistence(timeout: wait), "the plus menu")
        plus.tap()
        let entry = app.buttons["myday.add.activity"]
        XCTAssertTrue(entry.waitForExistence(timeout: wait), "Add activity in the plus menu")
        entry.tap()
        XCTAssertTrue(app.otherElements["addActivity.sheet"].waitForExistence(timeout: wait), "the Add activity sheet")
        let start = app.datePickers["addActivity.start"]
        XCTAssertTrue(start.waitForExistence(timeout: wait))
        let startDate = start.buttons.element(boundBy: 1).label
        let endDate = app.datePickers["addActivity.end"].buttons.element(boundBy: 1).label
        try XCTSkipUnless(startDate == endDate, "the default window starts before midnight")
    }

    private func choose(sport: String, in app: XCUIApplication) {
        app.buttons["addActivity.sport"].tap()
        let row = app.buttons["sportPicker.sport.\(sport)"]
        XCTAssertTrue(row.waitForExistence(timeout: wait), "\(sport) in the sport list")
        row.tap()
        XCTAssertTrue(app.datePickers["addActivity.start"].waitForExistence(timeout: wait), "back on the form")
    }

    private func type(_ text: String, into identifier: String, in app: XCUIApplication) {
        // A multi-line field is a text view; Optional text fields are text fields.
        let view = app.textViews[identifier]
        let field = view.waitForExistence(timeout: 5) ? view : app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: wait), "the \(identifier) field")
        field.tap()
        field.typeText(text)
    }

    /// A My Day row of an activity named `name` (the row's VoiceOver sentence starts with it).
    private func activityRow(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'myday.view.row.activity.' AND label BEGINSWITH %@",
                                         "\(name),")).firstMatch
    }

    /// Adds a Climbing activity with the default window and `notes`; the sheet closes and the row shows.
    private func addClimbing(notes: String, in app: XCUIApplication) throws -> XCUIElement {
        try openAddActivity(app)
        choose(sport: "climbing", in: app)
        type(notes, into: "addActivity.notes", in: app)
        let save = app.buttons["addActivity.save"]
        XCTAssertTrue(save.isEnabled, "a valid form can be saved")
        save.tap()
        waitForAbsence(of: app.otherElements["addActivity.sheet"], "the sheet closes on Save")
        let row = activityRow("Climbing", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: wait), "the new row in My Day")
        return row
    }

    // MARK: time pickers

    /// Moves the start's hour to the end's, so both are the same minute (the end picker's range follows the start).
    /// Only the hour and AM/PM wheels move; the minute is already equal because the default start is an hour before.
    private func setStartToEnd(_ app: XCUIApplication) {
        let endTime = app.datePickers["addActivity.end"].buttons
            .matching(NSPredicate(format: "label MATCHES %@", "\\d{1,2}:\\d{2}.*")).firstMatch
        XCTAssertTrue(endTime.exists, "the end's time button")
        let digits = endTime.label.prefix { $0 != ":" }
        let suffix = endTime.label.uppercased().contains("PM") ? "PM" : "AM"

        app.datePickers["addActivity.start"].buttons
            .matching(NSPredicate(format: "label MATCHES %@", "\\d{1,2}:\\d{2}.*")).firstMatch.tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 0).waitForExistence(timeout: wait), "the time wheels")
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: String(digits))
        if wheels.count > 2 { wheels.element(boundBy: 2).adjust(toPickerWheelValue: suffix) }
        let dismiss = app.buttons["PopoverDismissRegion"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: wait))
        dismiss.tap()
    }

    // MARK: 1. the happy path

    /// ＋ → Add activity → a sport, the default window (the last hour, inside today), effort and notes → Save: the row
    /// is in My Day, added by you, not yet confirmed by the platform, and its VoiceOver sentence leaves the notes out.
    @MainActor
    func testAddActivitySavesAPendingRowAddedByYouWithoutItsNotes() throws {
        let app = openMyDay()
        try openAddActivity(app)
        XCTAssertTrue(app.buttons["addActivity.save"].isEnabled, "the default window is valid")
        choose(sport: "climbing", in: app)
        app.buttons["effortScale.7"].tap()
        let secret = "Felt strong on the crux"
        type(secret, into: "addActivity.notes", in: app)
        app.buttons["addActivity.save"].tap()
        waitForAbsence(of: app.otherElements["addActivity.sheet"], "the sheet closes on Save")

        let row = activityRow("Climbing", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: wait), "the new row in today's list")
        let label = row.label
        XCTAssertTrue(label.contains(" to "), "its times: \(label)")
        XCTAssertTrue(label.contains("Source: Added by you"), "marked as added by you: \(label)")
        XCTAssertTrue(label.contains("Uploading") || label.contains("Strain pending"), "not confirmed or scored yet: \(label)")
        XCTAssertFalse(label.contains(secret), "the notes stay out of the VoiceOver sentence: \(label)")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'myday.view.row.activity.' AND label BEGINSWITH 'Climbing,'")).count,
                       1, "one row, not two")
    }

    // MARK: 2. validation

    /// End at or before the start: Save is disabled and the reason stands under the times. A start in the future can't
    /// be entered: the picker's calendar disables the days after today (ui.md §3.5: "the picker max already prevents
    /// it"), so that half asserts the picker's limit.
    @MainActor
    func testInvalidTimesDisableSaveWithTheirReasonAndTheFutureCannotBePicked() throws {
        let app = openMyDay()
        try openAddActivity(app)
        let save = app.buttons["addActivity.save"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(app.staticTexts["addActivity.issue.endBeforeStart"].exists, "no reason while valid")

        setStartToEnd(app)
        XCTAssertTrue(app.staticTexts["addActivity.issue.endBeforeStart"].waitForExistence(timeout: wait),
                      "the reason: End must be after start.")
        XCTAssertFalse(save.isEnabled, "Save is disabled")
        XCTAssertFalse(app.staticTexts["addActivity.issue.endInFuture"].exists)

        // The future: the start's calendar offers nothing after today.
        app.datePickers["addActivity.start"].buttons.element(boundBy: 1).tap()
        let next = app.buttons["DatePicker.NextMonth"]
        XCTAssertTrue(next.waitForExistence(timeout: wait), "the start's calendar")
        XCTAssertFalse(next.isEnabled, "no later month")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        let tomorrowButton = app.buttons[formatter.string(from: tomorrow)]
        if tomorrowButton.exists { XCTAssertFalse(tomorrowButton.isEnabled, "tomorrow can't be picked") }
    }

    // MARK: 3. the detail

    /// Row → detail; Edit changes the sport and the notes and both show in the detail and the row; Delete asks and the
    /// row is gone.
    @MainActor
    func testDetailEditsAndDeletesTheNewRow() throws {
        let app = openMyDay()
        let row = try addClimbing(notes: "First note", in: app)
        row.tap()

        let detail = app.scrollViews["activityDetail"]
        XCTAssertTrue(detail.waitForExistence(timeout: wait), "the detail")
        XCTAssertTrue(app.navigationBars["Climbing"].exists, "titled with the sport")
        XCTAssertTrue(app.staticTexts["activityDetail.notes"].waitForExistence(timeout: wait), "the notes card")
        XCTAssertTrue(app.staticTexts["activityDetail.notes"].label.contains("First note"))

        // Edit: another sport and more notes (typed at the start: the tap puts the cursor there).
        app.buttons["activityDetail.menu"].tap()
        app.buttons["activityDetail.menu.edit"].tap()
        XCTAssertTrue(app.otherElements["addActivity.sheet"].waitForExistence(timeout: wait), "the edit sheet")
        XCTAssertTrue(app.navigationBars["Edit activity"].exists)
        choose(sport: "cycling", in: app)
        type("Edited. ", into: "addActivity.notes", in: app)
        app.buttons["addActivity.save"].tap()
        waitForAbsence(of: app.otherElements["addActivity.sheet"], "the sheet closes on Save")

        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: wait), "the detail shows the new sport")
        let notes = app.staticTexts["activityDetail.notes"].label
        XCTAssertTrue(notes.contains("Edited.") && notes.contains("First note"), "and the new notes: \(notes)")

        // The row follows.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["myday.view"].waitForExistence(timeout: wait), "back on My Day")
        let edited = activityRow("Cycling", in: app)
        XCTAssertTrue(edited.waitForExistence(timeout: wait), "the row shows the new sport")
        XCTAssertFalse(activityRow("Climbing", in: app).exists, "and not the old one")

        // Delete, with confirmation.
        edited.tap()
        XCTAssertTrue(app.buttons["activityDetail.menu"].waitForExistence(timeout: wait))
        app.buttons["activityDetail.menu"].tap()
        app.buttons["activityDetail.menu.delete"].tap()
        XCTAssertTrue(app.staticTexts["Delete this activity?"].waitForExistence(timeout: wait), "the confirmation")
        // The dialog is a popover whose button the query finds twice.
        app.buttons["activityDetail.confirmDelete"].firstMatch.tap()

        XCTAssertTrue(app.otherElements["myday.view"].waitForExistence(timeout: wait), "back on My Day")
        waitForAbsence(of: activityRow("Cycling", in: app), "the deleted row is gone")
    }

    // MARK: 4. Add sleep

    /// A day in the strip with no night: "Add sleep" there puts the night in the list, added by you. The demo days all
    /// have their night (Apple Health), so this skips until demo data has a day without one.
    @MainActor
    func testAddSleepOnADayWithoutANightShowsTheNight() throws {
        let app = openMyDay()
        let night = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'myday.view.row.sleep.' OR identifier == 'myday.addSleep'"))
        var missing: String?
        for back in 0..<7 {
            let chip = app.buttons["datestrip.day.\(day(daysBack: back))"]
            guard chip.waitForExistence(timeout: 5) else { continue }
            chip.tap()
            XCTAssertTrue(night.firstMatch.waitForExistence(timeout: wait), "the day's night or its Add sleep")
            if night.firstMatch.identifier == "myday.addSleep" {
                missing = day(daysBack: back)
                break
            }
        }
        try XCTSkipIf(missing == nil, "every demo day has a night; Add sleep has nowhere to start")
        guard let missing else { return }

        app.buttons["myday.addSleep"].tap()
        XCTAssertTrue(app.otherElements["addSleep.sheet"].waitForExistence(timeout: wait), "the Add sleep sheet")
        // The duration and its note are one combined element: found by its sentence.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Time asleep'")).firstMatch
                        .waitForExistence(timeout: wait), "Time asleep, live")
        XCTAssertTrue(app.buttons["addSleep.save"].isEnabled, "the default night (23:00 to 07:00) is valid")
        app.buttons["addSleep.save"].tap()
        waitForAbsence(of: app.otherElements["addSleep.sheet"], "the sheet closes on Save")

        let row = app.buttons["myday.view.row.sleep.\(missing)"]
        XCTAssertTrue(row.waitForExistence(timeout: wait), "the night shows for that day")
        XCTAssertTrue(row.label.hasPrefix("Sleep"), row.label)
        XCTAssertTrue(row.label.contains("Source: Added by you"), row.label)
        XCTAssertFalse(app.buttons["myday.addSleep"].exists, "and the day no longer offers Add sleep")
    }

    /// S3: where a tracker has the night, Add sleep isn't offered; Add activity still is.
    @MainActor
    func testAddSleepIsNotOfferedWhereTheTrackerHasTheNight() throws {
        let app = openMyDay()
        let plus = app.buttons["myday.add"]
        XCTAssertTrue(plus.waitForExistence(timeout: wait))
        plus.tap()
        XCTAssertTrue(app.buttons["myday.add.activity"].waitForExistence(timeout: wait), "Add activity is offered")
        XCTAssertFalse(app.buttons["myday.add.sleep"].exists, "Add sleep isn't: today's night is Apple Health's")
        XCTAssertFalse(app.buttons["myday.addSleep"].exists)
    }

    // MARK: 5. the flag off

    /// `activities.manual` off, `today.my_day` on: nothing to add, and a manual activity's detail has no Edit or Delete.
    @MainActor
    func testWithManualEntriesOffNothingCanBeAddedEditedOrDeleted() throws {
        let app = openMyDay(extra: Self.manualOff)
        XCTAssertFalse(app.buttons["myday.view.addActivity"].exists, "no Add activity under the list")
        let plus = app.buttons["myday.add"]
        if plus.exists {
            plus.tap()
            XCTAssertFalse(app.buttons["myday.add.activity"].exists, "no Add activity in the plus menu")
            XCTAssertFalse(app.buttons["myday.add.sleep"].exists, "no Add sleep in the plus menu")
            // Dismiss the menu by tapping beside it.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        }

        // The demo's mobility entry was added by the user; its detail is reachable.
        let mobility = app.buttons["myday.view.row.activity.00000000-0000-4000-8000-0000000A0002"]
        XCTAssertTrue(mobility.waitForExistence(timeout: wait), "the added-by-you mobility row")
        mobility.tap()
        XCTAssertTrue(app.scrollViews["activityDetail"].waitForExistence(timeout: wait), "its detail")
        XCTAssertTrue(app.otherElements["activityDetail.header"].waitForExistence(timeout: wait))

        XCTExpectFailure("B2: fixed in feat/add-activity") {
            XCTAssertFalse(app.buttons["activityDetail.menu"].exists, "no Edit or Delete menu")
            XCTAssertFalse(app.buttons["activityDetail.edit"].exists, "no Edit button")
            XCTAssertFalse(app.buttons["activityDetail.delete"].exists, "no Delete button")
        }
    }
}
