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
    /// About → Report a problem, and "Send to RYFT" from an error's Details.
    let report: ReportProblemModel

    init(state: AppState, sync: SyncService, coordinator: SyncCoordinator, onboarding: OnboardingCoordinator? = nil,
         apiStatus: APIStatus? = nil) {
        self.state = state
        self.sync = sync
        self.coordinator = coordinator
        self.onboarding = onboarding
        self.apiStatus = apiStatus ?? .shared
        bodySettings = BodySettingsEditor(state: state)
        let details = SyncDetailsModel(state: state, sync: sync, coordinator: coordinator, apiStatus: apiStatus)
        syncDetails = details
        // The same text as Sync details → Copy diagnostics.
        report = ReportProblemModel(env: state.env, apiStatus: apiStatus ?? .shared) { details.diagnostics }
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
        await coordinator.run(.userInitiated)
        await state.refresh(force: true)
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
        lines.append("requests:")
        for r in requests {
            lines.append("\(r.date.ISO8601Format()) \(r.status) \(r.code ?? "-") \(r.method) \(r.path) \(r.requestID ?? "-")")
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
    var code: String? = nil

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

/// `POST /v1/feedback` within API.md's limits: message 1–4000 characters, the four strings up to 64, at most
/// 20 request IDs of up to 64, diagnostics up to 32 KiB of JSON. The diagnostics are counts, times, statuses,
/// IDs, gates and flags (the Sync details text, the last requests), never a health value.
enum FeedbackPayload {
    static let maxMessage = 4000
    static let maxField = 64
    static let maxRequestIDs = 20
    static let maxDiagnosticsBytes = 32 * 1024
    /// The last requests sent along (`APIStatus` keeps as many).
    static let maxRequests = 20

    /// Characters as the platform counts them (Unicode scalars: Go's runes).
    static func length(_ text: String) -> Int { text.unicodeScalars.count }

    static func make(message: String, category: FeedbackCategory, includeDiagnostics: Bool, diagnosticsText: String,
                     requests: [APIStatus.RequestFailure], gates: Set<APIErrorCode>, flags: [String: Bool],
                     context: ReportContext?, about: FeedbackAbout) -> FeedbackPost {
        let text = clipped(message.trimmingCharacters(in: .whitespacesAndNewlines), to: maxMessage)
        // Off: nothing is attached but the message (ui.md §5.2).
        guard includeDiagnostics else { return FeedbackPost(message: text, category: category) }
        return FeedbackPost(message: text, category: category,
                            appVersion: clipped(about.appVersion, to: maxField),
                            build: clipped(about.build, to: maxField),
                            deviceModel: clipped(about.deviceModel, to: maxField),
                            osVersion: clipped(about.osVersion, to: maxField),
                            requestIds: requestIDs(context: context, requests: requests),
                            diagnostics: diagnostics(text: diagnosticsText, requests: requests, gates: gates,
                                                     flags: flags, context: context, locale: about.locale))
    }

    /// The context's ID first, then the failed requests' IDs, newest first: each once, 1–64 bytes, at most 20.
    static func requestIDs(context: ReportContext?, requests: [APIStatus.RequestFailure]) -> [String] {
        let failed = requests.filter { !(200..<300).contains($0.status) }.compactMap(\.requestID)
        var seen = Set<String>()
        let ids = ([context?.requestID].compactMap { $0 } + failed)
            .filter { !$0.isEmpty && $0.utf8.count <= maxField && seen.insert($0).inserted }
        return Array(ids.prefix(maxRequestIDs))
    }

    /// One request: "2026-10-21T18:12:03Z GET /v1/days/2026-10-21 503 - 01a14ffa-…" (date, method, path,
    /// status, code, request ID).
    static func line(_ r: APIStatus.RequestFailure) -> String {
        "\(r.date.ISO8601Format()) \(r.method) \(r.path) \(r.status) \(r.code ?? "-") \(r.requestID ?? "-")"
    }

    /// `sync_details` (Copy diagnostics), `requests` (newest first), `gates`, `flags`, `locale` and, from an
    /// error's Details, `report_context`. Over 32 KiB the oldest requests go first, then the end of the text.
    static func diagnostics(text: String, requests: [APIStatus.RequestFailure], gates: Set<APIErrorCode>,
                            flags: [String: Bool], context: ReportContext?, locale: String) -> [String: String] {
        var base = [
            "gates": gates.isEmpty ? "-" : gates.map(\.rawValue).sorted().joined(separator: ","),
            "flags": flags.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value ? 1 : 0)" }.joined(separator: ","),
            "locale": locale,
        ]
        if let context {
            base["report_context"] = [context.resource, context.statusText, context.requestID ?? "-"]
                .joined(separator: " · ")
        }
        func assembled(_ lines: [String], _ text: String) -> [String: String] {
            var d = base
            if !text.isEmpty { d["sync_details"] = text }
            if !lines.isEmpty { d["requests"] = lines.joined(separator: "\n") }
            return d
        }
        var lines = requests.prefix(maxRequests).map(line)
        while size(assembled(lines, text)) > maxDiagnosticsBytes, !lines.isEmpty { lines.removeLast() }
        let whole = assembled(lines, text)
        guard size(whole) > maxDiagnosticsBytes else { return whole }
        // Still over without a single request: keep the head of the text (the engine), cut its end.
        let scalars = Array(text.unicodeScalars)
        func cut(_ n: Int) -> String {
            var head = String.UnicodeScalarView()
            head.append(contentsOf: scalars.prefix(n))
            return String(head) + "\n…"
        }
        var low = 0, high = scalars.count
        while low < high {
            let mid = (low + high + 1) / 2
            if size(assembled([], cut(mid))) <= maxDiagnosticsBytes { low = mid } else { high = mid - 1 }
        }
        let trimmed = assembled([], cut(low))
        if size(trimmed) <= maxDiagnosticsBytes { return trimmed }
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

/// A report waiting for a connection: the `FeedbackPost` as it will go out (the mirror stays `Encodable`).
/// The diagnostics are pairs, so the cache's snake-case coder can't rename their keys.
struct QueuedFeedback: Codable, Equatable, Identifiable {
    struct Entry: Codable, Equatable {
        let key: String
        let value: String
    }

    let id: UUID
    let queuedAt: Date
    let message: String
    let category: FeedbackCategory?
    let appVersion: String?
    let build: String?
    let deviceModel: String?
    let osVersion: String?
    let requestIds: [String]
    let diagnostics: [Entry]?

    init(_ post: FeedbackPost, id: UUID = UUID(), queuedAt: Date) {
        self.id = id
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
/// → rate limited, the message kept, nothing queued; `400`/`413`/`422` → rejected, dropped.
@MainActor
@Observable
final class ReportProblemModel {
    /// `sent` and `queued` replace the form; the others show on it, with the message kept.
    enum Result: Equatable { case sent, queued, rateLimited, rejected, saveFailed }

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
    private let diagnostics: @MainActor () -> String
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
    /// A preview or screenshot staged the screen: the next `prepare` leaves it.
    @ObservationIgnored private var staged = false

    /// `diagnostics` is the Sync details text (Copy diagnostics).
    init(env: AppEnvironment, apiStatus: APIStatus, queue: FeedbackQueueStore? = nil,
         diagnostics: @escaping @MainActor () -> String) {
        self.env = env
        self.apiStatus = apiStatus
        self.diagnostics = diagnostics
        self.queue = queue ?? PersistentFeedbackQueue(env: env)
        reloadWaiting()
    }

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
        if result == .sent || result == .queued {
            message = ""
            includeDiagnostics = true
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

    /// The request as it would go out now.
    func payload() -> FeedbackPost {
        FeedbackPayload.make(message: message, category: category, includeDiagnostics: includeDiagnostics,
                             diagnosticsText: includeDiagnostics ? diagnostics() : "", requests: apiStatus.requests,
                             gates: apiStatus.gates, flags: flagValues, context: context, about: .current)
    }

    private var flagValues: [String: Bool] {
        Dictionary(uniqueKeysWithValues: FeatureFlag.allCases.map { ($0.rawValue, env.flags.isOn($0)) })
    }

    func copyMessage() {
        UIPasteboard.general.string = message
    }

    // MARK: sending

    func send() async {
        guard canSend else { return }
        sending = true
        result = nil
        resultDetails = nil
        defer { sending = false }
        let item = QueuedFeedback(payload(), queuedAt: env.clock.now())
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
        switch delivery {
        case .delivered:
            dequeue(item)
            result = .sent
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

    /// Back online, or the app became active: what's queued goes out, oldest first. It stops at a report that
    /// can't go yet (no connection, `5xx`) or at the daily cap; the rest waits for the next time.
    func flush() async {
        guard !flushing, env.connectivity.isOnline, env.isDemo || env.auth.isSignedIn else { return }
        flushing = true
        defer {
            flushing = false
            reloadWaiting()
        }
        for item in queue.load().sorted(by: { $0.queuedAt < $1.queuedAt }) where !inFlight.contains(item.id) {
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
            result = .queued
        } else {
            dequeue(item)
            result = .saveFailed
        }
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
               context: ReportContext? = nil, result: Result? = nil, sending: Bool = false, waiting: Int = 0) {
        staged = true
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
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
