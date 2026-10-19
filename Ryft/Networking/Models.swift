// Wire types. Mirror the v1 API contract (plattform/docs/API.md, and
// backend/internal/model/model.go) — JSON keys are snake_case there; the
// shared decoder's .convertFromSnakeCase strategy maps them (see
// APIClient.jsonDecoder).
//
// Read-side types stay null-tolerant: every score can be null while the
// platform calibrates, and the on-disk cache may predate a field. Views render
// "–" for anything nil. Unknown response fields are ignored (API.md, v1 rule).
import Foundation

// MARK: - Sync (write side, unchanged)

enum SampleType: String, Codable, CaseIterable {
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
}

struct SleepSegment: Codable {
    let start: Date
    let end: Date
    let stage: SleepStage
    let source: String
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

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SyncRequest: Codable {
    let deviceId: UUID
    let deviceName: String
    let samples: [Sample]
    let sleep: [SleepSegment]
    let workouts: [Workout]
}

struct SyncResponse: Codable {
    let samples: Int
    let sleep: Int
    let workouts: Int
    let daysTouched: [String]
}

// MARK: - Daily score

enum ReadinessState: String, Codable, CaseIterable {
    case balanced, strained, depleted, calibrating
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

    var id: String { day }
    var date: Date { DayFormat.date(from: day) ?? .now }

    static func empty(day: String) -> DailyScore {
        DailyScore(day: day, state: .calibrating)
    }

    init(day: String, readiness: Int? = nil, state: ReadinessState? = nil, recovery: Int? = nil,
         strain: Double? = nil, steps: Int? = nil, activeKcal: Int? = nil, strengthMin: Int? = nil,
         volumeKg: Double? = nil, sleepPerformance: Int? = nil,
         sleepNeedMin: Int? = nil, sleepActualMin: Int? = nil, sleepDebtMin: Int? = nil, hrvMs: Double? = nil,
         rhr: Double? = nil, respRate: Double? = nil, spo2: Double? = nil, hrvBaselineMs: Double? = nil,
         rhrBaseline: Double? = nil, baselineDays: Int = 0, calibrating: Bool = false, computedAt: Date? = nil) {
        self.day = day
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
    }

    enum CodingKeys: String, CodingKey {
        case day, readiness, state, recovery, strain, steps, activeKcal, strengthMin, volumeKg, sleepPerformance, sleepNeedMin,
             sleepActualMin, sleepDebtMin, hrvMs, rhr, respRate, spo2, hrvBaselineMs, rhrBaseline,
             baselineDays, calibrating, computedAt
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
    var hasStages: Bool
    /// The hypnogram (only on `GET /v1/days/{day}`).
    var segments: [SleepInterval]

    init(start: Date? = nil, end: Date? = nil, totalMin: Int? = nil, inBedMin: Int? = nil,
         efficiency: Int? = nil, stages: [StageShare] = [], quality: Int? = nil,
         qualityLabel: SleepQualityLabel? = nil, hasStages: Bool = true, segments: [SleepInterval] = []) {
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
    }

    enum CodingKeys: String, CodingKey {
        case start, end, totalMin, inBedMin, efficiency, stages, quality, qualityLabel, hasStages, segments
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
    var hasStages: Bool

    var id: String { day }
    var date: Date { DayFormat.date(from: day) ?? .now }

    init(day: String, totalMin: Int?, stages: [StageShare], quality: Int?, start: Date? = nil, end: Date? = nil,
         inBedMin: Int? = nil, efficiency: Int? = nil, qualityLabel: SleepQualityLabel? = nil, hasStages: Bool = true) {
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
    }

    enum CodingKeys: String, CodingKey {
        case day, start, end, totalMin, inBedMin, efficiency, stages, quality, qualityLabel, hasStages
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
    }

    func minutes(for stage: SleepStageKind) -> Int {
        stages.first { $0.stage == stage }?.min ?? 0
    }
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

    init(range: String, from: String? = nil, to: String? = nil, days: [SleepNight], avgTotalMin: Int?,
         avgQuality: Int?, avgInBedMin: Int? = nil, avgEfficiency: Int? = nil, avgStages: [StageShare] = []) {
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
    }

    enum CodingKeys: String, CodingKey {
        case range, from, to, days, nights, avgTotalMin, avgInBedMin, avgEfficiency, avgQuality, avgStages
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
    }
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

// MARK: - User

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
}

struct UserPatch: Codable {
    var tz: String? = nil
    var maxHr: Int? = nil
    var sleepBaseMin: Int? = nil
}

struct RecomputeRequest: Codable {
    let from: String
    let to: String
}

/// `{"error": "…"}` bodies.
struct APIErrorBody: Codable {
    let error: String
    /// Same as the `X-Request-ID` header; optional because a proxy may answer on its own.
    var requestId: String? = nil
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
