import Foundation

/// What Import sends, wire-ready (design §7): built off the main actor by `ImportBuilder`, assembled for the user's
/// toggles by `ImportBuild.uploadPlan(including:planNames:)`, and stored in the job (`PendingImport.payload`) until it's
/// uploaded. It holds no file text beyond the names and titles the platform stores anyway.
struct ImportUploadPlan: Codable, Equatable, Sendable {
    /// New custom exercises the plans and sessions use, created first with `POST /v1/exercises`, one at a time.
    var exercises: [Exercise] = []
    /// At most 50 (`ImportLimits.maxPlans`); sent at most 5 per request, in the first requests.
    var plans: [Plan] = []
    /// Completed sessions, oldest first; at most 50 per request.
    var sessions: [TrainSession] = []
    /// "Make this my active plan": enrolled (week 1, day 0) once this plan is `done`.
    var enrolPlanID: UUID?
    /// What the preview left out, for the result screen.
    var skipped = ImportSkipCounts()

    var isEmpty: Bool { exercises.isEmpty && plans.isEmpty && sessions.isEmpty && enrolPlanID == nil }
}

/// Counts of what wasn't sent, and why (ui.md §8). Sessions are counted once, by their first reason.
struct ImportSkipCounts: Codable, Equatable, Sendable {
    /// Their derived id is already on the account (a re-import): never sent.
    var alreadyImported = 0
    /// "Looks like a session you already logged", left off in the preview.
    var duplicates = 0
    /// Turned off by hand in the preview (not duplicates).
    var deselected = 0
    /// Before or after the chosen history range.
    var outsideRange = 0
    /// Dated after the moment the preview was built (a clock or zone problem in the file).
    var inFuture = 0
    /// No performed set left (every set skipped, or every exercise left out).
    var empty = 0
    /// Sets with no weight and no reps, or zero reps, in the sessions that are sent: counted, never sent as zero.
    var skippedSets = 0
    /// Plans the user turned off, or kept as RYFT's copy ("Already in RYFT").
    var plans = 0
}
