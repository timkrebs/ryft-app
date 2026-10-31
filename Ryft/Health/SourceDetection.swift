import Foundation

// Source detection (architecture.md §D4, design.md §D4): which apps and devices wrote to Apple Health in the last
// 7 days, for the Sources screen and the wizard's pre-selection. It reuses Check sync's reads (`HealthProbe.run`,
// one `HKSourceQuery` per type and each source's newest record) with a 7-day window; nothing new is asked of
// HealthKit. Counts come from the sync's tally (`SourceTally`), not from reading every record of the week.

/// What Apple Health holds per source in the last 7 days, as the Sources screen and the wizard show it. Built off the
/// main actor by `HealthProbe.sources`, never persisted.
struct SourceDetection: Equatable, Sendable {
    /// The last 7 days, up to `at`.
    let window: DateInterval
    let at: Date
    /// Newest first; RYFT's own records are never a source.
    let sources: [DetectedSource]
    /// Types RYFT sees from any source but itself, ever. Empty: RYFT *may* not be allowed to read (design.md §D4.4
    /// state 5); HealthKit never says a read is denied.
    let visible: Set<HealthStream>
    /// Catalog trackers seen, in picker order: the iPhone only when nothing else, never Other. What the wizard
    /// pre-selects.
    let trackerIDs: [String]

    /// How far back detection looks.
    static let days = 7
    static var span: TimeInterval { TimeInterval(days) * 86_400 }

    /// Whether RYFT may not read at all: not one type visible, not even the iPhone's steps. Never "is".
    var mayNotRead: Bool { visible.isEmpty }

    /// Note A: picked trackers that wrote nothing in the window (the dashed rows), in the order given. Other and
    /// trackers RYFT can't read on iPhone are never listed: nothing could arrive from them. An Apple device isn't
    /// listed while an Apple source that doesn't say which device wrote (it may be this one).
    func silent(among picked: [Tracker]) -> [Tracker] {
        let seen = Set(sources.compactMap(\.trackerID))
        let anonymousApple = sources.contains(where: \.isAnonymousApple)
        return picked.filter { tracker in
            switch tracker.integration {
            case .none, .unknown: return false
            case .appleBuiltin: return !seen.contains(tracker.id) && !anonymousApple
            case .vendorApp: return !seen.contains(tracker.id)
            }
        }
    }

    /// Note B: picked trackers with a source that writes heart rate but no HRV, as the catalog says it doesn't.
    func withoutHRV(among picked: [Tracker]) -> [Tracker] {
        let ids = Set(sources.filter { $0.noHRV != nil }.compactMap(\.trackerID))
        return picked.filter { ids.contains($0.id) }
    }

    /// The pure part (architecture.md §D4.2): the probe's newest records and visible types, the sync's tally and the
    /// platform's `User.sources` in, the screen's rows out. `received`: nil without a platform answer (no
    /// `GET /v1/me` yet, offline, demo).
    static func build(samples: [SourceSample], visible: Set<HealthStream>, tally: SourceTally?, received: [UserSource]?,
                      catalog: TrackerCatalog, now: Date, calendar: Calendar = .current) -> SourceDetection {
        let window = DateInterval(start: now.addingTimeInterval(-span), end: now)
        let recent = samples.filter { $0.newest >= window.start && !HealthProbe.isRYFT($0.source) }
        var order: [String] = []
        var bySource: [String: [SourceSample]] = [:]
        for sample in recent {
            let key = SourceTally.key(sample.source)
            if bySource[key] == nil { order.append(key) }
            bySource[key, default: []].append(sample)
        }
        let sources = order.compactMap { key -> DetectedSource? in
            guard let list = bySource[key] else { return nil }
            return source(key: key, list, tally: tally, received: received, catalog: catalog, window: window,
                          calendar: calendar)
        }
        .sorted { ($0.lastSeen, $1.displayName) > ($1.lastSeen, $0.displayName) }
        let trackerIDs = TrackerCheckRules.seen(recent, catalog: catalog, since: window.start)
            .map(\.id).filter { $0 != "other" }
        return SourceDetection(window: window, at: now, sources: sources, visible: visible, trackerIDs: trackerIDs)
    }

    // swiftlint:disable:next function_parameter_count
    private static func source(key: String, _ list: [SourceSample], tally: SourceTally?, received: [UserSource]?,
                               catalog: TrackerCatalog, window: DateInterval, calendar: Calendar) -> DetectedSource? {
        guard let newest = list.max(by: { $0.newest < $1.newest }) else { return nil }
        // The newest record's device names the source; another type's, when the newest has none.
        let model = newest.source.deviceModel ?? list.lazy.compactMap(\.source.deviceModel).first
        let ref = SourceRef(name: newest.source.name, bundleID: newest.source.bundleID, deviceModel: model)
        var signals: [TrackerSignal: Date] = [:]
        for sample in list {
            guard let signal = TrackerSignal.allCases.first(where: { $0.stream == sample.stream }) else { continue }
            signals[signal] = max(signals[signal] ?? sample.newest, sample.newest)
            if signal == .sleep, sample.hasStages == true {
                signals[.sleepStages] = max(signals[.sleepStages] ?? sample.newest, sample.newest)
            }
        }
        let tracker = catalog.match(ref)
        return DetectedSource(ref: ref, displayName: catalog.displayName(ref), trackerID: tracker?.id, signals: signals,
                              lastSeen: newest.newest,
                              count: count(key: key, tally: tally, window: window, calendar: calendar),
                              received: Self.received(ref, in: received),
                              noHRV: tracker.flatMap { noHRV($0, signals: signals) })
    }

    /// **The `samples_7d` seam** (architecture.md §D4.5): the one rule that decides a row's count. Today the phone's
    /// tally, once it covers the window; nil before, rather than a number that is too low. Once `API.md` gives
    /// `User.sources[].samples_7d`, this takes the platform's total when the source has one, else the tally, else
    /// nil, and `DetectedSource.Count` gains its `platform` case. Nothing else changes.
    static func count(key: String, tally: SourceTally?, window: DateInterval, calendar: Calendar = .current)
        -> DetectedSource.Count? {
        guard let tally, tally.covers(window) else { return nil }
        return .phone(tally.records(key, streams: countedStreams, in: window, calendar: calendar))
    }

    /// The types a count adds up: those the chips show (not active energy or VO₂ max).
    static let countedStreams = Set(TrackerCheckRules.streams.map(\.anchorID))

    /// What the platform says it has from this source: by bundle id, by name only where either side has none.
    /// Apple devices each have their own (`com.apple.health.<uuid>`), so two watches never merge.
    static func received(_ ref: SourceRef, in list: [UserSource]?) -> DetectedSource.Received {
        guard let list, !list.isEmpty else { return .unknown }
        let name = SourceIdentity.folded(ref.name)
        let match = list.first { source in
            if let bundleID = ref.bundleID, let theirs = source.bundleId {
                return bundleID.caseInsensitiveCompare(theirs) == .orderedSame
            }
            return !name.isEmpty && SourceIdentity.folded(source.name) == name
        }
        guard let match else { return .notListed }
        return .kinds(Set(match.kinds), lastSeen: match.lastSeen)
    }

    /// Note B's facts: the catalog says this tracker doesn't share HRV, it writes heart rate and no HRV arrived (data
    /// beats the catalog). Never the iPhone: without a wearable it writes no HRV, which needs no note.
    static func noHRV(_ tracker: Tracker, signals: [TrackerSignal: Date]) -> DetectedSource.NoHRV? {
        guard tracker.id != "iphone", tracker.capabilities[.hrv] == .no,
              signals[.heartRate] != nil, signals[.hrv] == nil else { return nil }
        return DetectedSource.NoHRV(restingHR: signals[.restingHR] != nil, limit: hrvLimit(tracker))
    }

    /// The catalog's `limits` sentence about HRV (Garmin's first, Polar's second), in both languages.
    static func hrvLimit(_ tracker: Tracker) -> Localized<String>? {
        let en = tracker.limits.en, de = tracker.limits.de
        guard let i = en.firstIndex(where: { $0.localizedCaseInsensitiveContains("HRV") }) else { return nil }
        return Localized(en: en[i], de: i < de.count ? de[i] : en[i])
    }
}

/// One app or device that wrote to Apple Health in the window: a row of the Sources screen.
struct DetectedSource: Identifiable, Equatable, Sendable {
    /// Name, bundle id and device model, as HealthKit gave them.
    let ref: SourceRef
    /// `TrackerCatalog.displayName`: "Garmin Connect", "Tim's Apple Watch", else HealthKit's name.
    let displayName: String
    /// `TrackerCatalog.match`: the row's glyph comes from its tracker; nil for a source RYFT doesn't know.
    let trackerID: String?
    /// The newest record per signal in the window; `sleepStages` when the newest night has stages.
    let signals: [TrackerSignal: Date]
    let lastSeen: Date
    /// nil: nothing that covers the window yet (the row shows no number).
    let count: Count?
    /// What the platform says it has from this source.
    let received: Received
    /// Note B; nil when it doesn't apply.
    let noHRV: NoHRV?

    var id: String { SourceTally.key(ref) }

    enum Count: Equatable, Sendable {
        /// Records RYFT read from this source and the platform accepted, over the window's days (`SourceTally`).
        case phone(Int)
    }

    enum Received: Equatable, Sendable {
        /// No `GET /v1/me` yet, offline, demo, or a platform that lists no source at all.
        case unknown
        /// `User.sources` (the last 30 days).
        case kinds(Set<SourceKind>, lastSeen: Date)
        /// `User.sources` lists other sources, not this one.
        case notListed
    }

    /// Note B (decision 5.5): the wording depends on what this source wrote, not on the platform.
    struct NoHRV: Equatable, Sendable {
        /// It wrote resting heart rate in the window: "…recovery uses resting heart rate and sleep" may be said.
        let restingHR: Bool
        /// The catalog's `limits` sentence about HRV: the note's text without `restingHR`. nil: the catalog has none.
        let limit: Localized<String>?
    }

    /// The chips' fixed order (design.md §D4.2); the rest follow and collapse to "+n".
    static let chipOrder: [TrackerSignal] = [.heartRate, .hrv, .sleep, .steps, .workouts]

    /// Every signal this source wrote, in chip order: the five first, then resting heart rate, breathing rate and
    /// blood oxygen. Sleep stages are a detail of sleep, never a chip.
    var chips: [TrackerSignal] {
        let rest = TrackerSignal.allCases.filter { !Self.chipOrder.contains($0) && $0 != .sleepStages }
        return (Self.chipOrder + rest).filter { signals[$0] != nil }
    }

    /// Note C (decision 7, Q4): signals Apple Health has from this source in the window that the platform's 30 days
    /// lack, so RYFT has certainly not received them (as of its last answer). Empty without a platform answer.
    var notReceived: [TrackerSignal] { notReceived(given: received) }

    /// Note C against a platform answer of the caller's (the Sources screen re-reads `GET /v1/me` beside detection,
    /// so it matches the newest list rather than the one at read time). The same rule as `notReceived`.
    func notReceived(given received: Received) -> [TrackerSignal] {
        switch received {
        case .unknown: return []
        case .notListed: return chips
        case .kinds(let kinds, _): return chips.filter { $0.sourceKind.map { !kinds.contains($0) } ?? false }
        }
    }

    /// An Apple device that didn't say which (no device model): neither the watch nor the iPhone for certain.
    var isAnonymousApple: Bool {
        (ref.bundleID ?? "").lowercased().hasPrefix("com.apple.health.") && ref.deviceModel == nil
    }

    /// Note B's wording (lead correction to decision 5.5), nil when note B doesn't apply.
    var noHRVWording: NoHRV.Wording? { noHRV.map { Self.noHRVWording($0, signals: signals) } }

    /// Note B's wording, pure: "…recovery uses resting heart rate and sleep" only when this source wrote **both**
    /// resting heart rate and sleep in the window (what it wrote, not what the platform says Recovery used);
    /// otherwise the catalog's `limits` sentence about HRV; without one, the plain "doesn't share HRV".
    static func noHRVWording(_ note: NoHRV, signals: [TrackerSignal: Date]) -> NoHRV.Wording {
        if note.restingHR, signals[.restingHR] != nil, signals[.sleep] != nil { return .recoveryInputs }
        if let limit = note.limit { return .limit(limit) }
        return .plain
    }
}

extension DetectedSource.NoHRV {
    /// Which sentence note B says.
    enum Wording: Equatable, Sendable {
        /// "<name> doesn't share HRV with Apple Health; recovery uses resting heart rate and sleep."
        case recoveryInputs
        /// The catalog's `limits` sentence about HRV, in both languages.
        case limit(Localized<String>)
        /// "<name> doesn't share HRV with Apple Health."
        case plain
    }
}

extension TrackerSignal {
    /// The platform's word for it in `User.sources[].kinds` (`hr` covers resting heart rate); nil for sleep stages.
    var sourceKind: SourceKind? {
        switch self {
        case .heartRate, .restingHR: return .hr
        case .hrv: return .hrv
        case .sleep: return .sleep
        case .sleepStages: return nil
        case .respiratoryRate: return .resp
        case .spo2: return .spo2
        case .workouts: return .workout
        case .steps: return .steps
        }
    }
}

// MARK: - reading

extension HealthProbe {
    /// The Sources screen's read: Check sync's reads over the last 7 days, then `SourceDetection.build`, all on this
    /// actor, off the main actor. One `sources` signpost interval spans it (performance target: under 300 ms
    /// typical, 1 s p95 on a device). Only on the screen's appearance and pull to refresh, in the foreground.
    func sources(now: Date, tally: SourceTally?, received: [UserSource]?, catalog: TrackerCatalog,
                 calendar: Calendar = .current) async throws -> SourceDetection {
        let signposter = Signposts.sync
        let interval = signposter.beginInterval("sources", id: signposter.makeSignpostID())
        MainThread.assertOff("Source detection")
        do {
            let found = try await run(TrackerCheckRules.streams, since: now.addingTimeInterval(-SourceDetection.span))
            let detection = SourceDetection.build(samples: found.samples, visible: found.visible, tally: tally,
                                                  received: received, catalog: catalog, now: now, calendar: calendar)
            signposter.endInterval("sources", interval, "\(detection.sources.count) sources")
            return detection
        } catch {
            signposter.endInterval("sources", interval, "failed")
            throw error
        }
    }

    /// The one place that picks the store Check sync and Sources read (architecture.md §D4.3). Demo mode reads a
    /// scripted store, never this iPhone's Health: the `-RyftSyncCheck` scenario (Debug), else Garmin-like when Garmin
    /// is picked, else the Apple Watch one; with a scenario, its trackers replace `trackers`. Otherwise `env.health`.
    @MainActor
    static func store(env: AppEnvironment, trackers: [String]) -> (health: HealthStore, trackers: [String]) {
        guard env.isDemo else { return (env.health, trackers) }
        let requested = SyncCheckScenario.requested
        let scenario = requested ?? (trackers.contains("garmin") ? .garmin : .appleWatch)
        return (scenario.store(now: env.clock.now()), requested?.trackers ?? trackers)
    }
}

/// What the Sources screen and the wizard call: on the screen's appearance and on pull to refresh, in the foreground
/// only; never at launch, in the background or from a BG task. It never asks for Health access (the screen's Allow
/// access does). A result is never persisted.
@MainActor
struct SourceDetector {
    enum Outcome: Equatable, Sendable {
        case detected(SourceDetection)
        /// RYFT never asked for Health access: Allow access, no rows.
        case notAsked
        /// No Apple Health on this device.
        case unavailable
        /// The phone is locked (protected data): unlock, then pull to refresh.
        case locked
        case failed
    }

    let env: AppEnvironment
    let health: HealthStore
    /// The trackers picked in setup, resolved in the catalog (in demo with `-RyftSyncCheck`, the scenario's): what
    /// `silent(among:)` and `withoutHRV(among:)` take.
    let picked: [Tracker]

    /// `picked`: catalog ids (`TrackerSelectionStore.trackers`); unknown ids are dropped.
    init(env: AppEnvironment, picked ids: [String]) {
        let choice = HealthProbe.store(env: env, trackers: ids)
        self.init(env: env, health: choice.health, picked: choice.trackers)
    }

    /// Tests and previews: a store of their own.
    init(env: AppEnvironment, health: HealthStore, picked ids: [String]) {
        self.env = env
        self.health = health
        let catalog = env.trackerCatalog
        var seen = Set<String>()
        picked = ids.filter { seen.insert($0).inserted }.compactMap(catalog.tracker)
    }

    /// Reads Apple Health and builds the rows. `tally`: `SyncService.engineState`'s (nil until the sync counts);
    /// `received`: `AppState.user?.sources`, nil without a platform answer. Demo uses neither: its sources are
    /// scripted, and the demo account's list would name other devices.
    func detect(tally: SourceTally?, received: [UserSource]?) async -> Outcome {
        guard health.isAvailable else { return .unavailable }
        guard await health.accessStatus() != .notAsked else { return .notAsked }
        let demo = env.isDemo
        do {
            return .detected(try await HealthProbe(health: health)
                .sources(now: env.clock.now(), tally: demo ? nil : tally, received: demo ? nil : received,
                         catalog: env.trackerCatalog))
        } catch {
            return ProtectedData.isLocked(error) ? .locked : .failed
        }
    }

    /// The wizard's pre-selection (architecture.md §D4.6): catalog ids detected, or nil when nothing can be known
    /// without asking. Only once Health access was asked and not in demo; it never prompts. `[]`: nothing found.
    func trackerIDs() async -> [String]? {
        guard !env.isDemo, health.isAvailable, await health.accessStatus() == .asked else { return nil }
        guard case .detected(let detection) = await detect(tally: nil, received: nil) else { return nil }
        return detection.trackerIDs
    }
}
