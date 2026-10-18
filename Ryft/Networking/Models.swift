// Wire types. Mirror the v1 API contract (plattform/docs/API.md, and
// backend/internal/model/model.go) — JSON keys are snake_case there; the
// shared decoder's .convertFromSnakeCase strategy maps them (see
// APIClient.jsonDecoder).
//
// Read-side types decode leniently: every score can be null while the platform
// is calibrating, ints may arrive as floats, and fields newer than the running
// backend may be missing altogether. Views render "–" for anything nil.
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
    var sleepPerformance: Int?
    var sleepNeedMin: Int?
    var sleepActualMin: Int?
    var sleepDebtMin: Int?
    var hrvMs: Double?
    var rhr: Double?
    var respRate: Double?
    var spo2: Double?
    var calibrating: Bool
    var details: [String: JSONValue]?
    var computedAt: Date?

    var id: String { day }
    var date: Date { DayFormat.date(from: day) ?? .now }

    static func empty(day: String) -> DailyScore {
        DailyScore(day: day, calibrating: true)
    }

    init(day: String, readiness: Int? = nil, state: ReadinessState? = nil, recovery: Int? = nil,
         strain: Double? = nil, sleepPerformance: Int? = nil, sleepNeedMin: Int? = nil,
         sleepActualMin: Int? = nil, sleepDebtMin: Int? = nil, hrvMs: Double? = nil, rhr: Double? = nil,
         respRate: Double? = nil, spo2: Double? = nil, calibrating: Bool = false,
         details: [String: JSONValue]? = nil, computedAt: Date? = nil) {
        self.day = day
        self.readiness = readiness
        self.state = state
        self.recovery = recovery
        self.strain = strain
        self.sleepPerformance = sleepPerformance
        self.sleepNeedMin = sleepNeedMin
        self.sleepActualMin = sleepActualMin
        self.sleepDebtMin = sleepDebtMin
        self.hrvMs = hrvMs
        self.rhr = rhr
        self.respRate = respRate
        self.spo2 = spo2
        self.calibrating = calibrating
        self.details = details
        self.computedAt = computedAt
    }

    enum CodingKeys: String, CodingKey {
        case day, readiness, state, recovery, strain, sleepPerformance, sleepNeedMin, sleepActualMin,
             sleepDebtMin, hrvMs, rhr, respRate, spo2, calibrating, details, computedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        readiness = try c.decodeLenientInt(.readiness)
        state = try? c.decodeIfPresent(ReadinessState.self, forKey: .state)
        recovery = try c.decodeLenientInt(.recovery)
        strain = try c.decodeIfPresent(Double.self, forKey: .strain)
        sleepPerformance = try c.decodeLenientInt(.sleepPerformance)
        sleepNeedMin = try c.decodeLenientInt(.sleepNeedMin)
        sleepActualMin = try c.decodeLenientInt(.sleepActualMin)
        sleepDebtMin = try c.decodeLenientInt(.sleepDebtMin)
        hrvMs = try c.decodeIfPresent(Double.self, forKey: .hrvMs)
        rhr = try c.decodeIfPresent(Double.self, forKey: .rhr)
        respRate = try c.decodeIfPresent(Double.self, forKey: .respRate)
        spo2 = try c.decodeIfPresent(Double.self, forKey: .spo2)
        calibrating = try c.decodeIfPresent(Bool.self, forKey: .calibrating) ?? false
        details = try? c.decodeIfPresent([String: JSONValue].self, forKey: .details)
        computedAt = try? c.decodeIfPresent(Date.self, forKey: .computedAt)
    }

    // MARK: derived (fallbacks for platforms that predate readiness/state)

    /// Readiness, or recovery on platforms that don't compute readiness yet.
    var readinessValue: Int? { readiness ?? recovery }

    /// Server state, or one derived from the readiness bands.
    var resolvedState: ReadinessState? {
        if let state { return state }
        if calibrating { return .calibrating }
        guard let r = readinessValue else { return nil }
        switch r {
        case 67...: return .balanced
        case 34...: return .strained
        default: return .depleted
        }
    }

    /// Nights of history the baseline is built from (`details.baseline_days`).
    var baselineNights: Int? { details?[lenient: "baseline_days"]?.intValue }

    /// Nights until the 7-night baseline is complete (≥ 1 while calibrating).
    var nightsToGo: Int {
        if let n = details?[lenient: "nights_to_go"]?.intValue { return max(1, n) }
        return max(1, Self.baselineNightsRequired - (baselineNights ?? 0))
    }

    static let baselineNightsRequired = 7

    /// Minutes in HRR zones 1–5 for the whole day (`details.zone_minutes`).
    var zoneMinutes: [Double]? {
        guard let arr = details?[lenient: "zone_minutes"]?.arrayValue else { return nil }
        let values = arr.compactMap(\.doubleValue)
        return values.count == 5 ? values : nil
    }

    var trimp: Double? { details?[lenient: "trimp"]?.doubleValue }

    /// Sleep start/end as reported in `details` (local RFC3339).
    var sleepStart: Date? { details?[lenient: "sleep_start"]?.stringValue.flatMap(DateParsing.rfc3339) }
    var sleepEnd: Date? { details?[lenient: "sleep_end"]?.stringValue.flatMap(DateParsing.rfc3339) }
}

// MARK: - Sleep

/// The four display stages. HealthKit's "core" is shown as "light".
enum SleepStageKind: String, Codable, CaseIterable, Identifiable {
    case deep, light, rem, awake

    var id: String { rawValue }

    init?(apiValue: String) {
        switch apiValue.lowercased() {
        case "deep": self = .deep
        case "light", "core", "asleep": self = .light
        case "rem": self = .rem
        case "awake": self = .awake
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .deep: return String(localized: "Deep")
        case .light: return String(localized: "Light")
        case .rem: return String(localized: "REM")
        case .awake: return String(localized: "Awake")
        }
    }
}

struct StageShare: Codable, Hashable, Identifiable {
    let stage: SleepStageKind
    let min: Int
    /// Percentage 0…100 (a 0…1 fraction from the server is normalised).
    var pct: Double?

    var id: SleepStageKind { stage }

    init(stage: SleepStageKind, min: Int, pct: Double? = nil) {
        self.stage = stage
        self.min = min
        self.pct = pct
    }

    enum CodingKeys: String, CodingKey { case stage, min, pct }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .stage)
        guard let s = SleepStageKind(apiValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .stage, in: c, debugDescription: "unknown stage \(raw)")
        }
        stage = s
        min = try c.decodeLenientInt(.min) ?? 0
        pct = try c.decodeIfPresent(Double.self, forKey: .pct)
    }
}

struct SleepDetail: Codable, Hashable {
    var start: Date?
    var end: Date?
    var totalMin: Int?
    var inBedMin: Int?
    /// Percentage 0…100 (fractions are normalised in `efficiencyPercent`).
    var efficiency: Double?
    var stages: [StageShare]
    var quality: Int?
    var qualityLabel: String?
    var hasStages: Bool

    init(start: Date? = nil, end: Date? = nil, totalMin: Int? = nil, inBedMin: Int? = nil,
         efficiency: Double? = nil, stages: [StageShare] = [], quality: Int? = nil,
         qualityLabel: String? = nil, hasStages: Bool = true) {
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
        case start, end, totalMin, inBedMin, efficiency, stages, quality, qualityLabel, hasStages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try? c.decodeIfPresent(Date.self, forKey: .start)
        end = try? c.decodeIfPresent(Date.self, forKey: .end)
        totalMin = try c.decodeLenientInt(.totalMin)
        inBedMin = try c.decodeLenientInt(.inBedMin)
        efficiency = try c.decodeIfPresent(Double.self, forKey: .efficiency)
        stages = (try? c.decodeIfPresent([StageShare].self, forKey: .stages)) ?? []
        quality = try c.decodeLenientInt(.quality)
        qualityLabel = try c.decodeIfPresent(String.self, forKey: .qualityLabel)
        hasStages = try c.decodeIfPresent(Bool.self, forKey: .hasStages) ?? !stages.isEmpty
    }

    /// Stages in display order (deep, light, rem, awake) with percentages that
    /// always sum to 100. Server percentages win when present.
    var displayStages: [StageShare] {
        let computed = SleepMath.shares(stages.reduce(into: [:]) { $0[$1.stage, default: 0] += $1.min })
        return computed.map { share in
            if let server = stages.first(where: { $0.stage == share.stage })?.pct {
                return StageShare(stage: share.stage, min: share.min, pct: SleepMath.percent(server))
            }
            return share
        }
    }

    var efficiencyPercent: Double? {
        if let efficiency { return SleepMath.percent(efficiency) }
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
        qualityLabel ?? quality.map(SleepMath.qualityLabel)
    }

    /// Builds a sleep detail out of what a pre-v1 platform puts in
    /// `DailyScore.details` (`sleep_stages`, `sleep_start`, `sleep_end`).
    init?(fallbackFrom score: DailyScore) {
        let stagesJSON = score.details?[lenient: "sleep_stages"]?.objectValue
        guard score.sleepActualMin != nil || stagesJSON != nil else { return nil }
        var minutes: [SleepStageKind: Int] = [:]
        var inBed: Int?
        for (key, value) in stagesJSON ?? [:] {
            let k = JSONValue.normalise(key)
            if k == "inbed" { inBed = value.intValue; continue }
            if let stage = SleepStageKind(apiValue: k), let m = value.intValue, m > 0 {
                minutes[stage, default: 0] += m
            }
        }
        let hasStages = score.details?[lenient: "sleep_has_stages"]?.boolValue ?? !minutes.isEmpty
        let asleep = minutes.filter { $0.key != .awake }.values.reduce(0, +)
        self.init(start: score.sleepStart, end: score.sleepEnd,
                  totalMin: score.sleepActualMin ?? (asleep > 0 ? asleep : nil),
                  inBedMin: inBed, efficiency: nil,
                  stages: SleepMath.shares(minutes).filter { $0.min > 0 },
                  quality: score.sleepPerformance, qualityLabel: nil, hasStages: hasStages)
    }
}

enum SleepRangeKind: String, Codable, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    var days: Int { self == .week ? 7 : 30 }
}

struct SleepNight: Codable, Hashable, Identifiable {
    let day: String
    var totalMin: Int?
    var stages: [StageShare]
    var quality: Int?
    /// Optional bedtime / wake time, used for the consistency hint.
    var start: Date?
    var end: Date?

    var id: String { day }
    var date: Date { DayFormat.date(from: day) ?? .now }

    init(day: String, totalMin: Int?, stages: [StageShare], quality: Int?, start: Date? = nil, end: Date? = nil) {
        self.day = day
        self.totalMin = totalMin
        self.stages = stages
        self.quality = quality
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey { case day, totalMin, stages, quality, start, end }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        totalMin = try c.decodeLenientInt(.totalMin)
        quality = try c.decodeLenientInt(.quality)
        start = try? c.decodeIfPresent(Date.self, forKey: .start)
        end = try? c.decodeIfPresent(Date.self, forKey: .end)
        // `stages` is either [{stage, min, pct}] or {"deep": 92, ...}.
        if let list = try? c.decodeIfPresent([StageShare].self, forKey: .stages) {
            stages = list
        } else if let map = try? c.decodeIfPresent([String: Double].self, forKey: .stages) {
            var minutes: [SleepStageKind: Int] = [:]
            for (k, v) in map {
                if let s = SleepStageKind(apiValue: JSONValue.normalise(k)) { minutes[s, default: 0] += Int(v.rounded()) }
            }
            stages = SleepMath.shares(minutes).filter { $0.min > 0 }
        } else {
            stages = []
        }
    }

    func minutes(for stage: SleepStageKind) -> Int {
        stages.first { $0.stage == stage }?.min ?? 0
    }
}

struct SleepRange: Codable, Hashable {
    let range: String
    var days: [SleepNight]
    var avgTotalMin: Double?
    var avgQuality: Double?

    init(range: String, days: [SleepNight], avgTotalMin: Double?, avgQuality: Double?) {
        self.range = range
        self.days = days
        self.avgTotalMin = avgTotalMin
        self.avgQuality = avgQuality
    }

    enum CodingKeys: String, CodingKey { case range, days, avgTotalMin, avgQuality }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        range = try c.decodeIfPresent(String.self, forKey: .range) ?? ""
        days = try c.decodeIfPresent([SleepNight].self, forKey: .days) ?? []
        avgTotalMin = try c.decodeIfPresent(Double.self, forKey: .avgTotalMin)
        avgQuality = try c.decodeIfPresent(Double.self, forKey: .avgQuality)
    }
}

// MARK: - Day detail

struct DayDetail: Codable, Hashable {
    var score: DailyScore
    var sleep: SleepDetail?
    var workouts: [Workout]

    init(score: DailyScore, sleep: SleepDetail?, workouts: [Workout]) {
        self.score = score
        self.sleep = sleep
        self.workouts = workouts
    }

    enum CodingKeys: String, CodingKey { case score, sleep, workouts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = try c.decode(DailyScore.self, forKey: .score)
        sleep = try? c.decodeIfPresent(SleepDetail.self, forKey: .sleep)
        workouts = try c.decodeIfPresent([Workout].self, forKey: .workouts) ?? []
    }

    /// `sleep`, or one reconstructed from `score.details` on older platforms.
    var resolvedSleep: SleepDetail? { sleep ?? SleepDetail(fallbackFrom: score) }
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

enum TrendMetric: String, Codable, CaseIterable, Identifiable {
    case readiness, recovery, strain, sleep, hrv, rhr
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

    enum CodingKeys: String, CodingKey { case metric, range, points, avg, min, max, baseline }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metric = try c.decodeIfPresent(String.self, forKey: .metric) ?? ""
        range = try c.decodeIfPresent(String.self, forKey: .range) ?? ""
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

/// Untyped JSON for `DailyScore.details`.
///
/// Note: the shared decoder's `.convertFromSnakeCase` also rewrites dictionary
/// keys, so a key may arrive as `sleep_start` (in-memory) or `sleepStart`
/// (decoded). Use `dict[lenient: "sleep_start"]` to accept both.
enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    static func normalise(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: "").lowercased()
    }

    var doubleValue: Double? { if case .number(let n) = self { return n } else { return nil } }
    var intValue: Int? { doubleValue.map { Int($0.rounded()) } }
    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
}

extension Dictionary where Key == String, Value == JSONValue {
    /// Key lookup tolerant to snake_case / camelCase (see `JSONValue`).
    subscript(lenient key: String) -> JSONValue? {
        if let v = self[key] { return v }
        let n = JSONValue.normalise(key)
        return first { JSONValue.normalise($0.key) == n }?.value
    }
}
