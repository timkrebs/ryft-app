// Drains HealthKit into the backend, page by page, persisting each anchor only
// after its page was accepted. Safe to call from foreground, background
// delivery and a BGAppRefreshTask alike; concurrent calls coalesce. Needs a
// signed-in caller: the SDK restores the session from the Keychain without UI,
// so background runs work too.
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class SyncService {
    /// Migration shim: the live graph's instance (`docs/ARCHITECTURE.md`).
    static let shared = SyncService(env: .live)

    private(set) var isSyncing = false
    private(set) var progress = ""
    private(set) var lastError: String?
    /// Status and request ID of `lastError`, for the inline message's Details.
    private(set) var lastErrorDetails: String?
    private(set) var lastUploaded = 0
    /// Days the last sync queued for rescoring (`days_touched`).
    private(set) var lastDaysTouched: [String] = []
    /// Scoring usually finishes within a few seconds of an upload or recompute.
    static let rescoreDelay: Duration = .seconds(3)

    private let env: AppEnvironment
    private var health: HealthStore { env.health }
    /// Always the account's platform: demo mode never syncs.
    private var api: PlatformAPI { env.liveAPI }
    private var settings: Settings { env.settings }
    private var auth: AuthService { env.auth }
    private var inFlight: Task<[String], Error>?

    init(env: AppEnvironment) {
        self.env = env
    }

    /// Uploads and keeps any error for the screens (Profile → Re-sync, tests).
    func syncNow() async {
        _ = try? await upload()
    }

    /// Uploads what HealthKit has that the platform hasn't and returns the days
    /// queued for rescoring. Concurrent calls share one upload. `SyncCoordinator`
    /// waits for scoring and refreshes afterwards.
    func upload() async throws -> [String] {
        if let t = inFlight { return try await t.value }
        let t = Task { try await run() }
        inFlight = t
        defer { inFlight = nil }
        return try await t.value
    }

    private func run() async throws -> [String] {
        guard auth.isSignedIn else {
            lastError = APIError.signedOut.localizedDescription
            throw APIError.signedOut
        }
        guard settings.isConfigured else {
            lastError = APIError.notConfigured.localizedDescription
            throw APIError.notConfigured
        }
        // Offline: nothing to send; the anchors stay and the next reconnect resumes.
        guard env.connectivity.isOnline else { return [] }
        health.migrateLegacyAnchors()
        isSyncing = true
        lastError = nil
        lastErrorDetails = nil
        lastUploaded = 0
        var touched = Set<String>()
        // A 413 shrinks pages for the rest of this sync only.
        let pageSize = health.pageSize
        defer { isSyncing = false; progress = ""; health.pageSize = pageSize }

        do {
            for stream in health.streams {
                var more = true
                while more {
                    progress = "Reading \(stream.anchorID)…"
                    let page = try await health.nextPage(stream)
                    // On 413 the anchor isn't committed, so the loop re-reads the same page, smaller.
                    guard try await upload(page.delta, touched: &touched) else { continue }
                    health.commit(page, for: stream)
                    more = page.more
                }
            }
            settings.lastSync = env.clock.now()
        } catch {
            lastError = error.localizedDescription
            lastErrorDetails = error.diagnosticDetails
            lastDaysTouched = touched.sorted()
            throw error
        }
        lastDaysTouched = touched.sorted()
        return lastDaysTouched
    }

    /// Smallest page a 413 can shrink to; below that the error is real.
    static let minimumPageSize = 250

    /// `false` when the body was too large (413): `pageSize` is halved and the
    /// caller reads the page again. 503/429 are retried inside APIClient.
    private func upload(_ delta: HealthDelta, touched: inout Set<String>) async throws -> Bool {
        guard !delta.isEmpty else { return true }
        progress = "Uploading \(delta.count) records…"
        let req = SyncRequest(deviceId: settings.deviceId, deviceName: UIDevice.current.name,
                              samples: delta.samples, sleep: delta.sleep, workouts: delta.workouts)
        do {
            let resp = try await api.sync(req)
            lastUploaded += resp.samples + resp.sleep + resp.workouts
            touched.formUnion(resp.daysTouched)
            return true
        } catch let error as APIError where error.status == 413 && health.pageSize > Self.minimumPageSize {
            health.pageSize = max(Self.minimumPageSize, health.pageSize / 2)
            return false
        }
    }

    /// Forget anchors and re-upload the backfill window. Use after changing
    /// `backfillDays` or if the backend database was recreated.
    func fullResync() async {
        health.resetAnchors()
        await syncNow()
    }
}
