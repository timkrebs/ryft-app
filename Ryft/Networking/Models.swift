// Wire types. Mirror the v1 API contract (plattform/docs/API.md, and
// backend/internal/model/model.go) — JSON keys are snake_case there; the
// shared decoder's .convertFromSnakeCase strategy maps them (see
// APIClient.jsonDecoder).
//
// Read-side types stay null-tolerant: every score can be null while the
// platform calibrates, and the on-disk cache may predate a field. Views render
// "–" for anything nil. Unknown response fields are ignored (API.md, v1 rule).
import Foundation

// MARK: - Sync (write side)

enum SampleType: String, Codable, CaseIterable, Sendable {
    case heartRate = "heart_rate"
    case hrvSDNN = "hrv_sdnn"
    case restingHR = "resting_hr"
    case respiratoryRate = "respiratory_rate"
    case spo2 = "spo2"
    case vo2max = "vo2max"
    case activeEnergy = "active_energy"
    case steps = "steps"
}

/// HealthKit sleep stage as uploaded. See `SleepStageKind` for the four
/// display stages the API returns.
enum SleepStage: String, Codable {
    case inBed = "inbed", asleep, core, deep, rem, awake
}

struct Sample: Codable {
    let type: SampleType
    let start: Date
    let end: Date
    let value: Double
    let unit: String
    let source: String
    /// The HealthKit source's bundle identifier (`User.sources` shows it).
    var sourceBundleId: String? = nil
}

struct SleepSegment: Codable {
    let start: Date
    let end: Date
    let stage: SleepStage
    let source: String
    var sourceBundleId: String? = nil
}

struct Workout: Codable, Identifiable, Hashable {
    let id: UUID
    let activity: String
    let start: Date
    let end: Date
    let avgHr: Double?
    let maxHr: Double?
    let energyKcal: Double?
    let distanceM: Double?
    let source: String
    var strain: Double?
    /// Muscular load of the logged session attached to this workout (Train).
    var muscularLoad: Double? = nil
    /// The logged Train session this workout belongs to: the Strain list merges both into one row.
    var sessionId: UUID? = nil
    /// The scoring model that computed `strain` (`GET /v1/model`); `nil` before versions existed.
    var modelVersion: String? = nil
    var sourceBundleId: String? = nil

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SyncRequest: Codable {
    let deviceId: UUID
    var deviceName: String? = nil
    /// "1.0.0 (20261021.081500)", kept on the device row for support.
    var appVersion: String? = nil
    /// "iOS 27.1".
    var osVersion: String? = nil
    let samples: [Sample]
    let sleep: [SleepSegment]
    let workouts: [Workout]
}

struct SyncCounts: Codable, Hashable, Sendable {
    let samples: Int
    let sleep: Int
    let workouts: Int
}

/// Records not counted as stored, per reason (API.md → `POST /v1/sync`).
struct IgnoredCounts: Codable, Hashable, Sendable {
    let duplicate: Int
    let outsideWindow: Int
    let unknownType: Int

    static let none = IgnoredCounts(duplicate: 0, outsideWindow: 0, unknownType: 0)
}

struct SyncIgnored: Codable, Hashable, Sendable {
    let samples: IgnoredCounts
    let sleep: IgnoredCounts
    let workouts: IgnoredCounts

    static let none = SyncIgnored(samples: .none, sleep: .none, workouts: .none)
}

/// The days queued for rescoring and how long scoring has recently taken (p95).
struct SyncScoring: Codable, Hashable, Sendable {
    let queuedDays: [String]
    let expectedWithinSec: Int
}

struct SyncResponse: Codable, Sendable {
    /// Records stored new or changed (identical re-sends are in `ignored`).
    let samples: Int
    let sleep: Int
    let workouts: Int
    let daysTouched: [String]
    let accepted: SyncCounts
    let ignored: SyncIgnored
    let scoring: SyncScoring

    init(samples: Int, sleep: Int, workouts: Int, daysTouched: [String], accepted: SyncCounts? = nil,
         ignored: SyncIgnored = .none, scoring: SyncScoring? = nil) {
        self.samples = samples
        self.sleep = sleep
        self.workouts = workouts
        self.daysTouched = daysTouched
        self.accepted = accepted ?? SyncCounts(samples: samples, sleep: sleep, workouts: workouts)
        self.ignored = ignored
        // API.md: 30 s until the platform has measured scoring.
        self.scoring = scoring ?? SyncScoring(queuedDays: daysTouched, expectedWithinSec: 30)
    }
}

// MARK: - Daily score

enum ReadinessState: String, Codable, CaseIterable {
    case balanced, strained, depleted, calibrating
}

/// Whether a day's numbers are final (`DailyScore.scoring_state`, `SyncStatus.today.state`).
enum ScoringState: String, Codable, CaseIterable, Sendable {
    case scored
    /// Data newer than the score: scoring is queued or running.
    case pending
    /// Today, no night uploaded yet.
    case waitingForSleep = "waiting_for_sleep"
    /// Today, no new data for over 20 h.
    case stale
}

struct DailyScore: Codable, Identifiable, Hashable {
    let day: String // YYYY-MM-DD
    var readiness: Int?
    var state: ReadinessState?
    var recovery: Int?
    var strain: Double?
    var steps: Int?
    var activeKcal: Int?
    /// Minutes of logged strength training that day.
    var strengthMin: Int?
    /// Σ reps × kg of the day's sessions.
    var volumeKg: Double?
    var sleepPerformance: Int?
    var sleepNeedMin: Int?
    var sleepActualMin: Int?
    var sleepDebtMin: Int?
    /// The need by term (M4): `need = base + strain + debt − nap`.
    var sleepNeedBaseMin: Int?
    var sleepNeedStrainMin: Int?
    var sleepNeedDebtMin: Int?
    var sleepNeedNapMin: Int?
    /// Naps that day (lowers the following night's need); `0` without one.
    var napMin: Int?
    /// The night's quality score, 0–100 (`DayDetail.sleep.quality`).
    var sleepQuality: Int?
    /// Bedtime / wake regularity over 7 nights, 0–100.
    var sleepConsistency: Int?
    var hrvMs: Double?
    var rhr: Double?
    var respRate: Double?
    var spo2: Double?
    /// The 30-day baselines `hrv_ms` and `rhr` were scored against.
    var hrvBaselineMs: Double?
    var rhrBaseline: Double?
    /// Nights of history behind the baselines, 0–30.
    var baselineDays: Int
    /// `baseline_days < 7`.
    var calibrating: Bool
    /// `0001-01-01T00:00:00Z` for a day that hasn't been scored yet.
    var computedAt: Date?
    /// The scoring model that computed the row (`GET /v1/model`); `nil` before versions existed.
    var modelVersion: String?
    /// Always sent; `nil` only in a cached copy from before the field existed.
    var scoringState: ScoringState?

    var id: String { day }
    var date: Date { DayFormat.date(from: day) ?? .now }

    /// A day nothing is known about (MockData's days outside the history): no state, never
    /// calibrating. Its `standing` is `.unscored`.
    static func empty(day: String) -> DailyScore {
        DailyScore(day: day)
    }

    init(day: String, readiness: Int? = nil, state: ReadinessState? = nil, recovery: Int? = nil,
         strain: Double? = nil, steps: Int? = nil, activeKcal: Int? = nil, strengthMin: Int? = nil,
         volumeKg: Double? = nil, sleepPerformance: Int? = nil,
         sleepNeedMin: Int? = nil, sleepActualMin: Int? = nil, sleepDebtMin: Int? = nil, hrvMs: Double? = nil,
         rhr: Double? = nil, respRate: Double? = nil, spo2: Double? = nil, hrvBaselineMs: Double? = nil,
         rhrBaseline: Double? = nil, baselineDays: Int = 0, calibrating: Bool = false, computedAt: Date? = nil,
         sleepNeedBaseMin: Int? = nil, sleepNeedStrainMin: Int? = nil, sleepNeedDebtMin: Int? = nil,
         sleepNeedNapMin: Int? = nil, napMin: Int? = nil, sleepQuality: Int? = nil, sleepConsistency: Int? = nil,
         modelVersion: String? = nil, scoringState: ScoringState? = nil) {
        self.day = day
        self.modelVersion = modelVersion
        self.scoringState = scoringState
        self.readiness = readiness
        self.state = state
        self.recovery = recovery
        self.strain = strain
        self.steps = steps
        self.activeKcal = activeKcal
        self.strengthMin = strengthMin
        self.volumeKg = volumeKg
        self.sleepPerformance = sleepPerformance
        self.sleepNeedMin = sleepNeedMin
        self.sleepActualMin = sleepActualMin
        self.sleepDebtMin = sleepDebtMin
        self.hrvMs = hrvMs
        self.rhr = rhr
        self.respRate = respRate
        self.spo2 = spo2
        self.hrvBaselineMs = hrvBaselineMs
        self.rhrBaseline = rhrBaseline
        self.baselineDays = baselineDays
        self.calibrating = calibrating
        self.computedAt = computedAt
        self.sleepNeedBaseMin = sleepNeedBaseMin
        self.sleepNeedStrainMin = sleepNeedStrainMin
        self.sleepNeedDebtMin = sleepNeedDebtMin
        self.sleepNeedNapMin = sleepNeedNapMin
        self.napMin = napMin
        self.sleepQuality = sleepQuality
        self.sleepConsistency = sleepConsistency
    }

    enum CodingKeys: String, CodingKey {
        case day, readiness, state, recovery, strain, steps, activeKcal, strengthMin, volumeKg, sleepPerformance, sleepNeedMin,
             sleepActualMin, sleepDebtMin, hrvMs, rhr, respRate, spo2, hrvBaselineMs, rhrBaseline,
             baselineDays, calibrating, computedAt, sleepNeedBaseMin, sleepNeedStrainMin, sleepNeedDebtMin,
             sleepNeedNapMin, napMin, sleepQuality, sleepConsistency, modelVersion, scoringState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        readiness = try c.decodeLenientInt(.readiness)
        state = try? c.decodeIfPresent(ReadinessState.self, forKey: .state)
        recovery = try c.decodeLenientInt(.recovery)
        strain = try c.decodeIfPresent(Double.self, forKey: .strain)
        steps = try c.decodeLenientInt(.steps)
        activeKcal = try c.decodeLenientInt(.activeKcal)
        strengthMin = try c.decodeLenientInt(.strengthMin)
        volumeKg = try c.decodeIfPresent(Double.self, forKey: .volumeKg)
        sleepPerformance = try c.decodeLenientInt(.sleepPerformance)
        sleepNeedMin = try c.decodeLenientInt(.sleepNeedMin)
        sleepActualMin = try c.decodeLenientInt(.sleepActualMin)
        sleepDebtMin = try c.decodeLenientInt(.sleepDebtMin)
        hrvMs = try c.decodeIfPresent(Double.self, forKey: .hrvMs)
        rhr = try c.decodeIfPresent(Double.self, forKey: .rhr)
        respRate = try c.decodeIfPresent(Double.self, forKey: .respRate)
        spo2 = try c.decodeIfPresent(Double.self, forKey: .spo2)
        hrvBaselineMs = try c.decodeIfPresent(Double.self, forKey: .hrvBaselineMs)
        rhrBaseline = try c.decodeIfPresent(Double.self, forKey: .rhrBaseline)
        baselineDays = try c.decodeLenientInt(.baselineDays) ?? 0
        calibrating = try c.decodeIfPresent(Bool.self, forKey: .calibrating) ?? false
        computedAt = try? c.decodeIfPresent(Date.self, forKey: .computedAt)
        sleepNeedBaseMin = try c.decodeLenientInt(.sleepNeedBaseMin)
        sleepNeedStrainMin = try c.decodeLenientInt(.sleepNeedStrainMin)
        sleepNeedDebtMin = try c.decodeLenientInt(.sleepNeedDebtMin)
        sleepNeedNapMin = try c.decodeLenientInt(.sleepNeedNapMin)
        napMin = try c.decodeLenientInt(.napMin)
        sleepQuality = try c.decodeLenientInt(.sleepQuality)
        sleepConsistency = try c.decodeLenientInt(.sleepConsistency)
        modelVersion = try c.decodeIfPresent(String.self, forKey: .modelVersion)
        scoringState = try? c.decodeIfPresent(ScoringState.self, forKey: .scoringState)
    }

    /// The server's state. `null` (an older cached payload) is read like the
    /// platform does (D4): no readiness → calibrating, else the readiness bands.
    var resolvedState: ReadinessState {
        if let state { return state }
        guard let r = readiness else { return .calibrating }
        switch r {
        case 67...: return .balanced
        case 34...: return .strained
        default: return .depleted
        }
    }

    static let baselineNightsRequired = 7

    /// "Calibrating — N nights to go" is `7 − baseline_days` (≥ 1 while calibrating).
    var nightsToGo: Int { max(1, Self.baselineNightsRequired - baselineDays) }
}

/// What a row says about its day (app-side, not a wire field). The platform's placeholder for a
/// day it hasn't scored (`computed_at` 0001, `state: calibrating`, `calibrating: false`) and
/// `DailyScore.empty` are `.unscored`, never calibrating. Presentation branches on this, never on
/// `state == .calibrating` or `calibrating` alone.
enum ScoreStanding: Equatable, Sendable {
    case unscored
    /// Scored while the baselines fill: the row's `baseline_days`.
    case calibrating(baselineDays: Int)
    case scored
}

extension DailyScore {
    /// `.unscored`: no readiness and `computed_at` nil or not after 1970. Else `calibrating`
    /// → `.calibrating`.
    var standing: ScoreStanding {
        if readiness == nil, (computedAt ?? .distantPast) <= Date(timeIntervalSince1970: 0) { return .unscored }
        return calibrating ? .calibrating(baselineDays: baselineDays) : .scored
    }
}

// MARK: - Sleep

/// The four display stages. HealthKit's "core" is reported as "light".
enum SleepStageKind: String, Codable, CaseIterable, Identifiable {
    case deep, light, rem, awake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deep: return String(localized: "Deep")
        // Own key: "Light" is also the Appearance option, which German words differently.
        case .light: return String(localized: "sleep.stage.light", defaultValue: "Light",
                                   comment: "Sleep stage (light / core sleep), in stage lists and the hypnogram.")
        case .rem: return String(localized: "REM")
        case .awake: return String(localized: "Awake")
        }
    }
}

/// A hypnogram segment's stage: the four display stages plus `asleep` (stage unknown).
enum SleepIntervalStage: String, Codable, CaseIterable {
    case deep, light, rem, awake, asleep
}

enum SleepQualityLabel: String, Codable {
    case good, fair, poor

    /// The platform's bands: good ≥ 80, fair 60–79, poor < 60.
    init(quality: Int) {
        self = quality >= 80 ? .good : quality >= 60 ? .fair : .poor
    }

    var title: String {
        switch self {
        case .good: return String(localized: "Good")
        case .fair: return String(localized: "Fair")
        case .poor: return String(localized: "Poor")
        }
    }
}

struct StageShare: Codable, Hashable, Identifiable {
    let stage: SleepStageKind
    let min: Int
    /// Whole percent 0–100. Deep/light/rem: share of staged sleep (sum 100);
    /// awake: share of time in bed.
    var pct: Double?

    var id: SleepStageKind { stage }

    init(stage: SleepStageKind, min: Int, pct: Double? = nil) {
        self.stage = stage
        self.min = min
        self.pct = pct
    }
}

/// One hypnogram block, oldest first; touching blocks of one stage are merged.
struct SleepInterval: Codable, Hashable {
    let stage: SleepIntervalStage
    let start: Date
    let end: Date
}

/// Why a night's need is what it is (`DayDetail.sleep.need`), minutes:
/// `total = base + strain + debt − napCredit`.
struct SleepNeed: Codable, Hashable {
    let base: Int
    let strain: Int
    let debt: Int
    let napCredit: Int
    let total: Int
}

/// `DayDetail.sleep`: the night ending on that day.
struct SleepDetail: Codable, Hashable {
    var start: Date?
    var end: Date?
    var totalMin: Int?
    var inBedMin: Int?
    /// Whole percent 0–100.
    var efficiency: Int?
    var stages: [StageShare]
    var quality: Int?
    var qualityLabel: SleepQualityLabel?
    /// Deep + REM against 40 % of time asleep, 0–100.
    var restorative: Int?
    var hasStages: Bool
    /// The need behind the night (only on `GET /v1/days/{day}`).
    var need: SleepNeed?
    /// The hypnogram (only on `GET /v1/days/{day}`).
    var segments: [SleepInterval]

    init(start: Date? = nil, end: Date? = nil, totalMin: Int? = nil, inBedMin: Int? = nil,
         efficiency: Int? = nil, stages: [StageShare] = [], quality: Int? = nil,
         qualityLabel: SleepQualityLabel? = nil, hasStages: Bool = true, segments: [SleepInterval] = [],
         restorative: Int? = nil, need: SleepNeed? = nil) {
        self.start = start
        self.end = end
        self.totalMin = totalMin
        self.inBedMin = inBedMin
        self.efficiency = efficiency
        self.stages = stages
        self.quality = quality
        self.qualityLabel = qualityLabel
        self.hasStages = hasStages
        self.segments = segments
        self.restorative = restorative
        self.need = need
    }

    enum CodingKeys: String, CodingKey {
        case start, end, totalMin, inBedMin, efficiency, stages, quality, qualityLabel, hasStages, segments,
             restorative, need
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try? c.decodeIfPresent(Date.self, forKey: .start)
        end = try? c.decodeIfPresent(Date.self, forKey: .end)
        totalMin = try c.decodeLenientInt(.totalMin)
        inBedMin = try c.decodeLenientInt(.inBedMin)
        efficiency = try c.decodeLenientInt(.efficiency)
        stages = try c.decodeIfPresent([StageShare].self, forKey: .stages) ?? []
        quality = try c.decodeLenientInt(.quality)
        qualityLabel = try? c.decodeIfPresent(SleepQualityLabel.self, forKey: .qualityLabel)
        hasStages = try c.decodeIfPresent(Bool.self, forKey: .hasStages) ?? !stages.isEmpty
        segments = try c.decodeIfPresent([SleepInterval].self, forKey: .segments) ?? []
        restorative = try c.decodeLenientInt(.restorative)
        need = try? c.decodeIfPresent(SleepNeed.self, forKey: .need)
    }

    /// All four stages in display order (deep, light, rem, awake). The
    /// platform's percentages are used as sent; only a missing one is computed.
    var displayStages: [StageShare] {
        let computed = SleepMath.shares(stages.reduce(into: [:]) { $0[$1.stage, default: 0] += $1.min })
        return computed.map { share in
            stages.first { $0.stage == share.stage && $0.pct != nil } ?? share
        }
    }

    var efficiencyPercent: Double? {
        if let efficiency { return Double(efficiency) }
        if let t = totalMin, let b = timeInBedMin, b > 0 { return Double(t) / Double(b) * 100 }
        return nil
    }

    /// In-bed minutes from the server, else derived from start/end.
    var timeInBedMin: Int? {
        if let inBedMin, inBedMin > 0 { return inBedMin }
        if let start, let end { return Int(end.timeIntervalSince(start) / 60) }
        return nil
    }

    var resolvedQualityLabel: String? {
        (qualityLabel ?? quality.map(SleepQualityLabel.init(quality:)))?.title
    }
}

enum SleepRangeKind: String, Codable, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    var days: Int { self == .week ? 7 : 30 }
}

/// `SleepRange.days[]` (API `SleepDay`): a night with data. Missing nights are absent.
struct SleepNight: Codable, Hashable, Identifiable {
    let day: String
    var start: Date?
    var end: Date?
    var totalMin: Int?
    var inBedMin: Int?
    var efficiency: Int?
    var stages: [StageShare]
    var quality: Int?
    var qualityLabel: SleepQualityLabel?
    var restorative: Int?
    var hasStages: Bool
    /// That day's `score.sleep_consistency` and `score.nap_min`.
    var consistency: Int?
    var napMin: Int?

    var id: String { day }
    var date: Date { DayFormat.date(from: day) ?? .now }

    init(day: String, totalMin: Int?, stages: [StageShare], quality: Int?, start: Date? = nil, end: Date? = nil,
         inBedMin: Int? = nil, efficiency: Int? = nil, qualityLabel: SleepQualityLabel? = nil, hasStages: Bool = true,
         restorative: Int? = nil, consistency: Int? = nil, napMin: Int? = nil) {
        self.day = day
        self.start = start
        self.end = end
        self.totalMin = totalMin
        self.inBedMin = inBedMin
        self.efficiency = efficiency
        self.stages = stages
        self.quality = quality
        self.qualityLabel = qualityLabel
        self.hasStages = hasStages
        self.restorative = restorative
        self.consistency = consistency
        self.napMin = napMin
    }

    enum CodingKeys: String, CodingKey {
        case day, start, end, totalMin, inBedMin, efficiency, stages, quality, qualityLabel, hasStages,
             restorative, consistency, napMin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        start = try? c.decodeIfPresent(Date.self, forKey: .start)
        end = try? c.decodeIfPresent(Date.self, forKey: .end)
        totalMin = try c.decodeLenientInt(.totalMin)
        inBedMin = try c.decodeLenientInt(.inBedMin)
        efficiency = try c.decodeLenientInt(.efficiency)
        stages = try c.decodeIfPresent([StageShare].self, forKey: .stages) ?? []
        quality = try c.decodeLenientInt(.quality)
        qualityLabel = try? c.decodeIfPresent(SleepQualityLabel.self, forKey: .qualityLabel)
        hasStages = try c.decodeIfPresent(Bool.self, forKey: .hasStages) ?? !stages.isEmpty
        restorative = try c.decodeLenientInt(.restorative)
        consistency = try c.decodeLenientInt(.consistency)
        napMin = try c.decodeLenientInt(.napMin)
    }

    func minutes(for stage: SleepStageKind) -> Int {
        stages.first { $0.stage == stage }?.min ?? 0
    }
}

/// A night's bed and wake time, for the bedtime / wake strip.
struct SleepBedtime: Codable, Hashable, Identifiable {
    let day: String
    let bed: Date
    let wake: Date
    var id: String { day }
}

/// `GET /v1/sleep?range=week|month`.
struct SleepRange: Codable, Hashable {
    let range: String
    var from: String?
    var to: String?
    /// Only nights with data, oldest first.
    var days: [SleepNight]
    var nights: Int
    var avgTotalMin: Int?
    var avgInBedMin: Int?
    var avgEfficiency: Int?
    var avgQuality: Int?
    var avgStages: [StageShare]
    var avgConsistency: Int?
    var bedtimes: [SleepBedtime]

    init(range: String, from: String? = nil, to: String? = nil, days: [SleepNight], avgTotalMin: Int?,
         avgQuality: Int?, avgInBedMin: Int? = nil, avgEfficiency: Int? = nil, avgStages: [StageShare] = [],
         avgConsistency: Int? = nil, bedtimes: [SleepBedtime] = []) {
        self.range = range
        self.from = from
        self.to = to
        self.days = days
        self.nights = days.count
        self.avgTotalMin = avgTotalMin
        self.avgInBedMin = avgInBedMin
        self.avgEfficiency = avgEfficiency
        self.avgQuality = avgQuality
        self.avgStages = avgStages
        self.avgConsistency = avgConsistency
        self.bedtimes = bedtimes
    }

    enum CodingKeys: String, CodingKey {
        case range, from, to, days, nights, avgTotalMin, avgInBedMin, avgEfficiency, avgQuality, avgStages,
             avgConsistency, bedtimes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        range = try c.decodeIfPresent(String.self, forKey: .range) ?? ""
        from = try c.decodeIfPresent(String.self, forKey: .from)
        to = try c.decodeIfPresent(String.self, forKey: .to)
        days = try c.decodeIfPresent([SleepNight].self, forKey: .days) ?? []
        nights = try c.decodeLenientInt(.nights) ?? days.count
        avgTotalMin = try c.decodeLenientInt(.avgTotalMin)
        avgInBedMin = try c.decodeLenientInt(.avgInBedMin)
        avgEfficiency = try c.decodeLenientInt(.avgEfficiency)
        avgQuality = try c.decodeLenientInt(.avgQuality)
        avgStages = try c.decodeIfPresent([StageShare].self, forKey: .avgStages) ?? []
        avgConsistency = try c.decodeLenientInt(.avgConsistency)
        bedtimes = try c.decodeIfPresent([SleepBedtime].self, forKey: .bedtimes) ?? []
    }
}

/// `GET /v1/sleep/plan?wake=HH:MM`: what tonight's bedtimes rest on.
struct SleepPlanBasis: Codable, Hashable {
    let base: Int
    /// Today's strain so far × 3 min, at most 60.
    let strainTopup: Int
    let debtTopup: Int
    let napCredit: Int
    let efficiency: Int
}

/// `GET /v1/sleep/plan?wake=HH:MM`: bedtimes for 100 / 85 / 70 % of tonight's need.
struct SleepPlan: Codable, Hashable {
    let wake: Date
    let needMin: Int
    let inBedMin: Int
    let efficiency: Int
    let bedtime100: Date
    let bedtime85: Date
    let bedtime70: Date
    let basis: SleepPlanBasis
}

// MARK: - Day detail

/// `DayDetail.strain`: the heart-rate load behind `score.strain`. `null`
/// exactly when `score.strain` is.
struct DayStrain: Codable, Hashable {
    let trimp: Int
    /// Minutes of usable heart-rate data (watch worn).
    let hrMin: Int
    /// Minutes at 50–60, 60–70, 70–80, 80–90, ≥ 90 % of heart-rate reserve.
    let zoneMin: [Int]
    var steps: Int?
    var activeKcal: Int?
    /// Muscular load of the day's sessions (TRIMP-equivalent), part of `trimp`.
    var muscularTrimp: Int? = nil
    /// Train sessions logged that day.
    var sessions: [SessionSummary]? = nil
}

struct DayDetail: Codable, Hashable {
    var score: DailyScore
    var sleep: SleepDetail?
    var strain: DayStrain?
    var workouts: [Workout]

    init(score: DailyScore, sleep: SleepDetail?, strain: DayStrain? = nil, workouts: [Workout]) {
        self.score = score
        self.sleep = sleep
        self.strain = strain
        self.workouts = workouts
    }

    enum CodingKeys: String, CodingKey { case score, sleep, strain, workouts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = try c.decode(DailyScore.self, forKey: .score)
        sleep = try c.decodeIfPresent(SleepDetail.self, forKey: .sleep)
        strain = try c.decodeIfPresent(DayStrain.self, forKey: .strain)
        workouts = try c.decodeIfPresent([Workout].self, forKey: .workouts) ?? []
    }
}

// MARK: - Workouts

struct HRPoint: Codable, Hashable {
    let t: Date
    let bpm: Double
}

/// `GET /v1/workouts/{id}`: a Workout plus its HR series, zone minutes and TRIMP.
struct WorkoutDetail: Codable, Hashable {
    var workout: Workout
    var hr: [HRPoint]
    var zoneMin: [Double]
    var trimp: Double?

    init(workout: Workout, hr: [HRPoint] = [], zoneMin: [Double] = [], trimp: Double? = nil) {
        self.workout = workout
        self.hr = hr
        self.zoneMin = zoneMin
        self.trimp = trimp
    }

    private enum Extra: String, CodingKey { case hr, zoneMin, trimp }

    init(from decoder: Decoder) throws {
        workout = try Workout(from: decoder)
        let c = try decoder.container(keyedBy: Extra.self)
        hr = (try? c.decodeIfPresent([HRPoint].self, forKey: .hr)) ?? []
        zoneMin = (try? c.decodeIfPresent([Double].self, forKey: .zoneMin)) ?? []
        trimp = try c.decodeIfPresent(Double.self, forKey: .trimp)
    }

    func encode(to encoder: Encoder) throws {
        try workout.encode(to: encoder)
        var c = encoder.container(keyedBy: Extra.self)
        try c.encode(hr, forKey: .hr)
        try c.encode(zoneMin, forKey: .zoneMin)
        try c.encodeIfPresent(trimp, forKey: .trimp)
    }
}

// MARK: - Trends

/// `GET /v1/trends?metric=…`. `sleep` is sleep performance (%); minutes asleep is `sleep_min`.
enum TrendMetric: String, Codable, CaseIterable, Identifiable {
    case readiness, recovery, strain, sleep
    case sleepMin = "sleep_min"
    case hrv, rhr, steps
    case activeKcal = "active_kcal"
    case strengthMin = "strength_min"
    case volumeKg = "volume_kg"
    case sleepQuality = "sleep_quality"
    case sleepConsistency = "sleep_consistency"
    case napMin = "nap_min"
    var id: String { rawValue }
}

enum TrendRange: String, Codable, CaseIterable, Identifiable {
    case week = "7d", month = "30d", quarter = "90d"
    var id: String { rawValue }
    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        }
    }
}

struct TrendPoint: Codable, Hashable, Identifiable {
    let day: String
    var value: Double?
    var id: String { day }
    var date: Date { DayFormat.date(from: day) ?? .now }
}

struct TrendSeries: Codable, Hashable {
    let metric: String
    let range: String
    var from: String? = nil
    var to: String? = nil
    var points: [TrendPoint]
    var avg: Double?
    var min: Double?
    var max: Double?
    var baseline: Double?

    init(metric: String, range: String, points: [TrendPoint], avg: Double?, min: Double?, max: Double?, baseline: Double?) {
        self.metric = metric
        self.range = range
        self.points = points
        self.avg = avg
        self.min = min
        self.max = max
        self.baseline = baseline
    }

    enum CodingKeys: String, CodingKey { case metric, range, from, to, points, avg, min, max, baseline }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metric = try c.decodeIfPresent(String.self, forKey: .metric) ?? ""
        range = try c.decodeIfPresent(String.self, forKey: .range) ?? ""
        from = try c.decodeIfPresent(String.self, forKey: .from)
        to = try c.decodeIfPresent(String.self, forKey: .to)
        points = try c.decodeIfPresent([TrendPoint].self, forKey: .points) ?? []
        avg = try c.decodeIfPresent(Double.self, forKey: .avg)
        min = try c.decodeIfPresent(Double.self, forKey: .min)
        max = try c.decodeIfPresent(Double.self, forKey: .max)
        baseline = try c.decodeIfPresent(Double.self, forKey: .baseline)
    }
}

// MARK: - Insights

enum InsightSeverity: String, Codable, CaseIterable {
    case info, notice, warn

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InsightSeverity(rawValue: raw.lowercased()) ?? .info
    }
}

struct Insight: Codable, Hashable, Identifiable {
    let id: String
    let severity: InsightSeverity
    let title: String
    let body: String
    var metric: String?
    var day: String?

    init(id: String, severity: InsightSeverity, title: String, body: String, metric: String? = nil, day: String? = nil) {
        self.id = id
        self.severity = severity
        self.title = title
        self.body = body
        self.metric = metric
        self.day = day
    }

    enum CodingKeys: String, CodingKey { case id, severity, title, body, metric, day }

    /// The rule behind the card. Ids are open: new rules decode as `.other`.
    var kind: InsightKind { InsightKind(rawValue: id) }
    /// The trend metric the card deep-links to, when the app knows it.
    var trendMetric: TrendMetric? { metric.flatMap(TrendMetric.init(rawValue:)) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else {
            id = String(try c.decode(Int.self, forKey: .id))
        }
        severity = try c.decodeIfPresent(InsightSeverity.self, forKey: .severity) ?? .info
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        metric = try c.decodeIfPresent(String.self, forKey: .metric)
        day = try c.decodeIfPresent(String.self, forKey: .day)
    }
}

/// `Insight.id`, one per platform rule (API.md → Insights). Open: an id the app
/// doesn't know yet is `.other` and shows generically.
enum InsightKind: Hashable {
    case hrvLow3d, rhrElevated, strainNoRecovery, sleepDebt, bedtimeIrregular, readinessUp, hrvBest30d
    case pr, behaviorImpact, sleepConsistencyLow, napCredit, baselineLearned
    case other(String)

    private static let known: [String: InsightKind] = [
        "hrv-low-3d": .hrvLow3d, "rhr-elevated": .rhrElevated, "strain-no-recovery": .strainNoRecovery,
        "sleep-debt": .sleepDebt, "bedtime-irregular": .bedtimeIrregular, "readiness-up": .readinessUp,
        "hrv-best-30d": .hrvBest30d, "pr": .pr, "behavior-impact": .behaviorImpact,
        "sleep-consistency-low": .sleepConsistencyLow, "nap-credit": .napCredit, "baseline-learned": .baselineLearned,
    ]

    init(rawValue: String) {
        self = Self.known[rawValue] ?? .other(rawValue)
    }

    /// SF Symbol for the card; unknown kinds get `info.circle`.
    var systemImage: String {
        switch self {
        case .hrvLow3d: return "waveform.path.ecg"
        case .rhrElevated: return "heart"
        case .strainNoRecovery: return "bolt.heart"
        case .sleepDebt: return "moon.zzz"
        case .bedtimeIrregular: return "bed.double"
        case .readinessUp: return "chart.line.uptrend.xyaxis"
        case .hrvBest30d: return "star"
        case .pr: return "trophy"
        case .behaviorImpact: return "list.bullet.clipboard"
        case .sleepConsistencyLow: return "clock.badge.exclamationmark"
        case .napCredit: return "powersleep"
        case .baselineLearned: return "brain"
        case .other: return "info.circle"
        }
    }
}

// MARK: - User

enum SleepBaseSource: String, Codable, Hashable { case `default`, learned, manual }

struct User: Codable, Hashable {
    let id: UUID
    /// `""` until the sign-in provided a name (`user_metadata.full_name`).
    let name: String
    /// From the token; for Sign in with Apple possibly a private relay address.
    var email: String? = nil
    /// Sign-in provider, e.g. `apple` or `email`.
    var provider: String? = nil
    let tz: String
    let maxHr: Int
    let sleepBaseMin: Int
    var sleepBaseSource: SleepBaseSource = .default
    var sleepBaseLearnedMin: Int? = nil
    var sleepBaseLearnedAt: Date? = nil
    var notifications: NotificationPrefs = .allOn
    /// Redeemed an invite code (or existed before the gate). Whether the gate is on at
    /// all is `GET /v1/me/sync` → `gate`, so `false` alone doesn't mean "ask for a code".
    var betaAccess: Bool = true
    /// The latest consent that wasn't withdrawn; syncing needs its `policyVersion` to be
    /// `RemoteConfig.privacyPolicyVersion`.
    var consent: Consent? = nil
    var birthYear: Int? = nil
    var maxHrSource: MaxHRSource = .default
    /// Apps and devices that sent data in the last 30 days, newest first.
    var sources: [UserSource] = []
    /// This account has no data and this phone synced another account recently.
    var accountHint: AccountHint? = nil

    init(id: UUID, name: String, email: String? = nil, provider: String? = nil, tz: String, maxHr: Int,
         sleepBaseMin: Int, sleepBaseSource: SleepBaseSource = .default, sleepBaseLearnedMin: Int? = nil,
         sleepBaseLearnedAt: Date? = nil, notifications: NotificationPrefs = .allOn, betaAccess: Bool = true,
         consent: Consent? = nil, birthYear: Int? = nil, maxHrSource: MaxHRSource = .default,
         sources: [UserSource] = [], accountHint: AccountHint? = nil) {
        self.betaAccess = betaAccess
        self.consent = consent
        self.birthYear = birthYear
        self.maxHrSource = maxHrSource
        self.sources = sources
        self.accountHint = accountHint
        self.id = id
        self.name = name
        self.email = email
        self.provider = provider
        self.tz = tz
        self.maxHr = maxHr
        self.sleepBaseMin = sleepBaseMin
        self.sleepBaseSource = sleepBaseSource
        self.sleepBaseLearnedMin = sleepBaseLearnedMin
        self.sleepBaseLearnedAt = sleepBaseLearnedAt
        self.notifications = notifications
    }

    // Cached copies from before these fields existed decode with their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        tz = try c.decode(String.self, forKey: .tz)
        maxHr = try c.decode(Int.self, forKey: .maxHr)
        sleepBaseMin = try c.decode(Int.self, forKey: .sleepBaseMin)
        sleepBaseSource = try c.decodeIfPresent(SleepBaseSource.self, forKey: .sleepBaseSource) ?? .default
        sleepBaseLearnedMin = try c.decodeIfPresent(Int.self, forKey: .sleepBaseLearnedMin)
        sleepBaseLearnedAt = try c.decodeIfPresent(Date.self, forKey: .sleepBaseLearnedAt)
        notifications = try c.decodeIfPresent(NotificationPrefs.self, forKey: .notifications) ?? .allOn
        betaAccess = try c.decodeIfPresent(Bool.self, forKey: .betaAccess) ?? true
        consent = try c.decodeIfPresent(Consent.self, forKey: .consent)
        birthYear = try c.decodeIfPresent(Int.self, forKey: .birthYear)
        maxHrSource = (try? c.decodeIfPresent(MaxHRSource.self, forKey: .maxHrSource)) ?? .default
        sources = try c.decodeIfPresent([UserSource].self, forKey: .sources) ?? []
        accountHint = try? c.decodeIfPresent(AccountHint.self, forKey: .accountHint)
    }

    /// Consent to the policy in force, or no policy version known yet (no config).
    func hasConsented(to policyVersion: String?) -> Bool {
        guard let policyVersion else { return consent != nil }
        return consent?.policyVersion == policyVersion
    }
}

enum MaxHRSource: String, Codable, Hashable, Sendable {
    /// 190, nothing known.
    case `default`
    /// 208 − 0.7 · age (Tanaka), from `birth_year`.
    case estimated
    case manual
}

/// What a source provides (`UserSource.kinds`); `hr` covers heart rate, resting HR and VO₂max.
enum SourceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case energy, hr, hrv, resp, sleep, spo2, steps, workout
}

struct Consent: Codable, Hashable, Sendable {
    let policyVersion: String
    let grantedAt: Date
}

struct UserSource: Codable, Hashable, Sendable {
    let name: String
    let bundleId: String?
    let kinds: [SourceKind]
    let lastSeen: Date

    init(name: String, bundleId: String?, kinds: [SourceKind], lastSeen: Date) {
        self.name = name
        self.bundleId = bundleId
        self.kinds = kinds
        self.lastSeen = lastSeen
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
        kinds = try c.decodeLenientList(SourceKind.self, .kinds)
        lastSeen = try c.decode(Date.self, forKey: .lastSeen)
    }
}

/// `GET /v1/me` → `account_hint`: probably the same person, signed in another way.
struct AccountHint: Codable, Hashable, Sendable {
    /// `other_account_on_device` (the only value so far).
    let kind: String
    /// `apple`, `email`.
    let otherProvider: String?
    let otherLastSync: Date
}

struct UserPatch: Codable {   // PATCH /v1/me, every field optional
    var tz: String? = nil
    var maxHr: Int? = nil
    /// `false` goes back to the estimate (or 190 without a birth year).
    var maxHrManual: Bool? = nil
    var birthYear: Int? = nil
    var sleepBaseMin: Int? = nil
    var sleepBaseManual: Bool? = nil
}

struct ConsentPost: Encodable {   // POST /v1/me/consent
    let policyVersion: String
    var appVersion: String? = nil
}

struct InvitePost: Encodable {   // POST /v1/me/invite
    let code: String
}

// MARK: accounts and sync state (API.md → GET /v1/me/sync)

struct TodayState: Codable, Hashable, Sendable {
    let day: String
    let state: ScoringState
    let scoredAt: Date?
    let modelVersion: String
}

/// `GET /v1/me/sync`: what the server has, and what scoring is doing with it.
struct SyncStatus: Codable, Hashable, Sendable {
    /// The gate between this account and its scores, also while it only warns. `nil`: none.
    let gate: APIErrorCode?
    let lastSyncAt: Date?
    let lastSyncDevice: String?
    /// The newest record per kind (`SourceKind` raw values); missing keys never arrived.
    let latest: [String: Date]
    let today: TodayState
    /// Days a sync queued that scoring hasn't finished, oldest first.
    let pendingDays: [String]
    let expectedWithinSec: Int
    let resyncRequestedAt: Date?

    init(gate: APIErrorCode?, lastSyncAt: Date?, lastSyncDevice: String?, latest: [String: Date], today: TodayState,
         pendingDays: [String], expectedWithinSec: Int, resyncRequestedAt: Date?) {
        self.gate = gate
        self.lastSyncAt = lastSyncAt
        self.lastSyncDevice = lastSyncDevice
        self.latest = latest
        self.today = today
        self.pendingDays = pendingDays
        self.expectedWithinSec = expectedWithinSec
        self.resyncRequestedAt = resyncRequestedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Closed enum, but a code this build doesn't know is no gate it could show.
        gate = try? c.decodeIfPresent(APIErrorCode.self, forKey: .gate)
        lastSyncAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        lastSyncDevice = try c.decodeIfPresent(String.self, forKey: .lastSyncDevice)
        latest = try c.decodeIfPresent([String: Date].self, forKey: .latest) ?? [:]
        today = try c.decode(TodayState.self, forKey: .today)
        pendingDays = try c.decodeIfPresent([String].self, forKey: .pendingDays) ?? []
        expectedWithinSec = try c.decode(Int.self, forKey: .expectedWithinSec)
        resyncRequestedAt = try c.decodeIfPresent(Date.self, forKey: .resyncRequestedAt)
    }
}

// MARK: scoring model and feedback (API.md → GET /v1/model, POST /v1/feedback)

struct ModelChange: Codable, Hashable {
    let version: String
    let date: String
    let summary: String
    let summaryEn: String
    let summaryDe: String
    let affects: [String]
}

struct ModelInfo: Codable, Hashable {   // GET /v1/model
    let current: String
    let changelog: [ModelChange]
}

enum FeedbackCategory: String, Codable, CaseIterable { case bug, idea, data, other }

struct FeedbackPost: Encodable {   // POST /v1/feedback
    let message: String
    var category: FeedbackCategory? = nil
    var appVersion: String? = nil
    var build: String? = nil
    var deviceModel: String? = nil
    var osVersion: String? = nil
    var requestIds: [String] = []
    /// The server takes any JSON object up to 32 KiB.
    var diagnostics: [String: String]? = nil
}

// MARK: journal and behavior impact (API.md → Journal)

enum BehaviorKind: String, Codable, CaseIterable, Identifiable {
    case yesNo = "yes_no", count, time
    var id: String { rawValue }
}

enum BehaviorCategory: String, Codable, CaseIterable, Identifiable {
    case substances, sleep, recovery, supplements, health, lifestyle, custom
    var id: String { rawValue }
}

enum ImpactStatus: String, Codable { case locked, unlocked }

/// `GET /v1/behaviors`: the catalog with the user's choice.
struct Behavior: Codable, Hashable, Identifiable {
    let id: UUID
    let slug: String
    /// In the request's language.
    let name: String
    let nameEn: String
    let nameDe: String
    let category: BehaviorCategory
    let kind: BehaviorKind
    let defaultOn: Bool
    var enabled: Bool
    let isCustom: Bool
    let sort: Int
}

/// `PATCH /v1/behaviors`: behavior id (lowercase) → on.
struct BehaviorsPatch: Encodable {
    let enabled: [String: Bool]

    init(_ enabled: [UUID: Bool]) {
        self.enabled = Dictionary(uniqueKeysWithValues: enabled.map { ($0.key.uuidString.lowercased(), $0.value) })
    }
}

/// `POST /v1/behaviors`: a custom behavior with an app-generated id.
struct BehaviorInput: Encodable, Hashable {
    let id: UUID
    let name: String
    var nameDe: String? = nil
    let kind: BehaviorKind
    var category: BehaviorCategory? = nil
}

struct JournalEntry: Codable, Hashable {
    let behaviorId: UUID
    /// Did it happen (always present).
    let valueBool: Bool
    /// `count` behaviors: how many, ≥ 1 when `valueBool`.
    var valueNum: Int? = nil
    /// `time` behaviors: local "HH:MM" when `valueBool`.
    var valueTime: String? = nil

    /// `nil` values are sent as `null`, as the API's example shows.
    enum CodingKeys: String, CodingKey { case behaviorId, valueBool, valueNum, valueTime }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(behaviorId, forKey: .behaviorId)
        try c.encode(valueBool, forKey: .valueBool)
        try c.encode(valueNum, forKey: .valueNum)
        try c.encode(valueTime, forKey: .valueTime)
    }
}

/// `GET` / `PUT /v1/journal/{day}`: the day the behaviors happened.
struct JournalDay: Codable, Hashable {
    let day: String
    /// Saved at least once; a day never saved is unknown, not "no".
    let answered: Bool
    let answeredAt: Date?
    /// Within the last 14 days and not in the future.
    let editable: Bool
    let entries: [JournalEntry]
}

/// `PUT /v1/journal/{day}`: replaces the day; every behavior shown is sent.
struct JournalPut: Encodable, Hashable {
    let entries: [JournalEntry]
}

/// Yes − no of the mean the morning after, with a 90 % interval.
struct BehaviorEffect: Codable, Hashable {
    let delta: Double
    let ciLo: Double
    let ciHi: Double
    let significant: Bool
    let nYes: Int
    let nNo: Int
}

struct ImpactNeeded: Codable, Hashable {
    let yes: Int
    let no: Int
}

struct BehaviorImpact: Codable, Hashable, Identifiable {
    let behaviorId: UUID
    let slug: String
    let name: String
    let kind: BehaviorKind
    let status: ImpactStatus
    let nYes: Int
    let nNo: Int
    let needed: ImpactNeeded
    /// Recovery points; `nil` while locked.
    let recovery: BehaviorEffect?
    /// HRV in % of the "no" mean; `nil` while locked or with too few HRV nights.
    let hrvPct: BehaviorEffect?
    let sleepPerformance: BehaviorEffect?
    var id: UUID { behaviorId }
}

/// `GET /v1/behaviors/impact`: unlocked first by effect size, then locked by days needed.
struct BehaviorImpacts: Codable, Hashable {
    let windowDays: Int
    let computedAt: Date
    let impacts: [BehaviorImpact]
}

// MARK: remote config and push (API.md → GET /v1/config, push)

struct RemoteConfig: Codable, Hashable {   // GET /v1/config
    let flags: [String: Bool]     // open keys
    let evaluatedAt: Date
    let ttlSec: Int
    /// The privacy policy in force; consent is given to this version. Always sent;
    /// `nil` only in a config cached before the Beta.
    var privacyPolicyVersion: String? = nil
    var privacyPolicyUrl: String? = nil
}

enum NotificationCategory: String, Codable, CaseIterable, Identifiable {
    case morningScore = "MORNING_SCORE", sessionScored = "SESSION_SCORED", pr = "PR", syncStale = "SYNC_STALE"
    var id: String { rawValue }
}

struct QuietHours: Codable, Equatable, Hashable {
    var from: String   // local "HH:MM"
    var to: String
}

struct NotificationPrefs: Codable, Hashable {   // User.notifications, PATCH /v1/me/notifications
    let categories: [String: Bool]    // keyed by NotificationCategory.rawValue
    let quietHours: QuietHours?

    /// The platform's default: every category on, no quiet hours.
    static let allOn = NotificationPrefs(
        categories: Dictionary(uniqueKeysWithValues: NotificationCategory.allCases.map { ($0.rawValue, true) }),
        quietHours: nil)

    func isOn(_ c: NotificationCategory) -> Bool { categories[c.rawValue] ?? true }
}

struct NotificationPatch: Encodable {   // PATCH /v1/me/notifications
    var categories: [String: Bool]? = nil
    /// nil: leave unchanged; .some(nil): clear; .some(q): set.
    var quietHours: QuietHours?? = nil

    enum CodingKeys: String, CodingKey { case categories, quietHours = "quiet_hours" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(categories, forKey: .categories)
        if let q = quietHours { try c.encode(q, forKey: .quietHours) }   // .some(nil) encodes null
    }
}

enum PushEnvironment: String, Codable { case sandbox, production }

struct PushRegistration: Encodable {   // POST /v1/devices/{id}/push
    let token: String                   // hex
    let env: PushEnvironment
    let locale: String
}

struct RyftPushInfo: Decodable {   // userInfo["ryft"] of a notification
    let category: String?          // absent on the silent refresh
    let kind: String?              // "refresh" on the silent refresh
    let day: String
    let url: String?
}

struct RecomputeRequest: Codable {
    let from: String
    let to: String
}

/// What the client should do about an error (API.md → Errors). Also the `X-RYFT-Gate`
/// header's values and `SyncStatus.gate`.
enum APIErrorCode: String, Codable, CaseIterable, Sendable {
    /// No beta access: the invite screen, `POST /v1/me/invite`.
    case inviteRequired = "invite_required"
    /// Sync without consent to the current policy: the consent screen, `POST /v1/me/consent`.
    case consentRequired = "consent_required"
}

/// `{"error": "…"}` bodies.
struct APIErrorBody: Codable {
    let error: String
    /// Closed enum; a code this build doesn't know decodes as `nil`.
    var code: APIErrorCode? = nil
    /// Same as the `X-Request-ID` header; optional because a proxy may answer on its own.
    var requestId: String? = nil

    init(error: String, code: APIErrorCode? = nil, requestId: String? = nil) {
        self.error = error
        self.code = code
        self.requestId = requestId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = try c.decode(String.self, forKey: .error)
        code = try? c.decodeIfPresent(APIErrorCode.self, forKey: .code)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
    }
}

/// `DELETE /v1/me`.
struct AccountDeleted: Codable, Equatable {
    let status: String
    /// `false` if Supabase couldn't be reached; the platform retries on its own.
    let authUserDeleted: Bool
    /// `nil` without a stored Apple token; `false` if Apple couldn't be reached (retried later).
    var appleTokenRevoked: Bool? = nil
}

/// `POST /v1/me/apple-authorization`: the Sign in with Apple authorization code.
struct AppleAuthorization: Codable {
    let code: String
}

// MARK: - Train
//
// Exercises, plans and logged sessions: API.md → Train and its Swift mirror.
// Every id is a UUID; sessions, their exercises and sets, custom exercises and
// plans get theirs from the app. Two names differ from the mirror: `Session`
// is `TrainSession` here (Supabase's `Session` is the auth session), and
// `SessionComplete` keeps the mirror's name. Closed enums decode leniently: an
// unknown value falls back to a neutral case (or is dropped from a list), so a
// new server value never breaks a screen.

enum ExerciseKind: String, Codable, CaseIterable, Identifiable {
    case barbell, dumbbell, kettlebell, bodyweight, machine, cable, cardio
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        self = ExerciseKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .machine
    }
}

enum LoadType: String, Codable {
    case weight, bodyweight, time, distance

    init(from decoder: Decoder) throws {
        self = LoadType(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .weight
    }
}

/// The platform's muscle names (`primary_muscles`, `secondary_muscles`, `?muscle=`).
enum Muscle: String, Codable, CaseIterable, Identifiable {
    case chest, lats, traps, biceps, triceps, forearms, abs, obliques, glutes, quads, hamstrings, adductors, calves
    case upperBack = "upper_back", frontDelts = "front_delts", sideDelts = "side_delts", rearDelts = "rear_delts"
    case lowerBack = "lower_back"
    var id: String { rawValue }
}

extension KeyedDecodingContainer {
    /// A list of closed-enum values; unknown ones are dropped.
    func decodeLenientList<T: RawRepresentable & Decodable>(_ type: T.Type, _ key: Key) throws -> [T]
    where T.RawValue == String {
        (try decodeIfPresent([String].self, forKey: key) ?? []).compactMap(T.init(rawValue:))
    }
}

struct Exercise: Codable, Hashable, Identifiable {
    let id: UUID
    var slug: String
    /// In the request's `Accept-Language`.
    var name: String
    var nameEn: String
    var nameDe: String
    var kind: ExerciseKind
    var primaryMuscles: [Muscle]
    var secondaryMuscles: [Muscle]
    var equipment: [String]
    var loadType: LoadType
    var bodyweightFactor: Double
    var isUnilateral: Bool
    var isCustom: Bool
    var archived: Bool

    init(id: UUID = UUID(), slug: String, name: String, nameDe: String? = nil, kind: ExerciseKind,
         primaryMuscles: [Muscle], secondaryMuscles: [Muscle] = [], equipment: [String] = [],
         loadType: LoadType = .weight, bodyweightFactor: Double = 0, isUnilateral: Bool = false,
         isCustom: Bool = false, archived: Bool = false) {
        self.id = id
        self.slug = slug
        self.name = name
        self.nameEn = name
        self.nameDe = nameDe ?? name
        self.kind = kind
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.loadType = loadType
        self.bodyweightFactor = bodyweightFactor
        self.isUnilateral = isUnilateral
        self.isCustom = isCustom
        self.archived = archived
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, name, nameEn, nameDe, kind, primaryMuscles, secondaryMuscles, equipment, loadType,
             bodyweightFactor, isUnilateral, isCustom, archived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        name = try c.decode(String.self, forKey: .name)
        nameEn = try c.decodeIfPresent(String.self, forKey: .nameEn) ?? name
        nameDe = try c.decodeIfPresent(String.self, forKey: .nameDe) ?? name
        kind = try c.decodeIfPresent(ExerciseKind.self, forKey: .kind) ?? .machine
        primaryMuscles = try c.decodeLenientList(Muscle.self, .primaryMuscles)
        secondaryMuscles = try c.decodeLenientList(Muscle.self, .secondaryMuscles)
        equipment = try c.decodeIfPresent([String].self, forKey: .equipment) ?? []
        loadType = try c.decodeIfPresent(LoadType.self, forKey: .loadType) ?? .weight
        bodyweightFactor = try c.decodeIfPresent(Double.self, forKey: .bodyweightFactor) ?? 0
        isUnilateral = try c.decodeIfPresent(Bool.self, forKey: .isUnilateral) ?? false
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}

/// `POST /v1/exercises` (create a custom exercise; same `id` again updates it).
struct ExerciseInput: Codable {
    let id: UUID
    let name: String
    var nameDe: String?
    let kind: ExerciseKind
    let primaryMuscles: [Muscle]
    var secondaryMuscles: [Muscle]?
    var equipment: [String]?
    let loadType: LoadType
    var bodyweightFactor: Double?
    var isUnilateral: Bool?

    init(_ e: Exercise) {
        id = e.id
        name = e.name
        nameDe = e.nameDe == e.name ? nil : e.nameDe
        kind = e.kind
        primaryMuscles = e.primaryMuscles
        secondaryMuscles = e.secondaryMuscles
        equipment = e.equipment
        loadType = e.loadType
        bodyweightFactor = e.loadType == .bodyweight ? e.bodyweightFactor : nil
        isUnilateral = e.isUnilateral
    }
}

enum PlanGoal: String, Codable, CaseIterable, Identifiable {
    case strength, hypertrophy, weightlifting, general
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        self = PlanGoal(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .general
    }
}

enum ProgressionType: String, Codable, CaseIterable, Identifiable {
    case linear, percent, none
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        self = ProgressionType(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .none
    }
}

/// `{"type":"linear","increment_kg":2.5,"on_fail":"repeat","deload_after":3}`, `{"type":"percent"}`, `{"type":"none"}`.
struct Progression: Codable, Hashable {
    var type: ProgressionType
    var incrementKg: Double? = nil
    var onFail: String? = nil
    var deloadAfter: Int? = nil

    static let none = Progression(type: .none)
    static let linear = Progression(type: .linear, incrementKg: 2.5, onFail: "repeat", deloadAfter: 3)
    static let percent = Progression(type: .percent)

    static func of(_ type: ProgressionType) -> Progression {
        switch type {
        case .linear: return .linear
        case .percent: return .percent
        case .none: return .none
        }
    }
}

/// How a plan exercise's load is prescribed.
enum TargetKind: String, Codable, CaseIterable, Identifiable {
    case pct1rm = "pct_1rm", rpe, kg, bodyweight
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        self = TargetKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .kg
    }
}

struct PlanExercise: Codable, Hashable, Identifiable {
    let id: UUID
    var exerciseId: UUID
    /// Resolved, read-only (ignored on `PUT`).
    var exercise: Exercise
    var position: Int
    var sets: Int
    var repsMin: Int
    var repsMax: Int
    var targetKind: TargetKind
    var targetValue: Double?
    var restSec: Int
    var supersetGroup: Int?
    var notes: String

    init(id: UUID = UUID(), exercise: Exercise, position: Int, sets: Int, repsMin: Int, repsMax: Int,
         targetKind: TargetKind, targetValue: Double?, restSec: Int, supersetGroup: Int? = nil, notes: String = "") {
        self.id = id
        self.exerciseId = exercise.id
        self.exercise = exercise
        self.position = position
        self.sets = sets
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.targetKind = targetKind
        self.targetValue = targetValue
        self.restSec = restSec
        self.supersetGroup = supersetGroup
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, exerciseId, exercise, position, sets, repsMin, repsMax, targetKind, targetValue, restSec,
             supersetGroup, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exercise = try c.decode(Exercise.self, forKey: .exercise)
        exerciseId = try c.decodeIfPresent(UUID.self, forKey: .exerciseId) ?? exercise.id
        position = try c.decodeLenientInt(.position) ?? 0
        sets = try c.decodeLenientInt(.sets) ?? 1
        repsMin = try c.decodeLenientInt(.repsMin) ?? 1
        repsMax = try c.decodeLenientInt(.repsMax) ?? repsMin
        targetKind = try c.decodeIfPresent(TargetKind.self, forKey: .targetKind) ?? .kg
        targetValue = try c.decodeIfPresent(Double.self, forKey: .targetValue)
        restSec = try c.decodeLenientInt(.restSec) ?? 120
        supersetGroup = try c.decodeLenientInt(.supersetGroup)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

struct PlanDay: Codable, Hashable, Identifiable {
    let id: UUID
    /// `nil`: the same day every week.
    var week: Int?
    var dayIndex: Int
    var name: String
    var exercises: [PlanExercise]

    init(id: UUID = UUID(), week: Int? = nil, dayIndex: Int, name: String, exercises: [PlanExercise]) {
        self.id = id
        self.week = week
        self.dayIndex = dayIndex
        self.name = name
        self.exercises = exercises
    }

    enum CodingKeys: String, CodingKey { case id, week, dayIndex, name, exercises }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        week = try c.decodeLenientInt(.week)
        dayIndex = try c.decodeLenientInt(.dayIndex) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        exercises = try c.decodeIfPresent([PlanExercise].self, forKey: .exercises) ?? []
    }
}

/// `GET /v1/plans/{id}`; `PUT` sends the same document.
struct Plan: Codable, Hashable, Identifiable {
    let id: UUID
    /// Built-in plans only.
    var slug: String?
    var name: String
    var goal: PlanGoal
    /// `nil`: repeating.
    var weeks: Int?
    var daysPerWeek: Int
    var description: String
    /// `nil` = none.
    var progression: Progression?
    var isBuiltin: Bool
    var archived: Bool
    var days: [PlanDay]

    init(id: UUID = UUID(), slug: String? = nil, name: String, goal: PlanGoal, weeks: Int?, daysPerWeek: Int,
         description: String, progression: Progression?, isBuiltin: Bool, archived: Bool = false, days: [PlanDay]) {
        self.id = id
        self.slug = slug
        self.name = name
        self.goal = goal
        self.weeks = weeks
        self.daysPerWeek = daysPerWeek
        self.description = description
        self.progression = progression
        self.isBuiltin = isBuiltin
        self.archived = archived
        self.days = days
    }

    var progressionType: ProgressionType { progression?.type ?? .none }

    enum CodingKeys: String, CodingKey {
        case id, slug, name, goal, weeks, daysPerWeek, description, progression, isBuiltin, archived, days
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        name = try c.decode(String.self, forKey: .name)
        goal = try c.decodeIfPresent(PlanGoal.self, forKey: .goal) ?? .general
        weeks = try c.decodeLenientInt(.weeks)
        daysPerWeek = try c.decodeLenientInt(.daysPerWeek) ?? 3
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        progression = try? c.decodeIfPresent(Progression.self, forKey: .progression)
        isBuiltin = try c.decodeIfPresent(Bool.self, forKey: .isBuiltin) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        days = try c.decodeIfPresent([PlanDay].self, forKey: .days) ?? []
    }
}

/// `GET /v1/plans` list entries: a plan without its days, plus counts.
struct PlanSummary: Codable, Hashable, Identifiable {
    let id: UUID
    var slug: String?
    var name: String
    var goal: PlanGoal
    var weeks: Int?
    var daysPerWeek: Int
    var description: String
    var isBuiltin: Bool
    var archived: Bool
    var dayCount: Int
    var exerciseCount: Int

    init(_ p: Plan) {
        id = p.id
        slug = p.slug
        name = p.name
        goal = p.goal
        weeks = p.weeks
        daysPerWeek = p.daysPerWeek
        description = p.description
        isBuiltin = p.isBuiltin
        archived = p.archived
        dayCount = p.days.count
        exerciseCount = p.days.reduce(0) { $0 + $1.exercises.count }
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, name, goal, weeks, daysPerWeek, description, isBuiltin, archived, dayCount, exerciseCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        name = try c.decode(String.self, forKey: .name)
        goal = try c.decodeIfPresent(PlanGoal.self, forKey: .goal) ?? .general
        weeks = try c.decodeLenientInt(.weeks)
        daysPerWeek = try c.decodeLenientInt(.daysPerWeek) ?? 3
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        isBuiltin = try c.decodeIfPresent(Bool.self, forKey: .isBuiltin) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        dayCount = try c.decodeLenientInt(.dayCount) ?? 0
        exerciseCount = try c.decodeLenientInt(.exerciseCount) ?? 0
    }
}

enum EnrollmentStatus: String, Codable {
    case active, paused, completed

    init(from decoder: Decoder) throws {
        self = EnrollmentStatus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .active
    }
}

struct Enrollment: Codable, Hashable, Identifiable {
    let id: UUID
    let planId: UUID
    var startedAt: Date
    /// 1-based.
    var currentWeek: Int
    /// 0-based: the next plan day to train.
    var currentDayIndex: Int
    var status: EnrollmentStatus
}

/// `GET /v1/plans`.
struct PlansOverview: Codable, Hashable {
    var builtin: [PlanSummary]
    var mine: [PlanSummary]
    var active: Enrollment?

    init(builtin: [PlanSummary], mine: [PlanSummary], active: Enrollment?) {
        self.builtin = builtin
        self.mine = mine
        self.active = active
    }

    enum CodingKeys: String, CodingKey { case builtin, mine, active }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        builtin = try c.decodeIfPresent([PlanSummary].self, forKey: .builtin) ?? []
        mine = try c.decodeIfPresent([PlanSummary].self, forKey: .mine) ?? []
        active = try c.decodeIfPresent(Enrollment.self, forKey: .active)
    }

    func summary(id: UUID) -> PlanSummary? { (builtin + mine).first { $0.id == id } }
}

/// One logged set (`Set` in API.md). `updated_at` is the app's clock and decides conflicts.
struct SessionSet: Codable, Hashable, Identifiable {
    let id: UUID
    var setIndex: Int
    var reps: Int?
    var weightKg: Double?
    var rpe: Double?
    var durationSec: Int?
    var distanceM: Double?
    var isWarmup: Bool
    var completedAt: Date?
    var updatedAt: Date

    init(id: UUID = UUID(), setIndex: Int, reps: Int? = nil, weightKg: Double? = nil, rpe: Double? = nil,
         durationSec: Int? = nil, distanceM: Double? = nil, isWarmup: Bool = false, completedAt: Date? = nil,
         updatedAt: Date = .now) {
        self.id = id
        self.setIndex = setIndex
        self.reps = reps
        self.weightKg = weightKg
        self.rpe = rpe
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.isWarmup = isWarmup
        self.completedAt = completedAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, setIndex, reps, weightKg, rpe, durationSec, distanceM, isWarmup, completedAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        setIndex = try c.decodeLenientInt(.setIndex) ?? 0
        reps = try c.decodeLenientInt(.reps)
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        rpe = try c.decodeIfPresent(Double.self, forKey: .rpe)
        durationSec = try c.decodeLenientInt(.durationSec)
        distanceM = try c.decodeIfPresent(Double.self, forKey: .distanceM)
        isWarmup = try c.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
        completedAt = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? .distantPast
    }
}

/// `GET /v1/plans/today` → `targets[]`: the prescription for one plan exercise.
struct PlanTarget: Codable, Hashable {
    let planExerciseId: UUID
    var exerciseId: UUID
    var sets: Int
    var repsMin: Int
    var repsMax: Int
    var targetKind: TargetKind
    /// Rounded to 2.5 kg; `nil` for RPE and bodyweight targets (and % 1RM without history).
    var targetKg: Double?
    var restSec: Int
    var lastTime: [SessionSet]

    init(planExerciseId: UUID, exerciseId: UUID, sets: Int, repsMin: Int, repsMax: Int, targetKind: TargetKind,
         targetKg: Double?, restSec: Int, lastTime: [SessionSet] = []) {
        self.planExerciseId = planExerciseId
        self.exerciseId = exerciseId
        self.sets = sets
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.targetKind = targetKind
        self.targetKg = targetKg
        self.restSec = restSec
        self.lastTime = lastTime
    }

    enum CodingKeys: String, CodingKey {
        case planExerciseId, exerciseId, sets, repsMin, repsMax, targetKind, targetKg, restSec, lastTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        planExerciseId = try c.decode(UUID.self, forKey: .planExerciseId)
        exerciseId = try c.decodeIfPresent(UUID.self, forKey: .exerciseId) ?? planExerciseId
        sets = try c.decodeLenientInt(.sets) ?? 1
        repsMin = try c.decodeLenientInt(.repsMin) ?? 1
        repsMax = try c.decodeLenientInt(.repsMax) ?? repsMin
        targetKind = try c.decodeIfPresent(TargetKind.self, forKey: .targetKind) ?? .kg
        targetKg = try c.decodeIfPresent(Double.self, forKey: .targetKg)
        restSec = try c.decodeLenientInt(.restSec) ?? 120
        lastTime = try c.decodeIfPresent([SessionSet].self, forKey: .lastTime) ?? []
    }
}

/// `GET /v1/plans/today`; `204` (no active enrolment) is `nil` on the client.
struct PlanToday: Codable, Hashable {
    var enrollment: Enrollment
    var day: PlanDay
    var targets: [PlanTarget]

    func target(for planExercise: PlanExercise) -> PlanTarget? {
        targets.first { $0.planExerciseId == planExercise.id }
    }
}

enum SessionStatus: String, Codable {
    case inProgress = "in_progress", completed, discarded

    init(from decoder: Decoder) throws {
        self = SessionStatus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .completed
    }
}

struct SessionExercise: Codable, Hashable, Identifiable {
    let id: UUID
    var exerciseId: UUID
    /// The plan exercise it fulfils, for progression.
    var planExerciseId: UUID?
    var position: Int
    var notes: String
    var sets: [SessionSet]

    init(id: UUID = UUID(), exerciseId: UUID, planExerciseId: UUID? = nil, position: Int, notes: String = "",
         sets: [SessionSet]) {
        self.id = id
        self.exerciseId = exerciseId
        self.planExerciseId = planExerciseId
        self.position = position
        self.notes = notes
        self.sets = sets
    }

    enum CodingKeys: String, CodingKey { case id, exerciseId, planExerciseId, position, notes, sets }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exerciseId = try c.decode(UUID.self, forKey: .exerciseId)
        planExerciseId = try c.decodeIfPresent(UUID.self, forKey: .planExerciseId)
        position = try c.decodeLenientInt(.position) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        sets = try c.decodeIfPresent([SessionSet].self, forKey: .sets) ?? []
    }
}

enum PRKind: String, Codable, CaseIterable {
    case e1rm
    case maxWeight = "max_weight"
    case maxReps = "max_reps"
    case maxVolume = "max_volume"

    init(from decoder: Decoder) throws {
        self = PRKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .e1rm
    }
}

struct PersonalRecord: Codable, Hashable {
    let exerciseId: UUID
    let kind: PRKind
    let value: Double
    /// The set that set the record (the first one, on a tie).
    var setId: UUID?
    var sessionId: UUID?
    let achievedAt: Date
}

/// `Session` in API.md: the `PUT /v1/sessions/{id}` body and every session
/// response, the `409` body included. After `…/complete` it carries
/// `muscular_trimp`, `strain`, `volume_kg`, `prs` and `workout_id`.
struct TrainSession: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var status: SessionStatus
    var planDayId: UUID?
    var workoutId: UUID?
    var notes: String
    var bodyweightKg: Double?
    var muscularTrimp: Double?
    /// 0–21: the muscular load alone on the strain scale.
    var strain: Double?
    var volumeKg: Double?
    var deviceId: UUID?
    var exercises: [SessionExercise]
    /// Records this session set; `[]` before completion.
    var prs: [PersonalRecord]
    /// Server time of the last change (ignored on `PUT`).
    var updatedAt: Date?

    init(id: UUID = UUID(), title: String, startedAt: Date, endedAt: Date? = nil, status: SessionStatus,
         planDayId: UUID? = nil, workoutId: UUID? = nil, notes: String = "", bodyweightKg: Double? = nil,
         muscularTrimp: Double? = nil, strain: Double? = nil, volumeKg: Double? = nil, deviceId: UUID? = nil,
         exercises: [SessionExercise], prs: [PersonalRecord] = [], updatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.planDayId = planDayId
        self.workoutId = workoutId
        self.notes = notes
        self.bodyweightKg = bodyweightKg
        self.muscularTrimp = muscularTrimp
        self.strain = strain
        self.volumeKg = volumeKg
        self.deviceId = deviceId
        self.exercises = exercises
        self.prs = prs
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, startedAt, endedAt, status, planDayId, workoutId, notes, bodyweightKg, muscularTrimp,
             strain, volumeKg, deviceId, exercises, prs, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try? c.decodeIfPresent(Date.self, forKey: .endedAt)
        status = try c.decodeIfPresent(SessionStatus.self, forKey: .status) ?? .completed
        planDayId = try c.decodeIfPresent(UUID.self, forKey: .planDayId)
        workoutId = try c.decodeIfPresent(UUID.self, forKey: .workoutId)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        bodyweightKg = try c.decodeIfPresent(Double.self, forKey: .bodyweightKg)
        muscularTrimp = try c.decodeIfPresent(Double.self, forKey: .muscularTrimp)
        strain = try c.decodeIfPresent(Double.self, forKey: .strain)
        volumeKg = try c.decodeIfPresent(Double.self, forKey: .volumeKg)
        deviceId = try c.decodeIfPresent(UUID.self, forKey: .deviceId)
        exercises = try c.decodeIfPresent([SessionExercise].self, forKey: .exercises) ?? []
        prs = try c.decodeIfPresent([PersonalRecord].self, forKey: .prs) ?? []
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// `GET /v1/sessions` entries and `DayStrain.sessions`.
struct SessionSummary: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var status: SessionStatus
    var planDayId: UUID?
    var workoutId: UUID?
    /// `nil` while in progress.
    var durationMin: Int?
    var exerciseCount: Int
    /// Completed working sets.
    var setCount: Int
    var volumeKg: Double?
    var muscularTrimp: Double?
    var strain: Double?
    var prCount: Int

    init(_ s: TrainSession) {
        id = s.id
        title = s.title
        startedAt = s.startedAt
        endedAt = s.endedAt
        status = s.status
        planDayId = s.planDayId
        workoutId = s.workoutId
        durationMin = s.endedAt.map { Int(($0.timeIntervalSince(s.startedAt) / 60).rounded()) }
        exerciseCount = s.exercises.count
        setCount = s.exercises.flatMap(\.sets).filter { !$0.isWarmup && $0.completedAt != nil }.count
        volumeKg = s.volumeKg
        muscularTrimp = s.muscularTrimp
        strain = s.strain
        prCount = s.prs.count
    }

    enum CodingKeys: String, CodingKey {
        case id, title, startedAt, endedAt, status, planDayId, workoutId, durationMin, exerciseCount, setCount,
             volumeKg, muscularTrimp, strain, prCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try? c.decodeIfPresent(Date.self, forKey: .endedAt)
        status = try c.decodeIfPresent(SessionStatus.self, forKey: .status) ?? .completed
        planDayId = try c.decodeIfPresent(UUID.self, forKey: .planDayId)
        workoutId = try c.decodeIfPresent(UUID.self, forKey: .workoutId)
        durationMin = try c.decodeLenientInt(.durationMin)
        exerciseCount = try c.decodeLenientInt(.exerciseCount) ?? 0
        setCount = try c.decodeLenientInt(.setCount) ?? 0
        volumeKg = try c.decodeIfPresent(Double.self, forKey: .volumeKg)
        muscularTrimp = try c.decodeIfPresent(Double.self, forKey: .muscularTrimp)
        strain = try c.decodeIfPresent(Double.self, forKey: .strain)
        prCount = try c.decodeLenientInt(.prCount) ?? 0
    }
}

/// `POST /v1/sessions/{id}/complete` body. Send `ended_at` when completing from the offline queue.
struct SessionComplete: Codable {
    var bodyweightKg: Double?
    var endedAt: Date?
}

struct E1RMPoint: Codable, Hashable, Identifiable {
    let day: String
    let value: Double
    var id: String { day }
    var date: Date { DayFormat.date(from: day) ?? .now }
}

struct ExerciseHistorySession: Codable, Hashable {
    let sessionId: UUID
    /// The session's local day, `YYYY-MM-DD`.
    let date: String
    let startedAt: Date
    var sets: [SessionSet]
}

/// `GET /v1/exercises/{id}/history`: sessions newest first, e1RM oldest first.
struct ExerciseHistory: Codable, Hashable {
    let exerciseId: UUID
    var prs: [PersonalRecord]
    var sessions: [ExerciseHistorySession]
    var e1rm: [E1RMPoint]

    init(exerciseId: UUID, prs: [PersonalRecord], sessions: [ExerciseHistorySession], e1rm: [E1RMPoint]) {
        self.exerciseId = exerciseId
        self.prs = prs
        self.sessions = sessions
        self.e1rm = e1rm
    }

    enum CodingKeys: String, CodingKey { case exerciseId, prs, sessions, e1rm }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exerciseId = try c.decode(UUID.self, forKey: .exerciseId)
        prs = try c.decodeIfPresent([PersonalRecord].self, forKey: .prs) ?? []
        sessions = try c.decodeIfPresent([ExerciseHistorySession].self, forKey: .sessions) ?? []
        e1rm = try c.decodeIfPresent([E1RMPoint].self, forKey: .e1rm) ?? []
    }
}

// MARK: - Activities (draft)
//
// Activities the user recorded or added, and manual sleep. A mirror of the platform brief
// (`docs/work/2026-10-22-my-day-activities/platform-brief.md`), not of API.md: API.md → Activities isn't
// published yet, and api-contract-keeper reconciles these shapes with it (C1). No field beyond the brief.
// Two names differ from the brief: `Activity` is `SportActivity` here (ActivityKit owns `Activity`), and
// `strain_source: "none"` is `StrainSource.noSource` (a case called `none` would read as `Optional.none`).
// The closed `sport` enum lives here so the contract check, which compiles this file alone, can decode an
// activity; its catalogue (symbols, HealthKit types, tracking) is `Ryft/Activities/Sport.swift`.

/// `sport`: one entry of the app's catalogue (`Sport.swift`). The raw value is the API's; an unknown
/// value decodes as `.other`.
enum Sport: String, CaseIterable, Codable, Identifiable, Sendable {
    case running
    case trailRunning = "trail_running"
    case walking
    case hiking
    case cycling
    case mountainBiking = "mountain_biking"
    case gravel
    case indoorRunning = "indoor_running"
    case indoorCycling = "indoor_cycling"
    case rowing
    case swimming
    case strength
    case hiit
    case yoga
    case mobility
    case climbing
    case skiing
    case skiTouring = "ski_touring"
    case football
    case tennis
    case padel
    case other

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        self = Sport(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }
}

/// `origin`: typed in by the user, or recorded by RYFT with GPS (or the pedometer). Unknown → `manual`.
enum ActivityOrigin: String, Codable, Sendable {
    case manual, recorded

    init(from decoder: Decoder) throws {
        self = ActivityOrigin(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .manual
    }
}

/// `strain_source`: where the platform took the activity's strain from.
enum StrainSource: String, Codable, Sendable {
    case heartRate = "heart_rate"
    case perceivedEffort = "perceived_effort"
    /// `"none"`: no heart rate for the window and no effort mapping, so no strain.
    case noSource = "none"
}

/// One entry of `splits`: a kilometre (the last one partial) of a recorded activity.
struct ActivitySplit: Codable, Hashable, Sendable {
    let index: Int
    let distanceM: Double
    /// Moving time in the split.
    let durationSec: Double
    let ascentM: Double?
}

/// API.md → Activities `Activity` (renamed: ActivityKit owns `Activity`). The app picks the `id`, so a `PUT`
/// is idempotent. The platform sets the fields after `clientUpdatedAt`; `SportActivityPut` is the body that
/// leaves them out.
///
/// This type's own encoding is what the read model caches: it keeps the platform's fields and never writes
/// `route` or `hr_samples` (ADR 0006, review S5), whichever path caches it. Decoding reads them, for the detail
/// screen's memory. Its descriptions and mirror leave out the route, the samples and the notes (design.md §8.3).
struct SportActivity: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var sport: Sport
    var origin: ActivityOrigin
    var start: Date
    var end: Date
    var movingSec: Double
    var distanceM: Double?
    var ascentM: Double?
    var descentM: Double?
    /// 1–10.
    var perceivedEffort: Int?
    /// At most 500 characters.
    var notes: String?
    var splits: [ActivitySplit]?
    /// Encoded polyline, trimmed on the device; only with the route opt-in. Never encoded but by `SportActivityPut`.
    var route: String?
    /// Live heart rate from a Bluetooth sensor. Never encoded but by `SportActivityPut`.
    var hrSamples: [HRPoint]?
    var clientUpdatedAt: Date
    // Set by the platform, never sent.
    var strain: Double?
    var strainSource: StrainSource?
    /// The heart-rate source's name, verbatim.
    var hrSource: String?
    /// The tracker workout this activity was merged with: that workout's row is hidden (ADR 0006).
    var mergedWith: UUID?
    /// Values not specified yet (API request R2).
    var scoringState: String?

    init(id: UUID, sport: Sport, origin: ActivityOrigin, start: Date, end: Date, movingSec: Double,
         distanceM: Double? = nil, ascentM: Double? = nil, descentM: Double? = nil, perceivedEffort: Int? = nil,
         notes: String? = nil, splits: [ActivitySplit]? = nil, route: String? = nil, hrSamples: [HRPoint]? = nil,
         clientUpdatedAt: Date, strain: Double? = nil, strainSource: StrainSource? = nil, hrSource: String? = nil,
         mergedWith: UUID? = nil, scoringState: String? = nil) {
        self.id = id
        self.sport = sport
        self.origin = origin
        self.start = start
        self.end = end
        self.movingSec = movingSec
        self.distanceM = distanceM
        self.ascentM = ascentM
        self.descentM = descentM
        self.perceivedEffort = perceivedEffort
        self.notes = notes
        self.splits = splits
        self.route = route
        self.hrSamples = hrSamples
        self.clientUpdatedAt = clientUpdatedAt
        self.strain = strain
        self.strainSource = strainSource
        self.hrSource = hrSource
        self.mergedWith = mergedWith
        self.scoringState = scoringState
    }

    enum CodingKeys: String, CodingKey {
        case id, sport, origin, start, end, movingSec, distanceM, ascentM, descentM, perceivedEffort, notes, splits
        case route, hrSamples, clientUpdatedAt, strain, strainSource, hrSource, mergedWith, scoringState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sport = try c.decode(Sport.self, forKey: .sport)
        origin = try c.decode(ActivityOrigin.self, forKey: .origin)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        movingSec = try c.decode(Double.self, forKey: .movingSec)
        distanceM = try c.decodeIfPresent(Double.self, forKey: .distanceM)
        ascentM = try c.decodeIfPresent(Double.self, forKey: .ascentM)
        descentM = try c.decodeIfPresent(Double.self, forKey: .descentM)
        perceivedEffort = try c.decodeLenientInt(.perceivedEffort)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        splits = try c.decodeIfPresent([ActivitySplit].self, forKey: .splits)
        route = try c.decodeIfPresent(String.self, forKey: .route)
        hrSamples = try c.decodeIfPresent([HRPoint].self, forKey: .hrSamples)
        clientUpdatedAt = try c.decode(Date.self, forKey: .clientUpdatedAt)
        strain = try c.decodeIfPresent(Double.self, forKey: .strain)
        // A source this build doesn't know is shown like a missing one, never as "no heart rate".
        strainSource = try c.decodeIfPresent(String.self, forKey: .strainSource).flatMap(StrainSource.init(rawValue:))
        hrSource = try c.decodeIfPresent(String.self, forKey: .hrSource)
        mergedWith = try c.decodeIfPresent(UUID.self, forKey: .mergedWith)
        scoringState = try c.decodeIfPresent(String.self, forKey: .scoringState)
    }

    /// Everything but `route` and `hr_samples`: the cached copy.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sport, forKey: .sport)
        try c.encode(origin, forKey: .origin)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(movingSec, forKey: .movingSec)
        try c.encodeIfPresent(distanceM, forKey: .distanceM)
        try c.encodeIfPresent(ascentM, forKey: .ascentM)
        try c.encodeIfPresent(descentM, forKey: .descentM)
        try c.encodeIfPresent(perceivedEffort, forKey: .perceivedEffort)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(splits, forKey: .splits)
        try c.encode(clientUpdatedAt, forKey: .clientUpdatedAt)
        try c.encodeIfPresent(strain, forKey: .strain)
        try c.encodeIfPresent(strainSource, forKey: .strainSource)
        try c.encodeIfPresent(hrSource, forKey: .hrSource)
        try c.encodeIfPresent(mergedWith, forKey: .mergedWith)
        try c.encodeIfPresent(scoringState, forKey: .scoringState)
    }

    /// What list and day reads keep (API request R16): no route and no heart-rate samples. The detail screen
    /// fetches a route on demand and holds it in memory only (ADR 0005, 0006). The encoding drops both anyway;
    /// this keeps them out of values held in memory too.
    var withoutRouteOrHeartRate: SportActivity {
        var copy = self
        copy.route = nil
        copy.hrSamples = nil
        return copy
    }
}

extension SportActivity: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Times, totals and the platform's fields; of the route, the samples and the notes only whether they're
    /// there. `print`, interpolation, `dump`, `debugPrint` and the debugger show this (design.md §8.3).
    var description: String {
        var parts = ["\(id.uuidString)", sport.rawValue, origin.rawValue, start.ISO8601Format(), "\(Int(movingSec)) s"]
        if let distanceM { parts.append("\(Int(distanceM)) m") }
        if let strain { parts.append("strain \(strain)") }
        if let scoringState { parts.append(scoringState) }
        if route != nil { parts.append("route") }
        if let hrSamples { parts.append("\(hrSamples.count) hr samples") }
        if let notes { parts.append("notes \(notes.count) chars") }
        return "SportActivity(\(parts.joined(separator: ", ")))"
    }

    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(self, children: ["id": id, "sport": sport, "origin": origin, "start": start, "end": end,
                                "movingSec": movingSec, "distanceM": distanceM as Any, "ascentM": ascentM as Any,
                                "descentM": descentM as Any, "perceivedEffort": perceivedEffort as Any,
                                "splits": splits as Any, "clientUpdatedAt": clientUpdatedAt, "strain": strain as Any,
                                "strainSource": strainSource as Any, "hrSource": hrSource as Any,
                                "mergedWith": mergedWith as Any, "scoringState": scoringState as Any],
               displayStyle: .struct)
    }
}

/// The body of `PUT /v1/activities/{id}`: the activity without the fields the platform sets. A field the
/// user can clear goes as `null` when it's empty, so the platform clears it; `route`, `hr_samples` and
/// `splits` are left out when there are none, so the platform keeps what it has (API request R19).
struct SportActivityPut: Encodable, Sendable {
    let activity: SportActivity

    init(_ activity: SportActivity) {
        self.activity = activity
    }

    private typealias Keys = SportActivity.CodingKeys

    func encode(to encoder: Encoder) throws {
        let a = activity
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(a.id, forKey: .id)
        try c.encode(a.sport, forKey: .sport)
        try c.encode(a.origin, forKey: .origin)
        try c.encode(a.start, forKey: .start)
        try c.encode(a.end, forKey: .end)
        try c.encode(a.movingSec, forKey: .movingSec)
        // Editable: an empty one is sent as null.
        try c.encode(a.distanceM, forKey: .distanceM)
        try c.encode(a.ascentM, forKey: .ascentM)
        try c.encode(a.descentM, forKey: .descentM)
        try c.encode(a.perceivedEffort, forKey: .perceivedEffort)
        try c.encode(a.notes, forKey: .notes)
        // Measured or sent once: left out when there are none.
        try c.encodeIfPresent(a.splits, forKey: .splits)
        try c.encodeIfPresent(a.route, forKey: .route)
        try c.encodeIfPresent(a.hrSamples, forKey: .hrSamples)
        try c.encode(a.clientUpdatedAt, forKey: .clientUpdatedAt)
    }
}

/// The body of `PUT /v1/sleep/manual/{day}`: a night the user added ("Add sleep").
struct ManualSleepPut: Codable, Hashable, Sendable {
    let bed: Date
    let wake: Date
}

// MARK: - Helpers

extension KeyedDecodingContainer {
    /// Decodes an optional Int that may be sent as a JSON float (e.g. 82.0).
    func decodeLenientInt(_ key: Key) throws -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try decodeIfPresent(Double.self, forKey: key) { return Int(d.rounded()) }
        return nil
    }
}

enum DateParsing {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// RFC3339 with or without fractional seconds (Go emits nanoseconds).
    static func rfc3339(_ s: String) -> Date? {
        fractional.date(from: s) ?? plain.date(from: s)
    }
}
