import Foundation
import Observation

/// Profile → Notifications: iOS permission, one toggle per category and quiet
/// hours, saved with `PATCH /v1/me/notifications`. Changes show at once and
/// roll back if the platform refuses them.
@MainActor
@Observable
final class NotificationSettingsViewModel {
    private let state: AppState
    private let push: PushRegistrar

    private(set) var prefs: NotificationPrefs
    private(set) var saving = false
    private(set) var error: String?

    /// The default window when quiet hours are switched on.
    static let defaultQuietHours = QuietHours(from: "22:30", to: "07:00")

    init(state: AppState, push: PushRegistrar) {
        self.state = state
        self.push = push
        prefs = state.user?.notifications ?? .allOn
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
        if let saved = state.user?.notifications { prefs = saved }
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
        let previous = prefs
        prefs = optimistic
        error = nil
        saving = true
        defer { saving = false }
        do {
            let saved = try await state.env.api.patchNotifications(patch)
            prefs = saved
            if var user = state.user {
                user.notifications = saved
                state.user = user
            }
        } catch {
            prefs = previous
            self.error = String(localized: "Couldn't save: \(error.localizedDescription)")
        }
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
