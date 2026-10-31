import Foundation

/// What this phone last heard about a day's scoring that the platform's `GET /v1/me/sync` can't have told it yet
/// (`docs/work/2026-10-31-data-quality/architecture.md` §D3b, "one owner for 'this day is being scored'"):
///
/// - **pending:** the platform accepted a write that touches the day (an upload's `days_touched`, a `daysChanged`).
///   From then on the day is being scored on every path, foreground or background, on Today and on the widget.
/// - **scored:** a silent push named the day.
///
/// `SyncService.scoringLedger` keeps one per day, written only by the coordinator's steps (`SyncSteps.awaiting`,
/// `SyncSteps.scored`). A status read **requested** at least `statusCacheTime` after the word replaces it with the
/// platform's own; an earlier one (it may come from the platform's cache) can't. Both times are this phone's clock:
/// never compared with the server's.
struct ScoringWord: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case pending, scored
    }

    let kind: Kind
    /// When it was said, on this phone's clock.
    let at: Date

    /// API.md: `GET /v1/me/sync` is cached 10 s per user. An answer requested sooner after a word may be from before it.
    static let statusCacheTime: TimeInterval = 10

    /// A status read requested at `requestedAt` is the platform's word after this one.
    func isAnswered(byStatusRequestedAt requestedAt: Date) -> Bool {
        requestedAt.timeIntervalSince(at) >= Self.statusCacheTime
    }

    /// `day`'s scoring state, for Today (`TodayStates.todayState`) and the widget (`Repository.widgetFacts`) alike.
    /// The platform's: its latest status when it's about `day`, else the cached row's. While no later status read has
    /// answered this phone's word, the word adjusts it: `pending` wins over anything; `scored` rules out `pending` and
    /// `stale` (the push means new data arrived), but a push for a day without last night's sleep leaves it waiting
    /// for sleep.
    static func state(day: String, word: ScoringWord?, status: TodayState?, row: DailyScore?) -> ScoringState? {
        let platform = status?.day == day ? status?.state : row?.scoringState
        switch word?.kind {
        case nil: return platform
        case .pending?: return .pending
        case .scored?: return platform == .waitingForSleep ? .waitingForSleep : .scored
        }
    }

    /// The ledger for Copy diagnostics: days and kinds only (`2026-10-19 pending, 2026-10-18 scored`), or `-`.
    static func diagnosticLine(_ ledger: [String: ScoringWord]) -> String {
        guard !ledger.isEmpty else { return "-" }
        return ledger.sorted { $0.key > $1.key }.map { "\($0.key) \($0.value.kind)" }.joined(separator: ", ")
    }
}
