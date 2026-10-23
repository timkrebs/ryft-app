// My Day is a merged read model (ADR 0006, design.md §2.5): the platform's layer (the cached day detail and the
// day's activities) with this iPhone's layer on top (activities and manual sleep not confirmed yet, Train
// sessions not synced yet). Computed on read by one pure function; never stored.
import Foundation

/// One row of My Day (and of Strain's activity list, without the sleep rows).
struct MyDayItem: Identifiable, Equatable {
    enum Kind: Equatable {
        /// The night that ends on `day` (`yyyy-MM-dd`), a tracker's or added by the user.
        case sleep(day: String)
        /// No sleep for the night that ends on `day` (rule 5): "No sleep recorded".
        case missingSleep(day: String)
        /// A tracker's workout from Apple Health; with its Train session when one is linked (rule 3).
        case workout(UUID)
        /// A Train session no workout points at (yet).
        case session(UUID)
        /// An activity the user added or RYFT recorded.
        case activity(UUID)

        /// Sleep and missing sleep: the rows Strain's list leaves out.
        var isSleep: Bool {
            switch self {
            case .sleep, .missingSleep: return true
            case .workout, .session, .activity: return false
            }
        }
    }

    /// Where the item's strain is (ui.md §2.4).
    enum Strain: Equatable {
        case scored(Double)
        /// Heart rate may still arrive.
        case pending
        /// Scored, and the platform had no heart rate for the time (`strain_source: none`).
        case noHeartRate
        /// Sleep and recordings in progress: no strain to show.
        case notApplicable
    }

    /// Where an item came from (ui.md §2.3): one per row, two when the platform merged it with a tracker's workout
    /// or a workout carries its Train session.
    enum Source: Equatable {
        /// Recorded by RYFT on an iPhone; `indoor` without GPS (an indoor run).
        case ryftRecorded(indoor: Bool)
        /// An activity the user typed in (Add activity).
        case ryftManual
        /// A night the user typed in (Add sleep).
        case addedByYou
        /// A tracker or source in Apple Health, by its display name, with its form factor's glyph.
        case tracker(name: String, symbol: String)
        /// A Train session.
        case train
    }

    /// Stable across renders: `"<kind>.<id>"` ("activity.6F1C…", "sleep.2026-10-22").
    let id: String
    let kind: Kind
    /// The row's SF Symbol.
    let symbol: String
    let title: String
    let start: Date
    /// While recording: the time the list was made.
    let end: Date
    /// What the row says: moving time for an activity, time asleep for sleep, else the span.
    let duration: TimeInterval
    let distanceM: Double?
    let strain: Strain
    /// 1–2; tracker first when merged (ui.md §2.3).
    let sources: [Source]
    /// Own activities and manual sleep only; nil for the platform's other items and recordings in progress.
    let upload: UploadState?
    /// Manual and recorded activities and manual sleep, on any day (design.md §7.3). The actions are A2's.
    let editable: Bool
    /// Train's muscular load (a session, or a workout logged in Train): Strain shows it next to the strain.
    var load: Double?
    /// A recording in progress: no end yet ("07:12–now").
    var isRecording = false

    /// The platform merged an activity with a tracker's workout (two badges, one strain).
    var isMerged: Bool {
        if case .activity = kind { return sources.count > 1 }
        return false
    }
}

/// What the assembler reads: the platform's layer and this iPhone's (ADR 0006).
struct MyDayInput: Equatable {
    /// What the platform said about the day. Once API request R1 is answered, a `myDay` case (the platform's
    /// own items) joins this one; the overlay rules and the rows stay.
    enum Server: Equatable {
        /// `GET /v1/days/{day}` (nil: not cached) and `GET /v1/activities` for the day.
        case dayDetail(DayDetail?, activities: [SportActivity])
    }

    /// `yyyy-MM-dd`.
    var day: String
    var server: Server
    /// Value copies of the account's local activities for the day (`ActivityStore.snapshots(onDay:)`), plus
    /// unconfirmed ones whose edit moved them to another day.
    var local: [LocalActivitySnapshot] = []
    /// The uploader's word per activity (A2: offline, retrying, failed); without one, the row's own
    /// (`LocalActivitySnapshot.storedUploadState`).
    var uploads: [UUID: UploadState] = [:]
    /// Train sessions logged on this iPhone that day (`TrainLibrary.merged(local:remote:)`'s input).
    var localSessions: [SessionSummary] = []
    /// A night the user added for this day, until the platform confirms it.
    var localSleep: ManualSleepSnapshot?
    /// T1's night gap (`TodayStates.nightGap`): the tracker's night is only late, so "No sleep recorded" waits.
    var nightGap = false
}

/// Builds My Day's rows (design.md §2.5): pure, table-tested (`MyDayAssemblerTests`).
enum MyDayAssembler {
    /// "Apple Health": the source of a night until the platform says whose it is (API request R11).
    static let appleHealth = "Apple Health"
    static let appleHealthSymbol = "heart.text.square"

    /// The day's rows, oldest first (sleep first). `includingSleep: false` is Strain's list.
    static func items(_ input: MyDayInput, catalog: TrackerCatalog, now: Date,
                      includingSleep: Bool = true) -> [MyDayItem] {
        let detail: DayDetail?
        let serverActivities: [SportActivity]
        switch input.server {
        case .dayDetail(let d, let list):
            detail = d
            serverActivities = list
        }

        // Rule 4: the local layer over the platform's activities, by id.
        var activities: [UUID: (activity: SportActivity, upload: UploadState?)] = [:]
        for a in serverActivities { activities[a.id] = (a, .confirmed) }
        var recordings: [LocalActivitySnapshot] = []
        for local in input.local {
            if local.isTombstone {
                activities[local.id] = nil
                continue
            }
            guard local.isSaved else {
                if DayFormat.string(from: local.start) == input.day { recordings.append(local) }
                continue
            }
            let upload = input.uploads[local.id] ?? local.storedUploadState
            // An edit that moved the activity to another day hides it here until the platform confirms it.
            guard DayFormat.string(from: local.start) == input.day else {
                if local.needsUpload { activities[local.id] = nil }
                continue
            }
            if local.needsUpload {
                // The user's edit wins until it's confirmed; the platform's last word on strain and merge stays.
                var edited = local.activity
                if let server = activities[local.id]?.activity {
                    edited.strain = server.strain
                    edited.strainSource = server.strainSource
                    edited.hrSource = server.hrSource
                    edited.mergedWith = server.mergedWith
                    edited.scoringState = server.scoringState
                }
                activities[local.id] = (edited, upload)
            } else if activities[local.id] == nil {
                // Confirmed, and the platform's list doesn't have it yet.
                activities[local.id] = (local.activity, upload)
            }
        }

        let workouts = detail?.workouts ?? []
        let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Rule 2: a merged activity hides its workout. Only what the platform reported, never predicted.
        let merged = Set(activities.values.compactMap(\.activity.mergedWith))

        var items: [MyDayItem] = []
        for (activity, upload) in activities.values {
            let workout = activity.mergedWith.flatMap { workoutsByID[$0] }
            items.append(item(activity, upload: upload, mergedWith: workout, catalog: catalog))
        }
        items += recordings.map { recording($0, now: now) }

        // Rule 3: a workout and its Train session are one row; sessions without a workout follow.
        let sessions = TrainLibrary.merged(local: input.localSessions, remote: detail?.strain?.sessions ?? [])
        var linked = Set<UUID>()
        for w in workouts where !merged.contains(w.id) {
            let session = sessions.first { $0.id == w.sessionId || $0.workoutId == w.id }
            if let session { linked.insert(session.id) }
            items.append(item(w, session: session, catalog: catalog))
        }
        items += sessions.filter { !linked.contains($0.id) }.map(item(session:))

        // Rule 5: the night.
        if includingSleep, let sleep = sleepItem(input, detail: detail) { items.append(sleep) }

        // Rule 6: by start, sleep first, then a stable order.
        return items.sorted { a, b in
            if a.kind.isSleep != b.kind.isSleep { return a.kind.isSleep }
            if a.start != b.start { return a.start < b.start }
            return a.id < b.id
        }
    }

    // MARK: activities

    private static func item(_ a: SportActivity, upload: UploadState?, mergedWith workout: Workout?,
                             catalog: TrackerCatalog) -> MyDayItem {
        let own: MyDayItem.Source = a.origin == .recorded ? .ryftRecorded(indoor: !a.sport.hasGPS) : .ryftManual
        // The tracker's badge first: its heart rate is what scored the merged row (ui.md §2.3).
        let sources = workout.map { [tracker(for: $0, catalog: catalog), own] } ?? [own]
        let span = max(0, a.end.timeIntervalSince(a.start))
        return MyDayItem(id: "activity.\(a.id.uuidString)", kind: .activity(a.id), symbol: a.sport.symbol,
                         title: a.sport.name, start: a.start, end: a.end, duration: a.movingSec > 0 ? a.movingSec : span,
                         distanceM: a.distanceM, strain: strain(a), sources: sources, upload: upload, editable: true)
    }

    private static func recording(_ r: LocalActivitySnapshot, now: Date) -> MyDayItem {
        MyDayItem(id: "activity.\(r.id.uuidString)", kind: .activity(r.id), symbol: r.sport.symbol, title: r.sport.name,
                  start: r.start, end: max(r.start, now), duration: max(0, now.timeIntervalSince(r.start)),
                  distanceM: r.distanceM, strain: .notApplicable, sources: [.ryftRecorded(indoor: !r.sport.hasGPS)],
                  upload: nil, editable: false, isRecording: true)
    }

    /// Strain per item (design.md §2.5): a value is scored; `strain_source: none` is "no heart rate"; else pending.
    static func strain(_ a: SportActivity) -> MyDayItem.Strain {
        if let value = a.strain { return .scored(value) }
        if a.strainSource == .noSource { return .noHeartRate }
        return .pending
    }

    // MARK: workouts and sessions

    private static func item(_ w: Workout, session: SessionSummary?, catalog: TrackerCatalog) -> MyDayItem {
        var sources = [tracker(for: w, catalog: catalog)]
        if session != nil { sources.append(.train) }
        let title = session.flatMap { $0.title.isEmpty ? nil : $0.title } ?? ActivityStyle.title(for: w.activity)
        let value = w.strain ?? session?.strain
        return MyDayItem(id: "workout.\(w.id.uuidString)", kind: .workout(w.id),
                         symbol: session == nil ? ActivityStyle.icon(for: w.activity) : "dumbbell.fill", title: title,
                         start: w.start, end: w.end, duration: w.duration, distanceM: w.distanceM,
                         strain: value.map(MyDayItem.Strain.scored) ?? .pending, sources: sources, upload: nil,
                         editable: false, load: session?.muscularTrimp ?? w.muscularLoad)
    }

    private static func item(session s: SessionSummary) -> MyDayItem {
        let end = s.endedAt ?? s.startedAt.addingTimeInterval(Double(s.durationMin ?? 0) * 60)
        let duration = s.durationMin.map { Double($0) * 60 } ?? max(0, end.timeIntervalSince(s.startedAt))
        return MyDayItem(id: "session.\(s.id.uuidString)", kind: .session(s.id), symbol: "dumbbell.fill",
                         title: s.title.isEmpty ? String(localized: "Workout") : s.title, start: s.startedAt, end: end,
                         duration: duration, distanceM: nil, strain: s.strain.map(MyDayItem.Strain.scored) ?? .pending,
                         sources: [.train], upload: nil, editable: false, load: s.muscularTrimp)
    }

    /// A workout's source by the tracker catalog's name (T1's frozen API) and its form factor's glyph.
    static func tracker(for w: Workout, catalog: TrackerCatalog) -> MyDayItem.Source {
        let ref = SourceRef(name: w.source, bundleID: w.sourceBundleId, deviceModel: nil)
        let name = catalog.displayName(ref)
        guard !name.isEmpty else { return .tracker(name: appleHealth, symbol: appleHealthSymbol) }
        // The glyph only: a source without a bundle ID that carries a tracker app's exact name ("Garmin Connect")
        // gets that tracker's form factor. Identity stays the catalog's match.
        let tracker = catalog.match(ref)
            ?? catalog.trackers.first { $0.appTitle.caseInsensitiveCompare(name) == .orderedSame }
        return .tracker(name: name, symbol: tracker?.symbol ?? "ellipsis.circle")
    }

    // MARK: sleep

    /// Rule 5. A pending manual night wins until confirmed (as an activity edit does); a deleted one hides the
    /// platform's copy of it. Without any night, and with the day loaded, "No sleep recorded", unless the
    /// tracker's night is only late (`nightGap`).
    private static func sleepItem(_ input: MyDayInput, detail: DayDetail?) -> MyDayItem? {
        let server = detail?.sleep.flatMap { s -> (start: Date, end: Date, asleep: TimeInterval?)? in
            guard let end = s.end ?? s.start.map({ $0.addingTimeInterval(Double(s.inBedMin ?? s.totalMin ?? 0) * 60) })
            else { return nil }
            let start = s.start ?? end.addingTimeInterval(-Double(s.inBedMin ?? s.totalMin ?? 0) * 60)
            return (start, end, s.totalMin.map { Double($0) * 60 })
        }
        let local = input.localSleep
        // The platform's night is the one the user added: same times (until R11 says so itself).
        let serverIsManual = local.map { l in server.map { $0.start == l.bed && $0.end == l.wake } ?? false } ?? false

        if let local, !local.isTombstone, local.needsUpload || server == nil {
            return MyDayItem(id: "sleep.\(input.day)", kind: .sleep(day: input.day), symbol: "bed.double.fill",
                             title: String(localized: "Sleep"), start: local.bed, end: local.wake,
                             duration: max(0, local.wake.timeIntervalSince(local.bed)), distanceM: nil,
                             strain: .notApplicable, sources: [.addedByYou],
                             upload: local.needsUpload ? .pending(.queued) : .confirmed, editable: true)
        }
        if let server, !(local?.isTombstone == true && serverIsManual) {
            let manual = serverIsManual && local?.isTombstone == false
            return MyDayItem(id: "sleep.\(input.day)", kind: .sleep(day: input.day), symbol: "bed.double.fill",
                             title: String(localized: "Sleep"), start: server.start, end: server.end,
                             duration: server.asleep ?? max(0, server.end.timeIntervalSince(server.start)), distanceM: nil,
                             strain: .notApplicable,
                             sources: [manual ? .addedByYou : .tracker(name: appleHealth, symbol: appleHealthSymbol)],
                             upload: manual ? .confirmed : nil, editable: manual)
        }
        // A night the platform has without times isn't a missing one.
        guard detail != nil, detail?.sleep == nil, !input.nightGap else { return nil }
        let dayStart = DayFormat.date(from: input.day) ?? .distantPast
        return MyDayItem(id: "nosleep.\(input.day)", kind: .missingSleep(day: input.day), symbol: "bed.double",
                         title: String(localized: "No sleep recorded"), start: dayStart, end: dayStart, duration: 0,
                         distanceM: nil, strain: .notApplicable, sources: [], upload: nil, editable: false)
    }
}
