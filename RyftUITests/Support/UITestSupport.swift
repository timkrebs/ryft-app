import XCTest

/// What the My Day UI tests share: demo-mode launch, the broad identifier queries, day strings.
extension XCTestCase {
    /// Demo mode (`-demoMode YES`: no server, no HealthKit) on Today, English, dark, coach marks done.
    /// `openMyDayDaysBack`: `-RyftOpenMyDay <n>` pushes the full My Day screen on that day once Today has loaded (Debug).
    /// `extra`: more launch arguments, e.g. a flag override.
    func launchDemo(openMyDayDaysBack: Int? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.timkrebs.ryft")
        var arguments = ["-demoMode", "YES", "-RyftTab", "today", "-appearance", "dark", "-coachMarks.today.done", "YES",
                         "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let openMyDayDaysBack { arguments += ["-RyftOpenMyDay", "\(openMyDayDaysBack)"] }
        app.launchArguments = arguments + extra
        app.launch()
        return app
    }

    /// `yyyy-MM-dd`, `back` days before today, in the device's time zone (as the app writes day strings).
    func dayString(daysBack back: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: -back, to: Date()) ?? Date())
    }

    /// Fails unless `element` stops existing within `timeout`.
    func waitForAbsence(of element: XCUIElement, timeout: TimeInterval, _ message: String) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed, message)
    }
}

extension XCUIApplication {
    /// Scrolls until `element` can be tapped.
    func reveal(_ element: XCUIElement) {
        var tries = 0
        while !element.isHittable && tries < 10 {
            swipeUp()
            tries += 1
        }
    }
}
