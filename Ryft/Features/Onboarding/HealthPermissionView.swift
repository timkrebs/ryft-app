// Onboarding after sign-in: the gates (invite code, consent), "about you", then
// Apple Health. `OnboardingCoordinator` decides which step is missing; RootView shows
// the steps full screen on an account's first run and as a sheet afterwards.
import GameplayKit
import Observation
import SwiftUI
import UIKit

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
/// - **Nothing syncs before consent** (`syncGate`, read by `SyncService`); after
///   agreeing, the first sync starts at once.
@MainActor
@Observable
final class OnboardingCoordinator {
    enum Step: String, CaseIterable, Identifiable, Sendable {
        case invite, consent, aboutYou
        var id: String { rawValue }
        /// A gate the platform enforces; "about you" only belongs to the first run.
        var isGate: Bool { self != .aboutYou }
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
        /// `GET /v1/config` → `privacy_policy_version`; `nil` when unknown.
        var policyVersion: String?
        /// `GET /v1/me/sync` → `gate`.
        var serverGate: APIErrorCode?
        /// Refusals and warn-mode headers since (`APIStatus.gates`).
        var reported: Set<APIErrorCode> = []
        var birthYear: Int?
        var aboutYouDone = false
        /// The birth year was just saved: the step stays to show the platform's estimate.
        var aboutYouSaved = false
    }

    /// The missing steps, in order. Invite only when the platform says its gate applies
    /// (with the gate off, `beta_access: false` is normal); consent whenever the account
    /// hasn't agreed to the policy in force; "about you" until answered or skipped once.
    nonisolated static func missing(_ f: Facts) -> [Step] {
        var out: [Step] = []
        let inviteSignal = f.serverGate == .inviteRequired || f.reported.contains(.inviteRequired)
        if inviteSignal, !(f.userKnown && f.betaAccess) { out.append(.invite) }
        let consented = f.policyVersion.map { f.consentVersion == $0 } ?? (f.consentVersion != nil)
        let consentSignal = f.serverGate == .consentRequired || f.reported.contains(.consentRequired)
        if (f.userKnown && !consented) || consentSignal { out.append(.consent) }
        if f.userKnown, !f.aboutYouDone, f.birthYear == nil || f.aboutYouSaved { out.append(.aboutYou) }
        return out
    }

    /// The first run waits this long for the platform, then goes on with what it knows.
    static let checkTimeout: Duration = .seconds(10)
    /// Re-checks closer together than this are answered from the last one.
    static let recheckInterval: TimeInterval = 60

    private(set) var phase: Phase = .idle
    private(set) var config: RemoteConfig?
    private(set) var syncStatus: SyncStatus?
    /// "Not now" this session; asked again on the next app start.
    private(set) var deferred: Set<Step> = []
    /// The invite field; a `ryft://invite/<code>` link fills it in.
    var inviteCode = ""
    private(set) var isWorking = false
    /// One sentence for the step on screen, and its status and request ID.
    private(set) var errorMessage: String?
    private(set) var errorDetails: String?

    private let state: AppState
    private let apiStatus: APIStatus
    /// Starts a sync (after consent).
    private let startSync: @MainActor () async -> Void
    /// The launch's `GET /v1/me/sync` answer, for the sync (an operator's re-sync request).
    @ObservationIgnored var statusReceived: (@MainActor (SyncStatus) -> Void)?
    private var account: String?
    private var lastCheck: Date?
    private var aboutYouDone = false
    /// The birth year is saved; "about you" shows the estimate until Continue.
    private(set) var aboutYouSaved = false
    private var hintSeen = false

    /// This account reached the tabs on this phone once (`reachedTabs()`); per account, so
    /// another account on a phone that already allowed Apple Health still gets its steps.
    private var firstRunDone = false

    init(state: AppState, apiStatus: APIStatus, startSync: @escaping @MainActor () async -> Void) {
        self.state = state
        self.apiStatus = apiStatus
        self.startSync = startSync
        bodySettings = BodySettingsEditor(state: state)
    }

    /// About you: maximum heart rate and baseline sleep need, editable right there.
    let bodySettings: BodySettingsEditor

    private var env: AppEnvironment { state.env }
    private var api: PlatformAPI { env.api }
    private var defaults: UserDefaults { env.defaults }
    var user: User? { state.user }

    var facts: Facts {
        let u = user
        return Facts(userKnown: u != nil, betaAccess: u?.betaAccess ?? true, consentVersion: u?.consent?.policyVersion,
                     policyVersion: config?.privacyPolicyVersion, serverGate: syncStatus?.gate,
                     reported: apiStatus.gates, birthYear: u?.birthYear, aboutYouDone: aboutYouDone,
                     aboutYouSaved: aboutYouSaved)
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

    /// What `SyncService` waits for: consent to the policy in force, or an enforced invite gate.
    /// Until the account is known (first check still running or failed, nothing cached),
    /// nothing goes up either: a consent can't be assumed. The warn-mode invite gate
    /// doesn't hold sync back (the platform serves it).
    var syncGate: APIErrorCode? {
        guard !env.isDemo else { return nil }
        if apiStatus.inviteBlocked { return .inviteRequired }
        guard user != nil else { return .consentRequired }
        return missing.contains(.consent) ? .consentRequired : nil
    }

    // MARK: the policy

    /// The policy in force (`GET /v1/config`).
    var policyVersion: String? { config?.privacyPolicyVersion }

    /// Where the policy is published; the in-app Safari sheet opens it.
    var policyPage: LegalPage {
        config?.privacyPolicyUrl.flatMap(URL.init(string:)).flatMap(LegalPage.init(url:)) ?? .privacy
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
        case .consent, .aboutYou: return true
        }
    }

    func later(_ step: Step) {
        guard canDefer(step) else { return }
        clearError()
        if step == .aboutYou { finishAboutYou() } else { deferred.insert(step) }
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
    /// sign-in, when a gate is reported, and after each step.
    func check(force: Bool = false) async {
        guard !env.isDemo, env.auth.isSignedIn else {
            phase = .ready
            return
        }
        let account = env.auth.accountID
        if account != self.account { switchAccount(account) }
        if !force, phase == .ready, let lastCheck,
           env.clock.now().timeIntervalSince(lastCheck) < Self.recheckInterval { return }
        // Offline: the cached account decides; the next start (or a gate) asks again.
        guard env.connectivity.isOnline else {
            phase = .ready
            return
        }
        if phase != .ready { phase = .checking }
        let answer = await fetchWithTimeout()
        // Signed out or another account meanwhile: that answer isn't theirs.
        guard env.auth.accountID == account else { return }
        if let user = answer.user { state.user = user }
        if let config = answer.config { self.config = config }
        if let status = answer.status {
            syncStatus = status
            state.syncStatus = status
            statusReceived?(status)
            // The platform no longer reports a gate this phone still remembers: it's passed.
            switch status.gate {
            case nil:
                apiStatus.resolved(.inviteRequired)
                apiStatus.resolved(.consentRequired)
            case .consentRequired?:
                apiStatus.resolved(.inviteRequired)
            case .inviteRequired?:
                break
            }
        }
        lastCheck = env.clock.now()
        phase = .ready
    }

    private struct Answer: Sendable {
        var user: User?
        var config: RemoteConfig?
        var status: SyncStatus?
    }

    /// The three reads at once, through the read pipeline (joined with the launch's own reads of
    /// the same resources). Failures leave a part unknown (the cache decides); the first run gives
    /// up waiting after `checkTimeout`.
    private func fetchWithTimeout() async -> Answer {
        let api = api, clock = env.clock, reads = env.reads
        let tz = TimeZone.current.identifier
        return await withTaskGroup(of: Answer?.self) { group in
            group.addTask {
                async let me = try? reads.run(ReadKey(.me)) { try await api.me() }
                async let config = try? reads.run(ReadKey(.config)) { try await api.config() }
                async let status = try? reads.run(ReadKey(.syncStatus)) { try await api.syncStatus() }
                var user = await me
                // New users start in Europe/Berlin, which defines every day boundary.
                if let u = user, u.tz != tz, let patched = try? await api.patchMe(UserPatch(tz: tz)) { user = patched }
                return Answer(user: user, config: await config, status: await status)
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
    func switchAccount(_ account: String?) {
        if self.account != nil { apiStatus.resetGates() }
        self.account = account
        config = nil
        syncStatus = nil
        deferred = []
        lastCheck = nil
        clearError()
        phase = .idle
        aboutYouSaved = false
        firstRunDone = account.map { defaults.bool(forKey: Self.key("firstRunDone", $0)) } ?? false
        aboutYouDone = account.map { defaults.bool(forKey: Self.key("aboutYouDone", $0)) } ?? false
        hintSeen = account.map { defaults.bool(forKey: Self.key("hintSeen", $0)) } ?? false
    }

    // MARK: steps

    /// `POST /v1/me/invite`. One message for every bad code, as the platform answers.
    @discardableResult
    func redeemInvite() async -> Bool {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return false }
        return await perform {
            try await self.api.redeemInvite(code: code)
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

    /// `POST /v1/me/consent` for the policy in force, then the first sync.
    @discardableResult
    func agree() async -> Bool {
        let ok = await perform {
            let version: String
            if let v = self.config?.privacyPolicyVersion {
                version = v
            } else {
                let fresh = try await self.api.config()
                self.config = fresh
                guard let v = fresh.privacyPolicyVersion else { throw APIError.http(422, "no policy version") }
                version = v
            }
            try await self.api.consent(policyVersion: version, appVersion: AppInfo.version)
            self.apiStatus.resolved(.consentRequired)
            self.deferred.remove(.consent)
            await self.check(force: true)
        } message: { error in
            guard (error as? APIError)?.status == 422 else { return nil }
            // The text on screen was an older policy: show the new one.
            Task { [weak self] in self?.config = try? await self?.api.config() }
            return String(localized: "The privacy policy was just updated. Read the new version, then agree again.")
        }
        if ok { await startSync() }
        return ok
    }

    /// `PATCH /v1/me {birth_year}`: the platform answers with its max-HR estimate, which
    /// the step shows before `finishAboutYou()`.
    @discardableResult
    func saveAboutYou(birthYear: Int) async -> Bool {
        await perform {
            self.state.user = try await self.api.patchMe(UserPatch(birthYear: birthYear))
            self.aboutYouSaved = true
        } message: { error in
            (error as? APIError)?.isFieldError == true
                ? String(localized: "Choose a year between 1920 and \(Self.latestBirthYear(now: self.env.clock.now())).")
                : nil
        }
    }

    /// Profile → Privacy: `DELETE /v1/me/consent`. Syncing stops; nothing is deleted.
    @discardableResult
    func withdrawConsent() async -> Bool {
        await perform {
            try await self.api.revokeConsent()
            // Withdrawn now, whatever the re-check below manages: sync stops at once.
            if var u = self.user {
                u.consent = nil
                self.state.user = u
            }
            // Asked again only when the user wants to (Profile → Privacy, Today's action).
            self.deferred.insert(.consent)
            await self.check(force: true)
        } message: { _ in nil }
    }

    /// The youngest birth year the platform takes (`this year − 13`).
    static func latestBirthYear(now: Date) -> Int {
        Calendar.current.component(.year, from: now) - 13
    }

    func clearError() {
        errorMessage = nil
        errorDetails = nil
    }

    // MARK: private

    private func perform(_ body: @MainActor () async throws -> Void,
                         message: (Error) -> String?) async -> Bool {
        isWorking = true
        clearError()
        defer { isWorking = false }
        do {
            try await body()
            return true
        } catch where error.isCancellation {
            return false
        } catch {
            errorMessage = message(error) ?? error.localizedDescription
            errorDetails = error.diagnosticDetails
            return false
        }
    }

    private func key(_ name: String) -> String { Self.key(name, account ?? "signed-out") }

    private static func key(_ name: String, _ account: String) -> String { "onboarding.\(name).\(account)" }
}

extension AccountHint: Identifiable {
    var id: Date { otherLastSync }
}

// MARK: - the steps

/// The first run's missing steps, full screen, before Apple Health and the tabs.
struct OnboardingFlowView: View {
    let model: OnboardingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let step = model.flowStep {
                OnboardingStepView(step: step, model: model)
                    .id(step)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.standard), value: model.flowStep)
    }
}

/// One step's screen; the same views serve the full-screen flow and the sheet.
struct OnboardingStepView: View {
    let step: OnboardingCoordinator.Step
    let model: OnboardingCoordinator

    var body: some View {
        switch step {
        case .invite: InviteCodeView(model: model)
        case .consent: ConsentView(model: model)
        case .aboutYou: AboutYouView(model: model)
        }
    }
}

/// Title, text and content on Graphite or Mist, like the Health explanation.
private struct OnboardingScreen<Content: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 36)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
            .padding(.horizontal, Theme.Metrics.screenPadding + 4)
            .padding(.bottom, 24)
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
    }
}

/// The step's failure, with Details (status, code, request ID).
private struct OnboardingError: View {
    let model: OnboardingCoordinator

    var body: some View {
        if let message = model.errorMessage {
            InlineMessage(message: message, systemImage: "exclamationmark.circle", details: model.errorDetails)
        }
    }
}

/// "Not now" under the main button.
private struct LaterButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.ryft(.body))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// Invite code: one field, any case, spaces or dashes; paste-friendly.
struct InviteCodeView: View {
    let model: OnboardingCoordinator
    @Environment(AuthService.self) private var auth
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingScreen(symbol: "envelope.open",
                         title: "Enter your invite code",
                         text: "RYFT is invite-only during the beta. The person who invited you has a code for you, like RYFT-7K3M-QX9P.") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Invite code")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    TextField(text: Bindable(model).inviteCode, prompt: Text(verbatim: "RYFT-XXXX-XXXX")) {
                        Text("Invite code")
                    }
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit { Task { await model.redeemInvite() } }
                        .accessibilityIdentifier("invite.code")
                    PasteButton(payloadType: String.self) { strings in
                        if let code = strings.first { model.inviteCode = code.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.iconOnly)
                    .tint(Theme.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            OnboardingError(model: model)
            PrimaryButton(title: "Continue", busy: model.isWorking) { await model.redeemInvite() }
                .disabled(model.inviteCode.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("invite.continue")
            if model.canDefer(.invite) {
                LaterButton(title: "Not now") { model.later(.invite) }
            }
            Divider().overlay(Theme.separator)
            Text("Signed in with the wrong account?")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
            PrimaryButton(title: "Use another account", style: .secondary) { await auth.signOut() }
        }
        .onAppear { if model.inviteCode.isEmpty { focused = true } }
    }
}

/// Consent to health-data processing for the policy in force: a plain summary, the
/// whole policy in Safari, and a separate checkbox that starts unticked.
struct ConsentView: View {
    let model: OnboardingCoordinator
    @State private var agreed = false
    @State private var legal: LegalPage?

    var body: some View {
        OnboardingScreen(symbol: "hand.raised",
                         title: "Your health data, your consent",
                         text: "To calculate your scores, RYFT processes health data from Apple Health. Here is what that means.") {
            if let earlier = model.earlierConsent {
                InlineMessage(message: String(localized: "The privacy policy changed since you agreed on \(Fmt.date(earlier.grantedAt)). Read what changed, then agree again."),
                              systemImage: "doc.badge.clock")
            }
            VStack(alignment: .leading, spacing: 14) {
                ConsentPoint(symbol: "waveform.path.ecg", title: "What RYFT reads",
                             text: "Heart rate, HRV, resting heart rate, breathing rate, blood oxygen, VO₂ max, steps, active energy, sleep and workouts.")
                ConsentPoint(symbol: "lock.shield", title: "Where it is stored",
                             text: "In your RYFT account, on servers in the EU. Never sold, never used for advertising.")
                ConsentPoint(symbol: "person.crop.circle.badge.checkmark", title: "Who can see it",
                             text: "Only you, and the operator of RYFT when something needs fixing.")
                ConsentPoint(symbol: "arrow.down.doc", title: "Always yours",
                             text: "Export or delete everything at any time in Profile. You can withdraw this consent in Profile → Privacy.")
            }
            Button {
                legal = model.policyPage
            } label: {
                Text(model.earlierConsent == nil ? "Read the privacy policy" : "What changed")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            Toggle(isOn: $agreed) {
                Text("I agree that RYFT processes my health data to calculate my scores.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(CheckboxToggleStyle())
            .accessibilityIdentifier("consent.checkbox")
            OnboardingError(model: model)
            PrimaryButton(title: "Agree and continue", busy: model.isWorking) { await model.agree() }
                .disabled(!agreed)
                .accessibilityIdentifier("consent.agree")
            LaterButton(title: "Not now") { model.later(.consent) }
            Text("Nothing is synced until you agree. Privacy policy version \(model.policyVersion ?? "–").")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .safariSheet($legal)
    }
}

private struct ConsentPoint: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ryft(.headline)).foregroundStyle(Theme.textPrimary)
                Text(text).font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A square checkbox (the consent must be a separate, deliberate tick).
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(configuration.isOn ? Theme.accent : Theme.textSecondary)
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// Birth year → the platform's max-HR estimate, and the sleep need it starts from.
struct AboutYouView: View {
    let model: OnboardingCoordinator
    @State private var year: Int?
    @State private var editing: BodySetting?
    @Environment(\.appEnvironment) private var env

    private var years: [Int] {
        Array(stride(from: OnboardingCoordinator.latestBirthYear(now: env.clock.now()), through: 1920, by: -1))
    }

    var body: some View {
        OnboardingScreen(symbol: "person.text.rectangle",
                         title: "About you",
                         text: "Your birth year gives an estimate of your maximum heart rate, which strain and heart-rate zones are measured against. RYFT keeps only the year.") {
            if model.aboutYouSaved, model.user != nil {
                let editor = model.bodySettings
                VStack(alignment: .leading, spacing: 14) {
                    AboutYouValue {
                        SettingRow(title: "Maximum heart rate", value: editor.maxHRText, detail: editor.maxHRSourceText) {
                            editing = .maxHR
                        }
                        .accessibilityIdentifier("aboutYou.maxHR")
                    }
                    AboutYouValue {
                        SettingRow(title: "Baseline sleep need", value: editor.sleepBaseText,
                                   detail: editor.sleepBaseSourceText) {
                            editing = .sleepBase
                        }
                        .accessibilityIdentifier("aboutYou.sleepBase")
                        Text("RYFT adjusts this from your nights unless you set it.")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PrimaryButton(title: "Continue") { model.finishAboutYou() }
                    .accessibilityIdentifier("aboutYou.continue")
            } else {
                Picker("Birth year", selection: $year) {
                    Text("Choose your birth year").tag(Int?.none)
                    ForEach(years, id: \.self) { Text(verbatim: "\($0)").tag(Int?.some($0)) }
                }
                .pickerStyle(.wheel)
                .frame(height: 200)
                .accessibilityIdentifier("aboutYou.year")
                OnboardingError(model: model)
                PrimaryButton(title: "Continue", busy: model.isWorking) {
                    guard let year else { return }
                    await model.saveAboutYou(birthYear: year)
                }
                .disabled(year == nil)
                LaterButton(title: "Skip") { model.finishAboutYou() }
            }
        }
        .bodySettingSheet($editing, editor: model.bodySettings)
    }
}

/// One setting on About you, on a tile.
private struct AboutYouValue<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
    }
}

/// One onboarding step on mock data, for previews and the Debug `-RyftScreen` captures.
struct OnboardingStepPreview: View {
    let step: OnboardingCoordinator.Step
    /// About you after the birth year was saved: the values, editable.
    var saved = false
    @State private var model = OnboardingCoordinator(state: AppState.preview(), apiStatus: APIStatus()) {}

    var body: some View {
        OnboardingStepView(step: step, model: model)
            .task { if saved { await model.saveAboutYou(birthYear: 1990) } }
    }
}

#Preview("Invite code · dark") {
    OnboardingStepPreview(step: .invite).previewEnvironment()
}

#Preview("Invite code · light") {
    OnboardingStepPreview(step: .invite).previewEnvironment(scheme: .light)
}

#Preview("Consent · dark") {
    OnboardingStepPreview(step: .consent).previewEnvironment()
}

#Preview("Consent · light") {
    OnboardingStepPreview(step: .consent).previewEnvironment(scheme: .light)
}

#Preview("About you · dark") {
    OnboardingStepPreview(step: .aboutYou).previewEnvironment()
}

#Preview("About you · saved · dark") {
    OnboardingStepPreview(step: .aboutYou, saved: true).previewEnvironment()
}

#Preview("About you · saved · light") {
    OnboardingStepPreview(step: .aboutYou, saved: true).previewEnvironment(scheme: .light)
}

#Preview("About you · light") {
    OnboardingStepPreview(step: .aboutYou).previewEnvironment(scheme: .light)
}

// MARK: - Apple Health

/// After sign-in, once per account: what RYFT reads from Apple Health, why, and
/// where it goes — then the system's permission sheet. Declining keeps the app
/// usable (empty states, Profile → Data → Allow access).
struct HealthPermissionView: View {
    @Environment(\.appEnvironment) private var env

    var body: some View {
        HealthPermissionScreen(model: HealthOnboardingViewModel(env: env))
    }
}

/// "Connect Apple Health" as a state machine (`HealthOnboardingMachine`): explain →
/// requesting → granted → firstSync, or denied ("Not now", or the request failed).
/// Both ends mark the intro as done; RootView then shows the tabs and the first sync starts.
@MainActor
@Observable
final class HealthOnboardingViewModel {
    private let env: AppEnvironment
    private(set) var phase: HealthOnboardingPhase = .explain
    @ObservationIgnored private var machine: GKTableMachine<HealthOnboardingPhase>!

    init(env: AppEnvironment) {
        self.env = env
        machine = HealthOnboardingMachine.make { [weak self] to, _ in
            self?.phase = to
            if to == .denied || to == .firstSync { self?.env.settings.healthIntroDone = true }
        }
    }

    var isRequesting: Bool { phase == .requesting }

    /// The system sheet. HealthKit never says what was allowed for reading, only that it was answered.
    func connect() async {
        guard machine.enter(.requesting) else { return }
        do {
            try await env.health.requestAuthorization()
            let answered = await env.health.accessStatus() != .notAsked
            machine.enter(answered ? .granted : .denied)
        } catch {
            machine.enter(.denied)
        }
        if phase == .granted { machine.enter(.firstSync) }
    }

    func notNow() { machine.enter(.denied) }
}

private struct HealthPermissionScreen: View {
    @State var model: HealthOnboardingViewModel
    @State private var legal: LegalPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HealthIllustration()
                    .padding(.top, 32)
                Text("Connect Apple Health")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("RYFT turns what your watch writes to Apple Health into recovery, strain and sleep scores.")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    point("waveform.path.ecg", "What RYFT reads",
                          "Heart rate, HRV, resting heart rate, breathing rate, blood oxygen, VO₂ max, steps, active energy, sleep and workouts. RYFT writes nothing to Apple Health unless you turn on saving strength workouts.")
                    point("server.rack", "Where it goes",
                          "To your RYFT account, where the scores are calculated. Never used for advertising, never sold.")
                    point("hand.raised", "You decide",
                          "Choose the data types on the next screen. You can change them later in the Health app, and delete your account and data in Profile.")
                }
                Button {
                    legal = .privacy
                } label: {
                    Text("Privacy Policy")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 12)
                VStack(spacing: 10) {
                    Button {
                        Task { await model.connect() }
                    } label: {
                        if model.isRequesting { ProgressView().tint(Theme.onAccent) } else { Text("Continue") }
                    }
                    .buttonStyle(TealButtonStyle())
                    .disabled(model.isRequesting)
                    .accessibilityIdentifier("health.continue")
                    Button("Not now") { model.notNow() }
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("health.notNow")
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding + 4)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .safariSheet($legal)
    }

    private func point(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ryft(.headline)).foregroundStyle(Theme.textPrimary)
                Text(text).font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Empty state when there's no Health data: Health access may be off, or the
/// watch isn't writing to Apple Health. HealthKit never tells an app which.
struct HealthAccessHint: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("No Health data yet", systemImage: "heart.text.square")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                Text("RYFT needs Apple Health access, and your watch app writing to Apple Health (Garmin Connect → More → Settings → Apple Health). Check RYFT's access in Health → your profile → Apps → RYFT.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    HealthLinks.open(with: openURL)
                } label: {
                    Text("Open Health")
                }
                .buttonStyle(TealButtonStyle(prominent: false))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Saving workouts was refused (iOS asks only once) or the access was taken away since.
struct HealthWriteAccessHint: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Allow it in Health → Sharing → Apps → RYFT → Workouts.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Open Health") { HealthLinks.open(with: openURL) }
                .font(.ryft(.caption))
                .foregroundStyle(Theme.accent)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("health.writeAccessHint")
    }
}

enum HealthLinks {
    /// The Health app (its Apps list holds RYFT's permissions); Settings if Health is missing.
    @MainActor
    static func open(with openURL: OpenURLAction) {
        if let health = URL(string: "x-apple-health://"), UIApplication.shared.canOpenURL(health) {
            openURL(health)
        } else if let settings = URL(string: UIApplication.openSettingsURLString) {
            openURL(settings)
        }
    }
}

#Preview("Connect Apple Health · dark") {
    HealthPermissionView()
        .environment(Settings.shared)
        .preferredColorScheme(.dark)
}

#Preview("Connect Apple Health · light") {
    HealthPermissionView()
        .environment(Settings.shared)
        .preferredColorScheme(.light)
}

#Preview("Health hint", traits: .sizeThatFitsLayout) {
    SchemePair { HealthAccessHint() }
}

#Preview("Health write access hint", traits: .sizeThatFitsLayout) {
    SchemePair { Card { HealthWriteAccessHint() }.padding() }
}
