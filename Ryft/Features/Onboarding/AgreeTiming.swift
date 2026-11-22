// The agree line and the onboarding signposts (docs/work/2026-11-22-consent-agree-lag/design.md §6): how long Agree and
// continue took on this phone, for Copy diagnostics and Report a problem, and what Instruments shows of it.
import Foundation
import os

extension Signposts {
    /// Onboarding (design §6.4): the intervals `agree` (the tap to the next step on screen), `consent-post` (the POST)
    /// and `agree-confirm` (RYFT asked again), and the event `step-shown`. Messages are `.public` only for statuses and
    /// codes.
    static let onboarding = OSSignposter(subsystem: "dev.timkrebs.ryft", category: "onboarding")
}

/// The signed-in account's last Agree and continue, in ms from the tap on `AppClock.uptime()`:
/// `agree: sent +3 · answered +3120 (204; attempts 204/3080) · step +3121 · shown +3380 · confirmed +3530 ok ·
/// committed +5000 · session fail_fast · policy_read no · busy_taps 0`.
/// - `sent`: the POST handed to APIClient; the gap before it is the policy read.
/// - `answered`: the POST ended, with its status (`0`: no answer) and its own attempts as APIClient recorded them
///   (`APIStatus.requests`, newest first), as status/duration_ms. `answered − sent − Σ attempts` is the token, bearer and
///   `503` wait.
/// - `step`: the consent recorded on this phone; `shown`: the next step on screen (`RootView`), or the sheet gone.
/// - `confirmed`: RYFT's own word, asked again (`GET /v1/me`): `ok` (consent to the version agreed), `no_consent`,
///   `none` (nothing was sent), `failed <status>` (`0`: no answer), or `dropped` (the answer wasn't stored: a withdrawal
///   meanwhile). Its time is when this phone heard it.
/// - `committed`: the re-read returned, its SwiftData commit included.
/// - `session`: `fail_fast` (one attempt, `SettingsWrite`) or `default`; `policy_read`: the policy was read before the
///   POST; `busy_taps`: taps that found a step's request out.
///
/// Durations, statuses, counts and the session kind only: never a date or a time of day, an account, a device or request
/// ID, a policy version or a health value (§6.5). Kept as the `CachedDocument` `onboarding.agree`, written once the path
/// ends and wiped with the account's other documents; the account and the day are kept only to tell whose it is and how
/// old, and never go into the line.
struct AgreeTiming: Codable, Equatable, Sendable {
    /// One attempt of the POST, as `APIClient` recorded it.
    struct Attempt: Codable, Equatable, Sendable {
        let status: Int
        let durationMs: Int?
    }

    /// The session the POST went on.
    enum Session: String, Codable, Sendable {
        /// One attempt on the fail-fast session, within `SettingsWrite.deadline`.
        case failFast = "fail_fast"
        /// The default session: waits for a network, `429` and `503` loops.
        case standard = "default"
    }

    static let documentKey = "onboarding.agree"
    /// Diagnostics leave an older one out, as `TrackerCheckRecord` does.
    static let reportAge: TimeInterval = 14 * 86_400

    let account: String
    /// The tap, on this phone's clock: only for `reportAge`.
    let at: Date
    var sent: Int?
    var answered: Int?
    var status: Int?
    var attempts: [Attempt] = []
    var step: Int?
    var shown: Int?
    var confirmedAt: Int?
    var confirmed: String?
    var committed: Int?
    var session: Session
    var policyRead = false
    var busyTaps = 0

    init(account: String, at: Date, session: Session) {
        self.account = account
        self.at = at
        self.session = session
    }

    /// What the line says after `agree: `, the `agree` key of Report a problem.
    var text: String {
        func mark(_ ms: Int?) -> String { ms.map { "+\($0)" } ?? "-" }
        var answer = "answered \(mark(answered))"
        if let status {
            let tries = attempts.isEmpty ? "-"
                : attempts.map { "\($0.status)/\($0.durationMs.map(String.init) ?? "-")" }.joined(separator: ",")
            answer += " (\(status); attempts \(tries))"
        }
        let word = [confirmedAt.map { "+\($0)" }, confirmed].compactMap { $0 }
        return [
            "sent \(mark(sent))", answer, "step \(mark(step))", "shown \(mark(shown))",
            "confirmed \(word.isEmpty ? "-" : word.joined(separator: " "))", "committed \(mark(committed))",
            "session \(session.rawValue)", "policy_read \(policyRead ? "yes" : "no")", "busy_taps \(busyTaps)",
        ].joined(separator: " · ")
    }

    /// Copy diagnostics' line.
    var line: String { "agree: " + text }

    /// The POST's own attempts in `requests` (newest first), recorded since `tapped` (the wall clock `APIStatus` dates
    /// them by).
    static func attempts(in requests: [APIStatus.RequestFailure], since tapped: Date) -> [Attempt] {
        requests.filter { $0.method == "POST" && redactedPath($0.path) == "/v1/me/consent" && $0.date >= tapped }
            .map { Attempt(status: $0.status, durationMs: $0.durationMs) }
    }

    /// The status the line gives a failed POST: the platform's, or `0` when no answer came.
    static func status(of error: Error) -> Int { (error as? APIError)?.status ?? 0 }

    /// The signed-in account's; nothing in demo mode, signed out, or for another account.
    @MainActor static func load(_ env: AppEnvironment) -> AgreeTiming? {
        guard !env.isDemo, let account = env.auth.accountID,
              let timing = env.persistence.document(Self.self, key: documentKey), timing.account == account else { return nil }
        return timing
    }

    /// What diagnostics carry (Copy diagnostics, Report a problem): the last one, unless it's over 14 days old.
    @MainActor static func forReport(_ env: AppEnvironment) -> AgreeTiming? {
        load(env).flatMap { env.clock.now().timeIntervalSince($0.at) <= reportAge ? $0 : nil }
    }
}

/// One Agree and continue being timed (`OnboardingCoordinator.agree`): the marks on `env.clock.uptime()` and the
/// signposts. Saved when the path ends; a `shown` that comes later saves it again. Never for another account: the
/// coordinator forgets it on every switch, and `save` checks the account.
@MainActor
final class AgreeTimer {
    private let clock: AppClock
    private let started: Duration
    /// The tap on the wall clock, which `APIStatus.requests` are dated by: only to pick the POST's attempts.
    private let tapped = Date()
    private(set) var timing: AgreeTiming
    private let signposter = Signposts.onboarding
    private var agree: OSSignpostIntervalState?
    private var post: OSSignpostIntervalState?
    private var confirm: OSSignpostIntervalState?
    /// The path ended and the line was saved.
    private(set) var isSaved = false

    init(env: AppEnvironment, account: String, session: AgreeTiming.Session) {
        clock = env.clock
        started = env.clock.uptime()
        timing = AgreeTiming(account: account, at: env.clock.now(), session: session)
        agree = signposter.beginInterval("agree", id: signposter.makeSignpostID())
    }

    private func elapsed() -> Int {
        max(0, Int(((clock.uptime() - started).timeInterval * 1000).rounded()))
    }

    func readsPolicy() { timing.policyRead = true }

    /// The POST is handed to APIClient.
    func sent() {
        timing.sent = elapsed()
        post = signposter.beginInterval("consent-post", id: signposter.makeSignpostID())
    }

    /// The POST ended with `status` (`204`, the platform's, or `0` for no answer); its attempts from `requests`.
    func answered(_ status: Int, requests: [APIStatus.RequestFailure]) {
        timing.answered = elapsed()
        timing.status = status
        timing.attempts = AgreeTiming.attempts(in: requests, since: tapped)
        if let post { signposter.endInterval("consent-post", post, "\(status, privacy: .public)") }
        post = nil
    }

    /// The consent is recorded on this phone.
    func stepRecorded() { timing.step = elapsed() }

    /// The next step is on screen (or the sheet went): true the first time after `stepRecorded`.
    func shown() -> Bool {
        guard timing.step != nil, timing.shown == nil else { return false }
        timing.shown = elapsed()
        signposter.emitEvent("step-shown")
        if let agree { signposter.endInterval("agree", agree) }
        agree = nil
        return true
    }

    /// RYFT is asked again (`GET /v1/me`).
    func confirming() {
        confirm = signposter.beginInterval("agree-confirm", id: signposter.makeSignpostID())
    }

    /// This phone heard RYFT's word on the agreement.
    func heard() {
        if timing.confirmedAt == nil { timing.confirmedAt = elapsed() }
    }

    /// The re-read returned, with RYFT's word (`AgreeTiming.confirmed`'s values).
    func committed(_ word: String) {
        timing.committed = elapsed()
        timing.confirmed = word
        if let confirm { signposter.endInterval("agree-confirm", confirm, "\(word, privacy: .public)") }
        confirm = nil
    }

    func busyTap() { timing.busyTaps += 1 }

    /// The path ended (or a late `shown` came): the line, for the account it was timed for only. The `agree` interval
    /// stays open until the step shows; a path that failed ends it here.
    func save(in env: AppEnvironment) {
        if timing.step == nil, let agree {
            signposter.endInterval("agree", agree, "\(self.timing.status ?? 0, privacy: .public)")
            self.agree = nil
        }
        guard !env.isDemo, env.auth.accountID == timing.account else { return }
        env.persistence.saveDocument(timing, key: AgreeTiming.documentKey, at: env.clock.now())
        isSaved = true
    }
}
