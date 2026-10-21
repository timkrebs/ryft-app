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
/// actor at its start, which a CI runner took 12 s to work through.
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
        let coordinator = TrainCoordinator(sync: trainSync, library: TrainLibrary.preview(store: store))
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
