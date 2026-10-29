import Foundation
import Testing
@testable import Ryft

// F3 (beta feedback 2): "the baseline counter is not moving". A Garmin account (no HRV in Apple Health) saw
// "0 / 7" for a week beside a Recovery of 71 %: `baseline_days = min(H, R)` stays 0 without HRV, and the platform
// says `short_history` until 7 days have data. Today now counts what is filling, says why, shows N1 as soon as
// the tracker setup knows, and never puts a percentage beside the counter. Synthetic numbers, fixed dates.

private let day = "2026-10-22"
private let computed = Date(timeIntervalSince1970: 1_792_650_000)
private let snapshotTime = Date(timeIntervalSince1970: 1_792_650_000)

/// A `short_history` row: counts, readiness and, with a readiness, the day's own signals. The platform makes a recovery,
/// and so a readiness, from any of HRV, resting HR, breathing and sleep (`compute.go`): a row without a readiness has
/// none of them on the day, so `hrv` / `rhr` and the night apply only with one. `impossibleRecovery` builds the one shape
/// it never sends (a recovery without a readiness), only for the test that pins the defensive guard.
private func row(h: Int?, r: Int?, hrv: Double? = nil, rhr: Double? = nil, readiness: Int? = nil,
                 impossibleRecovery: Int? = nil, reason: CalibratingReason? = .shortHistory) -> DailyScore {
    let night = readiness != nil
    return DailyScore(day: day, readiness: readiness, state: .calibrating, recovery: readiness ?? impossibleRecovery,
                      strain: 6.8, sleepActualMin: night ? 410 : nil, hrvMs: night ? hrv : nil, rhr: night ? rhr : nil,
                      baselineDays: min(h ?? 0, r ?? 0), calibrating: true, computedAt: computed,
                      scoringState: .scored, baselineHrvDays: h, baselineRhrDays: r, calibratingReason: reason)
}

/// `count` scored days before `day`, oldest first; resting HR on the latest `rhrDays`, HRV on the latest `hrvDays`.
private func history(_ count: Int, hrvDays: Int = 0, rhrDays: Int = 0) -> [DailyScore] {
    guard count > 0, let today = DayFormat.date(from: day) else { return [] }
    return (1...count).reversed().map { offset in
        DailyScore(day: DayFormat.string(from: DayFormat.shift(today, days: -offset)), readiness: 70, recovery: 66,
                   strain: 6, hrvMs: offset <= hrvDays ? 48 : nil, rhr: offset <= rhrDays ? 53 : nil, baselineDays: 0,
                   calibrating: true, computedAt: computed, scoringState: .scored)
    }
}

private func facts(_ today: DailyScore, prior: [DailyScore] = history(4, rhrDays: 3), trackers: [String] = [],
                   flag: Bool = false) -> TodayScoreFacts {
    TodayScoreFacts(day: day, today: today, scoringState: .scored, prior: prior,
                    trackers: trackers.map { MockData.tracker($0) }, devicesSetup: flag)
}

private func widgetKind(_ f: TodayScoreFacts) -> ReadinessSnapshot.Kind? {
    ReadinessSnapshot.make(day: f.day, presentation: .decide(f), now: snapshotTime)?.kind
}

/// What each case is compared by.
struct CounterOutcome: Equatable, CustomStringConvertible {
    var gauge: TodayPresentation.Gauge
    var note: TodayPresentation.Note?
    var tilesCalibrating = false
    var recoveryWithheld = false
    var widget: ReadinessSnapshot.Kind?

    var description: String { "\(gauge) note \(note.map { "\($0)" } ?? "nil") widget \(widget.map { "\($0)" } ?? "nil")" }
}

struct CounterCase: Sendable, CustomTestStringConvertible {
    let name: String
    let facts: TodayScoreFacts
    let expected: CounterOutcome
    var testDescription: String { name }
}

@Suite("Today: the baseline counter counts what is filling (F3)")
struct TodayBaselineCounterTests {
    private static let noHRV = CalibrationBlocker(signals: [.hrv], source: .unknown, link: nil)
    private static let garminSetup = CalibrationLink.setup(trackerID: "garmin", app: "Garmin Connect")
    private static let garminNoHRV = CalibrationBlocker(signals: [.hrv], source: .notShared(app: "Garmin Connect"),
                                                        link: garminSetup)

    /// S1: the counter, "calibrating" under the tiles, Recovery withheld.
    private static func s1(_ nights: Int, _ note: TodayPresentation.Note? = nil) -> CounterOutcome {
        CounterOutcome(gauge: .baselines(nights: nights), note: note, tilesCalibrating: true, recoveryWithheld: true,
                       widget: .calibrating)
    }
    private static func restingHR(_ nights: Int, _ absent: CalibrationBlocker = noHRV) -> TodayPresentation.Note {
        .learning(CalibrationProgress(nights: nights, signals: [.restingHR], absent: absent))
    }
    private static func n1(_ readiness: Int?, _ blocker: CalibrationBlocker) -> CounterOutcome {
        CounterOutcome(gauge: .readiness(readiness), note: .blocked(blocker), widget: readiness == nil ? .waitingForSleep : .score)
    }

    static let cases: [CounterCase] = [
        // 1: what is filling
        // Without a readiness the day has no night: the counts are all there is.
        CounterCase(name: "S1 H0/R3, no readiness: counts resting HR 3 of 7, says why",
                    facts: facts(row(h: 0, r: 3)), expected: s1(3, restingHR(3))),
        CounterCase(name: "S1 H0/R1: one resting-HR night is enough to count it",
                    facts: facts(row(h: 0, r: 1), prior: history(2, rhrDays: 1)), expected: s1(1, restingHR(1))),
        CounterCase(name: "S1 H2/R0: counts HRV",
                    facts: facts(row(h: 2, r: 0), prior: history(4, hrvDays: 2)),
                    expected: s1(2, .learning(CalibrationProgress(
                        nights: 2, signals: [.hrv], absent: CalibrationBlocker(signals: [.restingHR], source: .unknown, link: nil))))),
        CounterCase(name: "S1 H0/R3, flag on, nothing chosen: the note links Devices & sync",
                    facts: facts(row(h: 0, r: 3), flag: true),
                    expected: s1(3, restingHR(3, CalibrationBlocker(signals: [.hrv], source: .unknown, link: .devices)))),
        CounterCase(name: "S1 H0/R3, Apple Watch chosen: HRV expected, Check sync, still counting",
                    facts: facts(row(h: 0, r: 3), trackers: ["apple_watch"], flag: true),
                    expected: s1(3, restingHR(3, CalibrationBlocker(signals: [.hrv], source: .unexpected, link: .checkSync)))),
        // Nothing counted yet: 0 of 7, the plain counter (W < 7, nothing known yet)
        CounterCase(name: "S1 both 0, no readiness, flag off: 0 of 7, no note",
                    facts: facts(row(h: 0, r: 0), prior: []), expected: s1(0)),
        CounterCase(name: "S1 H0/R0 with resting HR and a readiness (Garmin's first night), flag off: 0 of 7 baselines",
                    facts: facts(row(h: 0, r: 0, rhr: 55, readiness: 60), prior: []),
                    expected: CounterOutcome(gauge: .readiness(60),
                                             note: .learning(CalibrationProgress(nights: 0, signals: [.hrv, .restingHR])),
                                             widget: .score)),
        CounterCase(name: "S1 H3/R5, both counted: baseline_days as before",
                    facts: facts(row(h: 3, r: 5), prior: history(5, hrvDays: 3, rhrDays: 5)), expected: s1(3)),
        // 3: one story, readiness in the gauge
        CounterCase(name: "S1 with readiness, H0/R3: the readiness and the resting-HR note, tiles agree",
                    facts: facts(row(h: 0, r: 3, rhr: 54, readiness: 71)),
                    expected: CounterOutcome(gauge: .readiness(71), note: restingHR(3), widget: .score)),
        CounterCase(name: "S1 with readiness, first night: the readiness and 0 of 7 baselines",
                    facts: facts(row(h: 0, r: 0, hrv: 50, rhr: 52, readiness: 64), prior: []),
                    expected: CounterOutcome(gauge: .readiness(64),
                                             note: .learning(CalibrationProgress(nights: 0, signals: [.hrv, .restingHR])),
                                             widget: .score)),
        // 2: N1 as soon as the setup knows
        CounterCase(name: "N1 early: Garmin chosen, H0/R3, readiness 71",
                    facts: facts(row(h: 0, r: 3, rhr: 54, readiness: 71), trackers: ["garmin"], flag: true),
                    expected: n1(71, garminNoHRV)),
        CounterCase(name: "N1 early without a readiness: the empty gauge, never 3 of 7",
                    facts: facts(row(h: 0, r: 3), trackers: ["garmin"], flag: true), expected: n1(nil, garminNoHRV)),
        CounterCase(name: "N1 early on Garmin's first night (H0/R0, resting HR on the day)",
                    facts: facts(row(h: 0, r: 0, rhr: 55, readiness: 60), prior: [], trackers: ["garmin"], flag: true),
                    expected: n1(60, garminNoHRV)),
        CounterCase(name: "N1 early, Oura: neither signal, both named",
                    facts: facts(row(h: 0, r: 0, readiness: 66), prior: history(3), trackers: ["oura"], flag: true),
                    expected: n1(66, CalibrationBlocker(signals: [.hrv, .restingHR], source: .notShared(app: "Oura"),
                                                        link: .setup(trackerID: "oura", app: "Oura")))),
        CounterCase(name: "N1 early, just the iPhone",
                    facts: facts(row(h: 0, r: 0, readiness: 58), prior: history(2), trackers: ["iphone"], flag: true),
                    expected: n1(58, CalibrationBlocker(signals: [.hrv, .restingHR], source: .phoneOnly, link: .devices))),
        CounterCase(name: "Garmin chosen but the flag off: no N1 early, counts resting HR",
                    facts: facts(row(h: 0, r: 3), trackers: ["garmin"], flag: false), expected: s1(3, restingHR(3))),
        // a counter at 7 can't move either
        CounterCase(name: "H0/R7 short_history without HRV: blocked, never 7 of 7",
                    facts: facts(row(h: 0, r: 7), prior: history(7, rhrDays: 7)), expected: n1(nil, noHRV)),
        CounterCase(name: "H0/R6: counts 6 of 7, still moving",
                    facts: facts(row(h: 0, r: 6), prior: history(6, rhrDays: 6)), expected: s1(6, restingHR(6))),
        // legacy: no reason, unknown counts: as before, but no recovery beside the counter
        CounterCase(name: "legacy, short history, no reason: 0 of 7, Recovery withheld",
                    facts: facts(row(h: nil, r: nil, reason: nil), prior: history(3)), expected: s1(0)),
        CounterCase(name: "legacy, long history without vitals, no readiness: heart-rate nights, Recovery withheld",
                    facts: facts(row(h: nil, r: nil, reason: nil), prior: history(30, hrvDays: 2, rhrDays: 2)),
                    expected: CounterOutcome(gauge: .baselines(nights: 2), note: .needsVitals, recoveryWithheld: true,
                                             widget: .calibrating)),
    ]

    @Test("decide", arguments: cases)
    func decides(_ c: CounterCase) {
        let p = TodayPresentation.decide(c.facts)
        let got = CounterOutcome(gauge: p.gauge, note: p.note, tilesCalibrating: p.tiles.calibrating,
                                 recoveryWithheld: p.tiles.withholdsRecovery, widget: widgetKind(c.facts))
        #expect(got == c.expected)
        #expect(p.row == .calibrating && !p.showsDelta)
    }

    /// The counter moves: one more night of the signals that have been arriving (counted before, or on the day)
    /// raises it, or ends it. Not asserted where nothing has arrived yet (both counts 0, nothing on the day: API.md's
    /// day one) or the counts are unknown (path L).
    @Test("a counter moves with one more night of what has been arriving", arguments: cases)
    func theCounterMoves(_ c: CounterCase) throws {
        guard case .baselines(let nights) = TodayPresentation.decide(c.facts).gauge else { return }
        let today = try #require(c.facts.today)
        guard today.calibratingReason != nil, let h = today.baselineHrvDays, let r = today.baselineRhrDays else { return }
        let hrvArrives = h > 0 || today.hrvMs != nil, rhrArrives = r > 0 || today.rhr != nil
        guard hrvArrives || rhrArrives else { return }
        var tomorrow = today
        if hrvArrives { tomorrow.baselineHrvDays = h + 1 }
        if rhrArrives { tomorrow.baselineRhrDays = r + 1 }
        tomorrow.baselineDays = min(tomorrow.baselineHrvDays ?? 0, tomorrow.baselineRhrDays ?? 0)
        var next = c.facts
        next.today = tomorrow
        if case .baselines(let after) = TodayPresentation.decide(next).gauge {
            #expect(after > nights, "stuck at \(nights)")
        }
    }

    /// One story: the Recovery tile never shows a percentage beside the counter, and does beside a readiness.
    @MainActor @Test("Recovery beside the gauge", arguments: cases)
    func recoveryBesideTheGauge(_ c: CounterCase) {
        let content = Self.content(c.facts)
        if case .baselines = content.presentation.gauge {
            #expect(content.recovery == nil && content.recoveryText == Fmt.percent(Int?.none))
            #expect(content.recoveryCaption == "calibrating")
        } else if c.facts.today?.recovery != nil {
            #expect(content.recovery == c.facts.today?.recovery)
        }
    }

    /// The defensive guard: a recovery without a readiness is a shape the platform never sends (it sets both or
    /// neither), but a cached or rolled-back row could carry one. Beside the counter it is still "—" and
    /// "calibrating", on the short_history path and on path L.
    @MainActor @Test func aRecoveryWithoutReadinessIsNeverBesideTheCounter() {
        for impossible in [row(h: 0, r: 3, impossibleRecovery: 74),
                           row(h: nil, r: nil, impossibleRecovery: 74, reason: nil)] {
            let f = facts(impossible)
            let p = TodayPresentation.decide(f)
            guard case .baselines = p.gauge else { Issue.record("expected the counter, got \(p.gauge)"); continue }
            #expect(p.tiles.withholdsRecovery && p.tiles.source?.recovery == 74 && p.tiles.recovery == nil)
            let content = Self.content(f)
            #expect(content.recoveryText == Fmt.percent(Int?.none) && content.recoveryCaption == "calibrating")
            #expect(content.recoveryBand == nil)
        }
    }

    // MARK: the note's words

    @Test func theFillingNoteSaysWhichAndWhy() {
        #expect(CalibrationProgress(nights: 3, signals: [.restingHR], absent: Self.noHRV).text
            == "Learning your resting heart rate baseline: 3 of 7 nights. No HRV has reached RYFT yet, so recovery uses resting heart rate and sleep.")
        #expect(CalibrationProgress(nights: 2, signals: [.hrv], absent: CalibrationBlocker(signals: [.restingHR], source: .unknown, link: nil)).text
            == "Learning your HRV baseline: 2 of 7 nights. No resting heart rate has reached RYFT yet, so recovery uses HRV and sleep.")
        // Without an absent signal, the S2 lines as before.
        #expect(CalibrationProgress(nights: 3, signals: [.restingHR]).text == "Learning your resting heart rate baseline: 3 of 7 nights.")
        // The count is clamped like the gauge's.
        #expect(CalibrationProgress(nights: 9, signals: [.restingHR], absent: Self.noHRV).text.hasPrefix(
            "Learning your resting heart rate baseline: 7 of 7 nights."))
    }

    @Test func theFillingNoteLinksWhereItsBlockerDoes() {
        let check = TodayPresentation.Note.learning(CalibrationProgress(
            nights: 3, signals: [.restingHR], absent: CalibrationBlocker(signals: [.hrv], source: .unexpected, link: .checkSync)))
        #expect(check.link == .checkSync && check.isCalibration && !check.isBlocked)
        #expect(TodayPresentation.Note.learning(CalibrationProgress(nights: 3, signals: [.hrv])).link == nil)
        // The gauge names the counted signal only when the other is absent.
        #expect(check.countedSignal == .restingHR)
        #expect(TodayPresentation.Note.learning(CalibrationProgress(nights: 3, signals: [.restingHR])).countedSignal == nil)
        #expect(TodayPresentation.Note.blocked(Self.noHRV).countedSignal == nil)
        #expect(TodayPresentation.Note.needsVitals.countedSignal == nil)
    }

    @Test func absentAndFillingSignals() {
        #expect(row(h: 0, r: 3).absentSignals == [.hrv])
        #expect(row(h: 0, r: 3, hrv: 40, readiness: 70).absentSignals.isEmpty, "HRV on the day is arriving")
        #expect(row(h: 0, r: 0).absentSignals == [.hrv, .restingHR])
        #expect(row(h: 0, r: 0, rhr: 50, readiness: 70).absentSignals == [.hrv])
        #expect(row(h: nil, r: 3).absentSignals.isEmpty, "unknown counts say nothing")
        #expect(row(h: 1, r: 3).absentSignals.isEmpty)
        #expect(row(h: 0, r: 3).onlyFillingSignal?.signal == .restingHR)
        #expect(row(h: 0, r: 3).onlyFillingSignal?.nights == 3)
        #expect(row(h: 0, r: 0, rhr: 50, readiness: 70).onlyFillingSignal == nil, "no resting-HR night counted yet")
        #expect(row(h: 2, r: 0).onlyFillingSignal?.signal == .hrv)
        #expect(row(h: 0, r: 0).onlyFillingSignal == nil)
        // Which rows read the tracker setup.
        #expect(row(h: 0, r: 3).calibrationNamesTracker)
        #expect(!row(h: 0, r: 3, hrv: 40, readiness: 70).calibrationNamesTracker)
        #expect(!row(h: 2, r: 3).calibrationNamesTracker)
        #expect(row(h: 0, r: 24, reason: .noHrv).calibrationNamesTracker)
        #expect(!row(h: nil, r: nil, reason: nil).calibrationNamesTracker)
        var settled = row(h: 0, r: 3)
        settled.calibrating = false
        #expect(!settled.calibrationNamesTracker)
    }

    // MARK: the reported row and the demo states (presentation values, as the previews show them)

    /// The reported account's rows, synthetic numbers (`daily_score_f3_no_hrv.json`): [0] its first week
    /// (`short_history`, H 0, R 3), [1] a row scored today after 14 days with data (`no_hrv`, R 12), [2] a row scored
    /// before `calibrating_reason` existed (all null), [3] one written by an older scoring image (counts, no reason).
    /// All: readiness 71, recovery 71, no `hrv_ms`, a resting HR.
    private static func reportedRows() throws -> [DailyScore] {
        try Fixture.decode([DailyScore].self, "daily_score_f3_no_hrv")
    }

    /// 14 scored days with resting HR and without HRV: the account as the platform has it now.
    private static let fourteenDays = history(14, rhrDays: 14)

    /// (b) Today's row scored now: N1, the readiness and the note, never a counter (with or without the setup).
    @MainActor @Test func theReportedAccountTodayIsN1() throws {
        let rows = try Self.reportedRows()
        try #require(rows.count == 4)
        let today = rows[1]
        #expect(today.calibratingReason == .noHrv && today.baselineHrvDays == 0 && today.baselineRhrDays == 12)
        let off = Self.content(facts(today, prior: Self.fourteenDays))
        #expect(off.hero == .score && off.readiness == 71)
        #expect(off.gaugeNote == .blocked(Self.noHRV) && off.gaugeNote?.text == "No HRV has reached RYFT from your nights.")
        #expect(off.sentence == "Readiness from the signals that reached RYFT.")
        #expect(off.recoveryText == Fmt.percent(71) && off.recoveryBand != nil && off.tileCaption == nil)
        let garmin = Self.content(facts(today, prior: Self.fourteenDays, trackers: ["garmin"], flag: true))
        #expect(garmin.gaugeNote == .blocked(Self.garminNoHRV)
            && garmin.gaugeNote?.text == "Garmin Connect doesn't share HRV with Apple Health.")
        #expect(widgetKind(facts(today, prior: Self.fourteenDays)) == .score)
    }

    /// (a) A cached or rolled-back row without a reason over the long history: path L's B "needs vitals", the
    /// readiness with the note, no counter; the counts the row may carry don't change it.
    @MainActor @Test func theReportedAccountsLegacyRowIsNeedsVitals() throws {
        let rows = try Self.reportedRows()
        try #require(rows.count == 4)
        for legacy in [rows[2], rows[3]] {
            #expect(legacy.calibratingReason == nil)
            let content = Self.content(facts(legacy, prior: Self.fourteenDays, trackers: ["garmin"], flag: true))
            #expect(content.hero == .score && content.readiness == 71)
            #expect(content.gaugeNote == .needsVitals)
            #expect(content.recoveryText == Fmt.percent(71) && content.recoveryBand != nil)
            #expect(widgetKind(facts(legacy, prior: Self.fourteenDays)) == .score)
        }
        // The rolled-back row's counts (H 0, R 12) don't make it read the tracker setup.
        #expect(!rows[3].calibrationNamesTracker)
    }

    /// (c) The brief's first-week row: calibrating, `short_history`, `baseline_days` 0, H 0, R 3, readiness 71, no
    /// `hrv_ms`, a resting HR.
    @MainActor @Test func theReportedRow() throws {
        let rows = try Self.reportedRows()
        let reported = try #require(rows.first)
        #expect(reported.calibrating && reported.calibratingReason == .shortHistory && reported.baselineDays == 0)
        #expect(reported.baselineHrvDays == 0 && reported.baselineRhrDays == 3 && reported.hrvMs == nil && reported.rhr != nil)
        #expect(reported.readiness == 71 && reported.recovery == 71)

        // Flag off (the feedback build's world): the readiness, the note counting resting HR, the tiles agree.
        let off = Self.content(facts(reported))
        #expect(off.hero == .score && off.readiness == 71)
        #expect(off.gaugeNote == .learning(CalibrationProgress(nights: 3, signals: [.restingHR], absent: Self.noHRV)))
        #expect(off.gaugeNote?.text.contains("3 of 7") == true)
        #expect(off.sentence == String(localized: "Your baselines are still forming."))
        #expect(off.recoveryText == Fmt.percent(71) && off.recoveryBand != nil && off.tileCaption == nil)
        #expect(!off.showsReadinessBand && off.readinessDelta == nil)
        #expect(widgetKind(facts(reported)) == .score)

        // Garmin chosen with the setup on: N1 now.
        let garmin = Self.content(facts(reported, trackers: ["garmin"], flag: true))
        #expect(garmin.readiness == 71 && garmin.gaugeNote == .blocked(Self.garminNoHRV))
        #expect(garmin.gaugeNote?.link == Self.garminSetup)
        #expect(garmin.sentence == String(localized: "Readiness from the signals that reached RYFT."))
        let garminText = garmin.gaugeNote?.text ?? ""
        #expect(!garminText.isEmpty && !garminText.contains(where: \.isNumber))

        // The same row before its readiness: counting resting HR, Recovery "—" and "calibrating".
        var noReadiness = reported
        noReadiness.readiness = nil
        noReadiness.recovery = nil // set together by the platform, from the day's night: without one, none of it
        noReadiness.rhr = nil
        noReadiness.sleepActualMin = nil
        let counter = Self.content(facts(noReadiness))
        #expect(counter.hero == .calibrating(nights: 3))
        #expect(counter.recoveryText == Fmt.percent(Int?.none) && counter.recovery == nil)
        #expect(counter.sentence == String(localized: "Your baselines are still forming."))
        let snapshot = ReadinessSnapshot.make(day: day, presentation: .decide(facts(noReadiness)), now: snapshotTime)
        #expect(snapshot?.kind == .calibrating && snapshot?.baselineNights == 3)
    }

    /// The demo scenarios behind the previews (`-RyftScenario learningRestingHR` …): what each state shows.
    @MainActor @Test func theScenariosShowTheirStates() {
        let now = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: computed) ?? computed
        func content(_ scenario: TodayScenario) -> TodayContent {
            let f = scenario.apply(to: TodaySyncFacts(now: now))
            let p = TodayPresentation.decide(f.scores)
            return TodayContent(facts: f, presentation: p, hero: TodayStates.hero(f, presentation: p), hasDataSource: true,
                                readinessWeek: [], detailSleepMin: nil)
        }
        let counting = content(.learningRestingHR)
        #expect(counting.hero == .calibrating(nights: 3))
        #expect(counting.gaugeNote == .learning(CalibrationProgress(nights: 3, signals: [.restingHR], absent: Self.noHRV)))
        #expect(counting.recoveryText == Fmt.percent(Int?.none) && counting.tileCaption != nil)
        // No readiness, so no night on the day either: Sleep is "–" too.
        #expect(counting.sleepText == Fmt.placeholder && counting.facts.today?.rhr == nil)

        let scored = content(.learningRestingHRScored)
        #expect(scored.hero == .score && scored.readiness == 71 && scored.recoveryText == Fmt.percent(71))
        #expect(scored.gaugeNote == counting.gaugeNote)

        let early = content(.blockedEarly)
        #expect(early.hero == .score && early.readiness == 71 && early.gaugeNote == .blocked(Self.garminNoHRV))
        #expect(early.recoveryText == Fmt.percent(71))
    }

    /// 4: the widget decides from the store with the same tracker setup as Today, so N1 early reaches it too.
    @MainActor @Test func theWidgetDecidesWithTheTrackerSetup() throws {
        let noon = try #require(DayFormat.date(from: day)).addingTimeInterval(12 * 3_600)
        let env = AppEnvironment.test(clock: TestClock(now: noon), flags: [.devicesSetup: true])
        let state = AppState(env: env)
        state.history = history(4, rhrDays: 3)
        state.today = DayDetail(score: row(h: 0, r: 3), sleep: nil, workouts: [])
        // Nothing chosen: counting resting HR, which moves.
        #expect(state.repository.widgetFacts.trackers.isEmpty)
        #expect(TodayPresentation.decide(state.repository.widgetFacts).gauge == .baselines(nights: 3))
        // Garmin chosen: N1 now, no counter on the widget either.
        state.repository.chosenTrackers = { ["garmin"] }
        let p = TodayPresentation.decide(state.repository.widgetFacts)
        #expect(p.note == .blocked(Self.garminNoHRV))
        let snapshot = ReadinessSnapshot.make(day: day, presentation: p, now: noon)
        #expect(snapshot?.kind == .waitingForSleep && snapshot?.baselineNights == nil)
        // A row whose signals all arrive doesn't read the choice.
        state.today = DayDetail(score: row(h: 2, r: 3), sleep: nil, workouts: [])
        #expect(state.repository.widgetFacts.trackers.isEmpty)
    }

    /// Review: the widget is published again when the tracker choice changes, not only on the next score write.
    @MainActor @Test func choosingATrackerRepublishesTheWidget() async throws {
        let noon = try #require(DayFormat.date(from: day)).addingTimeInterval(12 * 3_600)
        let env = AppEnvironment.test(clock: TestClock(now: noon), flags: [.devicesSetup: true])
        let state = AppState(env: env)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("readiness-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        state.repository.widgetFile = file
        state.repository.reloadWidget = {}
        state.history = history(4, rhrDays: 3)
        state.today = DayDetail(score: row(h: 0, r: 3), sleep: nil, workouts: [])
        let sync = SyncService.ungated(env: env)
        let store = TrainStore(inMemory: true)
        let screens = ScreenModels(state: state, sync: sync,
                                   coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                                   store: store, library: TrainLibrary(store: store, remote: { [api = env.api] in api }, restore: false),
                                   apiStatus: APIStatus())
        state.repository.publishWidget()
        func written() -> ReadinessSnapshot? {
            (try? Data(contentsOf: file)).flatMap { try? ReadinessSnapshot.decoder.decode(ReadinessSnapshot.self, from: $0) }
        }
        #expect(written()?.kind == .calibrating && written()?.baselineNights == 3)
        screens.devices.set(["garmin"])
        // The watch acts on the next main-actor turn: poll, no fixed sleep.
        for _ in 0..<200 where written()?.kind == .calibrating { await Task.yield() }
        #expect(written()?.kind == .waitingForSleep && written()?.baselineNights == nil, "N1 early: no counter")
    }

    /// The watch itself, over `devices.setup` flipping in a `FlagStore` (what `/v1/config` changes) and again after.
    @MainActor @Test func theWatchFollowsTheFlag() async {
        let defaults = UserDefaults(suiteName: "ryft.test.watch.\(UUID().uuidString)") ?? .standard
        let flags = FlagStore(store: TrainStore(inMemory: true), defaults: defaults)
        var calls = 0
        let watch = ObservationWatch(read: { _ = flags.isOn(.devicesSetup) }, changed: { calls += 1 })
        let on = !FeatureFlag.devicesSetup.compiledDefault
        flags.apply(RemoteConfig(flags: [FeatureFlag.devicesSetup.rawValue: on], evaluatedAt: .now, ttlSec: 3_600,
                                 privacyPolicyVersion: nil, privacyPolicyUrl: nil), fetchedAt: .now)
        for _ in 0..<200 where calls == 0 { await Task.yield() }
        #expect(calls == 1 && flags.isOn(.devicesSetup) == on)
        // Still watching after the first change.
        flags.setOverride(.devicesSetup, !on)
        for _ in 0..<200 where calls == 1 { await Task.yield() }
        #expect(calls == 2)
        withExtendedLifetime(watch) {}
    }

    @MainActor private static func content(_ f: TodayScoreFacts) -> TodayContent {
        let now = (DayFormat.date(from: day) ?? computed).addingTimeInterval(7.5 * 3_600)
        var s = TodaySyncFacts(now: now)
        s.today = f.today
        s.prior = f.prior
        s.hasScoredDay = true
        s.devicesSetup = f.devicesSetup
        s.trackers = f.trackers
        let p = TodayPresentation.decide(s.scores)
        return TodayContent(facts: s, presentation: p, hero: TodayStates.hero(s, presentation: p), hasDataSource: true,
                            readinessWeek: [], detailSleepMin: nil)
    }
}
