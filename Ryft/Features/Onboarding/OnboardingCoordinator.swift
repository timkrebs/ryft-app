// Onboarding after sign-in: the gates (invite code, consent), "about you", then
// Apple Health. `OnboardingCoordinator` decides which step is missing; RootView shows
// the steps full screen on an account's first run and as a sheet afterwards.
import Observation
import SwiftUI

/// What stands between a signed-in account and its first sync: an invite code (while
/// the beta gate is on), consent to the privacy policy in force, and "about you".
/// Apple Health follows (RootView, `HealthPermissionView`).
///
/// - **Server truth, every time.** Decided from `GET /v1/me` (access, consent, birth
///   year, account hint), `GET /v1/config` (policy version) and `GET /v1/me/sync`
///   (`gate`, also in warn mode) on every sign-in and every app start, so another
///   account lands in its own step. A step the server already has is skipped.
/// - **Gates aren't errors.** A `403 invite_required` / `consent_required`, or
///   `X-RYFT-Gate` on a served request, reaches `APIStatus`; RyftApp re-checks, and
///   the gate shows: full screen during the account's first run on this phone, as a
///   sheet over the tabs afterwards (never a reset to Welcome).
/// - **Nothing uploads before consent to the policy in force** (`uploadGate(for:write:)`,
///   the pure `gate(_:path:write:)`, asked by `SyncService`, `ActivityUploader` and
///   `TrainSyncService`; ADR 0008). Agreeing moves the flow on at the consent's `204` (this phone's agreement,
///   `ConsentState`); the gate opens, and the first sync starts, once a `GET /v1/me` asked for after it shows the consent
///   (ADR 0025).
@MainActor
@Observable
final class OnboardingCoordinator {
    enum Step: String, CaseIterable, Identifiable, Sendable {
        case invite, consent, aboutYou
        /// "What do you wear?" (`devices.setup`), before Apple Health.
        case wear
        var id: String { rawValue }
        /// A gate the platform enforces; "about you" and "what do you wear" only belong to the first run.
        var isGate: Bool { self == .invite || self == .consent }
    }

    enum Phase: Equatable, Sendable {
        case idle
        /// Asking the platform; the first run waits on a splash, at most `checkTimeout`.
        case checking
        case ready
    }

    /// What the decision is made from: the server's answers plus what this phone knows.
    struct Facts: Equatable, Sendable {
        /// `GET /v1/me` answered (now or from the cache).
        var userKnown = false
        var betaAccess = true
        var consentVersion: String?
        /// This phone's consent `204` to this version, RYFT's own word on it still out (`ConsentState.unsettledAgreement`):
        /// the flow's consent step counts it (`missing`); the upload gate holds while it's there (`gate`; ADR 0025).
        var agreedVersion: String?
        /// `GET /v1/config` → `privacy_policy_version`, the latest heard of, whatever its age (`ConsentState`);
        /// `nil` when unknown.
        var policyVersion: String?
        /// `GET /v1/me/sync` → `gate`, without a `consent_required` from a status that can't speak for consent (asked within
        /// the platform's cache time of this phone's consent `204`, `ConsentState.statusSpeaksForConsent`).
        var serverGate: APIErrorCode?
        /// Refusals and warn-mode headers since (`APIStatus.gates`), the gates `ConsentState` keeps the
        /// platform's refusal of, and this phone's withdrawal of consent (`ConsentState.withdrawnAt`).
        var reported: Set<APIErrorCode> = []
        var birthYear: Int?
        var aboutYouDone = false
        /// The birth year was just saved: the step stays to show the platform's estimate.
        var aboutYouSaved = false
        /// "What do you wear?" was answered or skipped on this phone.
        var wearAsked = false
        /// `devices.setup`: the step exists at all.
        var devicesSetup = false
        /// Demo data is on.
        var demo = false
        /// A `403 invite_required` (not a warning), this session or kept from an earlier one (`ConsentState`).
        var inviteBlocked = false
        /// The policy answer is younger than its age limit (`ConsentState.isPolicyFresh`): only then can a gate open.
        var policyFresh = false
        /// The consent record could be read (`ConsentState.isRecordReadable`; false before the first unlock).
        var recordReadable = true
        /// Profile's Withdraw consent is on its way (`isWithdrawing`): data waits, whatever RYFT's word meanwhile (security
        /// review round 2, S-1). So it does after one sent with no answer, until RYFT is heard from after it
        /// (`ConsentState.withdrawalUnresolvedSince`, round 3, S-2). A local fact that only closes (ADR 0008); the flow's
        /// steps don't count it.
        var withdrawing = false
    }

    /// The missing steps, in order. Invite only when the platform says its gate applies
    /// (with the gate off, `beta_access: false` is normal); consent whenever the account
    /// hasn't agreed to the policy in force (the stored user's consent, or this phone's agreement while RYFT's word on it
    /// is out), or the platform refused at it; "about you" until answered or skipped once; "what do you wear"
    /// likewise, while `devices.setup` is on.
    nonisolated static func missing(_ f: Facts) -> [Step] {
        var out: [Step] = []
        let inviteSignal = f.serverGate == .inviteRequired || f.reported.contains(.inviteRequired)
        if inviteSignal, !(f.userKnown && f.betaAccess) { out.append(.invite) }
        let given = { (version: String?) in f.policyVersion.map { version == $0 } ?? (version != nil) }
        let consented = given(f.consentVersion) || given(f.agreedVersion)
        let consentSignal = f.serverGate == .consentRequired || f.reported.contains(.consentRequired)
        if (f.userKnown && !consented) || consentSignal { out.append(.consent) }
        if f.userKnown, !f.aboutYouDone, f.birthYear == nil || f.aboutYouSaved { out.append(.aboutYou) }
        if f.userKnown, f.devicesSetup, !f.wearAsked { out.append(.wear) }
        return out
    }

    /// What every upload waits for (ADR 0008; design.md §4's tables), the same rule for every path:
    /// - Demo data holds HealthKit sync, whose client is the platform's (`demo`). The other paths bind every request
    ///   to demo and send it to the in-memory platform, so they're open.
    /// - A record that can't be read (before the first unlock) holds every write as `policyUnknown`.
    /// - An enforced invite gate holds every write, erasures too (the platform refuses them behind it).
    /// - An erasure (`DELETE`) goes from here on: no account known, no consent, a refusal or an unknown policy don't
    ///   hold it (Art. 17).
    /// - Data waits for the account, then the consent step (`missing`: a known mismatch, or the platform's refusal),
    ///   then a fresh policy (`policyUnknown`). Only a fresh policy the consent matches opens it: staleness can only
    ///   hold. The consent is the stored user's, the platform's own word: never this phone's agreement, which only moves
    ///   the flow (ADR 0025).
    /// - While this phone's agreement waits for RYFT's word (`agreedVersion`), data waits too, whatever the stored user
    ///   says: a consent cached from before may be one the `204` didn't renew (a refusal it cleared, code review S3).
    ///   Only a `GET /v1/me` asked for after the `204` and stored opens it (ADR 0025, decision 3).
    /// - While a withdrawal is on its way (`withdrawing`), data waits too: an answer heard meanwhile (Check with RYFT, a
    ///   reconnect, Agree's re-read) may settle the agreement, and the withdrawal is the last word (security review round
    ///   2, S-1). So it does after one sent with no answer, until RYFT is heard from after it: RYFT may have recorded it
    ///   (round 3, S-2). Only closing: once it ends, the rest decides.
    nonisolated static func gate(_ f: Facts, path: UploadPath, write: UploadWrite) -> UploadGate? {
        if f.demo { return path == .healthKit ? .demo : nil }
        guard f.recordReadable else { return .policyUnknown }
        if f.inviteBlocked { return .gate(.inviteRequired) }
        if write == .erasure { return nil }
        if f.withdrawing { return .gate(.consentRequired) }
        guard f.userKnown, f.agreedVersion == nil else { return .gate(.consentRequired) }
        if missing(f).contains(.consent) { return .gate(.consentRequired) }
        guard f.policyFresh else { return .policyUnknown }
        return nil
    }

    /// The first run waits this long for the platform, then goes on with what it knows.
    static let checkTimeout: Duration = .seconds(10)
    /// Re-checks closer together than this are answered from the last one.
    static let recheckInterval: TimeInterval = 60

    private(set) var phase: Phase = .idle
    private(set) var syncStatus: SyncStatus?
    /// When `syncStatus`'s flight was asked for: whether its `consent_required` counts (`serverGate`, R2).
    private var syncStatusAskedAt: Date?
    /// "Not now" this session; asked again on the next app start.
    private(set) var deferred: Set<Step> = []
    /// The invite field; a `ryft://invite/<code>` link fills it in.
    var inviteCode = ""
    private(set) var isWorking = false
    /// Profile's Withdraw consent, from the confirmation until the platform answered, a wait for a step's request
    /// included (`withdrawConsent()`). Every data upload waits meanwhile (`Facts.withdrawing`).
    private(set) var isWithdrawing = false
    /// One sentence for the step on screen, and its status and request ID.
    private(set) var errorMessage: String?
    private(set) var errorDetails: String?

    private let state: AppState
    private let apiStatus: APIStatus
    /// Starts a sync (after consent).
    private let startSync: @MainActor () async -> Void
    /// The launch's `GET /v1/me/sync` answer, for the sync (an operator's re-sync request), with when its flight was asked
    /// for (nil: not known): the scoring wait and the sync's ledger count from then (code review round 2, 9).
    @ObservationIgnored var statusReceived: (@MainActor (SyncStatus, Date?) -> Void)?
    private var account: String?
    /// Bumped by every `switchAccount`: a step's request still out then is the previous account's (`Flight`).
    private var turn = 0
    /// Withdrawals waiting for the step's request in flight (`perform(waitsForTurn:)`).
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []
    /// The Agree being timed for the agree line (`AgreeTiming`), until the next one or another account.
    @ObservationIgnored private var agreeTimer: AgreeTimer?
    private var lastCheck: Date?
    private var aboutYouDone = false
    /// The birth year is saved; "about you" shows the estimate until Continue.
    private(set) var aboutYouSaved = false
    private var hintSeen = false
    /// "What do you wear?" answered or skipped, and the setup screen after Apple Health left (per account).
    private(set) var wearAsked = false
    private(set) var trackerSetupDone = false

    /// This account reached the tabs on this phone once (`reachedTabs()`); per account, so
    /// another account on a phone that already allowed Apple Health still gets its steps.
    private var firstRunDone = false

    init(state: AppState, apiStatus: APIStatus, devices: TrackerSelectionStore? = nil,
         startSync: @escaping @MainActor () async -> Void) {
        self.state = state
        self.apiStatus = apiStatus
        self.startSync = startSync
        bodySettings = BodySettingsEditor(state: state)
        self.devices = devices ?? TrackerSelectionStore(env: state.env)
        // The platform's consent gate, wherever it's reported (a 403, X-RYFT-Gate, GET /v1/me/sync), is kept for the
        // account; its end too (ADR 0008).
        state.env.consent.listen(to: apiStatus)
        // RYFT's word on this phone's agreement was heard: the agree line's `confirmed`.
        state.env.consent.agreementSettled = { [weak self] in self?.agreeTimer?.heard() }
    }

    /// What the user wears: "What do you wear?" saves it, the setup screen after Apple Health reads it.
    let devices: TrackerSelectionStore

    /// About you: maximum heart rate and baseline sleep need, editable right there.
    let bodySettings: BodySettingsEditor

    private var env: AppEnvironment { state.env }
    private var api: PlatformAPI { env.api }
    private var defaults: UserDefaults { env.defaults }
    var user: User? { state.user }

    private var consent: ConsentState { env.consent }

    var facts: Facts {
        let u = user
        // The refusals kept from before show their steps as a 403 does (an enforced invite is kept, never a warning).
        let refusals = consent.refusals
        var reported = apiStatus.gates.union(refusals)
        // A withdrawal on this phone, whatever the store kept of it (a refused save, a background launch).
        if consent.withdrawnAt != nil { reported.insert(.consentRequired) }
        return Facts(userKnown: u != nil, betaAccess: u?.betaAccess ?? true, consentVersion: u?.consent?.policyVersion,
                     agreedVersion: consent.unsettledAgreement, policyVersion: consent.latestPolicyVersion,
                     serverGate: serverGate,
                     reported: reported, birthYear: u?.birthYear, aboutYouDone: aboutYouDone,
                     aboutYouSaved: aboutYouSaved, wearAsked: wearAsked, devicesSetup: env.flags.isOn(.devicesSetup),
                     demo: env.isDemo, inviteBlocked: apiStatus.inviteBlocked || refusals.contains(.inviteRequired),
                     policyFresh: consent.isPolicyFresh(at: env.clock.now()), recordReadable: consent.isRecordReadable,
                     withdrawing: withdrawalHolds)
    }

    /// A withdrawal is on its way (`isWithdrawing`), or went without an answer and RYFT hasn't been heard from since
    /// (`ConsentState.withdrawalUnresolvedSince`): every data upload waits for it (`Facts.withdrawing`).
    var withdrawalHolds: Bool { isWithdrawing || consent.withdrawalUnresolvedSince != nil }

    /// `GET /v1/me/sync` → `gate`; a `consent_required` only from a status that speaks for consent (R2: not one asked
    /// within the platform's cache time of this phone's consent `204`).
    private var serverGate: APIErrorCode? {
        guard let gate = syncStatus?.gate else { return nil }
        if gate == .consentRequired, let asked = syncStatusAskedAt, !consent.statusSpeaksForConsent(askedAt: asked) {
            return nil
        }
        return gate
    }

    var missing: [Step] {
        guard !env.isDemo, env.auth.isSignedIn else { return [] }
        return Self.missing(facts)
    }

    /// The account's first run on this phone: it hasn't reached the tabs yet.
    var isFirstRun: Bool { !firstRunDone }

    /// RootView showed the tabs: from now on a gate is a sheet over them.
    func reachedTabs() {
        guard !firstRunDone, let account = env.auth.accountID else { return }
        firstRunDone = true
        defaults.set(true, forKey: Self.key("firstRunDone", account))
        env.analytics.track(.onboardingStep(.done))
    }

    /// The first run waits for the platform's answer before showing anything (no flash of tabs).
    var holdsFirstRun: Bool { isFirstRun && phase != .ready && !env.isDemo && env.auth.isSignedIn }

    /// The gate still waiting, deferred or not: Today's "Action needed" line.
    var pendingGate: Step? { missing.first { $0.isGate } }

    /// Full screen, before the tabs (first run only).
    var flowStep: Step? {
        guard phase == .ready, isFirstRun else { return nil }
        return missing.first { !deferred.contains($0) }
    }

    /// Over the tabs: a gate that appeared after the first run.
    var sheetStep: Step? {
        get {
            guard phase == .ready, !isFirstRun, accountHint == nil else { return nil }
            return missing.first { $0.isGate && !deferred.contains($0) }
        }
        set {
            // Swiped away: "not now" for this session (the invite gate can't be, see `canDefer`).
            if newValue == nil, let shown = sheetStep, canDefer(shown) { deferred.insert(shown) }
        }
    }

    /// What `path`'s next `write` waits for: `gate(facts, path, write)` (ADR 0008). Observable: a new answer, a
    /// refusal or its end re-renders whoever read it.
    func uploadGate(for path: UploadPath, write: UploadWrite = .data) -> UploadGate? {
        Self.gate(facts, path: path, write: write)
    }

    // MARK: the policy

    /// The latest policy heard of (`ConsentState`), whatever its age: what the consent step shows and agrees to. Where
    /// the record keeps nothing (demo data, a store not readable before the first unlock), the version consent's own
    /// read brought.
    var policyVersion: String? { consent.latestPolicyVersion ?? readPolicyVersion }

    /// The version `loadPolicyIfMissing()` read, for when the record couldn't keep it.
    private var readPolicyVersion: String?

    /// Consent's read of the policy version when none is known yet (`loadPolicyIfMissing()`).
    enum PolicyRead: Equatable { case idle, loading, failed }

    private(set) var policyRead: PolicyRead = .idle

    /// Agree has a version to record: the one on screen (while it runs, the pill shows busy).
    var canAgree: Bool { policyVersion != nil }

    /// The consent step opened with no policy version: one `GET /v1/config` (joined with any read in flight), so the
    /// version agreed to is always one the screen showed. A failure leaves Agree off and the step offers Try again.
    func loadPolicyIfMissing() async {
        guard policyVersion == nil, policyRead != .loading else { return }
        policyRead = .loading
        do {
            remember(try await consent.fetchConfig(userInitiated: true))
            policyRead = policyVersion == nil ? .failed : .idle
        } catch where error.isCancellation {
            policyRead = .idle
        } catch {
            policyRead = .failed
        }
    }

    /// Where the policy is published; the in-app Safari sheet opens it.
    var policyPage: LegalPage {
        consent.policyURL.flatMap(URL.init(string:)).flatMap(LegalPage.init(url:)) ?? .privacy
    }

    /// A consent to an older policy: the consent step says what changed.
    var earlierConsent: Consent? {
        guard let consent = user?.consent, let policyVersion, consent.policyVersion != policyVersion else { return nil }
        return consent
    }

    /// The gate is only a warning (the platform serves the account), or it's consent,
    /// which the user may decline for now (nothing syncs meanwhile).
    func canDefer(_ step: Step) -> Bool {
        switch step {
        case .invite: return !apiStatus.inviteBlocked
        case .consent, .aboutYou, .wear: return true
        }
    }

    func later(_ step: Step) {
        guard canDefer(step) else { return }
        clearError()
        switch step {
        case .aboutYou: finishAboutYou()
        // Skip saves nothing: the step is answered for this account, and Profile can choose later.
        case .wear: finishWear()
        case .invite, .consent: deferred.insert(step)
        }
    }

    /// "About you" is answered (or skipped) for good on this phone; Profile can change it later.
    func finishAboutYou() {
        clearError()
        aboutYouSaved = false
        aboutYouDone = true
        defaults.set(true, forKey: key("aboutYouDone"))
    }

    /// Shows a gate again that was put off ("Action needed" on Today, Profile → Privacy).
    func show(_ step: Step) {
        deferred.remove(step)
    }

    // MARK: account hint

    /// "This is a new RYFT account": once per account, before anything else.
    var accountHint: AccountHint? {
        guard phase == .ready, !hintSeen else { return nil }
        return user?.accountHint
    }

    func keepThisAccount() {
        hintSeen = true
        defaults.set(true, forKey: key("hintSeen"))
    }

    /// Signs out, so the person can sign in the way they did before.
    func useOtherAccount() async {
        keepThisAccount()
        await env.auth.signOut()
    }

    // MARK: checking

    /// Asks the platform what's missing: at launch (restored session) and after every
    /// sign-in, when a gate is reported, and after each step. `changedSince`: the account's answer must have been
    /// asked for after then (a withdrawal's re-check), never one already in flight. While this phone's agreement waits
    /// for RYFT's word (its re-read failed), or a withdrawal had no answer (S-2), every check asks: never answered from
    /// the last one, and `/v1/me` asked for after the agreement or the withdrawal. `userInitiated` (Profile's Check with RYFT): its reads don't wait out a `Retry-After`.
    func check(force: Bool = false, changedSince: Date? = nil, userInitiated: Bool = false) async {
        guard !env.isDemo, env.auth.isSignedIn else {
            phase = .ready
            return
        }
        let account = env.auth.accountID
        if account != self.account { switchAccount(account) }
        let unsettled = consent.pendingAgreement
        // A withdrawal without an answer the same way: every check asks, `/v1/me` asked for after it (security review
        // round 3, S-2).
        let unresolved = consent.withdrawalUnresolvedSince
        if !force, phase == .ready, let lastCheck, unsettled == nil, unresolved == nil,
           env.clock.now().timeIntervalSince(lastCheck) < Self.recheckInterval { return }
        // Offline: the cached account decides; the next start (or a gate) asks again.
        guard env.connectivity.isOnline else {
            phase = .ready
            return
        }
        if phase != .ready { phase = .checking }
        let since = changedSince ?? [unsettled?.at, unresolved].compactMap { $0 }.max()
        let answer = await fetchWithTimeout(changedSince: since, userInitiated: userInitiated)
        // Signed out or another account meanwhile: that answer isn't theirs.
        guard env.auth.accountID == account else { return }
        // Written through inside its read (and the time zone's PATCH): the gates below decide from it in this step
        // (ADR 0008, 0018). The Repository's, not the answer: one asked for before this phone changed the user (a
        // withdrawal) was dropped there, and its consent mustn't clear a gate here either.
        let user = answer.user == nil ? nil : state.repository.user()
        // The config was recorded inside its read (`ConsentState.fetchConfig`).
        var refusesConsent = false
        if let status = answer.status {
            syncStatus = status
            syncStatusAskedAt = answer.statusAskedAt
            state.setSyncStatus(status, askedAt: answer.statusAskedAt)
            statusReceived?(status, answer.statusAskedAt)
            // R2: asked within the platform's cache time of this phone's consent `204`, it may be from before it, so it
            // says nothing about consent either way. Its other fields count, the invite's gate too.
            let speaks = answer.statusAskedAt.map(consent.statusSpeaksForConsent(askedAt:)) ?? true
            // The platform no longer reports a gate this phone still remembers: it's passed.
            // Kept for the account (`ConsentState`): `consent_required` here as anywhere. `invite_required` here
            // can't tell warn from enforced, so it's never kept (a warn-mode invite doesn't hold uploads).
            switch status.gate {
            case nil:
                apiStatus.resolved(.inviteRequired)
                if speaks { apiStatus.resolved(.consentRequired) }
            case .consentRequired?:
                apiStatus.resolved(.inviteRequired)
                if speaks {
                    consent.refused(.consentRequired, at: env.clock.now())
                    refusesConsent = true
                }
            // The App Attest codes are never a `gate` (API.md → Errors → App Attest).
            case .inviteRequired?, .importInProgress?, .importNotEnabled?, .appAttestRequired?,
                 .appAttestChallengeInvalid?, .appAttestInvalid?, .appAttestKeyUnknown?:
                break
            }
        }
        // This same check's answers show a gate kept from before is passed, and its status didn't name it: the
        // account's consent matches the policy it heard, or the account has beta access.
        if let user, !refusesConsent,
           let version = answer.config?.privacyPolicyVersion, user.consent?.policyVersion == version {
            consent.cleared(.consentRequired)
        }
        if let user, user.betaAccess, answer.status?.gate != .inviteRequired {
            consent.cleared(.inviteRequired)
        }
        lastCheck = env.clock.now()
        phase = .ready
    }

    private struct Answer: Sendable {
        var user: User?
        var config: RemoteConfig?
        var status: SyncStatus?
        /// When the status's flight was asked for (a joined flight's start).
        var statusAskedAt: Date?
    }

    /// The three reads at once, through the read pipeline (joined with the launch's own reads of
    /// the same resources). Failures leave a part unknown (the cache decides); the first run gives
    /// up waiting after `checkTimeout`.
    private func fetchWithTimeout(changedSince: Date?, userInitiated: Bool) async -> Answer {
        let api = api, clock = env.clock, reads = env.reads, state = state, consent = consent
        let tz = TimeZone.current.identifier
        let meMode: ReadMode = changedSince.map { .changed(since: $0) } ?? .latest
        return await withTaskGroup(of: Answer?.self) { group in
            group.addTask {
                // The user is stored inside the read, so it lands even when the timeout wins.
                async let me = try? reads.run(ReadKey(.me), mode: meMode, userInitiated: userInitiated,
                                              storeAsked: { (user: User, asked: Date) in
                    await state.repository.store(fetchedUser: user, askedAt: asked).committed()
                }) {
                    try await api.me()
                }
                // The one door for the config: recorded inside the read, so it lands even when the timeout wins.
                async let config = try? consent.fetchConfig(userInitiated: userInitiated)
                // The same mode: after a withdrawal, a status asked for before it would say no gate. With when its flight
                // was asked for, without taking over its store (the sync's poll may have started it): R2 decides by it.
                async let status = try? reads.runAsked(ReadKey(.syncStatus), mode: meMode, userInitiated: userInitiated) {
                    try await api.syncStatus()
                }
                var user = await me
                // New users start in Europe/Berlin, which defines every day boundary.
                if let u = user, u.tz != tz {
                    let change = await state.repository.userChange()
                    if let patched = try? await api.patchMe(UserPatch(tz: tz)) {
                        await state.repository.store(user: patched, asOf: change).committed()
                        user = patched
                    }
                }
                let answered = await status
                return Answer(user: user, config: await config, status: answered?.value, statusAskedAt: answered?.asked)
            }
            group.addTask {
                try? await clock.sleep(for: Self.checkTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? Answer()
        }
    }

    /// Another account (or signed out): its steps are its own. Gates reported before
    /// the first check belong to the account the app launched with, so they stay.
    /// A step's request still out then is the previous account's: this one's steps aren't busy with it, and its answer
    /// touches nothing here (`perform`). One sent before the first check is the launch account's too. A withdrawal
    /// waiting for it ends unsent: never with this account's session. The invite field is the previous account's too
    /// (security review N-1): a code it typed or a link filled in, sent or not, is never the next account's to redeem.
    /// From no account (the launch's first check, a sign-in) it stays: a link opened at launch is the launch account's,
    /// and one that arrived signed out waits in `DeepLinkRouter.pending` until after this switch.
    func switchAccount(_ account: String?) {
        // Another account, or none: the previous account's withdrawal without an answer ends with it (security review
        // round 3, S-2). Never from no account: the launch's first check keeps the launch account's.
        if let old = self.account, old != account { consent.endUnresolvedWithdrawal(of: old) }
        if self.account != nil {
            apiStatus.resetGates()
            turn += 1
            isWorking = false
            isWithdrawing = false
            inviteCode = ""
            resumeWaiting()
        }
        self.account = account
        syncStatus = nil
        syncStatusAskedAt = nil
        agreeTimer = nil
        deferred = []
        lastCheck = nil
        clearError()
        phase = .idle
        aboutYouSaved = false
        readPolicyVersion = nil
        policyRead = .idle
        firstRunDone = account.map { defaults.bool(forKey: Self.key("firstRunDone", $0)) } ?? false
        aboutYouDone = account.map { defaults.bool(forKey: Self.key("aboutYouDone", $0)) } ?? false
        hintSeen = account.map { defaults.bool(forKey: Self.key("hintSeen", $0)) } ?? false
        wearAsked = account.map { defaults.bool(forKey: Self.key("wearAsked", $0)) } ?? false
        trackerSetupDone = account.map { defaults.bool(forKey: Self.key("trackerSetupDone", $0)) } ?? false
    }

    // MARK: steps

    /// `POST /v1/me/invite`. One message for every bad code, as the platform answers.
    @discardableResult
    func redeemInvite() async -> Bool {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return false }
        return await perform { sent in
            try await self.api.redeemInvite(code: code)
            try self.answered(sent)
            self.apiStatus.resolved(.inviteRequired)
            self.inviteCode = ""
            await self.check(force: true)
        } message: { error in
            switch (error as? APIError)?.status {
            case 422: return String(localized: "This code doesn't work. Ask the person who invited you for a new one.")
            case 429: return String(localized: "Too many tries. Wait an hour, then try the code again.")
            default: return nil
            }
        }
    }

    /// The version a config read brought, for when the record can't keep it (demo data).
    private func remember(_ config: RemoteConfig?) {
        if let version = config?.privacyPolicyVersion { readPolicyVersion = version }
    }

    /// The policy changed between drawing the step and agreeing: the new one is on screen now.
    private struct PolicyChangedOnScreen: Error {}

    /// `POST /v1/me/consent` for the policy version on screen (`shown`: the one the step drew; nil takes the current
    /// one), then the first sync. Nothing without a version, or when `shown` isn't the current one any more; a stale
    /// version is checked first, and a newer policy is shown, not agreed to.
    ///
    /// The `204` is this phone's agreement (`ConsentState.consented`): the next step shows in that step, and `isWorking`
    /// ends with it. RYFT's own word follows outside `perform`: one `GET /v1/me` asked for at or after the `204`
    /// (`Repository.readUserBack`), stored through, settles it, and its consent opens the upload gate (ADR 0025). Only
    /// then, still for this account (`Flight`), does the first sync start. A re-read that fails leaves the next step on
    /// screen, without a word, and the gate closed; every later `check()` asks again, and so does coming back online
    /// (`reconnected()`). True once that's done, for this account.
    ///
    /// The POST fails fast, as the withdrawal does (`failingFast`): offline nothing is sent and it says so at once; a
    /// `503` or `429` is said in `APIError`'s words. Sent with no answer (`Unanswered`), RYFT is asked what it holds
    /// (`/v1/me` only): consent to this version there is the `204` that didn't come, recorded settled; otherwise
    /// `consentUnansweredMessage` (trying again is safe: a repeat keeps the first `granted_at`).
    @discardableResult
    func agree(shown: String? = nil) async -> Bool {
        guard let version = policyVersion, shown == nil || shown == version else { return false }
        // A step's request is out, or this version's agreement is being confirmed with the step gone (the re-read below
        // doesn't hold `isWorking`): this tap sends nothing, and the agree line counts it.
        if isWorking || (consent.unsettledAgreement == version && !missing.contains(.consent)) {
            agreeTimer?.busyTap()
            return false
        }
        let timer = startAgreeTimer(session: .failFast)
        let going = flight
        // For the failure's sentence: the step it belongs to, at the tap (`tieErrorToConsentStep(wasMissing:)`).
        let consentWasMissing = missing.contains(.consent)
        var agreedAt: Date?
        // RYFT's word was heard inside `perform`: the POST had no answer, and the re-read showed the consent.
        var heardInside = false
        let ok = await perform { sent in
            if !self.consent.isPolicyFresh(at: self.env.clock.now()) {
                timer?.readsPolicy()
                // Nil: nothing was sent (offline, a Retry-After window).
                guard let fresh = try await self.consent.fetchConfig(userInitiated: true) else {
                    throw URLError(.notConnectedToInternet)
                }
                try self.answered(sent)
                guard fresh.privacyPolicyVersion == version else {
                    self.remember(fresh)
                    throw PolicyChangedOnScreen()
                }
            }
            timer?.sent()
            let sentAt = self.env.clock.now()
            do {
                try await self.failingFast { try await self.api.consent(policyVersion: version, appVersion: AppInfo.version) }
                timer?.answered(204, requests: self.apiStatus.requests)
            } catch is Unanswered {
                timer?.answered(0, requests: self.apiStatus.requests)
                // A cancelled or unanswered request isn't an unsent one: RYFT may have recorded it. Asked what it holds,
                // `/v1/me` only, still inside `perform` (the failure path only): the step stays busy meanwhile.
                try self.answered(sent)
                timer?.confirming()
                let read = await self.askAgain(since: sentAt)
                try self.answered(sent)
                guard read, self.state.repository.user()?.consent?.policyVersion == version else {
                    timer?.committed(read ? "no_consent" : "none")
                    throw Unanswered()
                }
                // It arrived: the 204 that didn't come, with RYFT's word already heard.
                timer?.heard()
                heardInside = true
            } catch {
                timer?.answered(AgreeTiming.status(of: error), requests: self.apiStatus.requests)
                throw error
            }
            try self.answered(sent)
            // In force now (the platform answers 422 otherwise): an answer, good for the usual ttl, and this phone's
            // agreement. The flow moves on here; nothing is awaited after it, so `isWorking` ends in the same step.
            let at = self.env.clock.now()
            self.consent.consented(to: version, at: at, settled: heardInside)
            self.apiStatus.resolved(.consentRequired)
            self.deferred.remove(.consent)
            timer?.stepRecorded()
            agreedAt = at
        } message: { error in
            if error is Unanswered { return Self.consentUnansweredMessage }
            let updated = String(localized: "The privacy policy was just updated. Read the new version, then agree again.")
            if error is PolicyChangedOnScreen { return updated }
            guard (error as? APIError)?.status == 422 else { return nil }
            // The platform refused an older policy than the one in force: read and show the new one.
            Task { [weak self] in
                guard let self else { return }
                remember(try? await consent.fetchConfig(userInitiated: true))
            }
            return updated
        }
        guard ok, let agreedAt, going == flight else {
            // The path ended for this account: its line, and its sentence stays with the consent step.
            if going == flight {
                timer?.save(in: env)
                tieErrorToConsentStep(wasMissing: consentWasMissing)
            }
            return false
        }
        // RYFT's own word: `/v1/me` only, neither the config nor the status. Not again when the no-answer path heard it.
        let word: String, read: Bool
        if heardInside {
            read = true
            word = confirmation(of: version, read: true)
        } else {
            timer?.confirming()
            do {
                read = try await state.repository.readUserBack(since: agreedAt)
                word = confirmation(of: version, read: read)
            } catch {
                read = false
                word = error.isCancellation ? "dropped" : "failed \(AgreeTiming.status(of: error))"
            }
        }
        // Signed out, another account or Demo data meanwhile: nothing of this one goes on, no line and no sync.
        guard going == flight else { return false }
        timer?.committed(word)
        // The path ended for this account: its line, before the sync it starts.
        timer?.save(in: env)
        // Not while a withdrawal is on its way (security review N-1): RYFT's word may have come before the DELETE's
        // answer, and the withdrawal is the last word.
        if read, !isWithdrawing, uploadGate(for: .healthKit) == nil { await startSync() }
        return true
    }

    /// The agree line's `confirmed` after the re-read: RYFT's word as stored (`ok`, `no_consent`), nothing sent (`none`), or
    /// a re-read that settled nothing (`dropped`: the store didn't take it after a withdrawal or a profile write meanwhile,
    /// the agreement went with a withdrawal, or the clock was set back since the agreement).
    private func confirmation(of version: String, read: Bool) -> String {
        guard read else { return "none" }
        guard let agreement = consent.agreement, agreement.version == version, agreement.settled else { return "dropped" }
        return state.repository.user()?.consent?.policyVersion == version ? "ok" : "no_consent"
    }

    /// Back online: an agreement RYFT hasn't confirmed yet (its re-read failed), or a withdrawal without an answer
    /// (security review round 3, S-2), is asked about again (RyftApp). Nothing else: the launch, a foreground return and a
    /// gate ask on their own.
    func reconnected() async {
        guard consent.unsettledAgreement != nil || consent.withdrawalUnresolvedSince != nil else { return }
        await check()
    }

    /// Profile's Check with RYFT: as coming back online asks (`reconnected()`), asked for by the person, so a `Retry-After`
    /// window doesn't hold it (code review round 2, 3). True when RYFT's word on the agreement is in (or nothing waits for
    /// it); false when it didn't come (offline, no answer within `checkTimeout`, a failure).
    @discardableResult
    func confirmAgreement() async -> Bool {
        guard consent.unsettledAgreement != nil else { return true }
        await check(userInitiated: true)
        return consent.unsettledAgreement == nil
    }

    /// A new Agree is timed from here (nothing signed out or in demo mode).
    private func startAgreeTimer(session: AgreeTiming.Session) -> AgreeTimer? {
        guard !env.isDemo, let account = env.auth.accountID else { return nil }
        let timer = AgreeTimer(env: env, account: account, session: session)
        agreeTimer = timer
        return timer
    }

    /// RootView: the onboarding step on screen changed (`flowStep ?? sheetStep`). After an Agree, the next one (or none:
    /// the sheet went) is the agree line's `shown` (`Signposts.onboarding` `step-shown`).
    func stepShown(_ step: Step?) {
        guard step != .consent, let timer = agreeTimer, timer.shown() else { return }
        // The path ended before the step showed: its line again, now with `shown`.
        if timer.isSaved { timer.save(in: env) }
    }

    /// `PATCH /v1/me {birth_year}`: the platform answers with its max-HR estimate, which
    /// the step shows before `finishAboutYou()`.
    @discardableResult
    func saveAboutYou(birthYear: Int) async -> Bool {
        await perform { sent in
            // Stored only for the account it was asked for (a sign-out while it's out drops it).
            let change = self.state.repository.userChange()
            let patched = try await self.api.patchMe(UserPatch(birthYear: birthYear))
            try self.answered(sent)
            await self.state.repository.store(user: patched, asOf: change).committed()
            try self.answered(sent)
            self.aboutYouSaved = true
        } message: { error in
            (error as? APIError)?.isFieldError == true
                ? String(localized: "Choose a year between 1920 and \(Self.latestBirthYear(now: self.env.clock.now())).")
                : nil
        }
    }

    /// Profile → Privacy: `DELETE /v1/me/consent`. Syncing stops; nothing is deleted. Never dropped for a step's request
    /// still out (an Agree's POST, an invite, About you): it waits for that one's answer and then goes, so it's the
    /// last word on the platform and on this phone, and Profile shows its failure (security review N-B). A sign-out or
    /// another account meanwhile ends it unsent: A's withdrawal never goes out with B's session. A second one while
    /// this one is on its way sends nothing (Profile's row is busy). An Agree's re-read holds no turn: the withdrawal goes at
    /// once, removes the agreement (`ConsentState.withdrew`), and the re-read's late answer is dropped (the Repository
    /// takes no `/v1/me` asked before this phone's change of the user). It fails fast (`failingFast`): Profile holds
    /// Demo data and Log out meanwhile, for seconds, not for a request's 5 minutes. `onRecorded` runs once the platform's
    /// answer is recorded on this phone, before the re-check (Profile's hold ends then, and VoiceOver hears it, security
    /// review N-3); true is returned only after the re-check. Sent with no answer (`Unanswered`), RYFT is asked what it
    /// holds: without the consent, the withdrawal arrived and is recorded as an answered one; with it, Profile says it may
    /// still have arrived (`withdrawalUnansweredMessage`). Without an answer, data waits until RYFT is heard from after the
    /// attempt ended (`ConsentState.withdrawalUnresolvedSince`, security review round 3, S-2).
    @discardableResult
    func withdrawConsent(onRecorded: @MainActor () -> Void = {}) async -> Bool {
        guard !isWithdrawing else { return false }
        isWithdrawing = true
        let started = turn
        defer { if started == turn { isWithdrawing = false } }
        return await perform(waitsForTurn: true) { sent in
            let change = self.state.repository.userChange()
            var reread = false
            do {
                try await self.failingFast { try await self.api.revokeConsent() }
            } catch is Unanswered {
                // A cancelled or unanswered request isn't an unsent one: RYFT may have recorded it. Asked what it holds
                // (`/v1/me` only, as Agree asks), so Privacy shows that (security review round 3, A). The consent sheet
                // waits meanwhile: a withdrawal that arrived is never asked about again on its own, as below.
                try self.answered(sent)
                // RYFT may have recorded it: every data upload waits until RYFT is heard from after the attempt ended,
                // here, after a relaunch and in a background launch (security review round 3, S-2). Set before
                // `isWithdrawing` ends, so the hold never lapses in between.
                let cancelledAt = self.env.clock.now()
                self.consent.withdrawalUnresolved(since: cancelledAt)
                let wasDeferred = self.deferred.contains(.consent)
                self.deferred.insert(.consent)
                // Asked for after the attempt ended: one asked earlier may be from before RYFT recorded the DELETE. Its
                // answer settles no agreement (security review round 2, S-1): RYFT may record the DELETE after it.
                let read = await self.askAgain(since: cancelledAt, settles: false)
                try self.answered(sent)
                let user = read ? self.state.repository.user() : nil
                // The consent still there, or not read: it may still arrive, and trying again makes sure (a withdrawal
                // is idempotent).
                guard let user, user.consent == nil else {
                    // The sheet may ask again only when RYFT answered and still shows the consent. Not read in time,
                    // the read's late answer may show the withdrawal arrived, and the consent sheet mustn't open over
                    // Profile on its own (code review round 2, 1).
                    if user != nil, !wasDeferred { self.deferred.remove(.consent) }
                    throw Unanswered()
                }
                // Gone: it arrived. Recorded as an answered one, with the re-read already done.
                reread = true
            }
            // A's withdrawal answered after a sign-out: never recorded as B's.
            try self.answered(sent)
            let revokedAt = self.env.clock.now()
            // Withdrawn now, whatever the re-check below manages: sync stops at once. Kept outside the store too, so a
            // save the store refuses, or a launch that never checks, can't open the gate again (`ConsentState`).
            self.consent.withdrew(at: revokedAt)
            // Written through: every upload gate is closed from this step on, before the commit (ADR 0008, 0018), and a
            // `/v1/me` or `PATCH /v1/me` begun before now can't bring the consent back.
            self.state.repository.storeConsentWithdrawn(asOf: change)
            // Asked again only when the user wants to (Profile → Privacy, Today's action). Not a read already in
            // flight: it may have been answered before the withdrawal.
            self.deferred.insert(.consent)
            onRecorded()
            if !reread { await self.check(force: true, changedSince: revokedAt) }
        } message: { $0 is Unanswered ? Self.withdrawalUnansweredMessage : nil }
    }

    /// A consent or a withdrawal sent, with no answer in time (`failingFast`), and RYFT, asked again, not showing it
    /// arrived (or not reached).
    private struct Unanswered: Error {}

    /// RYFT asked what it holds after a consent or a withdrawal went out with no answer (`Unanswered`): one `GET /v1/me`
    /// asked for at or after `since` (`Repository.readUserBack`), waited for at most `checkTimeout`, as the first run
    /// waits (code review S1: on its own, the read's three attempts could keep the step busy for over a minute). True
    /// when that read answered in time. Only the wait ends: the read goes on in the read pipeline, which stores its
    /// answer inside the flight, so a late one still lands and the next check sees it. `settles`: whether that answer
    /// may settle this phone's agreement (a withdrawal's doesn't).
    private func askAgain(since: Date, settles: Bool = true) async -> Bool {
        let repository = state.repository, clock = env.clock
        return await withTaskGroup(of: Bool?.self) { group in
            group.addTask { (try? await repository.readUserBack(since: since, settles: settles)) ?? false }
            group.addTask {
                try? await clock.sleep(for: Self.checkTimeout)
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first.flatMap { $0 } ?? false
        }
    }

    /// Under Agree and continue when `POST /v1/me/consent` went out but no answer came in time: RYFT may have it.
    nonisolated static var consentUnansweredMessage: String {
        String(localized: "RYFT didn't answer in time. Your consent may still have arrived; try again to be sure.",
               comment: "Onboarding → Consent, under Agree and continue: sent, no answer in time, and RYFT, asked again, didn't show the consent.")
    }

    /// Under Withdraw consent when `DELETE /v1/me/consent` went out but no answer came in time: RYFT may have it.
    nonisolated static var withdrawalUnansweredMessage: String {
        String(localized: "RYFT didn't answer in time. Your withdrawal may still have arrived; try again to be sure.",
               comment: "Profile → Privacy, under Withdraw consent: the request went out but no answer came in time (a timeout, the connection lost meanwhile), and RYFT still showed the consent when asked again.")
    }

    /// `send` (`POST` or `DELETE /v1/me/consent`) as a settings write sends it (`SettingsWrite`, security review S-2).
    /// Offline, nothing is sent and it fails at once ("No connection…"). Online, it is one attempt on the fail-fast
    /// session (no waiting for a network, no `429` or `503` loop; the `401` refresh and the App Attest retry stay), with
    /// an answer within `SettingsWrite.deadline` or none. Whatever may have reached RYFT without an answer
    /// (`SettingsWriteFailure.noAnswer`: no answer in time, the session's own timeout, the network gone while it was out)
    /// is `Unanswered`, never "No connection": the caller asks RYFT again. Before, both went on the default session,
    /// which waits up to 5 minutes for a network.
    private func failingFast(_ send: @escaping @MainActor () async throws -> Void) async throws {
        guard env.connectivity.isOnline else { throw APIError.transport(URLError(.notConnectedToInternet)) }
        do {
            try await SettingsWrite.answer(in: env, send)
        } catch where !error.isCancellation && SettingsWriteFailure(error) == .noAnswer {
            throw Unanswered()
        }
    }

    /// RYFT's minimum age (Art. 8 GDPR, Germany). The platform checks `birth_year ≤ this year − 16`.
    nonisolated static let minimumAge = 16

    /// The oldest birth year offered (the platform's lower bound).
    nonisolated static let earliestBirthYear = 1920

    /// The youngest birth year offered (`this year − minimumAge`).
    nonisolated static func latestBirthYear(now: Date) -> Int {
        Calendar.current.component(.year, from: now) - minimumAge
    }

    /// Every birth year offered in onboarding and Profile, newest first.
    nonisolated static func birthYears(now: Date) -> [Int] {
        Array(stride(from: latestBirthYear(now: now), through: earliestBirthYear, by: -1))
    }

    func clearError() {
        errorMessage = nil
        errorDetails = nil
        consentErrorWatch = nil
    }

    /// Watches the consent step while Agree's failure is on screen (`tieErrorToConsentStep(wasMissing:)`).
    @ObservationIgnored private var consentErrorWatch: ObservationWatch?

    /// Agree's failure belongs to the consent step: once `.consent` leaves `missing` (RYFT's late answer showed the
    /// consent, or it was given elsewhere), its sentence goes too, and doesn't stay on About you or Privacy (code review
    /// round 2, 2). `wasMissing`: the step was missing at the tap. Gone by the failure, it left during the flight: the
    /// sentence goes at once. A step `missing` never counted (no account known yet) keeps it: nothing left.
    private func tieErrorToConsentStep(wasMissing: Bool) {
        guard errorMessage != nil, wasMissing else { return }
        guard missing.contains(.consent) else { return clearError() }
        consentErrorWatch = ObservationWatch(read: { [weak self] in _ = self?.missing }, changed: { [weak self] in
            guard let self, !missing.contains(.consent) else { return }
            clearError()
        })
    }

    /// The banner's words for a failure the step has none of its own for (PR 6 A §A-7): not reaching the platform says
    /// so (the sentence `AuthMessage` uses); `APIError`'s own sentences stay (429, 503, …); a server's text, an answer
    /// that didn't decode and anything unknown say only that it didn't work. The details (request ID) stay behind Details.
    nonisolated static func fallbackMessage(for error: Error) -> String {
        let offline = String(localized: "No connection. Check your internet and try again.")
        let other = String(localized: "Something went wrong. Please try again.")
        if let api = error as? APIError {
            if case .transport = api { return offline }
            return hasOwnWords(api) ? api.localizedDescription : other
        }
        return error is URLError || (error as NSError).domain == NSURLErrorDomain ? offline : other
    }

    /// `APIError`'s own, vetted sentences (`APIError.errorDescription`): the rest there is the server's text, or a bare
    /// status. `app_attest_required` too: the invite and the consent aren't exempt from App Attest (API.md → App Attest →
    /// Exempt), and on an iPhone that can't verify the app trying again won't help (ADR 0023).
    private nonisolated static func hasOwnWords(_ error: APIError) -> Bool {
        switch error {
        case .notConfigured, .signedOut: return true
        case .http(401, _, _, _, _), .http(429, _, _, _, _), .http(500, _, _, _, _), .http(503, _, _, _, _): return true
        case .http(403, _, _, .inviteRequired?, _), .http(403, _, _, .consentRequired?, _), .http(403, _, _, nil, _): return true
        case .http(403, _, _, .appAttestRequired?, _): return true
        case .http, .transport: return false
        }
    }

    // MARK: private

    /// The account a step's request went out for: its binding then, and the switches since. What the step does with the
    /// answer (gates, consent, the field, its error) it does only while that's still the account here (`answered(_:)`).
    private struct Flight: Equatable {
        let binding: AccountBinding
        let turn: Int
    }

    private var flight: Flight { Flight(binding: AccountBinding(env), turn: turn) }

    /// `sent`'s answer came after a sign-out, another account or Demo data: it ends as a cancellation does, and touches
    /// nothing of the account here now.
    private func answered(_ sent: Flight) throws {
        guard sent == flight else { throw CancellationError() }
    }

    /// One step's request at a time: a second Continue or Agree while one is out sends nothing and changes nothing (the busy
    /// pill takes no tap either, but the coordinator doesn't count on its view). `waitsForTurn` (a withdrawal) waits for
    /// the one out instead, unless the account changes meanwhile. The body checks its flight after each answer; a flight
    /// that isn't this account's any more says nothing, and frees nothing `switchAccount` freed already: A's late answer
    /// never shows on B's step, nor ends B's request (review code N6).
    private func perform(waitsForTurn: Bool = false, _ body: @MainActor (Flight) async throws -> Void,
                         message: (Error) -> String?) async -> Bool {
        let sent = flight
        while waitsForTurn, isWorking, sent == flight {
            await withCheckedContinuation { waiting.append($0) }
        }
        guard !isWorking, sent == flight else { return false }
        isWorking = true
        clearError()
        defer {
            if sent.turn == turn {
                isWorking = false
                resumeWaiting()
            }
        }
        do {
            try await body(sent)
            return sent == flight
        } catch where error.isCancellation {
            return false
        } catch {
            guard sent == flight else { return false }
            errorMessage = message(error) ?? Self.fallbackMessage(for: error)
            errorDetails = error.diagnosticDetails
            env.analytics.track(.errorShown(for: error))
            return false
        }
    }

    /// The step's request ended, or the account went: each withdrawal waiting looks again (`perform`).
    private func resumeWaiting() {
        let resumed = waiting
        waiting = []
        resumed.forEach { $0.resume() }
    }

    private func key(_ name: String) -> String { Self.key(name, account ?? "signed-out") }

    private static func key(_ name: String, _ account: String) -> String { "onboarding.\(name).\(account)" }
}

extension AccountHint: Identifiable {
    var id: Date { otherLastSync }
}

// MARK: - what do you wear (devices.setup)

extension OnboardingCoordinator {
    /// Continue on "What do you wear?": the choice, saved for this account (Skip is `later(.wear)`).
    func answerWear(_ ids: [String]) {
        devices.set(ids)
        finishWear()
    }

    /// "What do you wear?" is answered or skipped for good on this phone; Profile → Devices & sync changes it.
    func finishWear() {
        wearAsked = true
        defaults.set(true, forKey: key("wearAsked"))
    }

    /// The chosen trackers that need setting up in an app of their own (not the Apple Watch, not the iPhone).
    var setupTrackers: [Tracker] {
        let catalog = env.trackerCatalog
        return devices.trackers.compactMap(catalog.tracker).filter(TrackerSelectionStore.needsSetup)
    }

    /// After Apple Health access, once per account (design.md §8): the cards of the trackers to set up.
    var showsTrackerSetup: Bool {
        phase == .ready && env.flags.isOn(.devicesSetup) && isFirstRun && !trackerSetupDone && !env.isDemo
            && env.auth.isSignedIn && !setupTrackers.isEmpty
    }

    /// A deleted account's answers to "What do you wear?" and the setup screen leave this phone too.
    func forgetTrackerSteps(of account: String) {
        defaults.removeObject(forKey: Self.key("wearAsked", account))
        defaults.removeObject(forKey: Self.key("trackerSetupDone", account))
    }

    /// Done (the guides count as set up, but those put off) or "Show me again later" (all of them, for
    /// Profile → Devices & sync); then the tabs.
    func finishTrackerSetup(later: Bool) {
        for tracker in setupTrackers {
            if later {
                devices.markLater(tracker.id)
            } else if !devices.isLater(tracker.id) {
                devices.markSetUp(tracker.id)
            }
        }
        trackerSetupDone = true
        defaults.set(true, forKey: key("trackerSetupDone"))
    }
}
