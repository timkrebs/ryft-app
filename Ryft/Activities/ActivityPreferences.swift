import Foundation

/// The account's activity preferences on this iPhone (design.md §2.4: `UserDefaults`, keyed per account, wiped at
/// sign-out): whether new GPS activities record their route (asked once, at the first GPS Start; plan D1-3),
/// auto-pause per sport family, and the sports Add activity's picker lists first.
///
/// A value made for the account of the moment (`init(env:)`): make a new one after an account change. Signed out
/// (`account == nil`) it reads the defaults and writes nothing.
@MainActor
struct ActivityPreferences {
    static let keyPrefix = "activities.prefs."
    /// The picker's "Recent" section (ui.md §3.2).
    static let recentLimit = 5

    let defaults: UserDefaults
    /// The signed-in account, demo data's (`ActivityStore.demoAccount`), or nobody.
    let account: String?

    init(defaults: UserDefaults, account: String?) {
        self.defaults = defaults
        self.account = account
    }

    /// The environment's defaults, for the account `ActivityStore` reads and writes as.
    init(env: AppEnvironment) {
        self.init(defaults: env.defaults, account: env.activities.account)
    }

    private func key(_ name: String) -> String? {
        account.map { "\(Self.keyPrefix)\($0).\(name)" }
    }

    // MARK: route

    /// "Record route" for a new GPS activity: nil until the user chose (pre-start asks then); the per-activity
    /// toggle starts from it. A restore to another iPhone resets it (`forgetRouteDefaults`, A5).
    var recordsRouteByDefault: Bool? {
        guard let key = key("recordRoute"), defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    func setRecordsRouteByDefault(_ on: Bool) {
        guard let key = key("recordRoute") else { return }
        defaults.set(on, forKey: key)
    }

    // MARK: auto-pause

    /// Whether a recording of `sport` starts with auto-pause on: the user's choice for its family, else the
    /// catalogue's default for the sport (design.md §2.1).
    func autoPause(for sport: Sport) -> Bool {
        guard let key = key("autoPause.\(sport.family.rawValue)"), defaults.object(forKey: key) != nil else {
            return sport.autoPauseDefault
        }
        return defaults.bool(forKey: key)
    }

    /// The user's choice for `sport`'s family (Profile → Activities, or the pre-start toggle).
    func setAutoPause(_ on: Bool, for sport: Sport) {
        guard let key = key("autoPause.\(sport.family.rawValue)") else { return }
        defaults.set(on, forKey: key)
    }

    // MARK: recent sports

    /// The last sports used, newest first, at most `recentLimit`.
    var recentSports: [Sport] {
        guard let key = key("recentSports") else { return [] }
        let raw = defaults.stringArray(forKey: key) ?? []
        return Array(raw.compactMap(Sport.init(rawValue:)).prefix(Self.recentLimit))
    }

    /// An activity of `sport` was added or started: it moves to the front of the recents.
    func noteUsed(_ sport: Sport) {
        guard let key = key("recentSports") else { return }
        let rest = (defaults.stringArray(forKey: key) ?? []).filter { $0 != sport.rawValue }
        defaults.set(Array(([sport.rawValue] + rest).prefix(Self.recentLimit)), forKey: key)
    }

    // MARK: wipe

    /// The sign-out wipe: every account's preferences on this phone (`AuthService.wipeSharedLocalData`).
    static func wipe(defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Every account's route default back to "not chosen" (design.md §8.6: a restore whose privacy zones couldn't
    /// come along; A5 calls it).
    static func forgetRouteDefaults(defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) && key.hasSuffix(".recordRoute") {
            defaults.removeObject(forKey: key)
        }
    }
}
