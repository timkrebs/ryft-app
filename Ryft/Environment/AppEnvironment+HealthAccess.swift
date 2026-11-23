import Foundation

extension AppEnvironment {
    /// "Allow access" outside the first run and bootstrap (Profile → Data, Devices & sync, Check sync): `core`'s sheet,
    /// then, when that request newly put `core` in the account's record, `healthAllowed`, so background delivery and the
    /// first sync don't wait for a relaunch (bootstrap's key doesn't change here). `store` is `health`, except for Check
    /// sync's demo scenarios, which start nothing; Demo data starts nothing either.
    func requestCoreAccess(on store: HealthStore? = nil) async {
        let store = store ?? health
        let hadCore = store.askedGroups.contains(.core)
        try? await store.requestAuthorization(.core)
        guard store === health, !isDemo, !hadCore, store.askedGroups.contains(.core) else { return }
        healthAllowed?()
    }
}
