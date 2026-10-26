import Foundation
import HealthKit
import Testing
@testable import Ryft

private func samples(_ n: Int, _ type: SampleType = .heartRate) -> HealthDelta {
    let t = Date(timeIntervalSince1970: 1_792_300_000)
    return HealthDelta(samples: (0..<n).map {
        Sample(type: type, start: t.addingTimeInterval(Double($0) * 60), end: t.addingTimeInterval(Double($0) * 60),
               value: 60, unit: "bpm", source: "Garmin")
    })
}

/// Waits until `condition` holds, for at most `timeout` of wall time, so a broken
/// expectation fails instead of hanging the run. Bounded by time, not by a number of
/// yields: on a loaded CI runner (parallel tests) thousands of yields pass before
/// work on another executor gets a thread. 30 s: the whole plan queues on the main
/// actor at its start, which a CI runner took 12 s to work through. That backlog is now
/// bounded at its source: the test plans cap Swift Testing's parallelism
/// (`SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH`), so each poll here waits behind a
/// few main-actor test bodies, not behind every test of the plan (see docs/CI.md).
@MainActor
func eventually(timeout: Duration = .seconds(30), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        await Task.yield()
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return condition()
}

@Suite("Test clock")
struct TestClockTests {
    @Test func sleepEndsOnlyWhenTimeAdvances() async throws {
        let clock = TestClock()
        let start = clock.now()
        let waiter = Task { try await clock.sleep(for: .seconds(3)) }
        #expect(await eventually { clock.pendingSleeps != 0 })
        clock.advance(by: .seconds(2))
        #expect(clock.pendingSleeps == 1)
        clock.advance(by: .seconds(1))
        try await waiter.value
        #expect(clock.now() == start.addingTimeInterval(3))
    }

    @Test func cancellingASleepThrows() async {
        let clock = TestClock()
        let waiter = Task { try await clock.sleep(for: .seconds(60)) }
        #expect(await eventually { clock.pendingSleeps != 0 })
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(clock.pendingSleeps == 0)
    }
}

@Suite("Sync through the seams")
@MainActor
struct SyncSeamTests {
    @Test func drainsEveryStreamAndCommitsAfterUpload() async {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [samples(3), samples(2)],
                                            .sleep: [HealthDelta(sleep: [])]])
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 3, sleep: 0, workouts: 0, daysTouched: ["2026-10-19"])
        let env = AppEnvironment.test(api: api, health: health)
        let sync = SyncService(env: env)

        await sync.syncNow()

        #expect(api.syncRequests.map(\.samples.count) == [3, 2]) // the empty sleep page isn't sent
        #expect(health.committed == [.quantity(.heartRate), .quantity(.heartRate), .sleep, .workouts])
        #expect(sync.lastError == nil)
        #expect(sync.lastDaysTouched == ["2026-10-19"])
        #expect(env.settings.lastSync == env.clock.now())
    }

    @Test func tooLargeHalvesThePageAndReadsItAgain() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(4)]])
        health.pageSize = 1_000
        let api = MockPlatformAPI()
        api.failNext = APIError.http(413, "too large")
        let sync = SyncService(env: .test(api: api, health: health))

        await sync.syncNow()

        #expect(api.count("sync") == 2)
        #expect(health.pageReads == 2)
        #expect(health.committed == [.quantity(.heartRate)]) // committed once, after the accepted upload
        #expect(health.pageSize == 1_000) // restored after the sync
        #expect(sync.lastError == nil)
    }

    @Test func offlineSendsNothing() async {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [samples(1)]])
        let api = MockPlatformAPI()
        let sync = SyncService(env: .test(api: api, health: health, online: false))

        await sync.syncNow()

        #expect(api.calls.isEmpty)
        #expect(health.committed.isEmpty)
    }

    @Test func failedUploadKeepsTheAnchor() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(2)]])
        let api = MockPlatformAPI()
        api.failNext = APIError.http(500, "")
        let sync = SyncService(env: .test(api: api, health: health))

        await sync.syncNow()

        #expect(health.committed.isEmpty)
        #expect(sync.lastError != nil)
    }
}

@Suite("Mock platform")
struct MockPlatformTests {
    @Test func failNextFailsOnceAndCallsAreRecorded() async throws {
        let api = MockPlatformAPI()
        api.failNext = APIError.http(503, "")
        await #expect(throws: APIError.self) { _ = try await api.me() }
        _ = try await api.me()
        #expect(api.count("me") == 2)
    }

    @Test func notificationPatchMerges() async throws {
        let api = MockPlatformAPI()
        let prefs = try await api.patchNotifications(NotificationPatch(categories: ["PR": false],
                                                                        quietHours: QuietHours(from: "22:30", to: "07:00")))
        #expect(!prefs.isOn(.pr) && prefs.isOn(.morningScore))
        #expect(prefs.quietHours?.to == "07:00")
        let cleared = try await api.patchNotifications(NotificationPatch(quietHours: .some(nil)))
        #expect(cleared.quietHours == nil && !cleared.isOn(.pr))
    }
}

@Suite("Sync engine")
@MainActor
struct SyncEngineTests {
    @Test func theNightGoesUpBeforeTheDayStreams() {
        let order = HealthKitManager.shared.streams
        #expect(order.first == .sleep)
        #expect(Array(order.prefix(5)) == [.sleep, .quantity(.hrvSDNN), .quantity(.restingHR),
                                           .quantity(.respiratoryRate), .quantity(.spo2)])
        let heartRate = order.firstIndex(of: .quantity(.heartRate)) ?? -1
        #expect((order.firstIndex(of: .workouts) ?? .max) < heartRate)
        #expect(order.suffix(3) == [.quantity(.steps), .quantity(.activeEnergy), .quantity(.vo2max)])
        #expect(Set(order).count == SampleType.allCases.count + 2) // every type, once
    }

    @Test func readingMappingEncodingAndUploadingStayOffTheMainThread() async {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [samples(3), samples(2)], .sleep: [samples(1)]])
        let api = MockPlatformAPI()
        let sync = SyncService(env: .test(api: api, health: health))

        await sync.syncNow()

        #expect(api.count("sync") == 3)
        #expect(health.readsOnMainThread == 0)
        #expect(api.syncsOnMainThread == 0)
    }

    @Test func aFirstSyncSendsTheLastDaysFirstAndLeavesTheBackfillForAfterTheScore() async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [samples(5), samples(5)], .sleep: [samples(2)]],
                                     recent: [.sleep: [samples(1)], .quantity(.heartRate): [samples(2)]])
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 1, sleep: 0, workouts: 0, daysTouched: ["2026-10-21"])
        let env = AppEnvironment.test(api: api, health: health)
        let sync = SyncService(env: env)

        let touched = try await sync.upload()

        #expect(touched == ["2026-10-21"])
        #expect(sync.hasBacklog)
        #expect(api.syncRequests.map(\.samples.count) == [2, 1]) // the recent window only, in stream order
        #expect(health.recentReads == 2 && health.pageReads == 0)
        #expect(health.committed.isEmpty) // the recent window's anchors are never kept
        #expect(sync.engineState.recentDone && sync.engineState.phase == .backfill)

        _ = try await sync.upload()

        #expect(!sync.hasBacklog)
        #expect(api.syncRequests.map(\.samples.count) == [2, 1, 5, 5, 2])
        #expect(health.committed == [.quantity(.heartRate), .quantity(.heartRate), .sleep, .workouts])
        #expect(sync.engineState.backfillDone && sync.engineState.phase == .idle)
        #expect(sync.engineState.streams["heart_rate"]?.backfilled == true)
    }

    @Test func aFirstSyncWithNothingRecentGoesStraightOn() async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [samples(3)]])
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 3, sleep: 0, workouts: 0, daysTouched: ["2026-10-18"])
        let sync = SyncService(env: .test(api: api, health: health))

        _ = try await sync.upload()

        #expect(!sync.hasBacklog && health.pageReads == 1 && sync.engineState.backfillDone)
    }

    @Test func anAccountWithAnchorsSkipsTheRecentWindow() async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [samples(1)]], recent: [.sleep: [samples(4)]])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .workouts) // synced before
        let api = MockPlatformAPI()
        let sync = SyncService(env: .test(api: api, health: health))

        _ = try await sync.upload()

        #expect(health.recentReads == 0)
        #expect(api.syncRequests.map(\.samples.count) == [1])
    }

    @Test func readsOnePageAheadWhileAPageUploadsAndNeverMore() async {
        let clock = TestClock()
        let health = MockHealthStore(streams: [.quantity(.heartRate)],
                                     pages: [.quantity(.heartRate): [samples(2), samples(2), samples(2), samples(2)]])
        let api = MockPlatformAPI()
        api.beforeSync = { try? await clock.sleep(for: .seconds(1)) }
        let sync = SyncService(env: .test(api: api, health: health, clock: clock))
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .sleep) // not a first sync
        let run = Task { await sync.syncNow() }

        // Page 0 is uploading: page 1 is read already, page 2 not yet.
        #expect(await eventually { clock.pendingSleeps == 1 && health.pageReads == 2 })
        #expect(health.committed.count == 1) // only the .sleep set up above
        clock.advance(by: .seconds(1))
        #expect(await eventually { clock.pendingSleeps == 1 && health.pageReads == 3 })
        #expect(health.committed.count == 2) // page 0, after its upload
        clock.advance(by: .seconds(1))
        #expect(await eventually { clock.pendingSleeps == 1 && health.pageReads == 4 })
        clock.advance(by: .seconds(1))
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(1))
        await run.value

        #expect(api.count("sync") == 4 && health.pageReads == 4)
        #expect(health.committed.filter { $0 == .quantity(.heartRate) }.count == 4)
    }

    @Test func pagesAreSizedByTheBytesTheLastPageMeasured() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)],
                                     pages: [.quantity(.heartRate): [samples(100), samples(100), samples(100)]])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .sleep) // not a first sync
        let api = MockPlatformAPI()
        let sync = SyncService(env: .test(api: api, health: health))

        await sync.syncNow()

        let estimate = Int(Double(SyncEngine.targetPageBytes) / SyncEngine.estimatedBytesPerRecord(.quantity(.heartRate)))
        // The first page, and the one read ahead while it uploaded: the estimate.
        #expect(Array(health.limits.prefix(2)) == [estimate, estimate].map { min($0, health.pageSize) })
        // The third, after the first page's encoded size was measured.
        let measured = Double(api.syncBodySizes[0]) / 100
        #expect(health.limits[2] == min(health.pageSize, Int(Double(SyncEngine.targetPageBytes) / measured)))
    }

    @Test func theEngineStateIsPersistedPerAccount() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(3)]])
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 2, sleep: 0, workouts: 0, daysTouched: ["2026-10-18"],
                                        ignored: SyncIgnored(samples: IgnoredCounts(duplicate: 1, outsideWindow: 0,
                                                                                    unknownType: 0),
                                                             sleep: .none, workouts: .none))
        let env = AppEnvironment.test(api: api, health: health)
        let sync = SyncService(env: env)

        await sync.syncNow()

        let saved = SyncEngineState.load(account: env.auth.accountID, defaults: env.defaults)
        #expect(saved == sync.engineState)
        let hr = saved.streams["heart_rate"]
        #expect(hr?.records == 3 && hr?.lastAccepted == 2 && hr?.lastIgnored?.duplicate == 1)
        #expect(hr?.oldest != nil && hr?.newest != nil)
        #expect(saved.bytesUploaded == api.syncBodySizes.reduce(0, +))
        #expect(SyncEngineState.load(account: "someone-else", defaults: env.defaults) == SyncEngineState())
    }

    @Test func aFailureIsPersistedWithItsRequestID() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(1)]])
        let api = MockPlatformAPI()
        api.failNext = APIError.http(500, "", requestID: "01a15a69-7142-7a8b-aba2-c099a5fcd1e4")
        let env = AppEnvironment.test(api: api, health: health)
        let sync = SyncService(env: env)

        await sync.syncNow()

        #expect(sync.engineState.lastRequestID == "01a15a69-7142-7a8b-aba2-c099a5fcd1e4")
        #expect(sync.engineState.lastError != nil && sync.engineState.phase == .idle)
        #expect(SyncEngineState.load(account: env.auth.accountID, defaults: env.defaults).lastRequestID != nil)
        SyncEngineState.wipe(defaults: env.defaults)
        #expect(SyncEngineState.load(account: env.auth.accountID, defaults: env.defaults) == SyncEngineState())
    }

    @Test func aFullResyncIsABackfillAgain() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(2)]])
        let api = MockPlatformAPI()
        let sync = SyncService(env: .test(api: api, health: health))
        await sync.syncNow()
        #expect(sync.engineState.backfillDone)

        await sync.fullResync()

        #expect(health.resets == 1)
        #expect(sync.engineState.backfillDone) // drained again
        #expect(sync.engineState.streams["heart_rate"]?.records == 2) // counted from zero
    }
}

@Suite("Sync engine: background, lock, deletions")
@MainActor
struct SyncEngineBackgroundTests {
    @Test func stoppingFinishesThePageInFlightAndLeavesABacklog() async {
        let clock = TestClock()
        let health = MockHealthStore(streams: [.quantity(.heartRate), .sleep],
                                     pages: [.quantity(.heartRate): [samples(2), samples(2)], .sleep: [samples(1)]])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .workouts) // not a first sync
        let api = MockPlatformAPI()
        api.beforeSync = { try? await clock.sleep(for: .seconds(1)) }
        let sync = SyncService(env: .test(api: api, health: health, clock: clock))
        let run = Task { await sync.syncNow() }
        #expect(await eventually { clock.pendingSleeps == 1 }) // page 0 uploading

        await sync.stopAfterCurrentPage()
        clock.advance(by: .seconds(1))
        await run.value

        #expect(api.count("sync") == 1) // page 1 never went up
        #expect(health.committed.filter { $0 == .quantity(.heartRate) }.count == 1) // page 0's anchor is in
        #expect(sync.hasBacklog && sync.lastError == nil)
        #expect((sync.backlogBytes ?? 0) > 0 && !sync.engineState.backfillDone)
    }

    @Test func aLockedPhoneWaitsAndResumesAfterTheUnlock() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(2)]])
        health.nextError = HKError(.errorDatabaseInaccessible)
        let api = MockPlatformAPI()
        let sync = SyncService(env: .test(api: api, health: health))

        let touched = try? await sync.upload()

        #expect(touched == [] && sync.waitingForUnlock)
        #expect(sync.lastError == nil && sync.phase == .idle) // waiting, not failed
        #expect(health.committed.isEmpty && api.count("sync") == 0)

        await sync.syncNow() // unlocked
        #expect(!sync.waitingForUnlock && api.count("sync") == 1)
    }

    @Test func deletionsInAppleHealthAreKeptForThePlatform() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(1)]])
        let gone = [UUID(), UUID()]
        health.deletions = [.quantity(.heartRate): gone]
        let env = AppEnvironment.test(health: health)
        let sync = SyncService(env: env)

        await sync.syncNow()

        let kept = PendingDeletions.load(account: env.auth.accountID ?? "", defaults: env.defaults)
        #expect(kept["heart_rate"] == gone.map { $0.uuidString.lowercased() })
        #expect(sync.engineState.pendingDeletions == 2)
        let many = (0..<(PendingDeletions.limitPerStream + 10)).map { _ in UUID() }
        let total = PendingDeletions.add(many, stream: .sleep, account: "a", defaults: env.defaults)
        #expect(total == PendingDeletions.limitPerStream) // bounded, the newest kept
        #expect(PendingDeletions.load(account: "a", defaults: env.defaults)["sleep"]?.last == many.last?.uuidString.lowercased())
        SyncEngineState.wipe(defaults: env.defaults)
        #expect(PendingDeletions.load(account: "a", defaults: env.defaults).isEmpty)
    }

    @Test func theBacklogIsEstimatedFromTheStreamsDone() {
        var done = SyncEngineState.StreamProgress()
        done.bytes = 4_000_000
        done.backfilled = true
        var half = SyncEngineState.StreamProgress()
        half.bytes = 1_000_000
        let streams = ["sleep": done, "heart_rate": half]
        #expect(SyncEngineState.backlogEstimate(streams, remaining: ["heart_rate", "steps"]) == 3_000_000 + 4_000_000)
        #expect(SyncEngineState.backlogEstimate([:], remaining: ["heart_rate"]) == SyncEngineState.unmeasuredStreamBytes)
    }

    @Test func observersAreRegisteredOnceAndADeliveryCompletesAfterItsUpload() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(1)]])
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, health: health)
        let state = AppState(env: env)
        let sync = SyncService(env: env)
        // Launched in the background for the delivery.
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock,
                                          inBackground: true)

        RyftApp.observeHealthKit(health, coordinator: coordinator) // launch
        RyftApp.observeHealthKit(health, coordinator: coordinator) // bootstrap
        #expect(health.observerRegistrations == 1)
        #expect(await eventually { health.backgroundDeliveryEnabled })

        let completed = SyncCoordinatorBackgroundTests.Completions()
        health.deliverChange { completed.done() }
        #expect(await eventually { completed.calls == 1 })
        #expect(api.count("sync") == 1) // the completion came after the upload
    }

    @Test func backgroundRunsFailFastInsteadOfWaitingForANetwork() {
        let c = APIClient.backgroundConfiguration
        #expect(!c.waitsForConnectivity)
        #expect(c.timeoutIntervalForRequest == 20 && c.timeoutIntervalForResource == 25)
        #expect(APIClient.defaultConfiguration.waitsForConnectivity)
        #expect(!APIClient.runsInBackground)
    }
}

/// The review on #10.
@Suite("Sync engine: account changes, checkpoints")
@MainActor
struct SyncEngineReviewTests {
    @Test func aWipeDuringARunIsNotUndoneByIt() async {
        let clock = TestClock()
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(2)]])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .sleep)
        let api = MockPlatformAPI()
        api.beforeSync = { try? await clock.sleep(for: .seconds(1)) }
        let env = AppEnvironment.test(api: api, health: health, clock: clock)
        let sync = SyncService(env: env)
        let run = Task { await sync.syncNow() }
        #expect(await eventually { clock.pendingSleeps == 1 })

        await env.auth.signOut() // signed out meanwhile: the wipe, then the account change
        SyncEngineState.wipe(defaults: env.defaults)
        sync.accountChanged()
        clock.advance(by: .seconds(1))
        await run.value

        #expect(SyncEngineState.load(account: env.auth.accountID, defaults: env.defaults) == SyncEngineState())
        #expect(sync.engineState.streams.isEmpty) // late reports of that run were ignored
    }

    @Test func progressIsCheckpointedWithEachAnchor() async {
        let clock = TestClock()
        let health = MockHealthStore(streams: [.quantity(.heartRate)],
                                     pages: [.quantity(.heartRate): [samples(2), samples(3)]])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .sleep)
        let api = MockPlatformAPI()
        api.beforeSync = { try? await clock.sleep(for: .seconds(1)) }
        let env = AppEnvironment.test(api: api, health: health, clock: clock)
        let sync = SyncService(env: env)
        let run = Task { await sync.syncNow() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(1)) // page 0 accepted and committed; page 1 uploading
        #expect(await eventually { clock.pendingSleeps == 1 && api.count("sync") == 2 })

        // If iOS ended the app now, the next launch would find page 0's progress.
        let saved = SyncEngineState.load(account: env.auth.accountID, defaults: env.defaults)
        #expect(saved.streams["heart_rate"]?.records == 2)
        clock.advance(by: .seconds(1))
        await run.value
    }

    @Test func anAccountThatSyncedBeforeAndAFullResyncSkipTheWindow() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(2)]],
                                     recent: [.quantity(.heartRate): [samples(1)]])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .sleep)
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 1, sleep: 0, workouts: 0, daysTouched: ["2026-10-20"])
        let sync = SyncService(env: .test(api: api, health: health))

        await sync.syncNow()
        #expect(sync.engineState.recentDone && health.recentReads == 0)

        await sync.fullResync() // anchors gone: still the whole window, no backlog left
        #expect(health.recentReads == 0 && !sync.hasBacklog && sync.engineState.backfillDone)
    }

    @Test func cancellingTheCoordinatorReachesTheUpload() async {
        let clock = TestClock()
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(2)]])
        let api = MockPlatformAPI()
        api.beforeSync = { try? await clock.sleep(for: .seconds(60)) }
        let env = AppEnvironment.test(api: api, health: health, clock: clock)
        let state = AppState(env: env)
        let sync = SyncService(env: env)
        let c = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        await c.cancel() // sign-out
        let outcome = await run.value
        #expect(outcome.cancelled)
        #expect(sync.engineState.lastError == nil && sync.lastError == nil) // cancelled, not failed
    }
}

/// The review on #11.
@Suite("Sync engine: background details")
@MainActor
struct SyncEngineBackgroundReviewTests {
    @Test func deletionsAreKeptBeforeTheAnchorMoves() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(1)]])
        health.deletions = [.quantity(.heartRate): [UUID()]]
        let env = AppEnvironment.test(health: health)
        let account = env.auth.accountID ?? ""
        let keptAtCommit = Counter()
        health.onCommit = { _ in
            if !PendingDeletions.load(account: account, defaults: env.defaults).isEmpty { keptAtCommit.add() }
        }
        await SyncService(env: env).syncNow()
        #expect(keptAtCommit.value >= 1)
    }

    @Test func aBackgroundUploadEndsDoneNotSyncing() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(1)]])
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 1, sleep: 0, workouts: 0, daysTouched: ["2026-10-20"])
        let env = AppEnvironment.test(api: api, health: health)
        let sync = SyncService(env: env)
        let c = SyncCoordinator(steps: LiveSyncSteps(state: AppState(env: env), sync: sync), clock: env.clock,
                                inBackground: true)
        _ = await c.run(.healthKit)
        #expect(sync.phase == .done && !sync.isSyncing)
    }

    @Test func theBacklogEstimateNeedsAnAccountAndFallsBackWhenUnmeasured() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate), .sleep], pages: [:],
                                     recent: [.sleep: [samples(1)]])
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 1, sleep: 0, workouts: 0, daysTouched: ["2026-10-20"])
        let env = AppEnvironment.test(api: api, health: health)
        let sync = SyncService(env: env)
        _ = try? await sync.upload() // the first-score window: a backlog, nothing measured yet
        #expect(sync.hasBacklog)
        // Not 0: both streams still to backfill, unmeasured, so the task waits for power.
        #expect((sync.backlogBytes ?? 0) > BackgroundWork.backfillPowerThreshold)
        await env.auth.signOut()
        #expect(sync.backlogBytes == nil)
    }

    @Test func anExpiredBackfillCancelsTheLiveUpload() async {
        let clock = TestClock()
        let health = MockHealthStore(streams: [.quantity(.heartRate)],
                                     pages: [.quantity(.heartRate): [samples(1), samples(1)]])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .sleep)
        let api = MockPlatformAPI()
        api.beforeSync = { try? await clock.sleep(for: .seconds(20)) }
        let env = AppEnvironment.test(api: api, health: health, clock: clock)
        let sync = SyncService(env: env)
        let c = SyncCoordinator(steps: LiveSyncSteps(state: AppState(env: env), sync: sync), clock: clock,
                                inBackground: true)
        let task = FakeProcessingTask()
        var scheduled: [Int] = []
        let run = Task {
            await BackgroundWork.runBackfill(task, coordinator: c, backlogBytes: { 1 }) { scheduled.append($0) }
        }
        #expect(await eventually { clock.pendingSleeps == 1 && task.expirationHandler != nil })
        task.expirationHandler?()
        await run.value
        #expect(task.completed == false && scheduled == [1])
        #expect(api.count("sync") == 1) // the second page never went up
    }
}

/// A `BGProcessingTask` stand-in.
@MainActor
final class FakeProcessingTask: BackgroundTaskHandle {
    var expirationHandler: (() -> Void)?
    private(set) var completed: Bool?
    func setTaskCompleted(success: Bool) { completed = success }
}

@Suite("Sync: the server's scoring state")
@MainActor
struct SyncScoringStateTests {
    @Test func theStatusIsKeptAndAGateGoesToOnboarding() async throws {
        let api = MockPlatformAPI()
        api.accountConsent = nil // the mock's gate: consent
        api.pendingDays = ["2026-10-21"]
        let env = AppEnvironment.test(api: api)
        let state = AppState(env: env)
        let status = APIStatus()
        let steps = LiveSyncSteps(state: state, sync: SyncService(env: env), apiStatus: status)

        let answer = try await steps.syncStatus()

        #expect(state.syncStatus == answer && answer.pendingDays == ["2026-10-21"])
        #expect(status.gates == [.consentRequired] && !status.inviteBlocked)
    }

    @Test func theOperatorsResyncRequestMakesTheNextUploadAFullOne() async throws {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(2)]])
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, health: health)
        let sync = SyncService(env: env)
        await sync.syncNow()
        #expect(health.resets == 0)

        sync.fullResyncRequested(at: env.clock.now().addingTimeInterval(60))
        sync.fullResyncRequested(at: env.clock.now().addingTimeInterval(120)) // asked again: still one
        await sync.syncNow()

        #expect(health.resets == 1 && api.count("sync") == 2) // the window again
        #expect(!sync.engineState.fullResyncRequested && sync.engineState.lastFullResyncAt != nil)
        sync.fullResyncRequested(at: env.clock.now().addingTimeInterval(-60)) // older than that re-sync
        #expect(!sync.engineState.fullResyncRequested)
    }

    @Test func theUploadsScoringIsMerged() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)],
                                     pages: [.quantity(.heartRate): [samples(1), samples(1)]])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .sleep)
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 1, sleep: 0, workouts: 0, daysTouched: ["2026-10-20"],
                                        scoring: SyncScoring(queuedDays: ["2026-10-20"], expectedWithinSec: 25))
        let sync = SyncService(env: .test(api: api, health: health))

        await sync.syncNow()

        #expect(sync.lastScoring == SyncScoring(queuedDays: ["2026-10-20"], expectedWithinSec: 25))
    }

    @Test func theLaunchChecksResyncRequestReachesTheSync() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(1)]])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .sleep) // synced before
        let api = MockPlatformAPI()
        api.resyncRequestedAt = Date(timeIntervalSince1970: 1_792_500_000)
        let env = AppEnvironment.test(api: api, health: health)
        let sync = SyncService(env: env)
        let onboarding = OnboardingCoordinator(state: AppState(env: env), apiStatus: APIStatus()) {}
        onboarding.statusReceived = { sync.receive($0) }

        await onboarding.check() // the launch's GET /v1/me/sync, no scoring wait involved
        await sync.syncNow()

        #expect(health.resets == 1) // the next upload was a full re-sync
    }

    @Test func resyncRequestsAreComparedAsTheServerSentThem() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [:])
        let clock = TestClock(now: Date(timeIntervalSince1970: 2_000_000_000)) // the phone runs far ahead
        let sync = SyncService(env: .test(health: health, clock: clock))
        let request = Date(timeIntervalSince1970: 1_792_500_000)

        sync.fullResyncRequested(at: request)
        await sync.syncNow()
        #expect(health.resets == 1) // honoured although "older" than the phone's clock
        sync.fullResyncRequested(at: request) // the same request again
        await sync.syncNow()
        #expect(health.resets == 1)
        sync.fullResyncRequested(at: request.addingTimeInterval(60)) // a new one
        await sync.syncNow()
        #expect(health.resets == 2)
    }
}

@Suite("Sync: gzip")
@MainActor
struct SyncGzipTests {
    @Test func gzipRoundTripsAndShrinksASyncPage() throws {
        let page = SyncRequest(deviceId: UUID(), deviceName: "iPhone", appVersion: "1.0.0 (1)", osVersion: "iOS 27.1",
                               samples: samples(5_000).samples, sleep: [], workouts: [])
        let json = try APIClient.jsonEncoder.encode(page)
        let zipped = try Gzip.compress(json)
        #expect(zipped.prefix(2) == Data([0x1F, 0x8B])) // a gzip header
        #expect(try Gzip.decompress(zipped) == json)
        #expect(zipped.count * 8 < json.count) // the repeated keys shrink well
        #expect(try Gzip.decompress(Gzip.compress(Data())) == Data())
    }

    @Test func pagesGoUpGzippedOnlyWhenTheFlagSaysSo() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(3)]])
        let api = MockPlatformAPI()
        await SyncService(env: .test(api: api, health: health)).syncNow()
        #expect(api.syncEncodings == [nil])

        let gzipHealth = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(3)]])
        let gzipAPI = MockPlatformAPI()
        await SyncService(env: .test(api: gzipAPI, health: gzipHealth, flags: [.syncGzip: true])).syncNow()
        #expect(gzipAPI.syncEncodings == ["gzip"])
        #expect(gzipAPI.syncRequests.first?.samples.count == 3) // the platform reads the same page
    }

    @Test func uploadedBytesCountTheWireAndStreamsTheJSON() async throws {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(500)]])
        let api = MockPlatformAPI()
        let sync = SyncService(env: .test(api: api, health: health, flags: [.syncGzip: true]))
        await sync.syncNow()
        let state = sync.engineState
        let json = try #require(state.streams["heart_rate"]?.bytes)
        #expect(state.bytesUploaded == api.syncBodySizes.reduce(0, +)) // the gzipped body
        #expect(state.bytesUploaded * 4 < json) // the savings show

        let plainHealth = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [samples(500)]])
        let plainAPI = MockPlatformAPI()
        plainAPI.refusesGzip = true
        let plain = SyncService(env: .test(api: plainAPI, health: plainHealth, flags: [.syncGzip: true]))
        await plain.syncNow()
        // The fallback counts the plain body once, not the refused gzipped one.
        #expect(plain.engineState.bytesUploaded == plainAPI.syncBodySizes.reduce(0, +))
        #expect(plain.engineState.bytesUploaded == plain.engineState.streams["heart_rate"]?.bytes)
    }

    @Test func aRefusalFallsBackToPlainJSONForTheRun() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)],
                                     pages: [.quantity(.heartRate): [samples(2), samples(2)]])
        let api = MockPlatformAPI()
        api.refusesGzip = true
        let sync = SyncService(env: .test(api: api, health: health, flags: [.syncGzip: true]))
        await sync.syncNow()
        #expect(api.syncEncodings == ["gzip", nil, nil]) // the page again, plain, then plain
        #expect(sync.lastError == nil && health.committed.count == 2)
    }
}

@Suite("Sync engine: what the import card counts")
@MainActor
struct SyncEngineImportCountTests {
    @Test func theRecentWindowAndTheBackfillAreCountedOnceEach() async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [samples(5), samples(5)]],
                                     recent: [.quantity(.heartRate): [samples(4)]])
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 1, sleep: 0, workouts: 0, daysTouched: ["2026-10-21"])
        let sync = SyncService(env: .test(api: api, health: health))

        _ = try await sync.upload() // the recent window
        #expect(sync.engineState.streams["heart_rate"]?.recentRecords == 4)
        #expect(sync.engineState.streams["heart_rate"]?.sent == 4)

        _ = try await sync.upload() // the backfill sends those again, among the rest
        let hr = try #require(sync.engineState.streams["heart_rate"])
        #expect(hr.records == 10 && hr.sent == 10) // the larger, not 14
        let expected = Set(samples(5).samples.map { DayFormat.string(from: $0.start) }) // local days
        #expect(hr.days == expected)
        #expect(hr.lastUploadAt != nil)
        #expect(sync.engineState.coveredDays == expected)
    }

    @Test func daysAreFormattedPerDayAndCoverEveryRecord() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date(timeIntervalSince1970: 1_792_300_000))
        let dates = (0..<3 * 24).map { start.addingTimeInterval(Double($0) * 3_600) }.shuffled() + [start]
        #expect(SyncEngine.days(of: dates).count == 3)
        #expect(SyncEngine.days(of: []).isEmpty)
    }

    @Test func coverageIsKeptForTheNewestDaysOnly() async {
        let t = Date(timeIntervalSince1970: 1_792_300_000)
        let spread = HealthDelta(samples: (0..<200).map {
            Sample(type: .heartRate, start: t.addingTimeInterval(-Double($0) * 86_400), end: t, value: 60, unit: "bpm",
                   source: "Garmin")
        })
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [spread]])
        let sync = SyncService(env: .test(health: health))
        await sync.syncNow()
        let days = sync.engineState.streams["heart_rate"]?.days ?? []
        #expect(days.count == SyncEngineState.StreamProgress.maxDays)
        #expect(days.contains(DayFormat.string(from: t)))
    }

    @Test func syncingTheLastThreeDaysAgainReadsTheWindowThenGoesOn() async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [samples(3)]],
                                     recent: [.quantity(.heartRate): [samples(2)]])
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 3, sleep: 0, workouts: 0, daysTouched: ["2026-10-19"])
        let sync = SyncService(env: .test(api: api, health: health))
        _ = try await sync.upload()
        _ = try await sync.upload()
        #expect(sync.engineState.backfillDone)
        let reads = health.recentReads

        sync.resendRecent()
        #expect(sync.engineState.recentRequested && !sync.engineState.recentDone)
        _ = try await sync.upload()

        #expect(health.recentReads == reads + 1) // the window again, though anchors exist
        #expect(sync.engineState.recentDone && !sync.engineState.recentRequested)
        #expect(sync.engineState.backfillDone) // not an import again
        #expect(sync.engineState.phase == .incremental)
    }

    @Test func aStateFromAnOlderBuildDecodesWithTheNewFields() throws {
        let old = #"{"phase":"backfill","streams":{"sleep":{"records":12,"bytes":3000,"backfilled":false,"lastAccepted":12}}}"#
        let state = try JSONDecoder().decode(SyncEngineState.self, from: Data(old.utf8))
        let sleep = try #require(state.streams["sleep"])
        #expect(sleep.records == 12 && sleep.recentRecords == 0 && sleep.days.isEmpty && sleep.lastUploadAt == nil)
        #expect(!state.recentRequested)
    }

    @Test func theRunReportsWhatItIsDoingAndClearsItAfter() async {
        let health = MockHealthStore(streams: [.sleep], pages: [.sleep: [samples(2)]])
        let api = MockPlatformAPI()
        let sync = SyncService(env: .test(api: api, health: health))
        let seen = Counter()
        api.beforeSync = { @MainActor in
            if case .uploading(.sleep, records: 2)? = sync.activity { seen.add() }
        }
        await sync.syncNow()
        #expect(seen.value == 1)
        #expect(sync.activity == nil && sync.progress.isEmpty)
        #expect(SyncActivity.reading(.sleep).text == String(localized: "Syncing · \(HealthStream.sleep.displayName)"))
    }
}

@Suite("Apple Health: last night and the newest record")
struct RawHealthTests {
    private let t = Date(timeIntervalSince1970: 1_792_400_000)

    private func segment(_ from: Double, _ to: Double, _ stage: SleepStage, _ source: String) -> SleepSegment {
        SleepSegment(start: t.addingTimeInterval(from * 60), end: t.addingTimeInterval(to * 60), stage: stage, source: source)
    }

    @Test func theNightIsTheSourceWithTheMostSleep() throws {
        let night = try #require(RawNight.from([
            segment(0, 20, .inBed, "Garmin Connect"),       // in bed: not asleep, but the bedtime
            segment(20, 200, .core, "Garmin Connect"),
            segment(200, 210, .awake, "Garmin Connect"),
            segment(210, 450, .deep, "Garmin Connect"),
            segment(30, 300, .asleep, "iPhone"),
        ]))
        #expect(night.source == "Garmin Connect")
        #expect(night.asleepMin == 180 + 240)
        #expect(night.bedtime == t && night.wake == t.addingTimeInterval(450 * 60))
        #expect(RawNight.from([segment(0, 30, .inBed, "iPhone")]) == nil)
        #expect(RawNight.from([]) == nil)
    }

    @Test func theNightWindowStartsTheEveningBefore() {
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 7, minute: 0, second: 0, of: t)!
        let window = RawNight.window(before: morning)
        #expect(cal.component(.hour, from: window) == 18)
        #expect(morning.timeIntervalSince(window) == 13 * 3_600)
    }

    @Test func anAppIsToldApartFromAnAppleDevice() {
        #expect(SourceFreshness(source: "Garmin Connect", bundleID: "com.garmin.connect.mobile", newest: t).isApp)
        #expect(!SourceFreshness(source: "Apple Watch", bundleID: "com.apple.health.4B1C", newest: t).isApp)
    }

    @Test func eachSourceCountsItsNewerOfHeartRateAndSleep() {
        let garminHR = SourceFreshness(source: "Connect", bundleID: "com.garmin.connect.mobile", newest: t)
        let garminSleep = SourceFreshness(source: "Connect", bundleID: "com.garmin.connect.mobile", newest: t.addingTimeInterval(3_600))
        let watchHR = SourceFreshness(source: "Tim's Apple Watch", bundleID: "com.apple.health.4B1C", newest: t.addingTimeInterval(600),
                                      deviceModel: "Watch")
        let watchSleep = SourceFreshness(source: "Tim's Apple Watch", bundleID: "com.apple.health.4B1C", newest: t)
        // The iPhone writes no heart rate, only its sleep schedule's in-bed time.
        let phoneSleep = SourceFreshness(source: "Tim's iPhone", bundleID: "com.apple.health.3F0A", newest: t.addingTimeInterval(7_200),
                                         deviceModel: "iPhone")
        let merged = SourceFreshness.newestPerSource([[garminHR, watchHR], [garminSleep, watchSleep, phoneSleep]])
        #expect(merged.map(\.source) == ["Connect", "Tim's Apple Watch", "Tim's iPhone"])
        #expect(merged[0].newest == garminSleep.newest) // sleep is newer: an app that only wrote the night counts
        #expect(merged[1].newest == watchHR.newest && merged[1].deviceModel == "Watch") // the model from either
        #expect(merged[2].isPhone && !merged[1].isPhone && !merged[0].isPhone)
        // Sources without a bundle ID stay apart by name.
        let a = SourceFreshness(source: "A", bundleID: nil, newest: t), b = SourceFreshness(source: "B", bundleID: nil, newest: t)
        #expect(SourceFreshness.newestPerSource([[a], [b]]).count == 2)
    }

    @Test func theDeviceModelComesFromTheDeviceOrTheProductType() {
        #expect(SourceRef.deviceModel(model: "Watch", productType: "Watch7,1") == "Watch")
        #expect(SourceRef.deviceModel(model: nil, productType: "Watch7,1") == "Watch")
        #expect(SourceRef.deviceModel(model: "", productType: "iPhone17,1") == "iPhone")
        #expect(SourceRef.deviceModel(model: nil, productType: nil) == nil)
        #expect(SourceRef.deviceModel(model: nil, productType: "7,1") == nil)
        #expect(SourceFreshness(source: "x", bundleID: "com.apple.health.1", newest: t, deviceModel: "iPhone").ref
                == SourceRef(name: "x", bundleID: "com.apple.health.1", deviceModel: "iPhone"))
    }

    @Test func lastNightKeepsItsSourcesBundleID() throws {
        func segment(_ from: Double, _ to: Double, _ source: String, _ bundle: String?) -> SleepSegment {
            SleepSegment(start: t.addingTimeInterval(from * 60), end: t.addingTimeInterval(to * 60), stage: .core, source: source,
                         sourceBundleId: bundle)
        }
        let night = try #require(RawNight.from([segment(0, 400, "Connect", "com.garmin.connect.mobile"),
                                                segment(10, 100, "Tim's iPhone", "com.apple.health.3F0A")]))
        #expect(night.source == "Connect" && night.bundleID == "com.garmin.connect.mobile")
        #expect(night.ref == SourceRef(name: "Connect", bundleID: "com.garmin.connect.mobile", deviceModel: nil))
    }
}

// MARK: - Check sync

/// design.md §4.4's table on the Garmin-like store and its variants, the wordings of §4.5, and the model: reads off
/// the main thread, only when the user asks, and only codes kept.
@Suite("Check sync")
@MainActor
struct SyncCheckTests {
    /// 09:12 on 2026-10-19: last night began yesterday at 18:00.
    private let now = Calendar.current.date(bySettingHour: 9, minute: 12, second: 0,
                                            of: Date(timeIntervalSince1970: 1_792_400_000)) ?? .now
    private let catalog = TrackerCatalog.bundled
    private let text = TrackerCheckText()

    private func at(_ hour: Int, _ minute: Int, daysAgo: Int = 0) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func classify(_ id: String, _ store: MockHealthStore, alongside: [String] = []) throws -> TrackerCheck {
        let tracker = try #require(catalog.tracker(id))
        return TrackerCheckRules.classify(tracker, samples: store.samples, visible: store.visible, now: now,
                                          catalog: catalog, alongside: alongside.compactMap(catalog.tracker))
    }

    private func rows(_ check: TrackerCheck) -> [TrackerSignal: SignalCheck] {
        Dictionary(uniqueKeysWithValues: check.rows.map { ($0.signal, $0.check) })
    }

    /// What a device check saw Garmin Connect write (catalog 2026-10-22.3): no HRV, breathing rate or SpO₂.
    private static let notGarmin: [TrackerSignal] = [.hrv, .respiratoryRate, .spo2]

    // MARK: the table

    @Test func garminSendsWhatTheDeviceCheckSawAndHRVIsAnExpectedGap() throws {
        let check = try classify("garmin", .garminLike(now: now))
        let r = rows(check)
        #expect(check.rows.map(\.signal) == TrackerSignal.allCases)
        #expect(r[.heartRate] == .arrived(now.addingTimeInterval(-1_200)))
        // One resting heart rate a day, stamped 00:00: last night's.
        #expect(r[.restingHR] == .arrived(at(0, 0)))
        #expect(r[.sleep] == .arrived(at(6, 48)) && r[.sleepStages] == .arrived(at(6, 48)))
        #expect(r[.steps] == .arrived(now.addingTimeInterval(-3_600)))
        #expect(r[.workouts] == .arrived(at(19, 2, daysAgo: 1)))
        for signal in Self.notGarmin { #expect(r[signal] == .notShared, "\(signal)") }
        #expect(check.overall == .ok && check.app == "Garmin Connect")
        #expect(check.expected == 6 && check.arriving == 6 && check.needsFix == 0 && check.drift.isEmpty)
        #expect(text.result(.notShared, signal: .hrv, app: check.app, now: now)
            == String(localized: "Not shared by \("Garmin Connect")"))
        #expect(text.summary(expected: 6, arriving: 6, needsFix: 0)
            == String(localized: "\(6) of \(6) expected signals are arriving."))
    }

    /// Resting heart rate: an expected gap from a tracker that writes none (Oura, per its docs), an unexpected one
    /// from Garmin Connect, which does.
    @Test func restingHeartRateIsExpectedOnlyWhereTheTrackerSharesIt() throws {
        let ring = try classify("oura", .ouraLike(now: now))
        #expect(rows(ring)[.restingHR] == .notShared && rows(ring)[.hrv] == .notShared && rows(ring)[.spo2] == .notShared)
        #expect(rows(ring)[.respiratoryRate] == .arrived(at(6, 40)) && rows(ring)[.sleepStages] == .arrived(at(6, 40)))
        #expect(ring.overall == .ok && ring.expected == 6 && ring.arriving == 6)
        let garmin = try classify("garmin", .garminLike(now: now, restingHR: false))
        #expect(rows(garmin)[.restingHR] == .missing(visible: false) && garmin.overall == .needsFix)
    }

    @Test func aNightThatHasNotReachedAppleHealthIsNotLastNight() throws {
        let check = try classify("garmin", .garminLike(now: now, nightSynced: false))
        let r = rows(check)
        #expect(r[.sleep] == .notLastNight(lastSeen: at(6, 48, daysAgo: 1)))
        #expect(r[.sleepStages] == .notLastNight(lastSeen: at(6, 48, daysAgo: 1)))
        #expect(r[.restingHR] == .notLastNight(lastSeen: at(0, 0, daysAgo: 1)))
        // Continuous signals from last evening still arrived.
        #expect(r[.heartRate] == .arrived(at(23, 24, daysAgo: 1)))
        #expect(check.overall == .nightMissing && check.expected == 6 && check.arriving == 3 && check.needsFix == 0)
    }

    @Test func nothingFromTheTrackerIn48HoursIsSilent() throws {
        let check = try classify("garmin", .garminLike(now: now, silent: true))
        let r = rows(check)
        #expect(check.overall == .silent && check.arriving == 0)
        #expect(r[.heartRate] == .missing(visible: true) && r[.hrv] == .notShared && r[.workouts] == .notSeenYet)
        #expect(text.silent(check)
            == String(localized: "No data from \("Garmin Connect") yet. Open \("Garmin Connect") and let it sync, then tap Check again."))
    }

    @Test func anUnexpectedGapSaysWhatRYFTCanKnow() throws {
        let store = MockHealthStore.garminLike(now: now, sleepOff: true)
        var check = try classify("garmin", store)
        #expect(rows(check)[.sleep] == .missing(visible: true))
        #expect(rows(check)[.sleepStages] == .notSeenYet) // nothing to judge without a night
        #expect(check.overall == .needsFix && check.needsFix == 1 && check.expected == 5 && check.arriving == 4)
        #expect(text.fixLead(check)
            == String(localized: "RYFT can read \("sleep"), but none came from \("Garmin Connect") in the last 2 days."))
        // Nobody's sleep visible: RYFT can't tell "not allowed to read" from "not written", so it says both.
        store.visible.remove(.sleep)
        check = try classify("garmin", store)
        #expect(rows(check)[.sleep] == .missing(visible: false))
        #expect(text.fixLead(check)
            // swiftlint:disable:next line_length
            == String(localized: "RYFT doesn't see any \("sleep") in Apple Health. Either RYFT isn't allowed to read it, or \("Garmin Connect") isn't writing it."))
        #expect(SignalCheck.missing(visible: false).code == "missing_unknown" && SignalCheck.missing(visible: true).code == "missing_visible")
        // Several gaps: one sentence, one cause.
        store.samples.removeAll { $0.source == .mockGarmin && $0.stream == .quantity(.steps) }
        check = try classify("garmin", store)
        #expect(check.needsFix == 2)
        #expect(text.fixLead(check)
            == String(localized: "Several signals should arrive and don't. The cause is usually one permission in \("Garmin Connect")."))
        // The words never claim a refusal.
        for words in [text.fixLead(check), text.spoken(.missing(visible: false), signal: .sleep, app: "Garmin Connect", now: now)] {
            #expect(!words.lowercased().contains("denied"))
        }
    }

    @Test func dataBeatsTheCatalog() throws {
        let store = MockHealthStore.garminLike(now: now)
        store.samples.append(SourceSample(stream: .quantity(.hrvSDNN), source: .mockGarmin, newest: at(3, 0)))
        let check = try classify("garmin", store)
        #expect(rows(check)[.hrv] == .arrived(at(3, 0)) && check.drift == [.hrv])
        #expect(check.expected == 7 && check.arriving == 7)
    }

    @Test func aSignalFromAnotherSelectedTrackerIsNoGap() throws {
        let oura = SourceRef(name: "Oura", bundleID: "com.ouraring.oura", deviceModel: nil)
        let store = MockHealthStore.garminLike(now: now, sleepOff: true)
        store.samples.append(SourceSample(stream: .sleep, source: oura, newest: at(6, 40), hasStages: true))
        let garmin = try classify("garmin", store, alongside: ["garmin", "oura"])
        #expect(rows(garmin)[.sleep] == .elsewhere(app: "Oura") && garmin.overall == .ok && garmin.needsFix == 0)
        #expect(text.result(.elsewhere(app: "Oura"), signal: .sleep, app: "Garmin Connect", now: now)
            == String(localized: "from \("Oura") instead"))
        let ring = try classify("oura", store, alongside: ["garmin", "oura"])
        #expect(rows(ring)[.sleep] == .arrived(at(6, 40)) && rows(ring)[.sleepStages] == .arrived(at(6, 40)))
        #expect(rows(ring)[.heartRate] == .elsewhere(app: "Garmin Connect"))
        // Alone, the same gap is one to fix.
        #expect(rows(try classify("garmin", store))[.sleep] == .missing(visible: true))
    }

    @Test func otherListsOnlyAppsTheCatalogDoesNotKnow() throws {
        let band = SourceRef(name: "Band", bundleID: "com.example.band", deviceModel: nil)
        let ryft = SourceRef(name: "RYFT", bundleID: Bundle.main.bundleIdentifier, deviceModel: nil)
        let store = MockHealthStore.garminLike(now: now)
        store.samples += [SourceSample(stream: .quantity(.heartRate), source: band, newest: at(8, 0)),
                          SourceSample(stream: .quantity(.steps), source: band, newest: at(8, 30)),
                          SourceSample(stream: .workouts, source: ryft, newest: at(7, 0))]
        let check = try classify("other", store)
        #expect(check.overall == .unknownTracker && check.app == nil)
        // Garmin, the iPhone and RYFT's own workout aren't "other".
        #expect(check.rows == [.init(signal: .heartRate, check: .arrived(at(8, 0))),
                               .init(signal: .steps, check: .arrived(at(8, 30)))])
        let nothing = try classify("other", .garminLike(now: now))
        #expect(nothing.rows.isEmpty)
        #expect(text.silent(nothing)
            == String(localized: "No data from your tracker's app yet. Open it and let it sync, then tap Check again."))
    }

    @Test func aTrackerThatWritesNothingIsNotChecked() throws {
        let check = try classify("samsung_galaxy_watch", .garminLike(now: now))
        #expect(check.overall == .cantRead && check.rows.isEmpty && check.expected == 0)
        #expect(TrackerCheckRules.waiting(try #require(catalog.tracker("samsung_galaxy_watch"))).rows.isEmpty)
    }

    @Test func appleDevicesAreToldApartByTheirDevice() throws {
        let store = MockHealthStore.appleWatchLike(now: now)
        let watch = try classify("apple_watch", store)
        #expect(watch.rows.allSatisfy { $0.check.isArrived }, "\(watch.rows)")
        #expect(watch.overall == .ok && watch.expected == 9 && watch.arriving == 9)
        #expect(text.result(rows(watch)[.sleep] ?? .waiting, signal: .sleep, app: nil, now: now)
            == String(localized: "last night"))
        #expect(text.result(.arrived(at(7, 42)), signal: .heartRate, app: nil, now: now)
            == String(localized: "last \(Fmt.time(at(7, 42)))"))
        let phone = rows(try classify("iphone", store))
        #expect(phone[.steps] == .arrived(now.addingTimeInterval(-600)) && phone[.hrv] == .notShared)
        #expect(phone[.heartRate] == .notSeenYet) // partial: AirPods only
        let phoneCheck = try classify("iphone", store)
        #expect(watch.app == "Apple Watch" && phoneCheck.app == "iPhone")
        // Without a device model the shared prefix matches neither: no verdict for the watch (nothing claims a
        // fault, design.md §10), its data under Other.
        let anonymous = SourceRef(name: "Watch", bundleID: "com.apple.health.81E4", deviceModel: nil)
        let bare = MockHealthStore()
        bare.samples = [SourceSample(stream: .quantity(.heartRate), source: anonymous, newest: at(8, 0))]
        bare.visible = [.quantity(.heartRate)]
        let unknownWatch = try classify("apple_watch", bare)
        #expect(unknownWatch.overall == .unidentified && unknownWatch.expected == 0 && unknownWatch.needsFix == 0)
        #expect(unknownWatch.rows.allSatisfy { $0.check == .notSeenYet })
        #expect(try classify("other", bare).rows.map(\.signal) == [.heartRate])
        // Silent Apple devices are worn or carried, never "opened".
        let silentWatch = try classify("apple_watch", MockHealthStore())
        let silentPhone = try classify("iphone", MockHealthStore())
        #expect(silentWatch.overall == .silent && silentPhone.overall == .silent)
        #expect(text.silent(silentWatch) == String(localized: """
            No data from your Apple Watch yet. Wear it and keep it near your iPhone so it syncs, then tap Check again.
            """))
        #expect(text.silent(silentPhone) == String(localized: """
            Nothing from this iPhone in the last 2 days. Carry it with you for a while, then tap Check again.
            """))
        #expect(![text.silent(silentWatch), text.silent(silentPhone)].contains { $0.contains(String(localized: "Open \("Watch")")) })
    }

    @Test func anAppleDeviceThatDoesNotSayWhichClaimsNothing() async {
        let bare = MockHealthStore()
        bare.samples = [SourceSample(stream: .quantity(.heartRate),
                                     source: SourceRef(name: "Watch", bundleID: "com.apple.health.81E4", deviceModel: nil),
                                     newest: at(8, 0))]
        bare.visible = [.quantity(.heartRate)]
        let (model, _) = model(bare, trackers: ["apple_watch"])
        await model.run()
        #expect(model.checks.first?.overall == .unidentified && !model.showsPermissionCard)
    }

    @Test func stagesThatShouldComeAndDoNotAreAGap() throws {
        let store = MockHealthStore.appleWatchLike(now: now)
        store.samples = store.samples.map { s in
            s.stream == .sleep ? SourceSample(stream: .sleep, source: s.source, newest: s.newest, hasStages: false) : s
        }
        let check = try classify("apple_watch", store)
        #expect(rows(check)[.sleep] == .arrived(at(6, 52)) && rows(check)[.sleepStages] == .missing(visible: true))
        #expect(check.overall == .needsFix)
    }

    @Test func withoutASelectionTheTrackersSeenAreChecked() {
        #expect(TrackerCheckRules.seen(MockHealthStore.garminLike(now: now).samples, catalog: catalog, now: now)
            .map(\.id) == ["garmin"])
        #expect(TrackerCheckRules.seen(MockHealthStore.garminLike(now: now, silent: true).samples, catalog: catalog, now: now)
            .map(\.id) == ["iphone"])
        #expect(TrackerCheckRules.seen([], catalog: catalog, now: now).map(\.id) == ["other"])
    }

    /// From midnight until 08:00 the night is still being written: the night before is "last night". Only a night the
    /// tracker promises can be missing, never the iPhone's or a partly shared signal.
    @Test(arguments: [(-1, 23, 30, false), (0, 0, 30, false), (0, 5, 0, false), (0, 8, 0, true)])
    func lastNightBeforeAndAfterWaking(daysAhead: Int, hour: Int, minute: Int, missed: Bool) throws {
        let day = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now // the morning after `now`'s day
        let clock = Calendar.current.date(byAdding: .day, value: daysAhead, to: day) ?? day
        let at = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: clock) ?? clock
        let wake = self.at(6, 48), evening = self.at(23, 20)
        let store = MockHealthStore()
        store.samples = [SourceSample(stream: .sleep, source: .mockGarmin, newest: wake, hasStages: true),
                         SourceSample(stream: .quantity(.restingHR), source: .mockGarmin, newest: self.at(0, 0)),
                         SourceSample(stream: .quantity(.heartRate), source: .mockGarmin, newest: evening),
                         SourceSample(stream: .quantity(.steps), source: .mockGarmin, newest: evening),
                         SourceSample(stream: .sleep, source: .mockPhone, newest: self.at(6, 30), hasStages: false),
                         SourceSample(stream: .quantity(.steps), source: .mockPhone, newest: evening),
                         SourceSample(stream: .quantity(.spo2), source: .mockWatch, newest: self.at(4, 10))]
        store.samples += [TrackerSignal.heartRate, .hrv, .restingHR, .respiratoryRate, .steps].compactMap(\.stream)
            .map { SourceSample(stream: $0, source: .mockWatch, newest: at.addingTimeInterval(-600)) }
        store.samples.append(SourceSample(stream: .sleep, source: .mockWatch, newest: at.addingTimeInterval(-600), hasStages: true))
        store.visible = Set(TrackerCheckRules.streams)
        func check(_ id: String) throws -> TrackerCheck {
            TrackerCheckRules.classify(try #require(catalog.tracker(id)), samples: store.samples, visible: store.visible,
                                       now: at, catalog: catalog)
        }
        let garmin = try check("garmin")
        #expect(rows(garmin)[.sleep] == (missed ? .notLastNight(lastSeen: wake) : .arrived(wake)), "\(at)")
        #expect(rows(garmin)[.restingHR] == (missed ? .notLastNight(lastSeen: self.at(0, 0)) : .arrived(self.at(0, 0))), "\(at)")
        #expect(garmin.overall == (missed ? .nightMissing : .ok), "\(at)")
        #expect((text.result(.arrived(wake), signal: .sleep, app: nil, now: at) == String(localized: "last night")) == !missed)
        // The iPhone's in-bed night and the watch's partly shared SpO₂ never make a night missing.
        #expect(try check("iphone").overall == .ok && rows(try check("iphone"))[.sleep] == .arrived(self.at(6, 30)))
        #expect(rows(try check("apple_watch"))[.spo2] == .arrived(self.at(4, 10)))
    }

    @Test func theCountsAgreeInNumberAndTheSilentAreSpokenAsSuch() throws {
        // Plurals (the catalog's substitutions): English only, the test host's language.
        if Bundle.main.preferredLocalizations.first == "en" {
            #expect(text.summary(expected: 1, arriving: 1, needsFix: 0) == "1 of 1 expected signal is arriving.")
            #expect(text.summary(expected: 4, arriving: 3, needsFix: 1) == "3 of 4 expected signals are arriving. 1 needs a fix.")
            #expect(text.summary(expected: 4, arriving: 2, needsFix: 2) == "2 of 4 expected signals are arriving. 2 need a fix.")
        }
        let silent = try classify("garmin", .garminLike(now: now, silent: true))
        let fine = try classify("apple_watch", .appleWatchLike(now: now))
        #expect(text.announcement([silent]) == String(localized: "Check finished.") + " " + text.silent(silent))
        #expect(text.announcement([fine, silent]) == [String(localized: "Check finished."),
                                                     text.summary(expected: 9, arriving: 9, needsFix: 0),
                                                     text.silent(silent)].joined(separator: " "))
    }

    /// The live store's proof of read access, as a table: RYFT's own record proves nothing, so then the type's
    /// sources decide, and they're asked only then.
    @Test func ryftsOwnRecordIsNoProofOfReadAccess() async throws {
        let own = try #require(Bundle.main.bundleIdentifier)
        let cases: [(first: String?, sources: [String], readable: Bool, asks: Bool)] = [
            (nil, [], false, false),
            ("com.garmin.connect.mobile", [], true, false),
            (own, [own], false, true),
            (own, [own, "com.garmin.connect.mobile"], true, true),
            (own, [own + ".widgets"], false, true),
        ]
        for c in cases {
            var asked = false
            let readable = await HealthProbe.readable(firstRecordFrom: c.first) {
                asked = true
                return c.sources
            }
            #expect(readable == c.readable && asked == c.asks, "\(c)")
        }
    }

    @Test func stagesCountOnlyFromTheNewestNight() {
        func segment(_ from: Double, _ to: Double, _ stage: SleepStage) -> SleepSegment {
            SleepSegment(start: at(0, 0).addingTimeInterval(from * 3_600), end: at(0, 0).addingTimeInterval(to * 3_600),
                         stage: stage, source: "Connect")
        }
        #expect(HealthProbe.newestNightHasStages([segment(-1, 0, .inBed), segment(0, 3, .core), segment(3, 6.8, .asleep)]))
        // An awake hour inside the night keeps it one night.
        #expect(HealthProbe.newestNightHasStages([segment(-1, 2, .deep), segment(2, 3, .awake), segment(3, 6.8, .asleep)]))
        // Last night without stages; the night before had them.
        #expect(!HealthProbe.newestNightHasStages([segment(-25, -18, .deep), segment(-1, 6.8, .asleep)]))
        #expect(!HealthProbe.newestNightHasStages([]))
    }

    // MARK: the model

    private func model(_ store: MockHealthStore, trackers: [String] = ["garmin"]) -> (TrackerCheckModel, AppEnvironment) {
        let env = AppEnvironment.test(clock: TestClock(now: now))
        return (TrackerCheckModel(env: env, health: store, trackers: trackers), env)
    }

    @Test func theProbeReadsOffTheMainThreadAndTheCheckKeepsOnlyCodes() async throws {
        let store = MockHealthStore.garminLike(now: now, sleepOff: true)
        let (model, env) = model(store, trackers: ["garmin", "garmin", "nonsense"])
        #expect(model.trackers.map(\.id) == ["garmin"])
        #expect(model.checks.first?.rows.allSatisfy { $0.check == .waiting } == true)
        #expect(store.probeReads == 0) // nothing before the screen asks
        await model.run()
        #expect(model.phase == .done && model.checkedAt == now)
        #expect(store.probeReads == 2 && store.readsOnMainThread == 0)
        #expect(model.needsFix == 1 && model.showsPermissionCard && !model.mayNotRead)
        let record = try #require(TrackerCheckRecord.load(env))
        #expect(record.lines == [
            "checked \(DayFormat.string(from: now))",
            "garmin needs_fix heart_rate=arrived hrv=not_shared resting_hr=arrived sleep=missing_visible "
                + "sleep_stages=not_seen respiratory_rate=not_shared spo2=not_shared workouts=arrived steps=arrived",
        ])
        // Another account's check isn't this one's.
        env.persistence.saveDocument(TrackerCheckRecord(account: "someone-else", at: now, checks: model.checks),
                                     key: TrackerCheckRecord.documentKey, at: now)
        #expect(TrackerCheckRecord.load(env) == nil)
    }

    @Test func notEvenTheIPhonesStepsIsTheStrongHint() async {
        let (model, _) = model(MockHealthStore())
        await model.run()
        #expect(model.checks.first?.overall == .silent)
        #expect(model.mayNotRead && model.showsPermissionCard)
        // Something visible: no strong hint, and all as expected needs no permission card.
        let (fine, _) = self.model(.garminLike(now: now))
        await fine.run()
        #expect(!fine.mayNotRead && !fine.showsPermissionCard && fine.arriving == 6 && fine.expected == 6)
    }

    @Test func aLockedPhoneWaitsForTheUnlock() async {
        let store = MockHealthStore.garminLike(now: now)
        store.nextError = HKError(.errorDatabaseInaccessible)
        let (model, env) = model(store)
        await model.run()
        #expect(model.phase == .locked && TrackerCheckRecord.load(env) == nil)
        #expect(model.checks.first?.rows.allSatisfy { $0.check == .waiting } == true)
        await model.run()
        #expect(model.phase == .done)
    }

    @Test func withoutHealthAccessItAsksFirst() async {
        let store = MockHealthStore.garminLike(now: now)
        store.access = .notAsked
        let (model, _) = model(store)
        await model.start(stagger: false)
        #expect(model.phase == .notAsked && store.probeReads == 0)
        await model.start(stagger: false) // once per screen
        await model.requestAccess()
        #expect(store.authorizationRequests == 1 && model.phase == .done)
        let none = MockHealthStore()
        none.isAvailable = false
        let (unavailable, _) = self.model(none)
        await unavailable.run()
        #expect(unavailable.phase == .unavailable && none.probeReads == 0)
    }

    @Test func rowsResolveTopDownWhenStaggered() async {
        let clock = TestClock(now: now)
        let env = AppEnvironment.test(clock: clock)
        let model = TrackerCheckModel(env: env, health: MockHealthStore.garminLike(now: now), trackers: ["garmin"])
        let run = Task { await model.run(stagger: true) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(model.isRunning && model.checks.first?.rows.allSatisfy { $0.check == .checking } == true)
        clock.advance(by: .milliseconds(150))
        #expect(await eventually { model.checks.first?.rows.first?.check.isArrived == true })
        #expect(model.checks.first?.rows.dropFirst().allSatisfy { $0.check == .checking } == true)
        run.cancel() // leaving the screen shows the rest at once
        await run.value
        #expect(model.phase == .done && model.checks.first?.overall == .ok)
    }

    @Test func checkAgainWithoutASelectionFindsATrackerThatSyncedSince() async throws {
        let store = MockHealthStore()
        store.samples = [SourceSample(stream: .quantity(.steps), source: .mockPhone, newest: at(9, 0))]
        store.visible = [.quantity(.steps)]
        let (model, _) = model(store, trackers: [])
        await model.run()
        #expect(model.trackers.map(\.id) == ["iphone"] && model.checks.map(\.trackerID) == ["iphone"])
        // Garmin Connect is opened: its records arrive.
        store.samples += MockHealthStore.garminLike(now: now).samples.filter { $0.source == .mockGarmin }
        await model.run(stagger: false)
        #expect(model.trackers.map(\.id) == ["garmin"] && model.selection.isEmpty)
        let garmin = try #require(model.checks.first)
        #expect(garmin.trackerID == "garmin" && rows(garmin)[.heartRate] == .arrived(now.addingTimeInterval(-1_200)))
    }

    @Test func aSecondTapDoesNotStartASecondRun() async {
        let store = MockHealthStore.garminLike(now: now)
        let (model, _) = model(store)
        let first = Task { await model.run() }
        let second = Task { await model.run() }
        await first.value
        await second.value
        #expect(store.probeReads == 2 && model.phase == .done) // one run: two reads
    }

    @Test func aCheckThatOutlivesItsAccountKeepsNothing() async {
        let clock = TestClock(now: now)
        let env = AppEnvironment.test(clock: clock)
        let model = TrackerCheckModel(env: env, health: MockHealthStore.garminLike(now: now), trackers: ["garmin"])
        let run = Task { await model.run(stagger: true) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        await env.auth.signOut()
        run.cancel()
        await run.value
        #expect(model.phase == .done)
        #expect(env.persistence.document(TrackerCheckRecord.self, key: TrackerCheckRecord.documentKey) == nil)
    }

    @Test func diagnosticsLeaveOutACheckOlderThan14Days() throws {
        let env = AppEnvironment.test(clock: TestClock(now: now), flags: [.devicesSetup: true])
        let account = try #require(env.auth.accountID)
        let check = try classify("garmin", .garminLike(now: now))
        for (daysAgo, reported) in [(13.0, true), (15.0, false)] {
            let at = now.addingTimeInterval(-daysAgo * 86_400)
            env.persistence.saveDocument(TrackerCheckRecord(account: account, at: at, checks: [check]),
                                         key: TrackerCheckRecord.documentKey, at: at)
            #expect(TrackerCheckRecord.load(env) != nil)
            #expect((TrackerCheckRecord.forReport(env) != nil) == reported, "\(daysAgo) days")
        }
        // It names tracker ids: with `devices.setup` off, like `trackers`, it stays home.
        let off = AppEnvironment.test(clock: TestClock(now: now))
        off.persistence.saveDocument(TrackerCheckRecord(account: account, at: now, checks: [check]),
                                     key: TrackerCheckRecord.documentKey, at: now)
        #expect(TrackerCheckRecord.load(off) != nil && TrackerCheckRecord.forReport(off) == nil)
    }

    /// Devices & sync's rows and "Last checked" show the last check, per tracker, once there is one.
    @Test func devicesAndSyncShowsTheLastCheck() async throws {
        let env = AppEnvironment.test(clock: TestClock(now: now), flags: [.devicesSetup: true])
        let devices = DevicesViewModel(state: AppState(env: env), selection: TrackerSelectionStore(env: env))
        devices.save(["garmin", "oura"])
        devices.reloadCheck()
        let garmin = try #require(catalog.tracker("garmin")), oura = try #require(catalog.tracker("oura"))
        #expect(devices.status(of: garmin) == String(localized: "Not checked yet"))
        #expect(devices.lastCheckedText == String(localized: "Not checked yet"))
        await TrackerCheckModel(env: env, health: MockHealthStore.garminLike(now: now, sleepOff: true),
                                trackers: devices.selection.trackers).run()
        devices.reloadCheck()
        #expect(devices.status(of: garmin) == String(localized: "Needs a fix"))
        #expect(devices.status(of: oura) == String(localized: "Nothing in the last 2 days"))
        #expect(devices.lastCheckedText == String(localized: "Last checked \(SyncLine.dataTime(now, now: now))"))
        devices.selection.markLater("oura")
        #expect(devices.status(of: oura) == String(localized: "Set up later"))
    }

    /// A Debug build on the user's iPhone: a staged choice (`-RyftScreen tracker-setup`) or a launch one
    /// (`-RyftTrackers`) is shown, but Done and "Show me again later" never store it as the account's.
    @Test(arguments: [false, true])
    func aStagedOrLaunchChoiceNeverBecomesTheAccounts(launch: Bool) throws {
        let env = AppEnvironment.test(clock: TestClock(now: now), flags: [.devicesSetup: true])
        let devices = TrackerSelectionStore(env: env, launch: launch ? ["garmin", "oura"] : nil)
        if !launch { devices.stage(["garmin", "oura"]) }
        let onboarding = OnboardingCoordinator(state: AppState(env: env), apiStatus: APIStatus(), devices: devices) {}
        #expect(devices.trackers == ["garmin", "oura"] && onboarding.setupTrackers.map(\.id) == ["garmin", "oura"])
        onboarding.finishTrackerSetup(later: false)
        devices.markLater("oura")
        #expect(env.persistence.document(TrackerSelection.self, key: TrackerSelectionStore.documentKey) == nil)
        // With a stored choice, only its own trackers are marked.
        devices.set(["garmin"])
        if !launch { devices.stage(["garmin", "oura"]) }
        onboarding.finishTrackerSetup(later: true)
        let saved = try #require(env.persistence.document(TrackerSelection.self, key: TrackerSelectionStore.documentKey))
        #expect(saved.trackers == ["garmin"] && saved.later == ["garmin"] && saved.setUp.isEmpty)
        // Without a launch choice the account shows what it stored.
        if !launch {
            devices.accountChanged()
            #expect(devices.trackers == ["garmin"])
        }
    }

    @Test func ryftsOwnWorkoutsNeverCount() async throws {
        let own = SourceRef(name: "RYFT", bundleID: Bundle.main.bundleIdentifier, deviceModel: nil)
        let store = MockHealthStore()
        store.samples = [SourceSample(stream: .workouts, source: own, newest: at(7, 0)),
                         SourceSample(stream: .quantity(.heartRate), source: .mockGarmin, newest: at(8, 0))]
        let found = try await HealthProbe(health: store).run(TrackerCheckRules.streams, since: at(9, 12, daysAgo: 2))
        #expect(found.samples.map(\.source) == [.mockGarmin])
        #expect(TrackerCheckRules.seen(store.samples, catalog: catalog, now: now).map(\.id) == ["garmin"])
        // The live store's test for proof of read access: RYFT and its extensions aren't another source.
        let id = Bundle.main.bundleIdentifier
        #expect(HealthProbe.isRYFT(bundleID: id) && HealthProbe.isRYFT(bundleID: id.map { $0 + ".widgets" }))
        #expect(!HealthProbe.isRYFT(bundleID: id.map { $0 + "x" }) && !HealthProbe.isRYFT(bundleID: "com.garmin.connect.mobile"))
        #expect(!HealthProbe.isRYFT(bundleID: nil))
    }
}

// MARK: - Report a problem

/// A queue whose saves never reach the disk (a full disk).
@MainActor
private final class FailingFeedbackQueue: FeedbackQueueStore {
    func load() -> [QueuedFeedback] { [] }
    func save(_ items: [QueuedFeedback]) -> Bool { false }
}

/// Holds each message's first post (the hook sleeps on the test clock); a repeat goes straight through, so a
/// double post fails on the count instead of waiting forever.
private final class FirstPostHold: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: Set<String> = []
    func isFirst(_ message: String) -> Bool { lock.withLock { seen.insert(message).inserted } }
}

/// Answers every request: `200`, with a gate header on `/v1/gate`, a `404` on `/v1/missing`, a `429` with
/// `Retry-After: 30` on `/v1/feedback`, a `503` with `Retry-After: 5` on `/v1/busy…`, and no answer (a timeout)
/// on `/v1/timeout`. It counts what reached it per path.
private final class LateReplyURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    /// Requests that reached the network for `path`.
    static func attempts(_ path: String) -> Int { lock.withLock { counts[path] ?? 0 } }
    /// A test that's retried in the same process starts from zero again.
    static func reset(_ path: String) { lock.withLock { counts[path] = nil } }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lock.withLock { Self.counts[path, default: 0] += 1 }
        if path == "/v1/timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        var headers = ["X-Request-ID": "late-1"]
        if path == "/v1/gate" { headers["X-RYFT-Gate"] = "consent_required" }
        if path == "/v1/feedback" { headers["Retry-After"] = "30" }
        if path.hasPrefix("/v1/busy") { headers["Retry-After"] = "5" }
        let code = path == "/v1/missing" ? 404 : path == "/v1/feedback" ? 429 : path.hasPrefix("/v1/busy") ? 503 : 200
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1",
                                             headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A token after one second on the test clock: the request is on its way while the test switches accounts.
private final class SlowTokens: AccessTokenProvider, @unchecked Sendable {
    let clock: TestClock
    init(clock: TestClock) { self.clock = clock }
    func accessToken() async throws -> String {
        try? await clock.sleep(for: .seconds(1))
        return "token"
    }
    func refreshedAccessToken() async throws -> String { "token" }
    func rejectedAfterRefresh() async {}
}

@Suite("Report a problem")
@MainActor
struct ReportProblemTests {
    private let about = FeedbackAbout(appVersion: "1.0.0", build: "20261021.141128", deviceModel: "iPhone17,1",
                                      osVersion: "iOS 27.0.1", locale: "de_DE")
    private static let sync = FeedbackSync(phase: "incremental", recentDone: true, backfillDone: true,
                                           streams: [.init(id: "sleep", records: 412, days: 31,
                                                           newest: Date(timeIntervalSince1970: 1_792_600_000))])
    private static let syncText = FeedbackPayload.syncLines(sync).joined(separator: "\n")
    /// `TrackerCheckRecord.lines` of a check.
    private static let syncCheck = ["checked 2026-10-21", "garmin needs_fix heart_rate=arrived hrv=not_shared sleep=missing_visible"]

    /// Request `i` of a newest-first list (`i == 0` is the newest).
    private func request(_ i: Int, status: Int = 503, path: String = "/v1/days/2026-10-21",
                         id: String? = nil) -> APIStatus.RequestFailure {
        APIStatus.RequestFailure(date: Date(timeIntervalSince1970: 1_792_600_000 - Double(i)), method: "GET",
                                 path: path, status: status, requestID: id ?? "req-\(i)")
    }

    private func make(_ message: String = "It broke.", requests: [APIStatus.RequestFailure] = [],
                      includeDiagnostics: Bool = true, context: ReportContext? = nil) -> FeedbackPost {
        FeedbackPayload.make(message: message, category: .bug, includeDiagnostics: includeDiagnostics,
                             requests: requests, sync: Self.sync, gates: [.consentRequired],
                             flags: ["sync.gzip": false, "push.enabled": true], trackers: ["garmin", "oura"],
                             syncCheck: Self.syncCheck, context: context, about: about)
    }

    private func model(_ api: MockPlatformAPI = MockPlatformAPI(), online: Bool = true, signedIn: Bool = true,
                       clock: TestClock = TestClock(),
                       queue: FeedbackQueueStore? = nil) -> (ReportProblemModel, AppEnvironment) {
        let env = AppEnvironment.test(api: api, clock: clock, auth: .preview(signedIn: signedIn), online: online)
        let model = ReportProblemModel(env: env, apiStatus: APIStatus(), queue: queue) { Self.sync }
        model.message = "Today said calibrating after a full week."
        return (model, env)
    }

    // MARK: payload

    @Test func thePayloadCarriesTheInstallTheContextAndTheFailedRequests() throws {
        let requests = [request(0, status: 200, id: "ok-0"), request(1, id: "fail-1"), request(2, status: 429, id: "fail-2")]
        let context = ReportContext(resource: "Today", status: "503", requestID: "ctx-1")
        let post = make("  It broke.\n", requests: requests, context: context)
        #expect(post.message == "It broke." && post.category == .bug)
        #expect(post.appVersion == "1.0.0" && post.build == "20261021.141128")
        #expect(post.deviceModel == "iPhone17,1" && post.osVersion == "iOS 27.0.1")
        // The context's first, then the failed ones, newest first; a served request has no place there.
        #expect(post.requestIds == ["ctx-1", "fail-1", "fail-2"])
        // Then the resources' last errors' IDs, each once.
        let error = { (id: String) in
            ResourceError(kind: .transient, status: 503, code: nil, requestID: id, transport: nil, attempts: 3, at: .now)
        }
        let withResources = FeedbackPayload.requestIDs(context: context, requests: requests,
                                                       resources: [.me: ResourceState(lastError: error("res-1")),
                                                                   .today: ResourceState(lastError: error("fail-1"))])
        #expect(withResources == ["ctx-1", "fail-1", "fail-2", "res-1"])
        let d = try #require(post.diagnostics)
        // Every key; `trackers` goes only with `devices.setup` on (DevicesAndDiagnosticsTests).
        #expect(Set(d.keys) == FeedbackPayload.keys)
        #expect(d["trackers"] == "garmin,oura")
        #expect(d["sync"] == Self.syncText)
        #expect(d["gates"] == "consent_required" && d["locale"] == "de_DE")
        #expect(d["flags"] == "push.enabled=1,sync.gzip=0")
        #expect(d["report_context"] == "Today · 503 · ctx-1")
        #expect(d["requests"] == requests.map(FeedbackPayload.line).joined(separator: "\n"))
        #expect(d["sync_check"] == Self.syncCheck.joined(separator: "\n"))
    }

    /// Check sync's result goes as tracker ids and codes, with the check's day: never a source's name, a bundle ID
    /// or a time of day (design.md §10).
    @Test func theLastCheckGoesAsTrackerIdsAndCodesOnly() async throws {
        // With `devices.setup` on, like `trackers` (forReport's test has it off).
        let env = AppEnvironment.test(flags: [.devicesSetup: true])
        let model = ReportProblemModel(env: env, apiStatus: APIStatus()) { Self.sync }
        model.message = "Today said calibrating after a full week."
        #expect(model.payload().diagnostics?["sync_check"] == nil && model.syncCheck == nil) // no check: no key, no row
        let store = MockHealthStore.garminLike(now: env.clock.now(), sleepOff: true)
        await TrackerCheckModel(env: env, health: store, trackers: ["garmin", "iphone"]).run()
        let check = try #require(model.payload().diagnostics?["sync_check"])
        let lines = check.components(separatedBy: "\n")
        #expect(model.syncCheck == lines) // and "What's included" lists it
        #expect(lines.first == "checked \(DayFormat.string(from: env.clock.now()))" && lines.count == 3)
        for line in lines.dropFirst() {
            #expect(line.wholeMatch(of: /[a-z_]+ [a-z_]+(?: [a-z0-9_]+=[a-z_]+)+/) != nil, "\(line)")
        }
        for leak in ["Connect", "com.", "iPhone", "Tim", ":"] { #expect(!check.contains(leak), "\(leak)") }
        model.includeDiagnostics = false
        #expect(model.payload().diagnostics == nil)
    }

    @Test func linesFollowTheirTemplates() {
        let r = request(0, status: 200, path: "/v1/sleep/plan?wake=06:30", id: "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c")
        #expect(FeedbackPayload.line(r) == "GET /v1/sleep/plan 200 - 01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c \(r.date.ISO8601Format())")
        // With a measured duration the line ends in it.
        var timed = r
        timed.durationMs = 412
        #expect(FeedbackPayload.line(timed) == FeedbackPayload.line(r) + " 412ms")
        let fetched = Date(timeIntervalSince1970: 1_792_600_000)
        let error = ResourceError(kind: .transient, status: 503, code: nil, requestID: "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c",
                                  transport: nil, attempts: 3, at: fetched)
        let timeout = ResourceError(kind: .transient, status: nil, code: nil, requestID: nil, transport: "timedOut",
                                    attempts: 3, at: fetched)
        let lines = FeedbackPayload.resourceLines([.today: ResourceState(fetchedAt: fetched),
                                                   .me: ResourceState(fetchedAt: fetched, lastError: error, consecutiveFailures: 3),
                                                   .history: ResourceState(lastError: timeout, consecutiveFailures: 1)])
        #expect(lines.count == ReadResource.allCases.count)
        #expect(lines.first == "today \(fetched.ISO8601Format()) - - -")
        #expect(lines.contains("me \(fetched.ISO8601Format()) 503 - 01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c"))
        #expect(lines.contains("history - timedOut - -") && lines.contains("journal - - - -"))
        let newest = Date(timeIntervalSince1970: 1_792_600_000)
        #expect(FeedbackPayload.syncLines(Self.sync) == [
            "phase incremental · recent true · backfill true",
            "queue running false · queued false · backlog 0 B",
            "stream sleep · 412 rec · 31 days · newest \(DayFormat.string(from: newest))",
        ])
        let never = FeedbackSync(streams: [.init(id: "workouts", records: 0, days: 0, newest: nil)])
        #expect(FeedbackPayload.syncLines(never).last == "stream workouts · 0 rec · 0 days · newest -")
    }

    @Test func thePayloadStaysWithinAPIMDsLimits() {
        let long = String(repeating: "x", count: 70)
        var requests = (0..<30).map { request($0) }
        requests.insert(request(0, id: String(repeating: "a", count: 65)), at: 0) // too long for the platform
        requests.insert(request(0, id: ""), at: 0)
        requests.insert(request(0, id: "req-1"), at: 0) // twice
        let post = FeedbackPayload.make(message: String(repeating: "é", count: 4100), category: .other,
                                        includeDiagnostics: true, requests: requests, sync: FeedbackSync(),
                                        gates: [], flags: [:], context: nil,
                                        about: FeedbackAbout(appVersion: long, build: long, deviceModel: long,
                                                             osVersion: long, locale: "en"))
        #expect(FeedbackPayload.length(post.message) == 4000)
        #expect(post.requestIds.count == 20 && Set(post.requestIds).count == 20)
        #expect(post.requestIds.first == "req-1" && post.requestIds.allSatisfy { (1...64).contains($0.utf8.count) })
        #expect([post.appVersion, post.build, post.deviceModel, post.osVersion].allSatisfy { $0?.count == 64 })
        #expect(post.diagnostics?["gates"] == "-")
        #expect(post.diagnostics?["requests"]?.components(separatedBy: "\n").count == 20)
    }

    @Test func withoutDiagnosticsOnlyTheMessageGoes() {
        let post = make(requests: [request(0)], includeDiagnostics: false,
                        context: ReportContext(resource: "Today", status: "503", requestID: "ctx-1"))
        #expect(post.message == "It broke." && post.category == .bug)
        #expect(post.appVersion == nil && post.build == nil && post.deviceModel == nil && post.osVersion == nil)
        #expect(post.requestIds.isEmpty && post.diagnostics == nil)
    }

    @Test func diagnosticsStayWithin32KiBDroppingTheOldestRequestsFirst() throws {
        let requests = (0..<20).map { request($0, path: "/v1/workouts/" + String(repeating: "w", count: 1_800)) }
        let all = requests.map(FeedbackPayload.line)
        #expect(FeedbackPayload.size(["requests": all.joined(separator: "\n")]) > FeedbackPayload.maxDiagnosticsBytes)

        let d = try #require(make(requests: requests).diagnostics)

        #expect(FeedbackPayload.size(d) <= FeedbackPayload.maxDiagnosticsBytes)
        #expect(d["sync"] == Self.syncText)
        let kept = try #require(d["requests"]).components(separatedBy: "\n")
        #expect(kept.count > 10 && kept.count < 20)
        #expect(kept == Array(all.prefix(kept.count))) // the newest stay, the oldest went
        #expect(d["resources"]?.components(separatedBy: "\n").count == ReadResource.allCases.count) // stays
    }

    @Test func aRequestTooBigForTheCapLeavesTheRest() throws {
        let huge = request(0, path: "/v1/workouts/" + String(repeating: "w", count: 40_000))
        let d = try #require(make(requests: [huge]).diagnostics)
        #expect(FeedbackPayload.size(d) <= FeedbackPayload.maxDiagnosticsBytes)
        #expect(d["requests"] == nil && d["sync"] == Self.syncText && d["flags"] != nil)
        #expect(d["resources"] != nil)
    }

    /// Without a single request still over 32 KiB: `resources` goes together with `sync`; the rest stays.
    @Test func aSyncTooBigForTheCapGoesWithTheResources() throws {
        let streams = (0..<2_000).map { FeedbackSync.Stream(id: "stream\($0)", records: 1, days: 1, newest: nil) }
        let d = try #require(FeedbackPayload.make(message: "Hi", category: .bug, includeDiagnostics: true,
                                                  requests: [request(0)], resources: [.today: ResourceState(fetchedAt: .now)],
                                                  sync: FeedbackSync(streams: streams), gates: [], flags: ["sync.gzip": true],
                                                  context: nil, about: about).diagnostics)
        #expect(FeedbackPayload.size(d) <= FeedbackPayload.maxDiagnosticsBytes)
        #expect(d["sync"] == nil && d["resources"] == nil && d["requests"] == nil)
        #expect(d["flags"] == "sync.gzip=1" && d["locale"] == "de_DE" && d["gates"] == "-")
    }

    /// Send to RYFT names a missing response "No response", never the transport's raw name (that goes out in
    /// `resources`): the chip and `report_context` stay readable.
    @Test func anUnreachableIssueIsReportedAsNoResponse() throws {
        let timeout = ResourceError(kind: .transient, status: nil, code: nil, requestID: nil, transport: "timedOut",
                                    attempts: 3, at: .now)
        let unreachable = RefreshIssue(reason: .unreachable, resource: .today, dataFrom: nil, failures: 1, error: timeout)
        #expect(unreachable.reportStatus == String(localized: "No response"))
        let busy = RefreshIssue(reason: .busy, resource: .today, dataFrom: nil, failures: 3,
                                error: ResourceError(kind: .transient, status: 503, code: nil, requestID: "r-1",
                                                     transport: nil, attempts: 3, at: .now))
        #expect(busy.reportStatus == "503")
        let context = ReportContext(resource: unreachable.resourceName, status: unreachable.reportStatus,
                                    requestID: unreachable.error.requestID, code: unreachable.error.code)
        let d = try #require(make(context: context).diagnostics)
        #expect(d["report_context"] == "\(unreachable.resourceName) · \(String(localized: "No response")) · -")
        #expect(d["report_context"]?.contains("timedOut") == false)
    }

    @Test func aQueuedReportGoesOutAsItWasWritten() throws {
        let post = make(requests: [request(0)], context: ReportContext(resource: "Today", status: "503", requestID: "ctx-1"))
        let queued = QueuedFeedback(post, account: "acct-1", queuedAt: Date(timeIntervalSince1970: 1_792_600_000))
        // Through the cache's own coder (snake_case): the diagnostics' keys must come back as they were.
        let back = try #require(WireCoding.decode([QueuedFeedback].self, WireCoding.encode([queued])))
        #expect(back == [queued] && back[0].account == "acct-1")
        func object(_ p: FeedbackPost) throws -> NSDictionary {
            try #require(try JSONSerialization.jsonObject(with: APIClient.jsonEncoder.encode(p)) as? NSDictionary)
        }
        #expect(try object(back[0].post) == object(post))
        #expect(back[0].post.diagnostics?["report_context"] == "Today · 503 · ctx-1")
    }

    // MARK: sending

    @Test func sentWhenThePlatformTakesIt() async throws {
        let api = MockPlatformAPI()
        let (model, env) = model(api)
        model.category = .data
        #expect(model.canSend)
        await model.send()
        #expect(model.result == .sent && !model.sending)
        #expect(api.feedbackPosts.map(\.message) == ["Today said calibrating after a full week."])
        #expect(model.waiting == 0 && PersistentFeedbackQueue(env: env).load().isEmpty)
        let posted = try #require(api.feedbackPosts.first)
        #expect(posted.category == .data && posted.diagnostics?["sync"] == Self.syncText)
        // The next report starts fresh.
        #expect(model.message.isEmpty && model.category == .other && model.includeDiagnostics)
    }

    @Test func offlineItIsQueuedAndSentOnReconnect() async {
        let api = MockPlatformAPI()
        let (model, env) = model(api, online: false)
        await model.send()
        #expect(model.result == .queued && model.waiting == 1)
        #expect(api.count("feedback") == 0 && model.category == .other)

        await model.flush() // still offline: nothing goes
        #expect(api.count("feedback") == 0 && model.waiting == 1)

        env.connectivityMonitor.update(true)
        await model.flush()
        #expect(api.feedbackPosts.map(\.message) == ["Today said calibrating after a full week."])
        #expect(model.waiting == 0 && PersistentFeedbackQueue(env: env).load().isEmpty)
    }

    @Test func theQueueSurvivesARelaunch() async {
        let api = MockPlatformAPI()
        let (model, env) = model(api, online: false)
        await model.send()
        #expect(model.result == .queued)

        // The app was closed: a new model over the same store finds the report and sends it.
        let relaunched = ReportProblemModel(env: env, apiStatus: APIStatus()) { FeedbackSync() }
        #expect(relaunched.waiting == 1 && relaunched.message.isEmpty)
        env.connectivityMonitor.update(true)
        await relaunched.flush()
        #expect(api.feedbackPosts.map(\.message) == ["Today said calibrating after a full week."])
        #expect(api.feedbackPosts.first?.diagnostics?["sync"] == Self.syncText)
        #expect(relaunched.waiting == 0)
    }

    @Test func aBusyPlatformQueuesTheReport() async {
        let api = MockPlatformAPI()
        let (model, _) = model(api)
        api.failNext = APIError.http(503, "busy")
        await model.send()
        #expect(model.result == .queued && model.waiting == 1)
        await model.flush()
        #expect(api.feedbackPosts.count == 1 && model.waiting == 0)
    }

    @Test func noConnectionAfterAllQueuesTheReport() async {
        let api = MockPlatformAPI()
        let (model, _) = model(api)
        api.failNext = APIError.transport(URLError(.notConnectedToInternet))
        await model.send()
        #expect(model.result == .queued && model.waiting == 1)
    }

    @Test func rateLimitedKeepsTheMessageAndQueuesNothing() async {
        let api = MockPlatformAPI()
        let (model, _) = model(api)
        for i in 0..<10 {
            model.message = "Report \(i)"
            await model.send()
            #expect(model.result == .sent)
        }
        model.message = "The eleventh today."
        await model.send()
        #expect(model.result == .rateLimited)
        #expect(model.message == "The eleventh today." && !model.canSend)
        #expect(model.waiting == 0 && api.feedbackPosts.count == 10)
        #expect(model.resultDetails?.contains("429") == true)
    }

    @Test func aQueuedReportWaitsOutTheDailyCap() async {
        let api = MockPlatformAPI()
        let (model, env) = model(api, online: false)
        await model.send()
        api.feedbackDailyLimit = 0
        env.connectivityMonitor.update(true)
        await model.flush()
        #expect(model.waiting == 1) // kept for tomorrow, not dropped
    }

    @Test func aRefusedReportIsDropped() async {
        let api = MockPlatformAPI()
        let (model, _) = model(api)
        api.failNext = APIError.http(422, "message must have 1-4000 characters", requestID: "r-422")
        await model.send()
        #expect(model.result == .rejected && model.waiting == 0)
        #expect(model.message == "Today said calibrating after a full week.")
        #expect(model.resultDetails?.contains("r-422") == true)
    }

    @Test func aReportThatCanNotBeSavedSaysSo() async {
        let api = MockPlatformAPI()
        let (offline, _) = model(api, online: false, queue: FailingFeedbackQueue())
        await offline.send()
        #expect(offline.result == .saveFailed && offline.message == "Today said calibrating after a full week.")

        let (busy, _) = model(api, queue: FailingFeedbackQueue())
        api.failNext = APIError.http(503, "busy")
        await busy.send()
        #expect(busy.result == .saveFailed && api.feedbackPosts.isEmpty)
    }

    @Test func fromDetailsItIsABugReportPrefilled() async {
        let api = MockPlatformAPI()
        let (model, _) = model(api)
        model.message = ""
        let context = ReportContext(resource: "Today", status: "503", requestID: "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c")
        model.prepare(context)
        #expect(model.category == .bug && model.context == context)
        #expect(model.message == ReportProblemModel.prefill(context) && model.includeDiagnostics)
        await model.send()
        #expect(api.feedbackPosts.first?.requestIds.first == "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c")
        #expect(api.feedbackPosts.first?.category == .bug)

        // From Profile afterwards: a fresh report about nothing in particular.
        model.prepare(nil)
        #expect(model.result == nil && model.context == nil)
        #expect(model.message.isEmpty && model.category == .other)
    }

    @Test func aDraftStaysUntilItIsSent() {
        let (model, _) = model()
        model.message = "Half a thought"
        model.prepare(nil)
        #expect(model.message == "Half a thought")
    }

    @Test func overTheLimitOrBlankCanNotBeSent() {
        let (model, _) = model()
        model.message = String(repeating: "a", count: 3_500)
        #expect(!model.showsCount && model.canSend)
        model.message = String(repeating: "a", count: 4_000)
        #expect(model.showsCount && !model.isTooLong && model.canSend)
        model.message = String(repeating: "a", count: 4_001)
        #expect(model.isTooLong && !model.canSend)
        model.message = " \n "
        #expect(!model.canSend)
    }

    // MARK: accounts

    @Test func signedOutNothingIsQueued() async {
        let api = MockPlatformAPI()
        let (model, _) = model(api, signedIn: false)
        await model.send()
        #expect(model.result == .signedOut && model.waiting == 0 && api.count("feedback") == 0)
        #expect(model.message == "Today said calibrating after a full week.")
    }

    @Test func anotherAccountsReportNeverGoesOut() async {
        let api = MockPlatformAPI()
        let (model, env) = model(api)
        let queue = PersistentFeedbackQueue(env: env)
        let account = env.auth.accountID ?? ""
        queue.save([QueuedFeedback(FeedbackPost(message: "Someone else's"), account: "another-account",
                                   queuedAt: env.clock.now()),
                    QueuedFeedback(FeedbackPost(message: "Mine"), account: account, queuedAt: env.clock.now())])
        model.reloadWaiting()
        #expect(model.waiting == 2)
        await model.flush()
        #expect(api.feedbackPosts.map(\.message) == ["Mine"])
        #expect(queue.load().isEmpty && model.waiting == 0)
    }

    @Test func anAccountChangeForgetsTheDraftAndTheRequests() {
        let env = AppEnvironment.test()
        let state = AppState(env: env)
        let status = APIStatus()
        status.record(.init(date: .now, method: "GET", path: "/v1/me", status: 503, requestID: "a-1"))
        status.served(.init(date: .now, method: "GET", path: "/v1/days/2026-10-21", status: 200, requestID: "a-2"))
        let sync = SyncService(env: env)
        let profile = ProfileViewModel(state: state, sync: sync,
                                       coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                    clock: env.clock),
                                       apiStatus: status)
        let report = profile.report
        report.stage(message: "A's words", category: .data, includeDiagnostics: false, context: .preview,
                     result: .rateLimited)

        // A first sign-in leaves no account behind: the draft goes, nothing else.
        profile.accountChanged(from: nil)
        #expect(status.requests.count == 2 && status.epoch == 0 && report.message.isEmpty)

        report.stage(message: "A's words", category: .data, includeDiagnostics: false, context: .preview,
                     result: .rateLimited)
        profile.accountChanged(from: "account-a")

        #expect(status.requests.isEmpty && status.failures.isEmpty && status.epoch == 1)
        #expect(report.message.isEmpty && report.category == .other && report.includeDiagnostics)
        #expect(report.context == nil && report.result == nil && report.resultDetails == nil)
        #expect(report.payload().requestIds.isEmpty)
    }

    @Test func aPostThatReturnsAfterAnAccountChangeLeavesTheNewScreenAlone() async {
        let api = MockPlatformAPI()
        let clock = TestClock()
        let (model, _) = model(api, clock: clock)
        api.beforeFeedback = { _ in try? await clock.sleep(for: .seconds(1)) }
        let sending = Task { await model.send() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        model.accountChanged()
        clock.advance(by: .seconds(1))
        await sending.value
        #expect(model.result == nil && model.waiting == 0 && model.message.isEmpty)
    }

    // MARK: concurrency

    /// A report `send` posts while a flush runs is posted once: the flush reads the queue again before each post.
    @Test(.timeLimit(.minutes(1))) func sendDuringAFlushPostsEachReportOnce() async {
        let api = MockPlatformAPI()
        let clock = TestClock()
        let (model, env) = model(api, online: false, clock: clock)
        model.message = "A"
        await model.send() // queued while offline
        env.connectivityMonitor.update(true)
        // B returns after 1 s, A after 2 s: B is settled (and dequeued) while the flush still waits on A. A second
        // post of either isn't held, so a regression shows in the count.
        let hold = FirstPostHold()
        api.beforeFeedback = { post in
            if hold.isFirst(post.message) { try? await clock.sleep(for: .seconds(post.message == "B" ? 1 : 2)) }
        }

        model.message = "B"
        let sending = Task { await model.send() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let flushing = Task { await model.flush() }
        #expect(await eventually { clock.pendingSleeps == 2 })

        clock.advance(by: .seconds(1))
        await sending.value
        clock.advance(by: .seconds(60))
        await flushing.value
        await model.flush()

        #expect(api.feedbackPosts.map(\.message).sorted() == ["A", "B"])
        #expect(api.count("feedback") == 2 && model.waiting == 0)
    }

    /// The account ends while a flush has a report on its way: the next report doesn't go out (as anyone).
    @Test(.timeLimit(.minutes(1))) func anAccountSwitchDuringAFlushStopsIt() async {
        let api = MockPlatformAPI()
        let clock = TestClock()
        let (model, env) = model(api, online: false, clock: clock)
        model.message = "First"
        await model.send()
        model.message = "Second"
        await model.send()
        #expect(model.waiting == 2)
        env.connectivityMonitor.update(true)
        let hold = FirstPostHold()
        api.beforeFeedback = { post in
            if hold.isFirst(post.message) { try? await clock.sleep(for: .seconds(1)) }
        }

        let flushing = Task { await model.flush() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        await env.auth.signOut()
        #expect(env.auth.accountID == nil)
        clock.advance(by: .seconds(60))
        await flushing.value

        #expect(api.feedbackPosts.map(\.message) == ["First"]) // already on its way; the second stays home
    }

    /// A request of the previous account's waiting out a 503 across an account change never goes out again:
    /// no second attempt (A's body with B's token), and no "RYFT is catching up" left on screen.
    @Test(.timeLimit(.minutes(1))) func aRetryNeverOutlivesItsAccount() async {
        LateReplyURLProtocol.reset("/v1/busy-account")
        let clock = TestClock()
        let status = APIStatus()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LateReplyURLProtocol.self]
        let base = URL(string: "https://api.test")!
        let client = APIClient(session: URLSession(configuration: config), tokens: FakeTokens(),
                               sleep: { try await clock.sleep(for: .seconds($0)) }, baseURL: base, status: status)
        let request = Task { () -> Error? in
            do {
                _ = try await client.data("PATCH", path: "/v1/busy-account", body: ["sleep_base_min": 450], base: base)
                return nil
            } catch {
                return error
            }
        }
        #expect(await eventually { clock.pendingSleeps == 1 }) // waiting out the 503
        #expect(status.retryNotice != nil)

        status.forgetRequests() // signed out (and in as someone else) meanwhile
        #expect(status.retryNotice == nil)
        clock.advance(by: .seconds(60))
        let error = await request.value

        #expect(error is CancellationError)
        #expect(LateReplyURLProtocol.attempts("/v1/busy-account") == 1)
        #expect(status.retryNotice == nil && status.requests.isEmpty && status.failures.isEmpty)
    }

    /// A 503 wait that ends in a throw (its task cancelled) takes "RYFT is catching up" with it.
    @Test(.timeLimit(.minutes(1))) func aCancelledWaitClearsTheNotice() async {
        LateReplyURLProtocol.reset("/v1/busy-cancelled")
        let status = APIStatus()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LateReplyURLProtocol.self]
        let base = URL(string: "https://api.test")!
        // The wait throws as a cancelled `Task.sleep` does.
        let client = APIClient(session: URLSession(configuration: config), tokens: FakeTokens(),
                               sleep: { _ in throw CancellationError() }, baseURL: base, status: status)
        var thrown: Error?
        do {
            _ = try await client.data("GET", path: "/v1/busy-cancelled", body: Optional<Int>.none, base: base)
        } catch {
            thrown = error
        }
        #expect(thrown is CancellationError)
        #expect(status.retryNotice == nil)
        #expect(LateReplyURLProtocol.attempts("/v1/busy-cancelled") == 1)

        // And an account change takes a notice with it at once.
        status.waiting(seconds: 12)
        status.forgetRequests()
        #expect(status.retryNotice == nil)
    }

    /// One redaction for every path the app shows or sends: the report's request lines use `redactedPath`
    /// (Sync details and the log do too): no query, `{id}` for UUIDs, days kept.
    @Test func oneRedactionForEveryPath() {
        for (path, redacted) in [("/v1/trends?metric=hrv&range=week#x", "/v1/trends"),
                                 ("/v1/devices/01A14FFA-EB7C-73E3-9CF9-262C70D5ED9C/push", "/v1/devices/{id}/push"),
                                 ("/v1/workouts/01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c", "/v1/workouts/{id}"),
                                 ("/v1/journal/2026-10-21", "/v1/journal/2026-10-21"),
                                 ("/v1/sleep/plan?wake=06:30", "/v1/sleep/plan")] {
            #expect(redactedPath(path) == redacted)
            #expect(FeedbackPayload.line(request(0, path: path)).components(separatedBy: " ")[1] == redacted)
        }
    }

    /// `POST /v1/feedback` makes one attempt: a `429` (10 a day) answers at once, with no `Retry-After` wait.
    @Test(.timeLimit(.minutes(1))) func postFeedbackDoesNotWaitOnA429() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LateReplyURLProtocol.self]
        let base = URL(string: "https://api.test")!
        let waits = SleepLog()
        let client = APIClient(session: URLSession(configuration: config), tokens: FakeTokens(),
                               sleep: { waits.record($0) }, baseURL: base, status: APIStatus())
        var status: Int?
        do {
            try await client.postFeedback(FeedbackPost(message: "Hi"))
        } catch {
            status = (error as? APIError)?.status
        }
        #expect(status == 429 && waits.waits.isEmpty)
    }

    /// After `forgetRequests()` a late cancellation or transport failure of the previous account's leaves
    /// `requests`, `failures` and `cancelledCount` empty (`APIStatus.epoch`).
    @Test(.timeLimit(.minutes(1))) func aLateCancellationOrTimeoutLeavesNothing() async {
        let clock = TestClock()
        let status = APIStatus()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LateReplyURLProtocol.self]
        let base = URL(string: "https://api.test")!
        let client = APIClient(session: URLSession(configuration: config), tokens: SlowTokens(clock: clock),
                               sleep: { _ in }, baseURL: base, status: status)
        func get(_ path: String) -> Task<Void, Never> {
            Task { _ = try? await client.data("GET", path: path, body: Optional<Int>.none, base: base) }
        }

        // Without a switch, both count: a timeout as a failure, a cancellation as cancelled.
        let timeout = get("/v1/timeout")
        let cancelled = get("/v1/me")
        #expect(await eventually { clock.pendingSleeps == 2 })
        cancelled.cancel()
        clock.advance(by: .seconds(1))
        await timeout.value
        await cancelled.value
        #expect(status.failures.count == 1 && status.failures.first?.transport == "timedOut")
        #expect(status.cancelledCount == 1)

        let lateTimeout = get("/v1/timeout")
        let lateCancelled = get("/v1/me")
        #expect(await eventually { clock.pendingSleeps == 2 })
        status.forgetRequests() // the account changed while they were on their way
        lateCancelled.cancel()
        clock.advance(by: .seconds(1))
        await lateTimeout.value
        await lateCancelled.value

        #expect(status.requests.isEmpty && status.failures.isEmpty && status.cancelledCount == 0)
    }

    /// A response to a request that started for the previous account lands nowhere: not in the requests, not
    /// in the failures, not as a gate (`APIStatus.epoch`).
    @Test(.timeLimit(.minutes(1))) func aResponseFromThePreviousAccountIsNotRecorded() async {
        let clock = TestClock()
        let status = APIStatus()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LateReplyURLProtocol.self]
        let base = URL(string: "https://api.test")!
        let client = APIClient(session: URLSession(configuration: config), tokens: SlowTokens(clock: clock),
                               sleep: { _ in }, baseURL: base, status: status)
        func get(_ path: String) -> Task<Void, Never> {
            Task { _ = try? await client.data("GET", path: path, body: Optional<Int>.none, base: base) }
        }

        // Without a switch, a response is recorded.
        let before = get("/v1/me")
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(1))
        await before.value
        #expect(status.requests.count == 1)

        let late = ["/v1/me", "/v1/gate", "/v1/missing"].map(get)
        #expect(await eventually { clock.pendingSleeps == 3 })
        status.forgetRequests() // the account changed while they were on their way
        clock.advance(by: .seconds(1))
        for request in late { await request.value }

        #expect(status.requests.isEmpty && status.failures.isEmpty && status.gates.isEmpty)
    }

    // MARK: privacy

    /// The diagnostics pass the allow-list: only known keys, every line one of its templates, no time of day
    /// from Apple Health, no query string. Every number therefore is a count, a status, a byte size, a day or a
    /// request's time, so a cached score can't hide in one (which is why there's no numeric loophole to test).
    @Test func noHealthValuesInTheDiagnostics() async throws {
        let env = AppEnvironment.test(flags: [.devicesSetup: true]) // every key, the trackers' ids included
        let state = AppState(env: env)
        await state.refresh() // MockData's scores in the read models
        state.repository.store(scores: try Fixture.decode([DailyScore].self, "days"))
        // Streams whose newest records end at a wake time and after a workout, to the second.
        let wake = try #require(Calendar.current.date(bySettingHour: 6, minute: 42, second: 17, of: env.clock.now()))
        let workoutEnd = try #require(Calendar.current.date(bySettingHour: 18, minute: 31, second: 5, of: env.clock.now()))
        var engine = SyncEngineState()
        engine.phase = .incremental
        engine.backfillDone = true
        var sleep = SyncEngineState.StreamProgress()
        sleep.records = 412
        sleep.newest = wake
        sleep.days = ["2026-10-18", "2026-10-19"]
        var workouts = SyncEngineState.StreamProgress()
        workouts.records = 3
        workouts.newest = workoutEnd
        engine.streams = ["sleep": sleep, "workouts": workouts]
        engine.lastError = "422 sample out of range"
        engine.save(account: try #require(env.auth.accountID), defaults: env.defaults)

        let status = APIStatus()
        let install = env.settings.deviceId.uuidString.lowercased()
        let workout = UUID().uuidString.lowercased()
        let requestIDs = (0..<7).map { _ in UUID().uuidString.lowercased() }
        for (i, (method, path, code)) in [("GET", "/v1/sleep/plan?wake=06:30", 200), ("GET", "/v1/journal/2026-10-21", 200),
                                          ("GET", "/v1/trends?metric=hrv&range=week", 200), ("GET", "/v1/days/2026-10-18", 200),
                                          ("GET", "/v1/me", 503), ("POST", "/v1/devices/\(install)/push", 204),
                                          ("GET", "/v1/workouts/\(workout)", 200)].enumerated() {
            status.record(.init(date: env.clock.now(), method: method, path: path, status: code, requestID: requestIDs[i],
                                durationMs: i.isMultiple(of: 2) ? 100 + i : nil))
        }
        // What the read pipeline recorded: a load, a 503 with its request ID, a timeout.
        let resourceID = UUID().uuidString.lowercased()
        let loaded = env.clock.now() // the app's own clock, not a sample's time
        env.reads.seed([
            .today: ResourceState(fetchedAt: loaded),
            .me: ResourceState(fetchedAt: loaded, lastError: ResourceError(kind: .transient, status: 503, code: nil,
                                                                         requestID: resourceID, transport: nil,
                                                                         attempts: 3, at: loaded),
                               consecutiveFailures: 3, retryNotBefore: loaded),
            .history: ResourceState(lastError: ResourceError(kind: .transient, status: nil, code: nil, requestID: nil,
                                                             transport: "timedOut", attempts: 3, at: loaded),
                                    consecutiveFailures: 1),
        ])
        let sync = SyncService(env: env)
        let profile = ProfileViewModel(state: state, sync: sync,
                                       coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                    clock: env.clock),
                                       apiStatus: status)
        profile.devices.save(["garmin", "oura"])
        // A check whose sources carry names and times of day.
        await TrackerCheckModel(env: env, health: MockHealthStore.garminLike(now: env.clock.now(), sleepOff: true),
                                trackers: ["garmin"]).run()
        profile.report.prepare(.preview)
        let post = profile.report.payload()
        let d = try #require(post.diagnostics)

        #expect(Set(d.keys) == FeedbackPayload.keys)
        #expect(d["trackers"] == "garmin,oura") // ids, never a device's name
        let templates: [String: [Regex<Substring>]] = [
            "requests": [/(?:GET|POST|PUT|PATCH|DELETE) \/[^ ?#]* \d{3} [a-z_-]+ \S+ \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z(?: \d+ms)?/],
            "resources": [/[a-zA-Z]+ (?:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z|-) (?:[A-Za-z0-9]+|-) (?:[a-z_]+|-) \S+/],
            "sync": [/phase [a-z]+ · recent (?:true|false) · backfill (?:true|false)/,
                     /queue running (?:true|false) · queued (?:true|false) · backlog \d+ B/,
                     /stream [A-Za-z0-9_]+ · \d+ rec · \d+ days · newest (?:\d{4}-\d{2}-\d{2}|-)/],
            "gates": [/-|[a-z_]+(?:,[a-z_]+)*/],
            // The flags' keys as the platform accepts them (`FeatureFlag`): identifiers, never free text.
            "flags": [/[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+=[01](?:,[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+=[01])*/],
            "locale": [/[A-Za-z0-9_@=-]+/],
            "report_context": [/[^·\n]+ · [^·\n]+ · \S+/],
            "trackers": [/-|[a-z][a-z0-9_]*(?:,[a-z][a-z0-9_]*)*/],
            "sync_check": [/checked \d{4}-\d{2}-\d{2}/, /[a-z_]+ [a-z_]+(?: [a-z0-9_]+=[a-z_]+)+/],
        ]
        for (key, value) in d {
            let patterns = try #require(templates[key])
            for line in value.components(separatedBy: "\n") {
                #expect(patterns.contains { line.wholeMatch(of: $0) != nil }, "\(key): \(line)")
            }
        }
        // No time of day from Apple Health: the newest records go as their day.
        let syncText = try #require(d["sync"])
        #expect(!syncText.contains(":") && syncText.contains("newest \(DayFormat.string(from: wake))"))
        #expect(syncText.components(separatedBy: "\n").count == 2 + env.health.streams.count)
        #expect(!syncText.contains("422") && !syncText.contains("sample out of range")) // free text stays home
        let sent = try #require(String(data: APIClient.jsonEncoder.encode(post), encoding: .utf8))
        #expect(!sent.contains("wake=") && !sent.contains("06:30") && !sent.contains("metric="))
        #expect(!sent.contains("Connect") && !sent.contains("com.garmin") && !sent.contains("Tim's"))
        // Copy diagnostics carries the same codes on one line.
        let copied = profile.syncDetails.diagnostics
        #expect(copied.contains("sync check: checked \(DayFormat.string(from: env.clock.now())) · garmin needs_fix "))
        #expect(!copied.contains("Connect") && !copied.contains("com.garmin"))
        // The install ID and other IDs in paths stay home: the only UUIDs are request IDs, in their place.
        #expect(!sent.lowercased().contains(install) && !sent.lowercased().contains(workout))
        let allowed = Set(requestIDs + [resourceID] + [ReportContext.preview.requestID].compactMap { $0 })
        // Every resource once, in order, with the seeded record and nothing more (no counts, no retry times).
        let resourceLines = try #require(d["resources"]).components(separatedBy: "\n")
        #expect(resourceLines.map { $0.components(separatedBy: " ")[0] } == ReadResource.allCases.map(\.rawValue))
        #expect(resourceLines.contains { $0.hasPrefix("me ") && $0.hasSuffix(" 503 - \(resourceID)") })
        // (History's load time is the stored scores', which AppState folds in.)
        #expect(resourceLines.contains { $0.hasPrefix("history ") && $0.hasSuffix(" timedOut - -") })
        #expect(d["requests"]?.contains("ms") == true)
        let uuid = /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/
        for value in d.values {
            for found in value.matches(of: uuid) { #expect(allowed.contains(String(found.output)), "\(found.output)") }
        }
        for line in try #require(d["requests"]).components(separatedBy: "\n") {
            let path = line.components(separatedBy: " ")[1]
            #expect(path.split(separator: "/").allSatisfy { UUID(uuidString: String($0)) == nil }, "\(path)")
        }
        #expect(d["requests"]?.contains("POST /v1/devices/{id}/push 204") == true)
        #expect(d["requests"]?.contains("GET /v1/workouts/{id} 200") == true)
        for field in ["readiness", "recovery", "sleep_performance", "hrv_ms", "\"rhr\"", "sleep_actual_min",
                      "resp_rate", "calibrating\":"] {
            #expect(!sent.contains(field), "\(field)")
        }
    }
}

@Suite("Apple Health: saving strength workouts (opt-in)")
@MainActor
struct WorkoutHealthExportTests {
    /// Not demo mode, whatever the simulator's setting (demo is on by default in a fresh one).
    private func export(_ health: MockHealthStore, account: String = "a") -> WorkoutHealthExport {
        WorkoutHealthExport(health: health, defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)")!,
                            account: { account }, isDemo: { false })
    }

    private let start = Date(timeIntervalSince1970: 1_792_400_000)

    @Test func nothingIsWrittenUntilYouSaySo() async {
        let health = MockHealthStore()
        let e = export(health)
        #expect(e.choice == nil && e.shouldAsk)
        await e.save(sessionID: UUID(), start: start, end: start.addingTimeInterval(3_600))
        #expect(health.savedWorkouts.isEmpty && health.writeRequests == 0)
    }

    @Test func turningItOnAsksOnceAndWritesTheSession() async throws {
        let health = MockHealthStore()
        let e = export(health)
        #expect(await e.turnOn())
        #expect(e.isOn && !e.shouldAsk && health.writeRequests == 1)
        let id = UUID()
        await e.save(sessionID: id, start: start, end: start.addingTimeInterval(3_000))
        let saved = try #require(health.savedWorkouts.first)
        #expect(saved.sessionID == id && saved.start == start && saved.end == start.addingTimeInterval(3_000))
        await e.save(sessionID: UUID(), start: start, end: start) // no duration: nothing
        #expect(health.savedWorkouts.count == 1)
    }

    @Test func aRefusalLeavesItOffAndNotNowIsNotAskedAgain() async {
        let health = MockHealthStore()
        health.allowsWorkoutWrites = false
        let e = export(health)
        #expect(!(await e.turnOn()))
        #expect(e.choice == .off)
        await e.save(sessionID: UUID(), start: start, end: start.addingTimeInterval(600))
        #expect(health.savedWorkouts.isEmpty)

        #expect(e.needsAccess)          // where to allow it (iOS won't ask again)
        e.turnOff()
        #expect(!e.needsAccess)

        let other = export(MockHealthStore())
        other.turnOff()                  // "Not now"
        #expect(!other.shouldAsk && !other.isOn && !other.needsAccess)
    }

    @Test func accessTakenAwayInHealthShowsOffAndWritesNothing() async {
        let health = MockHealthStore()
        let e = export(health)
        await e.turnOn()
        #expect(e.isWriting && !e.needsAccess)
        health.allowsWorkoutWrites = false        // Health → Sharing → Apps → RYFT
        await e.appBecameActive(now: start)
        #expect(e.isOn && !e.isWriting && e.needsAccess)
        await e.save(sessionID: UUID(), start: start, end: start.addingTimeInterval(600))
        #expect(health.savedWorkouts.isEmpty)
    }

    @Test func eachSessionIsWrittenOnceAndNotWhenTheWatchRecordedIt() async {
        let health = MockHealthStore()
        let e = export(health)
        await e.turnOn()
        let id = UUID()
        await e.save(sessionID: id, start: start, end: start.addingTimeInterval(3_600))
        await e.save(sessionID: id, start: start, end: start.addingTimeInterval(3_600))
        #expect(health.savedWorkouts.count == 1)

        // A watch strength workout over most of the session: that one counts.
        let later = start.addingTimeInterval(86_400)
        health.otherWorkouts = [DateInterval(start: later.addingTimeInterval(-300), end: later.addingTimeInterval(2_000))]
        await e.save(sessionID: UUID(), start: later, end: later.addingTimeInterval(3_600))
        #expect(health.savedWorkouts.count == 1)
        // Less than half of it: both stay.
        health.otherWorkouts = [DateInterval(start: later, end: later.addingTimeInterval(1_000))]
        await e.save(sessionID: UUID(), start: later, end: later.addingTimeInterval(3_600))
        #expect(health.savedWorkouts.count == 2)
    }

    @Test func aWatchWorkoutThatArrivesLaterReplacesRYFTs() async {
        let health = MockHealthStore()
        let e = export(health)
        await e.turnOn()
        await e.save(sessionID: UUID(), start: start, end: start.addingTimeInterval(3_600))
        #expect(health.savedWorkouts.count == 1)
        // The watch workout ended after the session and synced to Health afterwards.
        health.otherWorkouts = [DateInterval(start: start.addingTimeInterval(-60), end: start.addingTimeInterval(3_700))]
        await e.appBecameActive(now: start.addingTimeInterval(7_200))
        #expect(health.savedWorkouts.isEmpty)
    }

    @Test func overlapMeansAtLeastHalfOfTheSession() {
        let session = DateInterval(start: start, duration: 3_600)
        #expect(StrengthOverlap.covers(DateInterval(start: start, duration: 1_800), session: session))
        #expect(!StrengthOverlap.covers(DateInterval(start: start, duration: 1_799), session: session))
        #expect(StrengthOverlap.covers(DateInterval(start: start.addingTimeInterval(-7_200), duration: 10_000), session: session))
        #expect(!StrengthOverlap.covers(DateInterval(start: start.addingTimeInterval(3_600), duration: 600), session: session))
    }

    @Test func demoModeWritesNothing() async {
        let health = MockHealthStore()
        let e = WorkoutHealthExport(health: health, defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)")!,
                                    account: { "a" }, isDemo: { true })
        await e.turnOn()
        await e.save(sessionID: UUID(), start: start, end: start.addingTimeInterval(600))
        #expect(health.savedWorkouts.isEmpty)
    }

    @Test func signingOutForgetsEveryAccountsChoice() async {
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)")!
        var account = "a"
        let e = WorkoutHealthExport(health: MockHealthStore(), defaults: defaults, account: { account })
        await e.turnOn()
        account = "b"
        e.turnOff()
        defaults.set(true, forKey: "health.other")
        WorkoutHealthExport.wipe(defaults: defaults)
        #expect(e.choice == nil)
        account = "a"
        #expect(e.choice == nil && defaults.bool(forKey: "health.other"))
    }

    @Test func finishingWritesTheSessionOnceWhenComplete() async throws {
        let store = TrainStore(inMemory: true)
        let trainSync = TrainSyncService(store: store, remote: { MockPlatformAPI() }, monitorsNetwork: false)
        trainSync.gate = { _ in nil } // open: these tests are about what happens past it
        let coordinator = TrainCoordinator(sync: trainSync, library: TrainLibrary.preview(store: store), liveActivities: false)
        let s = SessionFactory.empty(in: store)
        s.startedAt = Date.now.addingTimeInterval(-1_800)
        SessionFactory.add(MockTrain.bench, to: s, sets: 1, in: store)
        let c = SessionController(session: s, sync: trainSync, liveActivity: nil)
        let ex = try #require(c.exercises.first)
        c.toggleCheck(try #require(ex.sets.first), in: ex)
        let health = MockHealthStore()
        let e = export(health)
        await e.turnOn()

        await coordinator.finish(c, export: e)
        await coordinator.finish(c, export: e)   // a second tap
        #expect(health.savedWorkouts.map(\.sessionID) == [s.id])
        #expect(health.savedWorkouts.first?.end == s.endedAt)
        c.stop()
    }

    @Test func onlyTheAppsOwnWorkoutsAreLeftOut() {
        func workout(_ bundle: String?) -> Workout {
            Workout(id: UUID(), activity: "strength", start: start, end: start.addingTimeInterval(3_600), avgHr: nil,
                    maxHr: nil, energyKcal: nil, distanceM: nil, source: "RYFT", sourceBundleId: bundle)
        }
        let watch = workout("com.apple.health")
        let kept = SyncEngine.withoutOwnWorkouts(HealthDelta(workouts: [workout("dev.test.ryft"), watch, workout(nil)]),
                                                 own: "dev.test.ryft")
        #expect(kept.workouts.count == 2 && kept.workouts.first?.id == watch.id)
        #expect(SyncEngine.withoutOwnWorkouts(HealthDelta(workouts: [watch]), own: nil).workouts.count == 1)
    }

    @Test func eachAccountChoosesForItself() async {
        let health = MockHealthStore()
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)")!
        var account = "a"
        let e = WorkoutHealthExport(health: health, defaults: defaults, account: { account })
        await e.turnOn()
        account = "b"
        #expect(e.choice == nil && e.shouldAsk)
    }

    @Test func workoutsRYFTWroteAreNotUploadedAgain() async throws {
        let own = try #require(SyncEngine.ownBundleID)
        func workout(_ bundle: String?) -> Workout {
            Workout(id: UUID(), activity: "strength", start: start, end: start.addingTimeInterval(3_600), avgHr: nil,
                    maxHr: nil, energyKcal: nil, distanceM: nil, source: "RYFT", sourceBundleId: bundle)
        }
        let watch = workout("com.garmin.connect.mobile")
        let health = MockHealthStore(streams: [.workouts], pages: [.workouts: [HealthDelta(workouts: [workout(own), watch]),
                                                                              HealthDelta(workouts: [workout(own)])]])
        let api = MockPlatformAPI()
        let sync = SyncService(env: .test(api: api, health: health))
        await sync.syncNow()
        #expect(api.syncRequests.flatMap(\.workouts).map(\.id) == [watch.id]) // the watch's only
        #expect(health.committed == [.workouts, .workouts]) // both pages' anchors still move
    }

    @Test func theSummarySaysWhereHeartRateCameFrom() {
        func workout(_ source: String, hr: Double?) -> Workout {
            Workout(id: UUID(), activity: "strength", start: start, end: start, avgHr: hr, maxHr: nil, energyKcal: nil,
                    distanceM: nil, source: source)
        }
        #expect(SessionSummarySheet.heartRateLine(workout("Garmin Connect", hr: 112))
                == String(localized: "Heart rate from Garmin Connect"))
        let none = String(localized: "No heart rate yet. With a strength workout on your watch too, it arrives once the watch syncs.")
        #expect(SessionSummarySheet.heartRateLine(workout("ryft-session", hr: nil)) == none)
        #expect(SessionSummarySheet.heartRateLine(workout("Garmin Connect", hr: nil)) == none)
    }
}

// MARK: - Tracker setup: the catalog's remote copy, the selection, the features line (design.md §2.6, §3, §8)

/// Two days after the newest date in the bundled catalog: a download built from it passes "not after tomorrow",
/// whatever the content ships next.
private let catalogNow: Date = {
    let bundled = TrackerCatalog.bundled
    let days = bundled.trackers.map(\.checked) + [String(bundled.version.prefix(10))]
    return DayFormat.shift(days.compactMap(DayFormat.date(from:)).max() ?? .now, days: 2)
}()

/// The bundled copy's version moved by `days`, with number `n`: a newer or an older download.
private func version(days: Int, _ n: Int = 1) -> String {
    let day = DayFormat.date(from: String(TrackerCatalog.bundled.version.prefix(10))) ?? catalogNow
    return "\(DayFormat.string(from: DayFormat.shift(day, days: days))).\(n)"
}

/// The bundled catalog as a download: another `version`, and whatever `change` does to it.
private func catalogBody(version: String, _ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
    var root = try #require(try JSONSerialization.jsonObject(with: Data(TrackerCatalog.bundledJSON.utf8)) as? [String: Any])
    root["version"] = version
    change(&root)
    return try JSONSerialization.data(withJSONObject: root)
}

@MainActor
private func catalogStore(flag: Bool = true, online: Bool = true)
    -> (TrackerCatalogStore, MockContentSource, TestClock, AppEnvironment) {
    let content = MockContentSource()
    let clock = TestClock(now: catalogNow)
    let env = AppEnvironment.test(clock: clock, flags: [.devicesSetup: flag], online: online, content: content)
    return (env.catalogStore, content, clock, env)
}

@Suite("Tracker catalog: the copy from ryftapp.de")
@MainActor
struct TrackerCatalogStoreTests {
    private let bundled = TrackerCatalog.bundled.version

    private func cached(_ env: AppEnvironment) -> TrackerCatalogStore.Cached? {
        env.persistence.document(TrackerCatalogStore.Cached.self, key: TrackerCatalogStore.documentKey)
    }

    @Test func theBundledCopyServesUntilADownloadIsBetter() async {
        let (store, content, _, env) = catalogStore()
        defer { withExtendedLifetime(env) {} } // the store holds its environment weakly
        #expect(store.current == .bundled && store.origin == .bundled(bundled))
        await store.load()
        #expect(store.current == .bundled && content.requests.isEmpty)
    }

    @Test func aNewerValidCopyIsShownAndCachedWithItsETag() async throws {
        let (store, content, clock, env) = catalogStore()
        content.script([.success(.fetched(try catalogBody(version: version(days: 1)), etag: #"W/"a1""#))])

        await store.refreshIfDue()

        #expect(content.requests == [.init(path: "trackers.json", etag: nil, maxBytes: 262_144)])
        #expect(store.current.version == version(days: 1) && store.lastFailure == nil)
        #expect(store.origin == .remote(version(days: 1), etag: #"W/"a1""#, checkedAt: clock.now()))
        #expect(cached(env)?.etag == #"W/"a1""# && cached(env)?.body != nil)
    }

    @Test func theETagGoesBackAndA304KeepsTheCopy() async throws {
        let (store, content, clock, env) = catalogStore()
        content.script([.success(.fetched(try catalogBody(version: version(days: 1)), etag: "e1")), .success(.notModified)])
        await store.refreshIfDue()
        clock.advance(by: .seconds(25 * 3_600))

        await store.refreshIfDue()

        #expect(content.requests.map(\.etag) == [nil, "e1"])
        #expect(store.current.version == version(days: 1) && store.checkedAt == clock.now())
        #expect(cached(env)?.checkedAt == clock.now() && cached(env)?.etag == "e1")
    }

    @Test func dueADayAfterAnAnswerAndAnHourAfterAFailure() async throws {
        let (store, content, clock, env) = catalogStore()
        defer { withExtendedLifetime(env) {} } // the store holds its environment weakly
        content.script([.failure(ContentError.http(404)), .success(.notModified), .success(.notModified)])
        await store.refreshIfDue()
        #expect(store.lastFailure == "http 404" && store.current == .bundled) // the URL isn't published yet: silent

        clock.advance(by: .seconds(59 * 60))
        await store.refreshIfDue()
        #expect(content.requests.count == 1) // one attempt, then the next due time is the retry
        clock.advance(by: .seconds(2 * 60))
        await store.refreshIfDue()
        #expect(content.requests.count == 2 && store.lastFailure == nil)

        clock.advance(by: .seconds(23 * 3_600))
        await store.refreshIfDue()
        #expect(content.requests.count == 2)
        clock.advance(by: .seconds(3_600))
        await store.refreshIfDue()
        #expect(content.requests.count == 3)
        await store.refreshIfDue(force: true) // Debug → Reload tracker catalog
        #expect(content.requests.count == 4)
    }

    @Test func anInvalidCopyKeepsTheCurrentOneAndStoresNoETag() async throws {
        let (store, content, clock, env) = catalogStore()
        let markup = try catalogBody(version: version(days: 1)) { root in
            guard var trackers = root["trackers"] as? [[String: Any]] else { return }
            trackers[1]["name"] = "Garmin <b>now</b>"
            root["trackers"] = trackers
        }
        content.script([.success(.fetched(markup, etag: "bad")), .success(.notModified)])

        await store.refreshIfDue()

        #expect(store.current == .bundled)
        #expect(store.lastFailure == "invalid text.markup at trackers[1].name")
        #expect(cached(env)?.etag == nil && cached(env)?.body == nil)
        clock.advance(by: .seconds(3_601))
        await store.refreshIfDue()
        #expect(content.requests.map(\.etag) == [nil, nil])
    }

    /// The trust rules a download must pass (ADR 0002): an off-allowlist link is dropped, not followed.
    @Test func aLinkOffTheAllowlistIsDroppedAndTheTextKept() async throws {
        let (store, content, _, env) = catalogStore()
        defer { withExtendedLifetime(env) {} } // the store holds its environment weakly
        let body = try catalogBody(version: version(days: 1)) { root in
            guard var trackers = root["trackers"] as? [[String: Any]] else { return }
            trackers[1]["help_url"] = "https://garmin.example.net/apple-health"
            root["trackers"] = trackers
        }
        content.script([.success(.fetched(body, etag: nil))])
        await store.refreshIfDue()
        #expect(store.current.version == version(days: 1))
        #expect(store.current.tracker("garmin")?.help == nil && store.current.tracker("garmin")?.name == "Garmin")
    }

    @Test func anOlderCopyNeverRollsBack() async throws {
        let (store, content, clock, env) = catalogStore()
        content.script([.success(.fetched(try catalogBody(version: version(days: 1)), etag: "new")),
                        .success(.fetched(try catalogBody(version: version(days: 0, 9)), etag: "old"))])
        await store.refreshIfDue()
        clock.advance(by: .seconds(25 * 3_600))

        await store.refreshIfDue()

        #expect(store.current.version == version(days: 1) && cached(env)?.etag == "new")
        #expect(store.lastFailure == "older \(version(days: 0, 9))")
    }

    @Test func aCopyOlderThanTheBundledOneIsNotShown() async throws {
        let (store, content, _, env) = catalogStore()
        content.script([.success(.fetched(try catalogBody(version: version(days: -1)), etag: "old"))])
        await store.refreshIfDue()
        #expect(store.current == .bundled && cached(env)?.etag == nil)
    }

    @Test func oversizeIsRefused() async {
        let (store, content, _, env) = catalogStore()
        defer { withExtendedLifetime(env) {} } // the store holds its environment weakly
        content.script([.success(.fetched(Data(repeating: 0x20, count: 300_000), etag: "big"))])
        await store.refreshIfDue()
        #expect(store.current == .bundled && store.lastFailure == "too large")
    }

    @Test func offlineBehindTheFlagOrInDemoNothingIsAsked() async {
        let (offline, offlineContent, _, offlineEnv) = catalogStore(online: false)
        defer { withExtendedLifetime(offlineEnv) {} } // the store holds its environment weakly
        await offline.refreshIfDue()
        let (dark, darkContent, _, darkEnv) = catalogStore(flag: false)
        defer { withExtendedLifetime(darkEnv) {} } // the store holds its environment weakly
        await dark.refreshIfDue()
        let demo = AppEnvironment.preview()
        await demo.catalogStore.refreshIfDue()

        #expect(offlineContent.requests.isEmpty && darkContent.requests.isEmpty)
        #expect((demo.content as? MockContentSource)?.requests.isEmpty == true)
        #expect(offline.lastFailure == nil && dark.lastFailure == nil)
    }

    @Test func oneRequestAtATime() async throws {
        let (store, content, _, env) = catalogStore()
        defer { withExtendedLifetime(env) {} } // the store holds its environment weakly
        content.script([.success(.fetched(try catalogBody(version: version(days: 1)), etag: "e")),
                        .success(.notModified)])
        async let a: Void = store.refreshIfDue()
        async let b: Void = store.refreshIfDue()
        _ = await (a, b)
        #expect(content.requests.count == 1)
    }

    @Test func theCacheIsCheckedAgainAtLaunch() async throws {
        let (_, _, clock, env) = catalogStore()
        env.persistence.saveDocument(TrackerCatalogStore.Cached(body: try catalogBody(version: version(days: 1, 2)), etag: "e2",
                                                                checkedAt: clock.now()),
                                     key: TrackerCatalogStore.documentKey, at: clock.now())
        let relaunched = TrackerCatalogStore(env: env)
        await relaunched.load()
        #expect(relaunched.current.version == version(days: 1, 2) && relaunched.checkedAt == clock.now())
        #expect(!relaunched.isDue(at: clock.now()))

        // The rules tightened since (here: the body went bad): refused, dropped with its ETag.
        env.persistence.saveDocument(TrackerCatalogStore.Cached(body: Data("{\"schema_version\": 2}".utf8), etag: "e3"),
                                     key: TrackerCatalogStore.documentKey, at: clock.now())
        let again = TrackerCatalogStore(env: env)
        await again.load()
        #expect(again.current == .bundled && again.lastFailure == "cache schema 2")
        #expect(cached(env)?.body == nil && cached(env)?.etag == nil)
    }

    @Test func newestWinsAgainstTheBundledCopyAtLaunch() async throws {
        let (_, _, clock, env) = catalogStore()
        env.persistence.saveDocument(TrackerCatalogStore.Cached(body: try catalogBody(version: version(days: -1)), etag: "old"),
                                     key: TrackerCatalogStore.documentKey, at: clock.now())
        let store = TrackerCatalogStore(env: env)
        await store.load()
        #expect(store.current == .bundled)
    }

    @Test func copyDiagnosticsSaysWhichCopyAndWhy() async throws {
        let (store, content, _, env) = catalogStore()
        defer { withExtendedLifetime(env) {} } // the store holds its environment weakly
        #expect(store.diagnosticLine == "catalog bundled \(bundled) etag - checked - failure -")
        content.script([.failure(URLError(.notConnectedToInternet))])
        await store.refreshIfDue()
        #expect(store.diagnosticLine == "catalog bundled \(bundled) etag - checked - failure offline")
    }
}

/// Serves replies by URL and records what it saw (`WebContentSource`'s own session).
final class WebContentStub: URLProtocol {
    struct Reply {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    static func serve(_ r: [String: Reply]) {
        lock.withLock { replies = r; seen = [] }
    }

    static var requests: [URLRequest] { lock.withLock { seen } }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let reply = Self.lock.withLock { () -> Reply in
            Self.seen.append(request)
            return Self.replies[url.absoluteString] ?? Reply(status: 404)
        }
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                             headerFields: reply.headers) else { return }
        if (300..<400).contains(reply.status), let location = reply.headers["Location"], let next = URL(string: location) {
            // The session asks its delegate; followed, this load ends here and a new one starts.
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: next), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Tracker catalog: fetching from ryftapp.de", .serialized)
struct WebContentSourceTests {
    private let file = "https://ryftapp.de/trackers.json"

    private func source() -> WebContentSource {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WebContentStub.self]
        return WebContentSource(configuration: config)
    }

    @Test func twoHundredBringsTheBodyAndItsETag() async throws {
        WebContentStub.serve([file: .init(status: 200, headers: ["ETag": #"W/"5f2""#], body: Data("{}".utf8))])
        let answer = try await source().fetch("trackers.json", ifNoneMatch: nil, maxBytes: 1_000)
        #expect(answer == .fetched(Data("{}".utf8), etag: #"W/"5f2""#))
        let request = try #require(WebContentStub.requests.first)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil && request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func theETagGoesOutAnd304IsNotModified() async throws {
        WebContentStub.serve([file: .init(status: 304)])
        let answer = try await source().fetch("trackers.json", ifNoneMatch: "e1", maxBytes: 1_000)
        #expect(answer == .notModified)
        #expect(WebContentStub.requests.first?.value(forHTTPHeaderField: "If-None-Match") == "e1")
    }

    @Test func aRedirectWithinRyftappIsFollowed() async throws {
        let moved = "https://ryftapp.de/content/trackers.json"
        WebContentStub.serve([file: .init(status: 302, headers: ["Location": moved]),
                              moved: .init(status: 200, body: Data("{}".utf8))])
        let answer = try await source().fetch("trackers.json", ifNoneMatch: nil, maxBytes: 1_000)
        #expect(answer == .fetched(Data("{}".utf8), etag: nil))
        #expect(WebContentStub.requests.map { $0.url?.absoluteString } == [file, moved])
    }

    @Test func aRedirectAnywhereElseIsNot() async throws {
        WebContentStub.serve([file: .init(status: 302, headers: ["Location": "https://example.com/trackers.json"])])
        await #expect(throws: ContentError.http(302)) {
            try await source().fetch("trackers.json", ifNoneMatch: nil, maxBytes: 1_000)
        }
        #expect(WebContentStub.requests.map { $0.url?.host } == ["ryftapp.de"])
        #expect(!WebContentSource.allows(URL(string: "http://ryftapp.de/trackers.json")))
        #expect(!WebContentSource.allows(URL(string: "https://ryftapp.de:8443/trackers.json")))
        #expect(!WebContentSource.allows(URL(string: "https://ryftapp.de.example.com/trackers.json")))
    }

    @Test func readingStopsPastTheLimit() async {
        WebContentStub.serve([file: .init(status: 200, body: Data(repeating: 0x20, count: 2_000))])
        await #expect(throws: ContentError.tooLarge) {
            try await source().fetch("trackers.json", ifNoneMatch: nil, maxBytes: 1_000)
        }
    }

    @Test func otherStatusesThrow() async {
        WebContentStub.serve([file: .init(status: 404)])
        await #expect(throws: ContentError.http(404)) {
            try await source().fetch("trackers.json", ifNoneMatch: nil, maxBytes: 1_000)
        }
    }
}

@Suite("Tracker selection: per account")
@MainActor
struct TrackerSelectionTests {
    @Test func savedForTheAccountInPickerOrderKnownIdsOnce() {
        let env = AppEnvironment.test()
        let store = TrackerSelectionStore(env: env)
        #expect(store.selection == nil && store.trackers.isEmpty) // nothing chosen yet

        store.set(["oura", "garmin", "made_up", "garmin"])

        #expect(store.trackers == ["garmin", "oura"])
        #expect(store.selection?.account == env.auth.accountID)
        #expect(TrackerSelectionStore(env: env).trackers == ["garmin", "oura"]) // stored: a relaunch has it
    }

    @Test func justMyIPhoneIsOnItsOwn() {
        let store = TrackerSelectionStore(env: .test())
        store.set(["garmin", "iphone"])
        #expect(store.trackers == ["iphone"])

        #expect(TrackerSelectionStore.toggled("iphone", in: ["garmin", "oura"]) == (["iphone"], true))
        #expect(TrackerSelectionStore.toggled("iphone", in: []) == (["iphone"], false))
        #expect(TrackerSelectionStore.toggled("oura", in: ["iphone"]) == (["oura"], false))
        #expect(TrackerSelectionStore.toggled("other", in: ["garmin"]) == (["garmin", "other"], false)) // Other combines
        #expect(TrackerSelectionStore.toggled("garmin", in: ["garmin", "oura"]) == (["oura"], false))
    }

    @Test func anotherAccountsChoiceIsNeverRead() {
        let env = AppEnvironment.test()
        env.persistence.saveDocument(TrackerSelection(account: "someone-else", trackers: ["garmin"], updatedAt: .now),
                                     key: TrackerSelectionStore.documentKey, at: .now)
        let store = TrackerSelectionStore(env: env)
        #expect(store.selection == nil && store.trackers.isEmpty)
    }

    @Test func idsTheCatalogNoLongerHasAreDropped() throws {
        let env = AppEnvironment.test()
        let account = try #require(env.auth.accountID)
        env.persistence.saveDocument(TrackerSelection(account: account, trackers: ["garmin", "retired_band"], updatedAt: .now),
                                     key: TrackerSelectionStore.documentKey, at: .now)
        #expect(TrackerSelectionStore(env: env).trackers == ["garmin"])
    }

    @Test func signOutLeavesNothing() async {
        let env = AppEnvironment.test()
        let store = TrackerSelectionStore(env: env)
        store.set(["garmin"])

        env.persistence.wipe() // AuthService's wipe on sign-out
        await env.auth.signOut()
        store.accountChanged() // RyftApp, on the account change

        #expect(store.selection == nil && store.trackers.isEmpty)
        store.set(["oura"]) // signed out: nobody to save it for
        #expect(store.selection == nil)
        #expect(env.persistence.document(TrackerSelection.self, key: TrackerSelectionStore.documentKey) == nil)
    }

    @Test func guidesDoneOrPutOffFollowTheChoice() {
        let store = TrackerSelectionStore(env: .test())
        store.set(["garmin", "oura"])
        store.markLater("garmin")
        store.markSetUp("oura")
        #expect(store.isLater("garmin") && store.selection?.setUp == ["oura"])
        store.markSetUp("garmin")
        #expect(!store.isLater("garmin") && store.selection?.setUp == ["oura", "garmin"])
        store.markLater("polar") // not chosen: nothing
        store.set(["oura"])
        #expect(store.selection?.setUp == ["oura"] && store.selection?.later == [])
    }

    @Test func demoDataKeepsItsChoiceInMemory() {
        let env = AppEnvironment.preview()
        let store = TrackerSelectionStore(env: env)
        #expect(store.trackers == ["apple_watch"])
        store.set(["oura"])
        #expect(store.trackers == ["oura"])
        #expect(env.persistence.document(TrackerSelection.self, key: TrackerSelectionStore.documentKey) == nil)
    }

    @Test func onlyTrackersWithTheirOwnAppNeedSetup() throws {
        let catalog = TrackerCatalog.bundled
        let needing = catalog.trackers.filter(TrackerSelectionStore.needsSetup).map(\.id)
        #expect(!needing.contains("apple_watch") && !needing.contains("iphone"))
        #expect(needing.contains("garmin") && needing.contains("samsung_galaxy_watch") && needing.contains("other"))
    }
}

/// The setup card's features line for every tracker in the catalog (R1's matrices, design.md §8, lead's decision 10).
@Suite("Tracker setup: what reaches RYFT means which features")
struct RyftFeaturesTests {
    private static func list(_ items: [String]) -> String { items.formatted(.list(type: .and)) }
    private static let all = list(["Strain", "Sleep", "Recovery", "Readiness"])

    @Test(arguments: [
        ("apple_watch", "Strain\u{00A0}✓ · Sleep\u{00A0}✓ · Recovery\u{00A0}✓ · Readiness\u{00A0}✓"),
        // Garmin Connect shares resting heart rate (one value a day, at midnight; a device check): Recovery fills,
        // and Readiness waits for HRV until the platform calibrates without it.
        ("garmin", "Strain\u{00A0}✓ · Sleep\u{00A0}✓ · Recovery from \(list(["resting heart rate", "sleep"])), no HRV · Readiness needs HRV, which Garmin Connect doesn't share"),
        ("oura", "Strain\u{00A0}✓ · Sleep\u{00A0}✓ · Recovery needs resting heart rate, which Oura doesn't share · Readiness needs \(list(["resting heart rate", "HRV"])), which Oura doesn't share"),
        ("polar", "Sleep\u{00A0}✓ · Strain in part · Recovery needs resting heart rate, which Polar Flow doesn't share · Readiness needs \(list(["resting heart rate", "HRV"])), which Polar Flow doesn't share"),
        ("suunto", "Not confirmed yet: \(all)"),
        ("coros", "Strain\u{00A0}✓ · Sleep\u{00A0}✓ · Recovery needs resting heart rate, which COROS doesn't share · Readiness needs \(list(["resting heart rate", "HRV"])), which COROS doesn't share"),
        ("withings", "Strain in part · Not confirmed yet: \(list(["Sleep", "Recovery", "Readiness"]))"),
        ("amazfit", "Not confirmed yet: \(all)"),
        ("ultrahuman", "Strain\u{00A0}✓ · Not confirmed yet: \(list(["Sleep", "Recovery", "Readiness"]))"),
        ("fitbit", "Strain\u{00A0}✓ · Sleep\u{00A0}✓ · Recovery from \(list(["resting heart rate", "sleep", "breathing rate"])), no HRV · Readiness needs HRV, which Google Health doesn't share"),
        ("samsung_galaxy_watch", "Steps\u{00A0}✓ · Sleep, Strain, Recovery and Readiness stay empty without data from your tracker"),
        ("iphone", "Steps\u{00A0}✓ · Sleep, Strain, Recovery and Readiness stay empty: they need heart rate and sleep from a watch or ring."),
    ])
    func line(id: String, expected: String) throws {
        let tracker = try #require(TrackerCatalog.bundled.tracker(id))
        #expect(RyftFeatures.line(for: tracker)?.text == expected)
    }

    @Test func otherPromisesNothing() throws {
        #expect(RyftFeatures.line(for: try #require(TrackerCatalog.bundled.tracker("other"))) == nil)
        #expect(TrackerCatalog.bundled.trackers.count == 13)
    }

    /// Once the platform derives resting heart rate from overnight heart rate, Garmin's Recovery fills without HRV.
    /// Once the platform derives resting heart rate from overnight heart rate, Oura's Recovery fills without it.
    @Test func derivedRestingHeartRateUnblocksRecovery() throws {
        let oura = try #require(TrackerCatalog.bundled.tracker("oura"))
        #expect(!RyftFeatures.restingHRFromHeartRate) // until API.md documents it
        #expect(RyftFeatures.line(for: oura, derivedRestingHR: true)?.text
                == "Strain\u{00A0}✓ · Sleep\u{00A0}✓ · Recovery from \(Self.list(["resting heart rate", "sleep", "breathing rate"])), no HRV · Readiness needs HRV, which Oura doesn't share")
    }

    /// Once the platform calibrates from resting-heart-rate nights, Readiness comes without HRV.
    @Test func baselinesWithoutHRVBringReadiness() throws {
        let garmin = try #require(TrackerCatalog.bundled.tracker("garmin"))
        #expect(!RyftFeatures.baselinesWithoutHRV) // until API.md documents it
        #expect(RyftFeatures.line(for: garmin, baselinesWithoutHRV: true)?.text
                == "Strain\u{00A0}✓ · Sleep\u{00A0}✓ · Recovery from \(Self.list(["resting heart rate", "sleep"])), no HRV · Readiness from the same")
    }

    @Test func missingSignalsAreNamedNeverCrossed() throws {
        let garmin = try #require(TrackerCatalog.bundled.tracker("garmin"))
        var caps = garmin.capabilities
        caps[.heartRate] = .no
        caps[.sleep] = .no
        caps[.restingHR] = .no
        let blind = Tracker(id: "garmin", name: "Garmin", form: .watch, appName: "Garmin Connect", integration: .vendorApp,
                            identity: garmin.identity, appStoreID: nil, capabilities: caps, notes: [:], setup: garmin.setup,
                            habits: garmin.habits, limits: garmin.limits, help: nil, checked: garmin.checked)
        let line = try #require(RyftFeatures.line(for: blind))
        #expect(line.text == [
            "Strain needs heart rate, which Garmin Connect doesn't share",
            "Sleep needs sleep, which Garmin Connect doesn't share",
            "Recovery needs \(Self.list(["sleep", "resting heart rate"])), which Garmin Connect doesn't share",
            "Readiness needs \(Self.list(["sleep", "resting heart rate", "HRV"])), which Garmin Connect doesn't share",
        ].joined(separator: " · "))
        #expect(!line.text.contains("✗"))
    }

    @Test func voiceOverSaysYes() throws {
        let watch = try #require(TrackerCatalog.bundled.tracker("apple_watch"))
        #expect(RyftFeatures.line(for: watch)?.spoken == "Strain, yes. Sleep, yes. Recovery, yes. Readiness, yes")
    }

    @Test func theCollapsedCardsVerdict() throws {
        let catalog = TrackerCatalog.bundled
        #expect(RyftFeatures.verdict(for: try #require(catalog.tracker("garmin"))) == "Heart rate, sleep, workouts · no HRV")
        #expect(RyftFeatures.verdict(for: try #require(catalog.tracker("samsung_galaxy_watch"))) == "Can't be read on iPhone today")
        #expect(RyftFeatures.verdict(for: try #require(catalog.tracker("suunto"))) == "Not confirmed yet")
    }
}

@Suite("Tracker setup: Devices & sync, diagnostics")
@MainActor
struct DevicesAndDiagnosticsTests {
    private func profile(flag: Bool) -> ProfileViewModel {
        let state = AppState(env: .test(flags: [.devicesSetup: flag]))
        let sync = SyncService(env: state.env)
        return ProfileViewModel(state: state, sync: sync,
                                coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: state.env.clock))
    }

    @Test func copyDiagnosticsHasTheCatalogLine() {
        #expect(profile(flag: true).syncDetails.diagnostics.contains("catalog bundled \(TrackerCatalog.bundled.version) etag -"))
    }

    @Test func seenInAppleHealthUsesRYFTsNames() {
        let state = AppState(env: .test())
        var user = MockData.user
        user.sources = [
            UserSource(name: "Connect", bundleId: "com.garmin.connect.mobile", kinds: [.hr, .sleep, .steps], lastSeen: .now),
            UserSource(name: "Tim's Apple Watch", bundleId: "com.apple.health.81E2", kinds: [.hrv], lastSeen: .now),
            UserSource(name: "Sleep Cycle", bundleId: "com.lexwarelabs.goodmorning", kinds: [.sleep], lastSeen: .now),
        ]
        state.user = user
        let model = DevicesViewModel(state: state, selection: TrackerSelectionStore(env: state.env))

        #expect(model.sources.map(\.name) == ["Garmin Connect", "Tim's Apple Watch", "Sleep Cycle"])
        #expect(model.sources.map(\.known) == [true, true, false]) // Apple's own devices aren't "unknown"
        let kinds = ["heart rate", "sleep", "steps"].formatted(.list(type: .and))
        #expect(model.sources.first?.kinds == "H" + kinds.dropFirst())
    }

    @Test func profileSummary() {
        let state = AppState(env: .test())
        let model = DevicesViewModel(state: state, selection: TrackerSelectionStore(env: state.env))
        #expect(model.summary == String(localized: "Not set"))
        model.save(["garmin", "oura", "polar"])
        #expect(model.summary == "Garmin · Oura · +1")
        model.selection.markLater("oura")
        #expect(model.status(of: model.trackers[1]) == String(localized: "Set up later"))
    }

    @Test func aReportCarriesTheTrackersIdsOnlyWithTheFlag() {
        let d = FeedbackPayload.diagnostics(requests: [], resources: [:], sync: FeedbackSync(), gates: [], flags: [:],
                                            trackers: ["garmin", "oura"], context: nil, locale: "de_DE")
        #expect(d["trackers"] == "garmin,oura" && FeedbackPayload.keys.isSuperset(of: d.keys))
        #expect(FeedbackPayload.diagnostics(requests: [], resources: [:], sync: FeedbackSync(), gates: [], flags: [:],
                                            trackers: [], context: nil, locale: "de_DE")["trackers"] == "-")
        #expect(FeedbackPayload.diagnostics(requests: [], resources: [:], sync: FeedbackSync(), gates: [], flags: [:],
                                            context: nil, locale: "de_DE")["trackers"] == nil)

        let on = profile(flag: true)
        on.devices.save(["garmin"])
        #expect(on.report.includesTrackers)
        on.report.message = "Steps look low."
        #expect(on.report.payload().diagnostics?["trackers"] == "garmin")
        on.report.includeDiagnostics = false
        #expect(on.report.payload().diagnostics == nil)

        let off = profile(flag: false)
        #expect(!off.report.includesTrackers && off.report.payload().diagnostics?["trackers"] == nil)
    }
}

@Suite("Tracker catalog: crash guard, the flag, what's kept")
@MainActor
struct TrackerCatalogGuardTests {
    private func cached(_ env: AppEnvironment) -> TrackerCatalogStore.Cached? {
        env.persistence.document(TrackerCatalogStore.Cached.self, key: TrackerCatalogStore.documentKey)
    }

    /// The last run died decoding a copy (its marker is left): the cache goes unread, and that body is refused
    /// unread from then on; another one is decoded as ever.
    @Test func aDecodeThatDiedIsNeverRepeated() async throws {
        let (store, content, clock, env) = catalogStore()
        defer { withExtendedLifetime(env) {} }
        let poison = try catalogBody(version: version(days: 1))
        let hash = TrackerCatalogStore.hash(poison)
        env.persistence.saveDocument(TrackerCatalogStore.Cached(body: poison, etag: "p1", checkedAt: clock.now()),
                                     key: TrackerCatalogStore.documentKey, at: clock.now())
        let marker = env.contentDirectory.appendingPathComponent(TrackerCatalogStore.markerName)
        TrackerCatalogStore.mark(marker, hash: hash)

        await store.load()

        #expect(store.current == .bundled && store.lastFailure == "crashed")
        #expect(cached(env)?.body == nil && cached(env)?.etag == nil)
        let refusedFile = env.contentDirectory.appendingPathComponent(TrackerCatalogStore.refusedName)
        #expect(TrackerCatalogStore.refusedHashes(at: refusedFile) == [hash])
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(!store.isDue(at: clock.now())) // a failure: an hour's wait

        content.script([.success(.fetched(poison, etag: "p2")),
                        .success(.fetched(try catalogBody(version: version(days: 1, 2)), etag: "f1"))])
        clock.advance(by: .seconds(3_601))
        await store.refreshIfDue()
        #expect(store.current == .bundled && store.lastFailure == "crashed" && content.requests.map(\.etag) == [nil])
        clock.advance(by: .seconds(3_601))
        await store.refreshIfDue()
        #expect(store.current.version == version(days: 1, 2) && store.lastFailure == nil)
        #expect(!FileManager.default.fileExists(atPath: marker.path)) // gone after every decode
    }

    /// Sign-out wipes the cache, never the refused hashes: a body that crashed the decoder stays refused unread.
    @Test func aRefusedBodyStaysRefusedAfterSignOut() async throws {
        let (store, content, _, env) = catalogStore()
        defer { withExtendedLifetime(env) {} }
        let poison = try catalogBody(version: version(days: 1))
        TrackerCatalogStore.mark(env.contentDirectory.appendingPathComponent(TrackerCatalogStore.markerName),
                                 hash: TrackerCatalogStore.hash(poison))
        await store.load()
        #expect(store.lastFailure == "crashed")

        env.persistence.wipe() // sign-out
        store.accountChanged()
        let relaunched = TrackerCatalogStore(env: env) // and a relaunch: nothing in memory
        content.script([.success(.fetched(poison, etag: "p"))])
        await relaunched.refreshIfDue()

        #expect(content.requests.count == 1 && relaunched.lastFailure == "crashed" && relaunched.current == .bundled)
        #expect(TrackerCatalogStore.merged(["a", "b"], ["b", "c"]) == ["a", "b", "c"])
        #expect(TrackerCatalogStore.merged((0..<10).map(String.init), []).count == TrackerCatalogStore.maxRefused)
    }

    @Test func withTheFlagOffTheBundledCopyServesAndNothingIsRead() async throws {
        let (store, content, clock, env) = catalogStore(flag: false)
        defer { withExtendedLifetime(env) {} }
        env.persistence.saveDocument(TrackerCatalogStore.Cached(body: try catalogBody(version: version(days: 1)), etag: "e1",
                                                                checkedAt: clock.now()),
                                     key: TrackerCatalogStore.documentKey, at: clock.now())
        await store.load()
        await store.refreshIfDue()
        #expect(store.current == .bundled && store.checkedAt == nil && content.requests.isEmpty)

        (env.flags as? StaticFlags)?.overrides[.devicesSetup] = true
        await store.load()
        #expect(store.current.version == version(days: 1)) // on: the cache, checked
        (env.flags as? StaticFlags)?.overrides[.devicesSetup] = false
        #expect(store.current == .bundled && store.origin == .bundled(TrackerCatalog.bundled.version))
    }

    @Test func onlyAPlainETagIsKept() async throws {
        #expect(TrackerCatalogStore.storable(#"W/"5f2-abc""#) == #"W/"5f2-abc""#)
        #expect(TrackerCatalogStore.storable("a b") == nil && TrackerCatalogStore.storable("café") == nil)
        #expect(TrackerCatalogStore.storable(String(repeating: "a", count: 129)) == nil)
        #expect(TrackerCatalogStore.storable("") == nil && TrackerCatalogStore.storable(nil) == nil)

        let (store, content, clock, env) = catalogStore()
        defer { withExtendedLifetime(env) {} }
        content.script([.success(.fetched(try catalogBody(version: version(days: 1)), etag: "two words")),
                        .success(.notModified)])
        await store.refreshIfDue()
        clock.advance(by: .seconds(25 * 3_600))
        await store.refreshIfDue()
        #expect(store.current.version == version(days: 1) && content.requests.map(\.etag) == [nil, nil])
    }

    @Test func failuresCarryNoOutsideText() {
        let text = TrackerCatalogStore.describe(CatalogError.invalid(rule: "text.markup",
                                                                     path: "trackers[1].<b>x</b> https://x.example/?q=1"))
        #expect(text.hasPrefix("invalid text.markup at trackers[1].") && !text.contains("<") && !text.contains("/"))
        #expect(!text.contains(":") && TrackerCatalogStore.clean(String(repeating: "a", count: 200)).count == 80)
    }

    @Test func aClockThatWentBackDoesntHoldTheCheckBack() async {
        let (store, content, clock, env) = catalogStore()
        defer { withExtendedLifetime(env) {} }
        content.script([.success(.notModified)])
        await store.refreshIfDue()
        #expect(!store.isDue(at: clock.now()))
        #expect(store.isDue(at: clock.now().addingTimeInterval(-3_600))) // "checked" an hour from now: stale
    }

    @Test func aForcedReloadMakesItsOwnAttempt() async {
        let (store, content, _, env) = catalogStore()
        defer { withExtendedLifetime(env) {} }
        content.script([.success(.notModified), .success(.notModified)])
        let check = Task { await store.refreshIfDue() }
        await Task.yield() // the check is in flight
        await store.refreshIfDue(force: true)
        await check.value
        #expect(content.requests.count == 2)
    }

    @Test func anotherAccountStartsFromTheBundledCopy() async throws {
        let (store, content, _, env) = catalogStore()
        defer { withExtendedLifetime(env) {} }
        content.script([.success(.fetched(try catalogBody(version: version(days: 1)), etag: "e1"))])
        await store.refreshIfDue()
        #expect(store.current.version == version(days: 1))
        env.persistence.wipe()
        store.accountChanged()
        #expect(store.current == .bundled && store.checkedAt == nil && store.lastFailure == nil)
    }
}

@Suite("Demo data's flags stay demo's")
@MainActor
struct DemoFlagsTests {
    private let demoConfig = RemoteConfig(flags: [FeatureFlag.devicesSetup.rawValue: true], evaluatedAt: .now,
                                          ttlSec: 21_600, privacyPolicyVersion: nil, privacyPolicyUrl: nil)

    @Test func demoOnFetchDemoOffTheFlagIsOff() async {
        let store = TrainStore(inMemory: true)
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let flags = FlagStore(store: store, defaults: defaults, account: "a", demo: true)
        let config = demoConfig
        await FeatureFlags(flags: flags, clock: TestClock()) { config }.refresh(force: true)
        #expect(flags.isOn(.devicesSetup))

        flags.setDemo(false)

        #expect(!flags.isOn(.devicesSetup) && flags.source(of: .devicesSetup) == .compiled)
        #expect(store.document(FlagStore.Cached.self, key: FlagStore.cacheKey("a")) == nil)
        #expect(!FlagStore(store: store, defaults: defaults, account: "a").isOn(.devicesSetup)) // relaunched as "a"
        flags.setDemo(true)
        #expect(flags.isOn(.devicesSetup)) // demo's own cache
    }

    @Test func anAnswerAskedForInDemoModeIsDroppedAfterIt() {
        let flags = FlagStore(store: TrainStore(inMemory: true),
                              defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard,
                              account: "a", demo: true)
        let asked = flags.generation
        flags.setDemo(false)
        flags.apply(demoConfig, fetchedAt: .now, generation: asked)
        #expect(!flags.isOn(.devicesSetup))
    }
}

@Suite("Tracker setup: Today, tiles, glyphs")
@MainActor
struct TrackerSetupScreensTests {
    @Test func todaysNightHintLooksAtWhatYouWear() {
        let env = AppEnvironment.test(flags: [.devicesSetup: true])
        let store = TrackerSelectionStore(env: env)
        let garmin = SourceFreshness(source: "Connect", bundleID: "com.garmin.connect.mobile", newest: .now)
        let oura = SourceFreshness(source: "Oura", bundleID: "com.ouraring.oura", newest: .now)
        let phone = SourceFreshness(source: "Tim's iPhone", bundleID: "com.apple.health.3F0A", newest: .now,
                                    deviceModel: "iPhone")
        let unknown = SourceFreshness(source: "Sleep Cycle", bundleID: "com.lexwarelabs.goodmorning", newest: .now)
        let all = [garmin, oura, phone, unknown]
        #expect(store.worn(all) == all) // nothing chosen: every source

        // Only a source matched to a tracker that wasn't chosen goes: an unchosen Oura doesn't cancel Garmin's hint.
        store.set(["garmin"])
        #expect(store.worn(all) == [garmin, phone, unknown])
        store.set(["iphone"]) // just the iPhone: no tracker's source is a candidate
        #expect(store.worn([garmin, oura, phone]) == [phone])
        (env.flags as? StaticFlags)?.overrides[.devicesSetup] = false
        #expect(store.worn(all) == all)
    }

    /// T1's rule: an Apple source without a device model matches no tracker and is still a candidate.
    @Test func appleSourcesWithoutADeviceModelStayCandidates() throws {
        let env = AppEnvironment.test(flags: [.devicesSetup: true])
        let store = TrackerSelectionStore(env: env)
        let now = Date.now
        // The Apple Watch chosen, its source without a model: the night hint keeps its candidate.
        let watch = SourceFreshness(source: "Tim's Apple Watch", bundleID: "com.apple.health.81E2",
                                    newest: now.addingTimeInterval(-9 * 3_600))
        store.set(["apple_watch"])
        #expect(store.worn([watch]) == [watch])
        // Garmin chosen, and an unknown Apple source wrote at 07:05: it stays, so it still counts as the night's
        // evidence (T1 shows no hint then).
        let garmin = SourceFreshness(source: "Connect", bundleID: "com.garmin.connect.mobile",
                                     newest: now.addingTimeInterval(-10 * 3_600))
        let morning = try #require(Calendar.current.date(bySettingHour: 7, minute: 5, second: 0, of: now))
        let apple = SourceFreshness(source: "Apple", bundleID: "com.apple.health.9C11", newest: morning)
        store.set(["garmin"])
        #expect(store.worn([garmin, apple]) == [garmin, apple])
    }

    @Test func nothingChosenReadsNoCatalog() {
        let store = TrackerSelectionStore(env: .test())
        #expect(store.trackers.isEmpty && store.selection == nil)
    }

    @Test func tileNamesNeverBreakMidWord() {
        let names = TrackerCatalog.bundled.trackers.map(\.title)
        #expect(TrackerPickerGrid.fitsTwoColumns(names, width: 1_000, size: .large))
        #expect(!TrackerPickerGrid.fitsTwoColumns(names, width: 200, size: .large)) // a narrow screen: one column
        #expect(!TrackerPickerGrid.fitsTwoColumns(names, width: 1_000, size: .accessibility1))
        #expect(TrackerPickerGrid.widestWord(["Ultrahuman"], size: .xxxLarge) > TrackerPickerGrid.widestWord(["Ultrahuman"], size: .large))
    }

    @Test func applesGlyphsOnlyForApplesDevicesByTheirIds() throws {
        let catalog = TrackerCatalog.bundled
        #expect(catalog.tracker("apple_watch")?.symbol == "applewatch" && catalog.tracker("iphone")?.symbol == "iphone")
        #expect(catalog.trackers.filter { !["apple_watch", "iphone"].contains($0.id) }
            .allSatisfy { !["applewatch", "iphone"].contains($0.symbol) })
        let g = try #require(catalog.tracker("garmin"))
        let phoneShaped = Tracker(id: "pocket_band", name: "Pocket", form: .phone, appName: "Pocket", integration: .vendorApp,
                                  identity: .none, appStoreID: nil, capabilities: g.capabilities, notes: [:], setup: g.setup,
                                  habits: g.habits, limits: g.limits, help: nil, checked: g.checked)
        #expect(phoneShaped.symbol != "iphone" && !phoneShaped.isJustIPhone)
        #expect(RyftFeatures.line(for: phoneShaped)?.text.contains("watch or ring") == false)
    }
}
