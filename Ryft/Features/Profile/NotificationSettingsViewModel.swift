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
    static let defaultQuietHours = QuietHours(from: "22:00", to: "07:00")

    init(state: AppState, push: PushRegistrar) {
        self.state = state
        self.push = push
        prefs = state.user?.notifications ?? .allOn
    }

    enum Permission: Equatable {
        case notAsked, allowed, denied
    }

    var permission: Permission {
        if push.isAllowed { return .allowed }
        return push.status == .notDetermined ? .notAsked : .denied
    }

    func load() async {
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

    static func detail(_ category: NotificationCategory) -> String {
        switch category {
        case .morningScore: return String(localized: "Your recovery once the night is scored.")
        case .sessionScored: return String(localized: "The strain of a logged workout, with any records.")
        case .pr: return String(localized: "A new record, when workout notifications are off.")
        case .syncStale: return String(localized: "When your watch hasn't synced for 20 hours.")
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
