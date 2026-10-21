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
/// work on another executor gets a thread.
@MainActor
func eventually(timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
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
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock)

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
