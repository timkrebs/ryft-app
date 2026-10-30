// What the readiness widget shows, written into the App Group container by the app and read by the widget: one
// source for both (ADR 0010). The app's half (`make`, `publish`, `clear`, the coders) is an extension in
// `Ryft/Persistence/Repository.swift`; the widget's previews are in `RyftWidgets/ReadinessWidget.swift`.
//
// COMPATIBILITY: an app update and a widget reload don't happen together, and the file outlives both. Only add
// optional keys (a missing one decodes as nil); a breaking change takes a new key or file name, because a failed
// decode shows "Open RYFT".
import Foundation

struct ReadinessSnapshot: Codable, Equatable {
    enum Kind: String, Codable {
        /// Today's readiness.
        case score
        /// The night is being scored.
        case pending
        /// No night has arrived for today.
        case waitingForSleep
        /// Fewer than 7 nights behind the baselines.
        case calibrating
    }

    /// The orbit's scores of the day the tiles show: today's; the latest scored day's while pending or waiting
    /// (the day `previousReadiness` is from). In the platform's numbers; `OrbitGaugeValues` makes them fractions.
    struct Orbit: Codable, Equatable {
        /// 0–100; nil while withheld beside the baselines counter (`Tiles.withholdsRecovery`) or unscored.
        var recovery: Int?
        /// `sleep_performance`, 0–100.
        var sleepPerformance: Int?
        /// 0–21.
        var strain: Double?
        /// With `baselineNights`: what the count counts.
        var counted: OrbitGaugeCalibration.Signal?

        init(recovery: Int? = nil, sleepPerformance: Int? = nil, strain: Double? = nil,
             counted: OrbitGaugeCalibration.Signal? = nil) {
            self.recovery = recovery
            self.sleepPerformance = sleepPerformance
            self.strain = strain
            self.counted = counted
        }

        /// A signal a later app adds decodes as nil here (an older widget), never as a failed snapshot.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            recovery = try c.decodeIfPresent(Int.self, forKey: .recovery)
            sleepPerformance = try c.decodeIfPresent(Int.self, forKey: .sleepPerformance)
            strain = try c.decodeIfPresent(Double.self, forKey: .strain)
            counted = try? c.decodeIfPresent(OrbitGaugeCalibration.Signal.self, forKey: .counted)
        }
    }

    /// The day it's about, `yyyy-MM-dd`; another day on the widget is "waiting for sleep".
    var day: String
    var kind: Kind
    var readiness: Int?
    /// The latest readiness before `day`, dimmed while the night isn't scored.
    var previousReadiness: Int?
    /// While calibrating; with `.score`, the count of baselines still learning beside the readiness (S2).
    var baselineNights: Int?
    var updatedAt: Date
    /// Tonight's bedtime (Bedtime & wake): "Bed by 22:41" in the evening.
    var bedtime: Date?
    /// The orbit's scores. Absent in a file written before the orbit: `gauge` is then unknown and the widget draws
    /// the tracks only until the app writes again (never hollow dots, which would say "missing").
    var orbit: Orbit?

    static let appGroup = "group.dev.timkrebs.ryft"
    static let widgetKind = "ReadinessWidget"
    static let baselineNightsRequired = 7

    static var sharedFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("readiness.json")
    }

    /// What the app last wrote; `nil` without one (or without the App Group).
    static func load(from file: URL? = sharedFile) -> ReadinessSnapshot? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ReadinessSnapshot.self, from: data)
    }

    /// As of `date`: a snapshot of an earlier day is no score for today. Its readiness becomes the dimmed one, and
    /// the night is awaited. The orbit goes along when it is that readiness's day (not a calibrating day's).
    func asOf(_ date: Date) -> ReadinessSnapshot {
        guard day != Self.dayString(date) else { return self }
        let previous = readiness ?? previousReadiness
        let orbitOfPrevious = readiness != nil || kind == .pending || kind == .waitingForSleep
        return ReadinessSnapshot(day: Self.dayString(date), kind: .waitingForSleep, readiness: nil,
                                 previousReadiness: previous, baselineNights: nil, updatedAt: updatedAt, bedtime: nil,
                                 orbit: orbitOfPrevious ? orbit.map { Orbit(recovery: $0.recovery, sleepPerformance: $0.sleepPerformance,
                                                                            strain: $0.strain) } : nil)
    }

    /// The orbit this snapshot draws, as the app's `OrbitGaugeMode(TodayPresentation)` decides it for the same day.
    /// `nil`: unknown (a file from before the orbit, with a score): tracks only.
    var gauge: OrbitGaugeMode? {
        switch kind {
        case .score:
            guard let orbit else { return nil }
            return .scored(values(readiness: readiness, orbit), learning: baselineNights.map(calibration))
        case .calibrating:
            return .calibrating(calibration(nights: baselineNights ?? 0))
        case .pending, .waitingForSleep:
            // The latest scored day always has a readiness (`TodayPresentation.decide`'s `latestPrior`). Without the
            // orbit (an older file, or a calibrating day's turned over) its scores are unknown: no previous drawing.
            return .pending(previous: orbit.flatMap { o in previousReadiness.map { values(readiness: $0, o) } })
        }
    }

    private func values(readiness: Int?, _ orbit: Orbit) -> OrbitGaugeValues {
        OrbitGaugeValues(readiness: readiness, recoveryScore: orbit.recovery, sleepPerformance: orbit.sleepPerformance,
                         strain: orbit.strain)
    }

    private func calibration(nights: Int) -> OrbitGaugeCalibration {
        OrbitGaugeCalibration(nights: nights, required: Self.baselineNightsRequired, signal: orbit?.counted ?? .anyNight)
    }

    /// What VoiceOver may say about a snapshot, decided without words (each target's catalog has those): on a locked
    /// device (`redacted`, the widget's `.privacy` redaction) only the widget's name, never a value.
    enum Speech: Equatable {
        /// Locked: "Readiness".
        case name
        /// No snapshot: "Open RYFT to see your readiness."
        case openApp
        /// Today's readiness and, when known, the orbit's scores.
        case score(readiness: Int?, values: OrbitGaugeValues?)
        /// A night pending or awaited, with the latest readiness.
        case night(Kind, previous: Int?)
        /// The baselines counting.
        case baselines(nights: Int, required: Int)
    }

    static func speech(_ s: ReadinessSnapshot?, redacted: Bool) -> Speech {
        if redacted { return .name }
        guard let s else { return .openApp }
        switch s.kind {
        case .score: return .score(readiness: s.readiness, values: s.gauge?.scoredValues)
        case .pending, .waitingForSleep: return .night(s.kind, previous: s.previousReadiness)
        case .calibrating: return .baselines(nights: s.baselineNights ?? 0, required: baselineNightsRequired)
        }
    }

    /// The widget's text slots, decided without words. On a locked device each slot is one constant whatever the
    /// state: a redacted placeholder keeps its text's width, so "Moderate" vs "High", "100" vs "71" or "Scoring your
    /// night…" vs a band word would show through, and a bedtime line by being there at all.
    enum TextSlot: Equatable {
        /// Locked: the slot's constant placeholder.
        case locked
        /// Today's readiness, beside or inside the orbit.
        case number(Int)
        /// The band word of a readiness.
        case band(Int)
        /// What the snapshot's kind says ("Scoring your night…", "Baselines 3 of 7"; `nil`: "Open RYFT …").
        case status(Kind?)
        /// "Bed by 22:41".
        case bedtime(Date)
        /// Nothing in this slot.
        case none
    }

    /// The number: today's readiness for a score.
    static func numberSlot(_ s: ReadinessSnapshot?, redacted: Bool) -> TextSlot {
        if redacted { return .locked }
        guard let s, s.kind == .score, let readiness = s.readiness else { return .none }
        return .number(readiness)
    }

    /// The line under the number or the orbit: the band word for a score, else the status.
    static func lineSlot(_ s: ReadinessSnapshot?, redacted: Bool) -> TextSlot {
        if redacted { return .locked }
        if let s, s.kind == .score, let readiness = s.readiness { return .band(readiness) }
        return .status(s?.kind)
    }

    /// Tonight's bedtime (`bedtimeShown(at:)`); never on a locked device, so its line can't give one away.
    static func bedtimeSlot(_ bedtime: Date?, redacted: Bool) -> TextSlot {
        guard !redacted, let bedtime else { return .none }
        return .bedtime(bedtime)
    }

    /// "Bed by 22:41" from 17:00 the evening before until bedtime (00:30 too).
    func bedtimeShown(at date: Date, calendar: Calendar = .current) -> Date? {
        guard let bedtime, bedtime > date,
              let evening = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: bedtime.addingTimeInterval(-12 * 3_600)),
              date >= evening else { return nil }
        return bedtime
    }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
