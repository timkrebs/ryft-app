import Foundation
import HealthKit

/// One anchored stream HealthKit is drained by: a quantity type, sleep or workouts.
enum HealthStream: Hashable, Sendable {
    case quantity(SampleType)
    case sleep
    case workouts

    /// Key of its persisted anchor (unchanged from before the seam).
    var anchorID: String {
        switch self {
        case .quantity(let t): return t.rawValue
        case .sleep: return "sleep"
        case .workouts: return "workouts"
        }
    }
}

/// One page of new records, with the opaque anchor that marks its end. The caller
/// uploads the delta, then `commit`s the page; that ordering makes sync crash-safe.
struct HealthPage {
    let delta: HealthDelta
    let anchor: Data?
    let more: Bool
}

/// What HealthKit grants is never visible for reads, only whether the prompt still has to show.
enum HealthAccess: Equatable, Sendable {
    case unavailable, notAsked, asked, unknown
}

/// HealthKit, behind a seam. `HealthKitManager` is the live store; `MockHealthStore`
/// scripts pages for tests and previews.
protocol HealthStore: AnyObject {
    var isAvailable: Bool { get }
    /// Streams in the order a sync drains them.
    var streams: [HealthStream] { get }
    /// Records per page; a `413` halves it for the rest of a sync.
    var pageSize: Int { get set }
    func requestAuthorization() async throws
    func accessStatus() async -> HealthAccess
    func enableBackgroundDelivery() async
    func startObserving(onChange: @escaping () async -> Void)
    func nextPage(_ stream: HealthStream) async throws -> HealthPage
    func commit(_ page: HealthPage, for stream: HealthStream)
    func migrateLegacyAnchors()
    func resetAnchors()
}

extension HealthKitManager: HealthStore {
    var isAvailable: Bool { Self.isAvailable }

    var streams: [HealthStream] { quantities.map { .quantity($0.type) } + [.sleep, .workouts] }

    func nextPage(_ stream: HealthStream) async throws -> HealthPage {
        switch stream {
        case .quantity(let type):
            guard let spec = quantities.first(where: { $0.type == type }) else {
                return HealthPage(delta: HealthDelta(), anchor: nil, more: false)
            }
            let p = try await quantityPage(spec)
            return HealthPage(delta: HealthDelta(samples: p.items), anchor: Self.archive(p.anchor), more: p.more)
        case .sleep:
            let p = try await sleepPage()
            return HealthPage(delta: HealthDelta(sleep: p.items), anchor: Self.archive(p.anchor), more: p.more)
        case .workouts:
            let p = try await workoutPage()
            return HealthPage(delta: HealthDelta(workouts: p.items), anchor: Self.archive(p.anchor), more: p.more)
        }
    }

    func commit(_ page: HealthPage, for stream: HealthStream) {
        guard let data = page.anchor,
              let anchor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) else { return }
        save(anchor: anchor, for: stream.anchorID)
    }

    private static func archive(_ anchor: HKQueryAnchor?) -> Data? {
        anchor.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
    }
}

/// Scripted HealthKit for tests and previews: pages per stream, handed out in order.
final class MockHealthStore: HealthStore {
    var isAvailable = true
    var access: HealthAccess = .asked
    var pageSize = 20_000
    let streams: [HealthStream]
    /// Remaining pages per stream; an empty list means "nothing new".
    var pages: [HealthStream: [HealthDelta]]
    /// Thrown by the next `nextPage`, then cleared.
    var nextError: Error?

    private(set) var authorizationRequests = 0
    private(set) var backgroundDeliveryEnabled = false
    private(set) var observing = false
    private(set) var committed: [HealthStream] = []
    private(set) var resets = 0
    private(set) var pageReads = 0
    private var onChange: (() async -> Void)?

    init(streams: [HealthStream] = [.quantity(.heartRate), .sleep, .workouts],
         pages: [HealthStream: [HealthDelta]] = [:]) {
        self.streams = streams
        self.pages = pages
    }

    func requestAuthorization() async throws { authorizationRequests += 1; access = .asked }
    func accessStatus() async -> HealthAccess { access }
    func enableBackgroundDelivery() async { backgroundDeliveryEnabled = true }

    func startObserving(onChange: @escaping () async -> Void) {
        observing = true
        self.onChange = onChange
    }

    /// Simulates HealthKit background delivery.
    func deliverChange() async { await onChange?() }

    /// Like HealthKit: the same page comes back until its anchor is committed.
    func nextPage(_ stream: HealthStream) async throws -> HealthPage {
        if let e = nextError { nextError = nil; throw e }
        let queue = pages[stream] ?? []
        guard let delta = queue.first else { return HealthPage(delta: HealthDelta(), anchor: nil, more: false) }
        pageReads += 1
        return HealthPage(delta: delta, anchor: Data("anchor".utf8), more: queue.count > 1)
    }

    func commit(_ page: HealthPage, for stream: HealthStream) {
        committed.append(stream)
        if pages[stream]?.isEmpty == false { pages[stream]?.removeFirst() }
    }
    func migrateLegacyAnchors() {}
    func resetAnchors() { resets += 1 }
}
