import Foundation
import SwiftData
import UIKit
import UserNotifications

// MARK: - persistence

/// The SwiftData container behind a seam: on disk in the app, in memory for tests
/// and previews. `TrainStore` is the live one (§3 extends it to every read model).
@MainActor
protocol Persistence: AnyObject {
    var container: ModelContainer { get }
    var context: ModelContext { get }
    func save()
    /// Everything the signed-in user left behind (sign-out, account switch).
    func wipe()
    /// Small keyed documents (`CachedDocument`), wiped with the rest.
    func document<T: Decodable>(_ type: T.Type, key: String) -> T?
    func saveDocument<T: Encodable>(_ value: T, key: String, at date: Date)
    func removeDocument(key: String)
}

extension TrainStore: Persistence {}

// MARK: - connectivity

/// Whether there's a network path. `ConnectivityMonitor` is the live one; its
/// `preview(online:)` is the fixed one for tests and previews.
@MainActor
protocol Connectivity: AnyObject {
    var isOnline: Bool { get }
}

extension ConnectivityMonitor: Connectivity {}

// MARK: - notifications

/// Local and remote notifications behind a seam: `SystemNotifier` talks to
/// `UNUserNotificationCenter` and APNs registration, `MockNotifier` records.
@MainActor
protocol Notifier: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    /// `true` when the user allowed alerts.
    func requestAuthorization() async throws -> Bool
    func setCategories(_ categories: Set<UNNotificationCategory>)
    func add(_ request: UNNotificationRequest) async throws
    func removePending(ids: [String])
    func pendingIDs() async -> [String]
    func registerForRemoteNotifications()
    func unregisterForRemoteNotifications()
}

final class SystemNotifier: Notifier {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) { center.setNotificationCategories(categories) }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePending(ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func pendingIDs() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func registerForRemoteNotifications() { UIApplication.shared.registerForRemoteNotifications() }
    func unregisterForRemoteNotifications() { UIApplication.shared.unregisterForRemoteNotifications() }
}

final class MockNotifier: Notifier {
    var status: UNAuthorizationStatus = .notDetermined
    /// What the user answers when asked.
    var grants = true

    private(set) var requests: [UNNotificationRequest] = []
    private(set) var categories: Set<UNNotificationCategory> = []
    private(set) var registeredForRemote = false
    private(set) var authorizationPrompts = 0

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        authorizationPrompts += 1
        status = grants ? .authorized : .denied
        return grants
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) { self.categories = categories }

    func add(_ request: UNNotificationRequest) async throws {
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }

    func removePending(ids: [String]) { requests.removeAll { ids.contains($0.identifier) } }
    func pendingIDs() async -> [String] { requests.map(\.identifier) }
    func registerForRemoteNotifications() { registeredForRemote = true }
    func unregisterForRemoteNotifications() { registeredForRemote = false }
}

// MARK: - feature flags

/// Every flag the app reads (`GET /v1/config` keys are open; these are the ones we know).
enum FeatureFlag: String, CaseIterable, Identifiable, Sendable {
    case trainEnabled = "train.enabled"
    case sleepPlanner = "sleep.planner"
    case todayRedesign = "today.redesign"
    // TODO(coach.enabled): reserved; no coach feature yet.
    case coachEnabled = "coach.enabled"
    case pushEnabled = "push.enabled"
    // TODO(physiology.card): reserved; no physiology card yet.
    case physiologyCard = "physiology.card"

    var id: String { rawValue }

    /// Compiled in, used until (and whenever) the platform's answer is missing.
    var compiledDefault: Bool {
        switch self {
        case .trainEnabled, .sleepPlanner: return true
        case .todayRedesign, .coachEnabled, .pushEnabled, .physiologyCard: return false
        }
    }
}

/// Where a flag's value came from, for Profile → Developer.
enum FlagSource: String, Sendable {
    case compiled, remote, override
}

@MainActor
protocol FeatureFlagProvider: AnyObject {
    func isOn(_ flag: FeatureFlag) -> Bool
    func source(of flag: FeatureFlag) -> FlagSource
}

/// Compiled defaults plus local overrides: previews, tests, and the fallback before §8's remote flags.
final class StaticFlags: FeatureFlagProvider {
    var overrides: [FeatureFlag: Bool]

    init(_ overrides: [FeatureFlag: Bool] = [:]) {
        self.overrides = overrides
    }

    func isOn(_ flag: FeatureFlag) -> Bool { overrides[flag] ?? flag.compiledDefault }
    func source(of flag: FeatureFlag) -> FlagSource { overrides[flag] == nil ? .compiled : .override }
}
