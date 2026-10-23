import Foundation

/// API.md → Activities (a draft of the platform brief until C1): activities the user recorded or added, and
/// manual sleep. Every write is idempotent by the app's id or the day, so a retry never creates a second one.
protocol ActivitiesAPI {
    /// The platform serves these endpoints. False before the contract is published (C1): reads show what's on
    /// the phone without asking, and nothing is recorded as fetched or failed.
    var publishesActivities: Bool { get }
    /// `PUT /v1/activities/{id}`: create or replace, the whole document (`SportActivityPut`). Answers the stored
    /// activity with `scoring_state`; `422` when it breaks the rules (end after start, ≤ 24 h, not in the future).
    func putActivity(_ a: SportActivity) async throws -> SportActivity
    /// `GET /v1/activities?from&to`: activities starting in `[from, to)`, without route and heart-rate samples
    /// (API request R16).
    func activities(from: Date, to: Date) async throws -> [SportActivity]
    /// `GET /v1/activities/{id}`: one activity, with its route (the detail screen holds it in memory only).
    func activity(id: UUID) async throws -> SportActivity
    /// `DELETE /v1/activities/{id}`: `204`; `404` when it's gone already.
    func deleteActivity(id: UUID) async throws
    /// `PUT /v1/sleep/manual/{day}`: a night the user added, for the wake day `yyyy-MM-dd`.
    func putManualSleep(day: String, _ body: ManualSleepPut) async throws
    /// `DELETE /v1/sleep/manual/{day}`.
    func deleteManualSleep(day: String) async throws
}

enum ActivitiesError: Error, Equatable, Sendable {
    /// API.md → Activities isn't published: the live client sent nothing. The uploader reports
    /// "not available yet"; reads show what's on the phone.
    case notPublished
}

/// The live client before C1: every call throws `ActivitiesError.notPublished` without a request. The flags keep
/// the features dark meanwhile. C1 (api-contract-keeper) replaces this with `Networking/APIClient+Activities.swift`.
extension APIClient: ActivitiesAPI {
    var publishesActivities: Bool { false }
    func putActivity(_ a: SportActivity) async throws -> SportActivity { throw ActivitiesError.notPublished }
    func activities(from: Date, to: Date) async throws -> [SportActivity] { throw ActivitiesError.notPublished }
    func activity(id: UUID) async throws -> SportActivity { throw ActivitiesError.notPublished }
    func deleteActivity(id: UUID) async throws { throw ActivitiesError.notPublished }
    func putManualSleep(day: String, _ body: ManualSleepPut) async throws { throw ActivitiesError.notPublished }
    func deleteManualSleep(day: String) async throws { throw ActivitiesError.notPublished }
}
