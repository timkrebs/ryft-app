import Foundation
import HealthKit
import Testing
@testable import Ryft

/// HealthKit anchors belong to the signed-in user (`AccountScope`).
@Suite("Anchors per user", .serialized)
struct AnchorScopeTests {
    private let hk = HealthKitManager.shared
    private let defaults = UserDefaults.standard

    private func asUser(_ id: String?, _ body: () -> Void) {
        let saved = defaults.string(forKey: AccountScope.defaultsKey)
        defer { defaults.set(saved, forKey: AccountScope.defaultsKey) }
        defaults.set(id, forKey: AccountScope.defaultsKey)
        body()
    }

    @Test func anotherAccountStartsWithoutAnchors() {
        let id = "test.\(UUID().uuidString)"
        asUser("user-a") { hk.save(anchor: HKQueryAnchor(fromValue: 42), for: id) }
        asUser("user-b") { #expect(hk.anchor(for: id) == nil) }
        asUser("user-a") { #expect(hk.anchor(for: id) != nil) }
        defaults.removeObject(forKey: "hk.anchor.user-a.\(id)")
    }

    @Test func legacyAnchorsMoveToTheCurrentUserOnce() {
        asUser("user-c") {
            let legacy = "hk.anchor.sleep"
            let data = try? NSKeyedArchiver.archivedData(withRootObject: HKQueryAnchor(fromValue: 7), requiringSecureCoding: true)
            defaults.set(data, forKey: legacy)
            hk.migrateLegacyAnchors()
            #expect(defaults.data(forKey: legacy) == nil)
            #expect(hk.anchor(for: "sleep") != nil)
            hk.resetAnchors()
            #expect(hk.anchor(for: "sleep") == nil)
        }
    }
}
