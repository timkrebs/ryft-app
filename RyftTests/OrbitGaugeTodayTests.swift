import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

// OrbitGauge PR 1 (architecture.md §2, §3): Today's one mapping to the orbit, the widget's snapshot carrying the
// same mode through JSON, and a snapshot from before the orbit. Synthetic values only (71 / 71 % / 88 % / 9.6);
// fixed dates, no clock.

private let day = "2026-10-22"
private let computed = Date(timeIntervalSince1970: 1_792_650_000)

/// A settled row (A) with the four scores.
private func scored(readiness: Int? = 71, recovery: Int? = 71, sleep: Int? = 88, strain: Double? = 9.6,
                    on key: String = day) -> DailyScore {
    DailyScore(day: key, readiness: readiness, state: .balanced, recovery: recovery, strain: strain, sleepPerformance: sleep,
               sleepActualMin: 430, hrvMs: 52, rhr: 51, baselineDays: 30, calibrating: false, computedAt: computed,
               scoringState: .scored)
}

/// `count` scored days before `day`, oldest first; the newest at readiness 64 (62 / 55 % / 14). `vitals`: with HRV and
/// resting HR (else path L's long history without them).
private func prior(_ count: Int = 30, vitals: Bool = true) -> [DailyScore] {
    guard count > 0, let today = DayFormat.date(from: day) else { return [] }
    return (1...count).reversed().map { offset in
        let key = DayFormat.string(from: DayFormat.shift(today, days: -offset))
        let newest = offset == 1
        return DailyScore(day: key, readiness: newest ? 64 : 70, recovery: newest ? 62 : 66, strain: newest ? 14 : 8,
                          sleepPerformance: newest ? 55 : 80, hrvMs: vitals ? 48 : nil, rhr: vitals ? 52 : nil,
                          baselineDays: 30, calibrating: false, computedAt: computed, scoringState: .scored)
    }
}

/// A `short_history` row (S1 / S2 / F3).
private func shortHistory(readiness: Int?, h: Int, r: Int) -> DailyScore {
    let night = readiness != nil
    return DailyScore(day: day, readiness: readiness, state: .calibrating, recovery: readiness, strain: 6.8,
                      sleepPerformance: night ? 81 : nil, sleepActualMin: night ? 410 : nil, rhr: night ? 53 : nil,
                      baselineDays: min(h, r), calibrating: true, computedAt: computed, scoringState: .scored,
                      baselineHrvDays: h, baselineRhrDays: r, calibratingReason: .shortHistory)
}

private func facts(_ today: DailyScore?, prior: [DailyScore] = prior(), state: ScoringState? = .scored,
                   trackers: [String] = [], flag: Bool = false) -> TodayScoreFacts {
    TodayScoreFacts(day: day, today: today, scoringState: state, prior: prior,
                    trackers: trackers.map { MockData.tracker($0) }, devicesSetup: flag)
}

private func mode(_ f: TodayScoreFacts) -> OrbitGaugeMode { OrbitGaugeMode(TodayPresentation.decide(f)) }

/// The snapshot as the widget reads it: written by `make`, encoded and decoded with the shared coders.
private func throughJSON(_ f: TodayScoreFacts) throws -> ReadinessSnapshot? {
    guard let s = ReadinessSnapshot.make(day: f.day, presentation: .decide(f), now: computed) else { return nil }
    return try ReadinessSnapshot.decoder.decode(ReadinessSnapshot.self, from: ReadinessSnapshot.encoder.encode(s))
}

struct OrbitParityCase: Sendable, CustomTestStringConvertible {
    let name: String
    let facts: TodayScoreFacts
    var testDescription: String { name }
}

// MARK: - Today's mapping

@Suite("OrbitGauge: Today's mapping (architecture.md §3)")
struct OrbitGaugeTodayMappingTests {
    @Test func aScoredDayIsTheFourScores() {
        #expect(mode(facts(scored())) == .scored(OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)))
    }

    @Test func aMissingSubScoreIsNilNeverZero() {
        let noSleep = mode(facts(scored(sleep: nil)))
        #expect(noSleep == .scored(OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: nil, strain: 9.6)))
        let noStrain = mode(facts(scored(strain: nil)))
        #expect(noStrain.scoredValues?.strain == nil && noStrain.scoredValues?.sleep == 0.88)
        // Zero is a score: a filled dot at the start, not a hollow one.
        #expect(mode(facts(scored(recovery: 0))).scoredValues?.recovery == 0)
    }

    @Test func readinessZeroAndHundredAreTheirOwnNumbers() {
        let zero = mode(facts(scored(readiness: 0, recovery: 0, sleep: 0, strain: 0)))
        #expect(zero == .scored(OrbitGaugeValues(readiness: 0, recovery: 0, sleep: 0, strain: 0)))
        let hundred = mode(facts(scored(readiness: 100, recovery: 100, sleep: 100, strain: 21)))
        #expect(hundred == .scored(OrbitGaugeValues(readiness: 100, recovery: 1, sleep: 1, strain: 21)))
        #expect(hundred.scoredValues?.strainFraction == 1)
    }

    @Test func theCountedSignalGoesWithTheBaselines() {
        // S1, a new account: any night with what a baseline needs.
        #expect(mode(facts(shortHistory(readiness: nil, h: 3, r: 3), prior: prior(3)))
                == .calibrating(OrbitGaugeCalibration(nights: 3, signal: .anyNight)))
        // F3: no HRV, resting heart rate on 3 nights: those are counted.
        #expect(mode(facts(shortHistory(readiness: nil, h: 0, r: 3), prior: prior(4, vitals: false)))
                == .calibrating(OrbitGaugeCalibration(nights: 3, signal: .restingHR)))
        // S2: the same count beside the platform's readiness.
        let s2 = mode(facts(shortHistory(readiness: 71, h: 0, r: 3), prior: prior(4, vitals: false)))
        #expect(s2.scoredValues?.readiness == 71)
        #expect(s2.calibration == OrbitGaugeCalibration(nights: 3, signal: .restingHR))
        // Path L over a long history without the watch: the heart-rate nights.
        var legacy = shortHistory(readiness: nil, h: 0, r: 0)
        legacy.calibratingReason = nil
        #expect(mode(facts(legacy, prior: prior(30, vitals: false))) == .calibrating(OrbitGaugeCalibration(nights: 0, signal: .heartRateNights)))
    }

    @Test func aNightBeingScoredCarriesTheLatestScoredDay() {
        let pending = mode(facts(nil, state: .pending))
        #expect(pending == .pending(previous: OrbitGaugeValues(readiness: 64, recovery: 0.62, sleep: 0.55, strain: 14)))
        #expect(mode(facts(nil, prior: [], state: .pending)) == .pending(previous: nil))
    }

    @Test func nothingScoredIsTheEmptyOrbit() {
        #expect(mode(facts(nil, prior: [], state: nil)) == .scored(.empty))
    }

    /// Today's `.score` hero reads the same mode as the widget's snapshot is made from.
    @Test func todayContentDrawsTheMapping() throws {
        // Local noon on `day`, after the import.
        var f = TodaySyncFacts(now: try #require(DayFormat.date(from: day)).addingTimeInterval(12 * 3_600), today: scored())
        f.hasScoredDay = true
        f.engine.backfillDone = true
        let p = TodayPresentation.decide(f.scores)
        let content = TodayContent(facts: f, presentation: p, hero: TodayStates.hero(f, presentation: p), hasDataSource: true,
                                   readinessWeek: [], detailSleepMin: nil)
        #expect(content.hero == .score)
        #expect(content.orbit == OrbitGaugeMode(p))
        #expect(content.orbit.scoredValues == OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6))
    }

    @Test func theSpokenValueFollowsTheCaption() {
        let v = OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)
        #expect(OrbitGauge.spokenValue(v).hasPrefix("71, High. Recovery 71 percent"))
        // Where a calibration note takes the band word's line (S2, N1), VoiceOver doesn't read it either.
        #expect(OrbitGauge.spokenValue(v, showsBand: false).hasPrefix("71. Recovery 71 percent"))
        let up = MetricDelta(current: 71, reference: 67)
        #expect(OrbitGauge.spokenValue(v, delta: up).hasPrefix("71, High, Up 4 vs 7 d. Recovery"))
    }
}

// MARK: - the widget's snapshot

@Suite("OrbitGauge: the widget draws Today's mode (architecture.md §2)")
struct OrbitGaugeSnapshotParityTests {
    static let cases: [OrbitParityCase] = {
        var c: [OrbitParityCase] = [
            OrbitParityCase(name: "A", facts: facts(scored())),
            OrbitParityCase(name: "A, no sleep performance", facts: facts(scored(sleep: nil))),
            OrbitParityCase(name: "A, no strain", facts: facts(scored(strain: nil))),
            OrbitParityCase(name: "A, readiness 0", facts: facts(scored(readiness: 0, recovery: 0, sleep: 0, strain: 0))),
            OrbitParityCase(name: "A, readiness 100", facts: facts(scored(readiness: 100, recovery: 100, sleep: 100, strain: 21))),
            OrbitParityCase(name: "S1", facts: facts(shortHistory(readiness: nil, h: 3, r: 3), prior: prior(3))),
            OrbitParityCase(name: "S1 counting resting HR", facts: facts(shortHistory(readiness: nil, h: 0, r: 3), prior: prior(4, vitals: false))),
            OrbitParityCase(name: "S2", facts: facts(shortHistory(readiness: 71, h: 3, r: 3), prior: prior(3))),
            OrbitParityCase(name: "S2 resting HR", facts: facts(shortHistory(readiness: 71, h: 0, r: 3), prior: prior(4, vitals: false))),
            OrbitParityCase(name: "N1 early (Garmin)", facts: facts(shortHistory(readiness: 71, h: 0, r: 3), prior: prior(4, vitals: false),
                                                                     trackers: ["garmin"], flag: true)),
            OrbitParityCase(name: "C pending", facts: facts(nil, state: .pending)),
            OrbitParityCase(name: "C waiting for sleep", facts: facts(nil, state: .waitingForSleep)),
            OrbitParityCase(name: "C, nothing before", facts: facts(nil, prior: [], state: .pending)),
            OrbitParityCase(name: "E", facts: facts(nil, prior: [], state: nil)),
        ]
        var noReason = scored()
        noReason.calibrating = true
        noReason.baselineDays = 0
        c.append(OrbitParityCase(name: "D, today's readiness", facts: facts(noReason)))
        c.append(OrbitParityCase(name: "L-B + r", facts: facts(noReason, prior: prior(30, vitals: false))))
        var noReasonNoReadiness = shortHistory(readiness: nil, h: 0, r: 0)
        noReasonNoReadiness.calibratingReason = nil
        c.append(OrbitParityCase(name: "D from yesterday", facts: facts(noReasonNoReadiness)))
        c.append(OrbitParityCase(name: "L-B long", facts: facts(noReasonNoReadiness, prior: prior(30, vitals: false))))
        // N2: `no_hrv` and no night, so no readiness; the empty gauge on Today, the night awaited on the widget.
        let n2 = DailyScore(day: day, state: .calibrating, strain: 4.2, baselineDays: 0, calibrating: true, computedAt: computed,
                            scoringState: .scored, baselineHrvDays: 0, baselineRhrDays: 24, calibratingReason: .noHrv)
        c.append(OrbitParityCase(name: "N2", facts: facts(n2)))
        // A settled day the platform scored without a readiness (not calibrating, not scoring).
        c.append(OrbitParityCase(name: "A, scored without a readiness", facts: facts(scored(readiness: nil))))
        // Every demo scenario behind the previews, over a scored day.
        let now = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: computed) ?? computed
        for scenario in TodayScenario.allCases {
            let base = TodaySyncFacts(now: now, today: scored(on: DayFormat.string(from: now)))
            c.append(OrbitParityCase(name: "scenario \(scenario.rawValue)", facts: scenario.apply(to: base).scores))
        }
        return c
    }()

    /// The parity test (architecture.md §3): the widget's mode from the JSON is Today's, for every row. The one
    /// difference by design: a readiness gauge without today's readiness (row D from an earlier day, N2 and a scored day
    /// without a readiness) is "waiting for last night" there, with the latest readiness dimmed. Any other readiness
    /// gauge is the widget's score.
    @Test(arguments: cases) func theWidgetsModeIsTodays(_ c: OrbitParityCase) throws {
        let p = TodayPresentation.decide(c.facts)
        let today = OrbitGaugeMode(p)
        guard let widget = try throughJSON(c.facts) else {
            #expect(p.row == .firstImport, "only the first import has no snapshot")
            return
        }
        if case .readiness(let readiness) = p.gauge {
            if readiness == nil || p.tiles.isEarlierDay {
                #expect(widget.kind == .waitingForSleep)
                #expect(widget.previousReadiness == p.previousReadiness)
                return
            }
            #expect(widget.kind == .score)
        }
        #expect(widget.gauge == today)
        // And the values the gauge is drawn from, one by one.
        #expect(widget.gauge?.scoredValues == today.scoredValues)
        #expect(widget.gauge?.calibration == today.calibration)
    }

    @Test func theScenariosCoverEveryMode() throws {
        var kinds = Set<String>()
        for c in Self.cases {
            switch OrbitGaugeMode(TodayPresentation.decide(c.facts)) {
            case .scored(_, nil): kinds.insert("scored")
            case .scored(_, _?): kinds.insert("scored, learning")
            case .calibrating: kinds.insert("calibrating")
            case .pending: kinds.insert("pending")
            case .assembling: kinds.insert("assembling")
            }
        }
        #expect(kinds == ["scored", "scored, learning", "calibrating", "pending"])
    }

    @Test func theExceptionsAreCovered() throws {
        let names = Set(Self.cases.map(\.name))
        #expect(names.isSuperset(of: ["N2", "A, scored without a readiness", "D from yesterday"]))
        for name in ["N2", "A, scored without a readiness"] {
            let c = try #require(Self.cases.first { $0.name == name })
            #expect(TodayPresentation.decide(c.facts).gauge == .readiness(nil), "\(name)")
            #expect(try throughJSON(c.facts)?.kind == .waitingForSleep, "\(name)")
        }
    }

    /// The counter draws no scores: the snapshot carries only what it counts, so a strain synced meanwhile
    /// doesn't reload the widget.
    @Test func theBaselinesCarryOnlyTheCountedSignal() throws {
        let s = try #require(try throughJSON(facts(shortHistory(readiness: nil, h: 0, r: 3), prior: prior(4, vitals: false))))
        #expect(s.kind == .calibrating && s.baselineNights == 3)
        #expect(s.orbit == ReadinessSnapshot.Orbit(counted: .restingHR))
    }

    /// A signal a later app adds doesn't break an older widget: `counted` decodes as nil, the rest stays.
    @Test func anUnknownCountedSignalDecodesAsNil() throws {
        let json = #"{"day":"2026-10-22","kind":"calibrating","baselineNights":3,"updatedAt":"2026-10-22T07:30:00Z","#
            + #""orbit":{"recovery":71,"strain":9.6,"counted":"spo2"}}"#
        let s = try ReadinessSnapshot.decoder.decode(ReadinessSnapshot.self, from: Data(json.utf8))
        #expect(s.orbit == ReadinessSnapshot.Orbit(recovery: 71, strain: 9.6, counted: nil))
        #expect(s.gauge == .calibrating(OrbitGaugeCalibration(nights: 3)))
    }

    @Test func theSnapshotCarriesThePlatformsNumbers() throws {
        let s = try #require(try throughJSON(facts(scored())))
        #expect(s.kind == .score && s.readiness == 71)
        #expect(s.orbit == ReadinessSnapshot.Orbit(recovery: 71, sleepPerformance: 88, strain: 9.6, counted: nil))
        let json = try #require(try JSONSerialization.jsonObject(with: ReadinessSnapshot.encoder.encode(s)) as? [String: Any])
        let orbit = try #require(json["orbit"] as? [String: Any])
        #expect(orbit["recovery"] as? Int == 71 && orbit["sleepPerformance"] as? Int == 88 && orbit["strain"] as? Double == 9.6)
    }

    @Test func tomorrowTheScoredDayIsThePreviousOne() throws {
        let s = try #require(try throughJSON(facts(scored())))
        let tomorrow = try #require(DayFormat.date(from: day)).addingTimeInterval(36 * 3_600)
        let next = s.asOf(tomorrow)
        #expect(next.kind == .waitingForSleep && next.previousReadiness == 71)
        #expect(next.gauge == .pending(previous: OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)))
        // A calibrating day's orbit isn't the previous readiness's day: no previous drawing.
        let calibrating = try #require(try throughJSON(facts(shortHistory(readiness: nil, h: 3, r: 3), prior: prior(3))))
        #expect(calibrating.asOf(tomorrow).gauge == .pending(previous: nil))
    }
}

// MARK: - a snapshot from before the orbit

@Suite("OrbitGauge: an older snapshot still decodes and draws")
@MainActor
struct OrbitGaugeOldSnapshotTests {
    /// What the app wrote before PR 1 (no `orbit` key), one per kind.
    private func old(_ kind: String, _ extra: String) throws -> ReadinessSnapshot {
        let json = #"{"day":"2026-10-22","kind":"\#(kind)","previousReadiness":64,"updatedAt":"2026-10-22T07:30:00Z"\#(extra)}"#
        return try ReadinessSnapshot.decoder.decode(ReadinessSnapshot.self, from: Data(json.utf8))
    }

    @Test func itDecodesWithTheOrbitUnknown() throws {
        let score = try old("score", #","readiness":71,"bedtime":"2026-10-22T20:41:00Z""#)
        #expect(score.kind == .score && score.readiness == 71 && score.previousReadiness == 64 && score.bedtime != nil)
        #expect(score.orbit == nil)
        // Unknown, not missing: tracks only, never three hollow dots.
        #expect(score.gauge == nil)
        #expect(try old("calibrating", #","baselineNights":3"#).gauge == .calibrating(OrbitGaugeCalibration(nights: 3)))
        #expect(try old("pending", "").gauge == .pending(previous: nil))
        #expect(try old("waitingForSleep", "").gauge == .pending(previous: nil))
    }

    @Test func itRenders() throws {
        let score = try old("score", #","readiness":71"#)
        let renderer = ImageRenderer(content: OrbitGaugeDrawing(mode: score.gauge, size: .small) {
            Text(verbatim: "71")
        })
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(OrbitGaugeSize.small.frame * renderer.scale))
    }

    /// The first publish after the update rewrites it: the orbit counts as what the widget shows.
    @Test func theFirstPublishAfterTheUpdateRewritesIt() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("readiness-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var before = try #require(ReadinessSnapshot.make(day: day, presentation: .decide(facts(scored())), now: computed))
        before.orbit = nil
        try ReadinessSnapshot.encoder.encode(before).write(to: file)
        let after = try #require(ReadinessSnapshot.make(day: day, presentation: .decide(facts(scored())), now: computed))
        #expect(ReadinessSnapshot.publish(after, to: file))
        #expect(!ReadinessSnapshot.publish(after, to: file))
        #expect(ReadinessSnapshot.load(from: file)?.orbit != nil)
        // Health scores stay out of device backups.
        #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
}

// MARK: - the drawing

@Suite("OrbitGauge: the shared drawing renders every mode")
@MainActor
struct OrbitGaugeDrawingRenderTests {
    @Test(arguments: [
        OrbitGaugeMode.scored(OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)),
        .scored(.empty), .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, strain: 6.2), learning: OrbitGaugeCalibration(nights: 3)),
        .calibrating(OrbitGaugeCalibration(nights: 3)), .pending(previous: nil), .assembling,
    ])
    func itRenders(_ mode: OrbitGaugeMode) throws {
        for size in [OrbitGaugeSize.small, .medium, .large, .custom(dial: 44)] {
            let renderer = ImageRenderer(content: OrbitGaugeDrawing(mode: mode, size: size))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            #expect(image.width == Int(size.frame) && image.height == Int(size.frame))
        }
    }

    @Test func theBandRuleIsTheAppsRule() {
        // 67 and 34 are the lower bounds (`Theme.band(forScore:)`, `MetricSpec.scoreBand`).
        let p = OrbitGaugePalette.assets
        for (score, expected) in [(100, p.high), (67, p.high), (66, p.moderate), (34, p.moderate), (33, p.low), (0, p.low)] {
            #expect(p.band(forReadiness: score) == expected, "readiness \(score)")
            #expect(Theme.band(forScore: score) == expected, "readiness \(score)")
        }
        #expect(p.band(forReadiness: nil) == p.noReadiness && Theme.band(forScore: nil) == p.noReadiness)
    }
}

// MARK: - the locked widget

@Suite("OrbitGauge: the lock screen hides the values")
struct OrbitGaugeLockedWidgetTests {
    private static let snapshots: [ReadinessSnapshot?] = {
        let make = { (f: TodayScoreFacts) in ReadinessSnapshot.make(day: f.day, presentation: .decide(f), now: computed) }
        return [make(facts(scored())), make(facts(nil, state: .pending)), make(facts(nil, state: .waitingForSleep)),
                make(facts(shortHistory(readiness: nil, h: 3, r: 3), prior: prior(3))), nil]
    }()

    /// Redacted (`.privacy`), VoiceOver says the widget's name and nothing else, whatever the snapshot holds.
    @Test func redactedTheSpeechCarriesNoValues() {
        for s in Self.snapshots {
            #expect(ReadinessSnapshot.speech(s, redacted: true) == .name, "\(String(describing: s?.kind))")
        }
    }

    @Test func unlockedTheSpeechCarriesTheValues() throws {
        let score = try #require(Self.snapshots[0])
        #expect(ReadinessSnapshot.speech(score, redacted: false)
                == .score(readiness: 71, values: OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)))
        #expect(ReadinessSnapshot.speech(Self.snapshots[1], redacted: false) == .night(.pending, previous: 64))
        #expect(ReadinessSnapshot.speech(Self.snapshots[3], redacted: false) == .baselines(nights: 3, required: 7))
        #expect(ReadinessSnapshot.speech(nil, redacted: false) == .openApp)
    }
}

// MARK: - the number fits

/// "100" fits the centre ring at ≥ 0.6 scale, and two digits at full size, at every dial a family uses: the widget's
/// circle (68–76 pt, dial 56–64), its small tile (dial about 77–106 pt) and the app's three sizes.
@Suite("OrbitGauge: the number fits the centre ring")
@MainActor
struct OrbitGaugeNumberFitTests {
    private func width(_ text: String, _ font: Font) -> CGFloat {
        let host = UIHostingController(rootView: Text(verbatim: text).font(font).monospacedDigit().fixedSize())
        return host.sizeThatFits(in: CGSize(width: 1_000, height: 1_000)).width
    }

    @Test(arguments: [56, 60, 64, 77, 92, 106] as [CGFloat])
    func inTheWidget(_ dial: CGFloat) {
        let slot = OrbitGaugeGeometry.metrics(forDial: dial).centreSlotWidth
        // The heavier lock-screen weight is the wider one.
        let font = Font.system(size: OrbitGaugeGeometry.numberPointSize(forDial: dial), weight: .semibold, design: .rounded)
        #expect(width("100", font) * 0.6 <= slot, "dial \(dial)")
        #expect(width("71", font) <= slot + 0.5, "dial \(dial)")
    }

    @Test(arguments: [OrbitGaugeSize.small, .medium, .large])
    func inTheApp(_ size: OrbitGaugeSize) {
        let slot = OrbitGaugeGeometry.metrics(forDial: size.dial).centreSlotWidth
        let font = Font.ryftNumber(size: size.dial * 0.19)
        #expect(width("100", font) * 0.6 <= slot, "\(size)")
        #expect(width("71", font) <= slot, "\(size)")
    }

    @Test func theNumberThresholdIsShared() {
        #expect(OrbitGauge.minDialForNumber == OrbitGaugeGeometry.minDialForNumber)
        #expect(OrbitGaugeGeometry.minDialForNumber == 56)
    }
}
