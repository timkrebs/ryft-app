import SwiftUI
import Testing
import UIKit
@testable import Ryft

// C1 (PR 6 C §6, items 4, 5, 9, 10, 15 and 17 for Profile's subpages): Report a problem, Notifications, Journal and Add a
// habit, Sign-in methods, Licences. Pure rules first, then the pages in a real window (`HostedWindow`), read from the
// accessibility tree, at the default size and at AX3. Dark, US English, synthetic data (Alex Doe).

// MARK: - pure rules

@MainActor
struct ProfileSubpagesRulesTests {
    @Test("Add a habit takes 1–60 characters, spaces at the ends not counted")
    func habitNameLimits() {
        #expect(!AddBehaviorSheet.isValid(name: ""))
        #expect(!AddBehaviorSheet.isValid(name: "   "))
        #expect(AddBehaviorSheet.isValid(name: "W"))
        #expect(AddBehaviorSheet.isValid(name: String(repeating: "a", count: 60)))
        #expect(AddBehaviorSheet.isValid(name: "  " + String(repeating: "a", count: 60) + " "))
        #expect(!AddBehaviorSheet.isValid(name: String(repeating: "a", count: 61)))
    }

    @Test("Add a habit offers the user's own category first, then the platform's, each once")
    func habitCategoriesOrder() {
        #expect(AddBehaviorSheet.categories.first == .custom)
        #expect(Set(AddBehaviorSheet.categories) == Set(BehaviorCategory.allCases))
        #expect(AddBehaviorSheet.categories.count == BehaviorCategory.allCases.count)
    }

    @Test("The delete dialog names the habit")
    func deleteTitleNamesTheHabit() {
        #expect(JournalSettingsView.deleteTitle("Evening walk") == "Delete “Evening walk”?")
    }

    @Test("A failed journal change says nothing changed: offline in its own words, otherwise with the status as details")
    func journalFailureWords() {
        let offline = JournalSettingsFailure(JournalStore.JournalError.offline)
        #expect(offline.message.hasPrefix("You're offline, so nothing changed."))
        #expect(offline.details == nil)
        let refused = JournalSettingsFailure(JournalStore.JournalError.idTaken)
        #expect(refused.message.hasPrefix("RYFT couldn't save that. Nothing changed"))
        #expect(!refused.message.localizedCaseInsensitiveContains("behavior"))
    }

    @Test("The habits' section on Insights is titled Habits; a good change is never teal unless the metric is recovery",
          arguments: ["recovery", "hrv", "sleepPerformance"])
    func impactColours(_ metric: String) {
        let spec: MetricSpec = switch metric {
        case "recovery": .recovery
        case "hrv": .hrv
        default: .sleepPerformance
        }
        let good = BehaviorEffect.significantTest(delta: spec.polarity == .lowerIsBetter ? -3 : 3)
        let bad = BehaviorEffect.significantTest(delta: spec.polarity == .lowerIsBetter ? 3 : -3)
        #expect(BehaviorsSection.color(good, spec: spec) == DeltaLabel.goodColor(spec))
        #expect(BehaviorsSection.color(bad, spec: spec) == Theme.alert)
    }
}

// MARK: - colour audit (§6 item 15)

struct ProfileSubpagesTokenTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Ryft")

    @Test("C1's pages name no teal, no PrimaryButton, no system tint and no German previews",
          arguments: ["Features/Profile/ReportProblemView.swift", "Features/Profile/NotificationSettingsView.swift",
                      "Features/Profile/SignInMethodsView.swift", "Features/Profile/LicensesView.swift",
                      "Features/Journal/JournalSettingsView.swift", "Features/Journal/BehaviorsSection.swift"])
    func noTeal(_ path: String) throws {
        let text = try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
        for token in ["Theme.accent", "Theme.onAccent", "TealButtonStyle", "PrimaryButton", ".tint(accent)", "ProfileSection",
                      "Locale(identifier: \"de\")", "preferredColorScheme(.light)", "URL(string: e.url)!"] {
            #expect(!text.contains(token), "\(path) names \(token)")
        }
    }

    @Test("The journal's pages say habit, never behavior, to the user (F1)")
    func habitsWording() throws {
        for path in ["Features/Journal/JournalSettingsView.swift", "Features/Journal/BehaviorsSection.swift"] {
            let text = try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
            // Every string literal the user can see: `Text("…")`, `String(localized: "…")`, `Button("…")`.
            let literals = text.matches(of: #/(?:Text|localized:|Button)\(\s*"([^"]*)"/#).map { String($0.output.1) }
            #expect(!literals.isEmpty)
            for literal in literals {
                #expect(!literal.localizedCaseInsensitiveContains("behavior"), "\(path): \(literal)")
            }
        }
    }
}

// MARK: - the pages, hosted

@MainActor
@Suite("C1: Profile subpages in a window", .serialized)
struct ProfileSubpagesHostedTests {
    private static let width: CGFloat = 390

    private func host(_ view: AnyView, height: CGFloat = 844, ax3: Bool = false,
                      _ body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: Self.width, height: height, bottomInset: 34,
                                   typeSize: ax3 ? .accessibility3 : .large,
                                   category: ax3 ? .accessibilityExtraLarge : .large, view, body: body)
    }

    private func node(_ w: HostedWindow, _ label: String, exactly: Bool = true) throws -> HostedWindow.Node {
        try #require(w.node(label, exactly: exactly), "'\(label)' in \(w.nodes().map(\.label))")
    }

    private func node(_ w: HostedWindow, id: String) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == id }, "'\(id)' in \(w.nodes().map { $0.identifier ?? $0.label })")
    }

    private func has(_ w: HostedWindow, id: String) -> Bool { w.nodes().contains { $0.identifier == id } }

    private func isSwitch(_ node: HostedWindow.Node) -> Bool {
        node.traits.contains(.toggleButton) || node.traits.contains(.button)
    }

    // MARK: Report a problem (§6 item 5)

    @Test("Send is disabled with no message and over 4,000 characters; the counter then says so in words")
    func reportSendRules() async throws {
        try await host(SubpageShotScreen.report { _ in }) { w in
            try await w.wait("the form") { has(w, id: "report.send") }
            try await w.settle()
            let send = try node(w, id: "report.send")
            #expect(!send.isEnabled, "empty: Send disabled")
            #expect(!has(w, id: "report.count"), "no counter far below the limit")
        }
        try await host(SubpageShotScreen.report { $0.stage(message: String(repeating: "x", count: 4_001)) }) { w in
            try await w.wait("the form") { has(w, id: "report.send") }
            try await w.settle()
            let send = try node(w, id: "report.send")
            #expect(!send.isEnabled, "over the limit: Send disabled")
            let count = try node(w, id: "report.count")
            #expect(count.value == "Over the limit", "counter value: \(String(describing: count.value))")
        }
        try await host(SubpageShotScreen.report { $0.stage(message: SubpageShotScreen.message) }) { w in
            try await w.wait("the form") { has(w, id: "report.send") }
            try await w.settle()
            let send = try node(w, id: "report.send")
            #expect(send.isEnabled && send.label == "Send")
        }
    }

    @Test("While sending: 'Sending…', 'In progress', and the form doesn't take changes")
    func reportSending() async throws {
        try await host(SubpageShotScreen.report { $0.stage(message: SubpageShotScreen.message, category: .data, sending: true) }) { w in
            try await w.wait("the form") { has(w, id: "report.send") }
            try await w.settle()
            let send = try node(w, id: "report.send")
            #expect(send.label == "Sending…" && send.value == "In progress", "\(send.label) \(String(describing: send.value))")
            let category = try node(w, id: "report.category.bug")
            #expect(!category.isEnabled, "the category rows are disabled while it goes")
            let diagnostics = try node(w, id: "report.diagnostics")
            #expect(!diagnostics.isEnabled)
        }
    }

    @Test("One category is selected; choosing another moves the selection", arguments: [FeedbackCategory.data, .bug])
    func reportCategorySelection(_ chosen: FeedbackCategory) async throws {
        try await host(SubpageShotScreen.report { $0.stage(message: SubpageShotScreen.message, category: chosen) }) { w in
            try await w.wait("the form") { has(w, id: "report.category.\(chosen.rawValue)") }
            try await w.settle()
            let selected = FeedbackCategory.allCases.filter { (try? node(w, id: "report.category.\($0.rawValue)").isSelected) == true }
            #expect(selected == [chosen])
            let other: FeedbackCategory = chosen == .bug ? .idea : .bug
            try node(w, id: "report.category.\(other.rawValue)").activate()
            try await w.wait("the selection moves") { (try? node(w, id: "report.category.\(other.rawValue)").isSelected) == true }
            let before = try node(w, id: "report.category.\(chosen.rawValue)")
            #expect(!before.isSelected)
        }
    }

    @Test("Sent and queued replace the form and the bar with a headline (a header) and Done; queued never says sent",
          arguments: [ReportProblemModel.Result.sent, .queued])
    func reportOutcome(_ result: ReportProblemModel.Result) async throws {
        try await host(SubpageShotScreen.report { $0.stage(result: result, waiting: result == .queued ? 1 : 0) }) { w in
            let id = result == .sent ? "report.sent" : "report.queued"
            try await w.wait("the outcome") { has(w, id: id) }
            try await w.settle()
            let headline = try node(w, id: id)
            #expect(headline.traits.contains(.header))
            if result == .queued {
                #expect(headline.label.hasPrefix("Saved.") && !headline.label.localizedCaseInsensitiveContains("reached"))
            }
            #expect(!has(w, id: "report.send") && !has(w, id: "report.message"), "the form and Send are gone")
            let done = try node(w, id: "report.done")
            #expect(done.traits.contains(.button) && done.label == "Done")
            // Read in order: the page title, then the headline, then Done.
            let order = w.nodes().map(\.label)
            let title = try #require(order.firstIndex(of: "Report a problem"))
            let line = try #require(order.firstIndex(of: headline.label))
            let button = try #require(order.firstIndex(of: "Done"))
            #expect(title < line && line < button)
        }
    }

    @Test("A refusal shows its notice above the form, keeps the message and offers Copy message",
          arguments: [ReportProblemModel.Result.rateLimited, .signedOut, .rejected, .saveFailed])
    func reportRefusals(_ result: ReportProblemModel.Result) async throws {
        try await host(SubpageShotScreen.report { $0.stage(message: SubpageShotScreen.message, category: .data, result: result) }) { w in
            try await w.wait("the notice") { w.node("Copy message", exactly: true) != nil }
            try await w.settle()
            // The message field is a UIKit text view (a vertical `TextField`): read it there.
            #expect(Self.texts(in: w.host.view).contains(SubpageShotScreen.message), "the message is kept")
            #expect(w.node("Copy message", exactly: true) != nil, "Copy message")
            switch result {
            case .rateLimited: #expect(w.node("You've reached today's limit of 10 reports.") != nil)
            case .signedOut: #expect(w.node("You're signed out, so this report can't be sent.") != nil)
            default: #expect(w.node("RYFT couldn't take this report") != nil || w.node("Couldn't save your report") != nil)
            }
            #expect(!has(w, id: "report.sent") && !has(w, id: "report.queued"))
        }
    }

    /// The text of every text view and field under `view`.
    private static func texts(in view: UIView) -> [String] {
        var found: [String] = []
        if let text = (view as? UITextView)?.text ?? (view as? UITextField)?.text { found.append(text) }
        for sub in view.subviews { found += texts(in: sub) }
        return found
    }

    @Test("From Details: the chip says what it's about, with the request ID while diagnostics go along")
    func reportContextChip() async throws {
        try await host(SubpageShotScreen.report(context: .preview) { $0.stage(message: "x", category: .bug, context: .preview) }) { w in
            try await w.wait("the chip") { has(w, id: "report.context") }
            try await w.settle()
            let chip = try node(w, id: "report.context")
            #expect(chip.label.hasPrefix("About: Today · 503") && chip.label.contains("01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c"),
                    "\(chip.label)")
            // "What's included" is a button that says whether it's open.
            let included = try node(w, id: "report.included")
            #expect(included.traits.contains(.button) && included.value == "Collapsed", "\(String(describing: included.value))")
            included.activate()
            try await w.wait("it opens") { (try? node(w, id: "report.included").value) == "Expanded" }
            #expect(w.node("App version and build", exactly: true) != nil)
        }
    }

    // MARK: Notifications (§6 item 9)

    @Test("Allowed: the switches and quiet hours, no pinned action")
    func notificationsAllowed() async throws {
        try await host(SubpageShotScreen.notifications(.authorized)) { w in
            try await w.wait("the switches") { w.node("Morning score") != nil }
            try await w.settle()
            let morning = try node(w, "Morning score", exactly: false)
            let quiet = try node(w, "Pause at night", exactly: false)
            #expect(isSwitch(morning) && isSwitch(quiet), "\(morning.traits.rawValue) \(quiet.traits.rawValue)")
            for title in ["Notify me about", "Quiet hours"] {
                let header = try node(w, title)
                #expect(header.traits.contains(.header), "\(title) is a header")
            }
            #expect(w.node("Allow notifications", exactly: true) == nil && w.node("Open Settings", exactly: true) == nil)
            #expect(w.node("Notifications are off in iOS Settings") == nil && w.node("Notifications are being rolled out") == nil)
        }
    }

    @Test("Not asked: the notice and the pinned Allow notifications")
    func notificationsNotAsked() async throws {
        try await host(SubpageShotScreen.notifications(.notDetermined)) { w in
            try await w.wait("the pill") { w.node("Allow notifications", exactly: true) != nil }
            try await w.settle()
            let allow = try node(w, id: "notifications.allow")
            #expect(allow.traits.contains(.button))
            #expect(w.node("RYFT hasn't asked to send notifications yet.") != nil)
            #expect(w.node("Open Settings", exactly: true) == nil)
        }
    }

    @Test("Off in iOS: the notice, the pinned Open Settings, and the switches still live")
    func notificationsDenied() async throws {
        try await host(SubpageShotScreen.notifications(.denied)) { w in
            try await w.wait("the notice") { w.node("Notifications are off in iOS Settings") != nil }
            try await w.settle()
            let open = try node(w, id: "notifications.openSettings")
            #expect(open.label == "Open Settings")
            #expect(w.node("Allow notifications", exactly: true) == nil)
            let morning = try node(w, "Morning score", exactly: false)
            #expect(isSwitch(morning) && morning.isEnabled, "the choices stay live while off in iOS")
        }
    }

    @Test("Rolling out: the notice and the categories as text, no switch, no pinned action")
    func notificationsRollingOut() async throws {
        try await host(SubpageShotScreen.notifications(.authorized, rolledOut: false)) { w in
            try await w.wait("the notice") { w.node("Notifications are being rolled out") != nil }
            try await w.settle()
            let morning = try node(w, "Morning score")
            #expect(morning.traits.contains(.staticText) && !morning.traits.contains(.button), "\(morning.traits.rawValue)")
            let switches = w.nodes().filter { $0.traits.contains(.toggleButton) }
            #expect(switches.isEmpty, "no switch: \(switches.map(\.label))")
            #expect(w.node("Allow notifications", exactly: true) == nil && w.node("Open Settings", exactly: true) == nil)
            #expect(w.node("Notifications are off in iOS Settings") == nil)
        }
    }

    // MARK: Journal and Add a habit (§6 items 4, 10; F1, F22)

    private func journal(ax3: Bool = false, _ body: (HostedWindow) async throws -> Void) async throws {
        try await host(SubpageShotScreen.view("journal"), height: ax3 ? 2_400 : 1_400, ax3: ax3, body)
    }

    @Test("Journal: the header's plus is Add a habit; only the user's own habit has a trash button; the footer says so")
    func journalTrashOnlyOnCustom() async throws {
        try await journal { w in
            try await w.wait("the habits") { w.node("Late screen meeting") != nil }
            try await w.settle()
            let add = try node(w, "Add a habit")
            #expect(add.traits.contains(.button) && add.identifier == "journal.add")
            let trash = w.nodes().filter { $0.label.hasPrefix("Delete ") && $0.traits.contains(.button) }
            #expect(trash.map(\.label) == ["Delete Late screen meeting"], "\(trash.map(\.label))")
            let own = try node(w, "Your own")
            #expect(own.traits.contains(.header))
            #expect(w.node("Your own habits can be deleted. The built-in ones can only be turned off.", exactly: true) != nil)
            for title in ["Substances", "Sleep", "Recovery"] {
                let header = try node(w, title)
                #expect(header.traits.contains(.header), "\(title) is a header")
            }
            let alcohol = try node(w, "Alcohol", exactly: false)
            #expect(isSwitch(alcohol))
            let behaviorWords = w.nodes().map(\.label).filter { $0.localizedCaseInsensitiveContains("behavior") }
            #expect(behaviorWords.isEmpty, "F1: \(behaviorWords)")
        }
    }

    @Test("Journal: the trash button asks first, naming the habit; Delete is destructive")
    func journalTrashConfirms() async throws {
        try await journal { w in
            try await w.wait("the habits") { w.node("Delete Late screen meeting", exactly: true) != nil }
            try await w.settle()
            try node(w, "Delete Late screen meeting").activate()
            var alert: UIAlertController?
            try await w.wait("the dialog") {
                alert = Self.presentedAlert(w.host)
                return alert != nil
            }
            let dialog = try #require(alert)
            #expect(dialog.title == "Delete “Late screen meeting”?")
            #expect(dialog.message == "This removes the habit from your Journal.")
            #expect(dialog.actions.contains { $0.title == "Delete" && $0.style == .destructive })
            dialog.dismiss(animated: false)
        }
    }

    private static func presentedAlert(_ controller: UIViewController) -> UIAlertController? {
        if let alert = controller as? UIAlertController { return alert }
        for child in controller.children { if let found = presentedAlert(child) { return found } }
        return controller.presentedViewController.flatMap(presentedAlert)
    }

    @Test("Add a habit: Add is disabled without a name and over 60 characters; one Answer and one Category selected",
          arguments: ["", String(repeating: "a", count: 61), "Evening walk"])
    func addHabit(_ name: String) async throws {
        try await host(SubpageShotScreen.addHabit(name: name), height: 1_400) { w in
            try await w.wait("the sheet") { has(w, id: "addHabit.add") }
            try await w.settle()
            let add = try node(w, id: "addHabit.add")
            #expect(add.isEnabled == AddBehaviorSheet.isValid(name: name), "'\(name.prefix(12))…': \(add.isEnabled)")
            let title = try node(w, "Add a habit")
            #expect(title.traits.contains(.header))
            let answers = BehaviorKind.allCases.filter { (try? node(w, id: "addHabit.answer.\($0.rawValue)").isSelected) == true }
            let categories = BehaviorCategory.allCases.filter {
                (try? node(w, id: "addHabit.category.\($0.rawValue)").isSelected) == true
            }
            #expect(answers == [.yesNo] && categories == [.custom], "\(answers) \(categories)")
            #expect(w.node("German name") == nil, "F23: no German name")
        }
    }

    // MARK: Sign-in methods and Licences

    @Test("Sign-in: an email account sees its row and the Apple sentence; with both linked, two rows and nothing to add",
          arguments: [false, true])
    func signInMethods(_ apple: Bool) async throws {
        try await host(SubpageShotScreen.signIn(apple: apple)) { w in
            try await w.wait("the methods") { w.node("Email and password", exactly: true) != nil }
            if apple { try await w.wait("Apple ID") { w.node("Apple ID", exactly: true) != nil } }
            try await w.settle()
            let email = try node(w, "Email and password")
            #expect(email.value == "alex@example.com")
            let sentence = w.node("Add Sign in with Apple")
            #expect((sentence == nil) == apple, "the sentence only while Apple isn't linked")
            #expect((w.node("Apple ID", exactly: true) != nil) == apple)
        }
    }

    @Test("Licences: link rows with the licence and holder, hint 'Opens the licence in Safari'")
    func licences() async throws {
        try await host(SubpageShotScreen.view("licences")) { w in
            try await w.wait("the rows") { w.node("supabase-swift", exactly: true) != nil }
            try await w.settle()
            let row = try node(w, "supabase-swift")
            #expect(row.traits.contains(.link) && row.value == "MIT · Supabase" && row.hint == "Opens the licence in Safari",
                    "\(row.traits.rawValue) \(String(describing: row.value)) \(String(describing: row.hint))")
        }
    }

    // MARK: AX3 sweep (§6 item 17)

    @Test("AX3: no element leaves the 390 pt width; every button has a label",
          arguments: ["report-filled", "report-included", "report-limited", "report-queued", "notifications-allowed",
                      "notifications-denied", "notifications-rollout", "journal", "add-habit", "sign-in-email",
                      "sign-in-both", "licences"])
    func ax3Frames(_ name: String) async throws {
        let tall = name == "journal" || name == "add-habit"
        try await host(SubpageShotScreen.view(name), height: tall ? 2_400 : 844, ax3: true) { w in
            try await w.wait("the page") { w.nodes().count > 3 }
            try await w.settle()
            let nodes = w.nodes()
            for node in nodes where node.frame.width > 0 {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= Self.width + 0.5,
                        "\(name): '\(node.label)' at \(node.frame)")
            }
            for node in nodes where node.traits.contains(.button) {
                #expect(!node.label.trimmingCharacters(in: .whitespaces).isEmpty, "\(name): a button without a label")
            }
        }
    }

    @Test("A custom habit's trash is a 44 pt target before the switch, inside the card, at the default size and AX3",
          arguments: [false, true])
    func journalCustomRow(_ ax3: Bool) async throws {
        try await journal(ax3: ax3) { w in
            try await w.wait("the habits") { w.node("Delete Late screen meeting", exactly: true) != nil }
            try await w.settle()
            let trash = try node(w, "Delete Late screen meeting")
            let row = try node(w, "Late screen meeting", exactly: false)
            #expect(trash.frame.width >= 43.5 && trash.frame.height >= 43.5, "\(trash.frame)")
            #expect(trash.frame.minX >= 20 && trash.frame.maxX <= Self.width - 20 - 16 - RyftToggleStyle.trackSize.width,
                    "\(trash.frame)")
            #expect(row.frame.minX >= 19.5 && row.frame.maxX <= Self.width - 19.5, "the switch row: \(row.frame)")
            #expect(abs(trash.frame.midY - row.frame.midY) < 1, "one line with the switch: \(trash.frame) \(row.frame)")
        }
    }
}

private extension BehaviorEffect {
    /// A significant effect of `delta` points, its 90 % interval around it.
    static func significantTest(delta: Double) -> BehaviorEffect {
        BehaviorEffect(delta: delta, ciLo: delta - 1, ciHi: delta + 1, significant: true, nYes: 12, nNo: 31)
    }
}
