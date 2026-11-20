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
/// The hosted suites' waits (C3 review 2, N6): a loaded runner lays out slowly.
private let hostedWait: Duration = .seconds(15)
private let busyWords = "RYFT is busy right now, so this wasn't saved. Try again in a minute."

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
        // A no-break space keeps each number with its "h" (50c0b80).
        #expect(BodySetting.sleepBase.rulerLabels == ["4\u{00A0}h", "8\u{00A0}h", "12\u{00A0}h"])
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

    @Test("While a save is out, Save is off (its spinner says so); the value on its way is the page's, every row says Saving…")
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

    @Test("A failure is its setting's page's: a max HR refusal doesn't show on Baseline sleep need (PR 6 C review N7)")
    func aFailureIsItsSettingsPages() async {
        let (api, _) = C3Platform.api()
        let editor = BodySettingsEditor(state: makeState(api: api))
        api.failNext = APIError.http(409, "", requestID: "rid-409")
        #expect(!(await editor.setMaxHR(185)))
        let message = editor.error
        #expect(editor.errorSetting == .maxHR && message != nil)
        #expect(BodySettingContent(.maxHR, editor: editor, draft: editor.maxHR).error == message)
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: editor.sleepBase).error == nil, "not on the baseline's page")
        // The baseline's own failure is on its page, and no longer on max HR's.
        api.failNext = APIError.http(409, "")
        #expect(!(await editor.setSleepBase(465)))
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: editor.sleepBase).error == editor.error)
        #expect(BodySettingContent(.maxHR, editor: editor, draft: editor.maxHR).error == nil)
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

    @Test("Refused (409, 403, 501): it's back as it was; the request ID goes along, never the raw error text",
          arguments: [APIError.http(409, "conflict", requestID: "rid-409"),
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

    /// C3 review 2, N5: a 429 is RYFT being busy, in its own words, for the editors and Notifications alike; not asked again.
    @Test("Busy (429): its own words for both callers; nothing changed, RYFT isn't asked again")
    func busy() async {
        let error = APIError.http(429, "", requestID: "rid-429", retryAfter: 60)
        #expect(SettingsWriteFailure(error) == .busy && !SettingsWriteFailure(error).rereads)
        #expect(BodySettingsFailure(save: error).message == busyWords && NotificationSettingsFailure(error).message == busyWords)
        #expect(BodySettingsFailure(save: error).details?.contains("Request ID rid-429") == true)
        #expect(BodySettingsFailure(rescore: error).message
                == "RYFT couldn't rescore your days, so past days keep their scores. Try again in a moment.")
        let (api, _) = C3Platform.api()
        let editor = BodySettingsEditor(state: makeState(api: api))
        let reads = api.count("me")
        api.failNext = error
        #expect(!(await editor.setSleepBase(465)))
        #expect(editor.error == busyWords && editor.sleepBase == 450 && !editor.savedChange)
        #expect(api.count("me") == reads, "a 429 changed nothing: nothing to ask")
    }

    /// C3 review 2, item 3: RYFT took the change and answered in words this build can't read (`APIClient.decode` keeps the
    /// status): no answer, which may have saved.
    @Test("An unreadable 2xx is no answer: it may have saved, and RYFT is asked again")
    func anUnreadableAnswer() async {
        let unreadable = APIError.http(200, "RYFT sent an answer this version of the app can't read.", requestID: "rid-200")
        #expect(SettingsWriteFailure(unreadable) == .noAnswer && SettingsWriteFailure(unreadable).rereads)
        #expect(SettingsWriteFailure(APIError.http(204, "")) == .noAnswer)
        let (api, platform) = C3Platform.api()
        platform.onPatch = { throw unreadable }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        let reads = api.count("me")
        #expect(await editor.setSleepBase(465), "asked again: the account holds it")
        #expect(editor.error == nil && editor.hasSaved(.sleepBase) && api.count("me") > reads)
        platform.applies = false
        platform.onPatch = { throw unreadable }
        #expect(!(await editor.setSleepBase(480)))
        #expect(editor.error == noAnswerWords && editor.errorDetails?.contains("rid-200") == true && editor.sleepBase == 465)
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
        #expect(!editor.savedChange && !editor.saving, "not Saved. on the dropped answer's word")
        #expect(editor.error == noAnswerWords, "RYFT couldn't be asked: it may not have saved (C3 review 2, N2)")
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
        // The sign-out's hooks ran: the editor forgot A (its value on its way among it).
        #expect(await eventually(timeout: .seconds(15)) { !auth.isSignedIn && !editor.saving })
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

// MARK: - what a save waits for (C3 review 2)

/// An app graph whose Demo data switch is its own setting (never the test host's), with the account's platform and demo's.
@MainActor
private func switchable(account: MockPlatformAPI, demo: MockPlatformAPI) -> (AppState, Settings, TestClock) {
    let clock = TestClock()
    let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
    let settings = Settings(defaults: defaults)
    settings.demoMode = false
    account.now = { clock.now() }
    demo.now = { clock.now() }
    let env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: account, demoAPI: demo, auth: .preview(),
                             persistence: TrainStore(inMemory: true), clock: clock, notifier: MockNotifier(),
                             flags: StaticFlags([:]), connectivity: .preview(online: true), defaults: defaults,
                             demoOverride: nil)
    env.reads.random = { $0.lowerBound }
    env.reads.budget = RequestBudget(clock: clock, maxStarts: .max)
    let state = AppState(env: env)
    state.repository.widgetFile = nil
    state.user = MockSleepNeedStates.user
    return (state, settings, clock)
}

/// Demo data's account: a learned 7:00.
private let demoUser = MockSleepNeedStates.user(sleepBaseMin: 420, sleepBaseSource: .learned)

@MainActor
struct BodySettingsWaitTests {
    /// The switch as `ProfileViewModel.setDemoMode(true)` turns it.
    private func demoOn(_ state: AppState, _ settings: Settings) async {
        settings.demoMode = true
        state.reset()
        await state.refresh()
    }

    @Test("Demo data on mid-save: nothing busy, nothing of the account's; the account's late answer ends only its own write",
          .timeLimit(.minutes(1)))
    func demoMidSave() async {
        let (account, accountPlatform) = C3Platform.api()
        let (demo, _) = C3Platform.api(user: demoUser)
        let gate = Gate()
        account.beforePatchMe = { await gate.wait() }
        let (state, settings, _) = switchable(account: account, demo: demo)
        let editor = BodySettingsEditor(state: state)
        let save = Task { await editor.setSleepBase(465) }
        #expect(await eventually { editor.pendingSleepBase == 465 })
        await demoOn(state, settings)
        #expect(!editor.isBusy && editor.pendingSleepBase == nil && editor.error == nil && !editor.savedChange)
        #expect(SleepNeedSheetContent.BaselineRow(editor: editor).value == "7:00", "demo's baseline, not Saving…")
        // Demo's own save, held, while the account's answer arrives.
        let demoGate = Gate()
        demo.beforePatchMe = { await demoGate.wait() }
        let demoSave = Task { await editor.setSleepBase(435) }
        #expect(await eventually { editor.pendingSleepBase == 435 })
        await gate.open()
        #expect(!(await save.value))
        #expect(editor.saving && editor.pendingSleepBase == 435, "the account's answer ends only its own write")
        #expect(editor.error == nil && !editor.savedChange)
        await demoGate.open()
        #expect(await demoSave.value)
        #expect(!editor.isBusy && editor.sleepBase == 435 && editor.hasSaved(.sleepBase))
        #expect(accountPlatform.user.sleepBaseMin == 465, "the account's change stayed the account's")
    }

    @Test("Demo data on mid-rescore: nothing busy, no status of the account's; its late end ends only its own rescore",
          .timeLimit(.minutes(1)))
    func demoMidRescore() async {
        let (account, _) = C3Platform.api()
        let (demo, _) = C3Platform.api(user: demoUser)
        let (state, settings, clock) = switchable(account: account, demo: demo)
        let editor = BodySettingsEditor(state: state)
        let run = Task { await editor.rescore() }
        #expect(await eventually { clock.pendingSleeps == 1 && editor.rescoreStatus != nil })
        await demoOn(state, settings)
        #expect(!editor.isBusy && editor.rescoreStatus == nil && !editor.rescoreFailed)
        // Demo's own rescore waits a second longer than the account's.
        clock.advance(by: .seconds(1))
        let demoRun = Task { await editor.rescore() }
        #expect(await eventually { clock.pendingSleeps == 2 })
        clock.advance(by: SyncService.rescoreDelay - .seconds(1))
        await run.value
        #expect(editor.rescoring && editor.rescoreStatus == "Rescoring — scores update in a few seconds.", "demo's still runs")
        clock.advance(by: .seconds(1))
        await demoRun.value
        #expect(!editor.isBusy && editor.rescored)
        #expect(account.count("recompute") == 1 && demo.count("recompute") == 1)
    }

    @Test("No answer within 25 s: the editor stops waiting, says it may not have saved, and asks RYFT; a late answer settles it",
          .timeLimit(.minutes(1)))
    func theDeadline() async {
        let (api, platform) = C3Platform.api()
        let gate = Gate()
        platform.applies = false
        platform.onPatch = { await gate.wait() }
        let clock = TestClock()
        let state = AppState(env: .test(api: api, clock: clock))
        state.user = MockSleepNeedStates.user
        let editor = BodySettingsEditor(state: state)
        let reads = api.count("me")
        let save = Task { await editor.setSleepBase(465) }
        #expect(await eventually { editor.saving && clock.pendingSleeps == 1 })
        clock.advance(by: BodySettingsEditor.answerDeadline - .seconds(1))
        #expect(editor.saving, "24 s: still waiting")
        clock.advance(by: .seconds(1))
        #expect(!(await save.value))
        #expect(!editor.saving && editor.error == noAnswerWords && editor.sleepBase == 450)
        #expect(api.count("me") > reads, "asked again")
        // The answer arrives after all, and the store takes it: the account holds the change, so it's Saved.
        await gate.open()
        #expect(await eventually { editor.error == nil && editor.hasSaved(.sleepBase) && editor.sleepBase == 465 })
    }

    @Test("The network goes mid-save: no answer at once, nothing asked offline; online, the next refresh asks and settles it",
          .timeLimit(.minutes(1)))
    func offlineMidSaveThenRefresh() async {
        let (api, platform) = C3Platform.api()
        let gate = Gate()
        // RYFT took it; the answer is held.
        platform.onPatch = { await gate.wait() }
        let state = makeState(api: api)
        let monitor = state.env.connectivityMonitor
        let editor = BodySettingsEditor(state: state)
        let reads = api.count("me")
        let save = Task { await editor.setSleepBase(465) }
        #expect(await eventually { editor.saving })
        monitor.update(false)
        #expect(!(await save.value))
        #expect(!editor.saving && editor.error == noAnswerWords && api.count("me") == reads, "offline: nothing asked")
        #expect(SleepNeedSheetContent.BaselineRow(editor: editor).value == "7:30")
        monitor.update(true)
        await state.refresh()
        #expect(api.count("me") == reads + 1, "the cached user was fresh, but marked: asked")
        #expect(SleepNeedSheetContent.BaselineRow(editor: editor).value == "7:45", "what the platform holds")
        #expect(await eventually { editor.error == nil && editor.hasSaved(.sleepBase) }, "held: Saved. after all")
        await state.refresh()
        #expect(api.count("me") == reads + 1, "asked once: the mark went with the answer")
        await gate.open()
    }

    @Test("RYFT can't be asked after no answer: the cached user is marked, and the next refresh asks and settles it",
          .timeLimit(.minutes(1)))
    func aFailedRereadMarksTheUser() async {
        let (api, platform) = C3Platform.api()
        platform.onPatch = { throw APIError.transport(URLError(.timedOut)) }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        api.faults["me"] = FaultInjection.Rule(.notFound)
        #expect(!(await editor.setSleepBase(465)))
        #expect(editor.error == noAnswerWords && editor.sleepBase == 450)
        api.faults["me"] = nil
        let reads = api.count("me")
        await state.refresh()
        #expect(api.count("me") == reads + 1)
        #expect(await eventually { editor.error == nil && editor.sleepBase == 465 && editor.hasSaved(.sleepBase) })
    }

    @Test("Saved is the saved setting's: the other page's words stay unsaid (C3 review 2, N1)")
    func savedIsTheSettings() async {
        let editor = BodySettingsEditor(state: makeState())
        #expect(await editor.setSleepBase(465))
        #expect(editor.hasSaved(.sleepBase) && !editor.hasSaved(.maxHR) && editor.savedChange)
        #expect(await editor.setBirthYear(1991))
        #expect(!editor.hasSaved(.sleepBase) && !editor.hasSaved(.maxHR) && editor.savedChange, "no page of its own")
    }

    @Test("The rescore's reload failed: it stays \"Rescoring — …\", never rescored (C3 review 2, N4)", .timeLimit(.minutes(1)))
    func aFailedReloadIsNotRescored() async {
        let (api, _) = C3Platform.api()
        let clock = TestClock()
        let state = AppState(env: .test(api: api, clock: clock))
        state.user = MockSleepNeedStates.user
        let editor = BodySettingsEditor(state: state)
        api.faults["days"] = FaultInjection.Rule(.notFound)
        let run = Task { await editor.rescore() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: SyncService.rescoreDelay)
        await run.value
        #expect(!editor.rescoring && !editor.rescored && !editor.rescoreFailed)
        #expect(editor.rescoreStatus == "Rescoring — scores update in a few seconds.")
        #expect(api.count("days") >= 1, "asked, not answered")
    }
}

// MARK: - Notifications: the same classifier

@MainActor
struct NotificationFailuresTests {
    @Test("Notifications judge a failure by what left the phone, as the editors do", arguments: [
        (APIError.transport(URLError(.notConnectedToInternet)), SettingsWriteFailure.offline),
        (APIError.transport(URLError(.timedOut)), .noAnswer), (APIError.transport(URLError(.networkConnectionLost)), .noAnswer),
        (APIError.http(500, ""), .serverError), (APIError.http(429, ""), .busy), (APIError.http(200, ""), .noAnswer),
        (APIError.http(409, ""), .refused),
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
        await model.asking?.value
        #expect(model.isOn(.pr) && api.count("me") > reads)
    }

    /// C3 review 2, N3: the question after a failure runs outside the save's turn.
    @Test("The question after a 5xx doesn't hold the switches: they're free while it's out", .timeLimit(.minutes(1)))
    func theQuestionDoesntHoldTheSwitches() async {
        let (model, api) = model()
        let gate = Gate()
        api.beforeMe = { await gate.wait() }
        api.failNext = APIError.http(503, "")
        await model.set(.pr, on: false)
        #expect(!model.saving && model.failure?.kind == .serverError, "back as it went, and free, while RYFT is asked")
        await gate.open()
        await model.asking?.value
        #expect(model.isOn(.pr) && model.failure?.kind == .serverError, "RYFT doesn't hold it: the notice stays")
    }

    @Test("Asked again, only the change's own key decides: another device's change of the rest doesn't keep the notice")
    func onlyTheChangedKeyDecides() async {
        let (model, api) = model()
        // RYFT took it, and another device turned the morning score off meanwhile.
        var categories = NotificationPrefs.allOn.categories
        categories[NotificationCategory.pr.rawValue] = false
        categories[NotificationCategory.morningScore.rawValue] = false
        api.prefs = NotificationPrefs(categories: categories, quietHours: nil)
        api.failNext = APIError.http(503, "")
        await model.set(.pr, on: false)
        await model.asking?.value
        #expect(model.failure == nil, "it did save")
        #expect(!model.isOn(.pr) && !model.isOn(.morningScore), "the page shows what RYFT holds")
    }

    @Test("A question that fails changes nothing: the page stays as it went back, the notice stays")
    func aFailedQuestionChangesNothing() async {
        let (model, api) = model()
        var categories = NotificationPrefs.allOn.categories
        categories[NotificationCategory.pr.rawValue] = false
        api.prefs = NotificationPrefs(categories: categories, quietHours: nil)
        api.faults["me"] = FaultInjection.Rule(.notFound)
        api.failNext = APIError.http(503, "")
        await model.set(.pr, on: false)
        await model.asking?.value
        #expect(model.isOn(.pr) && model.failure?.kind == .serverError)
    }
}

/// The UIKit pickers under `view` (a compact `DatePicker` is one).
@MainActor
private func datePickers(_ view: UIView?) -> [UIDatePicker] {
    guard let view else { return [] }
    if let picker = view as? UIDatePicker { return [picker] }
    return view.subviews.flatMap { datePickers($0) }
}

@MainActor
@Suite("C3: Notifications offline, hosted", .serialized)
struct NotificationsOfflineHostedTests {
    /// C3 review 2, N3: checked in the simulator, kept as a test.
    @Test("Offline, a time the wheel stopped on goes back: the wheel shows the saved time, the notice says why")
    func anOfflineTimeGoesBack() async throws {
        let notifier = MockNotifier()
        notifier.status = .authorized
        let state = AppState(env: .test(api: MockPlatformAPI(), notifier: notifier, flags: [.pushEnabled: true], online: false))
        var user = MockData.user
        user.notifications = NotificationPrefs(categories: user.notifications.categories,
                                               quietHours: QuietHours(from: "22:30", to: "07:00"))
        state.user = user
        let view = NavigationStack { NotificationSettingsView() }
            .previewEnvironment(state)
            .toggleStyle(.ryft)
            .environment(\.locale, Locale(identifier: "en_US"))
        try await HostedWindow.run(width: 390, height: 1_400, view) { w in
            try await w.wait("the time chips", timeout: hostedWait) { datePickers(w.host.view).count == 2 }
            try await w.settle()
            let from = try #require(datePickers(w.host.view).first)
            #expect(NotificationSettingsViewModel.string(from.date) == "22:30")
            from.date = Calendar.current.date(bySettingHour: 23, minute: 15, second: 0, of: from.date) ?? from.date
            from.sendActions(for: .valueChanged)
            try await w.wait("the notice", timeout: hostedWait) { w.node(offlineWords, exactly: true) != nil }
            try await w.settle()
            let shown = datePickers(w.host.view).first.map { NotificationSettingsViewModel.string($0.date) }
            #expect(shown == "22:30", "the wheel is back on the saved time, not the unsaved 23:15")
        }
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
            try await w.wait("the stepper", timeout: hostedWait) { w.nodes().contains { $0.isAdjustable } }
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
            let up = setting == .sleepBase ? "7 hours 45 minutes" : "191 beats per minute"
            try await w.wait("a step up", timeout: hostedWait) { (try? stepper(w).value) == up }
            try stepper(w).decrement()
            try stepper(w).decrement()
            let down = setting == .sleepBase ? "7 hours 15 minutes" : "189 beats per minute"
            try await w.wait("two down", timeout: hostedWait) { (try? stepper(w).value) == down }
        }
    }

    @Test("From the default 7:40, a step lands on the grid (7:45 up), then goes a step at a time (7:30, 7:15 down)")
    func aStepFromOffTheGrid() async throws {
        let user = MockSleepNeedStates.user(sleepBaseMin: BodySettingsEditor.defaultSleepBase, sleepBaseSource: .default)
        let (api, _) = C3Platform.api(user: user)
        try await host(state: makeState(api: api, user: user)) { w, _ in
            #expect(try stepper(w).value == "7 hours 40 minutes")
            try stepper(w).increment()
            try await w.wait("7:45", timeout: hostedWait) { (try? stepper(w).value) == "7 hours 45 minutes" }
            try stepper(w).decrement()
            try await w.wait("7:30", timeout: hostedWait) { (try? stepper(w).value) == "7 hours 30 minutes" }
            try stepper(w).decrement()
            try await w.wait("7:15", timeout: hostedWait) { (try? stepper(w).value) == "7 hours 15 minutes" }
        }
    }

    @Test("Save is off while nothing changed, on once something did; the source names the saved value, VoiceOver in words")
    func saveFollowsTheChange() async throws {
        try await host { w, _ in
            #expect(try save(w).isEnabled == false)
            #expect(w.node("Set by you", exactly: true) != nil)
            try stepper(w).increment()
            try await w.wait("Save on", timeout: hostedWait) { (try? save(w).isEnabled) == true }
            #expect(node(w, "bodySettings.source")?.label == "Set by you, saved 7 hours 30 minutes", "not 7:30 as a time of day")
        }
        try await host(.maxHR) { w, _ in
            try stepper(w).increment()
            try await w.wait("Save on", timeout: hostedWait) { (try? save(w, .maxHR).isEnabled) == true }
            #expect(node(w, "bodySettings.source")?.label == "Estimated from your age (born 1990), saved 190 beats per minute")
        }
    }

    @Test("Saving: the pill keeps Save and is busy (\"In progress\"), the stepper is off, Close isn't; Saved: the notice, the rescore row, Save off")
    func savingThenSaved() async throws {
        let (api, _) = C3Platform.api()
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        try await host(state: makeState(api: api)) { w, editor in
            try stepper(w).increment()
            try await w.wait("Save on", timeout: hostedWait) { (try? save(w).isEnabled) == true }
            try save(w).activate()
            // Busy is the spinner: the title stays Save (the build plan's rule, PR 6 C review N5).
            try await w.wait("busy", timeout: hostedWait) { (try? save(w).value) == "In progress" }
            #expect(try save(w).label == "Save")
            #expect(try stepper(w).isEnabled == false)
            #expect(node(w, "subpage.close")?.isEnabled == true, "the page may go while its save is out (C3 review 2, item 2)")
            #expect(!w.nodes().contains { $0.label.hasPrefix("Saved.") }, "nothing reads as saved yet")
            await gate.open()
            try await w.wait("Saved", timeout: hostedWait) { w.node(savedWords) != nil }
            try await w.settle()
            let pill = try save(w), value = try stepper(w)
            #expect(pill.label == "Save" && !pill.isEnabled)
            #expect(value.value == "7 hours 45 minutes" && editor.sleepBase == 465)
            #expect(node(w, "subpage.close")?.isEnabled == true)
            #expect(w.nodes().contains { $0.identifier == "bodySettings.rescore" && $0.label == "Rescore the last 90 days" })
        }
    }

    @Test("Opened while a save is out: Save busy, the value on its way, Close on; then its answer on this page")
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
            #expect(pill.label == "Save" && pill.value == "In progress")
            #expect(value.value == "8 hours" && !value.isEnabled)
            #expect(node(w, "subpage.close")?.isEnabled == true)
            await gate.open()
            _ = await saving.value
            try await w.wait("Saved", timeout: hostedWait) { w.node(savedWords) != nil }
            try await w.settle()
            let after = try save(w), stepped = try stepper(w)
            #expect(after.label == "Save" && stepped.value == "8 hours" && stepped.isEnabled)
        }
    }

    @Test("Another setting's page open while a save is out: that save's Saved isn't said there (C3 review 2, N1)")
    func savedIsItsOwnPages() async throws {
        let (api, _) = C3Platform.api()
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        let saving = Task { await editor.setSleepBase(480) }
        #expect(await eventually { editor.saving })
        try await host(.maxHR, state: state, editor: editor) { w, _ in
            await gate.open()
            #expect(await saving.value)
            try await w.settle()
            #expect(editor.hasSaved(.sleepBase) && !editor.hasSaved(.maxHR))
            #expect(w.node(savedWords) == nil && node(w, "bodySettings.rescore") == nil, "the baseline's Saved isn't this page's")
            let pill = try save(w, .maxHR), value = try stepper(w)
            #expect(pill.label == "Save" && value.isEnabled)
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
            try await w.wait("Save on", timeout: hostedWait) { (try? save(w).isEnabled) == true }
            try save(w).activate()
            try await w.wait("the notice", timeout: hostedWait) { w.node(message, exactly: true) != nil }
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
            try await w.wait("the rescore row", timeout: hostedWait) { w.nodes().contains { $0.identifier == "bodySettings.rescore" } }
            api.failure = APIError.http(500, "", requestID: "rid-rescore")
            try #require(w.nodes().first { $0.identifier == "bodySettings.rescore" }).activate()
            let message = "RYFT couldn't rescore your days, so past days keep their scores. Try again in a moment."
            try await w.wait("the rescore notice", timeout: hostedWait) { w.node(message) != nil }
            try await w.settle()
            let row = try #require(w.nodes().first { $0.identifier == "bodySettings.rescore" })
            let notice = try #require(w.node(message))
            let saved = try #require(w.node(savedWords))
            #expect(saved.frame.maxY <= row.frame.minY && notice.frame.minY >= row.frame.maxY, "\(saved.frame) \(row.frame) \(notice.frame)")
            #expect(w.nodes().contains { $0.label.contains("Request ID rid-rescore") || ($0.value ?? "").contains("rid-rescore") })
            #expect(row.isEnabled && row.label == "Rescore the last 90 days", "it can be tried again")
        }
    }

    @Test("Rescoring keeps the row's title, busy, and a tap does nothing; rescored and seen: the status says so, the row waits for a new change")
    func rescoredRowWaits() async throws {
        let (api, _) = C3Platform.api()
        let clock = TestClock()
        let state = AppState(env: .test(api: api, clock: clock))
        state.user = MockSleepNeedStates.user
        try await host(state: state) { w, editor in
            await editor.setSleepBase(465)
            try await w.wait("the rescore row", timeout: hostedWait) { node(w, "bodySettings.rescore") != nil }
            try #require(node(w, "bodySettings.rescore")).activate()
            // Waited for outside `#expect`: a closure inside its expansion here trips the compiler (closure type mismatch).
            try await w.wait("the delay", timeout: hostedWait) { clock.pendingSleeps == 1 }
            // The busy rule: the row keeps its title, its spinner says it runs, and a second tap starts nothing.
            try await w.wait("busy", timeout: hostedWait) { node(w, "bodySettings.rescore")?.value == "In progress" }
            let busy = try #require(node(w, "bodySettings.rescore"))
            #expect(busy.label == "Rescore the last 90 days", "\(busy.label)")
            busy.activate()
            try await w.settle()
            #expect(api.calls.filter { $0 == "recompute" }.count == 1, "\(api.calls)")
            clock.advance(by: SyncService.rescoreDelay)
            try await w.wait("rescored", timeout: hostedWait) { w.node("The last 90 days are rescored with your settings.") != nil }
            try await w.settle()
            #expect(node(w, "bodySettings.rescore")?.isEnabled == false, "nothing new to rescore")
            try stepper(w).increment()
            try await w.wait("Save on", timeout: hostedWait) { (try? save(w).isEnabled) == true }
            try save(w).activate()
            try await w.wait("Saved again", timeout: hostedWait) { w.node(savedWords) != nil }
            try await w.wait("the row is back", timeout: hostedWait) { node(w, "bodySettings.rescore")?.isEnabled == true }
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
            try await w.wait("the numeral follows", timeout: hostedWait) { (try? stepper(w).value) == expected }
            try await w.wait("Saved", timeout: hostedWait) { w.node(savedWords) != nil }
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
            try await w.wait("Save on", timeout: hostedWait) { (try? save(w).isEnabled) == true }
            try save(w).activate()
            try await w.wait("Saved", timeout: hostedWait) { w.node("Saved.", exactly: true) != nil }
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

    @Test("As Profile's and onboarding's sheet: Close, on mid-save, and the sheet swipes away; onboarding offers no rescore",
          arguments: [true, false])
    func asASheet(rescores: Bool) async throws {
        let (api, _) = C3Platform.api()
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        try await host(BodySettingSheetHost(editor: editor, rescores: rescores), state: state) { w in
            try await w.wait("the sheet", timeout: hostedWait) { sheetStepper(w) != nil && sheetNode(w, "subpage.close") != nil }
            try await w.settle()
            #expect(sheetNode(w, "subpage.back") == nil)
            sheetStepper(w)?.object.accessibilityIncrement()
            try await w.wait("Save on", timeout: hostedWait) { sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.isEnabled == true }
            sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.activate()
            try await w.wait("busy", timeout: hostedWait) { sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.value == "In progress" }
            #expect(sheetNode(w, "subpage.close")?.isEnabled == true)
            #expect(w.host.presentedViewController?.isModalInPresentation == false, "a swipe down leaves mid-save too")
            await gate.open()
            let saved = rescores ? savedWords : "Saved."
            try await w.wait("Saved", timeout: hostedWait) { sheetNodes(w).contains { $0.label == saved } }
            #expect(sheetNode(w, "subpage.close")?.isEnabled == true)
            #expect(w.host.presentedViewController?.isModalInPresentation == false)
            #expect((sheetNode(w, "bodySettings.rescore") != nil) == rescores)
        }
    }

    @Test("Pushed inside Sleep's need sheet: Back (no Close), the sheet's 26 pt inset, Back on while the save is out")
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
            try await w.wait("the need sheet", timeout: hostedWait) { sheetNode(w, "sleepNeed.changeBaseline") != nil }
            try await w.settle()
            let close = try #require(sheetNode(w, "subpage.close"))
            // The sheet's top edge on screen (its view's frame is in the transition container's coordinates).
            let sheetView = try #require(w.host.presentedViewController?.view)
            let sheetTop = sheetView.convert(sheetView.bounds, to: nil).minY
            let rootInset = close.frame.minY - sheetTop
            sheetNode(w, "sleepNeed.changeBaseline")?.activate()
            try await w.wait("the editor", timeout: hostedWait) { sheetNode(w, "subpage.back") != nil && sheetStepper(w) != nil }
            try await w.settle()
            let back = try #require(sheetNode(w, "subpage.back"))
            #expect(abs((back.frame.minY - sheetTop) - rootInset) < 1,
                    "the sheet's 26 pt inset, as its root: \(back.frame.minY - sheetTop) vs \(rootInset)")
            #expect(abs(rootInset - (SubpageSpec.sheetTopInset - ScreenHeaderSpec.buttonOverhang)) < 1, "\(rootInset)")
            #expect(sheetNodes(w).contains { $0.label == "Baseline sleep need" && $0.traits.contains(.header) })
            sheetStepper(w)?.object.accessibilityIncrement()
            try await w.wait("Save on", timeout: hostedWait) { sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.isEnabled == true }
            sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.activate()
            try await w.wait("busy", timeout: hostedWait) { sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.value == "In progress" }
            #expect(sheetNode(w, "subpage.back")?.isEnabled == true)
            #expect(w.host.presentedViewController?.isModalInPresentation == false)
            await gate.open()
            try await w.wait("Saved", timeout: hostedWait) { sheetNodes(w).contains { $0.label == savedWords } }
            #expect(sheetNode(w, "subpage.back")?.isEnabled == true)
        }
    }

    /// C3 review 2, item 2: the page doesn't hold the user while its save is out.
    @Test("Close mid-save: the sheet goes, the save goes on, and its failure is kept for where the user is")
    func closedMidSave() async throws {
        let (api, platform) = C3Platform.api()
        let gate = Gate()
        platform.applies = false
        platform.onPatch = {
            await gate.wait()
            throw APIError.transport(URLError(.timedOut))
        }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        try await host(BodySettingSheetHost(editor: editor, rescores: true), state: state) { w in
            try await w.wait("the sheet", timeout: hostedWait) { sheetStepper(w) != nil }
            try await w.settle()
            sheetStepper(w)?.object.accessibilityIncrement()
            try await w.wait("Save on", timeout: hostedWait) { sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.isEnabled == true }
            sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.activate()
            try await w.wait("Saving…", timeout: hostedWait) { editor.saving }
            sheetNode(w, "subpage.close")?.activate()
            try await w.wait("the sheet went", timeout: hostedWait) { w.host.presentedViewController == nil }
            #expect(editor.saving && editor.pendingSleepBase == 465, "the save goes on")
            await gate.open()
            try await w.wait("the failure", timeout: hostedWait) { editor.error != nil }
            #expect(editor.error == noAnswerWords && editor.errorMissed, "said where the user is: About you, the need sheet")
        }
    }

    /// The navigation stack inside the presented sheet.
    private func navigation(in controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let navigation = controller as? UINavigationController { return navigation }
        return controller.children.lazy.compactMap { self.navigation(in: $0) }.first
    }

    /// C3 review 2, item 5: Back (or the edge swipe) while the save is out; its failure arrives on the need sheet.
    @Test("Back mid-save in the need sheet: the row says Saving…, then the failure is under it")
    func backMidSave() async throws {
        let (api, platform) = C3Platform.api()
        let gate = Gate()
        platform.applies = false
        platform.onPatch = {
            await gate.wait()
            throw APIError.transport(URLError(.timedOut))
        }
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        let sheet = SheetHost {
            SleepNeedSheet(need: MockSleepNeedStates.need, total: "8h 18m", night: "Last night · Sun, Nov 15", editor: editor)
        }
        try await host(sheet, state: state) { w in
            try await w.wait("the need sheet", timeout: hostedWait) { sheetNode(w, "sleepNeed.changeBaseline") != nil }
            try await w.settle()
            sheetNode(w, "sleepNeed.changeBaseline")?.activate()
            try await w.wait("the editor", timeout: hostedWait) { sheetNode(w, "subpage.back") != nil && sheetStepper(w) != nil }
            try await w.settle()
            sheetStepper(w)?.object.accessibilityIncrement()
            try await w.wait("Save on", timeout: hostedWait) { sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.isEnabled == true }
            sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.activate()
            try await w.wait("busy", timeout: hostedWait) {
                sheetNode(w, BodySetting.sleepBase.saveIdentifier)?.value == "In progress"
            }
            // As the edge swipe ends: UIKit pops, SwiftUI follows.
            let stack = try #require(navigation(in: w.host.presentedViewController))
            stack.popViewController(animated: false)
            try await w.wait("the need sheet again", timeout: hostedWait) {
                sheetNode(w, "sleepNeed.changeBaseline") != nil && sheetStepper(w) == nil
            }
            #expect(sheetNode(w, "sleepNeed.changeBaseline")?.value == "Saving…")
            await gate.open()
            try await w.wait("the failure under the row", timeout: hostedWait) { sheetNode(w, "sleepNeed.baselineError") != nil }
            #expect(sheetNode(w, "sleepNeed.baselineError")?.label.contains(noAnswerWords) == true)
            #expect(sheetNode(w, "sleepNeed.changeBaseline")?.value == "7 hours 30 minutes, Set by you")
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
            try await w.wait("the row", timeout: hostedWait) { w.nodes().contains { $0.identifier == id } }
            try await w.settle()
            #expect(w.nodes().first { $0.identifier == id }?.value == "7h 30m, Set by you · learned 7h 52m")
            let saving = Task { await editor.setSleepBase(480) }
            try await w.wait("Saving…", timeout: hostedWait) { w.nodes().first { $0.identifier == id }?.value == "Saving…" }
            #expect(!w.nodes().contains { ($0.value ?? "").contains("8h") }, "the value on its way is the editor's alone")
            await gate.open()
            _ = await saving.value
            try await w.wait("the failure, where the user is", timeout: hostedWait) { w.node(noAnswerWords, exactly: true) != nil }
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
            try await w.wait("the baseline row", timeout: hostedWait) { w.nodes().contains { $0.identifier == "sleepNeed.changeBaseline" } }
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
            try await w.wait("the failure", timeout: hostedWait) { w.node(noAnswerWords, exactly: true) != nil }
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
            try await w.wait("the card", timeout: hostedWait) { w.nodes().contains { $0.identifier == "sleep.need" } }
            let row = try #require(w.nodes().first { $0.identifier == "sleep.need" })
            #expect(row.label == "Sleep need" && row.value == "8 hours 18 minutes")
            #expect(row.hint == "Shows how your sleep need adds up, and your baseline to change" && row.traits.contains(.button))
            #expect(w.node(SleepNeedBreakdown(MockSleepNeedStates.need).spokenSentence, exactly: true) != nil)
            row.activate()
            #expect(await eventually { opened })
        }
    }
}
