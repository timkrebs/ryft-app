import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// PR 6 A (signed out, onboarding, splash; docs/work/2026-11-16-nocturne/design-pr6-a-onboarding.md §8): the decisions
/// without a window (Resend, the Apple button's height, the splash's wait, the onboarding fallback text, no teal or old
/// controls in area A's files) and the screens in a real window, read from the accessibility tree (`HostedWindow`):
/// Welcome's ways in, the three forms in reading order at the default size and AX3, consent at AX3 and AX5, the wear
/// tiles' selected shape, About you, Apple Health's pinned bar, the splash caption after 3 s.
@MainActor
@Suite("PR 6 A: signed out and onboarding", .serialized)
struct SignedOutOnboardingTests {
    struct SizeCase: Sendable, CustomTestStringConvertible {
        let size: DynamicTypeSize
        let category: UIContentSizeCategory
        var testDescription: String { "\(size)" }
    }

    nonisolated static let standard = SizeCase(size: .large, category: .large)
    nonisolated static let ax3 = SizeCase(size: .accessibility3, category: .accessibilityExtraLarge)
    nonisolated static let ax5 = SizeCase(size: .accessibility5, category: .accessibilityExtraExtraExtraLarge)
    private static let width: CGFloat = 390, height: CGFloat = 844, bottomInset: CGFloat = 34

    private func run(_ s: SizeCase, _ content: some View, body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: Self.width, height: Self.height, bottomInset: Self.bottomInset, typeSize: s.size,
                                   category: s.category, content, body: body)
    }

    /// A clock that never moves: no field takes the keyboard (`authFocus`), no splash caption.
    private static func still() -> AppEnvironment { AppEnvironment.test() }

    private func expectNoOverlap(_ nodes: [HostedWindow.Node], _ context: String) {
        for (i, a) in nodes.enumerated() {
            for b in nodes[(i + 1)...] {
                let overlap = a.frame.intersection(b.frame)
                #expect(overlap.isNull || overlap.width < 1 || overlap.height < 1,
                        "\(context): '\(a.label)' \(a.frame) overlaps '\(b.label)' \(b.frame)")
            }
        }
    }

    private static func navigationController(in controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let nav = controller as? UINavigationController { return nav }
        for child in controller.children {
            if let nav = navigationController(in: child) { return nav }
        }
        return navigationController(in: controller.presentedViewController)
    }

    /// The window's text fields (UIKit's, outside SwiftUI's nodes), top to bottom.
    private func textFields(_ w: HostedWindow) -> [UITextField] {
        func walk(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(walk)
        }
        return walk(w.window).sorted { $0.convert($0.bounds, to: w.window).minY < $1.convert($1.bounds, to: w.window).minY }
    }

    /// The system's Sign in with Apple button (a UIKit view, outside SwiftUI's nodes).
    private func appleButton(in view: UIView) -> UIView? {
        if String(describing: type(of: view)).contains("ASAuthorizationAppleIDButton") { return view }
        for sub in view.subviews {
            if let found = appleButton(in: sub) { return found }
        }
        return nil
    }

    /// The nodes that aren't the pinned bar's (`ids`): the page that scrolls under it.
    private func pageNodes(_ w: HostedWindow, excluding ids: [String]) -> [HostedWindow.Node] {
        var page: [HostedWindow.Node] = []
        for node in w.nodes() where !ids.contains(node.identifier ?? "") {
            page.append(node)
        }
        return page
    }

    /// Scrolls the page to its end and lets it settle.
    private func scrollToEnd(_ w: HostedWindow) async throws {
        guard let scroll = w.pageScrollView() else { return }
        let end = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
        scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top, end)), animated: false)
        try await w.settle()
    }

    // MARK: test 8: Resend

    @Test("Resend: idle → sending → sent, announced once; a failure goes back to idle; taps while sending or sent do nothing")
    func resend() async {
        var announced: [String] = []
        let model = InboxResendModel { announced.append($0) }
        #expect(model.phase == .idle)
        var seen: InboxResendModel.Phase?
        await model.resend {
            seen = model.phase
            return false
        }
        #expect(seen == .sending && model.phase == .idle && announced.isEmpty, "failed: back to idle, the banner says why")

        var calls = 0
        await model.resend {
            calls += 1
            await model.resend { calls += 1; return true } // a second tap while sending
            return true
        }
        #expect(calls == 1 && model.phase == .sent)
        #expect(announced == [String(localized: "Sent again")])
        await model.resend { calls += 1; return true }
        #expect(calls == 1, "sent stays sent until the screen is left")
    }

    // MARK: test 6: Welcome

    @Test("The Apple button: 52 at the default size, growing with the text, never past 64")
    func appleButtonHeight() {
        #expect(AppleSignInButton.height(scaled: 40) == 52)
        #expect(AppleSignInButton.height(scaled: 52) == 52)
        #expect(AppleSignInButton.height(scaled: 58) == 58)
        #expect(AppleSignInButton.height(scaled: 120) == 64)
    }

    @Test("Welcome: the Apple button is 52 (64 at AX3); \"Have an account? Log in\" is one 44 pt button that opens Log in",
          arguments: [standard, ax3])
    func welcomeWaysIn(_ s: SizeCase) async throws {
        let view = WelcomeView(configProblem: nil)
            .environment(AuthService.preview(signedIn: false))
            .environment(\.appEnvironment, Self.still())
        try await run(s, view) { w in
            try await w.settle()
            let button = try #require(appleButton(in: w.window), "the Sign in with Apple button")
            let height = button.convert(button.bounds, to: w.window).height
            #expect(abs(height - (s.size.isAccessibilitySize ? 64 : 52)) < 0.5, "Apple button \(height)")

            let logIn = try #require(w.nodes().first { $0.identifier == "welcome.logIn" }, "\(w.nodes().map(\.label))")
            #expect(logIn.label.contains("Have an account?") && logIn.label.contains("Log in"), "\(logIn.label)")
            #expect(logIn.traits.contains(.button) && logIn.frame.height >= 44, "\(logIn.frame)")
            #expect(logIn.inputLabels.contains("Log in"), "Voice Control: \(logIn.inputLabels)")
            if s.size.isAccessibilitySize { try await scrollToEnd(w) }
            let shown = try #require(w.nodes().first { $0.identifier == "welcome.logIn" })
            #expect(shown.activate())
            try await w.wait("Log in pushed") { w.nodes().contains { $0.label == "Log in" && $0.traits.contains(.header) } }
            #expect(textFields(w).map(\.accessibilityLabel) == ["Email", "Password"])
        }
    }

    // MARK: test 7: the forms

    enum Form: String, CaseIterable, Sendable { case logIn, createAccount, resetPassword }

    private struct FormExpectation {
        let view: AnyView
        let title: String
        let fields: [String]
        let primary: String
        let enabled: Bool
    }

    private func expectation(_ form: Form) -> FormExpectation {
        switch form {
        case .logIn:
            return FormExpectation(view: AnyView(LogInView(path: .constant([]))), title: "Log in",
                                   fields: ["Email", "Password"], primary: "Log in", enabled: false)
        case .createAccount:
            return FormExpectation(view: AnyView(CreateAccountView(path: .constant([]))), title: "Create account",
                                   fields: ["Name", "Email", "Password"], primary: "Create account", enabled: false)
        case .resetPassword:
            return FormExpectation(view: AnyView(ForgotPasswordView(path: .constant([]), email: "alex@example.com")),
                                   title: "Reset password", fields: ["Email"], primary: "Send reset link", enabled: true)
        }
    }

    @Test("Log in, Create account, Reset password: the header, the fields by their labels in order, nothing overlapping, the primary reachable",
          arguments: Form.allCases, [standard, ax3])
    func forms(_ form: Form, _ s: SizeCase) async throws {
        let e = expectation(form)
        let view = NavigationStack { e.view }
            .environment(AuthService.preview(signedIn: false))
            .environment(\.appEnvironment, Self.still())
        try await run(s, view) { w in
            try await w.settle()
            let nodes = w.nodes()
            let header = try #require(nodes.first { $0.label == e.title && $0.traits.contains(.header) },
                                      "\(nodes.map(\.label))")
            let back = try #require(nodes.firstIndex { $0.identifier == "subpage.back" })
            let title = try #require(nodes.firstIndex { $0.label == e.title && $0.traits.contains(.header) })
            #expect(back < title, "Back, then the title")
            #expect(header.frame.minY < 120, "the title at the top: \(header.frame)")
            let fields = textFields(w)
            #expect(fields.map(\.accessibilityLabel) == e.fields)
            expectNoOverlap(nodes, "\(form) \(s.size)")

            // The primary under the fields, reachable by scrolling, dimmed with its reason until the form is filled.
            try await scrollToEnd(w)
            let primary = try #require(w.nodes().first { $0.label == e.primary && !$0.traits.contains(.header) },
                                       "\(w.nodes().map(\.label))")
            let last = try #require(textFields(w).last)
            let lastField = last.convert(last.bounds, to: w.window)
            #expect(primary.frame.minY > lastField.maxY, "the primary after the fields")
            #expect(primary.frame.maxY <= Self.height - Self.bottomInset + 0.5, "on screen: \(primary.frame)")
            #expect(primary.isEnabled == e.enabled)
            if form == .logIn {
                #expect(primary.hint == String(localized: "Fill in your email and password first."), "\(primary.hint ?? "nil")")
            }
        }
    }

    // MARK: test 10: consent

    @Test("Consent: nothing overlaps; the age line, the policy link and the checkbox are there; Agree waits for the tick",
          arguments: [ax3, ax5])
    func consent(_ s: SizeCase) async throws {
        try await run(s, OnboardingStepPreview(step: .consent)) { w in
            try await w.wait("Consent") { w.node("Your health data, your consent") != nil }
            // The step reads the policy version it shows (demo data: the mock config's); Agree waits for it too.
            let caption = String(localized: "Nothing is synced until you agree. Privacy policy version \(MockData.policyVersion).")
            try await w.wait("the policy version") { w.node(caption) != nil }
            try await w.settle()
            let nodes = w.nodes()
            expectNoOverlap(nodes, "consent \(s.size)")
            #expect(nodes.contains { $0.identifier == "consent.minimumAge" && $0.label == "You must be at least 16 to use RYFT." })
            let link = try #require(nodes.first { $0.identifier == "consent.policy" }, "\(nodes.map(\.label))")
            #expect(link.label == "Read the privacy policy" && link.traits.contains(.button) && link.frame.height >= 44)
            let agree = try #require(nodes.first { $0.identifier == "consent.agree" })
            #expect(!agree.isEnabled, "not before the tick")
            let box = try #require(nodes.first { $0.identifier == "consent.checkbox" })
            #expect(!box.isSelected && box.traits.contains(.button))
            #expect(box.activate())
            try await w.wait("ticked") { w.nodes().first { $0.identifier == "consent.checkbox" }?.isSelected == true }
            #expect(w.nodes().first { $0.identifier == "consent.agree" }?.isEnabled == true)
        }
    }

    // MARK: test 11: wear

    @Test("What do you wear?: a selected tile has the selected trait and a border the others don't (not colour alone)")
    func wearTiles() async throws {
        let state = AppState.preview()
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        try await run(Self.standard, TrackerPickerView(model: model, picked: ["garmin"]).previewEnvironment(state)) { w in
            try await w.wait("tiles") { w.nodes().contains { $0.identifier == "wear.tile.garmin" } }
            try await w.settle()
            let on = try #require(w.nodes().first { $0.identifier == "wear.tile.garmin" })
            let off = try #require(w.nodes().first { $0.identifier == "wear.tile.oura" })
            #expect(on.isSelected && !off.isSelected)
            // Half the 1.5 pt border in from the tile's edge, halfway down: ink on the chosen tile, the card's fill on the other.
            let edge = { (n: HostedWindow.Node) in w.pixel(at: CGPoint(x: n.frame.minX + 0.75, y: n.frame.midY)) }
            let ink = try #require(edge(on)), plain = try #require(edge(off))
            #expect(ink.r > 0.7 && ink.g > 0.7, "the border: \(ink)")
            #expect(plain.r < 0.3 && plain.g < 0.3, "no border: \(plain)")
            #expect(w.nodes().first { $0.identifier == "wear.continue" }?.isEnabled == true)
        }
    }

    // MARK: test 12: About you

    @Test("About you: Continue waits for a year; the saved values are buttons; the pinned bar stays under a quarter at AX3")
    func aboutYou() async throws {
        try await run(Self.ax3, OnboardingStepPreview(step: .aboutYou)) { w in
            try await w.wait("About you") { w.node("About you") != nil }
            try await w.settle()
            let save = try #require(w.nodes().first { $0.identifier == "aboutYou.save" }, "\(w.nodes().map(\.label))")
            #expect(!save.isEnabled, "no year chosen yet")
            #expect(w.nodes().contains { $0.identifier == "aboutYou.skip" })
            // The bar from its rule to the home indicator's inset.
            let bar = Self.height - Self.bottomInset - (save.frame.minY - PinnedBarSpec.topPadding)
            #expect(bar <= Self.height * 0.25, "the pinned bar is \(bar) of \(Self.height)")
        }
        try await run(Self.standard, OnboardingStepPreview(step: .aboutYou, saved: true)) { w in
            try await w.wait("saved") { w.nodes().contains { $0.identifier == "aboutYou.maxHR" } }
            try await w.settle()
            for id in ["aboutYou.maxHR", "aboutYou.sleepBase"] {
                let row = try #require(w.nodes().first { $0.identifier == id })
                #expect(row.traits.contains(.button) && row.frame.height >= 46, "\(id) \(row.frame)")
            }
            #expect(w.node("Estimated from your birth year") != nil)
        }
    }

    // MARK: test 13: the pinned bars

    @Test("Apple Health, What do you wear? and Set up: both pinned actions reachable, the page clear of the bar, the bar ≤ 25 % at AX3 and ≤ 35 % at AX5",
          arguments: ["health", "wear", "setup"], [ax3, ax5])
    func pinnedBars(_ screen: String, _ s: SizeCase) async throws {
        let state = AppState.preview()
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        model.devices.stage(["garmin"])
        let view: AnyView
        let ids: (String, String)
        switch screen {
        case "health":
            view = AnyView(HealthPermissionView().environment(\.appEnvironment, state.env))
            ids = ("health.continue", "health.notNow")
        case "wear":
            view = AnyView(TrackerPickerView(model: model, picked: ["garmin"]).previewEnvironment(state))
            ids = ("wear.continue", "wear.skip")
        default:
            view = AnyView(TrackerSetupStepView(model: model, checkOpen: false).previewEnvironment(state))
            ids = ("trackerSetup.done", "trackerSetup.later")
        }
        try await run(s, view) { w in
            try await w.wait(screen) { w.nodes().contains { $0.identifier == ids.0 } }
            try await w.settle()
            let primary = try #require(w.nodes().first { $0.identifier == ids.0 })
            let quiet = try #require(w.nodes().first { $0.identifier == ids.1 })
            let limit = Self.height - Self.bottomInset
            #expect(primary.frame.minY >= 0 && quiet.frame.maxY <= limit + 0.5, "\(primary.frame) \(quiet.frame)")
            #expect(primary.frame.height >= 44 && quiet.frame.height >= 44)
            // The bar from its rule to the home indicator's inset: a quarter at AX3; at AX5 the longest quiet action
            // ("Show me again later") wraps to three lines.
            let barTop = primary.frame.minY - PinnedBarSpec.topPadding
            let bar = limit - barTop
            let share = s.size == .accessibility5 ? 0.35 : 0.25
            #expect(bar <= Self.height * share, "\(screen) bar \(bar) of \(Self.height) at \(s.size)")
            if screen == "health" { expectNoOverlap(pageNodes(w, excluding: [ids.0, ids.1]), "health \(s.size)") }
            // The page's last element can be scrolled clear of the bar.
            try await scrollToEnd(w)
            let page = pageNodes(w, excluding: [ids.0, ids.1])
            let lowest = page.map(\.frame.maxY).max() ?? 0
            #expect(lowest <= barTop + 0.5, "the page's end at \(lowest), the bar at \(barTop)")
        }
    }

    // MARK: test 14: the splash

    @Test("Splash: no caption before 3 s; then \"Checking your account…\" under the mark, which stays where it was")
    func splashCaption() async throws {
        let clock = TestClock()
        let env = AppEnvironment.test(clock: clock)
        let caption = String(localized: "Checking your account…")
        try await run(Self.standard, SplashView().environment(\.appEnvironment, env)) { w in
            try await w.wait("the wait") { clock.pendingSleeps == 1 }
            try await w.settle()
            let mark = try #require(w.nodes().first { $0.identifier == "splash.mark" }, "\(w.nodes().map(\.label))")
            #expect(mark.label == "RYFT")
            #expect(abs(mark.frame.midX - Self.width / 2) < 0.5, "centred: \(mark.frame)")
            clock.advance(by: .seconds(2))
            try await w.settle()
            #expect(w.node(caption) == nil && clock.pendingSleeps == 1, "not before 3 s")
            clock.advance(by: .seconds(1))
            try await w.wait("the caption") { w.node(caption) != nil }
            try await w.settle()
            let shown = try #require(w.node(caption))
            let after = try #require(w.nodes().first { $0.identifier == "splash.mark" })
            #expect(after.frame == mark.frame, "the mark never moves: \(mark.frame) → \(after.frame)")
            #expect(shown.frame.minY >= mark.frame.maxY, "under the mark: \(shown.frame)")
        }
    }

    // MARK: the onboarding steps' fallback text

    @Test("A step that can't reach the platform says so; any other failure, a server's message included, says only that it didn't work (§A-7)")
    func fallbackMessages() {
        let offline = OnboardingCoordinator.fallbackMessage(for: APIError.transport(URLError(.notConnectedToInternet)))
        #expect(offline == String(localized: "No connection. Check your internet and try again."))
        #expect(OnboardingCoordinator.fallbackMessage(for: URLError(.timedOut)) == offline)
        let other = String(localized: "Something went wrong. Please try again.")
        #expect(OnboardingCoordinator.fallbackMessage(for: APIError.http(503, "")) == other)
        #expect(OnboardingCoordinator.fallbackMessage(for: APIError.http(500, "pq: relation \"users\" does not exist")) == other)
        let undecodable = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unexpected field"))
        #expect(OnboardingCoordinator.fallbackMessage(for: undecodable) == other)
    }

    // MARK: consent records the version it showed (SEC-1)

    @Test("Consent: with no policy version shown Agree is off and sends nothing; a failed read says so; once a version arrives, Agree records it")
    func consentNeedsAShownVersion() async {
        let api = MockPlatformAPI()
        api.accountConsent = nil
        let clock = TestClock()
        let state = AppState(env: AppEnvironment.test(api: api, clock: clock))
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        #expect(model.policyVersion == nil && !model.canAgree)
        #expect(await !model.agree())
        #expect(api.consentPosts.isEmpty)

        // Not a transient failure: the read pipeline doesn't retry it (a retry would wait on the test clock).
        api.failure = APIError.http(404, "no config")
        await model.loadPolicyIfMissing()
        #expect(model.policyRead == .failed && model.policyVersion == nil && !model.canAgree)

        api.failure = nil
        await model.loadPolicyIfMissing() // Try again (user-initiated: no wait after the failure)
        #expect(model.policyRead == .idle && model.policyVersion == MockData.policyVersion && model.canAgree)
        // The step drew another version than the current one: nothing is agreed to.
        #expect(await !model.agree(shown: "2026-01-01"))
        #expect(api.consentPosts.isEmpty)
        #expect(await model.agree(shown: MockData.policyVersion))
        #expect(api.consentPosts == [MockData.policyVersion])
    }

    @Test("Consent past the config's ttl: the version is read again; a newer one is shown, not agreed to, and the tick goes")
    func consentAfterThePolicyChanged() async throws {
        let api = MockPlatformAPI()
        api.accountConsent = nil
        let clock = TestClock()
        let state = AppState(env: AppEnvironment.test(api: api, clock: clock))
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        func caption(_ version: String) -> String {
            String(localized: "Nothing is synced until you agree. Privacy policy version \(version).")
        }
        func box(_ w: HostedWindow) -> HostedWindow.Node? { w.nodes().first { $0.identifier == "consent.checkbox" } }
        func agree(_ w: HostedWindow) -> HostedWindow.Node? { w.nodes().first { $0.identifier == "consent.agree" } }
        try await run(Self.standard, ConsentView(model: model).previewEnvironment(state)) { w in
            try await w.wait("the version") { w.node(caption(MockData.policyVersion)) != nil }
            #expect(try #require(box(w)).activate())
            try await w.wait("ticked") { box(w)?.isSelected == true && agree(w)?.isEnabled == true }

            clock.advance(by: .seconds(api.remoteConfig.ttlSec + 1))
            let newer = "2026-12-01"
            api.remoteConfig = RemoteConfig(flags: [:], evaluatedAt: clock.now(), ttlSec: 21_600,
                                            privacyPolicyVersion: newer, privacyPolicyUrl: nil)
            #expect(await !model.agree(shown: MockData.policyVersion))
            #expect(api.consentPosts.isEmpty, "nothing posted for the old version")
            #expect(model.errorMessage
                == String(localized: "The privacy policy was just updated. Read the new version, then agree again."))
            #expect(model.policyVersion == newer)
            try await w.wait("the new version") { w.node(caption(newer)) != nil }
            try await w.wait("unticked") { box(w)?.isSelected == false }
            #expect(agree(w)?.isEnabled == false, "Agree waits for a new tick")
        }
    }

    // MARK: the first field takes the keyboard once (S4)

    @Observable
    final class Route {
        var path: [AuthRoute] = []
    }

    private struct CreateAccountStack: View {
        @Bindable var route: Route

        var body: some View {
            NavigationStack(path: $route.path) {
                CreateAccountView(path: $route.path)
                    .navigationDestination(for: AuthRoute.self) { next in
                        if case let .checkInbox(reason, email) = next { CheckInboxView(reason: reason, email: email) }
                    }
            }
        }
    }

    @Test("Create account focuses Name on its first appearance only: back from Check your inbox, the keyboard stays down")
    func focusOnce() async throws {
        let clock = TestClock()
        let route = Route()
        let view = CreateAccountStack(route: route)
            .environment(AuthService.preview(signedIn: false))
            .environment(\.appEnvironment, AppEnvironment.test(clock: clock))
        try await run(Self.standard, view) { w in
            try await w.wait("the focus wait") { clock.pendingSleeps == 1 }
            clock.advance(by: AuthScreenSpec.focusDelay)
            // Name, the form's first field, has the keyboard.
            try await w.wait("Name focused") { textFields(w).first?.isFirstResponder == true }

            route.path.append(.checkInbox(.confirmSignUp, email: "alex@example.com"))
            try await w.wait("Check your inbox") { w.node("Check your inbox") != nil }
            try await w.settle()
            // The bar is hidden: the keeper also lets iOS 26's swipe from the content pop, but only a sideways pan
            // towards the trailing edge (none is under way here).
            if #available(iOS 26.0, *) {
                let nav = try #require(Self.navigationController(in: w.window.rootViewController))
                let content = try #require(nav.interactiveContentPopGestureRecognizer)
                let keeper = try #require(content.delegate as? InteractivePopGestureKeeper, "the keeper decides the content swipe")
                #expect(content.isEnabled && !keeper.gestureRecognizerShouldBegin(content))
            }
            let another = try #require(w.nodes().first { $0.label == "Use another email" })
            #expect(another.activate())
            try await w.wait("back on the form") { route.path.isEmpty && w.node("Check your inbox") == nil }
            try await w.settle()
            #expect(clock.pendingSleeps == 0, "no second wait for the focus")
            clock.advance(by: AuthScreenSpec.focusDelay)
            try await w.settle()
            #expect(!textFields(w).contains { $0.isFirstResponder }, "no field took the keyboard again")
        }
    }

    // MARK: test 9: no teal, no old controls, dark previews only

    /// Area A's files (T6A.3, T6A.4, T6A.5 and the Details sheet's part of `StatusViews.swift`, checked by its markers).
    nonisolated static let areaFiles = [
        "Features/Auth/AccountHintSheet.swift", "Features/Auth/AuthComponents.swift", "Features/Auth/CheckInboxView.swift",
        "Features/Auth/CreateAccountView.swift", "Features/Auth/ForgotPasswordView.swift", "Features/Auth/LogInView.swift",
        "Features/Auth/ParkedActivitiesNotice.swift", "Features/Auth/SetNewPasswordView.swift",
        "Features/Auth/WelcomeView.swift", "Auth/AppleSignInButton.swift",
        "Features/Onboarding/HealthAccessHint.swift", "Features/Onboarding/HealthIllustration.swift",
        "Features/Onboarding/HealthPermissionView.swift", "Features/Onboarding/OnboardingSteps.swift",
        "Features/Onboarding/OnboardingTrackerSteps.swift", "Features/Onboarding/TrackerPickerGrid.swift",
        "App/SplashView.swift", "App/PlatformConfig.swift",
    ]

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Ryft").appendingPathComponent(path), encoding: .utf8)
    }

    @Test("Area A uses no teal, no pre-Nocturne control and no light preview; the Health mark never loops")
    func noTealNoOldControls() throws {
        let banned = ["Theme.accent", "Theme.onAccent", "Theme.teal", "TealButtonStyle", "PrimaryButton(", "Theme.graphite",
                      "surfaceRaised.opacity(0.6)", "SchemePair", "preferredColorScheme(.light)", "scheme: .light"]
        let addresses = try NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        for path in Self.areaFiles {
            let text = try Self.source(path)
            for word in banned {
                #expect(!text.contains(word), "\(path) has \(word)")
            }
            // Synthetic data only: the one sample address.
            let found = addresses.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            #expect(found.allSatisfy { $0 == "alex@example.com" }, "\(path): \(found)")
        }
        let auth = try Self.source("Features/Auth/AuthComponents.swift")
        #expect(!auth.contains("import AuthenticationServices"), "AuthComponents doesn't need AuthenticationServices")
        let mark = try Self.source("Features/Onboarding/HealthIllustration.swift")
        #expect(!mark.contains("TimelineView") && !mark.contains("repeatForever"), "the pulse draws once")
        #expect(HealthIllustration.progress(drawn: false, reduceMotion: true) == 1, "at rest under Reduce Motion")
        #expect(HealthIllustration.progress(drawn: false, reduceMotion: false) == 0)
        #expect(HealthIllustration.progress(drawn: true, reduceMotion: false) == 1)

        // The Details sheet's part of the shared file.
        let status = try Self.source("Design/StatusViews.swift")
        let start = try #require(status.range(of: "struct RefreshDetailsSheet: View {"))
        let end = try #require(status.range(of: "private enum RequestIDRowSpec"))
        let sheet = String(status[start.lowerBound..<end.lowerBound])
        for word in ["Theme.accent", "Theme.onAccent", "PrimaryButton(", "NavigationLink {"] {
            #expect(!sheet.contains(word), "the Details sheet has \(word)")
        }
    }

    @Test("The root's cross-fades respect Reduce Motion: no fixed easeInOut left in RootView, and the splash lives in its own file")
    func rootFades() throws {
        let root = try Self.source("App/RyftApp.swift")
        #expect(!root.contains(".easeInOut(duration: 0.3)"))
        #expect(!root.contains("struct SplashView"))
        #expect(root.contains("Theme.Motion.respecting(reduceMotion, Theme.Motion.quick)"))
    }
}
