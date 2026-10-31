import Foundation
import Observation
import OSLog

/// Profile → Devices & sync → Sources (design.md §D4): which apps and devices wrote to Apple Health in the last 7
/// days, what each sent, and what's missing. It reads Apple Health through `SourceDetector` on appearance and on
/// pull to refresh only, and re-reads `GET /v1/me` beside it so the "not received yet" note isn't stale. It computes
/// nothing about scores; it shows what Apple Health and the platform say.
@MainActor
@Observable
final class SourcesViewModel: Identifiable {
    /// The screen's state (design.md §D4.4).
    enum Screen: Equatable {
        /// The first read of Apple Health is in flight: outline rows, "Reading Apple Health…".
        case loading
        /// At least one source in 7 days.
        case sources
        /// Nothing in 7 days; also "may not read" (HealthKit can't tell denied from empty, so it says both).
        case nothing
        /// RYFT never asked for Apple Health: Allow access, no rows.
        case notAsked
        case unavailable
        /// The phone is locked: unlock, then pull to refresh.
        case locked
        case failed
    }

    /// One source's row.
    struct Row: Identifiable, Equatable {
        let id: String
        /// `TrackerCatalog.displayName`: "Garmin Connect", "Tim's Apple Watch", else HealthKit's name.
        let name: String
        /// The tracker's neutral glyph (`Tracker.symbol`); `ellipsis.circle` for a source RYFT doesn't know.
        let symbol: String
        /// A catalog tracker or one of Apple's own devices; otherwise "Not a tracker RYFT knows".
        let known: Bool
        /// "HR", "HRV", "Sleep", "Steps", "Workouts", then "+n" for the rest.
        let chips: [String]
        /// The signals in words, for VoiceOver ("Heart rate, sleep and steps").
        let spokenKinds: String
        /// "07:12", "Yesterday 22:10", "Thu 07:12".
        let lastSeen: String
        /// "5,312 samples"; nil until a count covers the window.
        let count: String?
        /// In the order C, B (A belongs to the dashed rows).
        let notes: [Note]

        /// One VoiceOver element (design.md §D4.7): "Garmin Connect. Heart rate, sleep and steps. 5,312 samples. Last
        /// data Thu 07:12." The notes follow as elements of their own.
        var spoken: String {
            [name, spokenKinds, count, String(localized: "Last data \(lastSeen)"),
             known ? nil : SourcesViewModel.unknownSource]
                .compactMap { $0 }.joined(separator: ". ")
        }
    }

    /// A note under a row (design.md §D4.3). Colour is never alone: every note has a glyph and words.
    struct Note: Identifiable, Equatable {
        enum Kind: String, Sendable {
            /// A: a tracker picked in setup wrote nothing in 7 days. Amber glyph.
            case silent
            /// C: Apple Health has a type the platform hasn't received. Neutral.
            case notReceived
            /// B: an expected absence, the tracker doesn't share HRV. Neutral `minus.circle` (lead decision 5.4).
            case noHRV
        }

        let kind: Kind
        let text: String
        var id: String { kind.rawValue }

        var glyph: String {
            switch kind {
            case .silent: return "exclamationmark.circle"
            case .notReceived: return "arrow.triangle.2.circlepath"
            case .noHRV: return "minus.circle"
            }
        }
    }

    /// A tracker picked in setup that wrote nothing in 7 days: a dashed row with note A.
    struct SilentRow: Identifiable, Equatable {
        /// The tracker's catalog id.
        let id: String
        let name: String
        let symbol: String
        let note: Note
        /// "Garmin Connect in the App Store" (T1's "Open Garmin Connect" replaces it once that ships); nil for an
        /// Apple device or a tracker without a store page.
        let storeTitle: String?
        let storeURL: URL?

        var spoken: String {
            [name, String(localized: "Picked in setup", comment: "Sources: VoiceOver for a tracker picked but not seen."),
             String(localized: "Nothing in the last 7 days", comment: "Sources: VoiceOver for a tracker picked but not seen.")]
                .joined(separator: ". ")
        }
    }

    private let state: AppState
    /// What the user wears: note A's trackers.
    let selection: TrackerSelectionStore

    /// The last read's answer; nil before the first one.
    private(set) var outcome: SourceDetector.Outcome?
    /// A read is in flight (the first one shows the loading rows; a pull keeps the last answer on screen).
    private(set) var isReading = false
    /// `GET /v1/me` beside the read: nil not asked yet, false failed (state 6: counts from Apple Health, no note C).
    private(set) var platformReachable: Bool?
    /// The trackers note A and B were decided over (in demo with `-RyftSyncCheck`, the scenario's).
    private(set) var picked: [Tracker] = []
    private(set) var readAt: Date?

    /// A second appearance this soon after a read shows that read (Devices & sync reads for its row, then Sources
    /// opens); a pull always reads.
    static let reuseFor: TimeInterval = 30

    private static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "sources")

    init(state: AppState, selection: TrackerSelectionStore) {
        self.state = state
        self.selection = selection
    }

    private var env: AppEnvironment { state.env }
    var isDemo: Bool { env.isDemo }

    // MARK: reading

    /// On appearance: a read unless one is in flight or just happened.
    func appeared() async {
        guard !isReading else { return }
        if let readAt, outcome != nil, env.clock.now().timeIntervalSince(readAt) < Self.reuseFor { return }
        await read(userInitiated: false)
    }

    /// Pull to refresh: Apple Health again, and `GET /v1/me` (the platform's newest list for note C).
    func refresh() async {
        await read(userInitiated: true)
    }

    /// "Allow access" (state 4): the same request as Devices & sync's Apple Health access, then a read.
    func requestAccess() async {
        try? await env.health.requestAuthorization()
        await read(userInitiated: true)
    }

    private func read(userInitiated: Bool) async {
        isReading = true
        defer { isReading = false }
        let detector = SourceDetector(env: env, picked: selection.trackers)
        async let platform = reloadUser(userInitiated: userInitiated)
        // The sync's tally (`SourceTally`) joins here once T2 has landed and SyncService keeps it: until then every
        // count is nil, as design.md §D4.2 allows. The platform's list isn't passed: note C is matched against the
        // newest `User.sources` when the rows are built (`platformSources`).
        let tally: SourceTally? = nil
        let result = await detector.detect(tally: tally, received: nil)
        platformReachable = await platform
        picked = detector.picked
        outcome = result
        readAt = env.clock.now()
    }

    /// Previews: an answer without reading; nil keeps the first read "in flight" (the loading rows).
    func stage(_ outcome: SourceDetector.Outcome?, platformReachable: Bool? = true) {
        self.outcome = outcome
        self.platformReachable = platformReachable
        isReading = outcome == nil
        readAt = env.clock.now()
    }

    /// `GET /v1/me`: on appearance only when the cached one is stale, on a pull always. False when it can't be
    /// reached: offline, or its last read failed (a read held back after a failure sends nothing and throws nothing,
    /// so the read record decides). Cancelled: what was known before.
    private func reloadUser(userInitiated: Bool) async -> Bool {
        guard env.isDemo || env.connectivity.isOnline else { return false }
        do {
            try await state.repository.refreshUser(mode: userInitiated ? .latest : .ifStale, userInitiated: userInitiated)
        } catch is CancellationError {
            return platformReachable ?? true
        } catch {
            // The error's type only: its text can carry a request URL.
            Self.log.notice("Sources: GET /v1/me failed (\(String(describing: type(of: error)), privacy: .public))")
            return false
        }
        return (env.reads.states[.me]?.consecutiveFailures ?? 0) == 0
    }

    // MARK: what the screen shows

    var screen: Screen {
        switch outcome {
        case nil: return .loading
        case .detected(let detection)?: return detection.sources.isEmpty ? .nothing : .sources
        case .notAsked?: return .notAsked
        case .unavailable?: return .unavailable
        case .locked?: return .locked
        case .failed?: return .failed
        }
    }

    var detection: SourceDetection? {
        if case .detected(let detection)? = outcome { return detection }
        return nil
    }

    /// The platform's list note C is matched against: never in demo (the demo account's list names other devices),
    /// never when `GET /v1/me` just failed (state 6).
    private var platformSources: [UserSource]? {
        guard !isDemo, platformReachable != false else { return nil }
        return state.user?.sources
    }

    var rows: [Row] {
        guard let detection else { return [] }
        let catalog = env.trackerCatalog
        let now = env.clock.now()
        let platform = platformSources
        return detection.sources.map { Self.row($0, catalog: catalog, platform: platform, now: now) }
    }

    /// Picked trackers with nothing in 7 days (note A), only once Apple Health was read.
    var silentRows: [SilentRow] {
        guard let detection else { return [] }
        return detection.silent(among: picked).map(Self.silentRow)
    }

    /// Devices & sync's row: "2 sources in the last 7 days", once read.
    var summary: String? {
        guard let detection else { return nil }
        let count = detection.sources.count
        return String(localized: "\(count) sources in the last 7 days",
                      comment: "Devices & sync: the Sources row's subtitle, sources Apple Health showed in 7 days.")
    }

    /// State 6: the platform couldn't be reached; the rows are Apple Health's alone.
    var isPlatformOffline: Bool { !isDemo && platformReachable == false }

    /// Check sync from the "nothing detected" state: only with trackers to check.
    var canCheckSync: Bool { !selection.trackers.isEmpty }
    var checkTrackers: [String] { selection.trackers }

    // MARK: building rows (pure)

    static func row(_ source: DetectedSource, catalog: TrackerCatalog, platform: [UserSource]?, now: Date) -> Row {
        let tracker = source.trackerID.flatMap(catalog.tracker)
        let apple = (source.ref.bundleID ?? "").lowercased().hasPrefix("com.apple.")
        let signals = source.chips
        var notes: [Note] = []
        let missing = source.notReceived(given: SourceDetection.received(source.ref, in: platform))
        if !missing.isEmpty { notes.append(notReceivedNote(missing, name: source.displayName)) }
        if let wording = source.noHRVWording { notes.append(noHRVNote(wording, name: source.displayName)) }
        return Row(id: source.id, name: source.displayName, symbol: tracker?.symbol ?? "ellipsis.circle",
                   known: tracker != nil || apple, chips: chips(signals),
                   spokenKinds: spokenKinds(signals), lastSeen: SyncLine.dataTime(source.lastSeen, now: now),
                   count: source.count.map(countText), notes: notes)
    }

    static func silentRow(_ tracker: Tracker) -> SilentRow {
        let apple = tracker.integration == .appleBuiltin
        // An Apple device by its own name ("Apple Watch", not its app "Watch"); a vendor's by its app.
        let app = apple ? tracker.title : tracker.appTitle
        let text: String
        var storeURL: URL?
        if apple {
            text = String(localized: "Nothing from \(app) in 7 days. Keep it near your iPhone, then pull to refresh.",
                          comment: "Sources, note A for an Apple device picked in setup that wrote nothing in 7 days.")
        } else {
            text = String(localized: "Nothing from \(app) in 7 days. Open \(app), then pull to refresh.",
                          comment: "Sources, note A: a tracker picked in setup wrote nothing to Apple Health in 7 days.")
            // T1's verb ("Open Garmin Connect", a compiled URL scheme) replaces the store page here once it ships.
            storeURL = tracker.appStoreURL
        }
        return SilentRow(id: tracker.id, name: tracker.title, symbol: tracker.symbol,
                         note: Note(kind: .silent, text: text),
                         storeTitle: storeURL.map { _ in String(localized: "\(app) in the App Store") }, storeURL: storeURL)
    }

    /// The chips' words in their fixed order (design.md §D4.2): the first five kinds, the rest as "+n".
    static func chips(_ signals: [TrackerSignal]) -> [String] {
        let shown = signals.filter(DetectedSource.chipOrder.contains)
        let rest = signals.count - shown.count
        return shown.map(chipWord) + (rest > 0 ? ["+\(rest)"] : [])
    }

    static func chipWord(_ signal: TrackerSignal) -> String {
        switch signal {
        case .heartRate: return String(localized: "sources.chip.heartRate", defaultValue: "HR",
                                       comment: "Sources: type chip, heart rate. Short (de: HF).")
        case .hrv: return String(localized: "sources.chip.hrv", defaultValue: "HRV", comment: "Sources: type chip, HRV.")
        case .sleep: return String(localized: "sources.chip.sleep", defaultValue: "Sleep", comment: "Sources: type chip, sleep.")
        case .steps: return String(localized: "sources.chip.steps", defaultValue: "Steps", comment: "Sources: type chip, steps.")
        case .workouts: return String(localized: "sources.chip.workouts", defaultValue: "Workouts",
                                      comment: "Sources: type chip, workouts (de: Training).")
        default: return signal.title
        }
    }

    /// "Heart rate, sleep and steps", full words for VoiceOver.
    static func spokenKinds(_ signals: [TrackerSignal]) -> String {
        let text = signals.map(\.inline).formatted(.list(type: .and))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func countText(_ count: DetectedSource.Count) -> String {
        switch count {
        case .phone(let n):
            return String(localized: "\(n) samples", comment: "Sources: records from one source over the last 7 days.")
        }
    }

    /// Note C: "Apple Health has HRV from Oura; RYFT hasn't received it yet. Pull to refresh."
    static func notReceivedNote(_ missing: [TrackerSignal], name: String) -> Note {
        let types = missing.map(\.inline).formatted(.list(type: .and))
        let text = missing.count == 1
            ? String(localized: "Apple Health has \(types) from \(name); RYFT hasn't received it yet. Pull to refresh.",
                     comment: "Sources, note C: one data type Apple Health has from a source that the platform lacks.")
            : String(localized: "Apple Health has \(types) from \(name); RYFT hasn't received them yet. Pull to refresh.",
                     comment: "Sources, note C: several data types Apple Health has from a source that the platform lacks.")
        return Note(kind: .notReceived, text: text)
    }

    /// Note B in the wording `DetectedSource.noHRVWording` picks.
    static func noHRVNote(_ wording: DetectedSource.NoHRV.Wording, name: String) -> Note {
        let text: String
        switch wording {
        case .recoveryInputs:
            text = String(localized: "\(name) doesn't share HRV with Apple Health; recovery uses resting heart rate and sleep.",
                          comment: "Sources, note B: the source wrote resting heart rate and sleep in 7 days but no HRV.")
        case .limit(let limit):
            text = limit.current
        case .plain:
            text = String(localized: "\(name) doesn't share HRV with Apple Health.",
                          comment: "Sources, note B without a catalog sentence: the source writes heart rate, no HRV.")
        }
        return Note(kind: .noHRV, text: text)
    }

    nonisolated static var unknownSource: String { String(localized: "Not a tracker RYFT knows. It still counts.") }

    /// The setup step's row to this screen.
    static var setupLinkTitle: String {
        String(localized: "See what Apple Health has sent",
               comment: "Tracker setup after Apple Health: opens the Sources screen.")
    }
}
