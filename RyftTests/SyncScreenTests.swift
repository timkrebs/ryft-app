import Foundation
import Testing
@testable import Ryft

// Synthetic records only: no real person's data. Times are offsets from a whole second, so `t(0.2)` and `t(0.7)` go over
// the wire as the same second.
private let t0 = Date(timeIntervalSince1970: 1_792_300_000)
private func t(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

private func workout(_ start: TimeInterval, _ end: TimeInterval, id: UUID = UUID(),
                     bundle: String? = "com.example.tracker") -> Workout {
    Workout(id: id, activity: "running", start: t(start), end: t(end), avgHr: 140, maxHr: 170, energyKcal: 300,
            distanceM: 5_000, source: "Tracker", strain: nil, sourceBundleId: bundle)
}

private func segment(_ start: TimeInterval, _ end: TimeInterval, bundle: String? = nil) -> SleepSegment {
    SleepSegment(start: t(start), end: t(end), stage: .core, source: "Ring", sourceBundleId: bundle)
}

private func sample(_ start: TimeInterval, _ end: TimeInterval, value: Double = 60, bundle: String? = nil) -> Sample {
    Sample(type: .heartRate, start: t(start), end: t(end), value: value, unit: "bpm", source: "Watch",
           sourceBundleId: bundle)
}

private let nilUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

/// Ingest's `validate()` (`plattform/backend/cmd/ingest/main.go`), restated from the Go source over a request as the
/// platform decodes it (its dates are the wire's whole seconds; `len` counts UTF-8 bytes after the NULs were removed):
/// the `422`'s message, or nil. Independent of `SyncScreen`, so a test can show what the platform would say.
private func ingestRefusal(_ r: SyncRequest) -> String? {
    func long(_ s: String?, _ limit: Int) -> Bool { (s.map { $0.utf8.filter { $0 != 0 }.count } ?? 0) > limit }
    let zero = try? APIClient.jsonDecoder.decode(Date.self, from: Data(#""0001-01-01T00:00:00Z""#.utf8))
    if long(r.appVersion, 64) || long(r.osVersion, 64) { return "app_version and os_version: at most 64 characters" }
    if r.workouts.count > 5_000 { return "workouts: at most 5000 entries per request" }
    for (i, s) in r.samples.enumerated() {
        if s.start == zero { return "samples[\(i)]: start is required" }
        if s.end < s.start { return "samples[\(i)]: end before start" }
        if long(s.sourceBundleId, 255) { return "samples[\(i)]: source_bundle_id too long" }
    }
    for (i, s) in r.sleep.enumerated() {
        if !(s.end > s.start) { return "sleep[\(i)]: end must be after start" }
        if long(s.sourceBundleId, 255) { return "sleep[\(i)]: source_bundle_id too long" }
    }
    for (i, w) in r.workouts.enumerated() {
        if w.id == nilUUID { return "workouts[\(i)]: id is required" }
        if !(w.end > w.start) { return "workouts[\(i)]: end must be after start" }
        if long(w.sourceBundleId, 255) { return "workouts[\(i)]: source_bundle_id too long" }
    }
    return nil
}

/// What the platform would answer `delta` sent as one request: its records go through the app's encoder and decoder.
private func refusal(of delta: HealthDelta, appVersion: String? = "1.0.0 (1)") -> String? {
    let request = SyncRequest(deviceId: UUID(), appVersion: appVersion, osVersion: "iOS 27.1",
                              samples: delta.samples, sleep: delta.sleep, workouts: delta.workouts)
    guard let body = try? APIClient.jsonEncoder.encode(request),
          let arrived = try? APIClient.jsonDecoder.decode(SyncRequest.self, from: body) else { return "not encodable" }
    return ingestRefusal(arrived)
}

@Suite("Sync screen: ingest's rules")
struct SyncScreenRuleTests {
    @Test("A workout without a duration on the wire is left out, a short one stays")
    func workouts() {
        let kept = [workout(0.8, 1.1), workout(0, 1), workout(0, 3_600)]
        let delta = HealthDelta(workouts: [
            workout(0, 0),                  // no duration: the production case
            kept[0],                        // under a second, but across a whole second
            workout(60, 0),                 // ends before it starts
            kept[1],
            workout(0.2, 0.7),              // under a second within one: the same second on the wire
            workout(0, 3_600, id: nilUUID), // no id for the platform
            kept[2],
        ])

        let result = SyncScreen.screen(delta)

        #expect(result.delta.workouts.map(\.id) == kept.map(\.id)) // the rest in order
        #expect(result.invalid == 4 && result.trimmed == 0)
        #expect(refusal(of: delta) == "workouts[0]: end must be after start")
        #expect(refusal(of: result.delta) == nil)
    }

    @Test("A sleep segment needs its end after its start on the wire")
    func sleep() {
        let delta = HealthDelta(sleep: [segment(0, 0), segment(0, 1), segment(30, 0), segment(0.1, 0.9),
                                        segment(0, 1_800)])

        let result = SyncScreen.screen(delta)

        #expect(result.delta.sleep.map(\.end) == [t(1), t(1_800)])
        #expect(result.invalid == 3)
        #expect(refusal(of: delta) == "sleep[0]: end must be after start")
        #expect(refusal(of: result.delta) == nil)
    }

    @Test("A sample may end as it starts, not before, and needs a start")
    func samples() {
        // How the encoder writes the date the platform reads as "no start" (the rule relies on it).
        #expect(SyncScreen.wire(.distantPast) == SyncScreen.goZeroTime)
        let noStart = Sample(type: .heartRate, start: .distantPast, end: .distantPast, value: 60, unit: "bpm",
                             source: "Watch")
        let justAfter = Sample(type: .heartRate, start: .distantPast.addingTimeInterval(1),
                               end: .distantPast.addingTimeInterval(1), value: 61, unit: "bpm", source: "Watch")
        let delta = HealthDelta(samples: [
            sample(0, 0, value: 1),     // a heart rate: an instant
            sample(5, 0, value: 2),     // ends before it starts
            sample(0.7, 0.2, value: 3), // ends before it starts, within the second: equal on the wire, accepted
            sample(1.2, 0.9, value: 4), // across a second: before on the wire
            noStart,
            justAfter,
        ])

        let result = SyncScreen.screen(delta)

        #expect(result.delta.samples.map(\.value) == [1, 3, 61])
        #expect(result.invalid == 3)
        #expect(refusal(of: delta) == "samples[1]: end before start")
        #expect(refusal(of: HealthDelta(samples: [noStart])) == "samples[0]: start is required")
        #expect(refusal(of: HealthDelta(samples: [justAfter])) == nil)
        #expect(refusal(of: result.delta) == nil)
    }

    @Test("A source_bundle_id over 255 bytes goes as nil, and its record stays")
    func bundleIDs() {
        let limit = String(repeating: "a", count: 255)
        let over = limit + "b"                                // 256 bytes
        let wide = String(repeating: "é", count: 128)         // 128 characters, 256 bytes
        let withNUL = limit + "\u{0}"                         // 256 bytes, 255 once ingest removed the NUL
        let delta = HealthDelta(samples: [sample(0, 0, bundle: over), sample(1, 1, bundle: withNUL)],
                                sleep: [segment(0, 60, bundle: wide)],
                                workouts: [workout(0, 60, bundle: limit), workout(0, 120, bundle: over)])

        let result = SyncScreen.screen(delta)

        #expect(result.delta.samples.map(\.sourceBundleId) == [nil, withNUL])
        #expect(result.delta.sleep.map(\.sourceBundleId) == [nil])
        #expect(result.delta.workouts.map(\.sourceBundleId) == [limit, nil])
        #expect(result.delta.count == delta.count) // every record stays
        #expect(result.trimmed == 3 && result.invalid == 0)
        #expect(refusal(of: delta) == "samples[0]: source_bundle_id too long")
        #expect(refusal(of: result.delta) == nil)
    }

    @Test("An app or OS version over 64 bytes goes as nil")
    func versions() {
        let limit = String(repeating: "1", count: 64)
        #expect(SyncScreen.version(limit) == limit)
        #expect(SyncScreen.version(limit + "2") == nil)
        #expect(SyncScreen.version(String(repeating: "é", count: 32)) == String(repeating: "é", count: 32)) // 64 bytes
        #expect(SyncScreen.version(String(repeating: "é", count: 33)) == nil) // 33 characters, 66 bytes
        #expect(SyncScreen.version(limit + "\u{0}") == limit + "\u{0}")
        #expect(SyncScreen.version(nil) == nil)
        #expect(refusal(of: HealthDelta(), appVersion: limit + "2") == "app_version and os_version: at most 64 characters")
    }

    @Test("A page with nothing the platform refuses goes as it is")
    func cleanPage() {
        let delta = HealthDelta(samples: [sample(0, 0), sample(0, 5)], sleep: [segment(0, 30)],
                                workouts: [workout(0, 2)])

        let result = SyncScreen.screen(delta)

        #expect(result.delta.samples.map(\.end) == [t(0), t(5)])
        #expect(result.delta.sleep.count == 1 && result.delta.workouts.count == 1)
        #expect(result.invalid == 0 && result.trimmed == 0)
    }
}

/// The mock platform refusing as ingest does.
private func refusingAPI() -> MockPlatformAPI {
    let api = MockPlatformAPI()
    api.refuses = { request in ingestRefusal(request).map { APIError.http(422, $0, requestID: "req-422") } }
    return api
}

@Suite("Sync screen: through the engine")
@MainActor
struct SyncScreenEngineTests {
    @Test("A zero-duration workout is left out, its anchor moves and the sync goes on")
    func zeroDurationWorkout() async {
        let valid = workout(0, 1_800)
        let health = MockHealthStore(streams: [.workouts, .quantity(.heartRate)],
                                     pages: [.workouts: [HealthDelta(workouts: [workout(0, 0), valid])],
                                             .quantity(.heartRate): [HealthDelta(samples: [sample(0, 0)])]])
        let api = refusingAPI()
        let sync = SyncService.ungated(env: .test(api: api, health: health))

        await sync.syncNow()

        #expect(api.syncRequests.map(\.workouts.count) == [1, 0])
        #expect(api.syncRequests.first?.workouts.first?.id == valid.id)
        #expect(api.syncRequests.map(\.samples.count) == [0, 1]) // the stream after it went up too
        #expect(health.committed == [.workouts, .quantity(.heartRate)])
        #expect(sync.lastError == nil && sync.engineState.backfillDone)
        let workouts = sync.engineState.streams["workouts"]
        #expect(workouts?.invalid == 1 && workouts?.records == 1 && workouts?.backfilled == true)
        #expect(sync.engineState.streams["heart_rate"]?.invalid == 0)
    }

    @Test("A page of only invalid records counts as done, and the next page follows")
    func onlyInvalid() async {
        let valid = workout(0, 600)
        let health = MockHealthStore(streams: [.workouts],
                                     pages: [.workouts: [HealthDelta(workouts: [workout(0, 0), workout(60, 0)]),
                                                         HealthDelta(workouts: [valid])]])
        let api = refusingAPI()
        let sync = SyncService.ungated(env: .test(api: api, health: health))

        await sync.syncNow()

        #expect(api.count("sync") == 1) // nothing was left of the first page to send
        #expect(api.syncRequests.map { $0.workouts.map(\.id) } == [[valid.id]])
        #expect(health.committed == [.workouts, .workouts])
        #expect(sync.lastError == nil)
        #expect(sync.engineState.streams["workouts"]?.invalid == 2)
        #expect(sync.engineState.streams["workouts"]?.backfilled == true)
    }

    @Test("Sleep and samples lose only their invalid records")
    func sleepAndSamples() async {
        let health = MockHealthStore(streams: [.sleep, .quantity(.heartRate)], pages: [
            .sleep: [HealthDelta(sleep: [segment(0, 1_800), segment(1_800, 1_800)])],
            .quantity(.heartRate): [HealthDelta(samples: [sample(0, 0, value: 1), sample(10, 0, value: 2),
                                                          sample(20, 25, value: 3)])],
        ])
        let api = refusingAPI()
        let sync = SyncService.ungated(env: .test(api: api, health: health))

        await sync.syncNow()

        #expect(api.syncRequests.map(\.sleep.count) == [1, 0])
        #expect(api.syncRequests.last?.samples.map(\.value) == [1, 3])
        #expect(health.committed == [.sleep, .quantity(.heartRate)])
        #expect(sync.lastError == nil)
        #expect(sync.engineState.streams["sleep"]?.invalid == 1)
        #expect(sync.engineState.streams["heart_rate"]?.invalid == 1)
    }

    @Test("A workout with a too-long source_bundle_id goes without it")
    func bundleIDDropped() async {
        let long = workout(0, 1_800, bundle: String(repeating: "x", count: 256))
        let health = MockHealthStore(streams: [.workouts], pages: [.workouts: [HealthDelta(workouts: [long])]])
        let api = refusingAPI()
        let sync = SyncService.ungated(env: .test(api: api, health: health))

        await sync.syncNow()

        let sent = api.syncRequests.first?.workouts.first
        #expect(sent?.id == long.id && sent?.distanceM == 5_000)
        #expect(sent?.sourceBundleId == nil)
        #expect(health.committed == [.workouts] && sync.lastError == nil)
        #expect(sync.engineState.streams["workouts"]?.invalid == 0) // kept, so not counted
    }

    @Test("A workout page never asks for more than the platform takes")
    func workoutPagesWithinTheLimit() async throws {
        let pages = (0..<3).map { _ in HealthDelta(workouts: [workout(0, 60), workout(60, 120), workout(120, 180)]) }
        let health = MockHealthStore(streams: [.workouts], pages: [.workouts: pages])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .sleep) // not a first sync
        let api = MockPlatformAPI()
        let sync = SyncService.ungated(env: .test(api: api, health: health))

        await sync.syncNow()

        // The first page and the one read ahead: the estimate, below the limit anyway.
        let estimate = Int(Double(SyncEngine.targetPageBytes) / SyncEngine.estimatedBytesPerRecord(.workouts))
        #expect(Array(health.limits.prefix(2)) == [estimate, estimate])
        // The third, after a page measured small workouts: what fits would be more than the platform takes.
        try #require(health.limits.count == 3 && api.syncBodySizes.count == 3)
        let measured = Double(api.syncBodySizes[0]) / 3
        #expect(Int(Double(SyncEngine.targetPageBytes) / measured) > SyncScreen.maxWorkouts)
        #expect(health.limits[2] == SyncScreen.maxWorkouts)
    }

    @Test("An app version the platform would refuse goes as nil")
    func versionDropped() async throws {
        let first = HealthDelta(samples: [sample(0, 0)])
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [first]])
        let api = refusingAPI()
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let engine = SyncEngine(health: health, api: api, defaults: defaults)
        let limit = "1.0.0 (" + String(repeating: "9", count: 56) + ")" // 64 bytes
        func context(_ version: String) -> SyncEngine.Context {
            SyncEngine.Context(account: "acct", deviceID: UUID(), deviceName: nil, appVersion: version,
                               osVersion: "iOS 27.1", now: t0)
        }

        _ = try await engine.run(context(limit + "9"), gate: { nil }, report: { _ in })
        health.pages[.quantity(.heartRate)] = [first, HealthDelta(samples: [sample(1, 1)])] // one more page
        _ = try await engine.run(context(limit), gate: { nil }, report: { _ in })

        #expect(api.syncRequests.map(\.appVersion) == [nil, limit])
        #expect(api.syncRequests.map(\.osVersion) == ["iOS 27.1", "iOS 27.1"])
    }

    @Test("A record the first score's window leaves out is counted once, by the backfill")
    func recentWindowCountsOnce() async throws {
        let recent = workout(0, 1_800)
        let older = workout(-86_400, -84_600)
        let health = MockHealthStore(streams: [.workouts],
                                     pages: [.workouts: [HealthDelta(workouts: [workout(0, 0), recent, older])]],
                                     recent: [.workouts: [HealthDelta(workouts: [workout(0, 0), recent])]])
        let api = refusingAPI()
        api.syncResponse = SyncResponse(samples: 0, sleep: 0, workouts: 1, daysTouched: ["2026-10-17"])
        let sync = SyncService.ungated(env: .test(api: api, health: health))

        _ = try await sync.upload()

        #expect(sync.hasBacklog) // stopped after the window, before the backfill
        #expect(api.syncRequests.map { $0.workouts.map(\.id) } == [[recent.id]])
        #expect(sync.engineState.streams["workouts"]?.invalid == 0)

        _ = try await sync.upload()

        #expect(api.syncRequests.map(\.workouts.count) == [1, 2])
        #expect(health.committed == [.workouts])
        #expect(sync.engineState.streams["workouts"]?.invalid == 1)
    }
}
