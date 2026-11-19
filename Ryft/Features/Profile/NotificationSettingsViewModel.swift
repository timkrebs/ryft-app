import Foundation
import Observation

/// Profile → Notifications: iOS permission, one toggle per category and quiet
/// hours, saved with `PATCH /v1/me/notifications`. Changes show at once and
/// roll back if the platform refuses them.
///
/// Saves can overlap (a time chip's wheel sends each value it stops on): they go
/// one after another, in the order they were made, so the platform ends with the
/// latest; only the latest one's answer is shown, and if it fails the page goes
/// back to what the platform last confirmed.
///
/// Each save is the account's that was signed in at the tap, sent to that side's platform (the Demo data switch changes
/// `env.api`): another account or the switch before its turn and it isn't sent, while it's out and its answer is dropped,
/// and the queue is cancelled (PR 6 C security review S1). A save waits as every settings write does (`SettingsWrite`):
/// one attempt, an answer within 25 s or none, none at once when the network goes.
@MainActor
@Observable
final class NotificationSettingsViewModel {
    private let state: AppState
    private let push: PushRegistrar

    private(set) var prefs: NotificationPrefs
    /// The last change that didn't save, in words (`NotificationSettingsFailure`).
    private(set) var failure: NotificationSettingsFailure?
    /// Saves on their way.
    private var inFlight = 0
    /// Saves started, never reset: an answer is shown only while its save is the latest.
    private var saves = 0
    /// The settings as the platform last confirmed them (or as loaded): where a failed latest save goes back to.
    private var confirmed: NotificationPrefs
    /// The last save handed on: the next one waits for it.
    private var lastSave: Task<Void, Never>?
    /// The saves handed on and not done yet, by their number: another account or the Demo data switch cancels them all.
    @ObservationIgnored private var turns: [Int: Task<Void, Never>] = [:]
    /// Whose the queued saves are (`dropQueueIfAccountChanged`).
    @ObservationIgnored private var queuedFor: AccountBinding?
    /// Watches the account while saves were made: its change cancels the queue at once, not at the next save.
    @ObservationIgnored private var accountWatch: ObservationWatch?
    /// RYFT asked again after a change that may have saved, while it's out (`askAgain`; tests await it).
    private(set) var asking: Task<Void, Never>?

    /// A change is on its way: every switch and time chip waits for it.
    var saving: Bool { inFlight > 0 }

    /// The default window when quiet hours are switched on.
    static let defaultQuietHours = QuietHours(from: "22:30", to: "07:00")

    init(state: AppState, push: PushRegistrar) {
        self.state = state
        self.push = push
        let saved = state.user?.notifications ?? .allOn
        prefs = saved
        confirmed = saved
    }

    /// `push.enabled` for this account.
    var isRolledOut: Bool { state.env.flags.isOn(.pushEnabled) }

    /// What the screen is, which decides its controls.
    enum Mode: Equatable {
        /// `push.enabled` is off for this account: what will come, and no switch that looks on.
        case rollingOut
        /// On; iOS hasn't asked yet: the switches, and "Allow notifications".
        case notAsked
        /// On, but off in iOS Settings: the switches stay, with "Open Settings".
        case denied
        case allowed
    }

    var mode: Mode {
        guard isRolledOut else { return .rollingOut }
        if push.isAllowed { return .allowed }
        return push.status == .notDetermined ? .notAsked : .denied
    }

    /// The category switches and quiet hours: only once notifications can reach the account.
    var showsSwitches: Bool { mode != .rollingOut }

    /// The screen appears: a flag answer that arrived meanwhile (`FlagStore.applyPending`), the
    /// iOS permission, the saved choices.
    func load() async {
        (state.env.flags as? FlagStore)?.applyPending()
        await push.refresh()
        if let saved = state.user?.notifications, !saving {
            prefs = saved
            confirmed = saved
        }
    }

    func allow() async { await push.accept() }

    // MARK: categories

    func isOn(_ category: NotificationCategory) -> Bool { prefs.isOn(category) }

    func set(_ category: NotificationCategory, on: Bool) async {
        var categories = prefs.categories
        categories[category.rawValue] = on
        await save(NotificationPatch(categories: [category.rawValue: on]),
                   showing: NotificationPrefs(categories: categories, quietHours: prefs.quietHours))
    }

    static func title(_ category: NotificationCategory) -> String {
        switch category {
        case .morningScore: return String(localized: "Morning score")
        case .sessionScored: return String(localized: "Workout scored")
        case .pr: return String(localized: "Records")
        case .syncStale: return String(localized: "No new data")
        }
    }

    /// When each one is sent (API.md → Push notifications).
    static func detail(_ category: NotificationCategory) -> String {
        switch category {
        case .morningScore:
            return String(localized: "When today's recovery is scored after a night's sleep, once a day.")
        case .sessionScored:
            return String(localized: "When a logged strength session is scored, the first one each day.")
        case .pr:
            return String(localized: "When a session sets a record and Workout scored is off.")
        case .syncStale:
            return String(localized: "When no heart rate or steps arrived for 20 hours, between 09:00 and 21:00.")
        }
    }

    // MARK: quiet hours

    var quietHoursOn: Bool { prefs.quietHours != nil }
    var quietFrom: Date { Self.date(prefs.quietHours?.from ?? Self.defaultQuietHours.from) }
    var quietTo: Date { Self.date(prefs.quietHours?.to ?? Self.defaultQuietHours.to) }

    func setQuietHours(on: Bool) async {
        await setQuietHours(on ? (prefs.quietHours ?? Self.defaultQuietHours) : nil)
    }

    func setQuietFrom(_ date: Date) async {
        await setQuietHours(QuietHours(from: Self.string(date), to: prefs.quietHours?.to ?? Self.defaultQuietHours.to))
    }

    func setQuietTo(_ date: Date) async {
        await setQuietHours(QuietHours(from: prefs.quietHours?.from ?? Self.defaultQuietHours.from, to: Self.string(date)))
    }

    private func setQuietHours(_ quiet: QuietHours?) async {
        guard quiet != prefs.quietHours else { return }
        await save(NotificationPatch(quietHours: .some(quiet)),
                   showing: NotificationPrefs(categories: prefs.categories, quietHours: quiet))
    }

    // MARK: saving

    private func save(_ patch: NotificationPatch, showing optimistic: NotificationPrefs) async {
        // Offline nothing is sent: the change says so at once, instead of waiting for a network that isn't there.
        guard state.isDemo || state.env.connectivity.isOnline else {
            failure = NotificationSettingsFailure(.offline, quietHours: patch.quietHours != nil)
            return
        }
        dropQueueIfAccountChanged()
        saves += 1
        let mine = saves
        prefs = optimistic
        failure = nil
        inFlight += 1
        defer { inFlight -= 1 }
        // The account's, and its side's platform, as at the tap: a sign-out (another account) or the Demo data switch before
        // its turn keeps it unsent, and while the PATCH is out drops its answer.
        let binding = AccountBinding(state.env), api = state.env.api
        queuedFor = binding
        watchAccount()
        let before = lastSave
        let turn = Task { @MainActor in
            await before?.value
            await self.send(patch, mine: mine, binding: binding, api: api)
        }
        lastSave = turn
        turns[mine] = turn
        await withTaskCancellationHandler { await turn.value } onCancel: { turn.cancel() }
        turns[mine] = nil
    }

    /// One `PATCH` through `api`, once the saves before it are done, while the account is still `binding`'s.
    private func send(_ patch: NotificationPatch, mine: Int, binding: AccountBinding, api: PlatformAPI) async {
        // Its turn came after a sign-out, another account or the Demo data switch: never sent, to anyone.
        guard binding.isCurrent(in: state.env) else { return }
        guard !Task.isCancelled else {
            // Not sent, not failed: the platform's answer on the next load decides.
            if mine == saves { prefs = confirmed }
            return
        }
        // Offline by its turn: nothing is sent, and it says so (the check at the tap, again).
        guard state.isDemo || state.env.connectivity.isOnline else {
            guard mine == saves else { return }
            prefs = confirmed
            failure = NotificationSettingsFailure(.offline, quietHours: patch.quietHours != nil)
            return
        }
        do {
            let saved = try await SettingsWrite.answer(in: state.env) { try await api.patchNotifications(patch) }
            guard binding.isCurrent(in: state.env) else { return }
            confirmed = saved
            // A later change is on its way: its answer is the one to show.
            guard mine == saves else { return }
            prefs = saved
            // The user as the platform has it now, these settings with it: asked again, not assembled here from the
            // cached user, which a change of the user stored meanwhile (the withdrawal) may already have replaced.
            try? await state.repository.refreshUser(mode: .changed(since: state.env.clock.now()))
        } catch where error.isCancellation {
            // Not confirmed, not failed: the platform's answer on the next load decides.
            guard binding.isCurrent(in: state.env) else { return }
            if mine == saves { prefs = confirmed }
        } catch {
            guard binding.isCurrent(in: state.env), mine == saves else { return }
            prefs = confirmed
            let failed = NotificationSettingsFailure(error, quietHours: patch.quietHours != nil)
            failure = failed
            guard failed.kind.rereads else { return }
            // Offline the question would wait for the network: the cached user is marked instead, so the next refresh
            // asks (as the editors do).
            guard state.isDemo || state.env.connectivity.isOnline else {
                state.repository.userMayDiffer()
                return
            }
            // It may have saved (no answer), or RYFT had a problem (5xx): the page shows what RYFT holds, asked again outside
            // this turn, so the switches don't wait for the question (and the next save doesn't either).
            asking = Task { await self.askAgain(patch, mine: mine, binding: binding) }
        }
    }

    /// `GET /v1/me` after a change that may have saved. Only an answer counts: when the question fails the page stays as it
    /// went back, and the cached user is marked so the next refresh asks (`Repository.userMayDiffer`). Only while the change
    /// is the latest; and only the change's own key decides whether it did save (another device may have changed the rest
    /// meanwhile).
    private func askAgain(_ patch: NotificationPatch, mine: Int, binding: AccountBinding) async {
        do {
            try await state.repository.refreshUser(mode: .changed(since: state.env.clock.now()))
        } catch {
            if binding.isCurrent(in: state.env) { state.repository.userMayDiffer() }
            return
        }
        guard binding.isCurrent(in: state.env), mine == saves, let held = state.user?.notifications else { return }
        confirmed = held
        prefs = held
        // It did save: nothing to say.
        if patch.isHeld(by: held) { failure = nil }
    }

    // MARK: the account

    private func watchAccount() {
        guard accountWatch == nil else { return }
        accountWatch = ObservationWatch(read: { [env = state.env] in _ = AccountBinding(env) },
                                        changed: { [weak self] in self?.dropQueueIfAccountChanged() })
    }

    /// The queued saves are another account's, or the other side of the Demo data switch: they're cancelled (none of them
    /// is sent, and an answer on its way is dropped), and the page shows this account's settings. A token refresh changes
    /// nothing here.
    private func dropQueueIfAccountChanged() {
        guard let queuedFor, !queuedFor.isCurrent(in: state.env) else { return }
        self.queuedFor = nil
        for turn in turns.values { turn.cancel() }
        turns = [:]
        lastSave = nil
        asking?.cancel()
        asking = nil
        // Every answer still to come is the previous account's: none of them is shown.
        saves += 1
        failure = nil
        let saved = state.user?.notifications ?? .allOn
        prefs = saved
        confirmed = saved
    }

    // MARK: "HH:MM" ⇄ Date (today, local)

    static func date(_ hhmm: String, calendar: Calendar = .current, now: Date = .now) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return now }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now) ?? now
    }

    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

private extension NotificationPatch {
    /// `prefs` hold what this patch changes: its categories and its quiet hours, nothing else.
    func isHeld(by prefs: NotificationPrefs) -> Bool {
        let categoriesHeld = (categories ?? [:]).allSatisfy { (prefs.categories[$0.key] ?? true) == $0.value }
        guard let quietHours else { return categoriesHeld }
        return categoriesHeld && quietHours == prefs.quietHours
    }
}

/// What Notifications says when a change didn't save: calm words (`SettingsWriteFailure`, shared with the body-setting
/// editors), and the status and request ID as the caption when RYFT answered (never the raw error text).
struct NotificationSettingsFailure: Equatable {
    let message: String
    let details: String?
    /// The change was to quiet hours (its notice goes under them), not to a category.
    let quietHours: Bool
    /// What went wrong, judged by what left the phone: offline only when nothing did.
    let kind: SettingsWriteFailure

    init(_ error: Error, quietHours: Bool = false) {
        self.init(SettingsWriteFailure(error), details: error.diagnosticDetails, quietHours: quietHours)
    }

    init(_ kind: SettingsWriteFailure, details: String? = nil, quietHours: Bool = false) {
        self.kind = kind
        self.quietHours = quietHours
        message = kind.saveMessage
        self.details = details
    }
}
