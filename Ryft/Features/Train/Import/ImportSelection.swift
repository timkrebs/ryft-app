import Foundation

/// Step 3's choices (ui.md §6): which plans, whether history and over what range, and which plan becomes active. Pure:
/// every count and every reason Continue is off comes from here.
struct ImportSelection: Equatable, Sendable {
    struct PlanChoice: Equatable, Sendable {
        var isOn: Bool
        var state: PlanState
    }

    enum PlanState: Equatable, Sendable {
        case importable
        /// A plan with the derived id exists; RYFT's copy is kept unless the user asks for the file's version.
        case alreadyInRYFT(replace: Bool)
        /// More days than a RYFT plan has (7): history can still be imported.
        case tooManyDays(Int)

        var canImport: Bool {
            switch self {
            case .importable: true
            case let .alreadyInRYFT(replace): replace
            case .tooManyDays: false
            }
        }
    }

    enum RangePreset: String, CaseIterable, Identifiable, Sendable {
        case allTime, last12Months, last3Months, custom
        var id: String { rawValue }

        var title: String {
            switch self {
            case .allTime: String(localized: "All time", comment: "Training import, step 3: the history range.")
            case .last12Months: String(localized: "Last 12 months", comment: "Training import, step 3: the history range.")
            case .last3Months: String(localized: "Last 3 months", comment: "Training import, step 3: the history range.")
            case .custom: String(localized: "Custom range", comment: "Training import, step 3: the history range, with From and Until.")
            }
        }
    }

    /// One per plan in the files, in file order.
    var plans: [PlanChoice]
    /// The plan to enrol in (an index into `plans`); nil: none.
    var activePlan: Int?
    var includesHistory: Bool
    var preset: RangePreset = .allTime
    /// Custom range, limited to the file's first and last day.
    var from: LocalDate
    var to: LocalDate

    /// The files' plans and sessions; `today` in the flow's zone; `hasEnrollment`: an active or paused plan exists,
    /// so "make active" starts off (ui.md C2).
    init(bundle: ImportBundle, today: LocalDate, hasEnrollment: Bool,
         planExists: (ImportedPlan) -> Bool = { _ in false }) {
        plans = bundle.plans.map { plan in
            if plan.days.count > Self.maxDays { return PlanChoice(isOn: false, state: .tooManyDays(plan.days.count)) }
            if planExists(plan) { return PlanChoice(isOn: false, state: .alreadyInRYFT(replace: false)) }
            return PlanChoice(isOn: true, state: .importable)
        }
        let first = plans.firstIndex { $0.isOn && $0.state.canImport }
        activePlan = hasEnrollment ? nil : first
        includesHistory = !bundle.sessions.isEmpty
        let days = bundle.sessions.map(\.start.date)
        from = days.min() ?? today
        to = min(days.max() ?? today, today)
    }

    /// RYFT plans have at most 7 days (`days_per_week`).
    static let maxDays = 7

    // MARK: Plans

    var importedPlans: [Int] { plans.indices.filter { plans[$0].isOn && plans[$0].state.canImport } }

    mutating func setPlan(_ index: Int, on: Bool) {
        guard plans.indices.contains(index), plans[index].state.canImport || !on else { return }
        plans[index].isOn = on
        if !on, activePlan == index { activePlan = nil }
    }

    /// "Replace with the file's version": the plan is imported over RYFT's copy.
    mutating func replaceExisting(_ index: Int) {
        guard plans.indices.contains(index), case .alreadyInRYFT = plans[index].state else { return }
        plans[index].state = .alreadyInRYFT(replace: true)
        plans[index].isOn = true
    }

    /// The account's check came back: plans whose derived id it has are "Already in RYFT" and off, unless the user
    /// already turned them on meanwhile.
    mutating func markExisting(_ exists: [Bool]) {
        for (index, there) in exists.enumerated() where there && plans.indices.contains(index) {
            guard plans[index].state == .importable else { continue }
            plans[index] = PlanChoice(isOn: false, state: .alreadyInRYFT(replace: false))
            if activePlan == index { activePlan = nil }
        }
    }

    /// "Make this my active plan" for the one plan, or the "Active plan" picker for several.
    mutating func setActive(_ index: Int?) {
        guard let index else {
            activePlan = nil
            return
        }
        guard importedPlans.contains(index) else { return }
        activePlan = index
    }

    // MARK: History

    /// The range's first and last day; nil lower bound: from the first workout.
    func bounds(today: LocalDate, zone: TimeZone) -> (from: LocalDate?, to: LocalDate) {
        switch preset {
        case .allTime: return (nil, today)
        case .last12Months: return (Self.shift(today, months: -12, zone: zone), today)
        case .last3Months: return (Self.shift(today, months: -3, zone: zone), today)
        case .custom: return (from, min(to, today))
        }
    }

    /// Workouts in the range, never one in the future (they are left out and counted in step 5).
    func sessions(in bundle: ImportBundle, today: LocalDate, zone: TimeZone) -> [ImportedSession] {
        guard includesHistory else { return [] }
        let (lower, upper) = bounds(today: today, zone: zone)
        return bundle.sessions.filter { session in
            let day = session.start.date
            return day <= upper && lower.map { day >= $0 } ?? true
        }
    }

    /// Workouts dated after today (a clock or zone problem in the other app).
    static func futureSessions(in bundle: ImportBundle, today: LocalDate) -> Int {
        bundle.sessions.filter { $0.start.date > today }.count
    }

    /// The bundle as chosen: the plans that are on, the workouts in the range. What step 4 maps and step 5 builds.
    func chosen(from bundle: ImportBundle, today: LocalDate, zone: TimeZone) -> ImportBundle {
        var chosen = bundle
        chosen.plans = importedPlans.compactMap { bundle.plans.indices.contains($0) ? bundle.plans[$0] : nil }
        chosen.sessions = sessions(in: bundle, today: today, zone: zone)
        return chosen
    }

    // MARK: Continue

    enum Block: Equatable, Sendable {
        /// C3: both off.
        case nothingSelected
        /// C4: history on, 0 workouts in the range.
        case emptyRange
    }

    func block(bundle: ImportBundle, today: LocalDate, zone: TimeZone) -> Block? {
        let history = sessions(in: bundle, today: today, zone: zone).count
        if includesHistory, history == 0, !bundle.sessions.isEmpty { return .emptyRange }
        if importedPlans.isEmpty, !includesHistory || history == 0 { return .nothingSelected }
        return nil
    }

    /// Performed sets (skipped ones are counted apart, never imported as zero).
    static func performedSets(in sessions: [ImportedSession]) -> Int {
        sessions.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.filter { !$0.isSkipped }.count } }
    }

    static func shift(_ day: LocalDate, months: Int, zone: TimeZone) -> LocalDate? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let date = calendar.date(byAdding: .month, value: months, to: day.date(in: zone)) else { return nil }
        return LocalDate(date, in: zone)
    }
}
