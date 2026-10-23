import Foundation
import Testing
@testable import Ryft

// design.md §7 rev. 2 §6: Today's calibration decision over API.md's eight `calibrating_reason` examples, the
// legacy rows and the guards; the note's tracker naming (`CalibrationBlocker.resolve`); and the invariants that
// keep a counter that can't move off the screen and the widget. Fixed dates, no clock, no sleeps.

/// What a decision is compared by: the row, the gauge, the note and what the widget would show.
struct CalibrationOutcome: Equatable, CustomStringConvertible {
    var row: TodayPresentation.Row
    var gauge: TodayPresentation.Gauge?
    var note: TodayPresentation.Note?
    var tilesCalibrating = false
    var showsDelta = false
    /// `nil`: the widget has no snapshot (the first import).
    var widget: ReadinessSnapshot.Kind?

    var description: String {
        "\(row) \(gauge.map { "\($0)" } ?? "gauge not checked") note \(note.map { "\($0)" } ?? "nil") widget \(widget.map { "\($0)" } ?? "nil")"
    }
}

struct CalibrationDecideCase: Sendable, CustomTestStringConvertible {
    let name: String
    let facts: TodayScoreFacts
    let expected: CalibrationOutcome
    var testDescription: String { name }
}

private let day = "2026-10-22"
private let garmin = [MockData.tracker("garmin")]

/// API.md's eight examples, in order (`daily_score_calibrating_reasons.json`).
private let examples: [DailyScore] = (try? Fixture.decode([DailyScore].self, "daily_score_calibrating_reasons")) ?? []

/// Example `n` (1-based) as the platform sends it, plus what the prose adds: a computed row.
private func example(_ n: Int, readiness: Int? = nil, hrv: Double? = nil, rhr: Double? = nil) -> DailyScore {
    var row = examples.indices.contains(n - 1) ? examples[n - 1] : DailyScore(day: "missing example \(n)")
    row.readiness = readiness
    row.hrvMs = hrv
    row.rhr = rhr
    row.recovery = readiness.map { $0 - 2 }
    row.computedAt = Date(timeIntervalSince1970: 1_792_650_000)
    row.scoringState = .scored
    return row
}

/// `count` scored days before `day`, oldest first. `vitals`: how many of them (the latest ones) carry HRV and
/// resting HR; `readiness: nil` makes them scored days without one.
private func prior(_ count: Int, vitals: Int = 0, readiness: Int? = 70) -> [DailyScore] {
    guard let today = DayFormat.date(from: day) else { return [] }
    return (1...max(count, 1)).reversed().prefix(count).map { offset in
        let withVitals = offset <= vitals
        return DailyScore(day: DayFormat.string(from: DayFormat.shift(today, days: -offset)), readiness: readiness,
                          recovery: 60, strain: 8, hrvMs: withVitals ? 48 : nil, rhr: withVitals ? 52 : nil,
                          baselineDays: 0, calibrating: false, computedAt: Date(timeIntervalSince1970: 1_792_000_000),
                          scoringState: .scored)
    }
}

private func facts(_ today: DailyScore?, prior: [DailyScore], trackers: [Tracker] = [], flag: Bool = false,
                   state: ScoringState? = .scored) -> TodayScoreFacts {
    TodayScoreFacts(day: day, today: today, scoringState: state, prior: prior, trackers: trackers, devicesSetup: flag)
}

private func outcome(_ f: TodayScoreFacts) -> CalibrationOutcome {
    let p = TodayPresentation.decide(f)
    return CalibrationOutcome(row: p.row, gauge: p.gauge, note: p.note, tilesCalibrating: p.tiles.calibrating,
                   showsDelta: p.showsDelta,
                   widget: ReadinessSnapshot.make(day: f.day, presentation: p, now: Date(timeIntervalSince1970: 1_792_650_000))?.kind)
}

// MARK: - the decision table

@Suite("Today: the calibration decision (design.md §7 rev. 2 §6)")
struct TodayCalibrationDecisionTests {
    private static func s1(_ nights: Int) -> CalibrationOutcome {
        CalibrationOutcome(row: .calibrating, gauge: .baselines(nights: nights), note: nil, tilesCalibrating: true, widget: .calibrating)
    }
    private static func s2(_ readiness: Int, nights: Int, _ signals: [CalibrationSignal]) -> CalibrationOutcome {
        CalibrationOutcome(row: .calibrating, gauge: .readiness(readiness),
                note: .learning(CalibrationProgress(nights: nights, signals: signals)), widget: .score)
    }
    private static func n1(_ readiness: Int, _ signals: [CalibrationSignal], _ source: CalibrationBlocker.Source,
                           _ link: CalibrationLink) -> CalibrationOutcome {
        CalibrationOutcome(row: .calibrating, gauge: .readiness(readiness),
                note: .blocked(CalibrationBlocker(signals: signals, source: source, link: link)), widget: .score)
    }

    private static let garminSetup = CalibrationLink.setup(trackerID: "garmin", app: "Garmin Connect")

    static let cases: [CalibrationDecideCase] = [
        // ex 1: H 3, R 5, bd 3, short_history, readiness 80
        CalibrationDecideCase(name: "ex 1, 3 prior days: S1 counts baseline_days",
                   facts: facts(example(1, readiness: 80), prior: prior(3)), expected: s1(3)),
        CalibrationDecideCase(name: "ex 1, 30 prior days: S2 learns both, no delta",
                   facts: facts(example(1, readiness: 80), prior: prior(30)), expected: s2(80, nights: 3, [.hrv, .restingHR])),
        CalibrationDecideCase(name: "ex 1, 30 prior days, no readiness today: S1",
                   facts: facts(example(1), prior: prior(30)), expected: s1(3)),
        // ex 2: nothing yet is calibrating, not a first import
        CalibrationDecideCase(name: "ex 2: S1 baselines(0), not the first import",
                   facts: facts(example(2), prior: []), expected: s1(0)),
        // ex 3: Garmin, no HRV ever; the prior history can't change the answer
        CalibrationDecideCase(name: "ex 3, 30 days without HRV: N1 names Garmin Connect",
                   facts: facts(example(3, readiness: 74, rhr: 52), prior: prior(30), trackers: garmin, flag: true),
                   expected: n1(74, [.hrv], .notShared(app: "Garmin Connect"), garminSetup)),
        CalibrationDecideCase(name: "ex 3, 3 prior days: still N1, never 0 of 7",
                   facts: facts(example(3, readiness: 74, rhr: 52), prior: prior(3), trackers: garmin, flag: true),
                   expected: n1(74, [.hrv], .notShared(app: "Garmin Connect"), garminSetup)),
        CalibrationDecideCase(name: "ex 3, 30 days with vitals: still N1, never recalculating",
                   facts: facts(example(3, readiness: 74, rhr: 52), prior: prior(30, vitals: 30), trackers: garmin, flag: true),
                   expected: n1(74, [.hrv], .notShared(app: "Garmin Connect"), garminSetup)),
        CalibrationDecideCase(name: "ex 3 without a night: N2 empty gauge, widget waits for sleep",
                   facts: facts(example(3, rhr: 52), prior: prior(30), trackers: garmin, flag: true),
                   expected: CalibrationOutcome(row: .calibrating, gauge: .readiness(nil),
                                     note: .blocked(CalibrationBlocker(signals: [.hrv], source: .notShared(app: "Garmin Connect"),
                                                                       link: garminSetup)),
                                     widget: .waitingForSleep)),
        // ex 4 / 5: a signal just appeared
        CalibrationDecideCase(name: "ex 4, first HRV morning: S2 learns HRV",
                   facts: facts(example(4, readiness: 78), prior: prior(30)), expected: s2(78, nights: 0, [.hrv])),
        CalibrationDecideCase(name: "ex 5, first resting-HR morning: S2 learns resting HR",
                   facts: facts(example(5, readiness: 78), prior: prior(30)), expected: s2(78, nights: 0, [.restingHR])),
        // ex 6: no resting HR although the tracker should send it
        CalibrationDecideCase(name: "ex 6, Garmin without resting HR: N1 unexpected, Check sync",
                   facts: facts(example(6, readiness: 70, hrv: 45), prior: prior(30), trackers: garmin, flag: true),
                   expected: n1(70, [.restingHR], .unexpected, .checkSync)),
        // ex 7: just an iPhone, neither signal
        CalibrationDecideCase(name: "ex 7, iPhone only: N1 names both, phone only",
                   facts: facts(example(7, readiness: 60), prior: prior(30), trackers: [MockData.tracker("iphone")], flag: true),
                   expected: n1(60, [.hrv, .restingHR], .phoneOnly, .devices)),
        // ex 8: calibrated, a delta is allowed
        CalibrationDecideCase(name: "ex 8, not calibrating: A with a delta",
                   facts: facts(example(8, readiness: 77, hrv: 50, rhr: 51), prior: prior(30, vitals: 30)),
                   expected: CalibrationOutcome(row: .scored, gauge: .readiness(77), note: nil, showsDelta: true, widget: .score)),
        // path L: no reason on a calibrating row, as before the field
        CalibrationDecideCase(name: "legacy, 30 days with vitals: D recalculating",
                   facts: facts(legacyToday(), prior: prior(30, vitals: 30)),
                   expected: CalibrationOutcome(row: .recalculating, gauge: .readiness(70), note: .recalculating, widget: .score)),
        CalibrationDecideCase(name: "legacy, 30 days without vitals: B needs vitals",
                   facts: facts(legacyToday(), prior: prior(30)),
                   expected: CalibrationOutcome(row: .calibrating, gauge: .readiness(70), note: .needsVitals, widget: .score)),
        CalibrationDecideCase(name: "legacy, 3 prior days: B short, baselines",
                   facts: facts(legacyToday(), prior: prior(3)), expected: s1(0)),
        // guards
        CalibrationDecideCase(name: "guard: calibrating false with no_hrv is row A",
                   facts: facts(notCalibrating(.noHrv), prior: prior(30)),
                   expected: CalibrationOutcome(row: .scored, gauge: .readiness(74), note: nil, showsDelta: true, widget: .score)),
        CalibrationDecideCase(name: "guard: pending with no_hrv and no readiness is row C",
                   facts: facts(pendingToday(), prior: prior(30), state: .pending),
                   expected: CalibrationOutcome(row: .pending, gauge: nil, note: nil, widget: .pending)),
        CalibrationDecideCase(name: "guard: the placeholder with no_hrv and history is row C",
                   facts: facts(placeholder(), prior: prior(30), state: nil),
                   expected: CalibrationOutcome(row: .pending, gauge: nil, note: nil, widget: .waitingForSleep)),
        CalibrationDecideCase(name: "guard: the placeholder with no_hrv and no history is the first import",
                   facts: facts(placeholder(), prior: [], state: nil),
                   expected: CalibrationOutcome(row: .firstImport, gauge: .firstImport, note: nil, widget: nil)),
    ]

    private static func legacyToday() -> DailyScore {
        DailyScore(day: day, readiness: 70, state: .calibrating, recovery: 68, strain: 5, baselineDays: 0, calibrating: true,
                   computedAt: Date(timeIntervalSince1970: 1_792_650_000), scoringState: .scored)
    }
    private static func notCalibrating(_ reason: CalibratingReason) -> DailyScore {
        DailyScore(day: day, readiness: 74, state: .balanced, recovery: 72, strain: 5, baselineDays: 30, calibrating: false,
                   computedAt: Date(timeIntervalSince1970: 1_792_650_000), scoringState: .scored,
                   baselineHrvDays: 0, baselineRhrDays: 24, calibratingReason: reason)
    }
    private static func pendingToday() -> DailyScore {
        DailyScore(day: day, baselineDays: 0, calibrating: true, scoringState: .pending,
                   baselineHrvDays: 0, baselineRhrDays: 24, calibratingReason: .noHrv)
    }
    private static func placeholder() -> DailyScore {
        DailyScore(day: day, state: .calibrating, baselineDays: 0, calibrating: false,
                   baselineHrvDays: 0, baselineRhrDays: 24, calibratingReason: .noHrv)
    }

    @Test func theExamplesAreAllThere() {
        #expect(examples.count == 8)
    }

    @Test("decide", arguments: cases)
    func decides(_ c: CalibrationDecideCase) {
        let got = outcome(c.facts)
        var want = c.expected
        // A guard that only names the row doesn't pin the gauge's payload.
        if want.gauge == nil { want.gauge = got.gauge }
        #expect(got == want)
        if c.expected.gauge == nil {
            if case .pending = got.gauge {} else { Issue.record("expected the pending gauge, got \(String(describing: got.gauge))") }
        }
    }

    // MARK: invariants

    /// The N rows: the widget never shows "n of 7" for a baseline waiting can't fill.
    @Test("an N row never reaches the widget as a counter", arguments: cases.filter { c in
        if case .blocked? = c.expected.note { return true } else { return false }
    })
    func blockedRowsAreNeverACalibratingWidget(_ c: CalibrationDecideCase) throws {
        let p = TodayPresentation.decide(c.facts)
        let snapshot = try #require(ReadinessSnapshot.make(day: day, presentation: p, now: Date(timeIntervalSince1970: 1_792_650_000)))
        #expect(snapshot.kind != .calibrating && snapshot.baselineNights == nil)
        // The same rows with `devices.setup` off: the note loses its names, the widget doesn't change.
        var off = c.facts
        off.devicesSetup = false
        off.trackers = []
        let q = TodayPresentation.decide(off)
        #expect(ReadinessSnapshot.make(day: day, presentation: q, now: Date(timeIntervalSince1970: 1_792_650_000))?.kind == snapshot.kind)
    }

    @Test("no_* rows never say nights to go", arguments: [(0, 74 as Int?), (0, nil), (3, 74), (6, nil), (24, 70)])
    func noReasonRowsNeverCountNights(_ days: Int, _ readiness: Int?) {
        for reason in [CalibratingReason.noHrv, .noRhr] {
            let row = DailyScore(day: day, readiness: readiness, state: .calibrating, baselineDays: days, calibrating: true,
                                 computedAt: Date(timeIntervalSince1970: 1_792_650_000), scoringState: .scored,
                                 baselineHrvDays: days, baselineRhrDays: 24, calibratingReason: reason)
            let sentence = ReadinessCopy.sentence(score: row)
            #expect(!sentence.contains("nights to go"), "\(sentence)")
            #expect(sentence != ReadinessCopy.sentence(for: .calibrating, nightsToGo: row.nightsToGo))
            #expect(!sentence.hasDigit, "\(sentence)")
        }
        // The legacy row keeps its counter.
        let legacy = DailyScore(day: day, readiness: readiness, state: .calibrating, baselineDays: days, calibrating: true,
                                computedAt: Date(timeIntervalSince1970: 1_792_650_000), scoringState: .scored)
        #expect(ReadinessCopy.sentence(score: legacy).contains("to go"))
    }

    @Test func theNoNightSentenceAndTheScoredOne() {
        let withNight = DailyScore(day: day, readiness: 74, baselineDays: 0, calibrating: true,
                                   computedAt: Date(timeIntervalSince1970: 1_792_650_000), scoringState: .scored,
                                   baselineHrvDays: 0, baselineRhrDays: 24, calibratingReason: .noHrv)
        #expect(ReadinessCopy.sentence(score: withNight) == "Readiness from the signals that reached RYFT.")
        var noNight = withNight
        noNight.readiness = nil
        #expect(ReadinessCopy.sentence(score: noNight) == "No readiness yet today. It appears once last night has synced.")
    }
}

// MARK: - naming the signal and the tracker

struct CalibrationResolveCase: Sendable, CustomTestStringConvertible {
    let name: String
    let signals: [CalibrationSignal]
    let trackers: [String]
    var flag = true
    let source: CalibrationBlocker.Source
    let link: CalibrationLink?
    var testDescription: String { name }
}

@Suite("Today: naming the missing signal and the tracker (§2)")
struct CalibrationBlockerResolveTests {
    private static let hrv: [CalibrationSignal] = [.hrv]
    private static let both: [CalibrationSignal] = [.hrv, .restingHR]
    private static func setup(_ id: String, _ app: String) -> CalibrationLink { .setup(trackerID: id, app: app) }

    static let cases: [CalibrationResolveCase] = [
        CalibrationResolveCase(name: "flag off: unknown, no link", signals: hrv, trackers: ["garmin"], flag: false, source: .unknown, link: nil),
        CalibrationResolveCase(name: "nothing chosen: unknown, devices", signals: hrv, trackers: [], source: .unknown, link: .devices),
        CalibrationResolveCase(name: "garmin, hrv: not shared", signals: hrv, trackers: ["garmin"],
                    source: .notShared(app: "Garmin Connect"), link: setup("garmin", "Garmin Connect")),
        CalibrationResolveCase(name: "fitbit, hrv: named Google Health", signals: hrv, trackers: ["fitbit"],
                    source: .notShared(app: "Google Health"), link: setup("fitbit", "Google Health")),
        CalibrationResolveCase(name: "oura, hrv and resting HR: not shared", signals: both, trackers: ["oura"],
                    source: .notShared(app: "Oura"), link: setup("oura", "Oura")),
        CalibrationResolveCase(name: "garmin, hrv and resting HR: resting HR is yes, unexpected", signals: both, trackers: ["garmin"],
                    source: .unexpected, link: .checkSync),
        CalibrationResolveCase(name: "garmin, resting HR: unexpected", signals: [.restingHR], trackers: ["garmin"],
                    source: .unexpected, link: .checkSync),
        CalibrationResolveCase(name: "apple watch, hrv: unexpected", signals: hrv, trackers: ["apple_watch"], source: .unexpected, link: .checkSync),
        CalibrationResolveCase(name: "garmin and apple watch, hrv: unexpected", signals: hrv, trackers: ["garmin", "apple_watch"],
                    source: .unexpected, link: .checkSync),
        CalibrationResolveCase(name: "amazfit (partial), hrv: unexpected", signals: hrv, trackers: ["amazfit"], source: .unexpected, link: .checkSync),
        CalibrationResolveCase(name: "garmin and oura, hrv: several stay generic", signals: hrv, trackers: ["garmin", "oura"],
                    source: .unknown, link: .devices),
        CalibrationResolveCase(name: "suunto (unverified), hrv: generic", signals: hrv, trackers: ["suunto"], source: .unknown, link: .devices),
        CalibrationResolveCase(name: "samsung (no app of its own), hrv: generic", signals: hrv, trackers: ["samsung_galaxy_watch"],
                    source: .unknown, link: .devices),
        CalibrationResolveCase(name: "iphone, hrv: phone only", signals: hrv, trackers: ["iphone"], source: .phoneOnly, link: .devices),
    ]

    private static func resolved(_ c: CalibrationResolveCase) -> CalibrationBlocker {
        CalibrationBlocker.resolve(c.signals, trackers: c.trackers.map { MockData.tracker($0) }, devicesSetup: c.flag)
    }

    @Test("resolve", arguments: cases)
    func resolves(_ c: CalibrationResolveCase) {
        let got = Self.resolved(c)
        #expect(got == CalibrationBlocker(signals: c.signals, source: c.source, link: c.link))
    }

    @Test("a blocked note has no digit", arguments: cases)
    func noteHasNoDigit(_ c: CalibrationResolveCase) {
        let text = Self.resolved(c).text
        #expect(!text.isEmpty && !text.hasDigit, "\(text)")
    }

    @Test func theNoteNamesTheAppAsADataSource() {
        let garminNote = CalibrationBlocker(signals: [.hrv], source: .notShared(app: "Garmin Connect"), link: nil).text
        #expect(garminNote == "Garmin Connect doesn't share HRV with Apple Health.")
        #expect(CalibrationBlocker(signals: [.hrv], source: .phoneOnly, link: nil).text
                == "An iPhone on its own doesn't record HRV.")
        #expect(CalibrationBlocker(signals: [.hrv], source: .unknown, link: nil).text
                == "No HRV has reached RYFT from your nights.")
    }

    @Test func linkTitlesSayWhereTheyGo() {
        #expect(CalibrationLink.setup(trackerID: "garmin", app: "Garmin Connect").title == "How to set up Garmin Connect")
        #expect(CalibrationLink.checkSync.title == "Check sync")
        #expect(CalibrationLink.devices.title == "Devices & sync")
    }
}

// MARK: - the band word

/// S2, N1 and N2 take the band word's place with the note: under the gauge and on the Recovery tile. Row A and
/// path L keep it. Pinned so a change is deliberate.
@Suite("Today: the band word under a calibration note")
struct CalibrationBandWordTests {
    private static let now = (DayFormat.date(from: day) ?? .distantPast).addingTimeInterval(7.5 * 3_600)

    struct BandCase: Sendable, CustomTestStringConvertible {
        let name: String
        let today: DailyScore
        let prior: [DailyScore]
        let keepsBand: Bool
        var testDescription: String { name }
    }

    private static let cases: [BandCase] = [
        BandCase(name: "S2 hides it", today: example(4, readiness: 78), prior: prior(30), keepsBand: false),
        BandCase(name: "N1 hides it", today: example(3, readiness: 74, rhr: 52), prior: prior(30), keepsBand: false),
        BandCase(name: "N2 hides it (no readiness)", today: example(3, rhr: 52), prior: prior(30), keepsBand: false),
        BandCase(name: "S1 shows the baselines gauge", today: example(1, readiness: 80), prior: prior(3), keepsBand: true),
        BandCase(name: "row A keeps it", today: example(8, readiness: 77, hrv: 50, rhr: 51), prior: prior(30, vitals: 30), keepsBand: true),
        BandCase(name: "L (needs vitals) keeps it",
                 today: DailyScore(day: day, readiness: 70, recovery: 68, baselineDays: 0, calibrating: true,
                                   computedAt: Date(timeIntervalSince1970: 1_792_650_000), scoringState: .scored),
                 prior: prior(30), keepsBand: true),
    ]

    @MainActor @Test("band word", arguments: cases)
    func bandWord(_ c: BandCase) {
        var f = TodaySyncFacts(now: Self.now)
        f.today = c.today
        f.prior = c.prior
        f.hasScoredDay = true
        f.devicesSetup = true
        f.trackers = garmin
        let p = TodayPresentation.decide(f.scores)
        let content = TodayContent(facts: f, presentation: p, hero: TodayStates.hero(f, presentation: p), hasDataSource: true,
                                   readinessWeek: [], detailSleepMin: nil)
        #expect(content.showsReadinessBand == c.keepsBand)
        if c.today.readiness != nil, p.gauge != .baselines(nights: c.today.baselineDays) {
            #expect((content.recoveryBand != nil) == c.keepsBand, "Recovery's band word follows the gauge's")
        }
    }
}

private extension String {
    var hasDigit: Bool { contains { $0.isNumber } }
}
