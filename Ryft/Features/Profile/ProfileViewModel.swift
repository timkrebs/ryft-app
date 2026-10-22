import Foundation
import Observation
import UIKit

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

    init(state: AppState, sync: SyncService, coordinator: SyncCoordinator, onboarding: OnboardingCoordinator? = nil,
         apiStatus: APIStatus? = nil) {
        self.state = state
        self.sync = sync
        self.coordinator = coordinator
        self.onboarding = onboarding
        self.apiStatus = apiStatus ?? .shared
        bodySettings = BodySettingsEditor(state: state)
        syncDetails = SyncDetailsModel(state: state, sync: sync, coordinator: coordinator, apiStatus: apiStatus)
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
        for row in streams {
            guard let p = row.progress else { lines.append("\(row.id): -"); continue }
            let ignored = p.lastIgnored.map { "dup \($0.duplicate) out \($0.outsideWindow) unk \($0.unknownType)" } ?? "-"
            lines.append("\(row.id): \(p.sent) rec \(p.bytes) B days \(p.days.count) newest \(p.newest.map { $0.ISO8601Format() } ?? "-") backfilled \(p.backfilled) last \(p.lastAccepted) ignored \(ignored)")
        }
        lines.append("resources (resource | fetched_at | last_error status code request_id at | consecutive_failures):")
        let states = state.resourceStates
        lines += ReadResource.allCases.map { (states[$0] ?? ResourceState()).diagnosticLine($0) }
        lines.append("requests:")
        for r in requests {
            let duration = r.durationMs.map(String.init) ?? "-"
            lines.append("\(r.date.ISO8601Format()) \(r.status) \(r.code ?? "-") \(r.method) \(r.path) \(r.requestID ?? "-") duration_ms=\(duration) transport=\(r.transport ?? "-")")
        }
        return lines.joined(separator: "\n")
    }

    func copyDiagnostics() {
        UIPasteboard.general.string = diagnostics
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
