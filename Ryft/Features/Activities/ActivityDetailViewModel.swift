import Foundation
import Observation

/// Which activity a detail shows, and the day it was opened from (its platform copy is cached there).
struct ActivityRoute: Hashable, Identifiable {
    let id: UUID
    let day: Date
}

/// One activity the user added or RYFT recorded (ui.md §8, design.md §7.3; A2: without map and charts). Reads only
/// what's cached: this iPhone's row (an edit wins until confirmed, the platform's strain kept) or the platform's copy,
/// and the uploader's word on it. Edit and Delete follow the origin; a platform-only activity becomes the account's
/// row first (`ActivityStore.adopt`).
@MainActor
@Observable
final class ActivityDetailViewModel {
    let id: UUID
    private let state: AppState
    /// The day it was opened from.
    private let openedOn: Date

    init(route: ActivityRoute, state: AppState) {
        id = route.id
        self.state = state
        openedOn = Calendar.current.startOfDay(for: route.day)
    }

    private var env: AppEnvironment { state.env }

    // MARK: reads

    /// This iPhone's row; nil when only the platform has it.
    var local: LocalActivitySnapshot? { env.activities.snapshot(id: id) }

    /// The day it starts on now (an edit can move it).
    var day: Date { local.map { Calendar.current.startOfDay(for: $0.start) } ?? openedOn }

    /// The platform's copy, cached for its day or the day it was opened from.
    var serverCopy: SportActivity? {
        for d in Set([day, openedOn]) {
            if let a = state.repository.activities(day: DayFormat.string(from: d)).first(where: { $0.id == id }) { return a }
        }
        return nil
    }

    /// As shown: this iPhone's saved row with the platform's last strain and merge, else the platform's copy; nil
    /// once deleted.
    var activity: SportActivity? {
        if let local {
            guard !local.isTombstone, local.isSaved else { return nil }
            var a = local.activity
            if let server = serverCopy {
                a.strain = server.strain
                a.strainSource = server.strainSource
                a.hrSource = server.hrSource
                a.mergedWith = server.mergedWith
                a.scoringState = server.scoringState
            }
            return a
        }
        return serverCopy
    }

    /// The row as My Day shows it: strain state, sources, upload state, merge.
    var item: MyDayItem? {
        let key = DayFormat.string(from: day)
        let detail = state.cachedDayDetail(for: day)
        let server = serverCopy.map { [$0] } ?? []
        let uploads = local.map { [$0.id: env.uploader.state(for: $0)] } ?? [:]
        let input = MyDayInput(day: key, server: .dayDetail(detail, activities: server), local: local.map { [$0] } ?? [],
                               uploads: uploads)
        return MyDayAssembler.items(input, catalog: input.catalog(env, ready: true), now: env.clock.now(), includingSleep: false)
            .first { $0.kind == .activity(id) }
    }

    /// The uploader's word; nil when the platform has it and this iPhone has nothing to send.
    var upload: UploadState? {
        guard let local, local.needsUpload else { return nil }
        return env.uploader.state(for: local)
    }

    /// The tracker's workout the platform merged it with (cached for the day): its heart rate and zones.
    var mergedWorkout: Workout? {
        guard let wid = item?.mergedWorkout ?? activity?.mergedWith else { return nil }
        return state.cachedDayDetail(for: day)?.workouts.first { $0.id == wid }
    }

    var isMerged: Bool { activity?.mergedWith != nil }
    /// Manual and recorded activities, on any day; not a recording in progress or an origin this build doesn't know.
    var isEditable: Bool { (activity?.isEditable ?? false) && (local?.isSaved ?? true) }
    var isRecorded: Bool { activity?.origin == .recorded }
    /// A manual Strength activity: suggest Train (D8).
    var suggestsTrain: Bool { activity?.sport == .strength && activity?.origin == .manual }
    /// Offline: what's shown is what's on this iPhone (ui.md §8.2).
    var isOffline: Bool { !(env.isDemo || env.connectivity.isOnline) }

    // MARK: words

    var title: String { activity?.sport.name ?? String(localized: "Activity", comment: "Activity detail: the title before it's loaded.") }
    var symbol: String { activity?.sport.symbol ?? Sport.other.symbol }

    /// "Monday, 19 Oct · 06:40–07:32".
    func when(locale: Locale) -> String {
        guard let a = activity else { return "" }
        let date = a.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale))
        return "\(date) · \(Fmt.time(a.start, locale: locale))–\(Fmt.time(a.end, locale: locale))"
    }

    struct Stat: Identifiable, Equatable {
        let title: String
        let value: String
        var id: String { title }
    }

    /// Distance, moving time, pace or speed, climb, effort, strain: only what exists.
    func stats(locale: Locale) -> [Stat] {
        guard let a = activity else { return [] }
        var out: [Stat] = []
        if let d = a.distanceM, d > 0 { out.append(Stat(title: String(localized: "Distance"), value: Fmt.distance(meters: d))) }
        out.append(Stat(title: String(localized: "Duration"), value: Fmt.duration(seconds: a.movingSec)))
        if a.sport.paceStyle == .speed {
            if let v = ActivityFormat.speed(movingSec: a.movingSec, distanceM: a.distanceM, locale: locale) {
                out.append(Stat(title: String(localized: "Avg speed", comment: "Activity detail: average moving speed."), value: v))
            }
        } else if let v = ActivityFormat.pace(movingSec: a.movingSec, distanceM: a.distanceM, locale: locale) {
            out.append(Stat(title: String(localized: "Avg pace", comment: "Activity detail: average time per kilometre or mile."), value: v))
        }
        if let up = ActivityFormat.elevation(a.ascentM, locale: locale), (a.ascentM ?? 0) > 0 {
            out.append(Stat(title: String(localized: "Ascent", comment: "Activity detail: metres climbed."), value: up))
        }
        if let effort = a.perceivedEffort {
            out.append(Stat(title: String(localized: "Effort", comment: "Activity detail: perceived effort, 1 to 10."), value: "\(effort) / 10"))
        }
        if let strain = a.strain { out.append(Stat(title: String(localized: "Strain"), value: Fmt.strain(strain))) }
        return out
    }

    /// The strain card's line (ui.md §8.1.3).
    enum StrainLine: Equatable {
        /// D5: from heart rate, and whose.
        case heartRate(Double, source: String?)
        /// D6: from the effort rating.
        case effort(Double, rating: Int?)
        /// A value without a source the build knows.
        case value(Double)
        /// D7, scored: no heart rate for the time.
        case noHeartRate
        /// R1/R2: heart rate may still arrive.
        case waiting
    }

    var strainLine: StrainLine {
        guard let a = activity else { return .waiting }
        if let value = a.strain {
            switch a.strainSource {
            case .heartRate?: return .heartRate(value, source: a.hrSource)
            case .perceivedEffort?: return .effort(value, rating: a.perceivedEffort)
            case .noSource?, nil: return .value(value)
            }
        }
        return a.strainSource == .noSource ? .noHeartRate : .waiting
    }

    /// The tracker's name on a merged activity ("Garmin Connect").
    var mergeSource: String? {
        for source in item?.sources ?? [] {
            if case .tracker(let name, _) = source { return name }
        }
        return activity?.hrSource
    }

    // MARK: upload

    /// What the header's message says about the upload (ui.md §2.4, §3.6); nil when nothing is pending.
    enum UploadNote: Equatable {
        /// `gated`: consent, the invite or the account itself isn't ready; `accountDeleting`: the queue holds because
        /// the account is being deleted, and the activity goes with it.
        case uploading, offline, notAvailableYet, gated, accountDeleting, retrying
        /// The platform refused it (a `4xx`): Edit, Details, Try again.
        case refused(UploadAttempt)
        /// Transient failures in a row: Retry, Details.
        case failed(UploadAttempt)
    }

    var uploadNote: UploadNote? {
        switch upload {
        case .pending(let p)?:
            switch p {
            case .queued, .inFlight: return .uploading
            case .offline: return .offline
            case .notAvailableYet: return .notAvailableYet
            case .gated: return env.auth.isDeletingAccount ? .accountDeleting : .gated
            case .retrying: return .retrying
            }
        case .failed(let attempt)?:
            return attempt.kind == .other || attempt.kind == .appTooOld ? .refused(attempt) : .failed(attempt)
        case .confirmed?, nil:
            return nil
        }
    }

    // MARK: actions

    /// The edit sheet's model; nil when it can't be edited.
    func editModel() -> AddActivityModel? {
        guard isEditable, let activity else { return nil }
        return AddActivityModel(env: env, editing: activity, merged: isMerged)
    }

    /// Delete (after the confirmation): a tombstone until the platform confirms it, or gone at once when it never
    /// reached the platform. False when it can't be deleted.
    @discardableResult
    func delete() -> Bool {
        guard isEditable else { return false }
        if local == nil {
            guard let activity, env.activities.adopt(activity) != nil else { return false }
        }
        env.uploader.deleted(id)
        return true
    }

    /// Retry a failed upload now.
    func retry() async {
        await env.uploader.retry(id)
    }
}

extension UploadAttempt {
    /// Details: status, code, request ID, time (never a body).
    var details: String {
        var parts: [String] = []
        if let status { parts.append("HTTP \(status)") }
        if let code { parts.append(code) }
        if let requestID { parts.append("request-id \(requestID)") }
        parts.append(at.ISO8601Format())
        return parts.joined(separator: " · ")
    }
}
