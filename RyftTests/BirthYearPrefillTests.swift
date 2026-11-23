import Foundation
import SwiftUI
import Testing
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
        let model: OnboardingCoordinator

        init(health: MockHealthStore = MockHealthStore(), signedInAs account: UUID = BirthYearPrefillTests.a) {
            self.health = health
            let client = MockAuthClient(session: .preview(id: account))
            self.client = client
            let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
            let auth = AuthService(client: client, settings: Settings(defaults: defaults), defaults: defaults,
                                   wipeLocalData: { _ in true },
                                   deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                                   postAppleAuthorization: { _ in })
            self.auth = auth
            let state = AppState(env: .test(api: api, health: health, auth: auth))
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
        let health = MockHealthStore()
        health.asked = [.about]
        #expect(Rig(health: health).model.birthYearPrefill == .askedBefore)
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
        #expect(rig.model.birthYearPrefill != .filled)
        #expect(rig.model.birthYearPrefill != .asking)
        #expect(rig.api.mePatches.isEmpty)
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

    @Test("Demo data: About you without the button")
    func demo() async throws {
        try await screen(OnboardingStepPreview(step: .aboutYou).previewEnvironment()) { w in
            #expect(Self.node(w, "aboutYou.useHealth") == nil)
        } until: { Self.node($0, "aboutYou.save") != nil }
    }
}
