// Devices & sync, the tracker detail, Check sync and Sync details in Nocturne (PR 6 C2, design-pr6-c-settings.md §4.4–4.6):
// where a page sits, and the decisions the pages show, pure so tests assert them without a view. The offline-first rule
// (2026-11-19): a page never claims a freshness it doesn't have; what is cached says when it was loaded.
import SwiftUI

/// Where one of these pages sits, for its header: pushed (Back), a sheet's root (Close: Today's status line and its
/// calibration link), pushed inside such a sheet (Back, and the sheet's 26 pt top inset: the navigation bar is hidden, so the
/// header would otherwise sit at the sheet's edge under the grabber), or a root with neither (a Debug host).
enum DevicesPagePlacement: Equatable, Sendable {
    case pushed, sheet, pushedInSheet, root

    var navigation: SubpageNavigation {
        switch self {
        case .pushed, .pushedInSheet: return .back()
        case .sheet: return .close()
        case .root: return .none
        }
    }

    /// The sheet's own page: its top inset and its presentation (background, grabber), `SubpageScaffold`'s `isSheet`.
    var isSheet: Bool { self == .sheet }

    /// What a page pushed from this one is: inside a sheet it keeps the sheet's inset.
    var pushed: DevicesPagePlacement { self == .sheet || self == .pushedInSheet ? .pushedInSheet : .pushed }

    /// Pushed inside a sheet: the sheet's 26 pt top inset as a safe-area padding. Not `isSheet`: a pushed page that sets the
    /// sheet's presentation again moves the grabber and the page down (the comparison shots, `in-sheet-*`).
    var topInset: CGFloat { self == .pushedInSheet ? SubpageSpec.sheetTopInset : 0 }
}

extension View {
    /// Where a Devices & sync page sits beyond its header: inside a sheet, under the sheet's top inset.
    func devicesPagePlacement(_ placement: DevicesPagePlacement) -> some View {
        safeAreaPadding(.top, placement.topInset)
    }
}

/// Sync details' State between runs. The engine is `.idle` after every exit (done, failed, refused at a gate, stopped
/// early), and `Settings.lastSync` is only written after a run that sent everything, so "Up to date" comes last: after a
/// hold, no connection, a failure, an unfinished import and a backlog (the offline-first rule, 2026-11-19).
enum SyncIdleState: Equatable, Sendable {
    /// Held at a gate the user can pass: Today's words ("Action needed: agree to the privacy policy").
    case actionNeeded(OnboardingCoordinator.Step)
    /// Held until the policy in force is known: Today's "Health sync paused".
    case paused
    case offline
    /// The last run threw (`SyncEngineState.lastError`, or the policy read before it).
    case failed
    case importNotFinished
    /// The last run stopped early on purpose (the first score first, background time over): another follows.
    case moreToSend
    case upToDate
    /// Nothing sent yet on this iPhone, and nothing waiting.
    case idle

    /// - Parameters:
    ///   - pausedFor: `SyncService.pausedFor` (demo data's hold is silent: demo data never sends).
    ///   - failed: the last run's error, kept by the engine or the service.
    ///   - uploaded: a run that sent everything is on record (`Settings.lastSync`), or demo data (always there).
    static func decide(pausedFor: UploadGate?, offline: Bool, failed: Bool, backfillDone: Bool, backlog: Bool,
                       uploaded: Bool) -> SyncIdleState {
        switch pausedFor {
        case .gate(let code)?: return .actionNeeded(code == .inviteRequired ? .invite : .consent)
        case .policyUnknown?: return .paused
        case .demo?, nil: break
        }
        if offline { return .offline }
        if failed { return .failed }
        if !backfillDone { return .importNotFinished }
        if backlog { return .moreToSend }
        return uploaded ? .upToDate : .idle
    }

    var text: String {
        switch self {
        // The status line's own words, so Today and Sync details say a hold the same way.
        case .actionNeeded(let step): return SyncLine.actionNeeded(step).text(now: .distantPast)
        case .paused: return SyncLine.paused.text(now: .distantPast)
        case .offline: return String(localized: "Offline")
        case .failed: return String(localized: "Last sync failed",
                                    comment: "Sync details → Engine → State: the last Apple Health upload ended with an error.")
        case .importNotFinished: return String(localized: "Import not finished")
        case .moreToSend: return String(localized: "More to send",
                                        comment: "Sync details → Engine → State: the last upload stopped early on purpose; the next run sends the rest.")
        case .upToDate: return String(localized: "Up to date")
        case .idle: return String(localized: "Idle")
        }
    }

    /// Something the user should notice: the value in `warning`, beside its words.
    var needsAttention: Bool {
        switch self {
        case .actionNeeded, .paused, .failed: return true
        default: return false
        }
    }
}

/// "Seen in Apple Health" is `User.sources` from `GET /v1/me`: what the list may say about itself.
enum SourcesFreshness: Equatable, Sendable {
    /// Loaded, and the last load worked (or demo data, which is always there).
    case fresh
    /// Nothing loaded for this account yet, and RYFT is asking: the outline card, "Loading…".
    case loading
    /// Nothing loaded, and nothing can load now (offline, or the loads fail): "Not loaded yet".
    case notLoaded
    /// An earlier load's list while offline or failing: the footer says when it was loaded (nil: not known).
    case stale(Date?)

    /// - Parameters:
    ///   - hasList: a `User` is loaded for the account (its sources may be empty).
    ///   - fetchedAt, failures, lastError: the `.me` read's record (`ResourceState`). A refusal at a gate (`403
    ///     consent_required`, `invite_required`) is never counted as a failure, yet nothing loads past it: one newer than
    ///     the last load makes the list unreachable like a failure does (never "Loading…" forever).
    static func decide(hasList: Bool, isDemo: Bool, isOnline: Bool, fetchedAt: Date?, failures: Int,
                       lastError: ResourceError? = nil) -> SourcesFreshness {
        if isDemo { return .fresh }
        let refused = lastError.map { $0.kind == .gate && $0.at > (fetchedAt ?? .distantPast) } ?? false
        let reachable = isOnline && failures == 0 && !refused
        guard hasList else { return reachable ? .loading : .notLoaded }
        return reachable ? .fresh : .stale(fetchedAt)
    }
}

/// Check sync's one primary action (§4.5, D6C-15): "Allow access" while RYFT never asked, else "Check again", busy while
/// the check runs and disabled without Apple Health.
enum CheckSyncPrimary: Equatable, Sendable {
    case allowAccess
    case checkAgain(busy: Bool, enabled: Bool)

    static func decide(_ phase: TrackerCheckModel.Phase) -> CheckSyncPrimary {
        switch phase {
        case .notAsked: return .allowAccess
        case .running: return .checkAgain(busy: true, enabled: true)
        case .unavailable: return .checkAgain(busy: false, enabled: false)
        case .idle, .done, .locked, .failed: return .checkAgain(busy: false, enabled: true)
        }
    }
}

extension HealthAccess {
    /// RYFT's Health access asks something of the user: only while it was never requested (Allow access). "Not
    /// available" is a fact of the device, never a fault; the word says it without `warning`. Profile's Apple Health row
    /// and Devices & sync's share it.
    var needsAttention: Bool { self == .notAsked }
}
