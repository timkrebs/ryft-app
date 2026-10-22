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
        lines.append(env.catalogStore.diagnosticLine)
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
    static let keys: Set<String> = ["requests", "resources", "sync", "gates", "flags", "locale", "report_context", "trackers"]

    /// Characters as the platform counts them (Unicode scalars: Go's runes).
    static func length(_ text: String) -> Int { text.unicodeScalars.count }

    // swiftlint:disable:next function_parameter_count
    static func make(message: String, category: FeedbackCategory, includeDiagnostics: Bool,
                     requests: [APIStatus.RequestFailure], resources: [ReadResource: ResourceState] = [:],
                     sync: FeedbackSync, gates: Set<APIErrorCode>,
                     flags: [String: Bool], trackers: [String]? = nil, context: ReportContext?,
                     about: FeedbackAbout) -> FeedbackPost {
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
                                                     gates: gates, flags: flags, trackers: trackers, context: context,
                                                     locale: about.locale))
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
    /// `devices.setup` on `trackers` (catalog ids, "garmin,oura", never a device's name) and, from an error's
    /// Details, `report_context`. Over 32 KiB the oldest requests go first, then resources and sync.
    static func diagnostics(requests: [APIStatus.RequestFailure], resources: [ReadResource: ResourceState],
                            sync: FeedbackSync, gates: Set<APIErrorCode>, flags: [String: Bool],
                            trackers: [String]? = nil, context: ReportContext?, locale: String) -> [String: String] {
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
                             gates: apiStatus.gates, flags: flagValues, trackers: trackers(), context: context,
                             about: .current)
    }

    /// "What's included" lists the trackers only when they go out.
    var includesTrackers: Bool { trackers() != nil }

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

    init(env: AppEnvironment) {
        self.env = env
        var ids = Self.demoTrackers
        #if DEBUG
        if let picked = UserDefaults.standard.string(forKey: "RyftTrackers") {
            ids = picked.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        #endif
        demo = TrackerSelection(account: "demo", trackers: ids, updatedAt: .distantPast)
        accountChanged()
    }

    /// nil: nothing chosen (the step was skipped, or another account's answer).
    var selection: TrackerSelection? {
        if env.isDemo { return demo }
        guard let live, live.account == env.auth.accountID else { return nil }
        return live
    }

    /// The catalog's trackers that were picked, in picker order (a remote copy may have dropped one).
    var trackers: [String] { Self.normalized(selection?.trackers ?? [], catalog: env.trackerCatalog) }

    /// Saves what was picked: known ids only, de-duplicated, in picker order; "Just my iPhone" alone. Guides of
    /// trackers no longer worn are forgotten.
    func set(_ ids: [String]) {
        let picked = Self.normalized(ids, catalog: env.trackerCatalog)
        mutate { s in
            s.trackers = picked
            s.setUp.removeAll { !picked.contains($0) }
            s.later.removeAll { !picked.contains($0) }
        }
    }

    func markSetUp(_ id: String) {
        guard trackers.contains(id) else { return }
        mutate { s in
            s.later.removeAll { $0 == id }
            if !s.setUp.contains(id) { s.setUp.append(id) }
        }
    }

    func markLater(_ id: String) {
        guard trackers.contains(id) else { return }
        mutate { s in
            s.setUp.removeAll { $0 == id }
            if !s.later.contains(id) { s.later.append(id) }
        }
    }

    func isLater(_ id: String) -> Bool { selection?.later.contains(id) ?? false }

    /// Signed in, out, or as someone else: that account's answer, or none.
    func accountChanged() {
        guard let account = env.auth.accountID,
              let saved = env.persistence.document(TrackerSelection.self, key: Self.documentKey), saved.account == account
        else {
            live = nil
            return
        }
        live = saved
    }

    /// Previews and screenshot runs: this choice, in memory.
    func stage(_ ids: [String]) {
        demo.trackers = ids
        live = env.auth.accountID.map { TrackerSelection(account: $0, trackers: ids, updatedAt: env.clock.now()) }
    }

    private func mutate(_ change: (inout TrackerSelection) -> Void) {
        let now = env.clock.now()
        if env.isDemo {
            change(&demo)
            demo.updatedAt = now
            return
        }
        guard let account = env.auth.accountID else { return }
        var s = selection ?? TrackerSelection(account: account, trackers: [], updatedAt: now)
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
        let names = trackers.map(\.name)
        guard !names.isEmpty else { return String(localized: "Not set") }
        let shown = names.prefix(2).joined(separator: " · ")
        return names.count > 2 ? "\(shown) · +\(names.count - 2)" : shown
    }

    /// Under each tracker's name. "Not checked yet" until Check sync (T3) has a result to show.
    func status(of tracker: Tracker) -> String {
        selection.isLater(tracker.id) ? String(localized: "Set up later") : String(localized: "Not checked yet")
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

    /// Trackers whose app has written to Apple Health: their store button says "Open … in the App Store".
    var seenTrackers: Set<String> { catalog.seen(in: state.user?.sources ?? []) }

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
    static func line(for tracker: Tracker, derivedRestingHR: Bool = restingHRFromHeartRate) -> Line? {
        switch tracker.integration {
        case .unknown:
            return nil
        case .none:
            return line(ok: [String(localized: "Steps")],
                        rest: [String(localized: "Sleep, Strain, Recovery and Readiness stay empty without data from your tracker")])
        case .appleBuiltin where tracker.form == .phone:
            return line(ok: [String(localized: "Steps")],
                        rest: [String(localized: "Sleep, Strain, Recovery and Readiness stay empty: they need heart rate and sleep from a watch or ring.")])
        case .appleBuiltin, .vendorApp:
            break
        }
        let level = { (s: TrackerSignal) in Level(tracker.capabilities[s] ?? .unverified) }
        let restingHR = derivedRestingHR ? max(level(.restingHR), level(.heartRate)) : level(.restingHR)
        let recovery = min(level(.sleep), restingHR)
        let levels: [Feature: Level] = [.strain: level(.heartRate), .sleep: level(.sleep), .recovery: recovery,
                                        .readiness: recovery]
        var ok = [Feature.strain, .sleep].filter { levels[$0] == .yes }.map(\.name)
        var rest: [String] = []
        if recovery == .yes {
            if level(.hrv) == .no {
                let inputs = [(TrackerSignal.restingHR, restingHR), (.sleep, level(.sleep)), (.respiratoryRate, level(.respiratoryRate))]
                    .filter { $0.1 >= .partial }.map { $0.0.inline }
                rest.append(String(localized: "Recovery from \(inputs.formatted(.list(type: .and))), no HRV"))
                rest.append(String(localized: "Readiness from the same"))
            } else {
                ok += [Feature.recovery.name, Feature.readiness.name]
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
            case .recovery, .readiness: [(TrackerSignal.sleep, level(.sleep)), (.restingHR, restingHR)].filter { $0.1 == .no }.map(\.0)
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
        Line(text: (ok.map { String(localized: "\($0) ✓") } + rest).joined(separator: " · "),
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
    /// The tile's glyph (ui.md §2.2): the form factor only, never a logo.
    var symbol: String {
        switch form {
        case .watch, .band: return "applewatch"
        case .ring: return "circle.circle"
        case .phone: return "iphone"
        case .other: return "ellipsis.circle"
        }
    }

    /// The app named in sentences: "Garmin Connect", or the tracker's own name.
    var appTitle: String { appName ?? name }
}

extension TrackerCatalog {
    /// The trackers whose app has written to Apple Health, as the platform lists the sources (`User.sources`):
    /// by bundle ID, so Apple's own devices (no device model there) never count.
    func seen(in sources: [UserSource]) -> Set<String> {
        Set(sources.compactMap { match(SourceRef(name: $0.name, bundleID: $0.bundleId, deviceModel: nil))?.id })
    }
}

extension Localized {
    /// The text for a view's language (previews set it; the app follows its own).
    func value(in locale: Locale) -> T { value(for: locale.language.languageCode?.identifier) }
}
