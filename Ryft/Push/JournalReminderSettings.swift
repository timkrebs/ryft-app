import Foundation

/// The journal reminder's switch and time, per account and on this iPhone only (`notifications.journal.<account>`,
/// design.md §4.1): the platform has no field for it. An account that never chose has the default, on at 09:00. The sign-out
/// wipe removes every account's (`wipe`); Demo data reads and writes none.
@MainActor
final class JournalReminderStore {
    static let prefix = "notifications.journal."

    private let env: AppEnvironment
    /// A write changed the setting (the scheduler asks for a pass).
    var onChange: (@MainActor () -> Void)?

    init(env: AppEnvironment) {
        self.env = env
    }

    static func key(_ account: String) -> String { prefix + account }

    /// `account`'s choice, or the default; a stored value that doesn't decode (or a time outside the day) is the default.
    func settings(for account: String) -> JournalReminderSettings {
        guard let data = env.defaults.data(forKey: Self.key(account)),
              let stored = try? JSONDecoder().decode(JournalReminderSettings.self, from: data),
              (0..<24 * 60).contains(stored.minute) else { return .default }
        return stored
    }

    /// The signed-in account's choice, nil signed out or with Demo data on (whose reminder is never scheduled).
    var current: JournalReminderSettings? {
        guard !env.isDemo, let account = env.auth.accountID else { return nil }
        return settings(for: account)
    }

    /// Saves the signed-in account's choice; false (and nothing saved) signed out or with Demo data on.
    @discardableResult
    func set(_ settings: JournalReminderSettings) -> Bool {
        guard !env.isDemo, let account = env.auth.accountID, (0..<24 * 60).contains(settings.minute) else { return false }
        guard settings != self.settings(for: account) else { return true }
        guard let data = try? JSONEncoder().encode(settings) else { return false }
        env.defaults.set(data, forKey: Self.key(account))
        onChange?()
        return true
    }

    /// The sign-out wipe: every account's setting on this iPhone.
    static func wipe(defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
