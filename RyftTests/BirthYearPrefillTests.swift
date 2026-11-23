import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// About you's "Use my birth year from Apple Health" (health-groups.md §7 and §9 test 13, ADR 0027): its states, the
/// request before the read, a year out of range left alone, an account switch that leaves nothing, and Demo data without
/// the button. The year reaches the wheel only; nothing is sent before Continue. Synthetic data only.
@MainActor
@Suite("About you: the birth year from Apple Health")
struct BirthYearPrefillTests {
    nonisolated static let a = UUID(uuidString: "0000000A-0000-4000-8000-0000000000C1") ?? UUID()
    nonisolated static let b = UUID(uuidString: "0000000B-0000-4000-8000-0000000000C2") ?? UUID()

    /// An account's coordinator (Demo data off, `TestClock`: 2026, so 1920…2010 are offered) over a scriptable Health.
    @MainActor
    struct Rig {
        let api = MockPlatformAPI()
        let health: MockHealthStore
        let client: MockAuthClient
        let auth: AuthService
        let env: AppEnvironment
        let model: OnboardingCoordinator

        /// `sink`: analytics on (flag, config, opted in) into a recording sink.
        init(health: MockHealthStore = MockHealthStore(), signedInAs account: UUID = BirthYearPrefillTests.a,
             sink: FakeAnalyticsSink? = nil) {
            self.health = health
            let client = MockAuthClient(session: .preview(id: account))
            self.client = client
            let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
            let auth = AuthService(client: client, settings: Settings(defaults: defaults), defaults: defaults,
                                   wipeLocalData: { _ in true },
                                   deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                                   postAppleAuthorization: { _ in })
            self.auth = auth
            // The fake's record follows the signed-in account as the live store's does (`AccountScope`, which the
            // session writes).
            health.account = { AccountScope.current(defaults) }
            let env: AppEnvironment
            if let sink {
                env = .test(api: api, health: health, auth: auth, flags: [.analyticsEnabled: true], analyticsSink: sink)
                (env.flags as? StaticFlags)?.analytics = AnalyticsFixture.config
                env.analytics.setOptIn(true)
            } else {
                env = .test(api: api, health: health, auth: auth)
            }
            self.env = env
            let state = AppState(env: env)
            model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
            model.switchAccount(auth.accountID)
        }

        /// Holds every request open until `hold` opens; `entered` opens once the first is out.
        func holdRequests(entered: Gate, hold: Gate) {
            health.beforeAuthorizationReturns = {
                await entered.open()
                await hold.wait()
            }
        }

        /// Signs out, then RyftApp's account-change handler.
        func signOut() async {
            await auth.signOut()
            #expect(!auth.isSignedIn)
            model.switchAccount(auth.accountID)
        }

        /// Signs in as `account`, then RyftApp's account-change handler.
        func signIn(_ account: UUID) async {
            client.signInSession = .preview(id: account)
            _ = await auth.logIn(email: "alex@example.com", password: "0123456789")
            #expect(auth.accountID == account.uuidString)
            model.switchAccount(auth.accountID)
        }
    }

    // MARK: the states

    @Test("Never asked: the button with its primer; asked before: the button alone")
    func theStatesBeforeATap() {
        #expect(Rig().model.birthYearPrefill == .notAsked)
        let rig = Rig()
        rig.health.asked = [.about]
        #expect(rig.model.birthYearPrefill == .askedBefore)
    }

    @Test("Asking: the state is asking until the sheet answers, and a second tap asks nothing")
    func asking() async {
        let rig = Rig()
        let entered = Gate(), hold = Gate()
        rig.holdRequests(entered: entered, hold: hold)
        rig.health.birthYearValue = 1990
        let tap = Task { await rig.model.prefillBirthYear() }
        await entered.wait()
        #expect(rig.model.birthYearPrefill == .asking)
        #expect(await rig.model.prefillBirthYear() == nil, "a second tap while asking")
        #expect(rig.health.requests == [.about])
        await hold.open()
        #expect(await tap.value == 1990)
        #expect(rig.model.birthYearPrefill == .filled)
    }

    @Test("A year in range is returned for the wheel, and nothing is sent until Continue sends only the year")
    func filled() async throws {
        let rig = Rig()
        rig.health.birthYearValue = 1990
        #expect(await rig.model.prefillBirthYear() == 1990)
        #expect(rig.model.birthYearPrefill == .filled)
        #expect(rig.api.mePatches.isEmpty, "nothing is sent before Continue")
        #expect(await rig.model.saveAboutYou(birthYear: 1990))
        let patch = try #require(rig.api.mePatches.first)
        #expect(rig.api.mePatches.count == 1)
        #expect(patch.birthYear == 1990)
        let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any]
        #expect(fields?.keys.sorted() == ["birthYear"], "the year and no other field")
    }

    @Test("Apple Health shares no year (refused or unset): nothing, and the wheel gets no year")
    func nothing() async {
        let rig = Rig()
        #expect(await rig.model.prefillBirthYear() == nil)
        #expect(rig.model.birthYearPrefill == .nothing)
        #expect(rig.health.requests == [.about])
    }

    @Test("A request that fails is nothing too, and nothing is read after it")
    func aFailedRequestIsNothing() async {
        let rig = Rig()
        rig.health.birthYearValue = 1990
        rig.health.authorizationError = HealthPermissionError.notRequestable(.about)
        #expect(await rig.model.prefillBirthYear() == nil)
        #expect(rig.model.birthYearPrefill == .nothing)
        #expect(rig.health.birthYearReads.isEmpty)
    }

    // MARK: the request before the read

    @Test("No read before about is asked: the read comes after the request, with about in the record")
    func noReadBeforeAboutIsAsked() async {
        let rig = Rig()
        let entered = Gate(), hold = Gate()
        rig.holdRequests(entered: entered, hold: hold)
        rig.health.birthYearValue = 1990
        let tap = Task { await rig.model.prefillBirthYear() }
        await entered.wait()
        #expect(rig.health.birthYearReads.isEmpty, "the sheet is still up: nothing read")
        await hold.open()
        _ = await tap.value
        #expect(rig.health.requests == [.about], "only about, never core or another group")
        #expect(rig.health.birthYearReads == [[.about]], "one read, after the request was recorded")
    }

    @Test("Showing the button reads nothing and asks nothing")
    func theButtonAloneReadsNothing() {
        let rig = Rig()
        _ = rig.model.birthYearPrefill
        #expect(rig.health.requests.isEmpty)
        #expect(rig.health.birthYearReads.isEmpty)
    }

    // MARK: out of range

    @Test("A year outside 1920…2010 is not clamped: out of range, and no year for the wheel",
          arguments: [1900, 1919, 2011, 2015])
    func anOutOfRangeYearIsNotClamped(_ year: Int) async {
        let rig = Rig()
        rig.health.birthYearValue = year
        #expect(await rig.model.prefillBirthYear() == nil, "not clamped to a year the wheel offers")
        #expect(rig.model.birthYearPrefill == .outOfRange)
        #expect(rig.api.mePatches.isEmpty)
    }

    @Test("The range's ends are in range", arguments: [1920, 2010])
    func theRangesEndsFill(_ year: Int) async {
        let rig = Rig()
        rig.health.birthYearValue = year
        #expect(await rig.model.prefillBirthYear() == year)
        #expect(rig.model.birthYearPrefill == .filled)
    }

    // MARK: accounts

    @Test("A sign-out mid-request ends it with no outcome: nothing read, nothing returned, nothing sent")
    func aSignOutMidRequestLeavesNoOutcome() async {
        let rig = Rig()
        let entered = Gate(), hold = Gate()
        rig.holdRequests(entered: entered, hold: hold)
        rig.health.birthYearValue = 1990
        let tap = Task { await rig.model.prefillBirthYear() }
        await entered.wait()
        await rig.signOut()
        await hold.open()
        #expect(await tap.value == nil)
        #expect(rig.health.birthYearReads.isEmpty, "not read for an account that didn't ask")
        // Signed out: no record to read (no signed-out bucket), and no outcome of A's.
        #expect(rig.model.birthYearPrefill == .notAsked)
        #expect(rig.health.asked.isEmpty)
        // The sheet A answered is A's: recorded for A, the account that asked, and for nobody else.
        #expect(rig.health.askedByAccount == [Self.a.uuidString: [.about]])
        #expect(rig.api.mePatches.isEmpty)
    }

    @Test("The record is per account: after A's sheet, B reads not asked; A reads asked before again")
    func theRecordIsPerAccount() async {
        let rig = Rig()
        rig.health.birthYearValue = 1990
        #expect(await rig.model.prefillBirthYear() == 1990)
        #expect(rig.health.asked == [.about])
        await rig.signOut()
        await rig.signIn(Self.b)
        #expect(rig.health.asked.isEmpty)
        #expect(rig.model.birthYearPrefill == .notAsked, "B's own record, not A's")
        await rig.signOut()
        await rig.signIn(Self.a)
        #expect(rig.model.birthYearPrefill == .askedBefore)
        #expect(rig.health.askedByAccount == [Self.a.uuidString: [.about]])
    }

    @Test("An account switch mid-request leaves no outcome, and A's late answer never touches B's own tap")
    func anAccountSwitchMidRequestLeavesNoOutcome() async {
        let rig = Rig()
        let entered = Gate(), hold = Gate()
        rig.holdRequests(entered: entered, hold: hold)
        rig.health.birthYearValue = 1990
        let tapA = Task { await rig.model.prefillBirthYear() }
        await entered.wait()
        await rig.signOut()
        await rig.signIn(Self.b)
        #expect(rig.model.birthYearPrefill != .asking, "B starts without A's request")

        // B taps while A's request is still out, and its own is held too.
        let enteredB = Gate()
        rig.health.beforeAuthorizationReturns = { await enteredB.open() }
        rig.health.birthYearValue = 1975
        #expect(await rig.model.prefillBirthYear() == 1975)
        #expect(rig.model.birthYearPrefill == .filled)

        await hold.open()
        #expect(await tapA.value == nil, "A's answer goes nowhere")
        #expect(rig.model.birthYearPrefill == .filled, "B's outcome stays B's")
        #expect(rig.health.birthYearReads.count == 1, "read once, for B's request only")
        #expect(rig.api.mePatches.isEmpty)
    }

    // MARK: Demo data and availability

    @Test("Demo data hides the button, and a tap there asks and reads nothing")
    func demoHidesTheButton() async throws {
        let state = AppState.preview()
        #expect(state.env.isDemo)
        let health = try #require(state.env.health as? MockHealthStore)
        health.birthYearValue = 1990
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        #expect(model.birthYearPrefill == nil)
        #expect(await model.prefillBirthYear() == nil)
        #expect(health.requests.isEmpty)
        #expect(health.birthYearReads.isEmpty)
    }

    @Test("Without Apple Health on the device there's no button")
    func unavailableHidesTheButton() async {
        let health = MockHealthStore()
        health.isAvailable = false
        let rig = Rig(health: health)
        #expect(rig.model.birthYearPrefill == nil)
        #expect(await rig.model.prefillBirthYear() == nil)
        #expect(health.requests.isEmpty)
    }

    // MARK: the wheel

    @Test("Choosing a year on the wheel clears From Apple Health (and the notes)")
    func choosingAYearClearsFromAppleHealth() async {
        let rig = Rig()
        rig.health.birthYearValue = 1990
        _ = await rig.model.prefillBirthYear()
        #expect(rig.model.birthYearPrefill == .filled)
        rig.model.birthYearChosen()
        #expect(rig.model.birthYearPrefill == .askedBefore, "the button again, without the caption")

        rig.health.birthYearValue = 1900
        _ = await rig.model.prefillBirthYear()
        #expect(rig.model.birthYearPrefill == .outOfRange)
        rig.model.birthYearChosen()
        #expect(rig.model.birthYearPrefill == .askedBefore)
    }

    // MARK: analytics

    @Test("No analytics event on the prefill path carries the year (the gate open, every capture checked)")
    func noEventCarriesTheYear() async {
        let sink = FakeAnalyticsSink()
        let rig = Rig(sink: sink)
        #expect(sink.starts.count == 1, "the gate is open: anything tracked would be captured")
        rig.health.birthYearValue = 1990
        #expect(await rig.model.prefillBirthYear() == 1990)
        #expect(await rig.model.saveAboutYou(birthYear: 1990))
        // What RootView tracks for the step, and the step's end.
        rig.env.analytics.track(.onboardingStep(.aboutYou))
        rig.model.finishAboutYou()
        #expect(!sink.captures.isEmpty)
        for capture in sink.captures {
            #expect(!capture.properties.values.contains { $0.contains("1990") }, "\(capture.name)")
            #expect(!capture.properties.keys.contains { $0.contains("birth") || $0.contains("year") }, "\(capture.name)")
        }
    }

    /// The allow-list: no event of the closed list can carry a year at all, whatever the call site.
    @Test("No event of the allow-list has a year-like value or a birth or year property")
    func noEventCanCarryAYear() {
        for event in AnalyticsEvent.everyCase {
            for (key, value) in event.properties {
                #expect(!key.contains("birth") && !key.contains("year") && !key.contains("age"), "\(event.name).\(key)")
                #expect(Int(value).map { !(1900...2100).contains($0) } ?? true, "\(event.name).\(key) = \(value)")
            }
        }
    }

    @Test("A wheel change while asking doesn't end the request's state")
    func aChoiceWhileAskingKeepsAsking() async {
        let rig = Rig()
        let entered = Gate(), hold = Gate()
        rig.holdRequests(entered: entered, hold: hold)
        let tap = Task { await rig.model.prefillBirthYear() }
        await entered.wait()
        rig.model.birthYearChosen()
        #expect(rig.model.birthYearPrefill == .asking)
        await hold.open()
        _ = await tap.value
        #expect(rig.model.birthYearPrefill == .nothing)
    }
}

/// The previews as a user sees them: each state's words where they belong, and no button in Demo data.
@MainActor
@Suite("About you: the birth year from Apple Health, on screen", .serialized)
struct BirthYearPrefillScreenTests {
    private static let wait: Duration = .seconds(15)

    private func screen(_ view: some View, _ check: @MainActor (HostedWindow) throws -> Void,
                        until ready: @escaping @MainActor (HostedWindow) -> Bool) async throws {
        try await HostedWindow.run(width: 390, height: 1_400, view.environment(\.locale, Locale(identifier: "en_US"))) { w in
            try await w.wait("the state", timeout: Self.wait) { ready(w) }
            try await w.settle()
            try check(w)
        }
    }

    private static func node(_ w: HostedWindow, _ id: String) -> HostedWindow.Node? {
        w.nodes().first { $0.identifier == id }
    }

    private static func text(_ w: HostedWindow, _ words: String) -> Bool {
        w.nodes().contains { $0.label.contains(words) }
    }

    @Test("Never asked: the button and its primer")
    func notAsked() async throws {
        try await screen(AboutYouPrefillPreview(.notAsked)) { w in
            #expect(Self.text(w, "RYFT reads your date of birth and keeps only the year."))
            #expect(!Self.text(w, "From Apple Health"))
        } until: { Self.node($0, "aboutYou.useHealth") != nil }
    }

    @Test("Asked before: the button without the primer")
    func askedBefore() async throws {
        try await screen(AboutYouPrefillPreview(.askedBefore)) { w in
            #expect(!Self.text(w, "RYFT reads your date of birth and keeps only the year."))
        } until: { Self.node($0, "aboutYou.useHealth") != nil }
    }

    @Test("Filled: From Apple Health under the wheel, and no button")
    func filled() async throws {
        try await screen(AboutYouPrefillPreview(.filled)) { w in
            #expect(Self.node(w, "aboutYou.useHealth") == nil)
            #expect(Self.node(w, "aboutYou.save")?.isEnabled == true, "a year on the wheel: Continue can send it")
        } until: { Self.text($0, "From Apple Health") }
    }

    @Test("Nothing: the honest note with Allow in Health")
    func nothing() async throws {
        try await screen(AboutYouPrefillPreview(.nothing)) { w in
            #expect(Self.text(w, "Allow in Health"))
            #expect(!Self.text(w, "From Apple Health"))
            #expect(Self.node(w, "aboutYou.save")?.isEnabled == false, "no year on the wheel")
        } until: { Self.text($0, "Apple Health didn't share a birth year.") }
    }

    @Test("Out of range: the note, and the wheel without a year")
    func outOfRange() async throws {
        try await screen(AboutYouPrefillPreview(.outOfRange)) { w in
            #expect(!Self.text(w, "From Apple Health"))
            #expect(Self.node(w, "aboutYou.save")?.isEnabled == false, "the wheel untouched: nothing to send")
        } until: { Self.text($0, "outside the years RYFT offers") }
    }

    /// The step shown anew after a fill (its `@State` year gone): asked before, never "From Apple Health" under an
    /// empty wheel, and nothing for Continue to send.
    @Test("Filled once, then a fresh About you for the same account: the button, no caption, Continue off")
    func aFillShownAnewReadsAsAskedBefore() async throws {
        let state = MockBirthYearPrefill.state(health: MockBirthYearPrefill.health(.filled))
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        #expect(await model.prefillBirthYear() == MockBirthYearPrefill.year)
        #expect(model.birthYearPrefill == .filled)
        try await screen(AboutYouView(model: model).previewEnvironment(state)) { w in
            #expect(!Self.text(w, "From Apple Health"))
            #expect(!Self.text(w, "RYFT reads your date of birth and keeps only the year."), "asked before: no primer")
            #expect(Self.node(w, "aboutYou.save")?.isEnabled == false, "an empty wheel: nothing to send")
        } until: { Self.node($0, "aboutYou.useHealth") != nil }
    }

    /// The wheel's picker (SwiftUI's `.wheel` style is a `UIPickerView`).
    private static func picker(_ w: HostedWindow) -> UIPickerView? {
        func find(_ view: UIView) -> UIPickerView? {
            if let picker = view as? UIPickerView { return picker }
            return view.subviews.lazy.compactMap(find).first
        }
        return find(w.window)
    }

    /// The row of `year` on the wheel: "Choose your birth year" first, then the years newest first (2010 in 2026).
    private static func row(_ year: Int) -> Int { 2010 - year + 1 }

    /// A turn of the wheel as a finger ends it: the row selected, then the delegate told, as UIKit does.
    private static func turn(_ w: HostedWindow, to year: Int) async throws {
        let picker = try #require(picker(w))
        picker.selectRow(row(year), inComponent: 0, animated: false)
        picker.delegate?.pickerView?(picker, didSelectRow: row(year), inComponent: 0)
        try await w.settle()
    }

    /// `fillingFromHealth` marks only the fill's own change of the wheel. A fill of the year the wheel already shows
    /// changes nothing and marks nothing, so the user's next turn still clears "From Apple Health".
    @Test("The fill's own wheel change keeps From Apple Health; the user's next turn clears it, also after a same-year fill")
    func theFillsChangeIsNotAChoice() async throws {
        let health = MockHealthStore()
        health.birthYearValue = 1990
        let state = MockBirthYearPrefill.state(health: health)
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        try await HostedWindow.run(width: 390, height: 1_400, AboutYouView(model: model).previewEnvironment(state)
            .environment(\.locale, Locale(identifier: "en_US"))) { w in
            try await w.wait("the button", timeout: Self.wait) { Self.node(w, "aboutYou.useHealth") != nil }
            try await w.settle()
            #expect(Self.node(w, "aboutYou.save")?.isEnabled == false)
            // The user turns the wheel to 1990 first; Apple Health then holds that same year.
            try await Self.turn(w, to: 1990)
            #expect(Self.node(w, "aboutYou.save")?.isEnabled == true, "a turn reaches the view's year")
            #expect(Self.node(w, "aboutYou.useHealth")?.activate() == true)
            try await w.wait("filled", timeout: Self.wait) { model.birthYearPrefill == .filled && Self.text(w, "From Apple Health") }
            try await w.settle()
            #expect(Self.text(w, "From Apple Health"), "the same year: the fill changed nothing, and kept its caption")

            // The user's next turn is a choice: the caption goes, even though the fill moved nothing.
            try await Self.turn(w, to: 1985)
            try await w.wait("the choice", timeout: Self.wait) { model.birthYearPrefill == .askedBefore }
            try await w.settle()
            #expect(!Self.text(w, "From Apple Health"))
            #expect(Self.node(w, "aboutYou.useHealth") != nil)

            // A fill that moves the wheel (1985 → 1990): its own change isn't the user's choice.
            #expect(Self.node(w, "aboutYou.useHealth")?.activate() == true)
            try await w.wait("filled again", timeout: Self.wait) { model.birthYearPrefill == .filled && Self.text(w, "From Apple Health") }
            try await w.settle()
            #expect(model.birthYearPrefill == .filled)
            #expect(Self.picker(w)?.selectedRow(inComponent: 0) == Self.row(1990))
        }
    }

    @Test("Demo data: About you without the button")
    func demo() async throws {
        try await screen(OnboardingStepPreview(step: .aboutYou).previewEnvironment()) { w in
            #expect(Self.node(w, "aboutYou.useHealth") == nil)
        } until: { Self.node($0, "aboutYou.save") != nil }
    }
}
