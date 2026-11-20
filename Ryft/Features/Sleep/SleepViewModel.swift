import Foundation
import Observation

enum SleepMode: String, CaseIterable, Identifiable {
    case day, week, month, plan
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return String(localized: "Day")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .plan: return String(localized: "Bedtime")
        }
    }

    var rangeKind: SleepRangeKind? {
        switch self {
        case .day, .plan: return nil
        case .week: return .week
        case .month: return .month
        }
    }
}

@MainActor
@Observable
final class SleepViewModel {
    private let state: AppState

    /// `-RyftSleepMode week` preselects a mode (screenshots).
    var mode: SleepMode = UserDefaults.standard.string(forKey: "RyftSleepMode")
        .flatMap(SleepMode.init(rawValue:)) ?? .day
    /// The night shown in Day mode, identified by the morning it ended.
    private(set) var date: Date
    private(set) var isLoading = false
    /// Why the night couldn't load, with nothing cached: the app's calm sentence and the Details (VN1).
    private(set) var failure: SleepLoadFailure?
    /// The failure's sentence, which the board shows in the hypnogram's place.
    var error: String? { failure?.message }
    /// Week or Month whose last read failed while a copy was cached: the copy shows "As of" its day until a read succeeds.
    private(set) var staleRanges: Set<SleepRangeKind> = []
    /// Bumped by every load: a load that another one replaced (a mode switch, a step) writes nothing when it ends.
    @ObservationIgnored private var loadGeneration = 0

    /// Sleep → Planner, behind `sleep.planner`.
    let planner: SleepPlannerViewModel

    init(state: AppState) {
        self.state = state
        date = Calendar.current.startOfDay(for: state.env.clock.now())
        planner = SleepPlannerViewModel(state: state)
    }

    /// The picker's modes: the planner only with `sleep.planner`.
    var modes: [SleepMode] {
        state.env.flags.isOn(.sleepPlanner) ? SleepMode.allCases : SleepMode.allCases.filter { $0 != .plan }
    }

    /// A deep link to the planner (or the picker).
    func showPlanner() {
        guard modes.contains(.plan) else { return }
        mode = .plan
    }

    private var today: Date { Calendar.current.startOfDay(for: state.env.clock.now()) }

    var isToday: Bool { Calendar.current.isDate(date, inSameDayAs: today) }

    /// The night as cached (SwiftData); `load()` revalidates it.
    var detail: DayDetail? { state.cachedDayDetail(for: date) }
    var range: SleepRange? { mode.rangeKind.flatMap(state.cachedSleepRange) }
    var sleep: SleepDetail? { detail?.sleep }
    var score: DailyScore? { detail?.score }
    /// The night's scoring state beside its title (`DayMarker`); the cached 90 days when the
    /// detail isn't loaded.
    var marker: DayMarker.Kind? { DayMarker.kind(for: score ?? state.score(for: date)) }
    /// The night's day as the platform last sent it: the loaded detail's, else the cached 90 days'.
    private var row: DailyScore? { score ?? state.score(for: date) }
    /// The day's scoring state. Today's is Today's and the widget's (`ScoringWord.state`, architecture §D3b's one owner):
    /// this phone's word since its last write or push, then `GET /v1/me/sync`'s when it's about today, then the row. So
    /// right after the night uploads Sleep says what Today says, though the row still waits for sleep (S1). Another
    /// day's is its row's. Read in the board, so a new word or status redraws it (both are observed).
    var scoringState: ScoringState? {
        guard isToday else { return row?.scoringState }
        let key = DayFormat.string(from: date)
        return ScoringWord.state(day: key, word: state.repository.scoringLedger()[key], status: state.syncStatus?.today,
                                 row: row)
    }
    /// What the platform says about the night (`scoringState`, three-way): what the board says without one.
    var nightScoring: SleepBoard.NightScoring {
        SleepBoard.NightScoring(scoringState, isToday: isToday, hasNight: sleep != nil,
                                dayIsScored: row.map(TodayStates.isScored))
    }
    var hasNoHealthData: Bool { state.hasNoHealthData }

    /// The oldest night Previous reaches (design.md §P4-4 S2): the first cached day with a night, else the 90 days the
    /// history covers.
    var oldestNight: Date { SleepNights.oldest(in: state.history, today: today, reach: AppState.historyDays) }

    /// "Last night · Sun, Nov 15", "Yesterday · Sat, Nov 14", "Wed, Nov 11"; "Last 7 nights" / "Last 30 nights" /
    /// "Tonight".
    var subtitle: String { SleepHeaderContent.subtitle(mode: mode, night: date, today: today) }

    var canStepBack: Bool { mode == .day && date > oldestNight }
    var canStepForward: Bool { mode == .day && date < today }

    /// The header row: the night as shown and as spoken, its marker, the night buttons.
    var header: SleepHeaderContent {
        SleepHeaderContent(mode: mode, night: date, today: today, marker: mode == .day ? marker : nil,
                           canStepBack: canStepBack, canStepForward: canStepForward)
    }

    /// Day mode's board for the night shown (design.md §P4-2 rows 3–7, §P4-5).
    var board: SleepBoard {
        let shown = score ?? state.score(for: date)
        let week = (1..<SleepBoard.weekNights).reversed().map { back in
            state.score(for: DayFormat.shift(date, days: -back))?.sleepConsistency
        } + [shown?.sleepConsistency]
        return SleepBoard(sleep: sleep, score: score,
                          previousDebt: state.score(for: DayFormat.shift(date, days: -1))?.sleepDebtMin,
                          weekConsistency: week, scoring: nightScoring, isLoading: isLoading, error: error,
                          rawNight: rawNight)
    }

    /// Apple Health's last night (`AppState.lastNight`, what Today shows) when it is the night shown: it ended this
    /// morning, and the night shown is last night. The board shows it only while the night is being scored.
    var rawNight: RawNight? {
        guard isToday, let night = state.lastNight, Calendar.current.isDate(night.wake, inSameDayAs: date) else { return nil }
        return night
    }

    /// The hero numeral's style (Profile → Display → Hero numbers, design.md §P4-6).
    var numeralStyle: DotNumeral.Style { state.env.settings.heroNumerals.style }

    /// Week or Month as the screen shows it (design.md §P5-7.2); Week's while another mode is on. "As of" its day offline,
    /// after a failed read, or when the range doesn't end today.
    var rangeBoard: SleepRangeBoard { rangeBoard(locale: .autoupdatingCurrent) }

    func rangeBoard(locale: Locale) -> SleepRangeBoard {
        let kind = mode.rangeKind ?? .week
        return SleepRangeBoard(range: range, kind: kind, isLoading: isLoading, failure: failure,
                               isStale: !isOnline || staleRanges.contains(kind), today: state.env.clock.now(), locale: locale)
    }

    /// Bedtime as the screen shows it (design.md §P5-7.3): the numbers from the planner (`GET /v1/sleep/plan` for the wake
    /// time asked: Bedtime & wake's next one until the picker moves), the goal, the alarm and the summary from Bedtime & wake.
    func bedtimeBoard(_ bedtime: BedtimePlanner, locale: Locale = .autoupdatingCurrent) -> SleepBedtimeBoard {
        SleepBedtimeBoard(plan: planner.plan, wake: planner.wake, goal: bedtime.schedule?.goal, isLoading: planner.isLoading,
                          failure: planner.failure, isOnline: isOnline, asOf: planner.asOf, alarmProblem: bedtime.alarmProblem,
                          summary: BedtimePlanner.summary(bedtime.schedule, locale: locale), locale: locale)
    }

    /// Week, Month and Bedtime show Today's calm card under the picker while reads fail or the data is old (§P5-7 states);
    /// Day has its own failure in the hypnogram's place.
    var refreshIssue: RefreshIssue? { mode == .day ? nil : state.refreshIssue }
    var isDemo: Bool { state.isDemo }
    var isOnline: Bool { state.isDemo || state.env.connectivity.isOnline }

    /// The refresh issue's Try again: a forced refresh, then the mode again.
    func retryRefresh() async {
        await state.refresh(force: true)
        await load()
    }

    /// What VoiceOver hears after a step (design.md §P4-8): the night as the title says it ("…, not scored yet" while
    /// pending), then its duration or what is known of it.
    var stepAnnouncement: String {
        let board = board
        if case .failed(let message) = board.look { return "\(header.spokenValue). \(message)" }
        return "\(header.spokenValue). \(board.numeralLabel ?? board.spokenCaption ?? board.caption)"
    }

    /// A signed-out failure's "Sign in": Today's (`AppState.signInAgain`).
    func signIn() async {
        await state.signInAgain()
    }

    /// A deep link: Day mode on that night, clamped to the nights there are (never past today).
    func show(night: Date) {
        mode = .day
        date = SleepNights.clamp(Calendar.current.startOfDay(for: night), oldest: oldestNight, today: today)
    }

    /// The previous or next night, clamped to the oldest night and today; nothing at either end.
    func step(by days: Int) async {
        let next = SleepNights.clamp(DayFormat.shift(date, days: days), oldest: oldestNight, today: today)
        guard next != date else { return }
        date = next
        await load()
    }

    /// Revalidates what the mode shows (no request when cached and fresh). Only the newest load writes when it ends: one
    /// for another mode or night that answers late (or fails) leaves the screen to the load that replaced it.
    /// - Parameter bedtime: Bedtime & wake, which Bedtime's wake time follows (`SleepPlannerViewModel.follow`).
    func load(bedtime: BedtimePlanner? = nil) async {
        loadGeneration += 1
        let generation = loadGeneration
        failure = nil
        isLoading = false
        guard state.hasDataSource else { return }
        if mode == .plan {
            if let bedtime { planner.follow(bedtime.schedule, tonight: bedtime.plan, tonightAsOf: bedtime.asOf) }
            await planner.load()
            return
        }
        planner.resumeFollowing()
        if let kind = mode.rangeKind {
            isLoading = range == nil
            defer { if generation == loadGeneration { isLoading = false } }
            do {
                try await state.repository.refreshSleepRange(kind)
                // A read that was held back (or not needed) leaves an earlier failure standing.
                if generation == loadGeneration, (state.env.reads.states[.sleepRange]?.consecutiveFailures ?? 0) == 0 {
                    staleRanges.remove(kind)
                }
            } catch where error.isCancellation {
                return
            } catch {
                guard generation == loadGeneration, mode.rangeKind == kind else { return }
                // Week and Month say why as Day does (§P5-7 states) when nothing is cached; a cached copy stays, "As of".
                if range == nil {
                    failure = SleepLoadFailure(error, isOnline: isOnline, isDemo: state.isDemo, at: state.env.clock.now())
                } else {
                    staleRanges.insert(kind)
                }
            }
            return
        }
        isLoading = detail == nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            _ = try await state.dayDetail(for: date)
        } catch where error.isCancellation {
            // `.task(id:)` restarted (another day, new data): the next load says what's true.
            return
        } catch {
            guard generation == loadGeneration, mode == .day else { return }
            if detail == nil {
                failure = SleepLoadFailure(error, isOnline: isOnline, isDemo: state.isDemo, at: state.env.clock.now())
            }
        }
    }
}

/// What Sleep → Day says when a night couldn't load and nothing is cached (VN1): the sentences Today's refresh issue
/// uses (`RefreshIssue.Reason.message`), or "No connection" offline, never the system's error text; the status and the
/// request ID behind Details, for support.
struct SleepLoadFailure: Equatable {
    let message: String
    let systemImage: String
    /// "HTTP 503 · Request ID 01a1…"; nil without a response.
    let details: String?
    /// The button, as on Today's card (`RefreshIssue.Reason.action(isDemo:)`): Sign in when signed out (none with demo
    /// data on), none for an outdated app, else Try again.
    let action: RefreshIssue.Reason.Action

    init(_ error: Error, isOnline: Bool, isDemo: Bool = false, at date: Date) {
        if !isOnline || Self.lostConnection(error) {
            self.init(message: String(localized: "No connection. Check your internet and try again."),
                      systemImage: "wifi.exclamationmark", details: error.diagnosticDetails, action: .retry)
        } else {
            let reason = RefreshIssue.reason(for: ResourceError(error, kind: FailureKind.of(error), attempts: 1, at: date))
            self.init(reason: reason, details: error.diagnosticDetails, isDemo: isDemo)
        }
    }

    /// A reason's sentence, symbol and button (previews and tests: nothing produces `appTooOld` yet).
    init(reason: RefreshIssue.Reason, details: String? = nil, isDemo: Bool = false) {
        self.init(message: reason.message, systemImage: reason.systemImage, details: details,
                  action: reason.action(isDemo: isDemo))
    }

    private init(message: String, systemImage: String, details: String?, action: RefreshIssue.Reason.Action) {
        self.message = message
        self.systemImage = systemImage
        self.details = details
        self.action = action
    }

    /// The phone has no connection: URLSession says so, whatever the connectivity monitor last heard (Train's pages call
    /// it offline too).
    static func lostConnection(_ error: Error) -> Bool {
        var url = error as? URLError
        if case .transport(let inner)? = error as? APIError { url = inner as? URLError }
        guard let code = url?.code else { return false }
        return code == .notConnectedToInternet || code == .networkConnectionLost || code == .dataNotAllowed
    }
}

/// The nights Sleep → Day can show (design.md §P4-4 S2, §P4-11 test 27): from the oldest night to today.
enum SleepNights {
    /// The first day of `history` (oldest first) with a night (`sleepActualMin`); without one, `today − (reach − 1)`.
    static func oldest(in history: [DailyScore], today: Date, reach: Int) -> Date {
        guard let first = history.first(where: { $0.sleepActualMin != nil }), let day = DayFormat.date(from: first.day) else {
            return DayFormat.shift(today, days: -(reach - 1))
        }
        return min(day, today)
    }

    /// `night` within `oldest…today`.
    static func clamp(_ night: Date, oldest: Date, today: Date) -> Date {
        min(max(night, min(oldest, today)), today)
    }
}

/// Sleep's header (design.md §P4-2 row 1, §P4-8): the night as shown and as spoken, its scoring marker, and the night
/// buttons. Pure.
struct SleepHeaderContent: Equatable {
    /// "Last night · Sun, Nov 15"; "Last 7 nights" in Week mode.
    let subtitle: String
    /// "Last night, Sunday, November 15": the title's VoiceOver value.
    let spokenSubtitle: String
    let marker: DayMarker.Kind?
    /// Day mode: Previous and Next are there. Week, Month and Bedtime keep their places, hidden and disabled.
    let showsNightButtons: Bool
    let canStepBack: Bool
    let canStepForward: Bool

    init(mode: SleepMode, night: Date, today: Date, marker: DayMarker.Kind?, canStepBack: Bool, canStepForward: Bool,
         locale: Locale = .autoupdatingCurrent, calendar: Calendar = .current) {
        subtitle = Self.subtitle(mode: mode, night: night, today: today, locale: locale, calendar: calendar)
        spokenSubtitle = Self.spokenSubtitle(mode: mode, night: night, today: today, locale: locale, calendar: calendar)
        self.marker = marker
        showsNightButtons = mode == .day
        self.canStepBack = canStepBack
        self.canStepForward = canStepForward
    }

    /// The title's VoiceOver value: the night, then "not scored yet" while it is pending.
    var spokenValue: String { [spokenSubtitle, marker?.spoken].compactMap(\.self).joined(separator: ", ") }

    /// Day mode: "Last night · Sun, Nov 15" (the night ending today), "Yesterday · Sat, Nov 14", "Wed, Nov 11". The
    /// others: "Last 7 nights", "Last 30 nights", "Tonight".
    static func subtitle(mode: SleepMode, night: Date, today: Date, locale: Locale = .autoupdatingCurrent,
                         calendar: Calendar = .current) -> String {
        guard mode == .day else { return rangeTitle(mode) }
        let date = night.formatted(dateStyle(locale: locale, calendar: calendar).weekday(.abbreviated).month(.abbreviated).day())
        switch Self.age(of: night, today: today, calendar: calendar) {
        case 0: return String(localized: "Last night · \(date)",
                              comment: "Sleep's header under \"Sleep\": the night that ended this morning, then its date (\"Sun, Nov 15\").")
        case 1: return String(localized: "Yesterday · \(date)",
                              comment: "Sleep's header under \"Sleep\": the night that ended yesterday morning, then its date (\"Sat, Nov 14\").")
        default: return date
        }
    }

    /// `subtitle` for VoiceOver, the date in full: "Last night, Sunday, November 15".
    static func spokenSubtitle(mode: SleepMode, night: Date, today: Date, locale: Locale = .autoupdatingCurrent,
                               calendar: Calendar = .current) -> String {
        guard mode == .day else { return rangeTitle(mode) }
        let date = night.formatted(dateStyle(locale: locale, calendar: calendar).weekday(.wide).month(.wide).day())
        switch Self.age(of: night, today: today, calendar: calendar) {
        case 0: return String(localized: "Last night, \(date)",
                              comment: "VoiceOver: Sleep's title value for the night that ended this morning, the date in full (\"Sunday, November 15\").")
        case 1: return String(localized: "Yesterday, \(date)",
                              comment: "VoiceOver: Sleep's title value for the night that ended yesterday, the date in full (\"Saturday, November 14\").")
        default: return date
        }
    }

    private static func rangeTitle(_ mode: SleepMode) -> String {
        switch mode {
        case .day: return ""
        case .week: return String(localized: "Last 7 nights")
        case .month: return String(localized: "Last 30 nights")
        case .plan: return String(localized: "Tonight")
        }
    }

    /// Days from `night` to `today`: 0 for the night that ended this morning.
    private static func age(of night: Date, today: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: night), to: calendar.startOfDay(for: today)).day ?? 0
    }

    private static func dateStyle(locale: Locale, calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}

/// Sleep → Day in Nocturne (design.md §P4-2 rows 3–7, §P4-5): the numeral, its caption, the ruler, the hypnogram tile and
/// the four tiles of one night, every value formatted and every look decided. Pure: tests build it without a view.
struct SleepBoard: Equatable {
    enum Look: Equatable {
        /// A night to show: scored, pending, or with parts missing.
        case night
        /// Nothing cached and the load in flight: the unlit numeral, the ruler's ticks, outline tiles. No spinner.
        case loading
        /// The load failed with nothing cached: as loading, and the message with Try again in the hypnogram's place.
        case failed(String)
        /// A scored day without a night: "No sleep recorded for this night."
        case noSleep
        /// The night is being scored (`scoring_state: pending`) and the platform has no sleep for it yet (`sleep: null`):
        /// the numeral and the ruler from Apple Health's raw night when there is one, labelled unscored; the outline
        /// hypnogram and tiles. Never "No sleep recorded".
        case pending
        /// No night has reached RYFT (`waiting_for_sleep`, or today `stale`: a watch charging overnight): "Last night
        /// hasn't reached RYFT yet.", as Today says it, with the outline and no raw night (R2-F1).
        case awaitingNight
    }

    /// What the platform says about the night shown, from its day's `scoring_state` (`DayMarker` keeps the dot, which
    /// doesn't tell these apart). Today's reads as Today's gauge does (`TodayPresentation.decide`).
    enum NightScoring: Equatable, Sendable {
        /// Scored: the day's values are the night's.
        case scored
        /// `pending`: the night is in and being scored.
        case scoring
        /// `waiting_for_sleep`, or `stale` for today without a night: nothing of last night has arrived.
        case awaitingNight

        /// - `stale` (no new data for over 20 h) is the platform's word for today only (API.md): without a night, last
        ///   night hasn't arrived; with one, the day's score stands, as on another day.
        /// - `scored` while today's row isn't, or isn't here (`dayIsScored`, `TodayStates.isScored`): a push's or the
        ///   status's word before the row, which Today reads as being scored.
        /// - No word (`nil`: a value this app doesn't know, which decoding drops) is never read as scored on its own
        ///   (N1): a scored day is; today, unscored or without a row, waits for its night, as on Today; another day's
        ///   unscored row is being scored, the only other word the platform has for a past day. A past day without a
        ///   row (`dayIsScored` nil) has no night: as before.
        init(_ state: ScoringState?, isToday: Bool, hasNight: Bool, dayIsScored: Bool?) {
            switch state {
            case .pending: self = .scoring
            case .waitingForSleep: self = .awaitingNight
            case .stale: self = isToday && !hasNight ? .awaitingNight : .scored
            case .scored: self = isToday && dayIsScored != true ? .scoring : .scored
            case nil:
                switch dayIsScored {
                case true?: self = .scored
                case false?: self = isToday ? .awaitingNight : .scoring
                case nil: self = isToday ? .awaitingNight : .scored
                }
            }
        }
    }

    /// The consistency dots: this many nights, the last the night shown.
    static let weekNights = 7

    let look: Look
    /// "7:48"; `nil` draws the unlit "0:00".
    let clock: String?
    /// The numeral's VoiceOver label ("7 hours 48 minutes asleep", "Loading this night"); `nil` hides it, the caption
    /// says it.
    let numeralLabel: String?
    /// "Asleep · 94 % of your need", "Asleep", "Loading this night", "No sleep recorded for this night.", "From Apple
    /// Health · not scored yet", "Your night is being scored."
    let caption: String
    /// The caption's VoiceOver text ("94 percent of your need"); `nil` hides it where the numeral says it.
    let spokenCaption: String?
    let ruler: SleepRuler
    /// The hypnogram tile; `nil` outside `.night` (an outline slot, or the error's message).
    let hypnogram: SleepHypnogramContent?
    /// Consistency, Sleep debt, Efficiency, Restorative.
    let tiles: [SleepTile]

    /// Loading, a failed load and a night not scored yet without the platform's sleep draw the tiles as outlines (§P4-5).
    var isOutline: Bool {
        switch look {
        case .loading, .failed, .pending, .awaitingNight: return true
        case .night, .noSleep: return false
        }
    }

    /// - Parameters:
    ///   - previousDebt: the night before's `sleepDebtMin`, for the debt's change.
    ///   - weekConsistency: `sleepConsistency` of the last seven nights, oldest first, the last the night shown.
    ///   - scoring: what the platform says about the night; while it isn't scored, what needs a score shows "–".
    ///   - rawNight: last night as Apple Health has it (`AppState.lastNight`), when it is the night shown: a night being
    ///     scored that the platform has no sleep for yet shows its time asleep, labelled unscored (§P4-5 "Pending
    ///     score"). Not while no night has reached RYFT: Today hides it then too.
    init(sleep: SleepDetail?, score: DailyScore?, previousDebt: Int? = nil, weekConsistency: [Int?] = [],
         scoring: NightScoring = .scored, isLoading: Bool = false, error: String? = nil, rawNight: RawNight? = nil,
         locale: Locale = .autoupdatingCurrent) {
        let unscored = scoring != .scored
        let scored = unscored ? nil : score
        let need = scored?.sleepNeedMin ?? sleep?.need?.total
        guard let sleep else {
            let night: Look = switch scoring {
            case .scored: .noSleep
            case .scoring: .pending
            case .awaitingNight: .awaitingNight
            }
            let empty: Look = isLoading ? .loading : error.map(Look.failed) ?? night
            look = empty
            let raw = empty == .pending ? rawNight : nil
            clock = raw.map { Fmt.clock(minutes: $0.asleepMin) }
            switch empty {
            case .loading:
                let loading = String(localized: "Loading this night",
                                     comment: "Sleep → Day while a night that isn't cached loads: under the unlit numeral, and for VoiceOver.")
                numeralLabel = loading
                caption = loading
                spokenCaption = nil
            case .failed:
                // The message in the hypnogram's place says what happened; the numeral and caption stay quiet: no
                // "Asleep" under an unlit 0:00 (CR8). The caption keeps its line, empty.
                numeralLabel = nil
                caption = ""
                spokenCaption = nil
            case .pending:
                if let raw {
                    // Apple Health's total before the platform has scored it: said to be unscored (as Today's card).
                    numeralLabel = String(localized: "\(Fmt.spokenDuration(minutes: raw.asleepMin, locale: locale)) asleep")
                    caption = String(localized: "From Apple Health · not scored yet")
                    spokenCaption = String(localized: "Last night, from Apple Health, not scored yet")
                } else {
                    let scoring = String(localized: "Your night is being scored.")
                    numeralLabel = nil
                    caption = scoring
                    spokenCaption = scoring
                }
            case .awaitingNight:
                // Today's words for the same night (`TodayContent.sentence`): nothing claims it is being scored.
                let waiting = String(localized: "Last night hasn't reached RYFT yet.")
                numeralLabel = nil
                caption = waiting
                spokenCaption = waiting
            case .night, .noSleep:
                let none = String(localized: "No sleep recorded for this night.")
                numeralLabel = nil
                caption = none
                spokenCaption = none
            }
            ruler = SleepRuler(totalMin: raw?.asleepMin, needMin: need, locale: locale)
            hypnogram = nil
            tiles = SleepTile.placeholders(locale: locale)
            return
        }
        look = .night
        clock = sleep.totalMin.map { Fmt.clock(minutes: $0) }
        numeralLabel = sleep.totalMin.map {
            String(localized: "\(Fmt.spokenDuration(minutes: $0, locale: locale)) asleep")
        }
        if let performance = scored?.sleepPerformance {
            caption = String(localized: "Asleep · \(performance)\u{00A0}% of your need",
                             comment: "Under Sleep's numeral: the night's time asleep as a share of its sleep need (\"Asleep · 94 % of your need\").")
            spokenCaption = String(localized: "\(performance) percent of your need",
                                   comment: "VoiceOver: the caption under Sleep's numeral (\"94 percent of your need\").")
        } else {
            caption = String(localized: "Asleep")
            spokenCaption = nil
        }
        ruler = SleepRuler(totalMin: sleep.totalMin, needMin: need, locale: locale)
        hypnogram = SleepHypnogramContent(sleep: sleep, locale: locale)
        var week = weekConsistency
        if !week.isEmpty { week[week.count - 1] = scored?.sleepConsistency }
        tiles = [SleepTile.consistency(scored?.sleepConsistency, week: week, locale: locale),
                 SleepTile.debt(scored?.sleepDebtMin, before: unscored ? nil : previousDebt, locale: locale),
                 SleepTile.efficiency(sleep.efficiencyPercent, locale: locale),
                 SleepTile.restorative(sleep, locale: locale)]
    }
}

/// Sleep's ruler (design.md §P4-2 row 5, §P4-11 test 28): 0 to 10 hours, the needle at the time asleep, the need zone
/// over the last 10 % below the need (D4-6, L24), labels "0 h · need 8:18 · 10 h".
struct SleepRuler: Equatable {
    static let range: ClosedRange<Double> = 0...10
    /// The zone starts at this share of the need: the night counts as enough from there (L24).
    static let zoneShare = 0.9

    /// Hours asleep; `nil` draws no needle.
    let value: Double?
    let zone: ClosedRange<Double>?
    let labels: [String]
    let spokenValue: String

    /// - Parameter unknown: what VoiceOver says with neither a time asleep nor a need (Bedtime's own sentence); Day's
    ///   "No time asleep yet, …" by default.
    init(totalMin: Int?, needMin: Int?, unknown: String? = nil, locale: Locale = .autoupdatingCurrent) {
        let need = needMin.flatMap { $0 > 0 ? $0 : nil }
        value = totalMin.map { Double($0) / 60 }
        zone = need.flatMap { RulerScale.zone(lo: Self.zoneShare * Double($0) / 60, hi: Double($0) / 60) }
        let low = String(localized: "0 h", comment: "Sleep's duration ruler: the scale's start, zero hours.")
        let high = String(localized: "10 h", comment: "Sleep's duration ruler: the scale's end, ten hours.")
        if let need {
            labels = [low, String(localized: "need \(Fmt.clock(minutes: need))",
                                  comment: "Sleep's duration ruler, the middle label: the night's sleep need as hours:minutes (\"need 8:18\")."),
                      high]
        } else {
            labels = [low, high]
        }
        let spokenNeed = need.map { Fmt.spokenDuration(minutes: $0, locale: locale) }
        switch (totalMin.map { Fmt.spokenDuration(minutes: $0, locale: locale) }, spokenNeed) {
        case let (asleep?, need?):
            spokenValue = String(localized: "\(asleep), on a scale from 0 to 10 hours. Your need is \(need).",
                                 comment: "VoiceOver on Sleep's duration ruler: the time asleep, then the night's sleep need (both \"7 hours 48 minutes\").")
        case let (asleep?, nil):
            spokenValue = String(localized: "\(asleep), on a scale from 0 to 10 hours.",
                                 comment: "VoiceOver on Sleep's duration ruler without a sleep need: the time asleep (\"7 hours 48 minutes\").")
        case let (nil, need?):
            spokenValue = String(localized: "No time asleep yet, on a scale from 0 to 10 hours. Your need is \(need).",
                                 comment: "VoiceOver on Sleep's duration ruler before the night is known, with the sleep need (\"8 hours 18 minutes\").")
        case (nil, nil):
            spokenValue = unknown ?? String(localized: "No time asleep yet, on a scale from 0 to 10 hours.",
                                 comment: "VoiceOver on Sleep's duration ruler before the night is known, without a sleep need.")
        }
    }
}

/// What the cards under Sleep → Day's board show about one night (computed once, testable without a view): the details
/// card and the need sheet.
struct SleepNightSummary: Equatable {
    /// "91 · Good"; "–" without a quality score.
    let quality: String
    /// "Good"; "–" without one.
    let qualityLabel: String
    let qualityFraction: Double?
    let bedtime: String
    let wake: String
    let timeInBed: String
    let need: String
    let actual: String
    /// "87% of need".
    let actualOfNeed: String?
    /// "Nap · 35m" when there was one that day.
    let nap: String?
    let needBreakdown: SleepNeedBreakdown?

    init(sleep: SleepDetail, score: DailyScore?) {
        let need = score?.sleepNeedMin
        let actual = score?.sleepActualMin ?? sleep.totalMin
        let label = sleep.resolvedQualityLabel ?? Fmt.placeholder
        qualityLabel = label
        quality = sleep.quality.map { "\($0) · \(label)" } ?? Fmt.placeholder
        qualityFraction = sleep.quality.map { Double($0) / 100 }
        bedtime = Fmt.time(sleep.start)
        wake = Fmt.time(sleep.end)
        timeInBed = Fmt.duration(minutes: sleep.timeInBedMin)
        self.need = Fmt.duration(minutes: need)
        self.actual = Fmt.duration(minutes: actual)
        actualOfNeed = need.flatMap { n in actual.map { a in
            String(localized: "\(Int((Double(a) / Double(max(n, 1)) * 100).rounded()))% of need")
        } }
        nap = score?.napMin.flatMap { $0 > 0 ? String(localized: "Nap · \(Fmt.duration(minutes: $0))") : nil }
        needBreakdown = sleep.needBreakdown(score: score).map(SleepNeedBreakdown.init)
    }
}

/// Week / Month: each night's stages, the averages and the bedtime consistency (`SleepRangeBoard` lays them out).
struct SleepRangeSummary {
    /// One stage of one night: Deep, Light and REM bottom to top, or the night's total as "Asleep" without stages.
    struct Bar: Identifiable, Equatable {
        let day: String
        let date: Date
        /// `nil`: a night without stages ("Asleep").
        let stage: SleepStageKind?
        let hours: Double
        var id: String { "\(day)-\(stage?.rawValue ?? "asleep")" }
    }

    /// How regular bedtimes were: < 30 min steady, < 60 fair, else irregular.
    enum Regularity: Equatable { case steady, fair, irregular, unknown }

    static let asleep = String(localized: "Asleep")
    static let stageOrder = [SleepStageKind.deep, .light, .rem]

    /// Every night's stages, oldest night first, each night bottom to top.
    let bars: [Bar]
    let averageSleep: String
    let averageHours: Double?
    let window: ChartWindow
    let end: Date
    /// Tallest night, for the y scale.
    let tallestNight: Double
    let regularity: Regularity
    let consistencyHint: String
    /// Time asleep per night, for the header's value and delta.
    let totals: [TrendPoint]
    /// The platform's mean consistency over the nights (0–100).
    let averageConsistency: String
    let bedtimes: [SleepBedtime]
    /// Per night, newest first: date, total, quality, consistency, nap.
    let nightRows: [NightRow]

    struct NightRow: Identifiable, Equatable {
        let day: String
        let title: String
        let total: String
        let quality: String
        let consistency: String?
        let nap: String?
        /// VoiceOver: "Wednesday, November 18" and "7 hours 48 minutes asleep, quality 91, consistency 86, nap 25 minutes".
        var spokenTitle: String = ""
        var spokenValue: String = ""
        var id: String { day }
    }

    init(range: SleepRange, locale: Locale = .autoupdatingCurrent) {
        bars = range.days.flatMap(Self.bars)
        averageSleep = Fmt.duration(minutes: range.avgTotalMin)
        averageHours = range.avgTotalMin.map { Double($0) / 60 }
        window = range.range == SleepRangeKind.month.rawValue ? .month : .week
        end = range.to.flatMap(DayFormat.date(from:)) ?? range.days.last?.date ?? .now
        tallestNight = Dictionary(grouping: bars, by: \.day).values.map { $0.reduce(0) { $0 + $1.hours } }.max() ?? 0
        // The platform's consistency (bedtime and wake σ), else the local bedtime spread.
        if let c = range.avgConsistency {
            regularity = c >= 80 ? .steady : c >= 60 ? .fair : .irregular
            consistencyHint = Self.hint(consistency: c)
        } else {
            let deviation = SleepMath.bedtimeDeviation(range.days.compactMap(\.start))
            regularity = deviation.map { $0 < 30 ? .steady : $0 < 60 ? .fair : .irregular } ?? .unknown
            consistencyHint = SleepMath.consistencyHint(deviation: deviation)
        }
        totals = range.days.map { TrendPoint(day: $0.day, value: $0.totalMin.map(Double.init)) }
        averageConsistency = range.avgConsistency.map(String.init) ?? Fmt.placeholder
        bedtimes = range.bedtimes
        nightRows = range.days.reversed().map { n in
            let quality = n.quality.map(String.init) ?? Fmt.placeholder
            let nap = n.napMin.flatMap { $0 > 0 ? $0 : nil }
            let total = n.totalMin.map { Fmt.spokenDuration(minutes: $0, locale: locale) } ?? Fmt.placeholder
            var spoken = String(localized: "\(total) asleep, quality \(quality)")
            if let c = n.consistency { spoken += ", " + String(localized: "consistency \(String(c))") }
            if let nap { spoken += ", " + String(localized: "nap \(Fmt.spokenDuration(minutes: nap, locale: locale))") }
            return NightRow(day: n.day, title: n.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                            total: Fmt.duration(minutes: n.totalMin), quality: quality,
                            consistency: n.consistency.map(String.init), nap: nap.map { Fmt.duration(minutes: $0) },
                            spokenTitle: n.date.formatted(Date.FormatStyle(locale: locale).weekday(.wide).month(.wide).day()),
                            spokenValue: spoken)
        }
    }

    /// A night's stages bottom to top (`stageOrder`: Deep, Light, REM), or its total as "Asleep"; none without sleep.
    static func bars(_ night: SleepNight) -> [Bar] {
        let staged = stageOrder.compactMap { stage -> Bar? in
            let minutes = night.minutes(for: stage)
            return minutes > 0 ? Bar(day: night.day, date: night.date, stage: stage, hours: Double(minutes) / 60) : nil
        }
        if !staged.isEmpty { return staged }
        guard let total = night.totalMin, total > 0 else { return [] }
        return [Bar(day: night.day, date: night.date, stage: nil, hours: Double(total) / 60)]
    }

    /// Bands of the platform's 0–100 consistency: ≥ 80 steady, ≥ 60 fair (the
    /// `sleep-consistency-low` insight fires below 60).
    static func hint(consistency c: Int) -> String {
        switch c {
        case 80...: return String(localized: "Very regular — bedtime and wake time hardly move.")
        case 60...: return String(localized: "Fairly regular. Keeping bed and wake times within half an hour helps recovery.")
        default: return String(localized: "Irregular bed and wake times. A steadier rhythm helps recovery.")
        }
    }
}
