import Foundation
import Observation

/// The journal reminder's switch and time, per account and on this iPhone only (`notifications.journal.<account>`,
/// design.md §4.1): the platform has no field for it (NT6). An account that never chose has the default, on at 09:00. A
/// sign-out's wipe removes every account's; a session expiry's keeps the leaving account's, so its "off" survives the next
/// sign-in (review S-4). Demo data reads and writes none.
@MainActor
@Observable
final class JournalReminderStore {
    static let prefix = "notifications.journal."

    @ObservationIgnored private let env: AppEnvironment
    /// A write changed the setting (the scheduler asks for a pass).
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    /// Bumped by a write and by the wipe's turn: a view showing the setting (N4's page) reads it again.
    private var revision = 0
    /// The last account's setting as decoded: every pass reads it (review S4). A write replaces it, the wipe's turn drops it.
    @ObservationIgnored private var decoded: (account: String, settings: JournalReminderSettings)?

    init(env: AppEnvironment) {
        self.env = env
    }

    static func key(_ account: String) -> String { prefix + account }

    /// `account`'s choice, or the default; a stored value that doesn't decode (or a time outside the day) is the default.
    func settings(for account: String) -> JournalReminderSettings {
        _ = revision
        if let decoded, decoded.account == account { return decoded.settings }
        let settings = Self.read(account, from: env.defaults)
        decoded = (account, settings)
        return settings
    }

    private static func read(_ account: String, from defaults: UserDefaults) -> JournalReminderSettings {
        guard let data = defaults.data(forKey: key(account)),
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
        decoded = (account, settings)
        revision += 1
        onChange?()
        return true
    }

    /// The wipe's turn (`ReminderScheduler.forget`): what was decoded goes with the defaults it came from.
    func forget() {
        decoded = nil
        revision += 1
    }

    /// The wipe: every account's setting on this iPhone but `parking`'s (the account a session expiry parks).
    static func wipe(defaults: UserDefaults, keeping parking: String? = nil) {
        let kept = parking.map(key)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) && key != kept {
            defaults.removeObject(forKey: key)
        }
    }
}
