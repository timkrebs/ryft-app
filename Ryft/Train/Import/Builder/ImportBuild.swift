import Foundation

// The builder's input and output (design §6, §8; ui.md §6–§8). The flow model (I4) keeps an `ImportDecisions`, asks
// `TrainImportUploader.checkExisting(_:)` what the account already has, runs `ImportBuilder.build` off the main actor,
// shows the `ImportBuild`, and hands `ImportBuild.uploadPlan(including:planNames:)` to `TrainImportUploader.start`.

// MARK: - decisions (steps 3 and 4)

/// What the user decided in steps 3 and 4, for `ImportBuilder`. Step 5's per-workout toggles and the plan name are
/// applied later, without a rebuild (`ImportBuild.uploadPlan`).
struct ImportDecisions: Equatable, Sendable {
    /// The account the flow started with: its id, or `ImportMappingStore.demoAccount` in demo mode. Part of every
    /// derived id (ADR 0007).
    var account: String
    /// The zone captured when the flow started (design §3): times and days are read in it, never ids.
    var zone: TimeZone
    /// What each source exercise became in step 4, by its frozen key (`ExerciseNormalizer.key`). A key without an
    /// entry is left out, like `.skip`.
    var exercises: [SourceExerciseKey: ImportExerciseChoice]
    /// One per plan of the bundle, in the bundle's order. Missing entries count as `ImportPlanChoice()`.
    var plans: [ImportPlanChoice]
    var history: ImportHistoryChoice
    /// "Make this my active plan": the bundle index of the plan to enrol in (week 1, day 0, once it's uploaded).
    var enrolPlanIndex: Int?

    init(account: String, zone: TimeZone, exercises: [SourceExerciseKey: ImportExerciseChoice] = [:],
         plans: [ImportPlanChoice] = [], history: ImportHistoryChoice = ImportHistoryChoice(), enrolPlanIndex: Int? = nil) {
        self.account = account
        self.zone = zone
        self.exercises = exercises
        self.plans = plans
        self.history = history
        self.enrolPlanIndex = enrolPlanIndex
    }
}

/// One source exercise after step 4.
struct ImportExerciseChoice: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        /// An exercise in the library (built-in or the user's own): accepted, remembered or picked.
        case library(Exercise)
        /// A new custom exercise (`ImportCustomExercise.make`): created first, with its derived id.
        case custom(Exercise)
        /// "Don't import": its plan rows and sets are left out.
        case skip
    }

    var target: Target
    /// The answer to the `+N` question (design §5), when it was asked. nil: the default for the load type.
    var bodyweight: BodyweightAnswer?

    init(_ target: Target, bodyweight: BodyweightAnswer? = nil) {
        self.target = target
        self.bodyweight = bodyweight
    }

    var exercise: Exercise? {
        switch target {
        case let .library(e), let .custom(e): e
        case .skip: nil
        }
    }
}

/// Step 3's plan card, per plan.
struct ImportPlanChoice: Equatable, Sendable {
    /// The toggle (on by default).
    var included = true
    /// "Replace with the file's version" for a plan that's already in RYFT: off keeps RYFT's copy (design §6).
    var replaceExisting = false
}

/// Step 3's history card.
struct ImportHistoryChoice: Equatable, Sendable {
    /// The toggle (on by default).
    var included = true
    /// The first and last day to import, inclusive, as written in the file; nil: open on that side ("All time").
    var from: LocalDate?
    var to: LocalDate?

    func contains(_ day: LocalDate) -> Bool {
        if let from, day < from { return false }
        if let to, to < day { return false }
        return true
    }
}

// MARK: - what the account already has (design §6)

/// What to ask the platform before the preview: the import's derived ids and the days it covers.
/// `ImportBuilder.query(for:decisions:source:)` derives it; `TrainImportUploader.checkExisting(_:)` answers it.
struct ImportExistingQuery: Equatable, Sendable {
    let account: String
    /// The derived plan ids (design §6), one per plan of the bundle.
    let planIDs: [UUID]
    /// The derived session ids, one per session of the bundle.
    let sessionIDs: [UUID]
    /// The local days (`LocalDate.key`) with an imported session: logged sessions are read only for these.
    let days: Set<String>
    /// The instants that cover those days in the flow's zone, for `GET /v1/sessions`; nil without sessions.
    let range: ClosedRange<Date>?
    let zone: TimeZone
}

/// The account's side, read when the preview is built (and again by the uploader after an offline preview).
struct ImportExisting: Equatable, Sendable {
    /// False: it couldn't be read (offline, an error). Nothing is flagged and no id counts as existing; the job is
    /// saved with `duplicatesChecked = false` and the uploader checks before its first session batch.
    var checked: Bool
    /// Derived plan ids that are already the user's own plans, with their current copy when it could be read.
    var plans: [UUID: Plan?]
    /// Derived session ids already on the account: "Already imported", never sent.
    var sessionIDs: Set<UUID>
    /// Sessions logged in RYFT (not imports) on the import's days, for duplicates: on the platform, and finished on
    /// this iPhone but not uploaded yet.
    var logged: [LoggedSession]

    static let unchecked = ImportExisting(checked: false, plans: [:], sessionIDs: [], logged: [])
}

/// A session the user logged in RYFT, as duplicate detection sees it.
struct LoggedSession: Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    /// Distinct exercises with at least one performed set (a completed working or warm-up set).
    let exerciseIDs: Set<UUID>
}

// MARK: - the build (step 5)

/// The preview and everything Import sends, built by `ImportBuilder.build` for one `ImportDecisions` and
/// `ImportExisting`. Per-workout toggles and the plan names are applied by `uploadPlan(including:planNames:)`.
struct ImportBuild: Equatable, Sendable {
    let account: String
    let source: ImportFormatID
    let zone: TimeZone
    /// The bundle's plans, in its order.
    var plans: [ImportPlanPreview]
    /// The bundle's sessions, in its order (newest first in Alpha Progression's exports).
    var sessions: [ImportSessionPreview]
    /// The custom exercises the built plans and sessions use (step 4's "new" rows), by id.
    var customExercises: [Exercise]
    /// The builder's notes (`nonexistentLocalTime`, `repeatedLocalTime`, `durationAssumed`, `overPlatformLimit`,
    /// `assistedLoad`), at their lines, sorted. Shown in step 5 by kind and line, never with file text.
    var warnings: [ImportWarning]
    /// Whether duplicates and existing ids were checked (`ImportExisting.checked`).
    var duplicatesChecked: Bool
    /// The plan to enrol in, when it's sent (or already in RYFT).
    var enrolPlanID: UUID?

    /// The sessions sent unless the user toggles them: every `.new` one. Duplicates start off.
    var defaultIncluded: Set<UUID> { Set(sessions.filter { $0.verdict.isIncludedByDefault }.map(\.id)) }

    /// Step 5's numbers for the sessions the user has on (`included`, starting from `defaultIncluded`). Only `.new`
    /// and `.duplicate` sessions can be on; others are ignored.
    func totals(including included: Set<UUID>) -> ImportTotals {
        ImportBuilder.totals(of: self, including: included)
    }

    /// What Import sends: the plans that are on and not kept as RYFT's copy (renamed per `planNames`, ≤ 80
    /// characters, an empty name keeps the file's), the included sessions oldest first (their plan links dropped when
    /// their plan isn't sent and isn't already in RYFT), and the custom exercises they use.
    func uploadPlan(including included: Set<UUID>, planNames: [UUID: String] = [:]) -> ImportUploadPlan {
        ImportBuilder.uploadPlan(of: self, including: included, planNames: planNames)
    }
}

/// One plan of the file as RYFT will create it.
struct ImportPlanPreview: Equatable, Sendable, Identifiable {
    enum State: Equatable, Sendable {
        /// Not on the account: created.
        case new
        /// Its derived id is already one of the user's plans: kept as RYFT's copy unless `replaceExisting`.
        case alreadyInRYFT
        /// It can't be a RYFT plan; the history can still be imported.
        case cannotImport(ImportPlanRefusal)
    }

    /// Index in the bundle's plans.
    let index: Int
    /// The derived id (ADR 0007).
    let id: UUID
    let state: State
    /// The plan as built (with the file's name), nil when it can't be imported.
    let plan: Plan?
    /// On, and either new or replacing RYFT's copy.
    let willBeSent: Bool
    /// "Last time" per plan exercise id: the heaviest performed set of the most recent imported session with that
    /// exercise (the same plan day first). Its `kg` is the plan exercise's target; exercises without one show RPE 8.
    let lastTime: [UUID: ImportLastTime]
    /// Plan rows whose exercise was left out in step 4, in file order (shown once: "Not imported (1): …").
    let skippedExerciseNames: [String]

    /// "Make this my active plan" can be offered.
    var canEnrol: Bool { plan != nil }
}

/// Why a file's plan can't be imported (ui.md §6, 1b).
enum ImportPlanRefusal: Equatable, Sendable {
    /// More than 7 days: RYFT plans have at most 7.
    case tooManyDays(Int)
    /// Every exercise was left out in step 4.
    case noExercises
    /// It fails the plan checks (`PlanValidation.issues(in:)`).
    case invalid([PlanIssue])
}

/// The "last time" line under a plan exercise in step 5.
struct ImportLastTime: Equatable, Sendable {
    let kg: Double
    let day: LocalDate
    let sessionID: UUID
}

/// One workout of the file as RYFT will create it.
struct ImportSessionPreview: Equatable, Sendable, Identifiable {
    enum Verdict: Equatable, Sendable {
        /// Sent unless turned off.
        case new
        /// Same local day and ≥ 70 % of its exercises in common with a session already logged in RYFT
        /// (`DuplicateDetector`): "Looks like a session you already logged", off unless turned on.
        case duplicate(of: UUID)
        /// Its derived id is already on the account: "Already imported", never sent, no toggle.
        case alreadyImported
        /// Outside the chosen history range.
        case outsideRange
        /// After the moment the preview was built.
        case inFuture
        /// No performed set left: every set skipped, or every exercise left out.
        case empty
        /// Workout history is off in step 3.
        case historyOff

        var isIncludedByDefault: Bool { self == .new }

        /// Step 5 shows a toggle for it.
        var isToggleable: Bool {
            switch self {
            case .new, .duplicate: true
            case .alreadyImported, .outsideRange, .inFuture, .empty, .historyOff: false
            }
        }
    }

    /// Index in the bundle's sessions.
    let index: Int
    /// The derived id (ADR 0007).
    let id: UUID
    let verdict: Verdict
    /// The completed session as it would be sent; nil for `.empty` and `.historyOff`.
    let session: TrainSession?
    /// When it started, in the flow's zone (after the clock-change rules).
    let startedAt: Date
    /// The file's wall-clock day: step 5 groups by month and shows it.
    let day: LocalDate
    let exerciseCount: Int
    /// Performed sets that are sent.
    let setCount: Int
    /// Sets with no weight and reps, or zero reps: counted, not sent.
    let skippedSetCount: Int
    /// Σ weight × reps of the sent sets with a weight, in kg.
    let volumeKg: Double
    /// `.nonexistentLocalTime` or `.repeatedLocalTime` when a clock change moved its start; nil otherwise.
    let clockChange: ImportWarning.Kind?
}

/// Step 5's numbers for the sessions that are on.
struct ImportTotals: Equatable, Sendable {
    var plans = 0
    var sessions = 0
    var sets = 0
    var volumeKg = 0.0
    /// Skipped sets in the sessions that are on.
    var skippedSets = 0
    var customExercises = 0
    /// Sessions flagged as duplicates and still off.
    var duplicatesOff = 0
    var alreadyImported = 0
    var outsideRange = 0
    var inFuture = 0
    var empty = 0
    /// Sessions that are on and start on a clock change.
    var clockChanges = 0

    /// Nothing would be sent ("Nothing to import", V3).
    var isNothing: Bool { plans == 0 && sessions == 0 }
}
