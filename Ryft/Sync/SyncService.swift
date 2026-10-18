// Drains HealthKit into the backend, page by page, persisting each anchor only
// after its page was accepted. Safe to call from foreground, background
// delivery and a BGAppRefreshTask alike; concurrent calls coalesce. Needs a
// signed-in caller: the SDK restores the session from the Keychain without UI,
// so background runs work too.
import Foundation
import HealthKit
import UIKit

@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published private(set) var isSyncing = false
    @Published private(set) var progress = ""
    @Published private(set) var lastError: String?
    /// Status and request ID of `lastError`, for the inline message's Details.
    @Published private(set) var lastErrorDetails: String?
    @Published private(set) var lastUploaded = 0

    private let hk = HealthKitManager.shared
    private let api = APIClient.shared
    private let settings = Settings.shared
    private var auth: AuthService { .shared }
    private var inFlight: Task<Void, Never>?

    func syncNow() async {
        if let t = inFlight { await t.value; return }
        let t = Task { await run() }
        inFlight = t
        await t.value
        inFlight = nil
    }

    private func run() async {
        guard auth.isSignedIn else { lastError = APIError.signedOut.localizedDescription; return }
        guard settings.isConfigured else { lastError = APIError.notConfigured.localizedDescription; return }
        isSyncing = true
        lastError = nil
        lastErrorDetails = nil
        lastUploaded = 0
        // A 413 shrinks pages for the rest of this sync only.
        let pageSize = hk.pageSize
        defer { isSyncing = false; progress = ""; hk.pageSize = pageSize }

        do {
            // On 413 the anchor isn't saved, so `continue` re-reads the same page, smaller.
            for spec in hk.quantities {
                var more = true
                while more {
                    progress = "Reading \(spec.type.rawValue)…"
                    let page = try await hk.quantityPage(spec)
                    guard try await upload(HealthDelta(samples: page.items)) else { continue }
                    if let a = page.anchor { hk.save(anchor: a, for: spec.type.rawValue) }
                    more = page.more
                }
            }
            var more = true
            while more {
                progress = "Reading sleep…"
                let page = try await hk.sleepPage()
                guard try await upload(HealthDelta(sleep: page.items)) else { continue }
                if let a = page.anchor { hk.save(anchor: a, for: "sleep") }
                more = page.more
            }
            more = true
            while more {
                progress = "Reading workouts…"
                let page = try await hk.workoutPage()
                guard try await upload(HealthDelta(workouts: page.items)) else { continue }
                if let a = page.anchor { hk.save(anchor: a, for: "workouts") }
                more = page.more
            }
            settings.lastSync = .now
        } catch {
            lastError = error.localizedDescription
            lastErrorDetails = error.diagnosticDetails
        }
    }

    /// Smallest page a 413 can shrink to; below that the error is real.
    static let minimumPageSize = 250

    /// `false` when the body was too large (413): `pageSize` is halved and the
    /// caller reads the page again. 503/429 are retried inside APIClient.
    private func upload(_ delta: HealthDelta) async throws -> Bool {
        guard !delta.isEmpty else { return true }
        progress = "Uploading \(delta.count) records…"
        let req = SyncRequest(deviceId: settings.deviceId, deviceName: UIDevice.current.name,
                              samples: delta.samples, sleep: delta.sleep, workouts: delta.workouts)
        do {
            let resp = try await api.sync(req)
            lastUploaded += resp.samples + resp.sleep + resp.workouts
            return true
        } catch let error as APIError where error.status == 413 && hk.pageSize > Self.minimumPageSize {
            hk.pageSize = max(Self.minimumPageSize, hk.pageSize / 2)
            return false
        }
    }

    /// Forget anchors and re-upload the backfill window. Use after changing
    /// `backfillDays` or if the backend database was recreated.
    func fullResync() async {
        hk.resetAnchors()
        await syncNow()
    }
}
