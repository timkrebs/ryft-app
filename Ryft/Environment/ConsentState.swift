// What this phone knows about the account's consent standing, for every upload of health data (ADR 0008,
// docs/work/2026-10-26-consent-gates/design.md §3.1): the last answer about the privacy policy in force, when it
// arrived on this phone, and the platform's last `consent_required` refusal. The decision itself is the pure
// `OnboardingCoordinator.gate(_:)`.
import Foundation
import Observation
import UIKit

/// Why an upload waits (`OnboardingCoordinator.gate(_:path:write:)`, asked by `SyncService`, `ActivityUploader`,
/// `TrainSyncService` and `TrainImportUploader`).
enum UploadGate: Equatable, Sendable {
    /// Something only the user or the platform can settle: no consent to the policy in force, an enforced invite
    /// gate, the account not known yet.
    case gate(APIErrorCode)
    /// The policy in force isn't known on this phone right now (no answer, one older than its age limit, or a record
    /// that can't be read before the first unlock): an upload online asks `/v1/config` first
    /// (`ConsentState.revalidate`).
    case policyUnknown
    /// Demo data is on, and this path's client is the platform's whatever the switch says (HealthKit sync): it never
    /// sends while demo data shows. Silent.
    case demo

    /// For diagnostics (Sync details, Copy diagnostics): the code, `policy_unknown` or `demo`.
    var diagnosticName: String {
        switch self {
        case .gate(let code): return code.rawValue
        case .policyUnknown: return "policy_unknown"
        case .demo: return "demo"
        }
    }
}

/// Which upload asks the gate: each has its own client and binding (design.md §3.2).
enum UploadPath: Sendable {
    /// HealthKit pages (`SyncService`): always the platform's client.
    case healthKit
    /// Activities and manual nights (`ActivityUploader`): every request bound to its account or demo.
    case activities
    /// Train's outbox (`TrainSyncService`): every op bound to its account or demo.
    case train
    /// The training import (`TrainImportUploader`: `POST /v1/exercises`, `POST /v1/train/import`, the enrolment):
    /// every request bound to its account or demo, every `403` held.
    case trainImport
}

/// What an upload's request does with health data.
enum UploadWrite: Sendable {
    /// It carries health data: a sync page, an activity or night `PUT`, a Train session `PUT` or completion, the import.
    case data
    /// It removes data (every `DELETE`): erasure is in the user's interest (Art. 17), so it goes without a current
    /// consent.
    case erasure
}

/// One record per account (`CachedDocument` `consent.<account>`), so a background process, an offline start and a
/// long session decide from the same facts.
///
/// - **Written only here**, and only when something changed: a `/v1/config` answer (`fetchConfig`, the one door for
///   the config), a consent `204` (`consented`), a refusal and its end (`refused`, `cleared`): `consent_required` in
///   any mode, `invite_required` only when enforced; and this phone's agreement (`consented`, settled by `heard`,
///   removed by `withdrew`).
/// - **This phone's agreement** (ADR 0025, docs/work/2026-11-22-consent-agree-lag/design.md §4): a consent `204` moves
///   onboarding on at once (`unsettledAgreement`, counted by `OnboardingCoordinator.missing`), never an upload: the gate
///   waits for a `GET /v1/me` asked for at or after it (`heard`). Until `ScoringWord.statusCacheTime` after it, a
///   `GET /v1/me/sync` says nothing about consent (`statusSpeaksForConsent`): the platform caches it 10 s.
/// - **Fresh** while `0 ≤ now − answeredAt < min(ttl, 24 h)` on this phone's clock (`ttl` is the answer's `ttl_sec`;
///   a clock set back counts as stale). Only a fresh answer opens a gate; staleness can only hold.
/// - **Read once per `AccountBinding`** into unobserved storage. The observed `revision` bumps on every write and
///   every read touches it, so views re-render on a new answer without a read ever mutating observed state. A read
///   while protected data is unavailable (before the first unlock) isn't kept, and the gate holds every write until
///   the unlock reloads it (`isRecordReadable`).
/// - **Wiped with the account:** every wipe deletes every `CachedDocument` and moves the binding.
/// - **This phone's withdrawal** (`withdrew(at:)`) is kept beside the record, per account in `env.defaults`, outside
///   the store: it holds the gate when the store refuses the withdrawal's saves (T0.6 did on iOS 17 after demo data;
///   a failed save still can) and in a background launch that never runs the check, until this phone agrees again
///   (`consented`) or a `GET /v1/me` asked for after it shows consent to the policy in force (`heard`). Not wiped with
///   the account: the same account signing in again hasn't agreed since either.
/// - **A withdrawal with no answer** (`withdrawalUnresolvedSince`) is kept the same way, and only closes: every data
///   upload waits until RYFT is heard from after it (security review round 3, S-2).
/// - **Demo data** reads and writes nothing: the gate decides demo before the record (design.md §3.2).
@MainActor
@Observable
final class ConsentState {
    /// The stored record.
    struct Record: Codable, Equatable, Sendable {
        /// `privacy_policy_version` of the last answer.
        var policyVersion: String?
        /// `privacy_policy_url` of the last answer.
        var policyURL: String?
        /// When that answer arrived, on this phone's clock.
        var answeredAt: Date?
        /// How long it's good for: the answer's `ttl_sec` (`defaultTTL` when missing or 0). Trusted for at most
        /// `maximumTTL`, whatever is stored (`isPolicyFresh`).
        var ttl: TimeInterval = ConsentState.defaultTTL
        /// The platform's refusals, from when: `consent_required` in any mode (a `403`, `X-RYFT-Gate`,
        /// `GET /v1/me/sync`) and an enforced `invite_required` (a `403`), each until the platform no longer names it
        /// or the user passes it. A background process behind either sends nothing.
        var refusals: [APIErrorCode: Date] = [:]
        /// This phone's last consent `204` (`consented`), settled once a `GET /v1/me` asked for at or after it is stored
        /// (`heard`), removed by this phone's withdrawal. Older records have none.
        var agreement: Agreement?
    }

    /// A consent `204` on this phone: what onboarding's flow counts until RYFT's own word on it is heard, and when the
    /// platform's status cache may still say otherwise (`statusSpeaksForConsent`).
    struct Agreement: Codable, Equatable, Sendable {
        /// The policy version agreed to.
        var version: String
        /// When the `204` arrived, on this phone's clock.
        var at: Date
        /// A `GET /v1/me` asked for at or after `at` was stored: from then on the stored user decides, for the flow too.
        var settled = false
    }

    /// API.md: `GET /v1/config` → `ttl_sec` is 21 600 today.
    nonisolated static let defaultTTL: TimeInterval = 6 * 3_600
    /// The longest an answer is trusted, whatever `ttl_sec` says: a misconfigured server can't keep a stale policy
    /// open for days (privacy review N3).
    nonisolated static let maximumTTL: TimeInterval = 24 * 3_600
    /// After a failed `/v1/config` read, `revalidate` sends nothing for this long (`OnboardingCoordinator.recheckInterval`).
    nonisolated static let retryAfterFailure: TimeInterval = 60

    nonisolated static func key(_ account: String) -> String { "consent.\(account)" }

    /// Where `withdrawnAt` is kept for `account` (`env.defaults`).
    nonisolated static func withdrawalKey(_ account: String) -> String { "consent.withdrawn.\(account)" }

    /// Where `withdrawalUnresolvedSince` is kept for `account` (`env.defaults`, beside `withdrawnAt`).
    nonisolated static func unresolvedWithdrawalKey(_ account: String) -> String { "consent.withdrawal.unresolved.\(account)" }

    /// Bumped by every write: whoever reads the record reads again.
    private(set) var revision = 0

    @ObservationIgnored private weak var env: AppEnvironment?
    /// The record as read for a binding (nil: none stored).
    @ObservationIgnored private var memo: (binding: AccountBinding, record: Record?)?
    /// The last failed `revalidate` read, for its binding: nothing is sent again within `retryAfterFailure`.
    @ObservationIgnored private var lastFailure: (binding: AccountBinding, at: Date, error: Error)?
    /// Told when `heard` settles this phone's agreement (the agree line's `confirmed`, `OnboardingCoordinator`).
    @ObservationIgnored var agreementSettled: (@MainActor () -> Void)?
    /// Whether the store can be read (before the first unlock after a reboot it can't, and reads come back empty).
    @ObservationIgnored var isProtectedDataAvailable: @MainActor () -> Bool = {
        UIApplication.shared.isProtectedDataAvailable
    }
    @ObservationIgnored private var unlockObserver: NSObjectProtocol?
    /// The live graph's (`AppEnvironment.live`): the record counts only in the account's store on disk. A process
    /// that started before the first unlock and fell back to `TrainStore`'s in-memory store never reads or writes it
    /// there, so it holds every write until it's relaunched (an unlock can't bring the file back into this process).
    @ObservationIgnored var requiresDurableStore = false

    init(env: AppEnvironment) {
        self.env = env
        // The unlock: a read that came back empty before it is read again (and whoever asked the gate, asks again).
        unlockObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// Forget what was read: the next read asks the store again.
    func reload() {
        memo = nil
        revision += 1
    }

    // MARK: reads

    /// The account's record, read once per binding; nil signed out, in demo mode, or with none stored.
    private var record: Record? {
        _ = revision
        guard let env, !env.isDemo, let account = env.auth.accountID else { return nil }
        let binding = AccountBinding(env)
        if let memo, memo.binding == binding { return memo.record }
        let stored = env.persistence.document(Record.self, key: Self.key(account))
        // Nothing read while the store may be locked isn't kept: the next read, after the unlock, asks again
        // (privacy review N2). A record read is kept either way. Nothing from a fallback store is kept at all.
        if storeHoldsRecords, stored != nil || isProtectedDataAvailable() { memo = (binding, stored) }
        return stored
    }

    /// The store the record is read from and written to lasts: always in tests and previews, on disk in the live graph.
    private var storeHoldsRecords: Bool { !requiresDurableStore || env?.persistence.isDurable == true }

    /// The record could be read for the current binding (always signed out or in demo, where there's none). False
    /// before the first unlock when nothing came back: then every write holds (`policyUnknown`) and `revalidate`
    /// doesn't ask, since nothing could be stored.
    var isRecordReadable: Bool {
        _ = record
        guard let env, !env.isDemo, env.auth.accountID != nil else { return true }
        // Never memoised from a fallback store (`record`), so that's never readable either.
        return memo?.binding == AccountBinding(env)
    }

    /// The latest policy version heard of, whatever its age: the consent step's text and `earlierConsent`. Never
    /// what opens a gate on its own (`isPolicyFresh`).
    var latestPolicyVersion: String? { record?.policyVersion }

    /// Where the latest policy heard of is published.
    var policyURL: String? { record?.policyURL }

    /// The gates the platform refused at and hasn't said otherwise since: `consent_required` (any mode), an enforced
    /// `invite_required`.
    var refusals: Set<APIErrorCode> { record.map { Set($0.refusals.keys) } ?? [] }

    /// When the user withdrew consent on this phone, until it ends (`consented`, `heard`); nil signed out and in demo
    /// mode. Before the first unlock the defaults can't be read either, and then the record isn't readable
    /// (`isRecordReadable`), which holds every write anyway.
    var withdrawnAt: Date? {
        _ = revision
        guard let env, !env.isDemo, let account = env.auth.accountID else { return nil }
        return env.defaults.object(forKey: Self.withdrawalKey(account)) as? Date
    }

    /// A withdrawal sent with no answer, and RYFT not heard from since (security review round 3, S-2): from when its
    /// attempt ended. The `DELETE` may have been recorded, so every data upload waits (`OnboardingCoordinator`'s
    /// `Facts.withdrawing`), in this process, the next one and a background launch alike: kept per account in
    /// `env.defaults`, beside `withdrawnAt`. Only closes. It ends on a `GET /v1/me` asked for at or after it and stored
    /// (`heard`: the withdrawal's own late re-read, the next check), a withdrawal answered (`withdrew`), a new agreement
    /// (`consented`), or another account on this iPhone (`endUnresolvedWithdrawal(of:)`). Nil signed out and in demo mode.
    var withdrawalUnresolvedSince: Date? {
        _ = revision
        guard let env, !env.isDemo, let account = env.auth.accountID else { return nil }
        return env.defaults.object(forKey: Self.unresolvedWithdrawalKey(account)) as? Date
    }

    /// This phone's agreement as stored, settled or not; nil signed out, in demo mode, before the first `204` and after a
    /// withdrawal.
    var agreement: Agreement? { record?.agreement }

    /// The agreement as the flow, the upload gate and the status rule count it. One recorded after now is void (the clock
    /// was set back since, security review N-3): nothing waits for it, and the stored user decides. It counts again once
    /// the clock passes it, unless a `/v1/me` heard meanwhile settled it (`heard`).
    var standingAgreement: Agreement? {
        guard let env, let agreement, agreement.at <= env.clock.now() else { return nil }
        return agreement
    }

    /// The standing agreement while RYFT's own word on it is still out.
    var pendingAgreement: Agreement? { standingAgreement.flatMap { $0.settled ? nil : $0 } }

    /// The version this phone agreed to while RYFT's own word on it is still out: onboarding's flow counts it as given
    /// (`OnboardingCoordinator.missing`), and the upload gate holds while it's there (`gate`, ADR 0025).
    var unsettledAgreement: String? { pendingAgreement?.version }

    /// A `GET /v1/me/sync` asked for at `askedAt` speaks for consent, `consent_required` or `null`: not when it was asked
    /// within `ScoringWord.statusCacheTime` of this phone's consent `204`, or before it, when the platform's cache
    /// (API.md: 10 s per user) may still hold an answer from before the consent. The same rule as
    /// `ScoringWord.isAnswered(byStatusRequestedAt:)`. Without a standing agreement every status does.
    func statusSpeaksForConsent(askedAt: Date) -> Bool {
        guard let agreement = standingAgreement else { return true }
        return askedAt.timeIntervalSince(agreement.at) >= ScoringWord.statusCacheTime
    }

    /// A policy answer younger than its ttl (at most `maximumTTL`), on this phone's clock.
    func isPolicyFresh(at now: Date) -> Bool {
        guard let record, record.policyVersion != nil, let answeredAt = record.answeredAt else { return false }
        let age = now.timeIntervalSince(answeredAt)
        return age >= 0 && age < min(record.ttl, Self.maximumTTL)
    }

    // MARK: writers

    /// A `/v1/config` answer that arrived `at` for a flight started under `binding`. Dropped when the account changed
    /// since, when it names no version, or when a newer answer is already stored.
    func received(_ config: RemoteConfig, at: Date, binding: AccountBinding) {
        guard let env, binding.isCurrent(in: env), let version = config.privacyPolicyVersion else { return }
        write { record in
            if let answeredAt = record.answeredAt, answeredAt > at { return }
            record.policyVersion = version
            record.policyURL = config.privacyPolicyUrl
            record.answeredAt = at
            record.ttl = config.ttlSec > 0 ? TimeInterval(config.ttlSec) : Self.defaultTTL
        }
    }

    /// `POST /v1/me/consent` answered `204` for `version`: it was in force `at` (the platform answers `422`
    /// otherwise), so that's an answer then, good for the same ttl, and the refusal is over. This phone's agreement
    /// replaces the last one, unsettled, or `settled` when RYFT's own word on it was already stored (a POST without an
    /// answer whose re-read showed the consent).
    func consented(to version: String, at: Date, settled: Bool = false) {
        endWithdrawal()
        endUnresolvedWithdrawal()
        write { record in
            if record.answeredAt.map({ $0 <= at }) ?? true {
                if record.policyVersion != version { record.policyURL = nil }
                record.policyVersion = version
                record.answeredAt = at
            }
            record.refusals[.consentRequired] = nil
            record.agreement = Agreement(version: version, at: at, settled: settled)
        }
    }

    /// `DELETE /v1/me/consent` answered at `at`: this phone's withdrawal, kept outside the store (`withdrawnAt`), and the
    /// platform's refusal from then on (API.md: sync answers `403 consent_required`), recorded as any refusal is. This
    /// phone's agreement goes with it, and a withdrawal that had no answer is resolved (`withdrawalUnresolvedSince`).
    func withdrew(at: Date) {
        guard let env, !env.isDemo, let account = env.auth.accountID else { return }
        env.defaults.set(at, forKey: Self.withdrawalKey(account))
        env.defaults.removeObject(forKey: Self.unresolvedWithdrawalKey(account))
        revision += 1
        write { record in
            record.agreement = nil
            if record.refusals[.consentRequired] == nil { record.refusals[.consentRequired] = at }
        }
    }

    /// A `GET /v1/me` answer, asked for at `askedAt`, was written (`Repository.store(fetchedUser:askedAt:)`). Asked for at
    /// or after this phone's agreement, it settles it: the stored user decides from now on (R3). A void one (recorded
    /// after now, `standingAgreement`) any answer settles: the stored user decides then anyway (code review round 2, 5).
    /// Not when `settles` is false (a withdrawal's own re-read: RYFT may record the `DELETE` after it). Asked for after
    /// the withdrawal and showing consent to the latest policy heard of, it ends the withdrawal (the user agreed again, on
    /// another device). One asked for before either may be from before it, and an older policy's consent isn't one.
    /// Asked for at or after a withdrawal that had no answer, it resolves that one, whatever it shows, `settles` or not
    /// (security review round 3, S-2): the stored user is RYFT's word on it from then on.
    func heard(_ user: User, askedAt: Date, settles: Bool = true) {
        if settles, let env, let agreement, !agreement.settled,
           askedAt >= agreement.at || agreement.at > env.clock.now() {
            write { $0.agreement?.settled = true }
            agreementSettled?()
        }
        if let since = withdrawalUnresolvedSince, askedAt >= since { endUnresolvedWithdrawal() }
        guard let withdrawnAt, askedAt >= withdrawnAt, let version = latestPolicyVersion,
              user.consent?.policyVersion == version else { return }
        endWithdrawal()
    }

    private func endWithdrawal() {
        guard let env, !env.isDemo, let account = env.auth.accountID,
              env.defaults.object(forKey: Self.withdrawalKey(account)) != nil else { return }
        env.defaults.removeObject(forKey: Self.withdrawalKey(account))
        revision += 1
    }

    /// `DELETE /v1/me/consent` went out and no answer came (`withdrawalUnresolvedSince`): `since` is when its attempt
    /// ended. A later one without an answer moves it on: only a `/v1/me` asked for after that one resolves it.
    func withdrawalUnresolved(since: Date) {
        guard let env, !env.isDemo, let account = env.auth.accountID else { return }
        env.defaults.set(since, forKey: Self.unresolvedWithdrawalKey(account))
        revision += 1
    }

    /// The unresolved withdrawal of `account` ends: another account is on this iPhone now (`OnboardingCoordinator`'s
    /// `switchAccount`), or the current one heard RYFT (nil: the current account).
    func endUnresolvedWithdrawal(of account: String? = nil) {
        guard let env, let account = account ?? (env.isDemo ? nil : env.auth.accountID),
              env.defaults.object(forKey: Self.unresolvedWithdrawalKey(account)) != nil else { return }
        env.defaults.removeObject(forKey: Self.unresolvedWithdrawalKey(account))
        revision += 1
    }

    /// The platform refused at `code`'s gate: `consent_required` in any mode, `invite_required` only when enforced
    /// (`APIStatus` decides). Only the platform's word is recorded, never a hold the app decided.
    func refused(_ code: APIErrorCode, at: Date) {
        write { record in
            if record.refusals[code] == nil { record.refusals[code] = at }
        }
    }

    /// The platform no longer names `code`'s gate, or the account passed it (consent matching the policy, a code
    /// redeemed, `beta_access`).
    func cleared(_ code: APIErrorCode) {
        write { record in record.refusals[code] = nil }
    }

    private func write(_ change: (inout Record) -> Void) {
        guard let env, !env.isDemo, let account = env.auth.accountID, storeHoldsRecords else { return }
        var updated = record ?? Record()
        let before = updated
        change(&updated)
        guard updated != before else { return }
        env.persistence.saveDocument(updated, key: Self.key(account), at: env.clock.now())
        memo = (AccountBinding(env), updated)
        revision += 1
    }

    // MARK: the one door for /v1/config

    /// `GET /v1/config` through the read pipeline (joined with any read of it in flight). The answer is recorded
    /// inside the flight, so it lands even when the caller stopped waiting (`check()`'s timeout). Nil when nothing
    /// was sent (offline, a `Retry-After` window).
    @discardableResult
    func fetchConfig(userInitiated: Bool = false) async throws -> RemoteConfig? {
        guard let env else { return nil }
        let binding = AccountBinding(env), clock = env.clock, api = env.api
        return try await env.reads.run(ReadKey(.config), userInitiated: userInitiated,
                                       store: { [weak self] (config: RemoteConfig) in
                                           self?.received(config, at: clock.now(), binding: binding)
                                       }) { try await api.config() }
    }

    /// Before an upload holds for `policyUnknown`: one `/v1/config` read (joined with any in flight). A no-op while
    /// the policy is fresh. After a failure nothing is sent for `retryAfterFailure` and the same error is thrown, so a
    /// flapping connection asks at most once a minute.
    func revalidate() async throws {
        guard let env, !env.isDemo, env.auth.accountID != nil else { return }
        // Before the first unlock nothing could be stored: the write holds until the unlock reloads the record.
        if isPolicyFresh(at: env.clock.now()) || !isRecordReadable { return }
        let binding = AccountBinding(env)
        if let lastFailure, lastFailure.binding == binding,
           env.clock.now().timeIntervalSince(lastFailure.at) < Self.retryAfterFailure {
            throw lastFailure.error
        }
        do {
            try await fetchConfig()
            lastFailure = nil
        } catch {
            if !error.isCancellation { lastFailure = (binding, env.clock.now(), error) }
            throw error
        }
    }

    // MARK: wiring

    /// `APIStatus` reports the platform's gates here (`OnboardingCoordinator` wires it): consent in any mode, the
    /// invite only when enforced.
    func listen(to status: APIStatus) {
        status.onGate = { [weak self] code, refused in
            guard let self, let env = self.env else { return }
            if refused { self.refused(code, at: env.clock.now()) } else { self.cleared(code) }
        }
    }
}
