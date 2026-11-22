import Foundation
import Observation

/// Where events go: a checked `GET /v1/config` → `analytics`. `host` must be `https://eu.i.posthog.com` with no user,
/// port, path, query or fragment; `projectKey` must be `phc_` and 8 to 128 of `[A-Za-z0-9_-]`. Anything else counts as
/// `null`. Every description of it redacts the key.
struct AnalyticsDestination: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
                             CustomReflectable {
    /// `https://<host>`, nothing after it.
    let host: URL
    let projectKey: String

    init?(_ config: AnalyticsConfig?) {
        guard let config, Self.isValidKey(config.projectKey),
              let parts = URLComponents(string: config.host), parts.scheme == "https",
              let name = parts.host, name.lowercased() == Self.allowedHost,
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty || parts.path == "/", parts.query == nil, parts.fragment == nil,
              let url = URL(string: "https://\(Self.allowedHost)")
        else { return nil }
        host = url
        projectKey = config.projectKey
    }

    var description: String { "AnalyticsDestination(host: \(host.absoluteString), project_key: <redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror {
        Mirror(self, children: ["host": host.absoluteString, "project_key": "<redacted>"], displayStyle: .struct)
    }

    /// PostHog's EU cloud, the only host the onboarding step's "Sent to PostHog, in the EU" holds for. A proxy or another
    /// region needs a new build (and new copy), whatever the config says.
    static let allowedHost = "eu.i.posthog.com"
    private static let keyCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    /// `^phc_[A-Za-z0-9_-]{8,128}$`.
    private static func isValidKey(_ key: String) -> Bool {
        guard key.hasPrefix("phc_") else { return false }
        let rest = key.dropFirst(4)
        return (8...128).contains(rest.count) && rest.allSatisfy(keyCharacters.contains)
    }
}

/// Opt-in, anonymous product analytics (design.md "Product analytics, phase 1"): the one owner of the answer, the
/// running destination and the owed reset. Events are sent only while three facts hold, read from the newest config
/// (`FeatureFlagProvider.newest`): `analytics.enabled` is on, the config has a valid `analytics`, and the user opted
/// in; never in demo mode. When any stops holding, the sink stops and drops its queue at once. An event while the
/// gate is closed is dropped, never kept for later: that would be collecting before consent.
///
/// The answer is per install, in `defaults` (`analytics.optIn`: absent, "in" or "out"; `analytics.resetOwed`), never
/// next to an account id. A sign-out (`accountLeft()`) forgets it, so whoever signs in next is asked.
@MainActor
@Observable
final class Analytics {
    enum OptIn: String, Sendable {
        case optedIn = "in"
        case optedOut = "out"
    }

    nonisolated static let optInKey = "analytics.optIn"
    nonisolated static let resetOwedKey = "analytics.resetOwed"

    /// nil: not asked (or asked before the last sign-out).
    private(set) var optIn: OptIn?
    /// Bumped when what the prompt and the toggle read changed where observation can't see it (a pending config).
    private var inputsRevision = 0
    @ObservationIgnored private var lastInputs: Inputs?
    /// What the sink was started with; nil while stopped.
    @ObservationIgnored private(set) var running: AnalyticsDestination?
    /// The next start forgets the anonymous id first (an opt-out or sign-out while not started in this process).
    @ObservationIgnored private(set) var resetOwed: Bool

    /// Private: this owner is the only door, so nothing skips the gate or the token types.
    private let sink: AnalyticsSink
    private let flags: FeatureFlagProvider
    private let defaults: UserDefaults
    private let isDemo: @MainActor () -> Bool
    /// Closed while nobody is signed in: an owed wipe at launch (which forgets the last account's answer) runs while
    /// signed out, so a stale answer never opens the gate before it.
    private let isSignedIn: @MainActor () -> Bool

    init(sink: AnalyticsSink, flags: FeatureFlagProvider, defaults: UserDefaults,
         isDemo: @escaping @MainActor () -> Bool, isSignedIn: @escaping @MainActor () -> Bool = { true }) {
        self.sink = sink
        self.flags = flags
        self.defaults = defaults
        self.isDemo = isDemo
        self.isSignedIn = isSignedIn
        optIn = defaults.string(forKey: Self.optInKey).flatMap(OptIn.init(rawValue:))
        resetOwed = defaults.bool(forKey: Self.resetOwedKey)
    }

    // MARK: the gate

    /// Open only when the flag is on, the config is a valid destination, the user opted in, and demo data is off.
    nonisolated static func destination(flag: Bool, config: AnalyticsConfig?, optIn: OptIn?,
                                        demo: Bool) -> AnalyticsDestination? {
        guard flag, optIn == .optedIn, !demo else { return nil }
        return AnalyticsDestination(config)
    }

    private var gate: AnalyticsDestination? {
        guard isSignedIn() else { return nil }
        return Self.destination(flag: flags.newest(.analyticsEnabled), config: flags.newestAnalytics, optIn: optIn,
                                demo: isDemo())
    }

    // MARK: what call sites see

    /// One event, if the gate is open now (it is asked again first, so an event never rides on a stale answer).
    func track(_ event: AnalyticsEvent) {
        reevaluate()
        guard running != nil else { return }
        sink.capture(event.name, properties: event.properties)
    }

    /// The gate again: closed → stop (the queue goes); another destination → stop, then start with it; the same →
    /// nothing. After every newest-config change (`FeatureFlagProvider.onNewest`) and at launch.
    func reevaluate() {
        noteInputs()
        let next = gate
        guard next != running else { return }
        if running != nil {
            // The old project's queue goes; it never reaches the new one.
            sink.stop()
            running = nil
        }
        guard let next else { return }
        sink.start(next, newID: resetOwed)
        running = next
        if resetOwed { setResetOwed(false) }
    }

    /// The onboarding step's two buttons ("Not now" is `false`) and Profile → Privacy's switch. Off: the queue goes now, and the
    /// next opt-in starts with a new id.
    func setOptIn(_ on: Bool) {
        if on {
            optIn = .optedIn
            defaults.set(OptIn.optedIn.rawValue, forKey: Self.optInKey)
            reevaluate()
        } else {
            // Written first, so a kill between the two can't lose the reset.
            setResetOwed(true)
            optIn = .optedOut
            defaults.set(OptIn.optedOut.rawValue, forKey: Self.optInKey)
            stopAndForget()
        }
    }

    /// Every wipe (sign-out, deletion, a final 401, another account; `AppState.wiped`): the id resets, the queue goes,
    /// and the answer is forgotten, so whoever signs in next is asked in their own first run (or, past it, sets it in
    /// Profile → Privacy).
    func accountLeft() {
        setResetOwed(true)
        stopAndForget()
        optIn = nil
        defaults.removeObject(forKey: Self.optInKey)
    }

    /// What `accountLeft()` leaves in `defaults`, for a wipe that runs without this owner (one resumed at launch,
    /// `AuthService.wipeSharedLocalData`): the answer gone, the next start with a new id.
    nonisolated static func forgetAnswer(defaults: UserDefaults) {
        defaults.removeObject(forKey: optInKey)
        defaults.set(true, forKey: resetOwedKey)
    }

    /// The question (the onboarding's own step before Apple Health, on the first run: `OnboardingCoordinator
    /// .showsAnalyticsStep`): only where an answer means something.
    var showsPrompt: Bool {
        let inputs = currentInputs
        return optIn == nil && inputs.canSend && inputs.available
    }

    /// Profile → Privacy's switch: where the prompt could show, and always while opted in, so it can be withdrawn
    /// even with the flag off.
    var showsToggle: Bool {
        let inputs = currentInputs
        return inputs.canSend && (inputs.available || optIn == .optedIn)
    }

    // MARK: private

    /// What the prompt and the toggle decide from, besides the answer.
    private struct Inputs: Equatable {
        let canSend: Bool
        /// The flag on, a valid destination, demo data off.
        let available: Bool
    }

    private var currentInputs: Inputs {
        _ = inputsRevision
        return inputs()
    }

    private func inputs() -> Inputs {
        let available = flags.newest(.analyticsEnabled) && AnalyticsDestination(flags.newestAnalytics) != nil
            && !isDemo()
        return Inputs(canSend: sink.canSend, available: available)
    }

    /// The prompt and the toggle re-render when their inputs changed, also for a pending config.
    private func noteInputs() {
        let now = inputs()
        guard now != lastInputs else { return }
        lastInputs = now
        inputsRevision += 1
    }

    /// The sink drops what it holds, in memory and on disk, also when nothing was started in this process.
    private func stopNow() {
        sink.stop()
        running = nil
    }

    /// An opt-out or a sign-out: stopped, and the stored id deleted now, not only at the next start (`resetOwed`
    /// stays as the backstop for a sink that couldn't).
    private func stopAndForget() {
        stopNow()
        sink.forgetID()
    }

    private func setResetOwed(_ owed: Bool) {
        resetOwed = owed
        defaults.set(owed, forKey: Self.resetOwedKey)
    }
}
