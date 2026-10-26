import Foundation
import SwiftData
import UIKit
@testable import Ryft

/// Holds the fake platform's writes open until `release()`. `waiting` says how many are held: tests poll it (never a
/// fixed sleep) before they act on a request in flight.
final class RequestHold: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var open = false

    var waiting: Int { lock.withLock { continuations.count } }

    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let go = lock.withLock { () -> Bool in
                if open { return true }
                continuations.append(c)
                return false
            }
            if go { c.resume() }
        }
    }

    /// Lets every held write go on, and every later one through.
    func release() {
        let held = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            open = true
            defer { continuations = [] }
            return continuations
        }
        for c in held { c.resume() }
    }
}

/// An environment on the test clock with the fake platform (`MockPlatformAPI` → `MockActivitiesSource`), signed in
/// as the preview account; the uploader retries without jitter.
@MainActor
final class UploadHarness {
    let clock = TestClock()
    let api = MockPlatformAPI()
    let env: AppEnvironment

    init(online: Bool = true, signedIn: Bool = true) {
        env = .test(api: api, clock: clock, auth: signedIn ? nil : .preview(signedIn: false), online: online)
        env.uploader.random = { $0.lowerBound }
        // Closed until the app connects the onboarding's gate; these tests are about what happens past it.
        env.uploader.gate = { _ in nil }
    }

    var store: ActivityStore { env.activities }
    var uploader: ActivityUploader { env.uploader }
    var platform: MockActivitiesSource { api.activitySource }
    var account: String? { env.auth.accountID }
    var today: String { DayFormat.string(from: clock.now()) }

    /// A run of 30 minutes that ended `minutesAgo` minutes before the clock's now.
    func draft(minutesAgo: Double = 60, sport: Sport = .running, notes: String = "") -> ActivityDraft {
        let end = clock.now().addingTimeInterval(-minutesAgo * 60)
        return ActivityDraft(sport: sport, start: end.addingTimeInterval(-1_800), end: end, distanceM: 5_000,
                             perceivedEffort: 5, notes: notes)
    }

    /// Saved through the store, as Add activity does; nil when signed out.
    func save(minutesAgo: Double = 60, sport: Sport = .running, notes: String = "") -> UUID? {
        store.save(manual: draft(minutesAgo: minutesAgo, sport: sport, notes: notes))?.id
    }

    /// A row of another account, written straight into the store.
    @discardableResult
    func insertForeign(account: String = "someone-else") -> UUID {
        let end = clock.now().addingTimeInterval(-3_600)
        let row = LocalActivity(account: account, sport: .cycling, origin: .manual, start: end.addingTimeInterval(-1_800),
                                end: end, movingSec: 1_800, localRevision: 1, createdAt: clock.now())
        env.persistence.context.insert(row)
        env.persistence.save()
        return row.id
    }

    /// A night of eight hours that ended two hours before the clock's now, by its wake day.
    func night() -> (day: String, bed: Date, wake: Date) {
        let wake = clock.now().addingTimeInterval(-2 * 3_600)
        return (DayFormat.string(from: wake), wake.addingTimeInterval(-8 * 3_600), wake)
    }

    func puts() -> Int { api.count("putActivity") }
    func deletes() -> Int { api.count("deleteActivity") }
}

/// `UIApplication`'s background time, recorded.
@MainActor
final class FakeBackgroundApp: BackgroundTaskRunning {
    private(set) var begun = 0
    private(set) var ended: [UIBackgroundTaskIdentifier] = []
    private(set) var expiry: (@MainActor @Sendable () -> Void)?

    func beginBackgroundTask(withName taskName: String?,
                             expirationHandler handler: (@MainActor @Sendable () -> Void)?) -> UIBackgroundTaskIdentifier {
        begun += 1
        expiry = handler
        return UIBackgroundTaskIdentifier(rawValue: begun)
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        ended.append(identifier)
    }
}
