// Devices & sync, the tracker detail, Check sync and Sync details in Nocturne (PR 6 C2, design-pr6-c-settings.md §4.4–4.6):
// where a page sits, and the decisions the pages show, pure so tests assert them without a view. The offline-first rule
// (2026-11-19): a page never claims a freshness it doesn't have; what is cached says when it was loaded.
import SwiftUI

/// Where one of these pages sits, for its header: pushed (Back), a sheet's root (Close: Today's status line and its
/// calibration link), or a root with neither (a Debug host).
enum DevicesPagePlacement: Equatable, Sendable {
    case pushed, sheet, root

    var navigation: SubpageNavigation {
        switch self {
        case .pushed: return .back()
        case .sheet: return .close()
        case .root: return .none
        }
    }

    var isSheet: Bool { self == .sheet }
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
    ///   - fetchedAt, failures: the `.me` read's record (`ResourceState`).
    static func decide(hasList: Bool, isDemo: Bool, isOnline: Bool, fetchedAt: Date?, failures: Int) -> SourcesFreshness {
        if isDemo { return .fresh }
        let reachable = isOnline && failures == 0
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
