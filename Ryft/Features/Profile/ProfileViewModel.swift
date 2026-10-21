import Foundation
import Observation

/// Account, body settings, data and sync, export. The view keeps only which
/// dialog or sheet is open.
@MainActor
@Observable
final class ProfileViewModel {
    private let state: AppState
    private let sync: SyncService
    private let coordinator: SyncCoordinator
    private let apiStatus: APIStatus
    private let onboarding: OnboardingCoordinator?

    init(state: AppState, sync: SyncService, coordinator: SyncCoordinator, onboarding: OnboardingCoordinator? = nil,
         apiStatus: APIStatus? = nil) {
        self.state = state
        self.sync = sync
        self.coordinator = coordinator
        self.onboarding = onboarding
        self.apiStatus = apiStatus ?? .shared
    }

    private var env: AppEnvironment { state.env }
    private var auth: AuthService { env.auth }
    private var settings: Settings { env.settings }

    // MARK: account

    var isSignedIn: Bool { auth.isSignedIn }

    /// `User.name` → email → "Apple ID".
    var accountTitle: String {
        if let name = state.user?.name, !name.isEmpty { return name }
        return accountEmail ?? auth.identityDescription
    }

    var accountEmail: String? {
        let email = state.user?.email ?? auth.user?.email
        return email?.isEmpty == false ? email : nil
    }

    /// Shown under the title when it isn't the title already.
    var accountSubtitle: String? {
        guard let email = accountEmail, email != accountTitle else { return nil }
        return email
    }

    /// The platform's `User.provider`, else the session's `app_metadata.provider`.
    var provider: String? { state.user?.provider ?? auth.provider }
    var canChangePassword: Bool { provider == "email" }

    struct Badge: Equatable {
        let title: String
        let systemImage: String
    }

    var providerBadge: Badge? {
        switch provider {
        case "apple": return Badge(title: String(localized: "Apple"), systemImage: "apple.logo")
        case "email": return Badge(title: String(localized: "Email"), systemImage: "envelope.fill")
        default: return nil
        }
    }

    var timezone: String? { state.user?.tz }

    /// "Phone: Europe/Lisbon" when the phone is elsewhere than the account's zone.
    var timezoneDetail: String? {
        guard let tz = timezone, tz != TimeZone.current.identifier else { return nil }
        return String(localized: "Phone: \(TimeZone.current.identifier)")
    }

    var isWorking: Bool { auth.isWorking }
    var accountError: String? { auth.errorMessage }
    var accountErrorDetails: String? { auth.errorDetails }

    func logOut() async { await auth.signOut() }
    func deleteAccount() async { await auth.deleteAccount() }

    // MARK: body

    var maxHR = 190
    var sleepBase = 480
    private(set) var recomputing = false
    private(set) var recomputeStatus: String?
    var canRecompute: Bool { state.hasDataSource }
    var maxHRText: String { "\(maxHR) bpm" }
    var sleepBaseText: String { Fmt.duration(minutes: sleepBase) }

    /// The steppers start from the account's values.
    func applyUser() {
        guard let u = state.user else { return }
        maxHR = u.maxHr
        sleepBase = u.sleepBaseMin
    }

    /// Where the baseline comes from, as Profile says it:
    /// "Learned · 7h 35m (updated Mon)", "Set by you · 7h 50m · learned 7h 35m", "Default · 7h 40m".
    var sleepBaseSourceText: String? {
        guard let u = state.user else { return nil }
        let base = Fmt.duration(minutes: u.sleepBaseMin)
        switch u.sleepBaseSource {
        case .learned:
            guard let at = u.sleepBaseLearnedAt else { return String(localized: "Learned · \(base)") }
            return String(localized: "Learned · \(base) (updated \(at.formatted(.dateTime.weekday(.abbreviated))))")
        case .manual:
            guard let learned = u.sleepBaseLearnedMin else { return String(localized: "Set by you · \(base)") }
            return String(localized: "Set by you · \(base) · learned \(Fmt.duration(minutes: learned))")
        case .default:
            return String(localized: "Default · \(base)")
        }
    }

    /// "Estimated from your age (born 1990)", "Set by you", "Default · add your birth year".
    var maxHRSourceText: String? {
        guard let u = state.user else { return nil }
        switch u.maxHrSource {
        case .estimated:
            return u.birthYear.map { String(localized: "Estimated from your age (born \(String($0)))") }
                ?? String(localized: "Estimated from your age")
        case .manual: return String(localized: "Set by you")
        case .default: return String(localized: "Default · add your birth year for an estimate")
        }
    }

    /// Max HR set by hand: offer the estimate again (or the default without a birth year).
    var canUseMaxHREstimate: Bool { state.user?.maxHrSource == .manual }

    var birthYear: Int? { state.user?.birthYear }

    /// The years the platform takes: 1920 to this year − 13, newest first.
    var birthYears: [Int] {
        Array(stride(from: OnboardingCoordinator.latestBirthYear(now: env.clock.now()), through: 1920, by: -1))
    }

    /// `PATCH /v1/me {birth_year}`: the estimate follows unless max HR is set by hand.
    func setBirthYear(_ year: Int) async {
        await state.updateUser(UserPatch(birthYear: year))
        applyUser()
    }

    /// `PATCH /v1/me {max_hr_manual: false}`.
    func useMaxHREstimate() async {
        await state.updateUser(UserPatch(maxHrManual: false))
        applyUser()
        recomputeStatus = String(localized: "Back to the estimate. Apply & recompute rescores past days with it.")
    }

    /// Set by hand: offer going back (to the learned estimate, or the default without one).
    var canUseLearnedBase: Bool { state.user?.sleepBaseSource == .manual }
    var usesLearnedTitle: String {
        state.user?.sleepBaseLearnedMin == nil ? String(localized: "Use the default") : String(localized: "Use the learned value")
    }

    /// `PATCH /v1/me {sleep_base_manual: false}`. Like every setting, it doesn't
    /// rescore history until Apply & recompute.
    func useLearnedBase() async {
        await state.updateUser(UserPatch(sleepBaseManual: false))
        applyUser()
        recomputeStatus = String(localized: "Back to the learned baseline. Apply & recompute rescores past nights with it.")
    }

    /// Saves what changed, rescores 90 days, waits for scoring and reloads. The
    /// baseline is only sent when it was moved, since sending it makes it manual.
    func applyAndRecompute() async {
        recomputing = true
        defer { recomputing = false }
        let now = env.clock.now()
        let user = state.user
        await state.updateUser(UserPatch(tz: TimeZone.current.identifier,
                                         maxHr: maxHR == user?.maxHr ? nil : maxHR,
                                         sleepBaseMin: sleepBase == user?.sleepBaseMin ? nil : sleepBase))
        do {
            try await state.source.recompute(from: DayFormat.shift(now, days: -90), to: now)
            recomputeStatus = String(localized: "Recomputing — scores update in a few seconds.")
            try? await env.clock.sleep(for: SyncService.rescoreDelay)
            await state.refresh()
            recomputeStatus = String(localized: "Scores recomputed with your new settings.")
        } catch {
            recomputeStatus = error.localizedDescription
        }
    }

    // MARK: privacy (consent to health-data processing)

    /// Consent to the policy in force (`GET /v1/config`), from `User.consent`.
    var consentIsCurrent: Bool { state.user?.hasConsented(to: onboarding?.policyVersion) ?? false }

    var consentText: String {
        guard state.user?.consent != nil else { return String(localized: "Not given") }
        return consentIsCurrent ? String(localized: "Given") : String(localized: "Policy updated")
    }

    /// "Agreed on 20 Oct 2026 · policy 2026-10-20".
    var consentDetail: String? {
        guard let c = state.user?.consent else {
            return String(localized: "RYFT doesn't sync or score your health data until you agree.")
        }
        return String(localized: "Agreed on \(Fmt.date(c.grantedAt)) · policy \(c.policyVersion)")
    }

    var withdrawingConsent: Bool { onboarding?.isWorking ?? false }
    var consentError: String? { onboarding?.errorMessage }

    /// `DELETE /v1/me/consent`: syncing and scoring stop; nothing is deleted.
    func withdrawConsent() async { await onboarding?.withdrawConsent() }

    /// The consent screen, again.
    func reviewConsent() { onboarding?.show(.consent) }

    var policyPage: LegalPage { onboarding?.policyPage ?? .privacy }

    // MARK: Apple Health

    private(set) var healthStatus: HealthAccess = .unknown

    var healthStatusText: String {
        switch healthStatus {
        case .unavailable: return String(localized: "Not available")
        case .notAsked: return String(localized: "Not requested")
        case .asked: return String(localized: "Requested")
        case .unknown: return Fmt.placeholder
        }
    }

    var healthNeedsAttention: Bool { healthStatus != .asked }
    var canAskForHealth: Bool { healthStatus == .notAsked }

    func refreshHealthStatus() async { healthStatus = await env.health.accessStatus() }

    func requestHealthAccess() async {
        try? await env.health.requestAuthorization()
        await refreshHealthStatus()
    }

    // MARK: sync

    var lastSyncText: String {
        settings.lastSync?.formatted(.relative(presentation: .named)) ?? String(localized: "Never")
    }
    var deviceIDText: String { String(settings.deviceId.uuidString.prefix(8)) + "…" }
    var isSyncing: Bool { sync.isSyncing }
    var syncProgress: String { sync.progress.isEmpty ? String(localized: "Syncing…") : sync.progress }

    enum SyncNotice: Equatable {
        case retrying(String)
        case failed(message: String, details: String?)
    }

    var syncNotice: SyncNotice? {
        if let notice = apiStatus.retryNotice { return .retrying(notice) }
        if let e = sync.lastError, !env.isDemo { return .failed(message: e, details: sync.lastErrorDetails) }
        return nil
    }

    var canSync: Bool { !sync.isSyncing && settings.isConfigured && auth.isSignedIn && !env.isDemo }

    func syncNow() async {
        await coordinator.run(.userInitiated)
        await state.refresh(force: true)
    }

    /// Forget the anchors, upload 90 days again, rescore them, reload.
    func fullResync() async {
        await sync.fullResync()
        let now = env.clock.now()
        try? await state.source.recompute(from: DayFormat.shift(now, days: -90), to: now)
        await state.refresh()
    }

    // MARK: notifications

    /// The preferences belong to a platform account. With `push.enabled` off the
    /// screen explains the rollout instead.
    var showsNotifications: Bool { auth.isSignedIn && !env.isDemo }

    // MARK: demo data

    /// Through the environment, so tests (which pin demo off) never see the simulator's setting.
    var demoMode: Bool { env.isDemo }

    func setDemoMode(_ on: Bool) async {
        settings.demoMode = on
        state.reset()
        await state.refresh()
    }

    // MARK: export

    var canExport: Bool { auth.isSignedIn || env.isDemo }
    private(set) var exporting = false
    var exported: ExportedFile?
    private(set) var exportError: String?

    func export() async {
        exporting = true
        exportError = nil
        defer { exporting = false }
        do {
            let archive = try await DataExport.archive(source: state.source, train: env.api)
            exported = ExportedFile(url: try DataExport.write(archive))
        } catch {
            exportError = String(localized: "The export couldn't be created: \(error.localizedDescription)")
        }
    }

    // MARK: developer

    enum ConnectionResult: Equatable {
        case ok(String)
        case failed(String)
    }

    private(set) var testingConnection = false
    private(set) var connection: ConnectionResult?

    /// `GET /v1/me` against the live platform, then a sync and reload.
    func testConnection() async {
        testingConnection = true
        defer { testingConnection = false }
        guard settings.isConfigured else {
            connection = .failed(APIError.notConfigured.localizedDescription)
            return
        }
        guard auth.isSignedIn else {
            connection = .failed(APIError.signedOut.localizedDescription)
            return
        }
        do {
            let user = try await env.liveAPI.me()
            connection = .ok(String(localized: "Connected as \(user.name.isEmpty ? user.id.uuidString : user.name)"))
            await syncNow()
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }
}
