import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

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
    /// Data → Sync details.
    let syncDetails: SyncDetailsModel
    /// About → Report a problem, and "Send to RYFT" from an error's Details.
    let report: ReportProblemModel
    /// Data → Devices & sync (`devices.setup`).
    let devices: DevicesViewModel

    init(state: AppState, sync: SyncService, coordinator: SyncCoordinator, onboarding: OnboardingCoordinator? = nil,
         apiStatus: APIStatus? = nil, devices selection: TrackerSelectionStore? = nil) {
        self.state = state
        self.sync = sync
        self.coordinator = coordinator
        self.onboarding = onboarding
        self.apiStatus = apiStatus ?? .shared
        bodySettings = BodySettingsEditor(state: state)
        let devices = DevicesViewModel(state: state, selection: selection ?? TrackerSelectionStore(env: state.env))
        self.devices = devices
        let details = SyncDetailsModel(state: state, sync: sync, coordinator: coordinator, apiStatus: apiStatus)
        syncDetails = details
        // The read pipeline's record and Sync details' state through the report's allow-list (never its
        // support text); the trackers' ids while `devices.setup` is on.
        report = ReportProblemModel(env: state.env, apiStatus: apiStatus ?? .shared,
                                    resources: { state.resourceStates },
                                    trackers: { devices.isEnabled ? devices.selection.trackers : nil }) {
            FeedbackSync(engine: sync.engineState, backlogBytes: sync.backlogBytes, running: details.isRunning,
                         queued: details.hasQueuedRun, streams: details.streams)
        }
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
    func deleteAccount() async {
        let account = auth.accountID
        await auth.deleteAccount()
        // Deleted: this phone forgets the account's tracker steps too (what it wore went with the store).
        if let account, auth.accountID != account { onboarding?.forgetTrackerSteps(of: account) }
    }

    // MARK: body

    /// Baseline sleep need, maximum heart rate and birth year: one editor, shared with
    /// onboarding and the Sleep tab.
    let bodySettings: BodySettingsEditor

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

    /// Like pull to refresh: the upload starts, today and the sync status load at once, the rest after.
    func syncNow() async {
        await state.pullToRefresh(coordinator: coordinator)
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
        // Demo data's flags are its own: off again, the account's cached flags, never demo's.
        (env.flags as? FlagStore)?.setDemo(on)
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
        } catch where error.isCancellation {
            return
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
        } catch where error.isCancellation {
            return
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }
}

// MARK: - sync details

/// Profile → Data → Sync details: the engine's state, each stream's progress and last
/// answer, the last requests and the queue, with what a user (or support) can do about it.
@MainActor
@Observable
final class SyncDetailsModel {
    private let state: AppState
    private let sync: SyncService
    private let coordinator: SyncCoordinator
    private let apiStatus: APIStatus

    private(set) var isRunning = false
    private(set) var hasQueuedRun = false
    private(set) var copied = false

    init(state: AppState, sync: SyncService, coordinator: SyncCoordinator, apiStatus: APIStatus? = nil) {
        self.state = state
        self.sync = sync
        self.coordinator = coordinator
        self.apiStatus = apiStatus ?? .shared
    }

    private var env: AppEnvironment { state.env }
    var engine: SyncEngineState { sync.engineState }
    var requests: [APIStatus.RequestFailure] { apiStatus.requests }
    var cancelledRequests: Int { apiStatus.cancelledCount }
    var canSync: Bool { !sync.isSyncing && env.settings.isConfigured && env.auth.isSignedIn && !env.isDemo }

    /// One stream: how far it got and what the platform said to its last page.
    struct StreamRow: Identifiable, Equatable {
        let id: String
        let name: String
        let progress: SyncEngineState.StreamProgress?

        var newestText: String { progress?.newest.map(Fmt.date) ?? String(localized: "Nothing sent yet") }
        /// Sentence case ("Resting heart rate", "HRV", "VO₂ max").
        var title: String { name.prefix(1).uppercased() + name.dropFirst() }

        /// "1 200 accepted · 3 duplicates" for the last page.
        var lastPageText: String? {
            guard let p = progress, p.lastUploadAt != nil else { return nil }
            var parts = [String(localized: "\(p.lastAccepted.formatted()) accepted")]
            if let ignored = p.lastIgnored {
                if ignored.duplicate > 0 { parts.append(String(localized: "\(ignored.duplicate.formatted()) duplicates")) }
                if ignored.outsideWindow > 0 { parts.append(String(localized: "\(ignored.outsideWindow.formatted()) outside the window")) }
                if ignored.unknownType > 0 { parts.append(String(localized: "\(ignored.unknownType.formatted()) of an unknown type")) }
            }
            return parts.joined(separator: " · ")
        }
    }

    /// In the order the engine drains them.
    var streams: [StreamRow] {
        env.health.streams.map { StreamRow(id: $0.anchorID, name: $0.displayName, progress: engine.streams[$0.anchorID]) }
    }

    var phaseText: String {
        if let activity = sync.activity { return activity.text }
        if sync.waitingForUnlock { return String(localized: "Waiting for you to unlock your iPhone") }
        switch engine.phase {
        case .recent: return String(localized: "First score: the last 3 days")
        case .backfill: return String(localized: "Importing the last 90 days")
        case .incremental: return String(localized: "Only what's new")
        case .idle:
            return engine.backfillDone ? String(localized: "Up to date") : String(localized: "Import not finished")
        }
    }

    var queueText: String {
        if isRunning { return hasQueuedRun ? String(localized: "Running, another queued") : String(localized: "Running") }
        return String(localized: "Idle")
    }

    /// When scoring began (`SyncService.scoringSince`), and the platform's estimate.
    private var scoringSince: Date? { sync.scoringSince(pendingDays: state.syncStatus?.pendingDays ?? []) }
    private var expectedScoringSec: Int {
        state.syncStatus?.expectedWithinSec ?? sync.lastScoring?.expectedWithinSec ?? SyncCoordinator.defaultExpectedScoring
    }

    /// "Waiting since 10:21 · usually 20 s"; the platform's pending days when this app isn't timing them;
    /// "Nothing waiting" when nothing is.
    var scoringText: String {
        guard let since = scoringSince else {
            let pending = state.syncStatus?.pendingDays ?? []
            return pending.isEmpty ? String(localized: "Nothing waiting")
                : String(localized: "Pending: \(pending.joined(separator: ", "))")
        }
        return String(localized: "Waiting since \(Fmt.time(since)) · usually \(expectedScoringSec) s")
    }

    /// The same rule as Today's "Taking longer than usual" (`TodayStates.scoringSlow`).
    var scoringIsSlow: Bool {
        let listed = !(state.syncStatus?.pendingDays.isEmpty ?? true)
        return TodayStates.scoringSlow(since: scoringSince, expected: expectedScoringSec, now: env.clock.now(),
                                       checkedAt: listed ? sync.statusReadAt : nil)
    }

    var backlogText: String {
        guard let bytes = sync.backlogBytes else { return String(localized: "None") }
        return String(localized: "About \(bytes.formatted(.byteCount(style: .file)))")
    }

    var uploadedText: String {
        engine.bytesUploaded > 0 ? Int64(engine.bytesUploaded).formatted(.byteCount(style: .file)) : String(localized: "None")
    }

    var lastErrorText: String? {
        guard let error = engine.lastError else { return nil }
        return engine.lastRequestID.map { "\(error) · \($0)" } ?? error
    }

    /// The coordinator is an actor: asked when the screen appears and after each action.
    func loadQueue() async {
        isRunning = await coordinator.isRunning
        hasQueuedRun = await coordinator.hasQueuedRun
    }

    /// "Sync last 3 days again": the first score's window once more, then what's new.
    func resendRecent() async {
        sync.resendRecent()
        await state.pullToRefresh(coordinator: coordinator)
        // The pull returns before its upload ends; the queue is worth reading after it.
        await state.pullUploaded?.value
        await loadQueue()
    }

    /// Forget the anchors, upload 90 days again, rescore them, reload.
    func fullResync() async {
        await sync.fullResync()
        let now = env.clock.now()
        try? await state.source.recompute(from: DayFormat.shift(now, days: -90), to: now)
        await state.refresh()
        await loadQueue()
    }

    /// One resource the app reads: when it last loaded, how its last fetches went (Loaded data).
    struct ResourceRow: Identifiable, Equatable {
        let resource: ReadResource
        let name: String
        let state: ResourceState
        var id: String { resource.rawValue }

        /// "14:05", "Tue 14:05"; "Not loaded yet" when never.
        func fetchedText(now: Date) -> String {
            state.fetchedAt.map { SyncLine.dataTime($0, now: now) } ?? String(localized: "Not loaded yet")
        }

        /// "503 · consent_required · 12 s ago · 3 failed in a row"; "No errors" while the last fetch succeeded.
        func statusText(now: Date) -> String {
            guard state.consecutiveFailures > 0, let error = state.lastError else { return String(localized: "No errors") }
            var parts = [error.status.map(String.init) ?? String(localized: "No response")]
            if let code = error.code { parts.append(code) }
            parts.append(error.at.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
            let n = state.consecutiveFailures
            parts.append(n >= RefreshPolicy.failuresBeforeIssue ? String(localized: "\(n) failed in a row")
                         : String(localized: "\(n) failed"))
            return parts.joined(separator: " · ")
        }

        /// Warning colour from the threshold on; words always say it too.
        var isWarning: Bool { state.consecutiveFailures >= RefreshPolicy.failuresBeforeIssue }

        /// "Profile, loaded 13:58, last error 503, 3 failed in a row".
        func spoken(now: Date) -> String {
            var parts = [name, state.fetchedAt.map { String(localized: "loaded \(SyncLine.dataTime($0, now: now))") }
                            ?? String(localized: "Not loaded yet")]
            if state.consecutiveFailures > 0 { parts.append(statusText(now: now)) }
            return parts.joined(separator: ", ")
        }
    }

    /// Loaded data (ui.md §6): what the app reads, as the read pipeline recorded it.
    var resources: [ResourceRow] {
        let states = state.resourceStates
        return ReadResource.allCases.compactMap { r in
            r.displayName.map { ResourceRow(resource: r, name: $0, state: states[r] ?? ResourceState()) }
        }
    }

    /// Everything above as text for support: no health data, only counts, dates and IDs.
    var diagnostics: String {
        let e = engine
        var lines = [
            "RYFT \(AppInfo.version) · \(AppInfo.osVersion)",
            "device \(env.settings.deviceId.uuidString.lowercased())",
            "phase \(e.phase.rawValue) · recent \(e.recentDone) · backfill \(e.backfillDone) · stream \(e.stream ?? "-")",
            "uploaded \(e.bytesUploaded) B · backlog \(sync.backlogBytes ?? 0) B · deletions kept \(e.pendingDeletions)",
            "queue running \(isRunning) · queued \(hasQueuedRun) · unlock \(sync.waitingForUnlock) · gate \(sync.pausedFor?.rawValue ?? "-")",
            "updated \(e.updatedAt.map { $0.ISO8601Format() } ?? "-") · full resync \(e.lastFullResyncAt.map { $0.ISO8601Format() } ?? "-")",
        ]
        if let error = e.lastError { lines.append("last error \(error) · request \(e.lastRequestID ?? "-")") }
        if let status = state.syncStatus {
            lines.append("server today \(status.today.day) \(status.today.state.rawValue) · pending \(status.pendingDays.joined(separator: ",")) · expected \(status.expectedWithinSec) s")
        }
        lines.append("scoring since \(scoringSince.map { $0.ISO8601Format() } ?? "-") · expected \(expectedScoringSec) s · slow \(scoringIsSlow)")
        for row in streams {
            guard let p = row.progress else { lines.append("\(row.id): -"); continue }
            let ignored = p.lastIgnored.map { "dup \($0.duplicate) out \($0.outsideWindow) unk \($0.unknownType)" } ?? "-"
            lines.append("\(row.id): \(p.sent) rec \(p.bytes) B days \(p.days.count) newest \(p.newest.map { $0.ISO8601Format() } ?? "-") backfilled \(p.backfilled) last \(p.lastAccepted) ignored \(ignored)")
        }
        lines.append("resources (resource | fetched_at | last_error status code request_id at | consecutive_failures):")
        let states = state.resourceStates
        lines += ReadResource.allCases.map { (states[$0] ?? ResourceState()).diagnosticLine($0) }
        lines.append(env.catalogStore.diagnosticLine)
        if let check = TrackerCheckRecord.forReport(env) { lines.append("sync check: " + check.lines.joined(separator: " · ")) }
        lines.append("requests (cancelled since launch: \(cancelledRequests)):")
        for r in requests {
            let duration = r.durationMs.map(String.init) ?? "-"
            lines.append("\(r.date.ISO8601Format()) \(r.status) \(r.code ?? "-") \(r.method) \(redactedPath(r.path)) \(r.requestID ?? "-") duration_ms=\(duration) transport=\(r.transport ?? "-")")
        }
        return lines.joined(separator: "\n")
    }

    func copyDiagnostics() {
        // Health times to the second: on this iPhone only, and not for long.
        LocalPasteboard.copy(diagnostics)
        copied = true
    }
}

// MARK: - body settings

/// The settings the platform scores against that the user may set: baseline sleep need,
/// maximum heart rate and birth year. Onboarding, the Sleep tab and Profile edit them
/// through one sheet each. A change saves at once (`PATCH /v1/me`): it shows right away,
/// and a refusal shows in the sheet while the value goes back. Past days keep their scores
/// until "Rescore the last 90 days" (`POST /v1/recompute`).
@MainActor
@Observable
final class BodySettingsEditor {
    private let state: AppState

    /// Shown while its `PATCH` is out.
    private(set) var pendingSleepBase: Int?
    private(set) var pendingMaxHR: Int?
    private(set) var saving = false
    /// The last save's refusal, for the form; cleared when a form opens.
    private(set) var error: String?
    private(set) var errorDetails: String?
    /// A birth year Profile's picker couldn't save (it has no form to say so in).
    private(set) var birthYearError: String?
    private(set) var birthYearErrorDetails: String?
    /// A change was saved since the form opened: past days keep their scores until rescored.
    private(set) var savedChange = false
    private(set) var rescoring = false
    private(set) var rescoreStatus: String?
    /// Status and request ID of a failed rescore.
    private(set) var rescoreDetails: String?

    /// One thing at a time: a save during a rescore would be reported as rescored.
    var isBusy: Bool { saving || rescoring }

    /// What `PATCH /v1/me` takes: 4–12 h, in the sheet's 15-minute steps.
    static let sleepBaseRange = 240...720
    static let sleepBaseStep = 15
    static let defaultSleepBase = 460
    /// 100–230 bpm.
    static let maxHRRange = 100...230
    static let defaultMaxHR = 190

    init(state: AppState) {
        self.state = state
    }

    private var env: AppEnvironment { state.env }
    private var user: User? { state.user }
    var canSave: Bool { state.hasDataSource }

    /// A form opens: a fresh start, no earlier refusal or note.
    func begin() {
        error = nil
        errorDetails = nil
        savedChange = false
        rescoreStatus = nil
        rescoreDetails = nil
    }

    // MARK: baseline sleep need

    var sleepBase: Int { pendingSleepBase ?? user?.sleepBaseMin ?? Self.defaultSleepBase }
    var sleepBaseText: String { Fmt.duration(minutes: sleepBase) }
    var sleepBaseSource: SleepBaseSource? { pendingSleepBase != nil ? .manual : user?.sleepBaseSource }

    /// Where the value comes from, beside it: "Learned · updated Mon", "Set by you · learned
    /// 7h 35m", "Default".
    var sleepBaseSourceText: String? {
        guard let source = sleepBaseSource else { return nil }
        switch source {
        case .learned:
            guard let at = user?.sleepBaseLearnedAt else { return String(localized: "Learned") }
            return String(localized: "Learned · updated \(at.formatted(.dateTime.weekday(.abbreviated)))")
        case .manual:
            guard let learned = user?.sleepBaseLearnedMin else { return String(localized: "Set by you") }
            return String(localized: "Set by you · learned \(Fmt.duration(minutes: learned))")
        case .default:
            return String(localized: "Default")
        }
    }

    /// Set by hand: offer going back (to the learned estimate, or the default without one).
    var canUseLearnedBase: Bool { sleepBaseSource == .manual }
    var usesLearnedTitle: String {
        user?.sleepBaseLearnedMin == nil ? String(localized: "Use the default") : String(localized: "Use the learned value")
    }

    /// `PATCH /v1/me {sleep_base_min}`: the baseline becomes yours (`manual`), learning stops.
    @discardableResult
    func setSleepBase(_ minutes: Int) async -> Bool {
        let value = min(max(minutes, Self.sleepBaseRange.lowerBound), Self.sleepBaseRange.upperBound)
        pendingSleepBase = value
        defer { pendingSleepBase = nil }
        return await save(UserPatch(sleepBaseMin: value),
                          refused: String(localized: "RYFT takes a baseline between 4 and 12 hours."))
    }

    /// `PATCH /v1/me {sleep_base_manual: false}`: back to the learned estimate (or the default).
    @discardableResult
    func useLearnedSleepBase() async -> Bool {
        await save(UserPatch(sleepBaseManual: false), refused: Self.notTaken)
    }

    /// A refusal of a change without a range to name.
    private static var notTaken: String { String(localized: "RYFT couldn't take that change. Try again later.") }

    // MARK: maximum heart rate

    var maxHR: Int { pendingMaxHR ?? user?.maxHr ?? Self.defaultMaxHR }
    var maxHRText: String { "\(maxHR) bpm" }

    /// "Estimated from your age (born 1990)", "Set by you", "Default · add your birth year".
    var maxHRSourceText: String? {
        guard let u = user else { return nil }
        if pendingMaxHR != nil { return String(localized: "Set by you") }
        switch u.maxHrSource {
        case .estimated:
            return u.birthYear.map { String(localized: "Estimated from your age (born \(String($0)))") }
                ?? String(localized: "Estimated from your age")
        case .manual: return String(localized: "Set by you")
        case .default: return String(localized: "Default · add your birth year for an estimate")
        }
    }

    /// Set by hand: offer the estimate again (or the default without a birth year).
    var canUseMaxHREstimate: Bool { pendingMaxHR != nil || user?.maxHrSource == .manual }

    /// `PATCH /v1/me {max_hr}`: yours from now on (`manual`).
    @discardableResult
    func setMaxHR(_ bpm: Int) async -> Bool {
        let value = min(max(bpm, Self.maxHRRange.lowerBound), Self.maxHRRange.upperBound)
        pendingMaxHR = value
        defer { pendingMaxHR = nil }
        return await save(UserPatch(maxHr: value),
                          refused: String(localized: "RYFT takes a maximum heart rate between 100 and 230 bpm."))
    }

    /// `PATCH /v1/me {max_hr_manual: false}`.
    @discardableResult
    func useMaxHREstimate() async -> Bool {
        await save(UserPatch(maxHrManual: false), refused: Self.notTaken)
    }

    // MARK: birth year

    var birthYear: Int? { user?.birthYear }

    /// The years the platform takes: 1920 to this year − 13, newest first.
    var birthYears: [Int] {
        Array(stride(from: OnboardingCoordinator.latestBirthYear(now: env.clock.now()), through: 1920, by: -1))
    }

    /// `PATCH /v1/me {birth_year}`: the estimate follows unless max HR is set by hand. A
    /// failure stays beside the picker (`birthYearError`).
    @discardableResult
    func setBirthYear(_ year: Int) async -> Bool {
        birthYearError = nil
        birthYearErrorDetails = nil
        let saved = await save(UserPatch(birthYear: year), refused: Self.notTaken)
        if !saved {
            birthYearError = error
            birthYearErrorDetails = errorDetails
            error = nil
            errorDetails = nil
        }
        return saved
    }

    // MARK: rescoring

    /// Rescores the last 90 days with the settings as they are, waits for scoring and reloads.
    func rescore() async {
        guard !isBusy else { return }
        rescoring = true
        rescoreDetails = nil
        defer { rescoring = false }
        let now = env.clock.now()
        do {
            try await state.source.recompute(from: DayFormat.shift(now, days: -90), to: now)
            rescoreStatus = String(localized: "Rescoring — scores update in a few seconds.")
            try? await env.clock.sleep(for: SyncService.rescoreDelay)
            await state.refresh(force: true)
            rescoreStatus = String(localized: "The last 90 days are rescored with your settings.")
            savedChange = false
        } catch where error.isCancellation {
            return
        } catch {
            rescoreStatus = error.localizedDescription
            rescoreDetails = error.diagnosticDetails
        }
    }

    /// One `PATCH`: `true` when the platform took it. A refusal (`422`) says `refused` in the
    /// form; anything else says what went wrong. Details keep the request ID.
    private func save(_ patch: UserPatch, refused: String) async -> Bool {
        guard !isBusy else { return false }
        saving = true
        error = nil
        errorDetails = nil
        defer { saving = false }
        do {
            try await state.patchUser(patch)
            savedChange = true
            rescoreStatus = nil
            return true
        } catch let e as APIError where e.isFieldError {
            error = refused
            errorDetails = e.diagnosticDetails
        } catch where error.isCancellation {
            return false
        } catch {
            self.error = error.localizedDescription
            errorDetails = error.diagnosticDetails
        }
        return false
    }
}

// MARK: - check sync

/// One signal's result in Check sync (design.md §4.4): what HealthKit showed, not words (`TrackerCheckText`).
enum SignalCheck: Equatable, Sendable {
    /// Queued, then while the probe reads (D2 K1).
    case waiting, checking
    /// From the tracker: a nightly signal since last night began, any other within 48 h.
    case arrived(Date)
    /// A nightly signal the tracker shares (`yes`) whose newest record is from before last night began.
    case notLastNight(lastSeen: Date)
    /// Expected: the catalog says the tracker doesn't share it (D2 K3).
    case notShared
    /// Neutral: `partial` or `unverified` without data, workouts without a workout, stages without sleep.
    case notSeenYet
    /// Neutral: this tracker should send it, but another selected one did (the platform takes one source per hour
    /// or night). Its code is `not_seen`.
    case elsewhere(app: String)
    /// Unexpected: the catalog says `yes` and nothing came (D2 K4). `visible`: RYFT sees the type from another
    /// source, so it may read it; otherwise RYFT can't tell "not allowed to read" from "nobody wrote it" (§4.5).
    case missing(visible: Bool)

    /// What `devices.check` and Report a problem keep (§4.7): no times, no names.
    var code: String? {
        switch self {
        case .waiting, .checking: return nil
        case .arrived: return "arrived"
        case .notLastNight: return "not_last_night"
        case .notShared: return "not_shared"
        case .notSeenYet, .elsewhere: return "not_seen"
        case .missing(let visible): return visible ? "missing_visible" : "missing_unknown"
        }
    }

    var isMissing: Bool { if case .missing = self { return true } else { return false } }
    var isArrived: Bool { if case .arrived = self { return true } else { return false } }
    var isNotLastNight: Bool { if case .notLastNight = self { return true } else { return false } }
}

/// One tracker's check: a row per signal in `TrackerSignal` order, and what they add up to.
struct TrackerCheck: Equatable, Sendable, Identifiable {
    /// First match wins: checking › cantRead › unknownTracker › unidentified › silent › needsFix › nightMissing › ok.
    enum Overall: String, Equatable, Sendable {
        case checking, ok, nightMissing = "night_missing", needsFix = "needs_fix", silent
        case cantRead = "cant_read", unknownTracker = "unknown_tracker"
        /// An Apple device: Apple Health has records from Apple devices RYFT can't tell apart (no device model), so
        /// nothing is claimed (design.md §10).
        case unidentified
    }

    struct Row: Equatable, Sendable, Identifiable {
        let signal: TrackerSignal
        var check: SignalCheck
        var id: TrackerSignal { signal }
    }

    let trackerID: String
    /// What the text calls it: the vendor's app ("Garmin Connect"), an Apple device ("Apple Watch", "iPhone"), else
    /// the tracker's name; nil for Other.
    let app: String?
    var overall: Overall
    var rows: [Row]
    /// D2's "4 of 6 expected signals are arriving": the rows that arrived, missed last night or should arrive and
    /// don't. `no`, `partial` and `unverified` without data don't count; data beats the catalog, so they do once
    /// they arrive.
    var expected: Int
    var arriving: Int
    /// Signals that arrived although the catalog says `no` (catalog drift, logged by the model).
    var drift: [TrackerSignal] = []

    var id: String { trackerID }
    var needsFix: Int { rows.filter(\.check.isMissing).count }
    /// Rows and counts that mean something (not silent, can't read, Other or unidentified).
    var isCounted: Bool { [.ok, .needsFix, .nightMissing].contains(overall) }
}

/// The §4.4 table, pure: the probe's samples in, one tracker's check out.
enum TrackerCheckRules {
    /// How far back the check looks.
    static let window: TimeInterval = 48 * 3_600
    /// A night's signals: one older than when last night began didn't come last night.
    static let nightly: Set<TrackerSignal> = [.hrv, .restingHR, .sleep, .sleepStages, .respiratoryRate, .spo2]
    /// Before this hour the night is still being written: the one before is "last night".
    static let wakeHour = 8
    /// What the probe asks HealthKit about (stages come with sleep).
    static var streams: [HealthStream] { TrackerSignal.allCases.compactMap(\.stream) }

    /// When last night began: 18:00 the evening before (`RawNight.window`); from midnight until 08:00, the evening
    /// before that, since tonight isn't over yet.
    static func lastNightStart(before now: Date, calendar: Calendar = .current) -> Date {
        let start = RawNight.window(before: now, calendar: calendar)
        guard calendar.component(.hour, from: now) < wakeHour else { return start }
        return calendar.date(byAdding: .day, value: -1, to: start) ?? start
    }

    /// Before the probe answers: every row waiting (Other's and the can't-read trackers' rows come with the result).
    static func waiting(_ tracker: Tracker) -> TrackerCheck {
        let rows = tracker.integration == .none ? [] : TrackerSignal.allCases.map { TrackerCheck.Row(signal: $0, check: .waiting) }
        return TrackerCheck(trackerID: tracker.id, app: name(tracker), overall: .checking, rows: rows, expected: 0, arriving: 0)
    }

    /// `catalog` matches sources to trackers (T1's `match`); `alongside` are the other selected trackers, whose data
    /// makes a gap here `elsewhere` instead of `missing`. Samples from RYFT itself never count.
    static func classify(_ tracker: Tracker, samples: [SourceSample], visible: Set<HealthStream>,
                         now: Date, calendar: Calendar = .current,
                         catalog: TrackerCatalog, alongside: [Tracker] = []) -> TrackerCheck {
        let catalog = including(tracker, in: catalog)
        let since = now.addingTimeInterval(-window)
        let recent = samples.filter { $0.newest >= since && !HealthProbe.isRYFT($0.source) }
        switch tracker.integration {
        case .none:
            return TrackerCheck(trackerID: tracker.id, app: name(tracker), overall: .cantRead, rows: [], expected: 0, arriving: 0)
        case .unknown:
            return unknown(tracker, recent: recent, catalog: catalog)
        case .appleBuiltin, .vendorApp:
            break
        }
        let mine = recent.filter { catalog.match($0.source)?.id == tracker.id }
        if mine.isEmpty, tracker.integration == .appleBuiltin, recent.contains(where: isAnonymousApple) {
            return TrackerCheck(trackerID: tracker.id, app: name(tracker), overall: .unidentified,
                                rows: TrackerSignal.allCases.map { TrackerCheck.Row(signal: $0, check: .notSeenYet) },
                                expected: 0, arriving: 0)
        }
        let night = lastNightStart(before: now, calendar: calendar)
        let others = alongside.filter { $0.id != tracker.id }
        let rows = TrackerSignal.allCases.map { signal in
            TrackerCheck.Row(signal: signal, check: check(signal, of: tracker, mine: mine, recent: recent, visible: visible,
                                                          night: night, catalog: catalog, others: others))
        }
        let overall: TrackerCheck.Overall
        if mine.isEmpty {
            overall = .silent
        } else if rows.contains(where: \.check.isMissing) {
            overall = .needsFix
        } else if rows.contains(where: \.check.isNotLastNight) {
            overall = .nightMissing
        } else {
            overall = .ok
        }
        let drift = rows.filter { $0.check.isArrived && tracker.capabilities[$0.signal] == .no }.map(\.signal)
        return TrackerCheck(trackerID: tracker.id, app: name(tracker), overall: overall, rows: rows,
                            expected: rows.filter { $0.check.isArrived || $0.check.isNotLastNight || $0.check.isMissing }.count,
                            arriving: rows.filter(\.check.isArrived).count, drift: drift)
    }

    /// Without a selection: the trackers whose sources wrote in the window, in picker order; the iPhone only when
    /// nothing else did; Other when nothing matched.
    static func seen(_ samples: [SourceSample], catalog: TrackerCatalog, now: Date) -> [Tracker] {
        let since = now.addingTimeInterval(-window)
        let ids = Set(samples.filter { $0.newest >= since && !HealthProbe.isRYFT($0.source) }
            .compactMap { catalog.match($0.source)?.id })
        let found = catalog.trackers.filter { ids.contains($0.id) && $0.id != "iphone" }
        if !found.isEmpty { return found }
        return [catalog.tracker(ids.contains("iphone") ? "iphone" : "other")].compactMap { $0 }
    }

    /// The name in the text: the vendor's app; an Apple device by what it is (the catalog's `app_name` for them is
    /// the companion app, "Watch" or "Health", which no sentence should ask to open); nil for Other.
    private static func name(_ tracker: Tracker) -> String? {
        switch tracker.integration {
        case .vendorApp: return tracker.appName ?? tracker.name
        case .appleBuiltin: return tracker.id == "iphone" ? "iPhone" : tracker.name
        case .none: return tracker.name
        case .unknown: return nil
        }
    }

    /// A record from an Apple device that didn't say which (no device model): neither the watch nor the iPhone.
    private static func isAnonymousApple(_ sample: SourceSample) -> Bool {
        (sample.source.bundleID ?? "").lowercased().hasPrefix("com.apple.health.") && sample.source.deviceModel == nil
    }

    // swiftlint:disable:next function_parameter_count
    private static func check(_ signal: TrackerSignal, of tracker: Tracker, mine: [SourceSample], recent: [SourceSample],
                              visible: Set<HealthStream>, night: Date, catalog: TrackerCatalog,
                              others: [Tracker]) -> SignalCheck {
        let capability = tracker.capabilities[signal] ?? .unverified
        let newest: Date?
        if signal == .sleepStages {
            // Stages are a detail of sleep: nothing to judge without a night.
            let sleep = mine.filter { $0.stream == .sleep }
            guard !sleep.isEmpty else { return .notSeenYet }
            newest = sleep.filter { $0.hasStages == true }.map(\.newest).max()
        } else {
            newest = mine.filter { $0.stream == signal.stream }.map(\.newest).max()
        }
        if let newest {
            // Only a night the tracker promises can be missing: never the iPhone's, never a partly shared signal.
            let late = nightly.contains(signal) && newest < night && capability == .yes && tracker.id != "iphone"
            return late ? .notLastNight(lastSeen: newest) : .arrived(newest)
        }
        switch capability {
        case .no:
            return .notShared
        case .partial, .unverified:
            return .notSeenYet
        case .yes:
            // A day without a workout is no gap.
            if signal == .workouts { return .notSeenYet }
            if signal == .sleepStages { return .missing(visible: true) }
            let elsewhere = others.first { other in
                recent.contains { $0.stream == signal.stream && catalog.match($0.source)?.id == other.id }
            }
            if let elsewhere, let app = name(elsewhere) { return .elsewhere(app: app) }
            return .missing(visible: signal.stream.map(visible.contains) ?? false)
        }
    }

    /// Other (D2 C4): rows only for what apps the catalog doesn't know sent; nothing is promised, so nothing is
    /// missing.
    private static func unknown(_ tracker: Tracker, recent: [SourceSample], catalog: TrackerCatalog) -> TrackerCheck {
        let unmatched = recent.filter { catalog.match($0.source) == nil }
        let rows: [TrackerCheck.Row] = TrackerSignal.allCases.compactMap { signal in
            let newest = signal == .sleepStages
                ? unmatched.filter { $0.stream == .sleep && $0.hasStages == true }.map(\.newest).max()
                : unmatched.filter { $0.stream == signal.stream }.map(\.newest).max()
            return newest.map { TrackerCheck.Row(signal: signal, check: .arrived($0)) }
        }
        return TrackerCheck(trackerID: tracker.id, app: nil, overall: .unknownTracker, rows: rows,
                            expected: rows.count, arriving: rows.count)
    }

    /// A tracker from another copy of the catalog still matches its own sources.
    private static func including(_ tracker: Tracker, in catalog: TrackerCatalog) -> TrackerCatalog {
        guard catalog.tracker(tracker.id) == nil else { return catalog }
        return TrackerCatalog(version: catalog.version, trackers: [tracker] + catalog.trackers, healthAccess: catalog.healthAccess)
    }
}

/// Check sync's words (ui.md §5.7, design.md §4.5): what RYFT can know, never "denied". In the screen's language:
/// the app's own (`.main`), or a preview's `\.locale` (`String(localized:)` alone ignores that).
struct TrackerCheckText {
    let bundle: Bundle
    let locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
        let language = locale.language.languageCode?.identifier
        if let language, Bundle.main.preferredLocalizations.first?.hasPrefix(language) != true,
           let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) {
            self.bundle = bundle
        } else {
            bundle = .main
        }
    }

    private func s(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: bundle, locale: locale)
    }

    /// A row's name.
    func name(_ signal: TrackerSignal) -> String {
        switch signal {
        case .heartRate: return s("Heart rate")
        case .hrv: return s("HRV")
        case .restingHR: return s("Resting heart rate")
        case .sleep: return s("Sleep")
        case .sleepStages: return s("Sleep stages")
        case .respiratoryRate: return s("Breathing rate")
        case .spo2: return s("Blood oxygen")
        case .workouts: return s("Workouts")
        case .steps: return s("Steps")
        }
    }

    /// Inside a sentence: "RYFT can read resting heart rate, but …".
    func phrase(_ signal: TrackerSignal) -> String {
        switch signal {
        case .heartRate: return s("heart rate")
        case .hrv: return s("HRV")
        case .restingHR: return s("resting heart rate")
        case .sleep: return s("sleep")
        case .sleepStages: return s("sleep stages")
        case .respiratoryRate: return s("breathing rate")
        case .spo2: return s("blood oxygen")
        case .workouts: return s("workouts")
        case .steps: return s("steps")
        }
    }

    /// The row's trailing result: real clock times, never "x min ago".
    func result(_ check: SignalCheck, signal: TrackerSignal, app: String?, now: Date, calendar: Calendar = .current) -> String {
        switch check {
        case .waiting: return s("waiting…")
        case .checking: return s("checking…")
        case .arrived(let date):
            if signal == .sleep || signal == .sleepStages,
               date >= TrackerCheckRules.lastNightStart(before: now, calendar: calendar) {
                return s("last night")
            }
            return calendar.isDate(date, inSameDayAs: now) ? s("last \(Fmt.time(date, locale: locale))") : time(date, now: now, calendar: calendar)
        case .notLastNight(let date): return time(date, now: now, calendar: calendar)
        case .notShared: return app.map { s("Not shared by \($0)") } ?? s("Not shared")
        case .notSeenYet: return s("not seen yet")
        case .elsewhere(let other): return s("from \(other) instead")
        case .missing: return s("should arrive, nothing yet")
        }
    }

    /// `SyncLine.dataTime` in this language: "Yesterday 22:10", "Tue 22:10", then the date.
    private func time(_ date: Date, now: Date, calendar: Calendar) -> String {
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return s("Yesterday \(Fmt.time(date, locale: locale))")
        }
        let style = now.timeIntervalSince(date) < 6 * 86_400
            ? Date.FormatStyle(locale: locale).weekday(.abbreviated).hour().minute()
            : Date.FormatStyle(locale: locale).day().month(.abbreviated).hour().minute()
        return date.formatted(style)
    }

    /// VoiceOver's value for a row.
    func spoken(_ check: SignalCheck, signal: TrackerSignal, app: String?, now: Date) -> String {
        let result = result(check, signal: signal, app: app, now: now)
        switch check {
        case .waiting: return s("Waiting")
        case .checking: return s("Checking")
        case .arrived: return s("Arriving, \(result)")
        case .notLastNight: return s("Not since last night, last seen \(result)")
        case .notShared: return s("\(result), expected")
        case .notSeenYet: return s("Not seen yet")
        case .elsewhere: return result
        case .missing: return s("Should arrive, nothing yet. Fix available")
        }
    }

    /// "4 of 6 expected signals are arriving." and, with gaps, "2 need a fix."
    func summary(expected: Int, arriving: Int, needsFix: Int) -> String {
        let count = s("\(arriving) of \(expected) expected signals are arriving.")
        guard needsFix > 0 else { return count }
        return count + " " + s("\(needsFix) need a fix.")
    }

    /// The one announcement when the check is done: the counts of the trackers that have them, then what a silent
    /// tracker's card says.
    func announcement(_ checks: [TrackerCheck]) -> String {
        var parts = [s("Check finished.")]
        let counted = checks.filter(\.isCounted)
        if !counted.isEmpty {
            parts.append(summary(expected: counted.reduce(0) { $0 + $1.expected },
                                 arriving: counted.reduce(0) { $0 + $1.arriving },
                                 needsFix: counted.reduce(0) { $0 + $1.needsFix }))
        }
        parts += checks.filter { $0.overall == .silent }.map(silent)
        return parts.joined(separator: " ")
    }

    /// The fix's first sentence (§4.5): one signal with what RYFT can know about it, or several.
    func fixLead(_ check: TrackerCheck) -> String {
        let app = check.app ?? check.trackerID
        let missing = check.rows.filter(\.check.isMissing)
        guard missing.count == 1, let row = missing.first else {
            if check.trackerID == "apple_watch" || check.trackerID == "iphone" {
                return s("Several signals should arrive from \(app) and don't.")
            }
            return s("Several signals should arrive and don't. The cause is usually one permission in \(app).")
        }
        if row.check == .missing(visible: true) {
            return s("RYFT can read \(phrase(row.signal)), but none came from \(app) in the last 2 days.")
        }
        return s("RYFT doesn't see any \(phrase(row.signal)) in Apple Health. Either RYFT isn't allowed to read it, or \(app) isn't writing it.")
    }

    /// K5: nothing from the tracker. An app to open; an Apple device to wear; Other without a name.
    func silent(_ check: TrackerCheck) -> String {
        switch check.trackerID {
        case "iphone":
            return s("Nothing from this iPhone in the last 2 days. Carry it with you for a while, then tap Check again.")
        case "apple_watch":
            return s("No data from your Apple Watch yet. Wear it and keep it near your iPhone so it syncs, then tap Check again.")
        default:
            guard let app = check.app else {
                return s("No data from your tracker's app yet. Open it and let it sync, then tap Check again.")
            }
            return s("No data from \(app) yet. Open \(app) and let it sync, then tap Check again.")
        }
    }

    /// An Apple device RYFT can't tell apart from the others: neutral, nothing to fix.
    var unidentified: String {
        s("Apple Health has data from an Apple device, but RYFT can't tell which one. Nothing to fix here.")
    }
}

/// What the last check found, for the signed-in account: codes only (design.md §4.7). Report a problem sends it
/// as `sync_check`; Devices & sync (T2) reads it for "Last checked". `CachedDocument` "devices.check", wiped with
/// the account's other documents on sign-out. Entries, not a dictionary: the cache's snake-case coder would rename
/// dictionary keys.
struct TrackerCheckRecord: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let tracker: String
        /// A `TrackerSignal` raw value, or "overall".
        let signal: String
        let code: String
    }

    static let documentKey = "devices.check"
    /// Diagnostics leave an older check out: it no longer says how the sync is.
    static let reportAge: TimeInterval = 14 * 86_400

    let account: String
    let at: Date
    let entries: [Entry]

    init(account: String, at: Date, checks: [TrackerCheck]) {
        self.account = account
        self.at = at
        entries = checks.flatMap { check in
            [Entry(tracker: check.trackerID, signal: "overall", code: check.overall.rawValue)]
                + check.rows.compactMap { row in
                    row.check.code.map { Entry(tracker: check.trackerID, signal: row.signal.rawValue, code: $0) }
                }
        }
    }

    /// "checked 2026-10-22", then per tracker "garmin needs_fix heart_rate=arrived hrv=not_shared …": ids and codes,
    /// the check's day, never a time of day or a source's name.
    var lines: [String] {
        var order: [String] = []
        var byTracker: [String: [Entry]] = [:]
        for entry in entries {
            if byTracker[entry.tracker] == nil { order.append(entry.tracker) }
            byTracker[entry.tracker, default: []].append(entry)
        }
        return ["checked \(DayFormat.string(from: at))"] + order.map { tracker in
            let list = byTracker[tracker] ?? []
            let overall = list.first { $0.signal == "overall" }?.code ?? "-"
            return ([tracker, overall] + list.filter { $0.signal != "overall" }.map { "\($0.signal)=\($0.code)" })
                .joined(separator: " ")
        }
    }

    /// Demo data's last check: in memory, never in the account's store.
    @MainActor static var demo: TrackerCheckRecord?

    /// The signed-in account's last check (demo data's own in demo mode); nothing for another account.
    @MainActor static func load(_ env: AppEnvironment) -> TrackerCheckRecord? {
        if env.isDemo { return demo }
        guard let account = env.auth.accountID,
              let record = env.persistence.document(Self.self, key: documentKey), record.account == account else { return nil }
        return record
    }

    /// What diagnostics carry (Report a problem, Copy diagnostics): the last check, unless it's over 14 days old.
    /// It names tracker ids, so it goes with `devices.setup` on, like `trackers`.
    @MainActor static func forReport(_ env: AppEnvironment) -> TrackerCheckRecord? {
        guard env.flags.isOn(.devicesSetup) else { return nil }
        return load(env).flatMap { env.clock.now().timeIntervalSince($0.at) <= reportAge ? $0 : nil }
    }
}

/// Check sync (ui.md §5): the selected trackers, what HealthKit has from each in the last 48 h, and the fix for
/// what's missing. Only the user starts it, in the foreground: on appearance and with Check again. The reads run in
/// `HealthProbe`, off the main actor.
@MainActor
@Observable
final class TrackerCheckModel {
    enum Phase: Equatable {
        case idle, running, done
        /// RYFT never asked for Health access (D2 K9).
        case notAsked
        /// No Apple Health on this device.
        case unavailable
        /// The phone is locked (protected data): unlock and check again.
        case locked
        case failed
    }

    let catalog: TrackerCatalog
    /// The selection, in its order (resolved once; it doesn't change under the screen).
    let selection: [Tracker]
    /// What the cards show: the selection; without one, the trackers seen in Apple Health by the latest run.
    private(set) var trackers: [Tracker]
    private(set) var phase: Phase = .idle
    private(set) var checks: [TrackerCheck]
    /// Types RYFT sees from any source but itself.
    private(set) var visible: Set<HealthStream> = []
    private(set) var checkedAt: Date?

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let health: HealthStore
    @ObservationIgnored private var started = false

    /// `trackers`: catalog ids (`TrackerSelectionStore.trackers` once T2 lands); unknown ids are dropped.
    init(env: AppEnvironment, health: HealthStore, trackers ids: [String], catalog: TrackerCatalog? = nil) {
        let catalog = catalog ?? env.trackerCatalog
        var seen = Set<String>()
        let chosen = ids.filter { seen.insert($0).inserted }.compactMap(catalog.tracker)
        self.env = env
        self.health = health
        self.catalog = catalog
        selection = chosen
        trackers = chosen
        checks = chosen.map(TrackerCheckRules.waiting)
    }

    /// The one place that picks the store: in demo mode the `-RyftSyncCheck` scenario's (Debug), else the
    /// Garmin-like or Apple Watch one, never this iPhone's Health; otherwise `env.health`.
    static func make(env: AppEnvironment, trackers: [String]) -> TrackerCheckModel {
        guard env.isDemo else { return TrackerCheckModel(env: env, health: env.health, trackers: trackers) }
        let requested = SyncCheckScenario.requested
        let scenario = requested ?? (trackers.contains("garmin") ? .garmin : .appleWatch)
        return TrackerCheckModel(env: env, health: scenario.store(now: env.clock.now()),
                                 trackers: requested?.trackers ?? trackers)
    }

    var isRunning: Bool { phase == .running }
    var now: Date { env.clock.now() }
    /// Totals over the trackers with counts.
    var expected: Int { checks.filter(\.isCounted).reduce(0) { $0 + $1.expected } }
    var arriving: Int { checks.filter(\.isCounted).reduce(0) { $0 + $1.arriving } }
    var needsFix: Int { checks.reduce(0) { $0 + $1.needsFix } }
    /// The strong hint (§4.5): not one type visible, not even the iPhone's steps, so RYFT *may* not be allowed to
    /// read at all. Never "is".
    var mayNotRead: Bool { phase == .done && visible.isEmpty }
    /// K7, last on the screen: whenever a tracker is silent or has an unexpected gap.
    var showsPermissionCard: Bool {
        phase == .done && (mayNotRead || checks.contains { $0.overall == .silent || $0.needsFix > 0 })
    }

    /// On appearance: once per screen.
    func start(stagger: Bool) async {
        guard !started else { return }
        await run(stagger: stagger)
    }

    /// Reads HealthKit and classifies. `stagger` shows the rows top-down, 150 ms apart (off under Reduce Motion).
    func run(stagger: Bool = false) async {
        guard phase != .running else { return }
        // Before the first await, so a second tap can't start another run.
        started = true
        phase = .running
        let account = env.auth.accountID
        guard health.isAvailable else { phase = .unavailable; return }
        guard await health.accessStatus() != .notAsked else { phase = .notAsked; return }
        checks = Self.checking(trackers)
        let now = env.clock.now()
        do {
            let found = try await HealthProbe(health: health)
                .run(TrackerCheckRules.streams, since: now.addingTimeInterval(-TrackerCheckRules.window))
            visible = found.visible
            if selection.isEmpty {
                // Every run looks again: a tracker that synced since the last one is found now.
                trackers = TrackerCheckRules.seen(found.samples, catalog: catalog, now: now)
                checks = Self.checking(trackers)
            }
            let results = trackers.map {
                TrackerCheckRules.classify($0, samples: found.samples, visible: found.visible, now: now,
                                           catalog: catalog, alongside: trackers)
            }
            if stagger { await reveal(results) }
            checks = results
            checkedAt = now
            phase = .done
            results.forEach { HealthProbe.logDrift(tracker: $0.trackerID, signals: $0.drift) }
            save(results, at: now, account: account)
        } catch {
            checks = trackers.map(TrackerCheckRules.waiting)
            phase = ProtectedData.isLocked(error) ? .locked : .failed
        }
    }

    /// K9's Allow access: the system prompt, then the check.
    func requestAccess() async {
        try? await health.requestAuthorization()
        await run()
    }

    private static func checking(_ trackers: [Tracker]) -> [TrackerCheck] {
        trackers.map { tracker in
            var check = TrackerCheckRules.waiting(tracker)
            for i in check.rows.indices { check.rows[i].check = .checking }
            return check
        }
    }

    /// Each row's result 150 ms after its predecessor's, so the list reads top-down; a cancelled screen skips it.
    private func reveal(_ results: [TrackerCheck]) async {
        for (i, result) in results.enumerated() where i < checks.count && checks[i].trackerID == result.trackerID {
            for row in result.rows {
                guard let j = checks[i].rows.firstIndex(where: { $0.signal == row.signal }) else { continue }
                guard (try? await env.clock.sleep(for: .milliseconds(150))) != nil else { return }
                checks[i].rows[j].check = row.check
            }
        }
    }

    /// Only for the account the check began under: a sign-out or switch meanwhile keeps nothing.
    private func save(_ results: [TrackerCheck], at date: Date, account: String?) {
        if env.isDemo {
            TrackerCheckRecord.demo = TrackerCheckRecord(account: "demo", at: date, checks: results)
            return
        }
        guard let account, env.auth.accountID == account else { return }
        env.persistence.saveDocument(TrackerCheckRecord(account: account, at: date, checks: results),
                                     key: TrackerCheckRecord.documentKey, at: date)
    }

    /// Previews and screenshots: the screen in one state, without reading.
    func stage(_ phase: Phase, checks: [TrackerCheck]? = nil, visible: Set<HealthStream>? = nil) {
        started = true
        self.phase = phase
        if let checks { self.checks = checks }
        if let visible { self.visible = visible }
        if phase == .running {
            self.checks = trackers.map { tracker in
                var check = TrackerCheckRules.waiting(tracker)
                for i in check.rows.indices where i < 3 { check.rows[i].check = i < 2 ? .arrived(now) : .checking }
                return check
            }
        }
    }
}

// MARK: - report a problem

/// What a report is about when it comes from an error's Details (ui.md §5.3: the chip and the prefill).
struct ReportContext: Equatable, Sendable {
    /// The resource's name as Details shows it ("Today").
    let resource: String
    /// "503", or "No response" for a transport failure or timeout.
    let status: String
    /// Exactly as the platform sent it; it goes into `request_ids`.
    let requestID: String?
    /// The error body's `code` (`consent_required`), if any.
    var code: String?

    /// "403 consent_required".
    var statusText: String { [status, code ?? ""].filter { !$0.isEmpty }.joined(separator: " ") }
}

/// The install a report comes from: the top-level fields of `POST /v1/feedback`, and the locale.
struct FeedbackAbout: Equatable, Sendable {
    var appVersion: String
    var build: String
    var deviceModel: String
    var osVersion: String
    /// "de_DE": which strings the reporter saw.
    var locale: String

    @MainActor static var current: FeedbackAbout {
        FeedbackAbout(appVersion: AppInfo.marketingVersion, build: AppInfo.build, deviceModel: AppInfo.deviceModel,
                      osVersion: AppInfo.osVersion, locale: Locale.current.identifier)
    }
}

/// The sync as a report carries it: the phase, the queue and the backlog, and per data type how many records went
/// up on how many days, with the newest record's **day** only (a time of day from Apple Health can be a wake time).
struct FeedbackSync: Equatable, Sendable {
    struct Stream: Equatable, Sendable {
        /// `HealthStream.anchorID` ("sleep", "heartRate").
        let id: String
        let records: Int
        let days: Int
        /// Only its day is sent.
        let newest: Date?
    }

    var phase = SyncEngineState.Phase.idle.rawValue
    var recentDone = false
    var backfillDone = false
    var running = false
    var queued = false
    var backlogBytes = 0
    var streams: [Stream] = []
}

extension FeedbackSync {
    /// The engine's state and Sync details' rows, in the order the engine drains them.
    init(engine: SyncEngineState, backlogBytes: Int?, running: Bool, queued: Bool,
         streams: [SyncDetailsModel.StreamRow]) {
        self.init(phase: engine.phase.rawValue, recentDone: engine.recentDone, backfillDone: engine.backfillDone,
                  running: running, queued: queued, backlogBytes: backlogBytes ?? 0,
                  streams: streams.map { row in
                      Stream(id: row.id, records: row.progress?.sent ?? 0, days: row.progress?.days.count ?? 0,
                             newest: row.progress?.newest)
                  })
    }
}

/// `POST /v1/feedback` within API.md's limits: message 1–4000 characters, the four strings up to 64, at most
/// 20 request IDs of up to 64, diagnostics up to 32 KiB of JSON.
///
/// The diagnostics go through an allow-list: the keys in `keys`, each value built from one line template of
/// counts, statuses, codes, IDs, days and request times. Never a health value, never a time of day from Apple
/// Health, never a query string, never free text (Sync details' support text isn't sent).
enum FeedbackPayload {
    static let maxMessage = 4000
    static let maxField = 64
    static let maxRequestIDs = 20
    static let maxDiagnosticsBytes = 32 * 1024
    /// The last requests sent along (`APIStatus` keeps as many).
    static let maxRequests = 20
    /// Every key `diagnostics` may carry.
    static let keys: Set<String> = ["requests", "resources", "sync", "gates", "flags", "locale", "report_context", "trackers",
                                    "sync_check"]

    /// Characters as the platform counts them (Unicode scalars: Go's runes).
    static func length(_ text: String) -> Int { text.unicodeScalars.count }

    // swiftlint:disable:next function_parameter_count
    static func make(message: String, category: FeedbackCategory, includeDiagnostics: Bool,
                     requests: [APIStatus.RequestFailure], resources: [ReadResource: ResourceState] = [:],
                     sync: FeedbackSync, gates: Set<APIErrorCode>,
                     flags: [String: Bool], trackers: [String]? = nil, syncCheck: [String]? = nil,
                     context: ReportContext?, about: FeedbackAbout) -> FeedbackPost {
        let text = clipped(message.trimmingCharacters(in: .whitespacesAndNewlines), to: maxMessage)
        // Off: nothing is attached but the message (ui.md §5.2).
        guard includeDiagnostics else { return FeedbackPost(message: text, category: category) }
        return FeedbackPost(message: text, category: category,
                            appVersion: clipped(about.appVersion, to: maxField),
                            build: clipped(about.build, to: maxField),
                            deviceModel: clipped(about.deviceModel, to: maxField),
                            osVersion: clipped(about.osVersion, to: maxField),
                            requestIds: requestIDs(context: context, requests: requests, resources: resources),
                            diagnostics: diagnostics(requests: requests, resources: resources, sync: sync,
                                                     gates: gates, flags: flags, trackers: trackers, syncCheck: syncCheck,
                                                     context: context, locale: about.locale))
    }

    /// The context's ID first, then the failed requests' IDs (newest first), then the resources' last errors'
    /// (`ReadResource` order): each once, 1–64 bytes, at most 20.
    static func requestIDs(context: ReportContext?, requests: [APIStatus.RequestFailure],
                           resources: [ReadResource: ResourceState] = [:]) -> [String] {
        let failed = requests.filter { !(200..<300).contains($0.status) }.compactMap(\.requestID)
        let lastErrors = ReadResource.allCases.compactMap { resources[$0]?.lastError?.requestID }
        var seen = Set<String>()
        let ids = ([context?.requestID].compactMap { $0 } + failed + lastErrors)
            .filter { !$0.isEmpty && $0.utf8.count <= maxField && seen.insert($0).inserted }
        return Array(ids.prefix(maxRequestIDs))
    }

    /// One request: "GET /v1/sleep/plan 200 - 01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c 2026-10-21T18:12:03Z 412ms"
    /// (method, path through `redactedPath`, status, code, request ID, time, and the duration when measured).
    static func line(_ r: APIStatus.RequestFailure) -> String {
        var line = "\(r.method) \(redactedPath(r.path)) \(r.status) \(r.code ?? "-") \(r.requestID ?? "-") \(r.date.ISO8601Format())"
        if let ms = duration(of: r) { line += " \(ms)ms" }
        return line
    }

    /// How long the round trip took, as `APIClient` measured it (nil: not measured).
    static func duration(of request: APIStatus.RequestFailure) -> Int? { request.durationMs }

    /// What the app read, one line per resource (`ReadResource` order): "today 2026-10-21T14:05:12Z - - -",
    /// "me 2026-10-21T13:58:02Z 503 - 01a14ffa-…" (resource, last loaded, then the last error's status, code and
    /// request ID). From the read pipeline's record and nothing else: no counts, no retry times.
    static func resourceLines(_ states: [ReadResource: ResourceState]) -> [String] {
        ReadResource.allCases.map { resource in
            let state = states[resource] ?? ResourceState()
            let error = state.lastError
            return [resource.rawValue, state.fetchedAt.map { $0.ISO8601Format() } ?? "-", error?.statusText ?? "-",
                    error?.code ?? "-", error?.requestID ?? "-"].joined(separator: " ")
        }
    }

    /// The sync, one line each:
    /// "phase incremental · recent true · backfill true"
    /// "queue running false · queued false · backlog 0 B"
    /// "stream sleep · 412 rec · 31 days · newest 2026-10-21" (or "newest -")
    static func syncLines(_ sync: FeedbackSync) -> [String] {
        ["phase \(sync.phase) · recent \(sync.recentDone) · backfill \(sync.backfillDone)",
         "queue running \(sync.running) · queued \(sync.queued) · backlog \(sync.backlogBytes) B"]
            + sync.streams.map { s in
                "stream \(s.id) · \(s.records) rec · \(s.days) days · newest \(s.newest.map(DayFormat.string) ?? "-")"
            }
    }

    // swiftlint:disable function_parameter_count
    /// The allow-list: `requests` (newest first), `resources`, `sync`, `gates`, `flags`, `locale`, with
    /// `devices.setup` on `trackers` (catalog ids, "garmin,oura", never a device's name), after a Check sync
    /// `sync_check` (`TrackerCheckRecord.lines`: tracker ids and result codes) and, from an error's Details,
    /// `report_context`. Over 32 KiB the oldest requests go first, then resources and sync.
    static func diagnostics(requests: [APIStatus.RequestFailure], resources: [ReadResource: ResourceState],
                            sync: FeedbackSync, gates: Set<APIErrorCode>, flags: [String: Bool],
                            trackers: [String]? = nil, syncCheck: [String]? = nil, context: ReportContext?,
                            locale: String) -> [String: String] {
        // swiftlint:enable function_parameter_count
        var base = [
            "gates": gates.isEmpty ? "-" : gates.map(\.rawValue).sorted().joined(separator: ","),
            "flags": flags.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value ? 1 : 0)" }.joined(separator: ","),
            "locale": locale,
        ]
        if let context {
            base["report_context"] = [context.resource, context.statusText, context.requestID ?? "-"]
                .joined(separator: " · ")
        }
        if let trackers { base["trackers"] = trackers.isEmpty ? "-" : trackers.joined(separator: ",") }
        if let syncCheck, !syncCheck.isEmpty { base["sync_check"] = syncCheck.joined(separator: "\n") }
        let syncText = syncLines(sync).joined(separator: "\n")
        let resourcesText = resourceLines(resources).joined(separator: "\n")
        func assembled(_ lines: [String]) -> [String: String] {
            var d = base
            d["sync"] = syncText
            d["resources"] = resourcesText
            if !lines.isEmpty { d["requests"] = lines.joined(separator: "\n") }
            return d
        }
        var lines = requests.prefix(maxRequests).map(line)
        while size(assembled(lines)) > maxDiagnosticsBytes, !lines.isEmpty { lines.removeLast() }
        let whole = assembled(lines)
        if size(whole) <= maxDiagnosticsBytes { return whole }
        return size(base) <= maxDiagnosticsBytes ? base : [:]
    }

    /// The bytes the platform measures: the object as the shared encoder writes it.
    static func size(_ diagnostics: [String: String]) -> Int {
        (try? APIClient.jsonEncoder.encode(diagnostics).count) ?? .max
    }

    static func clipped(_ text: String, to limit: Int) -> String {
        guard length(text) > limit else { return text }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: text.unicodeScalars.prefix(limit))
        return String(view)
    }
}

/// A report waiting for a connection: the `FeedbackPost` as it will go out (the mirror stays `Encodable`), and the
/// account it belongs to. The diagnostics are pairs, so the cache's snake-case coder can't rename their keys.
struct QueuedFeedback: Codable, Equatable, Identifiable {
    struct Entry: Codable, Equatable {
        let key: String
        let value: String
    }

    let id: UUID
    /// `AuthService.accountID` when it was written ("demo" in demo mode): it never goes out as anyone else.
    let account: String
    let queuedAt: Date
    let message: String
    let category: FeedbackCategory?
    let appVersion: String?
    let build: String?
    let deviceModel: String?
    let osVersion: String?
    let requestIds: [String]
    let diagnostics: [Entry]?

    init(_ post: FeedbackPost, account: String, id: UUID = UUID(), queuedAt: Date) {
        self.id = id
        self.account = account
        self.queuedAt = queuedAt
        message = post.message
        category = post.category
        appVersion = post.appVersion
        build = post.build
        deviceModel = post.deviceModel
        osVersion = post.osVersion
        requestIds = post.requestIds
        diagnostics = post.diagnostics.map { pairs in
            pairs.sorted { $0.key < $1.key }.map { Entry(key: $0.key, value: $0.value) }
        }
    }

    var post: FeedbackPost {
        FeedbackPost(message: message, category: category, appVersion: appVersion, build: build,
                     deviceModel: deviceModel, osVersion: osVersion, requestIds: requestIds,
                     diagnostics: diagnostics.map { entries in
                         Dictionary(entries.map { ($0.key, $0.value) }) { _, last in last }
                     })
    }
}

/// Where reports wait for a connection. Tests replace it to make saving fail.
@MainActor
protocol FeedbackQueueStore: AnyObject {
    func load() -> [QueuedFeedback]
    /// `false`: the list didn't reach the disk.
    @discardableResult func save(_ items: [QueuedFeedback]) -> Bool
}

/// `CachedDocument` "feedback.queue", wiped with the account's other documents on sign-out. Demo data's
/// reports wait under their own key, so they never reach the account's platform.
@MainActor
final class PersistentFeedbackQueue: FeedbackQueueStore {
    static let key = "feedback.queue"
    static let demoKey = "feedback.queue.demo"

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    private var key: String { env.isDemo ? Self.demoKey : Self.key }

    func load() -> [QueuedFeedback] {
        env.persistence.document([QueuedFeedback].self, key: key) ?? []
    }

    @discardableResult
    func save(_ items: [QueuedFeedback]) -> Bool {
        let store = env.persistence
        if items.isEmpty {
            store.removeDocument(key: key)
        } else {
            store.saveDocument(items, key: key, at: env.clock.now())
        }
        // The store logs a failed save and keeps the change pending: then it isn't on disk.
        return load().map(\.id) == items.map(\.id) && !store.context.hasChanges
    }
}

/// Profile → About → Report a problem, and "Send to RYFT" from an error's Details (ui.md §5).
///
/// A report is saved before it's posted, so closing the app or losing the connection doesn't lose it.
/// `204` → sent; no connection, a timeout or `5xx` → queued and sent on reconnect (`flush`); `429` (10 a day)
/// → rate limited, the message kept, nothing queued; `400`/`413`/`422` → rejected, dropped. A report belongs to
/// the account it was written in: signed out nothing is queued, and a queued report goes out only as that account.
@MainActor
@Observable
final class ReportProblemModel {
    /// `sent` and `queued` replace the form; the others show on it, with the message kept.
    enum Result: Equatable { case sent, queued, rateLimited, rejected, saveFailed, signedOut }

    /// How a post went.
    enum Delivery {
        case delivered
        case rateLimited(Error)
        case rejected(Error)
        case later
    }

    /// The character count shows above this (ui.md §5.2).
    static let countFrom = 3500
    /// Reports kept for later at most (the platform takes 10 a day).
    static let maxQueued = 20

    private let env: AppEnvironment
    private let apiStatus: APIStatus
    private let sync: @MainActor () -> FeedbackSync
    private let resources: @MainActor () -> [ReadResource: ResourceState]
    /// What the user wears (ids), while `devices.setup` is on; nil: not sent.
    private let trackers: @MainActor () -> [String]?
    private let queue: FeedbackQueueStore

    var message = ""
    var category: FeedbackCategory = .other
    var includeDiagnostics = true
    private(set) var context: ReportContext?
    private(set) var result: Result?
    /// The refusal's status and request ID, for Details.
    private(set) var resultDetails: String?
    private(set) var sending = false
    /// Reports saved for later: "1 waiting to send".
    private(set) var waiting = 0
    /// Being posted (by `send` or `flush`): never twice at once.
    @ObservationIgnored private var inFlight: Set<UUID> = []
    @ObservationIgnored private var flushing = false
    /// Bumped on an account change: a post that returns afterwards doesn't touch the new account's screen.
    @ObservationIgnored private var generation = 0
    /// A preview or screenshot staged the screen: the next `prepare` leaves it.
    @ObservationIgnored private var staged = false

    /// `resources` is the read pipeline's record and `sync` Sync details' state, read when a report is written
    /// (only `FeedbackPayload.resourceLines`' and `FeedbackSync`'s fields go out).
    init(env: AppEnvironment, apiStatus: APIStatus, queue: FeedbackQueueStore? = nil,
         resources: @escaping @MainActor () -> [ReadResource: ResourceState] = { [:] },
         trackers: @escaping @MainActor () -> [String]? = { nil },
         sync: @escaping @MainActor () -> FeedbackSync) {
        self.env = env
        self.apiStatus = apiStatus
        self.resources = resources
        self.trackers = trackers
        self.sync = sync
        self.queue = queue ?? PersistentFeedbackQueue(env: env)
        reloadWaiting()
    }

    /// Whose reports these are: the signed-in account, "demo" with demo data, `nil` signed out.
    private var account: String? { env.isDemo ? "demo" : env.auth.accountID }
    /// Demo data: a report goes to the in-memory platform, and the sent state says so.
    var isDemo: Bool { stagedDemo ?? env.isDemo }
    /// Previews and screenshots run on demo data but show the live wording unless they ask.
    @ObservationIgnored private var stagedDemo: Bool?

    // MARK: form

    var length: Int { FeedbackPayload.length(message) }
    var showsCount: Bool { length > Self.countFrom }
    var isTooLong: Bool { length > FeedbackPayload.maxMessage }

    var canSend: Bool {
        !sending && !isTooLong && result != .rateLimited
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func prefill(_ context: ReportContext) -> String {
        String(localized: "Refreshing \(context.resource) didn't work.")
    }

    /// The screen appears: from Details (`context`) a bug report about it, pre-filled; from Profile the draft
    /// as it was. A report that was sent or queued starts a fresh one.
    func prepare(_ context: ReportContext?) {
        if staged {
            staged = false
            return
        }
        result = nil
        resultDetails = nil
        let oldPrefill = self.context.map(Self.prefill)
        let hadContext = self.context != nil
        self.context = context
        if let context {
            category = .bug
            if message.isEmpty || message == oldPrefill { message = Self.prefill(context) }
        } else if hadContext {
            category = .other
            if message == oldPrefill { message = "" }
        }
        reloadWaiting()
    }

    /// Signed out or another account: the draft was the previous account's.
    func accountChanged() {
        generation += 1
        staged = false
        message = ""
        category = .other
        includeDiagnostics = true
        context = nil
        result = nil
        resultDetails = nil
        reloadWaiting()
    }

    /// The request as it would go out now.
    func payload() -> FeedbackPost {
        FeedbackPayload.make(message: message, category: category, includeDiagnostics: includeDiagnostics,
                             requests: apiStatus.requests, resources: includeDiagnostics ? resources() : [:],
                             sync: includeDiagnostics ? sync() : FeedbackSync(),
                             gates: apiStatus.gates, flags: flagValues, trackers: trackers(),
                             syncCheck: includeDiagnostics ? syncCheck : nil, context: context, about: .current)
    }

    /// "What's included" lists the trackers only when they go out.
    var includesTrackers: Bool { trackers() != nil }

    /// The last Check sync as diagnostics carry it (ids and codes), when there is a recent one: "What's included"
    /// lists it only then.
    var syncCheck: [String]? { TrackerCheckRecord.forReport(env)?.lines }

    private var flagValues: [String: Bool] {
        Dictionary(uniqueKeysWithValues: FeatureFlag.allCases.map { ($0.rawValue, env.flags.isOn($0)) })
    }

    func copyMessage() {
        LocalPasteboard.copy(message)
    }

    // MARK: sending

    func send() async {
        guard canSend else { return }
        result = nil
        resultDetails = nil
        // Signed out there's no account to send it as, nor to keep it for.
        guard let account else {
            result = .signedOut
            return
        }
        sending = true
        defer { sending = false }
        let generation = generation
        let item = QueuedFeedback(payload(), account: account, queuedAt: env.clock.now())
        // Saved first: a report the app is closed on, or that meets no connection, isn't lost.
        let saved = queue.save(Array((queue.load() + [item]).suffix(Self.maxQueued)))
        reloadWaiting()
        guard env.connectivity.isOnline else {
            keepForLater(item, saved: saved)
            return
        }
        inFlight.insert(item.id)
        let delivery = await deliver(item)
        inFlight.remove(item.id)
        guard generation == self.generation else {
            // The account changed meanwhile: what's left of it isn't the new account's.
            dequeue(item)
            return
        }
        switch delivery {
        case .delivered:
            dequeue(item)
            finish(.sent)
        case .rateLimited(let error):
            dequeue(item)
            result = .rateLimited
            resultDetails = error.diagnosticDetails
        case .rejected(let error):
            dequeue(item)
            result = .rejected
            resultDetails = error.diagnosticDetails
        case .later:
            keepForLater(item, saved: saved)
        }
    }

    /// Back online, or the app became active: what's queued for this account goes out, oldest first; another
    /// account's reports are dropped. The queue is read again before every post, so a report `send` is posting
    /// or has settled is never posted again. It stops at a report that can't go yet (no connection, `5xx`) or at
    /// the daily cap; the rest waits for the next time.
    func flush() async {
        guard !flushing else { return }
        flushing = true
        defer {
            flushing = false
            reloadWaiting()
        }
        var tried: Set<UUID> = []
        while env.connectivity.isOnline, let account {
            let items = queue.load()
            if items.contains(where: { $0.account != account }) {
                queue.save(items.filter { $0.account == account })
            }
            let next = items
                .filter { $0.account == account && !inFlight.contains($0.id) && !tried.contains($0.id) }
                .min { $0.queuedAt < $1.queuedAt }
            guard let item = next else { return }
            tried.insert(item.id)
            inFlight.insert(item.id)
            let delivery = await deliver(item)
            inFlight.remove(item.id)
            switch delivery {
            case .delivered, .rejected: dequeue(item)
            case .rateLimited, .later: return
            }
        }
    }

    /// `429` is the daily cap. `400`, `413` and `422` refuse the report itself: dropped. No connection, a
    /// timeout, `5xx`, an ended session or a route that isn't live yet: later.
    nonisolated static func classify(_ error: Error) -> Delivery {
        switch (error as? APIError)?.status {
        case 429?: return .rateLimited(error)
        case 400?, 413?, 422?: return .rejected(error)
        default: return .later
        }
    }

    private func deliver(_ item: QueuedFeedback) async -> Delivery {
        do {
            try await env.api.postFeedback(item.post)
            return .delivered
        } catch {
            return Self.classify(error)
        }
    }

    /// Queued, or, when it couldn't be saved, not kept at all (it mustn't go out after "Couldn't save").
    private func keepForLater(_ item: QueuedFeedback, saved: Bool) {
        if saved {
            finish(.queued)
        } else {
            dequeue(item)
            result = .saveFailed
        }
    }

    /// Sent or queued: the next report starts fresh.
    private func finish(_ outcome: Result) {
        result = outcome
        message = ""
        category = .other
        includeDiagnostics = true
    }

    private func dequeue(_ item: QueuedFeedback) {
        queue.save(queue.load().filter { $0.id != item.id })
        reloadWaiting()
    }

    /// The queue may have changed underneath (sign-out wipes it).
    func reloadWaiting() {
        waiting = queue.load().count
    }

    // MARK: previews and screenshots

    /// One state of the screen, without a platform.
    func stage(message: String = "", category: FeedbackCategory = .other, includeDiagnostics: Bool = true,
               context: ReportContext? = nil, result: Result? = nil, sending: Bool = false, waiting: Int = 0,
               demo: Bool = false) {
        staged = true
        stagedDemo = demo
        self.message = message
        self.category = category
        self.includeDiagnostics = includeDiagnostics
        self.context = context
        self.result = result
        resultDetails = result == .rateLimited ? "HTTP 429 · Request ID 01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c" : nil
        self.sending = sending
        self.waiting = waiting
    }
}

extension ProfileViewModel {
    /// Signed out or another account (`previous`: the account before): its last requests (and the responses still
    /// on their way) and a report's draft were that account's, and must never go out as this one. A first sign-in
    /// leaves no account behind, so its first requests (Apple authorization, the gate check) stay.
    func accountChanged(from previous: String?) {
        if previous != nil { apiStatus.forgetRequests() }
        report.accountChanged()
    }
}

/// Copies text for this iPhone only (not Handoff's universal clipboard), gone after ten minutes: Copy message
/// and Copy diagnostics.
enum LocalPasteboard {
    static let lifetime: TimeInterval = 10 * 60

    @MainActor static func copy(_ text: String) {
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]],
                                      options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(lifetime)])
    }
}

extension AppInfo {
    /// "1.0.0".
    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// "20261021.081500".
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// The hardware model, "iPhone17,1" (in the simulator, the model it simulates).
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: info.machine) { raw in
            String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
        }
    }
}

// MARK: - devices & sync

/// What the user wears, for one account (design.md §3.1): catalog ids in picker order, `["iphone"]` for just the
/// iPhone, and which guides were finished or put off.
struct TrackerSelection: Codable, Equatable, Sendable {
    let account: String
    var trackers: [String]
    var updatedAt: Date
    /// Guides marked "Done".
    var setUp: [String] = []
    /// "Show me again later" (Devices & sync: "Set up later").
    var later: [String] = []
}

/// The selection, stored like the read record (`reads.state`): a `CachedDocument` "devices.selection" for the
/// signed-in account only, carrying its account ID and read only when that matches. Sign-out wipes it with the
/// store, and an account change reloads (`accountChanged`). Demo data keeps its own in memory. Local until API.md
/// has `User.trackers` (design.md §3.4).
@MainActor
@Observable
final class TrackerSelectionStore {
    static let documentKey = "devices.selection"
    /// "Just my iPhone": on its own or not at all.
    nonisolated static let iPhone = "iphone"
    /// Demo data wears an Apple Watch, unless a run says otherwise (`-RyftTrackers garmin,oura`, Debug).
    static let demoTrackers = ["apple_watch"]

    @ObservationIgnored private let env: AppEnvironment
    /// The signed-in account's, as stored.
    private var live: TrackerSelection?
    private var demo: TrackerSelection
    /// Previews and screenshot runs on a real account (`stage`): shown, never saved.
    private var staged: [String]?
    /// `-RyftTrackers` (Debug): shown over a real account's choice for the launch, never saved.
    private let launch: [String]?

    init(env: AppEnvironment, launch: [String]? = TrackerSelectionStore.launchTrackers) {
        self.env = env
        self.launch = launch
        var ids = Self.demoTrackers
        #if DEBUG
        // `-RyftSyncCheck <scenario>`: the trackers the scenario's check reads.
        if let scenario = SyncCheckScenario.requested { ids = scenario.trackers }
        #endif
        if let launch { ids = launch }
        demo = TrackerSelection(account: "demo", trackers: ids, updatedAt: .distantPast)
        accountChanged()
    }

    /// nil: nothing chosen (the step was skipped, or another account's answer).
    var selection: TrackerSelection? {
        if env.isDemo { return demo }
        guard let account = env.auth.accountID else { return nil }
        // A staged or (Debug) `-RyftTrackers` choice on a real account shows over the stored one, in memory only;
        // what was marked set up or later stays the stored one's.
        if let ids = shown {
            return TrackerSelection(account: account, trackers: ids, updatedAt: stored?.updatedAt ?? .distantPast,
                                    setUp: stored?.setUp ?? [], later: stored?.later ?? [])
        }
        return stored
    }

    /// What's stored for the signed-in account (demo data's own in demo mode): the only choice that marks and
    /// saves touch, so a staged or launch choice never becomes the account's.
    private var stored: TrackerSelection? {
        if env.isDemo { return demo }
        guard let account = env.auth.accountID, let live, live.account == account else { return nil }
        return live
    }

    private var shown: [String]? { staged ?? launch }

    /// `-RyftTrackers garmin,oura` (Debug builds; nil in Release): the demo choice, and a real account's for the
    /// launch.
    nonisolated static var launchTrackers: [String]? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "RyftTrackers").map {
            $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        #else
        nil
        #endif
    }

    /// The catalog's trackers that were picked, in picker order (a remote copy may have dropped one). Nothing
    /// chosen: nothing read (the catalog may not be decoded yet at launch).
    var trackers: [String] {
        guard let picked = selection?.trackers, !picked.isEmpty else { return [] }
        return Self.normalized(picked, catalog: env.trackerCatalog)
    }

    /// The sources Today's night hint may weigh (design.md §6.2, §9.3): with `devices.setup` on and a choice made,
    /// a source the catalog matches to a tracker that wasn't chosen goes; everything else stays, the iPhone's own
    /// records and sources no tracker claims included (an Apple Watch without a device model is still a candidate,
    /// as T1's rule has it). Without a choice, all of them.
    func worn(_ freshness: [SourceFreshness]) -> [SourceFreshness] {
        guard env.flags.isOn(.devicesSetup) else { return freshness }
        let chosen = Set(trackers)
        guard !chosen.isEmpty else { return freshness }
        let catalog = env.trackerCatalog
        return freshness.filter { source in
            if source.isPhone { return true }
            guard let tracker = catalog.match(source.ref) else { return true }
            return chosen.contains(tracker.id)
        }
    }

    /// Saves what was picked: known ids only, de-duplicated, in picker order; "Just my iPhone" alone. Guides of
    /// trackers no longer worn are forgotten.
    func set(_ ids: [String]) {
        let picked = Self.normalized(ids, catalog: env.trackerCatalog)
        staged = nil // a real choice replaces a staged one
        mutate { s in
            s.trackers = picked
            s.setUp.removeAll { !picked.contains($0) }
            s.later.removeAll { !picked.contains($0) }
        }
    }

    /// Only for a tracker in the stored choice (a staged one stays unmarked).
    func markSetUp(_ id: String) {
        guard stored?.trackers.contains(id) == true else { return }
        mutate { s in
            s.later.removeAll { $0 == id }
            if !s.setUp.contains(id) { s.setUp.append(id) }
        }
    }

    func markLater(_ id: String) {
        guard stored?.trackers.contains(id) == true else { return }
        mutate { s in
            s.setUp.removeAll { $0 == id }
            if !s.later.contains(id) { s.later.append(id) }
        }
    }

    func isLater(_ id: String) -> Bool { selection?.later.contains(id) ?? false }

    /// Signed in, out, or as someone else: that account's answer, or none.
    func accountChanged() {
        staged = nil
        guard let account = env.auth.accountID,
              let saved = env.persistence.document(TrackerSelection.self, key: Self.documentKey), saved.account == account
        else {
            live = nil
            return
        }
        live = saved
    }

    /// Previews and screenshot runs: this choice, in memory. Demo data's becomes demo's own; a real account's is only
    /// shown, never saved or marked.
    func stage(_ ids: [String]) {
        if env.isDemo {
            demo.trackers = ids
        } else {
            staged = ids
        }
    }

    private func mutate(_ change: (inout TrackerSelection) -> Void) {
        let now = env.clock.now()
        if env.isDemo {
            change(&demo)
            demo.updatedAt = now
            return
        }
        guard let account = env.auth.accountID else { return }
        // From what's stored, never a staged or launch choice (those stay in memory).
        var s = stored ?? TrackerSelection(account: account, trackers: [], updatedAt: now)
        change(&s)
        s.updatedAt = now
        live = s
        env.persistence.saveDocument(s, key: Self.documentKey, at: now)
    }

    /// Known ids only, once each, in the catalog's order; "Just my iPhone" excludes the rest.
    nonisolated static func normalized(_ ids: [String], catalog: TrackerCatalog) -> [String] {
        let known = Set(ids.filter { catalog.tracker($0) != nil })
        if known.contains(iPhone) { return [iPhone] }
        return catalog.trackers.map(\.id).filter(known.contains)
    }

    /// A tile tapped (ui.md §2.3): "Just my iPhone" clears every other choice, any other tile clears it.
    /// `cleared`: other choices went, which VoiceOver announces.
    nonisolated static func toggled(_ id: String, in picked: [String]) -> (picked: [String], cleared: Bool) {
        if picked.contains(id) { return (picked.filter { $0 != id }, false) }
        if id == iPhone { return ([iPhone], !picked.isEmpty) }
        return (picked.filter { $0 != iPhone } + [id], false)
    }

    /// A tracker whose data needs more than Apple Health itself: everything but the Apple Watch and the iPhone.
    nonisolated static func needsSetup(_ tracker: Tracker) -> Bool { tracker.integration != .appleBuiltin }
}

/// Profile → Data → Devices & sync (ui.md §4): what the user wears and each tracker's card, what Apple Health
/// has seen (`User.sources`, with RYFT's names), RYFT's own Health access, and the way to Sync details.
@MainActor
@Observable
final class DevicesViewModel {
    private let state: AppState
    let selection: TrackerSelectionStore
    private(set) var healthStatus: HealthAccess = .unknown

    init(state: AppState, selection: TrackerSelectionStore) {
        self.state = state
        self.selection = selection
    }

    private var env: AppEnvironment { state.env }
    var catalog: TrackerCatalog { env.trackerCatalog }
    /// `devices.setup`: off, Profile looks as it did.
    var isEnabled: Bool { env.flags.isOn(.devicesSetup) }

    var trackers: [Tracker] { selection.trackers.compactMap(catalog.tracker) }

    /// Profile → Data's row: "Garmin · Oura", "Garmin · Oura · +1", or "Not set".
    var summary: String {
        let names = trackers.map(\.title)
        guard !names.isEmpty else {
            return String(localized: "devices.summary.none", defaultValue: "Not set",
                          comment: "Profile → Data → Devices & sync row when no tracker is chosen.")
        }
        let shown = names.prefix(2).joined(separator: " · ")
        return names.count > 2 ? "\(shown) · +\(names.count - 2)" : shown
    }

    /// The last Check sync (`TrackerCheckRecord`), reloaded when the screen shows again.
    private(set) var lastCheck: TrackerCheckRecord?

    func reloadCheck() { lastCheck = TrackerCheckRecord.load(env) }

    /// Under each tracker's name: put off, else the last check's verdict for it, else "Not checked yet".
    func status(of tracker: Tracker) -> String {
        if selection.isLater(tracker.id) { return String(localized: "Set up later") }
        let code = lastCheck?.entries.first { $0.tracker == tracker.id && $0.signal == "overall" }?.code
        switch code.flatMap(TrackerCheck.Overall.init(rawValue:)) {
        case .ok?: return String(localized: "Data arrives")
        case .needsFix?: return String(localized: "Needs a fix")
        case .nightMissing?: return String(localized: "Last night missing")
        case .silent?: return String(localized: "Nothing in the last 2 days")
        case .cantRead?: return String(localized: "Can't be read on iPhone")
        case .unknownTracker?, .unidentified?: return String(localized: "Checked")
        case .checking?, nil: return String(localized: "Not checked yet")
        }
    }

    /// Under Check sync: "Last checked Yesterday 22:10", or "Not checked yet".
    var lastCheckedText: String {
        guard let at = lastCheck?.at else { return String(localized: "Not checked yet") }
        return String(localized: "Last checked \(SyncLine.dataTime(at, now: env.clock.now()))")
    }

    /// The picker sheet's Done.
    func save(_ ids: [String]) { selection.set(ids) }

    // MARK: seen in Apple Health

    struct SourceRow: Identifiable, Equatable {
        let id: String
        /// RYFT's name for it ("Garmin Connect"), or HealthKit's.
        let name: String
        /// "Heart rate, sleep and steps".
        let kinds: String
        let lastSeen: Date
        /// A tracker in the catalog, or one of Apple's own devices; otherwise "Not a tracker RYFT knows".
        let known: Bool
    }

    /// `User.sources`: what sent data in the last 30 days, newest first, by RYFT's names.
    var sources: [SourceRow] {
        let catalog = catalog
        return (state.user?.sources ?? []).map { s in
            let ref = SourceRef(name: s.name, bundleID: s.bundleId, deviceModel: nil)
            let apple = s.bundleId?.lowercased().hasPrefix("com.apple.") ?? false
            return SourceRow(id: s.bundleId ?? s.name, name: catalog.displayName(ref), kinds: Self.kinds(s.kinds),
                             lastSeen: s.lastSeen, known: apple || catalog.match(ref) != nil)
        }
    }

    func lastSeenText(_ row: SourceRow) -> String {
        String(localized: "Last data \(SyncLine.dataTime(row.lastSeen, now: env.clock.now()))")
    }

    static func kinds(_ kinds: [SourceKind]) -> String {
        let names = kinds.map { kind -> String in
            switch kind {
            case .energy: return String(localized: "active energy")
            case .hr: return String(localized: "heart rate")
            case .hrv: return String(localized: "HRV")
            case .resp: return String(localized: "breathing rate")
            case .sleep: return String(localized: "sleep")
            case .spo2: return String(localized: "blood oxygen")
            case .steps: return String(localized: "steps")
            case .workout: return String(localized: "workouts")
            }
        }
        let text = names.formatted(.list(type: .and))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: Apple Health access

    var healthStatusText: String {
        switch healthStatus {
        case .unavailable: return String(localized: "Not available")
        case .notAsked: return String(localized: "Not requested")
        case .asked: return String(localized: "Requested")
        case .unknown: return Fmt.placeholder
        }
    }

    var canAskForHealth: Bool { healthStatus == .notAsked }
    /// The catalog's route to RYFT's own read permission (Health → … → Apps → RYFT).
    var healthAccessSteps: [String] { catalog.healthAccess.current }

    func refreshHealthStatus() async { healthStatus = await env.health.accessStatus() }

    func requestHealthAccess() async {
        try? await env.health.requestAuthorization()
        await refreshHealthStatus()
    }

    /// On appearance: the catalog when due (never in demo mode or offline).
    func appeared() async {
        await refreshHealthStatus()
        await env.catalogStore.refreshIfDue()
    }
}

/// What a tracker's matrix means for RYFT's features (design.md §8, ui.md §3.2): the setup card's line. Mirrors
/// the platform's model: Strain needs heart rate; Sleep needs sleep; Recovery and Readiness need sleep and resting
/// heart rate, and Recovery uses whichever of HRV, resting heart rate, sleep and breathing rate arrive. What's
/// missing is said in words, never as ✗. Pure.
enum RyftFeatures {
    /// Resting heart rate derived from overnight heart rate: false until API.md documents it (lead's decision 10);
    /// the ticket that lands that contract flips it.
    static let restingHRFromHeartRate = false
    /// Readiness without HRV: the platform calibrating from resting-heart-rate nights alone (design.md §7). False
    /// until API.md documents it (the ticket that lands that contract flips it): today a day's baselines need HRV
    /// nights as well (`baseline_days = min(N_hrv, N_rhr)`), so without HRV there's no Readiness.
    static let baselinesWithoutHRV = false

    enum Feature: CaseIterable, Sendable {
        case strain, sleep, recovery, readiness

        var name: String {
            switch self {
            case .strain: return String(localized: "Strain")
            case .sleep: return String(localized: "Sleep")
            case .recovery: return String(localized: "Recovery")
            case .readiness: return String(localized: "Readiness")
            }
        }
    }

    /// The line and how VoiceOver says it ("✓" as "yes").
    struct Line: Equatable, Sendable {
        let text: String
        let spoken: String
    }

    /// nil for "Other": what arrives depends on the tracker.
    static func line(for tracker: Tracker, derivedRestingHR: Bool = restingHRFromHeartRate,
                     baselinesWithoutHRV: Bool = baselinesWithoutHRV) -> Line? {
        switch tracker.integration {
        case .unknown:
            return nil
        case .none:
            return line(ok: [String(localized: "Steps")],
                        rest: [String(localized: "Sleep, Strain, Recovery and Readiness stay empty without data from your tracker")])
        case .appleBuiltin where tracker.isJustIPhone:
            return line(ok: [String(localized: "Steps")],
                        rest: [String(localized: "Sleep, Strain, Recovery and Readiness stay empty: they need heart rate and sleep from a watch or ring.")])
        case .appleBuiltin, .vendorApp:
            break
        }
        let level = { (s: TrackerSignal) in Level(tracker.capabilities[s] ?? .unverified) }
        let restingHR = derivedRestingHR ? max(level(.restingHR), level(.heartRate)) : level(.restingHR)
        let recovery = min(level(.sleep), restingHR)
        // Readiness needs settled baselines: HRV's too, until the platform calibrates without it.
        let readiness = baselinesWithoutHRV ? recovery : min(recovery, level(.hrv))
        let levels: [Feature: Level] = [.strain: level(.heartRate), .sleep: level(.sleep), .recovery: recovery,
                                        .readiness: readiness]
        var ok = [Feature.strain, .sleep].filter { levels[$0] == .yes }.map(\.name)
        var rest: [String] = []
        if recovery == .yes {
            if level(.hrv) == .no {
                let inputs = [(TrackerSignal.restingHR, restingHR), (.sleep, level(.sleep)), (.respiratoryRate, level(.respiratoryRate))]
                    .filter { $0.1 >= .partial }.map { $0.0.inline }
                rest.append(String(localized: "Recovery from \(inputs.formatted(.list(type: .and))), no HRV"))
                if readiness == .yes { rest.append(String(localized: "Readiness from the same")) }
            } else {
                ok.append(Feature.recovery.name)
                if readiness == .yes { ok.append(Feature.readiness.name) }
            }
        }
        let partly = Feature.allCases.filter { levels[$0] == .partial }.map(\.name)
        if !partly.isEmpty { rest.append(String(localized: "\(partly.formatted(.list(type: .and))) in part")) }
        // Features that can't fill, grouped by the signals they lack ("Recovery and Readiness need resting heart rate").
        var needs: [(features: [Feature], signals: [TrackerSignal])] = []
        for feature in Feature.allCases where levels[feature] == .no {
            let signals: [TrackerSignal] = switch feature {
            case .strain: [.heartRate]
            case .sleep: [.sleep]
            case .recovery: [(TrackerSignal.sleep, level(.sleep)), (.restingHR, restingHR)].filter { $0.1 == .no }.map(\.0)
            case .readiness:
                ([(TrackerSignal.sleep, level(.sleep)), (.restingHR, restingHR)] + (baselinesWithoutHRV ? [] : [(.hrv, level(.hrv))]))
                    .filter { $0.1 == .no }.map(\.0)
            }
            if let i = needs.firstIndex(where: { $0.signals == signals }) {
                needs[i].features.append(feature)
            } else {
                needs.append(([feature], signals))
            }
        }
        let app = tracker.appName ?? tracker.name
        for need in needs {
            let features = need.features.map(\.name).formatted(.list(type: .and))
            let signals = need.signals.map(\.inline).formatted(.list(type: .and))
            rest.append(need.features.count == 1
                        ? String(localized: "\(features) needs \(signals), which \(app) doesn't share")
                        : String(localized: "\(features) need \(signals), which \(app) doesn't share"))
        }
        let unconfirmed = Feature.allCases.filter { levels[$0] == .unverified }.map(\.name)
        if !unconfirmed.isEmpty { rest.append(String(localized: "Not confirmed yet: \(unconfirmed.formatted(.list(type: .and)))")) }
        return line(ok: ok, rest: rest)
    }

    /// The collapsed card's one line (ui.md §3.3): "Heart rate, sleep, workouts · no HRV".
    static func verdict(for tracker: Tracker) -> String {
        switch tracker.integration {
        case .none: return String(localized: "Can't be read on iPhone today")
        case .unknown: return String(localized: "Depends on your tracker's app")
        case .appleBuiltin, .vendorApp: break
        }
        let arriving = [TrackerSignal.heartRate, .sleep, .workouts, .steps, .restingHR, .respiratoryRate]
            .filter { tracker.capabilities[$0] == .yes }.prefix(3).map(\.inline)
        guard !arriving.isEmpty else { return String(localized: "Not confirmed yet") }
        let list = arriving.joined(separator: ", ")
        let text = list.prefix(1).uppercased() + list.dropFirst()
        return tracker.capabilities[.hrv] == .no ? String(localized: "\(text) · no HRV") : text
    }

    private static func line(ok: [String], rest: [String]) -> Line {
        // A no-break space keeps "✓" with its feature.
        Line(text: (ok.map { String(localized: "\($0)\u{00A0}✓") } + rest).joined(separator: " · "),
             spoken: (ok.map { String(localized: "\($0), yes") } + rest).joined(separator: ". "))
    }

    /// no < not confirmed < partly < yes: a feature is as good as the worst signal it needs.
    enum Level: Int, Comparable, Sendable {
        case no, unverified, partial, yes

        init(_ capability: Capability) {
            switch capability {
            case .no: self = .no
            case .unverified: self = .unverified
            case .partial: self = .partial
            case .yes: self = .yes
            }
        }

        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
}

extension TrackerSignal {
    /// The capability rows' order (ui.md §3.2): sleep stages are a detail of Sleep.
    static let rows: [TrackerSignal] = [.heartRate, .hrv, .restingHR, .sleep, .respiratoryRate, .spo2, .workouts, .steps]

    /// A row's name ("Heart rate", "HRV", "SpO₂").
    var title: String {
        switch self {
        case .heartRate: return String(localized: "Heart rate")
        case .hrv: return String(localized: "HRV")
        case .restingHR: return String(localized: "Resting heart rate")
        case .sleep: return String(localized: "Sleep")
        case .sleepStages: return String(localized: "Sleep stages")
        case .respiratoryRate: return String(localized: "Breathing rate")
        case .spo2: return String(localized: "SpO₂")
        case .workouts: return String(localized: "Workouts")
        case .steps: return String(localized: "Steps")
        }
    }

    /// What VoiceOver says ("Heart rate variability", "Blood oxygen").
    var spoken: String {
        switch self {
        case .hrv: return String(localized: "Heart rate variability")
        case .spo2: return String(localized: "Blood oxygen")
        default: return title
        }
    }

    /// Inside a sentence ("needs resting heart rate").
    var inline: String {
        switch self {
        case .heartRate: return String(localized: "heart rate")
        case .hrv: return String(localized: "HRV")
        case .restingHR: return String(localized: "resting heart rate")
        case .sleep: return String(localized: "sleep")
        case .sleepStages: return String(localized: "sleep stages")
        case .respiratoryRate: return String(localized: "breathing rate")
        case .spo2: return String(localized: "blood oxygen")
        case .workouts: return String(localized: "workouts")
        case .steps: return String(localized: "steps")
        }
    }
}

extension Tracker {
    /// The tracker's glyph, the one mapping every tracker view uses (tiles, cards, rows, the sync check): the
    /// form factor only, never a logo, and Apple's silhouettes only for the Apple Watch and the iPhone themselves.
    var symbol: String {
        switch id {
        case "apple_watch": return "applewatch"
        case TrackerSelectionStore.iPhone: return "iphone"
        default: break
        }
        switch form {
        case .watch: return "watch.analog"
        case .band: return "figure.run.circle"
        case .ring: return "circle.circle"
        case .phone, .other: return "ellipsis.circle"
        }
    }

    /// "Just my iPhone": decided by its id, never by what a copy says its form is.
    var isJustIPhone: Bool { id == TrackerSelectionStore.iPhone }

    /// The app named in sentences: "Garmin Connect", or the tracker's own name.
    var appTitle: String { appName ?? name }
}

extension Localized {
    /// The text for a view's language (previews set it; the app follows its own).
    func value(in locale: Locale) -> T { value(for: locale.language.languageCode?.identifier) }
}
