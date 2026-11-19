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

    @Test("A failed journal change in the settings pages' words: offline in its own, a refusal with the status as details")
    func journalFailureWords() {
        let offline = JournalSettingsFailure(JournalStore.JournalError.offline)
        #expect(offline.message == SettingsWriteFailure.offline.saveMessage)
        #expect(offline.details == nil)
        let refused = JournalSettingsFailure(JournalStore.JournalError.idTaken)
        #expect(refused.message == SettingsWriteFailure.refused.saveMessage)
        #expect(!refused.message.localizedCaseInsensitiveContains("behavior"))
    }

    @Test("A significant effect: good in the metric's colour (recovery and HRV teal, F5, L27; sleep violet), bad in alert",
          arguments: ["recovery", "hrv", "sleepPerformance"])
    func impactColours(_ metric: String) {
        let (spec, good): (MetricSpec, Color) = switch metric {
        case "recovery": (.recovery, Theme.accent)
        case "hrv": (.hrv, Theme.accent)
        default: (.sleepPerformance, Theme.metricSleep)
        }
        #expect(BehaviorsSection.color(BehaviorEffect.significantTest(delta: 3), spec: spec) == good)
        #expect(BehaviorsSection.color(BehaviorEffect.significantTest(delta: -3), spec: spec) == Theme.alert)
        let unclear = BehaviorEffect(delta: 3, ciLo: -1, ciHi: 7, significant: false, nYes: 6, nNo: 9)
        #expect(BehaviorsSection.color(unclear, spec: spec) == Theme.textTertiary)
    }
}

// MARK: - colour audit (§6 item 15)

struct ProfileSubpagesTokenTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Ryft")

    @Test("C1's pages name no teal (in code, not comments), no PrimaryButton, no system tint and no German previews",
          arguments: ["Features/Profile/ReportProblemView.swift", "Features/Profile/NotificationSettingsView.swift",
                      "Features/Profile/SignInMethodsView.swift", "Features/Profile/LicensesView.swift",
                      "Features/Journal/JournalSettingsView.swift", "Features/Journal/BehaviorsSection.swift"])
    func noTeal(_ path: String) throws {
        let source = try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
        // The code only: a comment may name a token to say why it isn't used. `//` after a colon is a URL's.
        let code = source.replacing(#/(^|[^:])//.*/#) { String($0.output.1) }
        // `Theme.signal` is the orbit mark's alone, and none of these pages draws the mark.
        for token in ["Theme.accent", "Theme.onAccent", "Theme.teal", "Theme.recovery", "Theme.signal", "Color.accentColor",
                      "TealButtonStyle", "PrimaryButton", ".tint(accent)", "ProfileSection",
                      "Locale(identifier: \"de\")", "preferredColorScheme(.light)"] {
            #expect(!code.contains(token), "\(path) names \(token)")
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

    /// The system switch's traits, off and on, read from a real `Toggle` in a window (as `NocturneControlsTests` pins
    /// `RyftToggleStyle` to them): a node is a switch when it reads exactly so, enabled or not.
    /// Read before the page is hosted: one window at a time.
    private func switchTraits() async throws -> [UIAccessibilityTraits] {
        var found: [UIAccessibilityTraits] = []
        for on in [false, true] {
            try await host(AnyView(Toggle("Wake alarm", isOn: .constant(on)).toggleStyle(.switch).padding(.horizontal, 20))) { w in
                try await w.settle()
                let reference = try node(w, "Wake alarm")
                found.append(reference.traits)
            }
        }
        return found
    }

    private func isSwitch(_ candidate: HostedWindow.Node, _ switchTraits: [UIAccessibilityTraits]) -> Bool {
        switchTraits.contains(candidate.traits.subtracting(.notEnabled))
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
        let reference = try await switchTraits()
        try await host(SubpageShotScreen.notifications(.authorized)) { w in
            try await w.wait("the switches") { w.node("Morning score") != nil }
            try await w.settle()
            let morning = try node(w, "Morning score", exactly: false)
            let quiet = try node(w, "Pause at night", exactly: false)
            #expect(isSwitch(morning, reference) && isSwitch(quiet, reference), "\(morning.traits.rawValue) \(quiet.traits.rawValue)")
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
        let reference = try await switchTraits()
        try await host(SubpageShotScreen.notifications(.denied)) { w in
            try await w.wait("the notice") { w.node("Notifications are off in iOS Settings") != nil }
            try await w.settle()
            let open = try node(w, id: "notifications.openSettings")
            #expect(open.label == "Open Settings")
            #expect(w.node("Allow notifications", exactly: true) == nil)
            let morning = try node(w, "Morning score", exactly: false)
            #expect(isSwitch(morning, reference) && morning.isEnabled, "the choices stay live while off in iOS")
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
        let reference = try await switchTraits()
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
            #expect(isSwitch(alcohol, reference), "\(alcohol.traits.rawValue)")
            // Built-ins by their slug, the user's own by its id (N5).
            let ownID = MockJournal.meeting.uuidString.lowercased()
            let meeting = try node(w, "Late screen meeting", exactly: false), bin = try node(w, "Delete Late screen meeting")
            #expect(alcohol.identifier == "journal.habit.alcohol")
            #expect(meeting.identifier == "journal.habit.\(ownID)" && bin.identifier == "journal.delete.\(ownID)",
                    "\(String(describing: meeting.identifier)) \(String(describing: bin.identifier))")
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
                      "notifications-quiet-on",
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

    @Test("A custom habit's trash is 44 wide and as tall as its row (N4), before the switch, inside the card, default and AX3",
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
            #expect(abs(trash.frame.height - row.frame.height) < 1, "the row's height: \(trash.frame) \(row.frame)")
        }
    }

    // MARK: fix round (S1–S9, N1–N6)

    /// The page's list (a `List` is a collection view), scrolled to its end without animation.
    private static func scrollToEnd(_ w: HostedWindow) throws {
        func find(_ view: UIView) -> UICollectionView? {
            if let list = view as? UICollectionView, list.bounds.height > 300 { return list }
            return view.subviews.lazy.compactMap(find).first
        }
        let list = try #require(find(w.host.view), "the list")
        let end = list.contentSize.height + list.adjustedContentInset.bottom - list.bounds.height
        list.setContentOffset(CGPoint(x: 0, y: max(-list.adjustedContentInset.top, end)), animated: false)
    }

    /// The dialog's button `title`, as a tap runs it: its handler (UIKit keeps it private), then the dialog goes.
    private static func choose(_ title: String, in alert: UIAlertController) throws {
        typealias Handler = @convention(block) (UIAlertAction) -> Void
        let action = try #require(alert.actions.first { $0.title == title }, "\(alert.actions.map(\.title))")
        let handler = try #require(action.value(forKey: "handler") as AnyObject?, "a handler")
        unsafeBitCast(handler, to: Handler.self)(action)
        if alert.presentingViewController != nil { alert.dismiss(animated: false) }
    }

    /// Opens the trash's dialog for the user's own habit and chooses Delete.
    private func deleteOwnHabit(_ w: HostedWindow) async throws {
        let trash = try node(w, "Delete Late screen meeting")
        #expect(trash.activate())
        var alert: UIAlertController?
        try await w.wait("the dialog") {
            alert = Self.presentedAlert(w.host)
            return alert != nil
        }
        let dialog = try #require(alert)
        try Self.choose("Delete", in: dialog)
    }

    private func journalPage(online: Bool) -> (AnyView, JournalStore, MockPlatformAPI?) {
        // Offline is an account's: demo data answers on the phone, with no network to lose (PR 6 C review N6).
        let state = online ? AppState.preview() : AppState(env: .test(clock: TestClock(now: .now), online: false))
        if !online { state.user = MockData.user }
        let store = journalPreviewStore(state)
        return (SubpageShotScreen.pushed(state) { JournalSettingsView(store: store) }, store, state.env.api as? MockPlatformAPI)
    }

    @Test("S3: a delete that fails far down the page shows its notice under the habit's group, on screen; the habit stays")
    func journalFailureBelowTheFold() async throws {
        let (page, store, _) = journalPage(online: false)
        try await host(page) { w in
            try await w.wait("the habits") { w.node("Alcohol") != nil }
            try await w.settle()
            let before = w.node("Delete Late screen meeting", exactly: true)
            #expect(before == nil || before.map { $0.frame.minY >= 844 - 34 } == true, "below the fold at first")
            try Self.scrollToEnd(w)
            try await w.wait("the trash") { w.node("Delete Late screen meeting", exactly: true) != nil }
            try await w.settle()
            try await deleteOwnHabit(w)
            let sentence = "You're offline, so this wasn't saved. Try again when you're back online."
            try await w.wait("the notice") { w.node(sentence, exactly: true) != nil }
            try await w.settle()
            let notice = try node(w, sentence)
            let row = try node(w, "Late screen meeting", exactly: false)
            let gap = notice.frame.minY - row.frame.maxY
            #expect(gap >= 0 && gap <= 40, "right under the habit's card: \(notice.frame) under \(row.frame)")
            #expect(notice.frame.minY >= 0 && notice.frame.maxY <= 844 - 34, "on screen: \(notice.frame)")
            #expect(w.node("Delete Late screen meeting", exactly: true) != nil && store.behavior(MockJournal.meeting) != nil,
                    "the habit stays")
        }
    }

    @Test("S8: confirming the dialog deletes the habit (one DELETE), and no notice shows")
    func journalConfirmDeletes() async throws {
        let (page, store, api) = journalPage(online: true)
        try await host(page, height: 1_400) { w in
            try await w.wait("the habits") { w.node("Delete Late screen meeting", exactly: true) != nil }
            try await w.settle()
            try await deleteOwnHabit(w)
            // The store, not the tree: a list keeps a removed row's cell, hidden, for reuse.
            try await w.wait("the habit to go") { store.behavior(MockJournal.meeting) == nil }
            try await w.settle()
            #expect(api?.count("deleteBehavior") == 1)
            let platform = try await api?.behaviors() ?? []
            #expect(!platform.isEmpty && !platform.contains { $0.id == MockJournal.meeting }, "gone on the platform too")
            #expect(w.node("RYFT") == nil && w.node("You're offline") == nil, "no notice")
        }
    }

    @Test("S8: offline, a switch goes back and the offline notice shows under its group, not at the page's top")
    func journalOfflineSwitch() async throws {
        let (page, store, _) = journalPage(online: false)
        try await host(page, height: 1_400) { w in
            try await w.wait("the habits") { w.node("Alcohol") != nil }
            try await w.settle()
            let alcohol = try node(w, "Alcohol", exactly: false)
            #expect(alcohol.activate())
            let sentence = "You're offline, so this wasn't saved. Try again when you're back online."
            try await w.wait("the notice") { w.node(sentence, exactly: true) != nil }
            try await w.settle()
            let after = try node(w, "Alcohol", exactly: false)
            #expect(after.value == alcohol.value && store.behavior(MockJournal.alcohol)?.enabled == true, "back as it was")
            let notice = try node(w, sentence), last = try node(w, "Last caffeine", exactly: false), sleep = try node(w, "Sleep")
            // A list row's frame: the notice's row starts where the last habit's ends.
            #expect(notice.frame.minY >= last.frame.maxY - 0.5 && notice.frame.maxY <= sleep.frame.minY + 0.5,
                    "under Substances: \(notice.frame), \(last.frame), \(sleep.frame)")
        }
    }

    /// Notifications, allowed, and the mock behind it (to hold or fail its `PATCH`).
    private func notificationsPage(quietHours: Bool) -> (AnyView, MockPlatformAPI?) {
        let notifier = MockNotifier()
        notifier.status = .authorized
        let state = AppState.preview(flags: [.pushEnabled: true], notifier: notifier)
        if quietHours, let user = state.user {
            state.user?.notifications = NotificationPrefs(categories: user.notifications.categories,
                                                          quietHours: NotificationSettingsViewModel.defaultQuietHours)
        }
        return (SubpageShotScreen.pushed(state) { NotificationSettingsView() }, state.env.api as? MockPlatformAPI)
    }

    private static func datePickers(in view: UIView) -> [UIDatePicker] {
        ((view as? UIDatePicker).map { [$0] } ?? []) + view.subviews.flatMap(datePickers)
    }

    private static let notificationSwitches = ["Morning score", "Workout scored", "Records", "No new data", "Pause at night"]

    @Test("S4: while a change is on its way every switch and both time chips are disabled; then they're live again")
    func notificationsDisabledInFlight() async throws {
        let (page, api) = notificationsPage(quietHours: true)
        let hold = RequestHold()
        api?.beforePatchNotifications = { await hold.wait() }
        try await host(page, height: 1_400) { w in
            try await w.wait("the switches") { w.node("Records") != nil }
            try await w.settle()
            #expect(Self.datePickers(in: w.host.view).count == 2, "From and Until")
            let tapped = try node(w, "Records", exactly: false).activate()
            #expect(tapped)
            try await w.wait("the change on its way") { hold.waiting == 1 }
            try await w.wait("everything disabled") {
                Self.notificationSwitches.allSatisfy { w.node($0)?.isEnabled == false }
                    && Self.datePickers(in: w.host.view).allSatisfy { !$0.isEnabled }
            }
            hold.release()
            try await w.wait("live again") {
                Self.notificationSwitches.allSatisfy { w.node($0)?.isEnabled == true }
                    && Self.datePickers(in: w.host.view).allSatisfy(\.isEnabled)
            }
            #expect(api?.prefs.isOn(.pr) == false, "saved")
        }
    }

    @Test("S5: a refused change goes back; the notice is calm, under its group, with the status and request ID as caption")
    func notificationsRollbackAndNotice() async throws {
        let (page, api) = notificationsPage(quietHours: false)
        api?.faults["patchNotifications"] = FaultInjection.Rule(.status(422, retryAfter: nil), times: 1)
        try await host(page, height: 1_400) { w in
            try await w.wait("the switches") { w.node("Records") != nil }
            try await w.settle()
            let records = try node(w, "Records", exactly: false)
            #expect(records.activate())
            let sentence = "RYFT couldn't save this change, so it's back as it was."
            try await w.wait("the notice") { w.node(sentence, exactly: true) != nil }
            try await w.settle()
            let after = try node(w, "Records", exactly: false)
            #expect(after.value == records.value, "back as it was: \(String(describing: after.value))")
            #expect(w.node("HTTP 422 · Request ID fault-patchNotifications", exactly: true) != nil, "the caption")
            #expect(w.node("injected fault") == nil && w.node("Couldn't save:") == nil, "never the raw error text")
            let notice = try node(w, sentence), last = try node(w, "No new data", exactly: false)
            let quiet = try node(w, "Quiet hours")
            #expect(notice.frame.minY >= last.frame.maxY - 0.5 && notice.frame.maxY <= quiet.frame.minY + 0.5,
                    "under Notify me about: \(notice.frame)")
        }
    }

    @Test("S9: quiet hours on: From and Until with their chips, beside the title by default and under it at AX3",
          arguments: [false, true])
    func quietHoursChips(_ ax3: Bool) async throws {
        try await host(SubpageShotScreen.view("notifications-quiet-on"), height: 1_400, ax3: ax3) { w in
            try await w.wait("the chips") { w.node("Until", exactly: true) != nil }
            try await w.settle()
            let pickers = Self.datePickers(in: w.host.view)
                .map { $0.convert($0.bounds, to: w.window) }
                .sorted { $0.minY < $1.minY }
            #expect(pickers.count == 2)
            for (title, chip) in zip(["From", "Until"], pickers) {
                let label = try node(w, title)
                if ax3 {
                    #expect(chip.midY > label.frame.maxY, "\(title): the chip under its title, \(chip) \(label.frame)")
                } else {
                    #expect(abs(chip.midY - label.frame.midY) < 4, "\(title): beside it, \(chip) \(label.frame)")
                }
                #expect(chip.minX >= 0 && chip.maxX <= Self.width + 0.5, "\(title): on the page, \(chip)")
            }
        }
    }

    @Test("S2: Add a habit retried after no answer sends its own id again: one habit, not two")
    func addHabitRetryKeepsItsID() async throws {
        let state = AppState.preview()
        let store = journalPreviewStore(state)
        let api = try #require(state.env.api as? MockPlatformAPI)
        let id = UUID()
        api.faults["createBehavior"] = FaultInjection.Rule(.timeout, times: 1)
        let sheet = AnyView(AddBehaviorSheet(store: store, name: "Evening walk", id: id).previewEnvironment(state)
            .toggleStyle(.ryft).environment(\.locale, Locale(identifier: "en_US")))
        try await host(sheet, height: 1_400) { w in
            try await w.wait("the sheet") { has(w, id: "addHabit.add") }
            try await w.settle()
            let first = try node(w, id: "addHabit.add").activate()
            #expect(first)
            // The editors' words (PR 6 C review S4): it may have saved.
            let sentence = SettingsWriteFailure.noAnswer.saveMessage
            try await w.wait("the notice") { w.node(sentence, exactly: true) != nil }
            // It did arrive, as a timeout allows: the platform has the habit under the sheet's id.
            _ = try await api.createBehavior(BehaviorInput(id: id, name: "Evening walk", kind: .yesNo, category: .custom))
            try await w.wait("Add again") { (try? node(w, id: "addHabit.add").isEnabled) == true }
            let again = try node(w, id: "addHabit.add").activate()
            #expect(again)
            try await w.wait("saved") { store.behavior(id) != nil }
            let platform = try await api.behaviors()
            #expect(platform.filter { $0.name == "Evening walk" }.map(\.id) == [id], "one habit, its id")
            #expect(store.behaviors.filter { $0.name == "Evening walk" }.count == 1)
        }
    }

    @Test("S2: with 50 habits of the user's own, Add is disabled and the bar says why, before anything is sent")
    func addHabitAtFifty() async throws {
        let state = AppState.preview()
        let own = MockJournal.behaviors.filter(\.isCustom).count
        let more = (own..<AddBehaviorSheet.maxOwn).map { n in
            Behavior(id: UUID(), slug: "habit-\(n)", name: "Habit \(n)", nameEn: "Habit \(n)", nameDe: "Habit \(n)",
                     category: .custom, kind: .yesNo, defaultOn: true, enabled: true, isCustom: true, sort: n)
        }
        state.env.persistence.saveDocument(MockJournal.behaviors + more, key: JournalStore.behaviorsKey, at: .now)
        let sheet = AnyView(AddBehaviorSheet(store: JournalStore(env: state.env), name: "Evening walk").previewEnvironment(state)
            .toggleStyle(.ryft).environment(\.locale, Locale(identifier: "en_US")))
        try await host(sheet, height: 1_400) { w in
            try await w.wait("the sheet") { has(w, id: "addHabit.add") }
            try await w.settle()
            let add = try node(w, id: "addHabit.add")
            #expect(!add.isEnabled, "a valid name, but 50 of the user's own")
            #expect(w.node("You have 50 habits of your own, the most RYFT keeps. Delete one to add another.", exactly: true) != nil)
        }
    }

    @Test("N3: while Add a habit saves, Close is disabled (and the sheet can't be swiped away); otherwise it's live",
          arguments: [false, true])
    func addHabitCloseWhileSaving(_ saving: Bool) async throws {
        let state = AppState.preview()
        let sheet = AnyView(AddBehaviorSheet(store: journalPreviewStore(state), name: "Evening walk", saving: saving)
            .previewEnvironment(state).toggleStyle(.ryft).environment(\.locale, Locale(identifier: "en_US")))
        try await host(sheet, height: 1_400) { w in
            try await w.wait("the sheet") { w.node("Close", exactly: true) != nil }
            try await w.settle()
            let close = try node(w, "Close")
            #expect(close.isEnabled == !saving, "Close enabled: \(close.isEnabled)")
        }
    }

    @Test("S1: the message field keeps 4 lines' room at the default size and AX3, so its prompt is never cut off",
          arguments: [false, true])
    func reportFieldRoom(_ ax3: Bool) async throws {
        try await host(SubpageShotScreen.report { _ in }, ax3: ax3) { w in
            try await w.wait("the form") { has(w, id: "report.send") }
            try await w.settle()
            let field = try #require(Self.textViews(in: w.host.view).first, "the message's text view")
            let font = try #require(field.font ?? field.typingAttributes[.font] as? UIFont, "its font")
            let line = font.lineHeight
            #expect(field.bounds.height >= 4 * line - 1, "\(field.bounds.height) for lines of \(line)")
        }
    }

    private static func textViews(in view: UIView) -> [UITextView] {
        ((view as? UITextView).map { [$0] } ?? []) + view.subviews.flatMap(textViews)
    }

    @Test("N1, N6: rate limited, the bar says why Send is off; over 4,000 characters, the footer says it's too long")
    func reportCaptions() async throws {
        try await host(SubpageShotScreen.report { $0.stage(message: SubpageShotScreen.message, category: .data, result: .rateLimited) }) { w in
            try await w.wait("the notice") { w.node("Copy message", exactly: true) != nil }
            try await w.settle()
            #expect(w.node("You can send again tomorrow.", exactly: true) != nil)
            let send = try node(w, id: "report.send")
            #expect(!send.isEnabled)
        }
        try await host(SubpageShotScreen.report { $0.stage(message: String(repeating: "x", count: 4_001)) }) { w in
            try await w.wait("the form") { has(w, id: "report.count") }
            try await w.settle()
            #expect(w.node("Too long: a report takes up to 4,000 characters.") != nil)
        }
        try await host(SubpageShotScreen.report { $0.stage(message: SubpageShotScreen.message) }) { w in
            try await w.wait("the form") { has(w, id: "report.send") }
            try await w.settle()
            #expect(w.node("Too long") == nil && w.node("You can send again tomorrow.") == nil)
        }
    }
}

private extension BehaviorEffect {
    /// A significant effect of `delta` points, its 90 % interval around it.
    static func significantTest(delta: Double) -> BehaviorEffect {
        BehaviorEffect(delta: delta, ciLo: delta - 1, ciHi: delta + 1, significant: true, nYes: 12, nNo: 31)
    }
}
