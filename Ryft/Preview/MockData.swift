// Realistic, deterministic history for previews and the simulator demo mode.
// Today matches the brand board: readiness 84, 7h 48m sleep, recovery 82 %,
// strain 12.4, Deep 1h 52m / Light 4h 21m / REM 1h 35m / Awake 10m.
//
// Shapes follow API.md: typed baselines, steps/kcal, DayDetail.strain and a
// hypnogram, so every screen renders without a server.
import Foundation

enum MockData {
    static let historyDays = 90
    static let maxHR = 190
    static let restingHR = 50.0

    static let user = User(id: UUID(uuidString: "6F1C2B8E-1D3A-4E55-9C61-2B0F7E4A9D10") ?? UUID(),
                           name: "Tim", email: "tim@example.com", provider: "email",
                           tz: TimeZone.current.identifier, maxHr: maxHR, sleepBaseMin: 480)

    /// Oldest first; the last element is today.
    static let history: [DailyScore] = nights.map(\.score)

    static var todayScore: DailyScore { history[history.count - 1] }

    static var todayDetail: DayDetail { detail(for: .now) }

    static func detail(for date: Date) -> DayDetail {
        let day = DayFormat.string(from: date)
        guard let night = nights.first(where: { $0.score.day == day }) else {
            return DayDetail(score: .empty(day: day), sleep: nil, workouts: [])
        }
        var strain = night.strain
        let sessions = MockTrain.sessions(on: day)
        strain.sessions = sessions.isEmpty ? nil : sessions
        let workouts = night.workouts.map { w in
            var linked = w
            linked.muscularLoad = sessions.first { $0.id == w.sessionId }?.muscularTrimp
            return linked
        }
        return DayDetail(score: night.score, sleep: night.sleep, strain: strain, workouts: workouts)
    }

    static var allWorkouts: [Workout] { nights.flatMap(\.workouts) }

    static func workoutDetail(id: UUID) -> WorkoutDetail? {
        allWorkouts.first { $0.id == id }.map(workoutDetail)
    }

    static func workoutDetail(_ w: Workout) -> WorkoutDetail {
        // Seed from the UUID text (hashValue is randomised per launch).
        var rng = SeededRandom(seed: UInt64(w.id.uuidString.suffix(8), radix: 16) ?? 7)
        let samples = Int(w.duration / 30)
        let avg = w.avgHr ?? 130
        var hr: [HRPoint] = []
        var zones = [Double](repeating: 0, count: 5)
        for i in 0...max(1, samples) {
            let p = Double(i) / Double(max(1, samples))
            // Warm-up ramp, a working block with gentle intervals, cool-down.
            let shape: Double
            switch p {
            case ..<0.12: shape = 0.72 + 0.28 * (p / 0.12)
            case 0.88...: shape = 1 - 0.25 * ((p - 0.88) / 0.12)
            default: shape = 1 + 0.07 * sin(p * 24)
            }
            let bpm = min(Double(maxHR) - 4, avg * shape + rng.next(in: -3...3))
            hr.append(HRPoint(t: w.start.addingTimeInterval(Double(i) * 30), bpm: bpm.rounded()))
            let hrr = (bpm - restingHR) / (Double(maxHR) - restingHR)
            let zone = Int(((hrr - 0.5) * 10).rounded(.down))
            if hrr >= 0.5 { zones[min(4, max(0, zone))] += 0.5 }
        }
        let trimp = zones.enumerated().reduce(0) { $0 + $1.element * Double($1.offset + 1) }
        return WorkoutDetail(workout: w, hr: hr, zoneMin: zones, trimp: trimp.rounded())
    }

    static func sleepRange(_ kind: SleepRangeKind) -> SleepRange {
        let window = DayFormat.days(endingAt: .now, count: kind.days)
        let days = Set(window)
        let selected = nights.filter { days.contains($0.score.day) }
        let list = selected.map { n in
            SleepNight(day: n.score.day, totalMin: n.sleep.totalMin, stages: n.sleep.stages,
                       quality: n.sleep.quality, start: n.sleep.start, end: n.sleep.end,
                       inBedMin: n.sleep.inBedMin, efficiency: n.sleep.efficiency,
                       qualityLabel: n.sleep.qualityLabel, hasStages: n.sleep.hasStages)
        }
        func mean(_ xs: [Int]) -> Int? { xs.isEmpty ? nil : Int((Double(xs.reduce(0, +)) / Double(xs.count)).rounded()) }
        return SleepRange(range: kind.rawValue, from: window.first, to: window.last, days: list,
                          avgTotalMin: mean(list.compactMap(\.totalMin)), avgQuality: mean(list.compactMap(\.quality)),
                          avgInBedMin: mean(list.compactMap(\.inBedMin)), avgEfficiency: mean(list.compactMap(\.efficiency)))
    }

    /// `GET /v1/trends` from the mock history: one point per scored day with a
    /// value (gaps absent, like the platform); `hrv`/`rhr` carry the latest baseline.
    static func trend(_ metric: TrendMetric, range: TrendRange, today: Date = .now) -> TrendSeries {
        let window = Set(DayFormat.days(endingAt: today, count: range.days))
        let days = history.filter { window.contains($0.day) }
        let points = days.compactMap { d in metric.mockValue(in: d).map { TrendPoint(day: d.day, value: $0) } }
        let values = points.compactMap(\.value)
        let baseline: Double? = switch metric {
        case .hrv: days.last?.hrvBaselineMs
        case .rhr: days.last?.rhrBaseline
        default: nil
        }
        return TrendSeries(metric: metric.rawValue, range: range.rawValue, points: points,
                           avg: values.isEmpty ? nil : (values.reduce(0, +) / Double(values.count)).roundedTo(1),
                           min: values.min(), max: values.max(), baseline: baseline)
    }

    static let insights: [Insight] = [
        Insight(id: "mock-hrv", severity: .info, title: "HRV above your baseline",
                body: "Your HRV is 12% above your 30-day average. Your body is ready for a harder session.",
                metric: "hrv", day: DayFormat.string(from: .now)),
        Insight(id: "mock-bedtime", severity: .notice, title: "Bedtime drifting later",
                body: "You went to bed 40 minutes later than usual three nights this week. A steadier rhythm improves deep sleep.",
                metric: "sleep", day: DayFormat.string(from: .now)),
        Insight(id: "mock-strain", severity: .warn, title: "Strain outpacing recovery",
                body: "Strain has been above 15 on four of the last seven days while recovery stayed under 60%. Plan a lighter day.",
                metric: "strain", day: DayFormat.string(from: .now)),
    ]

    /// A day in the middle of calibration (all scores null) for previews.
    static let calibratingScore = DailyScore(day: DayFormat.string(from: .now), state: .calibrating,
                                             sleepNeedMin: 480, sleepActualMin: 431, baselineDays: 3,
                                             calibrating: true, computedAt: .now)

    // MARK: generation

    private struct Night {
        let score: DailyScore
        let sleep: SleepDetail
        let strain: DayStrain
        let workouts: [Workout]
    }

    private static let nights: [Night] = {
        var rng = SeededRandom(seed: 42)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // Last 7 days of readiness, shaped like the board's trend line.
        let lastWeek = [72, 66, 75, 70, 79, 76, 84]
        var debt = 0.0
        var out: [Night] = []
        var hrvs: [Double] = [], rhrs: [Double] = []

        for i in 0..<historyDays {
            let offset = historyDays - 1 - i
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let day = DayFormat.string(from: date)
            let t = Double(i)
            let isToday = offset == 0

            var readiness = Int((68 + 10 * sin(t / 4.3) + rng.next(in: -8...8)).rounded())
            if offset < 7 { readiness = lastWeek[6 - offset] }
            readiness = min(97, max(24, readiness))
            let recovery = isToday ? 82 : min(99, max(20, readiness + Int(rng.next(in: -6...4))))
            let strain = isToday ? 12.4 : (4 + rng.next(in: 0...13)).roundedTo(1)

            // Sleep
            let need = 480 + Int((strain - 10) * 3)
            let asleep = isToday ? 468 : Int(410 + rng.next(in: -45...70))
            let awake = isToday ? 10 : Int(rng.next(in: 8...28))
            let deep = isToday ? 112 : Int(Double(asleep) * rng.next(in: 0.19...0.26))
            let rem = isToday ? 95 : Int(Double(asleep) * rng.next(in: 0.17...0.23))
            let light = asleep - deep - rem
            let latency = isToday ? 12 : Int(rng.next(in: 6...22))
            let bedtimeOffset = isToday ? 5.0 : rng.next(in: -45...55) + (offset < 7 && offset % 2 == 0 ? 35 : 0)
            let start = cal.date(byAdding: .minute, value: -(75 - Int(bedtimeOffset)), to: date) ?? date // ~22:45 previous evening
            let inBed = asleep + awake + latency
            let end = start.addingTimeInterval(Double(inBed) * 60)
            debt = max(0, debt * 0.7 + Double(need - asleep))
            let performance = min(100, Int((Double(asleep) / Double(need) * 100).rounded()))
            let quality = isToday ? 82 : min(98, max(40, performance + Int(rng.next(in: -6...4))))

            let hrv = isToday ? 66 : (58 + 7 * sin(t / 6) + rng.next(in: -6...6)).roundedTo(1)
            let rhr = isToday ? 50 : (52 - 2 * sin(t / 6) + rng.next(in: -2...2)).roundedTo(1)
            let zoneScale = strain / 12
            let zones = [30, 24, 15, 6, 2].map { Int((Double($0) * zoneScale).rounded()) }
            let steps = isToday ? 9412 : Int(6000 + strain * 380 + rng.next(in: -1500...1500))
            let kcal = isToday ? 612 : Int(250 + strain * 30 + rng.next(in: -80...80))

            // 30-day baselines of the days before this one, like the platform.
            let hrvBase = hrvs.isEmpty ? nil : (hrvs.suffix(30).reduce(0, +) / Double(hrvs.suffix(30).count)).roundedTo(1)
            let rhrBase = rhrs.isEmpty ? nil : (rhrs.suffix(30).reduce(0, +) / Double(rhrs.suffix(30).count)).roundedTo(1)
            let baselineDays = min(30, i)
            hrvs.append(hrv)
            rhrs.append(rhr)

            // Staged shares of sleep (sum 100); awake as a share of time in bed.
            var stages = SleepMath.shares([.deep: deep, .light: light, .rem: rem]).filter { $0.stage != .awake }
            stages.append(StageShare(stage: .awake, min: awake, pct: (Double(awake) / Double(inBed) * 100).rounded()))
            let state: ReadinessState = readiness >= 67 ? .balanced : readiness >= 34 ? .strained : .depleted
            let score = DailyScore(
                day: day, readiness: readiness, state: state, recovery: recovery, strain: strain,
                steps: steps, activeKcal: kcal,
                sleepPerformance: quality, sleepNeedMin: need, sleepActualMin: asleep,
                sleepDebtMin: isToday ? 25 : Int(debt.rounded()), hrvMs: hrv, rhr: rhr,
                respRate: (14.2 + rng.next(in: -0.6...0.6)).roundedTo(1),
                spo2: (96 + rng.next(in: -1.5...1.5)).roundedTo(0),
                hrvBaselineMs: hrvBase, rhrBaseline: rhrBase, baselineDays: baselineDays,
                calibrating: baselineDays < DailyScore.baselineNightsRequired, computedAt: end.addingTimeInterval(600))
            let sleep = SleepDetail(start: start, end: end, totalMin: asleep, inBedMin: inBed,
                                    efficiency: Int((Double(asleep) / Double(inBed) * 100).rounded()),
                                    stages: stages, quality: quality,
                                    qualityLabel: SleepQualityLabel(quality: quality), hasStages: true,
                                    segments: hypnogram(start: start, latency: latency, deep: deep, light: light,
                                                        rem: rem, awake: awake))
            let dayStrain = DayStrain(trimp: Int((strain * 9).rounded()), hrMin: 900 + Int(rng.next(in: 0...200)),
                                      zoneMin: zones, steps: steps, activeKcal: kcal)
            out.append(Night(score: score, sleep: sleep, strain: dayStrain,
                             workouts: workouts(on: date, index: i, isToday: isToday, strain: strain, rng: &rng)))
        }
        return out
    }()

    /// Five ~90-minute cycles: deep front-loaded, REM growing towards morning,
    /// two short wake-ups. Minutes add up to the night's stage totals.
    private static func hypnogram(start: Date, latency: Int, deep: Int, light: Int, rem: Int, awake: Int) -> [SleepInterval] {
        let deepShare = [0.32, 0.26, 0.2, 0.14, 0.08], remShare = [0.1, 0.16, 0.2, 0.24, 0.3]
        var t = start.addingTimeInterval(Double(latency) * 60)
        var out: [SleepInterval] = []
        func add(_ stage: SleepIntervalStage, _ minutes: Int) {
            guard minutes > 0 else { return }
            let end = t.addingTimeInterval(Double(minutes) * 60)
            out.append(SleepInterval(stage: stage, start: t, end: end))
            t = end
        }
        for c in 0..<5 {
            add(.light, light / 10)
            add(.deep, Int(Double(deep) * deepShare[c]))
            add(.light, light / 10)
            add(.rem, Int(Double(rem) * remShare[c]))
            if c == 1 || c == 3 { add(.awake, awake / 2) }
        }
        return out
    }

    private static func workouts(on date: Date, index: Int, isToday: Bool, strain: Double,
                                 rng: inout SeededRandom) -> [Workout] {
        func at(_ h: Int, _ m: Int) -> Date {
            Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
        }
        func make(_ n: Int, _ activity: String, _ start: Date, minutes: Int, avg: Double, max: Double,
                  kcal: Double, km: Double?, strain: Double) -> Workout {
            // Strength workouts belong to the Train session logged at the same time.
            let session = activity == "strength" && MockTrain.hasHistorySession(dayIndex: index)
                ? MockTrain.historySessionID(dayIndex: index) : nil
            return Workout(id: mockUUID(index * 10 + n), activity: activity, start: start,
                           end: start.addingTimeInterval(Double(minutes) * 60), avgHr: avg, maxHr: max,
                           energyKcal: kcal, distanceM: km.map { $0 * 1000 }, source: "Garmin Connect", strain: strain,
                           sessionId: session)
        }
        if isToday {
            return [
                make(1, "running", at(6, 40), minutes: 52, avg: 148, max: 176, kcal: 540, km: 8.4, strain: 10.6),
                make(2, "walking", at(12, 15), minutes: 35, avg: 102, max: 118, kcal: 140, km: 2.6, strain: 3.1),
            ]
        }
        switch index % 7 {
        case 0, 2, 4:
            let minutes = Int(rng.next(in: 35...70))
            return [make(1, "running", at(7, 0), minutes: minutes, avg: rng.next(in: 138...156).rounded(),
                         max: rng.next(in: 168...182).rounded(), kcal: Double(minutes) * 10.5,
                         km: (Double(minutes) / 5.8).roundedTo(1), strain: (strain * 0.8).roundedTo(1))]
        case 1, 5:
            return [make(1, "strength", at(18, 10), minutes: 50, avg: 118, max: 152, kcal: 320, km: nil,
                         strain: (strain * 0.6).roundedTo(1))]
        case 3:
            let minutes = Int(rng.next(in: 60...110))
            return [make(1, "cycling", at(17, 30), minutes: minutes, avg: 135, max: 168, kcal: Double(minutes) * 9,
                         km: (Double(minutes) / 2.4).roundedTo(1), strain: (strain * 0.85).roundedTo(1))]
        default:
            return []
        }
    }

    private static func mockUUID(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n)) ?? UUID()
    }
}

/// SplitMix64 — tiny deterministic PRNG so mock data is stable across launches.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(nextUInt64() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

extension TrendMetric {
    /// The value a mock day contributes to this metric's series.
    func mockValue(in s: DailyScore) -> Double? {
        switch self {
        case .readiness: return s.readiness.map(Double.init)
        case .recovery: return s.recovery.map(Double.init)
        case .strain: return s.strain
        case .sleep: return s.sleepPerformance.map(Double.init)
        case .sleepMin: return s.sleepActualMin.map(Double.init)
        case .hrv: return s.hrvMs
        case .rhr: return s.rhr
        case .steps: return s.steps.map(Double.init)
        case .activeKcal: return s.activeKcal.map(Double.init)
        }
    }
}

private extension Double {
    func roundedTo(_ digits: Int) -> Double {
        let p = pow(10, Double(digits))
        return (self * p).rounded() / p
    }
}

/// `RyftDataSource` backed by `MockData`.
struct MockDataSource: RyftDataSource {
    static let shared = MockDataSource()

    func me() async throws -> User { MockData.user }

    func patchMe(_ p: UserPatch) async throws -> User {
        User(id: MockData.user.id, name: MockData.user.name, email: MockData.user.email,
             provider: MockData.user.provider, tz: p.tz ?? MockData.user.tz,
             maxHr: p.maxHr ?? MockData.user.maxHr, sleepBaseMin: p.sleepBaseMin ?? MockData.user.sleepBaseMin)
    }

    func days(from: Date, to: Date) async throws -> [DailyScore] {
        let lo = DayFormat.string(from: from), hi = DayFormat.string(from: to)
        return MockData.history.filter { $0.day >= lo && $0.day <= hi }
    }

    func day(_ date: Date) async throws -> DayDetail { MockData.detail(for: date) }

    func sleep(range: SleepRangeKind) async throws -> SleepRange { MockData.sleepRange(range) }

    func workouts(from: Date, to: Date) async throws -> [Workout] {
        MockData.allWorkouts.filter { $0.start >= from && $0.start <= to }
    }

    func workout(id: UUID) async throws -> WorkoutDetail {
        guard let d = MockData.workoutDetail(id: id) else { throw APIError.http(404, "not found") }
        return d
    }

    func trends(metric: TrendMetric, range: TrendRange) async throws -> TrendSeries {
        MockData.trend(metric, range: range)
    }

    func insights() async throws -> [Insight] { MockData.insights }

    func recompute(from: Date, to: Date) async throws {}

    func deleteMe() async throws -> AccountDeleted { AccountDeleted(status: "deleted", authUserDeleted: true) }
}
