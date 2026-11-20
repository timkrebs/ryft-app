import Foundation
import Observation

/// Where events go: a checked `GET /v1/config` → `analytics`. `host` must be `https://<host>` with no user, port,
/// path, query or fragment; `projectKey` must be `phc_` and 8 to 128 of `[A-Za-z0-9_-]`. Anything else counts as
/// `null`. Every description of it redacts the key.
struct AnalyticsDestination: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
                             CustomReflectable {
    /// `https://<host>`, nothing after it.
    let host: URL
    let projectKey: String

    init?(_ config: AnalyticsConfig?) {
        guard let config, Self.isValidKey(config.projectKey),
              let parts = URLComponents(string: config.host), parts.scheme == "https",
              let name = parts.host, Self.isValidHostName(name),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty || parts.path == "/", parts.query == nil, parts.fragment == nil,
              let url = URL(string: "https://\(name)")
        else { return nil }
        host = url
        projectKey = config.projectKey
    }

    var description: String { "AnalyticsDestination(host: \(host.absoluteString), project_key: <redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror {
        Mirror(self, children: ["host": host.absoluteString, "project_key": "<redacted>"], displayStyle: .struct)
    }

    private static let keyCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    private static let hostCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")

    /// `^phc_[A-Za-z0-9_-]{8,128}$`.
    private static func isValidKey(_ key: String) -> Bool {
        guard key.hasPrefix("phc_") else { return false }
        let rest = key.dropFirst(4)
        return (8...128).contains(rest.count) && rest.allSatisfy(keyCharacters.contains)
    }

    /// A DNS name: letters, digits, dots and dashes, nothing percent-encoded, no empty label.
    private static func isValidHostName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy(hostCharacters.contains) && !name.split(separator: ".", omittingEmptySubsequences: false)
            .contains { $0.isEmpty }
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

    static let optInKey = "analytics.optIn"
    static let resetOwedKey = "analytics.resetOwed"

    /// nil: not asked (or asked before the last sign-out).
    private(set) var optIn: OptIn?
    /// Bumped when what the prompt and the toggle read changed where observation can't see it (a pending config).
    private var inputsRevision = 0
    @ObservationIgnored private var lastInputs: Inputs?
    /// What the sink was started with; nil while stopped.
    @ObservationIgnored private(set) var running: AnalyticsDestination?
    /// The next start forgets the anonymous id first (an opt-out or sign-out while not started in this process).
    @ObservationIgnored private(set) var resetOwed: Bool

    let sink: AnalyticsSink
    private let flags: FeatureFlagProvider
    private let defaults: UserDefaults
    private let isDemo: @MainActor () -> Bool

    init(sink: AnalyticsSink, flags: FeatureFlagProvider, defaults: UserDefaults,
         isDemo: @escaping @MainActor () -> Bool) {
        self.sink = sink
        self.flags = flags
        self.defaults = defaults
        self.isDemo = isDemo
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
        Self.destination(flag: flags.newest(.analyticsEnabled), config: flags.newestAnalytics, optIn: optIn,
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

    /// The prompt's two buttons (a swipe is `false`) and Profile → Privacy's switch. Off: the queue goes now, and the
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
            stopNow()
        }
    }

    /// Every wipe (sign-out, deletion, a final 401, another account; `AppState.wiped`): the id resets, the queue goes,
    /// and the answer is forgotten, so whoever signs in next is asked after their own onboarding.
    func accountLeft() {
        setResetOwed(true)
        stopNow()
        optIn = nil
        defaults.removeObject(forKey: Self.optInKey)
    }

    /// The prompt (after the onboarding, once): only where an answer means something.
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

    private func setResetOwed(_ owed: Bool) {
        resetOwed = owed
        defaults.set(owed, forKey: Self.resetOwedKey)
    }
}
