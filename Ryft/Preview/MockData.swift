// Realistic, deterministic history for previews and the simulator demo mode.
// Today matches the Nocturne boards (docs/work/2026-11-16-nocturne/design.md §P4-4): readiness 84 (+11 vs 7 d),
// recovery 82 %, strain 12.4; the night 22:50 – 07:00, 7:48 asleep (Deep 1:35, REM 1:45, Light 4:28, Awake 0:22),
// efficiency 95, a need of 8:18 (a 40-minute nap credit) and so 94 % of it, debt 0:30 (1:12 the night before),
// consistency 86. The last seven days carry an HRV week (lowest 51, highest 66 today), nights that met their need
// (≥ 90 % of it, L24), missed it, and one without a need (no data), and a consistency below 60 and one missing.
//
// Shapes follow API.md: typed baselines, steps/kcal, DayDetail.strain and a
// hypnogram, so every screen renders without a server.
import Foundation

enum MockData {
    static let historyDays = 90
    static let maxHR = 190
    static let restingHR = 50.0

    /// The learned baseline in use (API.md → Learned baseline).
    static let sleepBase = 460

    /// The privacy policy in force (`GET /v1/config`) and the demo account's consent to it.
    static let policyVersion = "2026-10-20"
    static let consentedAt = Date(timeIntervalSince1970: 1_792_489_964) // 2026-10-20T09:12:44Z

    static let user = User(id: UUID(uuidString: "6F1C2B8E-1D3A-4E55-9C61-2B0F7E4A9D10") ?? UUID(),
                           name: "Alex Doe", email: "alex@example.com", provider: "email",
                           tz: TimeZone.current.identifier, maxHr: maxHR, sleepBaseMin: sleepBase,
                           sleepBaseSource: .learned, sleepBaseLearnedMin: sleepBase,
                           sleepBaseLearnedAt: Calendar.current.date(byAdding: .day, value: -2, to: .now),
                           consent: Consent(policyVersion: policyVersion, grantedAt: consentedAt),
                           sources: [UserSource(name: "Alex's Apple Watch", bundleId: "com.apple.health.81E2",
                                                kinds: [.energy, .hr, .hrv, .resp, .sleep, .spo2, .workout],
                                                lastSeen: .now.addingTimeInterval(-1_800)),
                                     UserSource(name: "Alex's iPhone", bundleId: "com.apple.health.3F0A",
                                                kinds: [.steps], lastSeen: .now.addingTimeInterval(-600))])

    /// Oldest first; the last element is today: the day the process first read the mock.
    static let history: [DailyScore] = nights.map(\.score)

    static var todayScore: DailyScore { history[history.count - 1] }

    /// The mock's day is the one its nights were built for, for the life of the process (`MockTrain.history` is frozen the
    /// same way, and the workout→session links agree only while both are). Every read below anchors to it, never to
    /// `.now`: past midnight `.now` is a day the table doesn't have, `detail(for: .now)` came back empty and
    /// `todayDetail.workouts[0]` trapped with "Index out of range" (CI, 2026-11-23 00:00:15). A relaunch starts a new day.
    static var todayDetail: DayDetail { Window(nights: nights).today }

    static func detail(for date: Date) -> DayDetail { Window(nights: nights).detail(for: date) }

    /// The nights as a value, so a test can build one at an instant far from the real date and read it.
    struct Window {
        let nights: [Night]

        /// A window of the 90 nights ending on the day of `instant`.
        init(endingOn instant: Date) { nights = MockData.makeNights(today: Calendar.current.startOfDay(for: instant)) }
        init(nights: [Night]) { self.nights = nights }

        /// The last night's day, as a date.
        var lastDay: Date { nights.last.flatMap { DayFormat.date(from: $0.score.day) } ?? .now }

        /// The window's own last day, whatever the wall clock says.
        var today: DayDetail { detail(for: lastDay) }

        func detail(for date: Date) -> DayDetail {
            let day = DayFormat.string(from: date)
            guard let night = nights.first(where: { $0.score.day == day }) else {
                return DayDetail(score: .empty(day: day), sleep: nil, workouts: [])
            }
            var strain = night.strain
            let sessions = MockTrain.sessions(on: day)
            strain.sessions = sessions.isEmpty ? nil : sessions
            let muscular = sessions.compactMap(\.muscularTrimp).reduce(0, +)
            strain.muscularTrimp = muscular > 0 ? Int(muscular.rounded()) : 0
            let workouts = night.workouts.map { w in
                var linked = w
                linked.muscularLoad = sessions.first { $0.id == w.sessionId }?.muscularTrimp
                return linked
            }
            return DayDetail(score: night.score, sleep: night.sleep, strain: strain, workouts: workouts)
        }
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
        var curve: [Double] = (0...max(1, samples)).map { i in
            let p = Double(i) / Double(max(1, samples))
            // Warm-up ramp, a working block with gentle intervals, cool-down.
            let shape: Double
            switch p {
            case ..<0.12: shape = 0.72 + 0.28 * (p / 0.12)
            case 0.88...: shape = 1 - 0.25 * ((p - 0.88) / 0.12)
            default: shape = 1 + 0.07 * sin(p * 24)
            }
            return min(Double(maxHR) - 4, avg * shape + rng.next(in: -3...3))
        }
        // A push around the highest interval, so the curve's peak is the workout's max heart rate (the Max tile and the
        // chart's "peak" agree): a smooth rise over a few minutes, nothing above the max.
        if let top = w.maxHr, let peak = curve.indices.max(by: { curve[$0] < curve[$1] }) {
            let lift = top - curve[peak]
            curve = curve.enumerated().map { i, bpm in
                let d = Double(i - peak) / 6
                return min(top, bpm + lift * exp(-d * d))
            }
        }
        var hr: [HRPoint] = []
        var zones = [Double](repeating: 0, count: 5)
        for (i, bpm) in curve.enumerated() {
            hr.append(HRPoint(t: w.start.addingTimeInterval(Double(i) * 30), bpm: bpm.rounded()))
            let hrr = (bpm - restingHR) / (Double(maxHR) - restingHR)
            let zone = Int(((hrr - 0.5) * 10).rounded(.down))
            if hrr >= 0.5 { zones[min(4, max(0, zone))] += 0.5 }
        }
        let trimp = zones.enumerated().reduce(0) { $0 + $1.element * Double($1.offset + 1) }
        return WorkoutDetail(workout: w, hr: hr, zoneMin: zones, trimp: trimp.rounded())
    }

    static func sleepRange(_ kind: SleepRangeKind) -> SleepRange {
        let window = DayFormat.days(endingAt: Window(nights: nights).lastDay, count: kind.days)
        let days = Set(window)
        let selected = nights.filter { days.contains($0.score.day) }
        let list = selected.map { n in
            SleepNight(day: n.score.day, totalMin: n.sleep.totalMin, stages: n.sleep.stages,
                       quality: n.sleep.quality, start: n.sleep.start, end: n.sleep.end,
                       inBedMin: n.sleep.inBedMin, efficiency: n.sleep.efficiency,
                       qualityLabel: n.sleep.qualityLabel, hasStages: n.sleep.hasStages,
                       restorative: n.sleep.restorative, consistency: n.score.sleepConsistency, napMin: n.score.napMin)
        }
        func mean(_ xs: [Int]) -> Int? { xs.isEmpty ? nil : Int((Double(xs.reduce(0, +)) / Double(xs.count)).rounded()) }
        let bedtimes = selected.compactMap { n in
            n.sleep.start.flatMap { bed in n.sleep.end.map { SleepBedtime(day: n.score.day, bed: bed, wake: $0) } }
        }
        return SleepRange(range: kind.rawValue, from: window.first, to: window.last, days: list,
                          avgTotalMin: mean(list.compactMap(\.totalMin)), avgQuality: mean(list.compactMap(\.quality)),
                          avgInBedMin: mean(list.compactMap(\.inBedMin)), avgEfficiency: mean(list.compactMap(\.efficiency)),
                          avgConsistency: mean(list.compactMap(\.consistency)), bedtimes: bedtimes)
    }

    /// `GET /v1/trends` from the mock history: one point per scored day with a
    /// value (gaps absent, like the platform); `hrv`/`rhr` carry the latest baseline.
    static func trend(_ metric: TrendMetric, range: TrendRange, today: Date? = nil) -> TrendSeries {
        let window = Set(DayFormat.days(endingAt: today ?? Window(nights: nights).lastDay, count: range.days))
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
        Insight(id: "strain-no-recovery", severity: .warn, title: "Strain outpacing recovery",
                body: "Strain has been above 15 on four of the last seven days while recovery stayed under 60%. Plan a lighter day.",
                metric: "strain", day: DayFormat.string(from: .now)),
        Insight(id: "behavior-impact", severity: .notice, title: "Alcohol yesterday",
                body: "Your recovery is typically 14 points lower the morning after.",
                metric: "recovery", day: DayFormat.string(from: .now)),
        Insight(id: "sleep-consistency-low", severity: .notice, title: "Irregular sleep times",
                body: "Your sleep consistency is 54 over the last 7 nights. Going to bed within the same half hour helps recovery.",
                metric: "sleep_consistency", day: DayFormat.string(from: .now)),
        Insight(id: "hrv-best-30d", severity: .info, title: "Best HRV in 30 days",
                body: "Last night's HRV of 66 ms is your highest in a month.",
                metric: "hrv", day: DayFormat.string(from: .now)),
    ]

    /// A day in the middle of calibration (all scores null) for previews.
    static let calibratingScore = DailyScore(day: DayFormat.string(from: .now), state: .calibrating,
                                             sleepNeedMin: 480, sleepActualMin: 431, baselineDays: 3,
                                             calibrating: true, computedAt: .now)

    // MARK: generation

    /// The last seven days, oldest first (offset 6 … 0; today is the board's own night). What the Nocturne previews
    /// show as the HRV sparkline, the 7-night dots of Today's sleep tile and Sleep's consistency tile (§P4-4, T10, T12,
    /// S10). `asleepShare`: the night's sleep as a share of its need (≥ 0.90 met, below missed; today's is the board's
    /// 468 of 498, not applied); `nil` is a night scored without a need, so neither "met" nor "missed" can be told.
    enum BoardWeek {
        static let hrv: [Double] = [58, 51, 60, 55, 62, 57, 66]
        static let asleepShare: [Double?] = [0.95, 0.82, nil, 0.96, 0.84, 0.93, 0.94]
        static let consistency: [Int?] = [78, 64, nil, 52, 71, 80, 86]
        /// Debt the night before today and today (the ▼ 0:42).
        static let debtYesterday = 72, debtToday = 30
        /// Yesterday's nap: today's need takes it off (the 40-minute credit).
        static let napYesterday = 40
    }

    struct Night {
        let score: DailyScore
        let sleep: SleepDetail
        let strain: DayStrain
        let workouts: [Workout]
    }

    private static let nights: [Night] = makeNights(today: Calendar.current.startOfDay(for: .now))

    private static func makeNights(today: Date) -> [Night] {
        var rng = SeededRandom(seed: 42)
        let cal = Calendar.current
        // Last 7 days of readiness, shaped like the board's trend line.
        let lastWeek = [72, 66, 75, 70, 79, 76, 84]
        var debt = 0.0
        var out: [Night] = []
        var hrvs: [Double] = [], rhrs: [Double] = []
        var beds: [Double] = [], wakes: [Double] = []
        var lastStrain = 10.0, lastNap = 0

        for i in 0..<historyDays {
            let offset = historyDays - 1 - i
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let day = DayFormat.string(from: date)
            let t = Double(i)
            let isToday = offset == 0

            var readiness = Int((68 + 10 * sin(t / 4.3) + rng.next(in: -8...8)).rounded())
            // The board's week: index 0 is six days back, 6 today.
            let week = offset < 7 ? 6 - offset : nil
            if let week { readiness = lastWeek[week] }
            readiness = min(97, max(24, readiness))
            let recovery = isToday ? 82 : min(99, max(20, readiness + Int(rng.next(in: -6...4))))
            let strain = isToday ? 12.4 : (4 + rng.next(in: 0...13)).roundedTo(1)

            // Sleep: the need by term, as the platform scores it (API.md → DailyScore).
            let needStrain = isToday ? 37 : min(60, Int((lastStrain * 3).rounded()))
            let needDebt = isToday ? 41 : min(60, Int((debt * 0.3).rounded()))
            let needNap = lastNap
            let need = sleepBase + needStrain + needDebt - needNap
            let nap = isToday ? 25 : offset == 1 ? BoardWeek.napYesterday : (i % 9 == 4 ? Int(rng.next(in: 25...50)) : 0)
            lastStrain = strain
            lastNap = nap
            var asleep = isToday ? 468 : Int(410 + rng.next(in: -45...70))
            if let week, !isToday, let share = BoardWeek.asleepShare[week] { asleep = Int((Double(need) * share).rounded()) }
            let awake = isToday ? 22 : Int(rng.next(in: 8...28))
            let deep = isToday ? 95 : Int(Double(asleep) * rng.next(in: 0.19...0.26))
            let rem = isToday ? 105 : Int(Double(asleep) * rng.next(in: 0.17...0.23))
            let light = asleep - deep - rem
            let latency = isToday ? 0 : Int(rng.next(in: 6...22))
            let bedtimeOffset = isToday ? 5.0 : rng.next(in: -45...55) + (offset < 7 && offset % 2 == 0 ? 35 : 0)
            let start = cal.date(byAdding: .minute, value: -(75 - Int(bedtimeOffset)), to: date) ?? date // ~22:45 previous evening
            let inBed = asleep + awake + latency
            let end = start.addingTimeInterval(Double(inBed) * 60)
            debt = max(0, debt * 0.7 + Double(need - asleep))
            let performance = min(100, Int((Double(asleep) / Double(need) * 100).rounded()))
            // Today: the board's 95 (468 of 490 minutes is 95.5; the platform's own rounding is not the mock's).
            let efficiency = isToday ? 95 : Int((Double(asleep) / Double(inBed) * 100).rounded())
            let restorative = min(100, Int((Double(deep + rem) / Double(asleep) / 0.40 * 100).rounded()))
            let quality = isToday ? 91 : Int((0.6 * Double(performance) + 0.2 * Double(efficiency)
                                              + 0.2 * Double(restorative)).rounded())
            // Consistency over the last 7 nights: 100 − 0.5·(σ bed + σ wake) in minutes, 5 nights needed.
            beds.append(start.timeIntervalSince(date) / 60)
            wakes.append(end.timeIntervalSince(date) / 60)
            func sd(_ xs: ArraySlice<Double>) -> Double {
                let m = xs.reduce(0, +) / Double(xs.count)
                return (xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)).squareRoot()
            }
            let measured: Int? = beds.count < 5 ? nil
                : max(0, min(100, Int((100 - 0.5 * (sd(beds.suffix(7)) + sd(wakes.suffix(7)))).rounded())))
            let consistency = week.map { BoardWeek.consistency[$0] } ?? measured

            // Today draws no random value here (nor below), so the rest of today's values keep their sequence.
            var hrv = isToday ? 66 : (58 + 7 * sin(t / 6) + rng.next(in: -6...6)).roundedTo(1)
            if let week { hrv = BoardWeek.hrv[week] }
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
            // A night of the board's week scored without a need: no performance either.
            let hasNeed = week.map { BoardWeek.asleepShare[$0] != nil } ?? true
            let debtShown = isToday ? BoardWeek.debtToday : offset == 1 ? BoardWeek.debtYesterday : Int(debt.rounded())
            let score = DailyScore(
                day: day, readiness: readiness, state: state, recovery: recovery, strain: strain,
                steps: steps, activeKcal: kcal,
                sleepPerformance: hasNeed ? performance : nil, sleepNeedMin: hasNeed ? need : nil, sleepActualMin: asleep,
                sleepDebtMin: debtShown, hrvMs: hrv, rhr: rhr,
                respRate: (14.2 + rng.next(in: -0.6...0.6)).roundedTo(1),
                spo2: (96 + rng.next(in: -1.5...1.5)).roundedTo(0),
                hrvBaselineMs: hrvBase, rhrBaseline: rhrBase, baselineDays: baselineDays,
                calibrating: baselineDays < DailyScore.baselineNightsRequired, computedAt: end.addingTimeInterval(600),
                sleepNeedBaseMin: hasNeed ? sleepBase : nil, sleepNeedStrainMin: hasNeed ? needStrain : nil,
                sleepNeedDebtMin: hasNeed ? needDebt : nil, sleepNeedNapMin: hasNeed ? needNap : nil, napMin: nap,
                sleepQuality: quality, sleepConsistency: consistency)
            let sleep = SleepDetail(start: start, end: end, totalMin: asleep, inBedMin: inBed,
                                    efficiency: efficiency,
                                    stages: stages, quality: quality,
                                    qualityLabel: SleepQualityLabel(quality: quality), hasStages: true,
                                    segments: hypnogram(start: start, latency: latency, deep: deep, light: light,
                                                        rem: rem, awake: awake),
                                    restorative: restorative,
                                    need: hasNeed ? SleepNeed(base: sleepBase, strain: needStrain, debt: needDebt,
                                                              napCredit: needNap, total: need) : nil)
            let dayStrain = DayStrain(trimp: Int((strain * 9).rounded()), hrMin: 900 + Int(rng.next(in: 0...200)),
                                      zoneMin: zones, steps: steps, activeKcal: kcal)
            out.append(Night(score: score, sleep: sleep, strain: dayStrain,
                             workouts: workouts(on: date, index: i, isToday: isToday, strain: strain, rng: &rng)))
        }
        return out
    }

    /// Five ~90-minute cycles: deep front-loaded, REM growing towards morning,
    /// two short wake-ups. Minutes add up to the night's stage totals exactly (the last cycle takes what the shares
    /// leave), so the timeline runs from sleep onset to the night's end.
    private static func hypnogram(start: Date, latency: Int, deep: Int, light: Int, rem: Int, awake: Int) -> [SleepInterval] {
        let deepShare = [0.32, 0.26, 0.2, 0.14, 0.08], remShare = [0.1, 0.16, 0.2, 0.24, 0.3]
        var t = start.addingTimeInterval(Double(latency) * 60)
        var out: [SleepInterval] = []
        var left: [SleepIntervalStage: Int] = [.light: light, .deep: deep, .rem: rem, .awake: awake]
        func add(_ stage: SleepIntervalStage, _ minutes: Int, last: Bool = false) {
            let minutes = last ? left[stage] ?? 0 : min(minutes, left[stage] ?? 0)
            guard minutes > 0 else { return }
            left[stage, default: 0] -= minutes
            let end = t.addingTimeInterval(Double(minutes) * 60)
            out.append(SleepInterval(stage: stage, start: t, end: end))
            t = end
        }
        for c in 0..<5 {
            let last = c == 4
            add(.light, light / 10)
            add(.deep, Int(Double(deep) * deepShare[c]), last: last)
            add(.light, light / 10)
            add(.rem, Int(Double(rem) * remShare[c]), last: last)
            if c == 1 || c == 3 { add(.awake, awake / 2, last: c == 3) }
            if last { add(.light, 0, last: true) }
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

    /// One of the bundled catalog's trackers; `checked` replaces its date (the stale-guide preview).
    static func tracker(_ id: String, checked: String? = nil) -> Tracker {
        guard let t = TrackerCatalog.bundled.tracker(id) ?? TrackerCatalog.bundled.trackers.first else {
            preconditionFailure("the bundled catalog has trackers")
        }
        guard let checked else { return t }
        return Tracker(id: t.id, name: t.name, form: t.form, appName: t.appName, integration: t.integration,
                       identity: t.identity, appStoreID: t.appStoreID, appScheme: t.appScheme, capabilities: t.capabilities, notes: t.notes,
                       setup: t.setup, habits: t.habits, sync: t.sync, limits: t.limits, help: t.help, checked: checked)
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
        case .strengthMin: return s.strengthMin.map(Double.init)
        case .volumeKg: return s.volumeKg
        case .sleepQuality: return s.sleepQuality.map(Double.init)
        case .sleepConsistency: return s.sleepConsistency.map(Double.init)
        case .napMin: return s.napMin.map(Double.init)
        }
    }
}

private extension Double {
    func roundedTo(_ digits: Int) -> Double {
        let p = pow(10, Double(digits))
        return (self * p).rounded() / p
    }
}

#if DEBUG
/// Demo data's own scenarios, from the same `-RyftScenario` argument as Today's (`TodayScenario`, which ignores
/// these): what the demo platform serves differently, for UI tests and screenshots. Demo mode only; without the
/// argument demo data is unchanged.
enum DemoDataScenario: String {
    /// No night three days back (the day is scored, its sleep missing): My Day says "No sleep recorded" there and
    /// Add sleep can be reached. Today's and yesterday's nights stay.
    case missingNight = "missing-night"

    static var requested: DemoDataScenario? {
        UserDefaults.standard.string(forKey: "RyftScenario").flatMap(DemoDataScenario.init(rawValue:))
    }

    /// The day without its night (`missingNight`).
    static var missingNightDay: String { DayFormat.string(from: DayFormat.shift(.now, days: -3)) }

    func apply(to detail: DayDetail) -> DayDetail {
        switch self {
        case .missingNight:
            guard detail.score.day == Self.missingNightDay else { return detail }
            var d = detail
            d.sleep = nil
            return d
        }
    }
}
#endif

/// `RyftDataSource` backed by `MockData`.
struct MockDataSource: RyftDataSource {
    static let shared = MockDataSource()

    func me() async throws -> User { MockData.user }

    /// The platform's rules: a baseline sent by hand becomes `manual`;
    /// `sleep_base_manual: false` goes back to the learned value (or 460). A birth year
    /// sets the Tanaka estimate unless max HR is manual; `max_hr_manual: false` returns to it.
    /// A birth year outside 1920 … this year − 16 (the minimum age) is a `422`.
    func patchMe(_ p: UserPatch) async throws -> User {
        try await patchMe(p, on: MockData.user)
    }

    /// `p` applied on top of `u` (the mock platform keeps the user between patches).
    func patchMe(_ p: UserPatch, on u: User) async throws -> User {
        if p.sleepBaseMin != nil, p.sleepBaseManual == false { throw APIError.http(422, "conflicting baseline") }
        if p.maxHr != nil, p.maxHrManual == false { throw APIError.http(422, "conflicting max HR") }
        if let y = p.birthYear, !OnboardingCoordinator.birthYears(now: .now).contains(y) {
            throw APIError.http(422, "birth_year out of range")
        }
        var base = u.sleepBaseMin, source = u.sleepBaseSource
        if let m = p.sleepBaseMin {
            base = m
            source = .manual
        } else if p.sleepBaseManual == false {
            base = u.sleepBaseLearnedMin ?? 460
            source = u.sleepBaseLearnedMin == nil ? .default : .learned
        }
        let birthYear = p.birthYear ?? u.birthYear
        var maxHr = u.maxHr, hrSource = u.maxHrSource
        if let m = p.maxHr {
            maxHr = m
            hrSource = .manual
        } else if let year = birthYear, hrSource != .manual || p.maxHrManual == false {
            // The platform's Tanaka estimate, 208 − 0.7 · age.
            let age = Calendar.current.component(.year, from: .now) - year
            maxHr = Int((208 - 0.7 * Double(age)).rounded())
            hrSource = .estimated
        } else if p.maxHrManual == false {
            maxHr = 190
            hrSource = .default
        }
        return User(id: u.id, name: u.name, email: u.email, provider: u.provider, tz: p.tz ?? u.tz,
                    maxHr: maxHr, sleepBaseMin: base, sleepBaseSource: source,
                    sleepBaseLearnedMin: u.sleepBaseLearnedMin, sleepBaseLearnedAt: u.sleepBaseLearnedAt,
                    notifications: u.notifications, consent: u.consent, birthYear: birthYear,
                    maxHrSource: hrSource, sources: u.sources)
    }

    func days(from: Date, to: Date) async throws -> [DailyScore] {
        let lo = DayFormat.string(from: from), hi = DayFormat.string(from: to)
        return MockData.history.filter { $0.day >= lo && $0.day <= hi }
    }

    func day(_ date: Date) async throws -> DayDetail {
        #if DEBUG
        return DemoDataScenario.requested?.apply(to: MockData.detail(for: date)) ?? MockData.detail(for: date)
        #else
        return MockData.detail(for: date)
        #endif
    }

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

// MARK: - check sync (design.md §4.6)

extension SourceRef {
    /// Garmin Connect as HealthKit names it.
    static let mockGarmin = SourceRef(name: "Connect", bundleID: "com.garmin.connect.mobile", deviceModel: nil)
    static let mockOura = SourceRef(name: "Oura", bundleID: "com.ouraring.oura", deviceModel: nil)
    static let mockPhone = SourceRef(name: "Alex's iPhone", bundleID: "com.apple.health.3F0A8C2E-5B1D-4E7A-9C6F-2D8B1A4E7F30",
                                     deviceModel: "iPhone")
    static let mockWatch = SourceRef(name: "Alex's Apple Watch", bundleID: "com.apple.health.81E4B0C2-7D3A-4F19-B6E5-0C9A2F7D41B8",
                                     deviceModel: "Watch")
}

extension MockHealthStore {
    /// Garmin Connect ("Connect", `com.garmin.connect.mobile`) as a device check saw it (2026-10-22, catalog
    /// 2026-10-22.3): heart rate (20 min ago), resting heart rate (one sample a day, stamped 00:00), sleep with stages
    /// (ending 06:48), steps (1 h ago) and a workout (yesterday, ending 19:02); no HRV, breathing rate or SpO₂. The
    /// iPhone writes steps (10 min ago) and an in-bed night: the iPhone isn't the night. `visible` is what those
    /// sources wrote.
    ///
    /// `nightSynced: false`: Connect wasn't opened this morning, Garmin's newest is yesterday 23:24 (and yesterday's
    /// resting heart rate). `silent`: nothing from Garmin in 48 h. `sleepOff`: no sleep from Garmin, though the
    /// iPhone's makes sleep visible (an unexpected gap RYFT can read). `restingHR: false`: none at all, as from a
    /// tracker that writes none.
    static func garminLike(now: Date = .now, nightSynced: Bool = true, silent: Bool = false, sleepOff: Bool = false,
                           restingHR: Bool = true, calendar: Calendar = .current) -> MockHealthStore {
        let at = MockTimes(now: now, calendar: calendar)
        var samples = [SourceSample(stream: .quantity(.steps), source: .mockPhone, newest: now.addingTimeInterval(-600)),
                       SourceSample(stream: .sleep, source: .mockPhone, newest: at.morning(6, 30), hasStages: false)]
        if !silent {
            let evening = at.yesterday(23, 24)
            samples += [
                SourceSample(stream: .quantity(.heartRate), source: .mockGarmin,
                             newest: nightSynced ? now.addingTimeInterval(-1_200) : evening),
                SourceSample(stream: .quantity(.steps), source: .mockGarmin,
                             newest: nightSynced ? now.addingTimeInterval(-3_600) : evening.addingTimeInterval(-840)),
                SourceSample(stream: .workouts, source: .mockGarmin, newest: at.yesterday(19, 2)),
            ]
            if restingHR {
                samples.append(SourceSample(stream: .quantity(.restingHR), source: .mockGarmin,
                                            newest: at.midnight(daysAgo: nightSynced ? 0 : 1)))
            }
            if !sleepOff {
                let wake = at.morning(6, 48)
                samples.append(SourceSample(stream: .sleep, source: .mockGarmin,
                                            newest: nightSynced ? wake : wake.addingTimeInterval(-86_400), hasStages: true))
            }
        }
        let store = MockHealthStore()
        store.samples = samples
        var visible: Set<HealthStream> = [.quantity(.heartRate), .sleep, .quantity(.steps), .workouts]
        if restingHR { visible.insert(.quantity(.restingHR)) }
        store.visible = visible
        return store
    }

    /// Oura as its docs say: heart rate, sleep with stages, breathing rate, steps and a workout; no HRV, resting heart
    /// rate or SpO₂ (the expected gaps a ring has).
    static func ouraLike(now: Date = .now, calendar: Calendar = .current) -> MockHealthStore {
        let at = MockTimes(now: now, calendar: calendar)
        let store = MockHealthStore()
        store.samples = [
            SourceSample(stream: .quantity(.heartRate), source: .mockOura, newest: now.addingTimeInterval(-1_800)),
            SourceSample(stream: .sleep, source: .mockOura, newest: at.morning(6, 40), hasStages: true),
            SourceSample(stream: .quantity(.respiratoryRate), source: .mockOura, newest: at.morning(6, 40)),
            SourceSample(stream: .quantity(.steps), source: .mockOura, newest: now.addingTimeInterval(-2_400)),
            SourceSample(stream: .workouts, source: .mockOura, newest: at.yesterday(19, 2)),
        ]
        store.visible = [.quantity(.heartRate), .sleep, .quantity(.respiratoryRate), .quantity(.steps), .workouts]
        return store
    }

    /// An Apple Watch that sends everything (sleep with stages), and the iPhone's steps.
    static func appleWatchLike(now: Date = .now, calendar: Calendar = .current) -> MockHealthStore {
        let at = MockTimes(now: now, calendar: calendar)
        let watch: [(HealthStream, Date)] = [
            (.quantity(.heartRate), now.addingTimeInterval(-300)), (.quantity(.hrvSDNN), at.morning(3, 12)),
            (.quantity(.restingHR), at.morning(7, 5)), (.quantity(.respiratoryRate), at.morning(6, 40)),
            (.quantity(.spo2), at.morning(4, 10)), (.workouts, at.yesterday(19, 2)),
            (.quantity(.steps), now.addingTimeInterval(-900)),
        ]
        let store = MockHealthStore()
        store.samples = watch.map { SourceSample(stream: $0.0, source: .mockWatch, newest: $0.1) }
            + [SourceSample(stream: .sleep, source: .mockWatch, newest: at.morning(6, 52), hasStages: true),
               SourceSample(stream: .quantity(.steps), source: .mockPhone, newest: now.addingTimeInterval(-600))]
        store.visible = Set(TrackerCheckRules.streams)
        return store
    }
}

/// Times of day for the mocks, never in the future: this morning's once it's past, else five minutes ago (a check
/// at 02:00 sees a night still being written, not yesterday's).
private struct MockTimes {
    let now: Date
    let calendar: Calendar

    func morning(_ hour: Int, _ minute: Int) -> Date {
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        return min(today, now.addingTimeInterval(-300))
    }

    /// Midnight that began today, or `daysAgo` days before.
    func midnight(daysAgo: Int) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
    }

    func yesterday(_ hour: Int, _ minute: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

/// Check sync on mock data: `-RyftSyncCheck <name>` in Debug builds and demo mode (with `-RyftScreen syncCheck`, or
/// wherever Check sync opens), so the screen can be opened and UI-tested without a tracker. It sets the trackers
/// checked and the store `TrackerCheckModel.make` reads instead of `env.health`.
enum SyncCheckScenario: String, CaseIterable {
    case garmin, garminNightMissing, garminSilent, garminSleepOff, appleWatch
    /// Nothing visible at all, not even the iPhone's steps: the strong hint.
    case nothingReadable

    var trackers: [String] { self == .appleWatch ? ["apple_watch"] : ["garmin"] }

    func store(now: Date) -> MockHealthStore {
        switch self {
        case .garmin: return .garminLike(now: now)
        case .garminNightMissing: return .garminLike(now: now, nightSynced: false)
        case .garminSilent: return .garminLike(now: now, silent: true)
        case .garminSleepOff: return .garminLike(now: now, sleepOff: true)
        case .appleWatch: return .appleWatchLike(now: now)
        case .nothingReadable: return MockHealthStore()
        }
    }

    static var requested: SyncCheckScenario? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "RyftSyncCheck").flatMap(SyncCheckScenario.init(rawValue:))
        #else
        nil
        #endif
    }
}
