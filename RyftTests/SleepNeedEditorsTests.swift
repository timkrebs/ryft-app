import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

// C3 (PR 6 C §4.11–§4.12): the body-setting editors, Sleep's need sheet and its card in Nocturne. The decisions are pure
// (`BodySettingContent`, `SleepNeedSheetContent`, `BodySettingsFailure`, `SleepNeedBreakdown`); the hosted suites prove what
// VoiceOver and the layout get, at the default size and at AX3. Every state is honest offline: nothing reads as saved that
// wasn't, and nothing shows the default as if it were the user's.

@MainActor
private func makeState(api: MockPlatformAPI = C3Platform.api().0, online: Bool = true, user: User? = MockSleepNeedStates.user,
                       auth: AuthService? = nil) -> AppState {
    let state = AppState(env: .test(api: api, auth: auth, online: online))
    if let user { state.user = user }
    return state
}

/// The mock platform with the account as the drafts show it (`MockSleepNeedStates.user`): asked again (`GET /v1/me`) after a
/// save that may not have gone through, it answers with that account as it holds it. `onPatch` runs inside each
/// `PATCH /v1/me` after the platform applied it (unless `applies` is off): it holds the answer, or throws one that never
/// came (the change saved, the phone doesn't know).
final class C3Platform: RyftDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var held: User
    var onPatch: (@Sendable () async throws -> Void)?
    var applies = true

    init(user: User = MockSleepNeedStates.user) { held = user }

    var user: User { lock.withLock { held } }

    static func api(user: User = MockSleepNeedStates.user) -> (MockPlatformAPI, C3Platform) {
        let platform = C3Platform(user: user)
        return (MockPlatformAPI(screens: platform), platform)
    }

    func me() async throws -> User { user }
    func patchMe(_ p: UserPatch) async throws -> User {
        let patched = try await MockDataSource.shared.patchMe(p, on: user)
        if applies { lock.withLock { held = patched } }
        try await onPatch?()
        return patched
    }
    func days(from: Date, to: Date) async throws -> [DailyScore] { try await MockDataSource.shared.days(from: from, to: to) }
    func day(_ date: Date) async throws -> DayDetail { try await MockDataSource.shared.day(date) }
    func sleep(range: SleepRangeKind) async throws -> SleepRange { try await MockDataSource.shared.sleep(range: range) }
    func workouts(from: Date, to: Date) async throws -> [Workout] { try await MockDataSource.shared.workouts(from: from, to: to) }
    func workout(id: UUID) async throws -> WorkoutDetail { try await MockDataSource.shared.workout(id: id) }
    func trends(metric: TrendMetric, range: TrendRange) async throws -> TrendSeries {
        try await MockDataSource.shared.trends(metric: metric, range: range)
    }
    func insights() async throws -> [Insight] { try await MockDataSource.shared.insights() }
    func recompute(from: Date, to: Date) async throws { try await MockDataSource.shared.recompute(from: from, to: to) }
    func deleteMe() async throws -> AccountDeleted { try await MockDataSource.shared.deleteMe() }
}

extension MockSleepNeedStates {
    /// `user` with other body settings (`User.maxHr` and `sleepBaseMin` are constants).
    static func user(maxHr: Int = 190, maxHrSource: MaxHRSource = .estimated, sleepBaseMin: Int = 450,
                     sleepBaseSource: SleepBaseSource = .manual, birthYear: Int? = 1990) -> User {
        let base = user
        return User(id: base.id, name: base.name, email: base.email, provider: base.provider, tz: base.tz, maxHr: maxHr,
                    sleepBaseMin: sleepBaseMin, sleepBaseSource: sleepBaseSource, sleepBaseLearnedMin: base.sleepBaseLearnedMin,
                    sleepBaseLearnedAt: base.sleepBaseLearnedAt, notifications: base.notifications, consent: base.consent,
                    birthYear: birthYear, maxHrSource: maxHrSource, sources: base.sources)
    }
}

private let noAnswerWords = "RYFT didn't answer, so this may not have saved. Try again in a moment."
private let offlineWords = "You're offline, so this wasn't saved. Try again when you're back online."
private let serverErrorWords = "RYFT had a problem saving this, so it's back as it was. Try again in a moment."
private let savedWords = "Saved. Past days keep their scores until you rescore them."

// MARK: - the stepper and the ruler

@MainActor
struct BodySettingStepperTests {
    @Test("Baseline: 4–12 h in 15 minutes; heart rate: 100–230 one at a time; both clamp at their ends")
    func limits() {
        #expect(BodySetting.sleepBase.range == 240...720 && BodySetting.sleepBase.step == 15)
        #expect(BodySetting.maxHR.range == 100...230 && BodySetting.maxHR.step == 1)
        var minutes = 240
        let low = RyftStepperValue(Binding(get: { minutes }, set: { minutes = $0 }), in: BodySetting.sleepBase.range, step: 15,
                                   format: BodySetting.sleepBase.numeral, spoken: BodySetting.sleepBase.spoken)
        #expect(!low.canDecrement && low.canIncrement)
        #expect(low.accessibilityValue == "4 hours, minimum")
        low.step(-1)
        #expect(minutes == 240)
        low.step(1)
        #expect(minutes == 255)
        var bpm = 230
        let high = RyftStepperValue(Binding(get: { bpm }, set: { bpm = $0 }), in: BodySetting.maxHR.range,
                                    format: BodySetting.maxHR.numeral, spoken: BodySetting.maxHR.spoken)
        #expect(high.canDecrement && !high.canIncrement)
        #expect(high.accessibilityValue == "230 beats per minute, maximum")
        high.step(1)
        #expect(bpm == 230)
    }

    @Test("One tick per step (33, 27); from the default 7:40 and a learned 7:52 every value reached lands on a tick",
          arguments: [BodySettingsEditor.defaultSleepBase, 472])
    func ticks(_ start: Int) {
        #expect(BodySetting.sleepBase.tickCount == 33 && BodySetting.maxHR.tickCount == 27)
        let range = 240.0...720.0
        for direction in [1, -1] {
            var minutes = start
            for _ in 0..<40 {
                minutes = BodySetting.sleepBase.stepped(minutes, direction: direction)
                let position = (RulerScale.needleFraction(value: Double(minutes), range: range) ?? -1) * 32
                #expect(abs(position - position.rounded()) < 1e-9, "\(minutes) min (from \(start)) sits between ticks")
            }
            #expect(minutes == (direction > 0 ? 720 : 240), "it reaches the end")
        }
        #expect(BodySetting.sleepBase.rulerLabels == ["4 h", "8 h", "12 h"])
        #expect(BodySetting.maxHR.rulerLabels == ["100 bpm", "165", "230 bpm"])
    }

    @Test("Off the grid, the first step goes to the grid line its way: 7:40 → 7:45 up, 7:30 down; 7:52 → 8:00, 7:45")
    func stepsSnapToTheGrid() {
        let base = BodySetting.sleepBase
        #expect(base.stepped(460, direction: 1) == 465 && base.stepped(460, direction: -1) == 450)
        #expect(base.stepped(472, direction: 1) == 480 && base.stepped(472, direction: -1) == 465)
        #expect(base.stepped(450, direction: 1) == 465 && base.stepped(450, direction: -1) == 435, "on the grid: a step")
        #expect(base.stepped(240, direction: -1) == 240 && base.stepped(720, direction: 1) == 720, "the ends hold")
        #expect(base.stepped(715, direction: 1) == 720 && base.stepped(245, direction: -1) == 240)
        #expect(BodySetting.maxHR.stepped(190, direction: 1) == 191 && BodySetting.maxHR.stepped(190, direction: -1) == 189)
    }

    @Test("VoiceOver hears the unit: 8 hours 15 minutes, 185 beats per minute")
    func spokenUnits() {
        #expect(BodySetting.sleepBase.spoken(495) == "8 hours 15 minutes")
        #expect(BodySetting.sleepBase.numeral(495) == "8:15")
        #expect(BodySetting.maxHR.spoken(185) == "185 beats per minute")
        #expect(BodySetting.maxHR.text(185) == "185 bpm")
    }
}

// MARK: - what an editor shows

@MainActor
struct BodySettingContentTests {
    @Test("Unchanged: Save is off; changed: Save is on and the source line names the saved value")
    func changedAndUnchanged() {
        let editor = BodySettingsEditor(state: makeState())
        let unchanged = BodySettingContent(.sleepBase, editor: editor, draft: 450)
        #expect(!unchanged.isChanged && !unchanged.canSave)
        #expect(unchanged.source == "Set by you")
        let changed = BodySettingContent(.sleepBase, editor: editor, draft: 465)
        #expect(changed.isChanged && changed.canSave)
        #expect(changed.numeral == "7:45" && changed.spoken == "7 hours 45 minutes")
        #expect(changed.source == "Set by you · saved 7:30")
        let hr = BodySettingContent(.maxHR, editor: editor, draft: 185)
        #expect(hr.source == "Estimated from your age (born 1990) · saved 190 bpm" && hr.canSave)
    }

    @Test("VoiceOver reads the saved value in words, not as a time of day")
    func spokenSource() {
        let editor = BodySettingsEditor(state: makeState())
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: 450).spokenSource == "Set by you")
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: 465).spokenSource == "Set by you, saved 7 hours 30 minutes")
        #expect(BodySettingContent(.maxHR, editor: editor, draft: 185).spokenSource
                == "Estimated from your age (born 1990), saved 190 beats per minute")
    }

    @Test("While a save is out, Save is off (it shows Saving… itself); the value on its way is the page's, every row says Saving…")
    func whileSaving() async {
        let (api, _) = C3Platform.api()
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        let save = Task { await editor.setSleepBase(465) }
        #expect(await eventually { editor.saving })
        #expect(!BodySettingContent(.sleepBase, editor: editor, draft: 480).canSave)
        #expect(editor.pending(.sleepBase) == 465 && editor.pending(.maxHR) == nil)
        #expect(editor.sleepBase == 450 && editor.sleepBaseSourceText == "Set by you · learned 7h 52m", "the saved value")
        #expect(editor.rowValue(.sleepBase, saved: editor.sleepBaseText) == "Saving…" && editor.rowDetail(.sleepBase) == nil)
        #expect(editor.rowValue(.maxHR, saved: editor.maxHRText) == "190 bpm", "only the setting on its way")
        #expect(SleepNeedSheetContent.BaselineRow(editor: editor).value == "Saving…")
        await gate.open()
        #expect(await save.value)
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: 480).canSave)
        #expect(editor.rowValue(.sleepBase, saved: editor.sleepBaseText) == "7h 45m")
    }

    @Test("Set by hand, the row goes back to RYFT's estimate with the learned value; without one, to the default")
    func theEstimateRow() {
        let state = makeState()
        let editor = BodySettingsEditor(state: state)
        let estimate = BodySettingContent(.sleepBase, editor: editor, draft: 450).estimate
        #expect(estimate == BodySettingContent.Estimate(title: "Use RYFT's estimate", value: "7:52", spokenValue: "7 hours 52 minutes"))
        var user = MockSleepNeedStates.user
        user.sleepBaseLearnedMin = nil
        state.user = user
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: 450).estimate
                == BodySettingContent.Estimate(title: "Use the default", value: nil, spokenValue: nil))
        user.sleepBaseSource = .learned
        state.user = user
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: 450).estimate == nil, "learned already")
        // Max HR: the estimate's value isn't sent, so the row has none; without a birth year it goes back to the default.
        var manual = MockSleepNeedStates.user
        manual.maxHrSource = .manual
        state.user = manual
        #expect(BodySettingContent(.maxHR, editor: editor, draft: 190).estimate
                == BodySettingContent.Estimate(title: "Use the estimate", value: nil, spokenValue: nil))
        manual.birthYear = nil
        state.user = manual
        #expect(BodySettingContent(.maxHR, editor: editor, draft: 190).estimate
                == BodySettingContent.Estimate(title: "Use the default", value: nil, spokenValue: nil))
    }

    @Test("The \"Use …\" row dims when it can't be used, never while its own write runs")
    func theEstimateRowDoesntDimWhileBusy() {
        #expect(BodySettingsLayout.estimateOpacity(enabled: true, busy: false) == 1)
        #expect(BodySettingsLayout.estimateOpacity(enabled: false, busy: true) == 1, "busy: at full strength, as the pill")
        #expect(BodySettingsLayout.estimateOpacity(enabled: false, busy: false) == GroupedListSpec.disabledOpacity)
    }

    @Test("No account here: the numeral unlit (as the need sheet's Not loaded yet), no source, Save off; each says why")
    func noAccount() {
        let online = BodySettingContent(.sleepBase, editor: BodySettingsEditor(state: makeState(user: nil)), draft: 475)
        #expect(online.numeral == nil && online.spoken == "Not loaded yet" && online.source == nil && !online.canSave)
        #expect(online.unloaded == .loading
                && online.unloaded?.message == "RYFT hasn't loaded your settings yet, so this shows the default.")
        let offline = BodySettingContent(.sleepBase, editor: BodySettingsEditor(state: makeState(online: false, user: nil)),
                                         draft: BodySettingsEditor.defaultSleepBase)
        #expect(offline.numeral == nil && offline.source == nil && !offline.canSave && offline.unloaded == .offline)
        #expect(offline.unloaded?.message.hasPrefix("You're offline and RYFT hasn't loaded your settings yet") == true)
        let loaded = BodySettingContent(.sleepBase, editor: BodySettingsEditor(state: makeState()), draft: 450)
        #expect(loaded.numeral == "7:30" && loaded.unloaded == nil)
        // Demo data needs no network: never "offline" (`SleepViewModel.isOnline`).
        #expect(BodySettingsEditor(state: AppState(env: .preview(online: false))).isOnline)
    }
}

// MARK: - failures in words

@MainActor
struct BodySettingsFailureTests {
    @Test("Offline only when nothing left the phone", arguments: [
        APIError.transport(URLError(.notConnectedToInternet)), APIError.transport(URLError(.dataNotAllowed)),
        APIError.transport(URLError(.internationalRoamingOff)),
    ])
    func offline(_ error: APIError) {
        #expect(SettingsWriteFailure(error) == .offline)
        #expect(SettingsWriteFailure(URLError(.notConnectedToInternet)) == .offline, "unwrapped too")
        #expect(BodySettingsFailure(save: error).message == offlineWords)
        #expect(BodySettingsFailure(rescore: error).message
                == "You're offline, so nothing was rescored. Try again when you're back online.")
    }

    /// The review's case (C3, item 2): a timeout that arrives while the iPhone is offline was sent, and may have saved.
    @Test("Sent, no answer: it may have saved, whatever the network says when the failure arrives", arguments: [
        APIError.transport(URLError(.timedOut)), APIError.transport(URLError(.networkConnectionLost)),
        APIError.transport(URLError(.cannotFindHost)), APIError.http(408, ""),
    ])
    func noAnswer(_ error: APIError) {
        #expect(SettingsWriteFailure(error) == .noAnswer && SettingsWriteFailure(error).rereads)
        #expect(BodySettingsFailure(save: error).message == noAnswerWords)
        #expect(BodySettingsFailure(rescore: error).message
                == "RYFT didn't answer, so the rescore may not have started. Try again in a moment.")
        #expect(SettingsWriteFailure(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x"))) == .noAnswer,
                "an answer it couldn't read: it may have saved")
    }

    @Test("A server error (5xx) has its own words, and RYFT is asked again", arguments: [
        APIError.http(500, "", requestID: "rid-500"), APIError.http(503, "", requestID: "rid-503"),
    ])
    func aServerError(_ error: APIError) {
        #expect(SettingsWriteFailure(error) == .serverError && SettingsWriteFailure(error).rereads)
        let failure = BodySettingsFailure(save: error)
        #expect(failure.message == serverErrorWords && failure.details?.contains("Request ID rid-5") == true)
        #expect(BodySettingsFailure(rescore: error).message
                == "RYFT couldn't rescore your days, so past days keep their scores. Try again in a moment.")
    }

    @Test("Refused (429, 409, 403, 501): it's back as it was; the request ID goes along, never the raw error text",
          arguments: [APIError.http(429, "", requestID: "rid-429"), APIError.http(409, "conflict", requestID: "rid-409"),
                      APIError.http(403, "forbidden", requestID: "rid-403"), APIError.http(501, "", requestID: "rid-501")])
    func refused(_ error: APIError) {
        let failure = BodySettingsFailure(save: error)
        #expect(SettingsWriteFailure(error) == .refused && !SettingsWriteFailure(error).rereads)
        #expect(failure.message == "RYFT couldn't save this change, so it's back as it was.")
        #expect(failure.details?.contains("Request ID rid-") == true)
        #expect(failure.message != error.localizedDescription)
        #expect(BodySettingsFailure(rescore: error).message
                == "RYFT couldn't rescore your days, so past days keep their scores. Try again in a moment.")
    }

    /// The blocker (C3 review, item 1): offline with an account, a save used to wait up to 300 s for the network.
    @Test("Offline with an account: a save says so at once and sends nothing (a PATCH that would never answer)",
          .timeLimit(.minutes(1)))
    func anOfflineSaveSendsNothing() async {
        let (api, _) = C3Platform.api()
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        let state = makeState(api: api, online: false)
        let editor = BodySettingsEditor(state: state)
        #expect(!(await editor.setSleepBase(465)))
        #expect(editor.error == offlineWords && editor.errorDetails == nil)
        #expect(api.mePatches.isEmpty && !editor.saving)
        #expect(editor.sleepBase == 450 && !editor.savedChange)
        let learned = await editor.useLearnedSleepBase(), maxHR = await editor.setMaxHR(185)
        #expect(!learned && !maxHR && api.mePatches.isEmpty)
        #expect(!(await editor.setBirthYear(1991)) && editor.birthYearError == offlineWords && api.mePatches.isEmpty)
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: editor.sleepBase).source == "Set by you")
        await gate.open()
    }

    @Test("Offline with an account: the rescore says so at once and sends nothing", .timeLimit(.minutes(1)))
    func anOfflineRescoreSendsNothing() async {
        let (api, _) = C3Platform.api()
        let editor = BodySettingsEditor(state: makeState(api: api, online: false))
        await editor.rescore()
        #expect(api.count("recompute") == 0 && !editor.rescoring)
        #expect(editor.rescoreFailed && editor.rescoreDetails == nil)
        #expect(editor.rescoreStatus == "You're offline, so nothing was rescored. Try again when you're back online.")
        #expect(RescoreStatus.look(editor) == .failure(editor.rescoreStatus ?? "", details: nil), "Profile's footer: the error glyph")
    }

    @Test("A timeout that arrives after the network went is no answer, not offline; offline, RYFT isn't asked again")
    func aTimeoutWhileOfflineIsNoAnswer() async {
        let (api, platform) = C3Platform.api()
        let state = makeState(api: api)
        let monitor = state.env.connectivityMonitor
        platform.applies = false
        platform.onPatch = {
            await MainActor.run { monitor.update(false) }
            throw APIError.transport(URLError(.timedOut))
        }
        let editor = BodySettingsEditor(state: state)
        let reads = api.count("me")
        #expect(!(await editor.setSleepBase(465)))
        #expect(editor.error == noAnswerWords, "sent while online: it may have saved")
        #expect(api.count("me") == reads, "offline the question would wait for the network")
    }

    @Test("A failed rescore is marked failed, in words, and keeps the request ID; Profile's footer shows the error glyph")
    func aFailedRescore() async {
        let (api, _) = C3Platform.api()
        let editor = BodySettingsEditor(state: makeState(api: api))
        api.failure = APIError.http(500, "", requestID: "rid-rescore")
        await editor.rescore()
        #expect(editor.rescoreFailed)
        #expect(editor.rescoreStatus == "RYFT couldn't rescore your days, so past days keep their scores. Try again in a moment.")
        #expect(editor.rescoreDetails?.contains("rid-rescore") == true)
        #expect(RescoreStatus.look(editor) == .failure(editor.rescoreStatus ?? "", details: editor.rescoreDetails))
        api.failure = nil
        editor.begin()
        #expect(!editor.rescoreFailed && editor.rescoreStatus == nil && RescoreStatus.look(editor) == nil)
    }
}

// MARK: - asking RYFT again, the account, the rescore's last word

@MainActor
struct BodySettingsHonestyTests {
    @Test("No answer, but RYFT took it: asked again, the account holds it, and it's Saved.")
    func noAnswerButSaved() async {
        let (api, platform) = C3Platform.api()
        platform.onPatch = { throw APIError.transport(URLError(.timedOut)) }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        #expect(await editor.setSleepBase(465))
        #expect(editor.error == nil && editor.savedChange)
        #expect(editor.sleepBase == 465 && state.user?.sleepBaseSource == .manual)
        #expect(api.count("me") >= 1)
    }

    @Test("No answer, and RYFT didn't take it: asked again, the words stay, the value is RYFT's")
    func noAnswerNotSaved() async {
        let (api, platform) = C3Platform.api()
        platform.applies = false
        platform.onPatch = { throw APIError.transport(URLError(.networkConnectionLost)) }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        #expect(!(await editor.setSleepBase(465)))
        #expect(editor.error == noAnswerWords && !editor.savedChange && editor.sleepBase == 450)
        #expect(api.count("me") >= 1)
    }

    @Test("A 5xx: its own words, and RYFT is asked again; holding the change after all, it's Saved.")
    func aServerErrorRereads() async {
        let (api, platform) = C3Platform.api()
        platform.applies = false
        api.failNext = APIError.http(500, "", requestID: "rid-500")
        let editor = BodySettingsEditor(state: makeState(api: api))
        #expect(!(await editor.setSleepBase(465)))
        #expect(editor.error == serverErrorWords && editor.errorDetails?.contains("rid-500") == true)
        #expect(api.count("me") >= 1, "asked again")
        platform.applies = true
        platform.onPatch = { throw APIError.http(503, "") }
        #expect(await editor.setMaxHR(185))
        #expect(editor.error == nil && editor.savedChange && editor.maxHR == 185)
    }

    @Test("An answer the store dropped (another change of the user came first) is never Saved. on its word: RYFT is asked")
    func aDroppedAnswerRereads() async {
        let (api, _) = C3Platform.api()
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        // RYFT can't be asked: nothing confirms the change.
        api.faults["me"] = FaultInjection.Rule(.notFound)
        let save = Task { await editor.setSleepBase(465) }
        #expect(await eventually { editor.saving })
        // Another change of the user is stored while the PATCH is out (the withdrawal does this).
        await state.repository.store(user: MockSleepNeedStates.user, asOf: state.repository.userChange()).committed()
        await gate.open()
        #expect(!(await save.value))
        #expect(!editor.savedChange && editor.error == nil && !editor.saving, "not Saved. on the dropped answer's word")
        // Asked, and RYFT holds it: Saved.
        api.faults["me"] = nil
        let gate2 = Gate()
        api.beforePatchMe = { await gate2.wait() }
        let again = Task { await editor.setSleepBase(480) }
        #expect(await eventually { editor.saving })
        await state.repository.store(user: MockSleepNeedStates.user, asOf: state.repository.userChange()).committed()
        await gate2.open()
        #expect(await again.value)
        #expect(editor.savedChange && editor.sleepBase == 480)
    }

    @Test("A sign-out and another account while a save is out: B sees nothing of A's, and A's late answer changes nothing",
          .timeLimit(.minutes(1)))
    func anAccountChangeForgetsTheEditor() async throws {
        let client = MockAuthClient(session: .preview())
        let auth = AuthService(client: client, defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard,
                               wipeLocalData: { _ in true },
                               deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                               postAppleAuthorization: { _ in })
        let (api, _) = C3Platform.api()
        let state = makeState(api: api, auth: auth)
        state.bindAccountHooks(auth, apiStatus: APIStatus())
        let editor = BodySettingsEditor(state: state)
        // A's words: a birth year that wasn't taken, a rescore, then a save whose answer is held.
        api.failNext = APIError.http(409, "")
        #expect(!(await editor.setBirthYear(1991)) && editor.birthYearError != nil)
        api.failure = APIError.http(403, "")
        await editor.rescore()
        api.failure = nil
        #expect(editor.rescoreStatus != nil)
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        let save = Task { await editor.setSleepBase(465) }
        #expect(await eventually { editor.saving && editor.pendingSleepBase == 465 })

        await auth.signOut()
        for _ in 0..<20 { await Task.yield() }
        client.emit(.signedIn, .preview(id: UUID()))
        #expect(await eventually { auth.isSignedIn })
        state.user = MockSleepNeedStates.user

        func nothingOfA() {
            #expect(editor.pendingSleepBase == nil && !editor.saving && !editor.savedChange)
            #expect(editor.rescoreStatus == nil && !editor.rescoreFailed && editor.birthYearError == nil && editor.error == nil)
            #expect(SleepNeedSheetContent.BaselineRow(editor: editor).value == "7:30")
        }
        nothingOfA()
        await gate.open()
        _ = await save.value
        nothingOfA()
    }

    @Test("The rescore's last word: after the 202 it stays \"Rescoring — …\" unless the reload ran and answered")
    func theRescoreSaysOnlyWhatItSaw() async {
        let (api, _) = C3Platform.api()
        let clock = TestClock()
        let state = AppState(env: .test(api: api, clock: clock))
        state.user = MockSleepNeedStates.user
        let editor = BodySettingsEditor(state: state)
        // Offline before the reload: it never ran, so nothing says rescored.
        let run = Task { await editor.rescore() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(editor.rescoreStatus == "Rescoring — scores update in a few seconds." && api.count("recompute") == 1)
        state.env.connectivityMonitor.update(false)
        clock.advance(by: SyncService.rescoreDelay)
        await run.value
        #expect(!editor.rescoring && !editor.rescored && !editor.rescoreFailed)
        #expect(editor.rescoreStatus == "Rescoring — scores update in a few seconds.", "never \"rescored\" offline")
        // Online, the reload answered: rescored, and the row waits for the next change.
        state.env.connectivityMonitor.update(true)
        await editor.setSleepBase(465)
        let again = Task { await editor.rescore() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: SyncService.rescoreDelay)
        await again.value
        #expect(editor.rescored && editor.rescoreStatus == "The last 90 days are rescored with your settings.")
        #expect(RescoreStatus.look(editor) == .note("The last 90 days are rescored with your settings."))
        await editor.setSleepBase(480)
        #expect(!editor.rescored, "a new change: the row is back")
    }
}

// MARK: - Notifications: the same classifier

@MainActor
struct NotificationFailuresTests {
    @Test("Notifications judge a failure by what left the phone, as the editors do", arguments: [
        (APIError.transport(URLError(.notConnectedToInternet)), SettingsWriteFailure.offline),
        (APIError.transport(URLError(.timedOut)), .noAnswer), (APIError.transport(URLError(.networkConnectionLost)), .noAnswer),
        (APIError.http(500, ""), .serverError), (APIError.http(429, ""), .refused),
    ])
    func classified(_ error: APIError, _ kind: SettingsWriteFailure) {
        let failure = NotificationSettingsFailure(error)
        #expect(failure.kind == kind && failure.message == kind.saveMessage)
    }

    private func model(online: Bool = true) -> (NotificationSettingsViewModel, MockPlatformAPI) {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, flags: [.pushEnabled: true], online: online)
        let state = AppState(env: env)
        state.user = MockData.user
        return (NotificationSettingsViewModel(state: state, push: PushRegistrar(env: env)), api)
    }

    @Test("Offline, a switch says so at once and sends nothing", .timeLimit(.minutes(1)))
    func offlineSendsNothing() async {
        let (model, api) = model(online: false)
        let hold = RequestHold()
        api.beforePatchNotifications = { await hold.wait() }
        await model.set(.pr, on: false)
        #expect(model.failure?.message == offlineWords && model.failure?.kind == .offline)
        #expect(api.count("patchNotifications") == 0 && model.isOn(.pr) && !model.saving)
        hold.release()
    }

    @Test("A 5xx has its own words, and RYFT is asked again")
    func aServerErrorRereads() async {
        let (model, api) = model()
        api.failNext = APIError.http(503, "", requestID: "rid-503")
        let reads = api.count("me")
        await model.set(.pr, on: false)
        #expect(model.failure?.message == serverErrorWords && model.failure?.details?.contains("rid-503") == true)
        #expect(model.isOn(.pr) && api.count("me") > reads)
    }
}

// MARK: - the need, its sheet and its card

struct SleepNeedContentTests {
    @Test("The terms as clocks, in words for VoiceOver; the nap is a real minus")
    func terms() {
        let b = SleepNeedBreakdown(MockSleepNeedStates.needWithNap)
        #expect(b.terms.map(\.title) == ["Baseline", "Strain", "Sleep debt", "Nap credit"])
        #expect(b.terms.map(\.signed) == ["7:30", "+0:20", "+0:28", "−0:25"])
        #expect(b.terms.map(\.spoken) == ["Baseline, 7 hours 30 minutes", "Strain, plus 20 minutes",
                                          "Sleep debt, plus 28 minutes", "Nap credit, minus 25 minutes"])
    }

    @Test("One scale for every row: the total, or with a nap credit what the night added up to before it")
    func scale() {
        #expect(SleepNeedBreakdown(MockSleepNeedStates.need).scaleMax == 498)
        #expect(SleepNeedBreakdown(MockSleepNeedStates.needWithNap).scaleMax == 498, "7:53 after the nap, 8:18 before it")
    }

    @Test("A night scored before the breakdown (its score's nap_min is null, API.md) has none: the notice, not the tile")
    func scoredBeforeTheBreakdown() throws {
        var sleep = try #require(MockData.todayDetail.sleep)
        sleep.need = SleepNeed(base: 498, strain: 0, debt: 0, napCredit: 0, total: 498)
        var score = MockData.todayScore
        score.napMin = nil
        #expect(sleep.needBreakdown(score: score) == nil)
        #expect(SleepNightSummary(sleep: sleep, score: score).needBreakdown == nil, "the details card keeps its need row")
        score.napMin = 0
        #expect(sleep.needBreakdown(score: score) == sleep.need, "scored with the breakdown: no nap is 0")
        #expect(sleep.needBreakdown(score: nil) == sleep.need, "no score to tell: as it is")
        sleep.need = nil
        #expect(sleep.needBreakdown(score: score) == nil)
    }

    @Test("The sentence in clocks; VoiceOver's in words")
    func sentence() {
        let b = SleepNeedBreakdown(MockSleepNeedStates.need)
        #expect(b.sentence == "You needed 8:18: 7:30 baseline, +0:20 for yesterday's strain, +0:28 of debt.")
        #expect(b.spokenSentence
                == "You needed 8 hours 18 minutes: 7 hours 30 minutes baseline, +20 minutes for yesterday's strain, +28 minutes of debt.")
    }

    @Test("The sheet's numeral: the breakdown's total, or the night's need without one, or unlit")
    func numeral() {
        let full = SleepNeedSheetContent(need: MockSleepNeedStates.need, needMinutes: nil)
        #expect(full.numeral == "8:18" && full.spokenNumeral == "Sleep need, 8 hours 18 minutes" && full.breakdown != nil)
        let older = SleepNeedSheetContent(need: nil, needMinutes: 490)
        #expect(older.numeral == "8:10" && older.breakdown == nil)
        let none = SleepNeedSheetContent(need: nil, needMinutes: nil)
        #expect(none.numeral == nil && none.spokenNumeral == "Sleep need, no value yet")
    }

    @Test("The baseline row reads the cached account; without one it says so instead of the default")
    @MainActor
    func baselineRow() {
        let loaded = SleepNeedSheetContent.BaselineRow(editor: BodySettingsEditor(state: makeState()))
        #expect(loaded.value == "7:30" && loaded.spokenValue == "7 hours 30 minutes" && loaded.detail == "Set by you")
        let missing = SleepNeedSheetContent.BaselineRow(editor: BodySettingsEditor(state: makeState(online: false, user: nil)))
        #expect(missing.value == "Not loaded yet" && missing.detail == nil)
    }
}

// MARK: - colour (L27)

struct SleepNeedColourTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Ryft")

    @Test("No teal, accent or recovery in the editors, the need sheet, its card and the tile; no Volt of their own",
          arguments: ["Features/Profile/BodySettingsForms.swift", "Features/Sleep/SleepNeedSheet.swift",
                      "Design/SleepNeedBar.swift", "Preview/MockSleepNeedStates.swift"])
    func noTealNoVolt(_ path: String) throws {
        let text = try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
        let teal = try Regex(#"Theme\.(teal|accent\w*|onAccent|recovery)|Color\("(Accent|Teal|Recovery)"#)
        #expect(!text.contains(teal), "\(path) names teal or the accent")
        // Volt is the ruler's needle (`RulerScale`), never a page's own colour.
        #expect(!text.contains("Theme.signal"), "\(path) uses Volt")
    }

    @Test("The tile is the sleep colour")
    func theTileIsSleep() throws {
        let text = try String(contentsOf: Self.root.appendingPathComponent("Design/SleepNeedBar.swift"), encoding: .utf8)
        #expect(text.contains("GlowTile(Theme.metricSleep"))
    }
}

// MARK: - hosted: the editors

@MainActor
@Suite("C3: the editors, hosted", .serialized)
struct BodySettingsEditorHostedTests {
    static let width: CGFloat = 390, height: CGFloat = 844

    private func host(_ setting: BodySetting = .sleepBase, state: AppState? = nil, editor: BodySettingsEditor? = nil,
                      rescores: Bool = true, ax3: Bool = false,
                      body: (HostedWindow, BodySettingsEditor) async throws -> Void) async throws {
        let state = state ?? makeState()
        let editor = editor ?? BodySettingsEditor(state: state)
        let page = setting == .sleepBase ? AnyView(BaselineSleepNeedForm(editor: editor, showsClose: true, rescores: rescores))
            : AnyView(MaxHeartRateForm(editor: editor, showsClose: true, rescores: rescores))
        try await HostedWindow.run(width: Self.width, height: Self.height, bottomInset: 34,
                                   typeSize: ax3 ? .accessibility3 : .large, category: ax3 ? .accessibilityExtraLarge : .large,
                                   page.previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US"))) { w in
            try await w.wait("the stepper") { w.nodes().contains { $0.isAdjustable } }
            try await w.settle()
            try await body(w, editor)
        }
    }

    private func stepper(_ w: HostedWindow) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.isAdjustable }, "the stepper")
    }

    private func save(_ w: HostedWindow, _ setting: BodySetting = .sleepBase) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == setting.saveIdentifier }, "Save")
    }

    private func node(_ w: HostedWindow, _ identifier: String) -> HostedWindow.Node? {
        w.nodes().first { $0.identifier == identifier }
    }

    @Test("The numeral and its circles are one adjustable element that speaks its unit", arguments: [BodySetting.sleepBase, .maxHR])
    func oneAdjustableElement(_ setting: BodySetting) async throws {
        try await host(setting) { w, _ in
            let element = try stepper(w)
            #expect(element.label == (setting == .sleepBase ? "Baseline sleep need" : "Maximum heart rate"))
            #expect(element.value == (setting == .sleepBase ? "7 hours 30 minutes" : "190 beats per minute"))
            // The circles take taps but VoiceOver doesn't stop on them; the ruler repeats the value and is hidden.
            #expect(!w.nodes().contains { $0.label == "Less" || $0.label == "More" })
            #expect(!w.nodes().contains { $0.identifier == "bodySettings.ruler" })
            element.increment()
            try await w.wait("a step up") { (try? stepper(w).value) == (setting == .sleepBase ? "7 hours 45 minutes" : "191 beats per minute") }
            try stepper(w).decrement()
            try stepper(w).decrement()
            try await w.wait("two down") { (try? stepper(w).value) == (setting == .sleepBase ? "7 hours 15 minutes" : "189 beats per minute") }
        }
    }

    @Test("From the default 7:40, a step lands on the grid (7:45 up), then goes a step at a time (7:30, 7:15 down)")
    func aStepFromOffTheGrid() async throws {
        let user = MockSleepNeedStates.user(sleepBaseMin: BodySettingsEditor.defaultSleepBase, sleepBaseSource: .default)
        let (api, _) = C3Platform.api(user: user)
        try await host(state: makeState(api: api, user: user)) { w, _ in
            #expect(try stepper(w).value == "7 hours 40 minutes")
            try stepper(w).increment()
            try await w.wait("7:45") { (try? stepper(w).value) == "7 hours 45 minutes" }
            try stepper(w).decrement()
            try await w.wait("7:30") { (try? stepper(w).value) == "7 hours 30 minutes" }
            try stepper(w).decrement()
            try await w.wait("7:15") { (try? stepper(w).value) == "7 hours 15 minutes" }
        }
    }

    @Test("Save is off while nothing changed, on once something did; the source names the saved value, VoiceOver in words")
    func saveFollowsTheChange() async throws {
        try await host { w, _ in
            #expect(try save(w).isEnabled == false)
            #expect(w.node("Set by you", exactly: true) != nil)
            try stepper(w).increment()
            try await w.wait("Save on") { (try? save(w).isEnabled) == true }
            #expect(node(w, "bodySettings.source")?.label == "Set by you, saved 7 hours 30 minutes", "not 7:30 as a time of day")
        }
        try await host(.maxHR) { w, _ in
            try stepper(w).increment()
            try await w.wait("Save on") { (try? save(w, .maxHR).isEnabled) == true }
            #expect(node(w, "bodySettings.source")?.label == "Estimated from your age (born 1990), saved 190 beats per minute")
        }
    }

    @Test("Saving: the pill says Saving… and is busy, the stepper and Close are off; Saved: the notice, the rescore row, Save off")
    func savingThenSaved() async throws {
        let (api, _) = C3Platform.api()
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        try await host(state: makeState(api: api)) { w, editor in
            try stepper(w).increment()
            try await w.wait("Save on") { (try? save(w).isEnabled) == true }
            try save(w).activate()
            try await w.wait("Saving…") { (try? save(w).label) == "Saving…" }
            #expect(try save(w).value == "In progress")
            #expect(try stepper(w).isEnabled == false)
            #expect(node(w, "subpage.close")?.isEnabled == false, "the page stays while its save is out")
            #expect(!w.nodes().contains { $0.label.hasPrefix("Saved.") }, "nothing reads as saved yet")
            await gate.open()
            try await w.wait("Saved") { w.node(savedWords) != nil }
            try await w.settle()
            let pill = try save(w), value = try stepper(w)
            #expect(pill.label == "Save" && !pill.isEnabled)
            #expect(value.value == "7 hours 45 minutes" && editor.sleepBase == 465)
            #expect(node(w, "subpage.close")?.isEnabled == true)
            #expect(w.nodes().contains { $0.identifier == "bodySettings.rescore" && $0.label == "Rescore the last 90 days" })
        }
    }

    @Test("Opened while a save is out: Saving…, the value on its way, Close off; then its answer on this page")
    func reopenedMidSave() async throws {
        let (api, _) = C3Platform.api()
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        let saving = Task { await editor.setSleepBase(480) }
        #expect(await eventually { editor.saving })
        try await host(state: state, editor: editor) { w, _ in
            let pill = try save(w), value = try stepper(w)
            #expect(pill.label == "Saving…" && pill.value == "In progress")
            #expect(value.value == "8 hours" && !value.isEnabled)
            #expect(node(w, "subpage.close")?.isEnabled == false)
            await gate.open()
            _ = await saving.value
            try await w.wait("Saved") { w.node(savedWords) != nil }
            try await w.settle()
            let after = try save(w), stepped = try stepper(w)
            #expect(after.label == "Save" && stepped.value == "8 hours" && stepped.isEnabled)
        }
    }

    @Test("A refusal, no answer, a server error or offline: the notice under the value, the value back, nothing saved", arguments: [
        ("refused", true), ("noAnswer", true), ("serverError", true), ("offline", false),
    ])
    func failures(_ kind: String, online: Bool) async throws {
        let (api, _) = C3Platform.api()
        switch kind {
        case "refused": api.failNext = APIError.http(422, "sleep_base_min out of range", requestID: "rid-422")
        case "noAnswer": api.failNext = APIError.transport(URLError(.timedOut))
        case "serverError": api.failNext = APIError.http(500, "", requestID: "rid-500")
        default: break
        }
        let message = switch kind {
        case "refused": "RYFT takes a baseline between 4 and 12 hours."
        case "noAnswer": noAnswerWords
        case "serverError": serverErrorWords
        default: offlineWords
        }
        try await host(state: makeState(api: api, online: online)) { w, editor in
            try stepper(w).increment()
            try await w.wait("Save on") { (try? save(w).isEnabled) == true }
            try save(w).activate()
            try await w.wait("the notice") { w.node(message, exactly: true) != nil }
            try await w.settle()
            let notice = try #require(w.node(message, exactly: true))
            let value = try stepper(w)
            let paragraph = try #require(w.node("Each night's sleep need starts from this baseline"))
            #expect(notice.frame.minY > value.frame.maxY && notice.frame.maxY < paragraph.frame.minY,
                    "under the value, above the paragraph: \(notice.frame) \(value.frame) \(paragraph.frame)")
            #expect(value.value == "7 hours 30 minutes" && editor.sleepBase == 450, "back to the saved value")
            #expect(!w.nodes().contains { $0.label.hasPrefix("Saved.") })
            #expect(try save(w).isEnabled == false)
            if kind == "refused" {
                #expect(w.nodes().contains { $0.label.contains("Request ID rid-422") || ($0.value ?? "").contains("rid-422") })
            }
            if kind == "offline" { #expect(api.mePatches.isEmpty, "nothing was sent") }
        }
    }

    @Test("A failed rescore says so under the rescore row, with the request ID; Saved stays above")
    func aFailedRescoreUnderItsRow() async throws {
        let (api, _) = C3Platform.api()
        try await host(state: makeState(api: api)) { w, editor in
            await editor.setSleepBase(465)
            try await w.wait("the rescore row") { w.nodes().contains { $0.identifier == "bodySettings.rescore" } }
            api.failure = APIError.http(500, "", requestID: "rid-rescore")
            try #require(w.nodes().first { $0.identifier == "bodySettings.rescore" }).activate()
            let message = "RYFT couldn't rescore your days, so past days keep their scores. Try again in a moment."
            try await w.wait("the rescore notice") { w.node(message) != nil }
            try await w.settle()
            let row = try #require(w.nodes().first { $0.identifier == "bodySettings.rescore" })
            let notice = try #require(w.node(message))
            let saved = try #require(w.node(savedWords))
            #expect(saved.frame.maxY <= row.frame.minY && notice.frame.minY >= row.frame.maxY, "\(saved.frame) \(row.frame) \(notice.frame)")
            #expect(w.nodes().contains { $0.label.contains("Request ID rid-rescore") || ($0.value ?? "").contains("rid-rescore") })
            #expect(row.isEnabled && row.label == "Rescore the last 90 days", "it can be tried again")
        }
    }

    @Test("Rescored and seen: the status says so, and the row waits for the next saved change")
    func rescoredRowWaits() async throws {
        let (api, _) = C3Platform.api()
        let clock = TestClock()
        let state = AppState(env: .test(api: api, clock: clock))
        state.user = MockSleepNeedStates.user
        try await host(state: state) { w, editor in
            await editor.setSleepBase(465)
            try await w.wait("the rescore row") { node(w, "bodySettings.rescore") != nil }
            try #require(node(w, "bodySettings.rescore")).activate()
            // Waited for outside `#expect`: a closure inside its expansion here trips the compiler (closure type mismatch).
            try await w.wait("the delay", timeout: .seconds(10)) { clock.pendingSleeps == 1 }
            clock.advance(by: SyncService.rescoreDelay)
            try await w.wait("rescored", timeout: .seconds(10)) { w.node("The last 90 days are rescored with your settings.") != nil }
            try await w.settle()
            #expect(node(w, "bodySettings.rescore")?.isEnabled == false, "nothing new to rescore")
            try stepper(w).increment()
            try await w.wait("Save on") { (try? save(w).isEnabled) == true }
            try save(w).activate()
            try await w.wait("Saved again") { w.node(savedWords) != nil }
            try await w.wait("the row is back") { node(w, "bodySettings.rescore")?.isEnabled == true }
        }
    }

    @Test("Both \"Use …\" rows go back to RYFT's value, and the numeral follows it", arguments: [BodySetting.sleepBase, .maxHR])
    func theUseRowsMoveTheDraft(_ setting: BodySetting) async throws {
        let user = MockSleepNeedStates.user(maxHr: 185, maxHrSource: .manual)
        let (api, _) = C3Platform.api(user: user)
        let age = Calendar.current.component(.year, from: .now) - 1990
        let estimate = Int((208 - 0.7 * Double(age)).rounded())
        try await host(setting, state: makeState(api: api, user: user)) { w, _ in
            let row = try #require(node(w, "bodySettings.useEstimate"))
            #expect(row.label == (setting == .sleepBase ? "Use RYFT's estimate" : "Use the estimate"))
            row.activate()
            let expected = setting == .sleepBase ? "7 hours 52 minutes" : "\(estimate) beats per minute"
            try await w.wait("the numeral follows") { (try? stepper(w).value) == expected }
            try await w.wait("Saved") { w.node(savedWords) != nil }
            #expect(node(w, "bodySettings.useEstimate") == nil, "RYFT's value now: nothing to go back to")
        }
    }

    @Test("Offline with no account on this iPhone: unlit, a notice that says so, the stepper and Save off")
    func offlineWithoutAccount() async throws {
        try await host(state: makeState(online: false, user: nil)) { w, _ in
            let value = try stepper(w)
            #expect(value.value == "Not loaded yet" && !value.isEnabled)
            #expect(w.nodes().contains { $0.label.hasPrefix("You're offline and RYFT hasn't loaded your settings yet") })
            #expect(try save(w).isEnabled == false)
        }
    }

    @Test("Online, the account not loaded yet: unlit, its own notice, the stepper and Save off")
    func notLoadedYetOnline() async throws {
        try await host(state: makeState(user: nil)) { w, _ in
            let value = try stepper(w)
            #expect(value.value == "Not loaded yet" && !value.isEnabled)
            #expect(w.node("RYFT hasn't loaded your settings yet, so this shows the default.", exactly: true) != nil)
            #expect(!w.nodes().contains { $0.label.hasPrefix("You're offline") })
            #expect(try save(w).isEnabled == false)
        }
    }

    @Test("In onboarding: Saved. on its own, no rescore row (no past days yet)")
    func onboardingHasNoRescore() async throws {
        try await host(rescores: false) { w, _ in
            try stepper(w).increment()
            try await w.wait("Save on") { (try? save(w).isEnabled) == true }
            try save(w).activate()
            try await w.wait("Saved") { w.node("Saved.", exactly: true) != nil }
            try await w.settle()
            #expect(node(w, "bodySettings.rescore") == nil && w.node(savedWords) == nil)
        }
    }

    @Test("AX3: nothing leaves the screen's width; the circles stay beside the numeral; Save stays reachable")
    func ax3() async throws {
        try await host(ax3: true) { w, _ in
            for node in w.nodes() {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= Self.width + 0.5 && node.frame.height > 0,
                        "\(node.label) \(node.frame)")
            }
            let value = try stepper(w)
            #expect(value.frame.height < 160, "one row, not stacked: \(value.frame)")
            let pill = try save(w)
            #expect(pill.frame.maxY <= Self.height - 34 + 0.5 && pill.frame.height >= 52)
        }
    }
}

// MARK: - hosted: where the editors open from

/// Opens the editor as Profile does (`bodySettingSheet`), or onboarding (`rescores: false`), at once.
private struct BodySettingSheetHost: View {
    let editor: BodySettingsEditor
    let rescores: Bool
    @State private var item: BodySetting? = .sleepBase

    var body: some View {
        Theme.background
            .ignoresSafeArea()
            .bodySettingSheet($item, editor: editor, rescores: rescores)
    }
}

@MainActor
private extension SheetNode {
    var isEnabled: Bool { !traits.contains(.notEnabled) }
    var value: String? { object.accessibilityValue }
    var frame: CGRect { object.accessibilityFrame }
}

@MainActor
private func sheetNode(_ w: HostedWindow, _ identifier: String) -> SheetNode? {
    sheetNodes(w).first { $0.identifier == identifier }
}

@MainActor
private func sheetStepper(_ w: HostedWindow) -> SheetNode? {
    sheetNodes(w).first { $0.traits.contains(.adjustable) }
}

@MainActor
@Suite("C3: the editors where they open, hosted", .serialized)
struct BodySettingsPlacementHostedTests {
    private func host(_ view: some View, state: AppState, body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 34,
                                   view.previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US"))) { w in
            try await body(w)
        }
    }

    @Test("As Profile's and onboarding's sheet: Close; off mid-save, no swipe away; onboarding offers no rescore",
          arguments: [true, false])
    func asASheet(rescores: Bool) async throws {
        let (api, _) = C3Platform.api()
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        try await host(BodySettingSheetHost(editor: editor, rescores: rescores), state: state) { w in
            try await w.wait("the sheet") { sheetStepper(w) != nil && sheetNode(w, "subpage.close") != nil }
            try await w.settle()
            #expect(sheetNode(w, "subpage.back") == nil)
            sheetStepper(w)?.object.accessibilityIncrement()
            try await w.wait("Save on") { sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.isEnabled == true }
            sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.activate()
            try await w.wait("Saving…") { sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.label == "Saving…" }
            #expect(sheetNode(w, "subpage.close")?.isEnabled == false)
            #expect(w.host.presentedViewController?.isModalInPresentation == true, "no swipe down mid-save")
            await gate.open()
            let saved = rescores ? savedWords : "Saved."
            try await w.wait("Saved") { sheetNodes(w).contains { $0.label == saved } }
            #expect(sheetNode(w, "subpage.close")?.isEnabled == true)
            #expect(w.host.presentedViewController?.isModalInPresentation == false)
            #expect((sheetNode(w, "bodySettings.rescore") != nil) == rescores)
        }
    }

    @Test("Pushed inside Sleep's need sheet: Back (no Close), the sheet's 26 pt inset, Back off while the save is out")
    func pushedInTheNeedSheet() async throws {
        let (api, _) = C3Platform.api()
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        let sheet = SheetHost {
            SleepNeedSheet(need: MockSleepNeedStates.need, total: "8h 18m", night: "Last night · Sun, Nov 15", editor: editor)
        }
        try await host(sheet, state: state) { w in
            try await w.wait("the need sheet") { sheetNode(w, "sleepNeed.changeBaseline") != nil }
            try await w.settle()
            let close = try #require(sheetNode(w, "subpage.close"))
            // The sheet's top edge on screen (its view's frame is in the transition container's coordinates).
            let sheetView = try #require(w.host.presentedViewController?.view)
            let sheetTop = sheetView.convert(sheetView.bounds, to: nil).minY
            let rootInset = close.frame.minY - sheetTop
            sheetNode(w, "sleepNeed.changeBaseline")?.activate()
            try await w.wait("the editor") { sheetNode(w, "subpage.back") != nil && sheetStepper(w) != nil }
            try await w.settle()
            let back = try #require(sheetNode(w, "subpage.back"))
            #expect(abs((back.frame.minY - sheetTop) - rootInset) < 1,
                    "the sheet's 26 pt inset, as its root: \(back.frame.minY - sheetTop) vs \(rootInset)")
            #expect(abs(rootInset - (SubpageSpec.sheetTopInset - ScreenHeaderSpec.buttonOverhang)) < 1, "\(rootInset)")
            #expect(sheetNodes(w).contains { $0.label == "Baseline sleep need" && $0.traits.contains(.header) })
            sheetStepper(w)?.object.accessibilityIncrement()
            try await w.wait("Save on") { sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.isEnabled == true }
            sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.activate()
            try await w.wait("Saving…") { sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.label == "Saving…" }
            #expect(sheetNode(w, "subpage.back")?.isEnabled == false)
            #expect(w.host.presentedViewController?.isModalInPresentation == true)
            await gate.open()
            try await w.wait("Saved") { sheetNodes(w).contains { $0.label == savedWords } }
            #expect(sheetNode(w, "subpage.back")?.isEnabled == true)
        }
    }

    /// Profile as the app builds it (`ScreenModels`), its rows and About you's footer.
    private func profile(_ state: AppState) -> (AnyView, ScreenModels) {
        let sync = SyncService.ungated(env: state.env)
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: state.env.clock)
        let screens = ScreenModels(state: state, sync: sync, coordinator: coordinator, store: TrainPreview.store,
                                   library: TrainPreview.library, apiStatus: APIStatus())
        let view = ProfileView()
            .environment(\.appEnvironment, state.env)
            .environment(screens)
            .environment(state.env.settings)
            .environment(state.env.auth)
            .environment(sync)
            .environment(state)
            .environment(TrainPreview.library)
            .environment(TrainPreview.sync)
            .environment(TrainPreview.coordinator)
            .environment(state.env.connectivityMonitor)
            .environment(\.locale, Locale(identifier: "en_US"))
        return (AnyView(view), screens)
    }

    @Test("Profile: the row says Saving…, then the saved value; a failure with no editor open is in About you's footer")
    func profileRows() async throws {
        let (api, platform) = C3Platform.api()
        let gate = Gate()
        platform.applies = false
        platform.onPatch = {
            await gate.wait()
            throw APIError.transport(URLError(.timedOut))
        }
        let state = makeState(api: api)
        let (view, screens) = profile(state)
        let editor = screens.profile.bodySettings
        try await HostedWindow.run(width: 390, height: 3_200, view) { w in
            let id = ProfileRow.sleepBase.identifier
            try await w.wait("the row") { w.nodes().contains { $0.identifier == id } }
            try await w.settle()
            #expect(w.nodes().first { $0.identifier == id }?.value == "7h 30m, Set by you · learned 7h 52m")
            let saving = Task { await editor.setSleepBase(480) }
            try await w.wait("Saving…") { w.nodes().first { $0.identifier == id }?.value == "Saving…" }
            #expect(!w.nodes().contains { ($0.value ?? "").contains("8h") }, "the value on its way is the editor's alone")
            await gate.open()
            _ = await saving.value
            try await w.wait("the failure, where the user is") { w.node(noAnswerWords, exactly: true) != nil }
            #expect(w.nodes().first { $0.identifier == id }?.value == "7h 30m, Set by you · learned 7h 52m")
        }
    }
}

// MARK: - hosted: the sheet and the card

@MainActor
@Suite("C3: Sleep need, hosted", .serialized)
struct SleepNeedHostedTests {
    private func host(need: SleepNeed? = MockSleepNeedStates.need, needMinutes: Int? = nil, state: AppState? = nil,
                      editor: BodySettingsEditor? = nil, ax3: Bool = false,
                      body: (HostedWindow) async throws -> Void) async throws {
        let state = state ?? makeState()
        let sheet = SleepNeedSheet(need: need, total: "8h 18m", needMinutes: needMinutes, night: "Last night · Sun, Nov 15",
                                   editor: editor ?? BodySettingsEditor(state: state))
        try await HostedWindow.run(width: 390, height: ax3 ? 2_400 : 1_000, bottomInset: 0,
                                   typeSize: ax3 ? .accessibility3 : .large, category: ax3 ? .accessibilityExtraLarge : .large,
                                   sheet.previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US"))) { w in
            try await w.wait("the baseline row") { w.nodes().contains { $0.identifier == "sleepNeed.changeBaseline" } }
            try await w.settle()
            try await body(w)
        }
    }

    @Test("VoiceOver: the numeral, the tile's head, one element per term, the sentence, the paragraph, the row")
    func readingOrder() async throws {
        try await host { w in
            let labels = w.nodes().map(\.label)
            let order = ["Sleep need, 8 hours 18 minutes", "How it adds up", "Baseline, 7 hours 30 minutes",
                         "Strain, plus 20 minutes", "Sleep debt, plus 28 minutes",
                         SleepNeedBreakdown(MockSleepNeedStates.need).spokenSentence, "Your baseline is yours to set",
                         "Baseline sleep need"].map { label in labels.firstIndex { $0.hasPrefix(label) } ?? -1 }
            #expect(!order.contains(-1) && order == order.sorted(), "\(order) in \(labels)")
            let head = try #require(w.node("How it adds up", exactly: true))
            #expect(head.traits.contains(.header) && head.value == "8 hours 18 minutes")
            #expect(labels.filter { $0 == "How it adds up" }.count == 1, "said once, by the head row: \(labels)")
            // Each term's ticks are one value, not 30 elements; no nap without a credit.
            #expect(!labels.contains { $0.hasPrefix("Nap credit") })
            let row = try #require(w.nodes().first { $0.identifier == "sleepNeed.changeBaseline" })
            #expect(row.label == "Baseline sleep need" && row.hint == "Opens the editor")
            #expect(row.value == "7 hours 30 minutes, Set by you", "in words, not a time of day: \(row.value ?? "")")
        }
    }

    @Test("A save out: the row says Saving…; its failure, after the editor went, is under the row, where the user is")
    func aSaveFromTheSheet() async throws {
        let (api, platform) = C3Platform.api()
        let gate = Gate()
        platform.applies = false
        platform.onPatch = {
            await gate.wait()
            throw APIError.transport(URLError(.timedOut))
        }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        let saving = Task { await editor.setSleepBase(480) }
        #expect(await eventually { editor.saving })
        try await host(state: state, editor: editor) { w in
            let row = { w.nodes().first { $0.identifier == "sleepNeed.changeBaseline" } }
            #expect(row()?.value == "Saving…", "never the value on its way: \(row()?.value ?? "")")
            await gate.open()
            _ = await saving.value
            try await w.wait("the failure") { w.node(noAnswerWords, exactly: true) != nil }
            try await w.settle()
            #expect(row()?.value == "7 hours 30 minutes, Set by you")
            let notice = try #require(w.node(noAnswerWords, exactly: true))
            #expect(notice.frame.minY >= (row()?.frame.maxY ?? .infinity), "under the row")
        }
    }

    @Test("A nap credit is its own row, a minus")
    func napCredit() async throws {
        try await host(need: MockSleepNeedStates.needWithNap) { w in
            #expect(w.node("Nap credit, minus 25 minutes", exactly: true) != nil)
            #expect(w.node("Sleep need, 7 hours 53 minutes", exactly: true) != nil)
        }
    }

    @Test("No breakdown: the notice instead of the tile, the night's need as the numeral, no sentence")
    func noBreakdown() async throws {
        try await host(need: nil, needMinutes: 498) { w in
            #expect(w.node("This night was scored before RYFT broke the need down.", exactly: true) != nil)
            #expect(w.node("How it adds up") == nil && !w.nodes().contains { $0.identifier == "sleepNeed.sentence" })
            #expect(w.node("Sleep need, 8 hours 18 minutes", exactly: true) != nil)
            #expect(w.nodes().contains { $0.identifier == "sleepNeed.changeBaseline" })
        }
    }

    @Test("Offline with no account cached: the baseline row says Not loaded yet, never the default")
    func offlineWithoutAccount() async throws {
        try await host(state: makeState(online: false, user: nil)) { w in
            let row = try #require(w.nodes().first { $0.identifier == "sleepNeed.changeBaseline" })
            #expect(row.value == "Not loaded yet")
            #expect(w.node("Sleep need, 8 hours 18 minutes", exactly: true) != nil, "the night is the cached one")
        }
    }

    @Test("AX3: nothing leaves the width, the terms stack (label and value over the ticks), the row grows")
    func ax3() async throws {
        var defaultRow: CGFloat = 0
        try await host { w in
            let strain = try #require(w.node("Strain, plus 20 minutes", exactly: true))
            #expect(strain.frame.height < 20, "one line at the default size: \(strain.frame)")
            defaultRow = try #require(w.nodes().first { $0.identifier == "sleepNeed.changeBaseline" }).frame.height
        }
        try await host(ax3: true) { w in
            for node in w.nodes() {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= 390.5 && node.frame.height > 0, "\(node.label) \(node.frame)")
            }
            for label in ["Baseline, 7 hours 30 minutes", "Strain, plus 20 minutes", "Sleep debt, plus 28 minutes"] {
                let term = try #require(w.node(label, exactly: true))
                #expect(term.frame.height > TickRow.tick.height + TickRow.stackedSpacing + 20, "\(label) stacked: \(term.frame)")
            }
            let row = try #require(w.nodes().first { $0.identifier == "sleepNeed.changeBaseline" })
            #expect(row.frame.height > 2 * defaultRow, "the value goes under the title: \(row.frame.height) vs \(defaultRow)")
        }
    }

    @Test("The card: one push row with the need in words, its hint, and the sentence as its footer; a tap opens the sheet")
    func card() async throws {
        var opened = false
        let state = makeState()
        try await HostedWindow.run(width: 390, height: 400, bottomInset: 0,
                                   SleepNeedCard(need: MockSleepNeedStates.need) { opened = true }
                                       .padding(20).previewEnvironment(state)) { w in
            try await w.wait("the card") { w.nodes().contains { $0.identifier == "sleep.need" } }
            let row = try #require(w.nodes().first { $0.identifier == "sleep.need" })
            #expect(row.label == "Sleep need" && row.value == "8 hours 18 minutes")
            #expect(row.hint == "Shows how your sleep need adds up, and your baseline to change" && row.traits.contains(.button))
            #expect(w.node(SleepNeedBreakdown(MockSleepNeedStates.need).spokenSentence, exactly: true) != nil)
            row.activate()
            #expect(await eventually(timeout: .seconds(5)) { opened })
        }
    }
}
