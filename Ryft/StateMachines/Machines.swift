import Foundation

// The four flows with many states and guards. Each: an enum, its transition
// table, one GKState subclass per case (GameplayKit identifies states by class),
// and a factory that wires the owner's entry/exit side effects in.

// MARK: - sync pipeline

/// What a sync is doing (`SyncService.phase`, driven by `SyncCoordinator`).
enum SyncPhase: String, CaseIterable, Sendable {
    case idle, reading, uploading, awaitingScores, refreshing, done, failed, offline
}

enum SyncMachine {
    static func table(onEnter: (@MainActor (SyncPhase, SyncPhase) -> Void)? = nil) -> TransitionTable<SyncPhase> {
        TransitionTable(initial: .idle, edges: [
            // `refreshing` straight from `idle`: a silent push refreshes without uploading.
            .idle: [.reading, .refreshing, .offline],
            // `idle` from an active phase: the sync was cancelled. `done` straight after the
            // upload: a run in the background (the silent push refreshes).
            .reading: [.uploading, .awaitingScores, .refreshing, .done, .failed, .offline, .idle],
            .uploading: [.reading, .awaitingScores, .refreshing, .done, .failed, .idle],
            .awaitingScores: [.refreshing, .failed, .idle],
            .refreshing: [.done, .failed, .idle],
            .done: [.reading, .refreshing, .offline, .idle],
            .failed: [.reading, .refreshing, .offline, .idle],
            .offline: [.reading, .idle],
        ], onEnter: onEnter)
    }

    @MainActor
    static func make(onEnter: (@MainActor (SyncPhase, SyncPhase) -> Void)? = nil) -> GKTableMachine<SyncPhase> {
        GKTableMachine(table(onEnter: onEnter), classes: [
            .idle: SyncIdle.self, .reading: SyncReading.self, .uploading: SyncUploading.self,
            .awaitingScores: SyncAwaitingScores.self, .refreshing: SyncRefreshing.self, .done: SyncDone.self,
            .failed: SyncFailed.self, .offline: SyncOffline.self,
        ])
    }

    final class SyncIdle: TableGKState<SyncPhase> {}
    final class SyncReading: TableGKState<SyncPhase> {}
    final class SyncUploading: TableGKState<SyncPhase> {}
    final class SyncAwaitingScores: TableGKState<SyncPhase> {}
    final class SyncRefreshing: TableGKState<SyncPhase> {}
    final class SyncDone: TableGKState<SyncPhase> {}
    final class SyncFailed: TableGKState<SyncPhase> {}
    final class SyncOffline: TableGKState<SyncPhase> {}
}

// MARK: - auth session

/// The account's session (`AuthService.phase`). `RootView` reads the coarser `AuthService.State`.
enum AuthPhase: String, CaseIterable, Sendable {
    /// The SDK hasn't reported the stored session yet.
    case restoring
    case signedOut
    /// A sign-in, sign-up or link exchange is running.
    case signingIn
    case signedIn
    /// The platform answered 401; the session is being refreshed once.
    case refreshing
    /// The session ended without the user asking (revoked, deleted elsewhere).
    case expired
}

enum AuthMachine {
    static func table(onEnter: (@MainActor (AuthPhase, AuthPhase) -> Void)? = nil) -> TransitionTable<AuthPhase> {
        TransitionTable(initial: .restoring, edges: [
            .restoring: [.signedIn, .signedOut, .expired],
            .signedOut: [.signingIn, .signedIn],
            .signingIn: [.signedIn, .signedOut],
            .signedIn: [.refreshing, .signedOut, .expired],
            .refreshing: [.signedIn, .signedOut, .expired],
            .expired: [.signingIn, .signedIn, .signedOut],
        ], onEnter: onEnter)
    }

    @MainActor
    static func make(onEnter: (@MainActor (AuthPhase, AuthPhase) -> Void)? = nil) -> GKTableMachine<AuthPhase> {
        GKTableMachine(table(onEnter: onEnter), classes: [
            .restoring: AuthRestoring.self, .signedOut: AuthSignedOut.self, .signingIn: AuthSigningIn.self,
            .signedIn: AuthSignedIn.self, .refreshing: AuthRefreshing.self, .expired: AuthExpired.self,
        ])
    }

    final class AuthRestoring: TableGKState<AuthPhase> {}
    final class AuthSignedOut: TableGKState<AuthPhase> {}
    final class AuthSigningIn: TableGKState<AuthPhase> {}
    final class AuthSignedIn: TableGKState<AuthPhase> {}
    final class AuthRefreshing: TableGKState<AuthPhase> {}
    final class AuthExpired: TableGKState<AuthPhase> {}
}

// MARK: - live training session

/// The workout being logged (`SessionController.phase`).
enum LiveSessionPhase: String, CaseIterable, Sendable {
    case idle
    case active
    /// The rest timer is running.
    case resting
    /// The app went to the background mid-workout; back to `active` on return.
    case paused
    /// Finish was tapped; the session is being completed and uploaded.
    case finishing
    case completed
    case discarded
}

enum LiveSessionMachine {
    static func table(onEnter: (@MainActor (LiveSessionPhase, LiveSessionPhase) -> Void)? = nil)
        -> TransitionTable<LiveSessionPhase> {
        TransitionTable(initial: .idle, edges: [
            .idle: [.active],
            .active: [.resting, .paused, .finishing, .discarded],
            .resting: [.active, .paused, .finishing, .discarded],
            .paused: [.active, .finishing, .discarded],
            // Back to `active` when completing couldn't even be queued.
            .finishing: [.completed, .active],
            .completed: [],
            .discarded: [],
        ], onEnter: onEnter)
    }

    @MainActor
    static func make(onEnter: (@MainActor (LiveSessionPhase, LiveSessionPhase) -> Void)? = nil)
        -> GKTableMachine<LiveSessionPhase> {
        GKTableMachine(table(onEnter: onEnter), classes: [
            .idle: SessionIdle.self, .active: SessionActive.self, .resting: SessionResting.self,
            .paused: SessionPaused.self, .finishing: SessionFinishing.self, .completed: SessionCompleted.self,
            .discarded: SessionDiscarded.self,
        ])
    }

    final class SessionIdle: TableGKState<LiveSessionPhase> {}
    final class SessionActive: TableGKState<LiveSessionPhase> {}
    final class SessionResting: TableGKState<LiveSessionPhase> {}
    final class SessionPaused: TableGKState<LiveSessionPhase> {}
    final class SessionFinishing: TableGKState<LiveSessionPhase> {}
    final class SessionCompleted: TableGKState<LiveSessionPhase> {}
    final class SessionDiscarded: TableGKState<LiveSessionPhase> {}
}

// MARK: - HealthKit onboarding

/// "Connect Apple Health" (`HealthOnboardingViewModel.phase`).
enum HealthOnboardingPhase: String, CaseIterable, Sendable {
    /// The explanation screen.
    case explain
    /// The system sheet is up.
    case requesting
    /// The sheet was answered. HealthKit never says what was allowed for reading.
    case granted
    /// "Not now", or the request failed.
    case denied
    /// Handed over to the first 90-day sync.
    case firstSync
}

enum HealthOnboardingMachine {
    static func table(onEnter: (@MainActor (HealthOnboardingPhase, HealthOnboardingPhase) -> Void)? = nil)
        -> TransitionTable<HealthOnboardingPhase> {
        TransitionTable(initial: .explain, edges: [
            .explain: [.requesting, .denied],
            .requesting: [.granted, .denied],
            .granted: [.firstSync],
            .denied: [.requesting],
            .firstSync: [],
        ], onEnter: onEnter)
    }

    @MainActor
    static func make(onEnter: (@MainActor (HealthOnboardingPhase, HealthOnboardingPhase) -> Void)? = nil)
        -> GKTableMachine<HealthOnboardingPhase> {
        GKTableMachine(table(onEnter: onEnter), classes: [
            .explain: OnboardingExplain.self, .requesting: OnboardingRequesting.self,
            .granted: OnboardingGranted.self, .denied: OnboardingDenied.self, .firstSync: OnboardingFirstSync.self,
        ])
    }

    final class OnboardingExplain: TableGKState<HealthOnboardingPhase> {}
    final class OnboardingRequesting: TableGKState<HealthOnboardingPhase> {}
    final class OnboardingGranted: TableGKState<HealthOnboardingPhase> {}
    final class OnboardingDenied: TableGKState<HealthOnboardingPhase> {}
    final class OnboardingFirstSync: TableGKState<HealthOnboardingPhase> {}
}
