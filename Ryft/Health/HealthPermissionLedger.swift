// Which permission groups an account asked Apple Health for (ADR 0027, design note §4). HealthKit's grant is per
// install and never visible for reads; "asked" is a product fact the app keeps itself, per account.
import Foundation

/// The record for one account: `health.asked.<account>`, the asked groups' names (no health data). Built when
/// needed, never shared across actors. Without an account (signed out, Demo data) it holds nothing and never writes.
///
/// It decides the derived sets (`HealthKitManager.readTypes`, `observedTypes`) and which state a feature shows. It
/// never skips a request: every read of a group is preceded by `requestAuthorization(group)` in the same action, so a
/// stale record (a backup restore) can't cause a read without HealthKit's own answer.
struct HealthPermissionLedger {
    /// `Settings.healthIntroDone`'s key: the migration's signal.
    static let introDoneKey = "health.introDone"

    static func key(_ account: String) -> String { "health.asked.\(account)" }

    let defaults: UserDefaults
    let account: String?

    init(defaults: UserDefaults, account: String?) {
        self.defaults = defaults
        self.account = account
    }

    /// The asked groups. Migration, without a prompt: a record without `core` gains it when the Connect Apple Health
    /// intro was answered (`healthIntroDone`), since then `core` was requested (or bootstrap requests it on this run).
    /// Synchronous and without HealthKit or the network, so it holds in a background launch (`RyftApp.init`) too.
    var asked: Set<HealthPermissionGroup> {
        var asked = Set(stored.compactMap(HealthPermissionGroup.init(rawValue:)))
        if !asked.contains(.core), defaults.bool(forKey: Self.introDoneKey) {
            asked.insert(.core)
            record(.core)
        }
        return asked
    }

    func contains(_ group: HealthPermissionGroup) -> Bool { asked.contains(group) }

    /// Adds `group`. Names this build doesn't know are kept, so a newer build's groups survive a downgrade.
    /// Idempotent; without an account, nothing.
    func record(_ group: HealthPermissionGroup) {
        guard let account else { return }
        let names = stored
        guard !names.contains(group.rawValue) else { return }
        defaults.set(names + [group.rawValue], forKey: Self.key(account))
    }

    /// Account deletion: the record goes with the account.
    func remove() {
        guard let account else { return }
        defaults.removeObject(forKey: Self.key(account))
    }

    private var stored: [String] {
        guard let account else { return [] }
        return defaults.stringArray(forKey: Self.key(account)) ?? []
    }

    /// Runs `request` (the system sheet), then records `group` for the account that was signed in when it started:
    /// an account switch while the sheet is up records for the account that asked. A throw records nothing.
    static func recording(_ group: HealthPermissionGroup, defaults: UserDefaults,
                          request: () async throws -> Void) async rethrows {
        let account = AccountScope.current(defaults)
        try await request()
        HealthPermissionLedger(defaults: defaults, account: account).record(group)
    }

    /// The wipe's step (`AuthService.wipeSharedLocalData`): an account deletion removes the leaving account's record.
    /// A sign-out (by the user or a final 401) or a switch keeps it, like the onboarding keys; HealthKit's grant stays
    /// with the install anyway.
    static func wipe(_ wipe: AuthService.Wipe, defaults: UserDefaults) {
        guard wipe.reason?.isDeletion == true else { return }
        HealthPermissionLedger(defaults: defaults, account: wipe.account ?? AccountScope.current(defaults)).remove()
    }
}
