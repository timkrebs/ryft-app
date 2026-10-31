import Foundation
import HealthKit
import Testing
@testable import Ryft

/// 09:12 on 2026-10-19 (local), as in the Check sync suite.
private let now = Calendar.current.date(bySettingHour: 9, minute: 12, second: 0,
                                        of: Date(timeIntervalSince1970: 1_792_400_000)) ?? .now
private let catalog = TrackerCatalog.bundled
private let day: TimeInterval = 86_400

/// Catalog trackers by id (`catalogHasEveryTrackerTheseTestsPick` proves none is missing).
private func picked(_ ids: String...) -> [Tracker] { ids.compactMap(catalog.tracker) }

private func build(_ samples: [SourceSample], visible: Set<HealthStream> = Set(TrackerCheckRules.streams),
                   tally: SourceTally? = nil, received: [UserSource]? = nil) -> SourceDetection {
    SourceDetection.build(samples: samples, visible: visible, tally: tally, received: received, catalog: catalog, now: now)
}

private func row(_ detection: SourceDetection, _ ref: SourceRef) -> DetectedSource? {
    detection.sources.first { $0.ref.bundleID == ref.bundleID && $0.ref.name == ref.name }
}

private func sample(_ stream: HealthStream, _ source: SourceRef, ago: TimeInterval, stages: Bool? = nil) -> SourceSample {
    SourceSample(stream: stream, source: source, newest: now.addingTimeInterval(-ago), hasStages: stages)
}

@Suite("Source detection: the rules")
struct SourceDetectionTests {
    @Test func aGarminLikeSourceWithHeartRateAndSleepButNoHRVGetsTheNoHRVNote() throws {
        let detection = build(MockHealthStore.garminLike(now: now).samples)
        let note = try #require(row(detection, .mockGarmin)?.noHRV)
        #expect(note.restingHR)
        #expect(note.limit?.en == "Garmin Connect doesn't send HRV, breathing rate or blood oxygen to Apple Health.")
        #expect(note.limit?.de == "Garmin Connect sendet HRV, Atemfrequenz oder Blutsauerstoff nicht an Apple Health.")
        #expect(detection.withoutHRV(among: picked("garmin", "apple_watch")).map(\.id) == ["garmin"])

        // Without resting heart rate the note is the catalog's sentence alone (decision 5.5).
        let noResting = row(build(MockHealthStore.garminLike(now: now, restingHR: false).samples), .mockGarmin)
        #expect(noResting?.noHRV == DetectedSource.NoHRV(restingHR: false, limit: note.limit))
        // Resting heart rate older than the window doesn't count.
        let old = MockHealthStore.garminLike(now: now, restingHR: false).samples
            + [sample(.quantity(.restingHR), .mockGarmin, ago: 7 * day + 60)]
        #expect(row(build(old), .mockGarmin)?.noHRV?.restingHR == false)

        // Data beats the catalog: HRV that arrives needs no note.
        let withHRV = build(MockHealthStore.garminLike(now: now).samples + [sample(.quantity(.hrvSDNN), .mockGarmin, ago: 3_600)])
        #expect(row(withHRV, .mockGarmin)?.noHRV == nil)
        #expect(withHRV.withoutHRV(among: picked("garmin")).isEmpty)
        // No heart rate, no note (it says "writes heart rate but no HRV").
        let sleepOnly = build([sample(.sleep, .mockGarmin, ago: 3_600, stages: true)])
        #expect(row(sleepOnly, .mockGarmin)?.noHRV == nil)
        // An Apple Watch shares HRV; the iPhone writing heart rate (AirPods) gets no note either.
        let watch = build(MockHealthStore.appleWatchLike(now: now).samples + [sample(.quantity(.heartRate), .mockPhone, ago: 60)])
        #expect(watch.sources.compactMap(\.noHRV) == [])
        // A tracker whose HRV is unverified gets no note.
        let suunto = SourceRef(name: "Suunto", bundleID: "com.sports-tracker.suunto.iphone", deviceModel: nil)
        #expect(build([sample(.quantity(.heartRate), suunto, ago: 60)]).sources.compactMap(\.noHRV) == [])
    }

    /// Lead correction to decision 5.5: "…recovery uses resting heart rate and sleep" only when the source wrote both
    /// in the window; otherwise the catalog's sentence about HRV; without one, the plain "doesn't share HRV".
    @Test func noteBNamesRecoveryInputsOnlyWhenTheSourceWroteRestingHeartRateAndSleep() throws {
        let both = try #require(row(build(MockHealthStore.garminLike(now: now).samples), .mockGarmin))
        #expect(both.noHRVWording == .recoveryInputs)

        let limit = try #require(both.noHRV?.limit)
        // Resting heart rate but no sleep from Garmin (the iPhone's in-bed night isn't Garmin's).
        let noSleep = row(build(MockHealthStore.garminLike(now: now, sleepOff: true).samples), .mockGarmin)
        #expect(noSleep?.noHRV?.restingHR == true && noSleep?.noHRVWording == .limit(limit))
        // Sleep but no resting heart rate.
        let noResting = row(build(MockHealthStore.garminLike(now: now, restingHR: false).samples), .mockGarmin)
        #expect(noResting?.noHRVWording == .limit(limit))
        // A tracker the catalog has no HRV sentence for: the plain wording.
        let signals: [TrackerSignal: Date] = [.heartRate: now, .restingHR: now]
        #expect(DetectedSource.noHRVWording(.init(restingHR: true, limit: nil), signals: signals) == .plain)
        #expect(DetectedSource.noHRVWording(.init(restingHR: true, limit: nil), signals: signals.merging([.sleep: now]) { $1 })
            == .recoveryInputs)
        // The flag alone isn't enough: the signals must say both.
        #expect(DetectedSource.noHRVWording(.init(restingHR: true, limit: limit), signals: [.heartRate: now, .sleep: now])
            == .limit(limit))
        // No note B, no wording (an Apple Watch shares HRV).
        let watch = build(MockHealthStore.appleWatchLike(now: now).samples)
        #expect(watch.sources.compactMap(\.noHRVWording).isEmpty)
    }

    @Test func catalogHasEveryTrackerTheseTestsPick() {
        let ids = ["garmin", "oura", "iphone", "apple_watch", "polar", "other", "samsung_galaxy_watch"]
        #expect(ids.filter { catalog.tracker($0) == nil } == [])
    }

    @Test func theHRVLimitIsTheCatalogsSentenceAboutHRV() {
        #expect(picked("polar").first.flatMap(SourceDetection.hrvLimit)?.en
            == "Polar Flow doesn't send HRV, resting heart rate, sleep stages, breathing rate or blood oxygen.")
        #expect(picked("apple_watch").first.flatMap(SourceDetection.hrvLimit) == nil)
    }

    @Test func aPickedTrackerSilentForSevenDaysIsListed() {
        let trackers = picked("garmin", "oura", "iphone")
        let detection = build(MockHealthStore.garminLike(now: now).samples)
        #expect(detection.silent(among: trackers).map(\.id) == ["oura"])

        let silent = build(MockHealthStore.garminLike(now: now, silent: true).samples)
        #expect(silent.silent(among: trackers).map(\.id) == ["garmin", "oura"])

        // The window's edge: just inside is seen, just outside is silent.
        let inside = build([sample(.quantity(.heartRate), .mockGarmin, ago: 7 * day - 60)])
        let outside = build([sample(.quantity(.heartRate), .mockGarmin, ago: 7 * day + 60)])
        #expect(inside.silent(among: picked("garmin")).isEmpty)
        #expect(outside.silent(among: picked("garmin")).map(\.id) == ["garmin"])
        #expect(outside.sources.isEmpty)

        // Other and a tracker RYFT can't read on iPhone never get "nothing in 7 days".
        #expect(build([]).silent(among: picked("other", "samsung_galaxy_watch")).isEmpty)
        #expect(build([]).silent(among: picked("apple_watch")).map(\.id) == ["apple_watch"])
        // An Apple source that doesn't say which device: the watch isn't claimed silent.
        let bare = SourceRef(name: "Watch", bundleID: "com.apple.health.81E4", deviceModel: nil)
        let anonymous = build([sample(.quantity(.heartRate), bare, ago: 600)])
        #expect(anonymous.silent(among: picked("apple_watch", "garmin")).map(\.id) == ["garmin"])
    }

    @Test func theIPhoneOnlyWhenNothingElse() {
        #expect(build(MockHealthStore.garminLike(now: now).samples).trackerIDs == ["garmin"])
        #expect(build(MockHealthStore.garminLike(now: now, silent: true).samples).trackerIDs == ["iphone"])
        #expect(build(MockHealthStore.garminLike(now: now).samples + MockHealthStore.ouraLike(now: now).samples
                      + MockHealthStore.appleWatchLike(now: now).samples).trackerIDs == ["apple_watch", "garmin", "oura"])
        // Never Other: an unknown source alone pre-selects nothing.
        let unknown = SourceRef(name: "Sleep Cycle", bundleID: "com.lexwarelabs.goodmorning", deviceModel: nil)
        #expect(build([sample(.sleep, unknown, ago: 3_600)]).trackerIDs.isEmpty)
        #expect(build([]).trackerIDs.isEmpty)
        // 7 days, not Check sync's 48 h.
        #expect(build([sample(.quantity(.heartRate), .mockGarmin, ago: 5 * day)]).trackerIDs == ["garmin"])
    }

    @Test func ryftsOwnSourceIsNeverDetected() {
        let own = SourceRef(name: "RYFT", bundleID: Bundle.main.bundleIdentifier, deviceModel: nil)
        let widgets = SourceRef(name: "RYFT", bundleID: Bundle.main.bundleIdentifier.map { $0 + ".widgets" }, deviceModel: nil)
        let detection = build([sample(.workouts, own, ago: 3_600), sample(.workouts, widgets, ago: 60)])
        #expect(detection.sources.isEmpty && detection.trackerIDs.isEmpty)
        #expect(build([sample(.workouts, own, ago: 60)] + MockHealthStore.garminLike(now: now).samples).sources
            .map(\.displayName) == ["Tim's iPhone", "Garmin Connect"])
    }

    @Test func namesComeFromTheCatalog() throws {
        let unknown = SourceRef(name: "Sleep Cycle", bundleID: "com.lexwarelabs.goodmorning", deviceModel: nil)
        let detection = build(MockHealthStore.appleWatchLike(now: now).samples + MockHealthStore.garminLike(now: now).samples
                              + [sample(.sleep, unknown, ago: 2 * day)])
        #expect(row(detection, .mockGarmin)?.displayName == "Garmin Connect")
        #expect(row(detection, .mockGarmin)?.trackerID == "garmin")
        #expect(row(detection, .mockWatch)?.displayName == "Tim's Apple Watch")
        #expect(row(detection, .mockWatch)?.trackerID == "apple_watch")
        #expect(row(detection, .mockPhone)?.trackerID == "iphone")
        let other = try #require(row(detection, unknown))
        #expect(other.displayName == "Sleep Cycle" && other.trackerID == nil)
    }

    @Test func rowsAreNewestFirstWithTheirSignalsAndChipsInTheFixedOrder() throws {
        let detection = build(MockHealthStore.garminLike(now: now).samples)
        // The iPhone's steps (10 min ago) are newer than Garmin's heart rate (20 min ago).
        #expect(detection.sources.map(\.displayName) == ["Tim's iPhone", "Garmin Connect"])
        let garmin = try #require(row(detection, .mockGarmin))
        #expect(garmin.lastSeen == now.addingTimeInterval(-1_200))
        #expect(garmin.chips == [.heartRate, .sleep, .steps, .workouts, .restingHR])
        #expect(garmin.signals[.sleepStages] != nil && garmin.signals[.hrv] == nil)
        #expect(garmin.id == "com.garmin.connect.mobile")
        // The iPhone's in-bed night has no stages.
        let phone = try #require(row(detection, .mockPhone))
        #expect(phone.chips == [.sleep, .steps] && phone.signals[.sleepStages] == nil)
        #expect(DetectedSource.chipOrder == [.heartRate, .hrv, .sleep, .steps, .workouts])
        let watch = try #require(row(build(MockHealthStore.appleWatchLike(now: now).samples), .mockWatch))
        #expect(watch.chips == [.heartRate, .hrv, .sleep, .steps, .workouts, .restingHR, .respiratoryRate, .spo2])
        // A type nobody may read: the strong hint.
        #expect(build([], visible: []).mayNotRead && !detection.mayNotRead)
        #expect(detection.window == DateInterval(start: now.addingTimeInterval(-7 * day), end: now) && detection.at == now)
    }

    @Test func aSourceIsOneRowWhateverItsTypesSay() {
        // A vendor app whose types carry different device models (or none) is still one source.
        let a = SourceRef(name: "Connect", bundleID: "com.garmin.connect.mobile", deviceModel: nil)
        let b = SourceRef(name: "Connect", bundleID: "com.garmin.connect.mobile", deviceModel: "Forerunner")
        let detection = build([sample(.quantity(.heartRate), a, ago: 60), sample(.quantity(.steps), b, ago: 600)])
        #expect(detection.sources.count == 1)
        #expect(detection.sources.first?.ref.deviceModel == "Forerunner")
        // Without bundle ids, by name.
        let x = SourceRef(name: "Scale", bundleID: nil, deviceModel: nil)
        #expect(build([sample(.quantity(.steps), x, ago: 60), sample(.sleep, x, ago: 90)]).sources.map(\.id) == ["name:Scale"])
    }

    @Test func countIsNilUntilTheTallyCoversTheWindow() throws {
        let samples = MockHealthStore.garminLike(now: now).samples
        var tally = SourceTally()
        tally.add(page(30, .heartRate, from: .mockGarmin, ago: day), stream: .quantity(.heartRate), at: now.addingTimeInterval(-6 * day))
        tally.add(page(5, .activeEnergy, from: .mockGarmin, ago: day), stream: .quantity(.activeEnergy), at: now)
        let untallied = try #require(row(build(samples, tally: nil), .mockGarmin))
        #expect(untallied.count == nil)
        // Counting began 6 days ago: a week's number would be too low.
        let sixDays = try #require(row(build(samples, tally: tally), .mockGarmin))
        #expect(sixDays.count == nil)

        var week = tally
        week.reset(at: now.addingTimeInterval(-7 * day - 60))
        week.add(page(30, .heartRate, from: .mockGarmin, ago: day), stream: .quantity(.heartRate), at: now)
        week.add(page(4, .steps, from: .mockGarmin, ago: 2 * day), stream: .quantity(.steps), at: now)
        week.add(page(5, .activeEnergy, from: .mockGarmin, ago: day), stream: .quantity(.activeEnergy), at: now)
        // Active energy isn't a chip: not counted. The iPhone sent nothing RYFT counted: 0, not nil.
        #expect(row(build(samples, tally: week), .mockGarmin)?.count == .phone(34))
        #expect(row(build(samples, tally: week), .mockPhone)?.count == .phone(0))

        // A backfill from scratch with the tally on covers the window at once.
        var fresh = SourceTally()
        fresh.reset(at: now.addingTimeInterval(-3_600))
        fresh.add(page(12, .heartRate, from: .mockGarmin, ago: 3 * day), stream: .quantity(.heartRate), at: now)
        let midBackfill = try #require(row(build(samples, tally: fresh), .mockGarmin))
        #expect(midBackfill.count == nil)
        fresh.backfillFinished(startedAt: now.addingTimeInterval(-1_800))
        #expect(row(build(samples, tally: fresh), .mockGarmin)?.count == .phone(12))
    }

    @Test func receivedMatchesByBundleIDThenName() {
        let lastSeen = now.addingTimeInterval(-3_600)
        // Same name, another watch's bundle id: not this one.
        let otherWatch = UserSource(name: "Tim's Apple Watch", bundleId: "com.apple.health.0000", kinds: [.hr, .hrv],
                                    lastSeen: lastSeen)
        let garmin = UserSource(name: "Connect", bundleId: "COM.GARMIN.CONNECT.MOBILE", kinds: [.hr, .sleep, .steps],
                                lastSeen: lastSeen)
        let detection = build(MockHealthStore.garminLike(now: now).samples + MockHealthStore.appleWatchLike(now: now).samples,
                              received: [otherWatch, garmin])
        #expect(row(detection, .mockWatch)?.received == .notListed)
        #expect(row(detection, .mockGarmin)?.received == .kinds([.hr, .sleep, .steps], lastSeen: lastSeen))
        // By name only where a side has no bundle id.
        let noBundle = UserSource(name: "tim's iphone ", bundleId: nil, kinds: [.steps], lastSeen: lastSeen)
        #expect(SourceDetection.received(.mockPhone, in: [noBundle]) == .kinds([.steps], lastSeen: lastSeen))
        let scale = SourceRef(name: "Scale", bundleID: nil, deviceModel: nil)
        let scaleSource = UserSource(name: "Scale", bundleId: "com.example.scale", kinds: [.steps], lastSeen: lastSeen)
        #expect(SourceDetection.received(scale, in: [scaleSource]) == .kinds([.steps], lastSeen: lastSeen))
        // No platform answer, or one that lists nothing: unknown, never "not received".
        #expect(SourceDetection.received(.mockGarmin, in: nil) == .unknown)
        #expect(SourceDetection.received(.mockGarmin, in: []) == .unknown)
    }

    @Test func notReceivedNamesWhatHealthHasAndThePlatformLacks() {
        let lastSeen = now.addingTimeInterval(-3_600)
        // Resting heart rate is the platform's `hr`; workouts and sleep it lacks.
        let garmin = UserSource(name: "Connect", bundleId: "com.garmin.connect.mobile", kinds: [.hr, .steps], lastSeen: lastSeen)
        let detection = build(MockHealthStore.garminLike(now: now).samples, received: [garmin])
        #expect(row(detection, .mockGarmin)?.notReceived == [.sleep, .workouts])
        // Not listed at all: everything Health has from it.
        #expect(row(detection, .mockPhone)?.notReceived == [.sleep, .steps])
        #expect(row(build(MockHealthStore.garminLike(now: now).samples), .mockGarmin)?.notReceived == [])
        #expect(TrackerSignal.sleepStages.sourceKind == nil && TrackerSignal.restingHR.sourceKind == .hr)
    }
}

@Suite("Source detection: the sync's tally")
struct SourceTallyTests {
    @Test func countsPerSourceStreamAndLocalDay() {
        var tally = SourceTally()
        #expect(tally.since == nil && !tally.covers(DateInterval(start: now.addingTimeInterval(-7 * day), end: now)))
        tally.add(HealthDelta(), stream: .quantity(.heartRate), at: now)
        #expect(tally.since == nil) // an empty page starts nothing
        tally.add(page(3, .heartRate, from: .mockGarmin, ago: day), stream: .quantity(.heartRate), at: now)
        tally.add(page(2, .heartRate, from: .mockGarmin, ago: day), stream: .quantity(.heartRate), at: now)
        let night = HealthDelta(sleep: [SleepSegment(start: at(-1, 23), end: at(0, 6), stage: .core, source: "Connect",
                                                     sourceBundleId: "com.garmin.connect.mobile"),
                                        SleepSegment(start: at(0, 6), end: at(0, 7), stage: .core, source: "Scale")])
        tally.add(night, stream: .sleep, at: now)
        let workout = Workout(id: UUID(), activity: "running", start: at(-2, 18), end: at(-2, 19), avgHr: nil, maxHr: nil,
                              energyKcal: nil, distanceM: nil, source: "Connect", sourceBundleId: "com.garmin.connect.mobile")
        tally.add(HealthDelta(workouts: [workout]), stream: .workouts, at: now)
        #expect(tally.since == now)
        let yesterday = DayFormat.string(from: now.addingTimeInterval(-day))
        #expect(tally.counts["com.garmin.connect.mobile"]?["heart_rate"] == [yesterday: 5])
        // A night by its wake, a workout by its start; a source without a bundle id by its name.
        #expect(tally.counts["com.garmin.connect.mobile"]?["sleep"] == [DayFormat.string(from: now): 1])
        #expect(tally.counts["com.garmin.connect.mobile"]?["workouts"] == [DayFormat.string(from: at(-2, 18)): 1])
        #expect(tally.counts["name:Scale"]?["sleep"] == [DayFormat.string(from: now): 1])
        let window = DateInterval(start: now.addingTimeInterval(-7 * day), end: now)
        #expect(tally.records("com.garmin.connect.mobile", streams: ["heart_rate", "sleep"], in: window) == 6)
        #expect(tally.records("com.garmin.connect.mobile", streams: SourceDetection.countedStreams, in: window) == 7)
        #expect(tally.records("nobody", streams: SourceDetection.countedStreams, in: window) == 0)
    }

    @Test func theWindowTouchesEightLocalDays() {
        let window = DateInterval(start: now.addingTimeInterval(-7 * day), end: now)
        let days = SourceTally.days(touching: window)
        #expect(days.count == SourceTally.keptDays)
        #expect(days.contains(DayFormat.string(from: now)) && days.contains(DayFormat.string(from: window.start)))
        #expect(!days.contains(DayFormat.string(from: now.addingTimeInterval(-8 * day))))
        // Records on the day before the window's first don't count.
        var tally = SourceTally()
        tally.add(page(4, .steps, from: .mockGarmin, ago: 8 * day), stream: .quantity(.steps), at: now)
        tally.add(page(1, .steps, from: .mockGarmin, ago: 7 * day), stream: .quantity(.steps), at: now)
        #expect(tally.records("com.garmin.connect.mobile", streams: ["steps"], in: window) == 1)
    }

    @Test func pruneKeepsTheLastEightDaysAndDropsWhatIsEmpty() {
        var tally = SourceTally()
        tally.add(page(2, .steps, from: .mockGarmin, ago: 7 * day), stream: .quantity(.steps), at: now)
        tally.add(page(3, .steps, from: .mockGarmin, ago: 8 * day), stream: .quantity(.steps), at: now)
        tally.add(page(1, .heartRate, from: .mockOura, ago: 9 * day), stream: .quantity(.heartRate), at: now)
        tally.prune(now: now)
        #expect(tally.counts == ["com.garmin.connect.mobile": ["steps": [DayFormat.string(from: now.addingTimeInterval(-7 * day)): 2]]])
    }

    @Test func resetAndBackfillDecideCoverage() {
        let window = DateInterval(start: now.addingTimeInterval(-7 * day), end: now)
        var tally = SourceTally()
        tally.add(page(2, .steps, from: .mockGarmin, ago: day), stream: .quantity(.steps), at: now.addingTimeInterval(-8 * day))
        #expect(tally.covers(window))
        // A full re-sync: counts go, and counting starts again.
        tally.reset(at: now.addingTimeInterval(-60))
        #expect(tally.counts.isEmpty && tally.since == now.addingTimeInterval(-60) && !tally.covers(window))
        // A backfill that began before the tally was on doesn't cover.
        tally.backfillFinished(startedAt: now.addingTimeInterval(-120))
        #expect(!tally.covers(window))
        tally.backfillFinished(startedAt: now.addingTimeInterval(-60))
        #expect(tally.covers(window))
        tally.reset(at: now)
        #expect(!tally.covers(window))
        // Never on: no backfill covers.
        var off = SourceTally()
        off.backfillFinished(startedAt: now)
        #expect(!off.covers(window))
    }

    @Test func itSurvivesTheDiskWithFieldsMissing() throws {
        var tally = SourceTally()
        tally.add(page(2, .steps, from: .mockGarmin, ago: day), stream: .quantity(.steps), at: now)
        tally.backfillFinished(startedAt: now)
        let data = try JSONEncoder().encode(tally)
        let decoded = try JSONDecoder().decode(SourceTally.self, from: data)
        let empty = try JSONDecoder().decode(SourceTally.self, from: Data("{}".utf8))
        #expect(decoded == tally && empty == SourceTally())
    }
}

@Suite("Source detection: the reader")
@MainActor
struct SourceDetectorTests {
    @Test func sourcesRunOffTheMainActor() async throws {
        let store = MockHealthStore.garminLike(now: now)
        let env = AppEnvironment.test(health: store, clock: TestClock(now: now))
        let detector = SourceDetector(env: env, picked: ["garmin", "garmin", "nonsense"])
        #expect(detector.picked.map(\.id) == ["garmin"])
        #expect(store.probeReads == 0) // nothing before the screen asks
        let lastSeen = now.addingTimeInterval(-3_600)
        let outcome = await detector.detect(tally: nil, received: [
            UserSource(name: "Connect", bundleId: "com.garmin.connect.mobile", kinds: [.hr], lastSeen: lastSeen),
        ])
        guard case .detected(let detection) = outcome else { Issue.record("not detected: \(outcome)"); return }
        #expect(store.probeReads == 2 && store.readsOnMainThread == 0 && store.authorizationRequests == 0)
        #expect(detection.at == now && detection.trackerIDs == ["garmin"])
        #expect(row(detection, .mockGarmin)?.received == .kinds([.hr], lastSeen: lastSeen))
        #expect(detection.silent(among: detector.picked).isEmpty)
        #expect(detection.withoutHRV(among: detector.picked).map(\.id) == ["garmin"])
    }

    @Test func demoNeverReadsThisPhonesHealth() async throws {
        let env = AppEnvironment.preview()
        let phone = try #require(env.health as? MockHealthStore)
        var tally = SourceTally()
        tally.reset(at: .distantPast)
        let received = [UserSource(name: "Connect", bundleId: "com.garmin.connect.mobile", kinds: [], lastSeen: .now)]
        let garmin = await SourceDetector(env: env, picked: ["garmin"]).detect(tally: tally, received: received)
        guard case .detected(let detection) = garmin else { Issue.record("not detected: \(garmin)"); return }
        #expect(phone.probeReads == 0)
        #expect(detection.sources.map(\.displayName).contains("Garmin Connect"))
        // The demo account's platform list and the sync's tally don't belong to the scripted sources.
        #expect(detection.sources.compactMap(\.count) == [])
        #expect(detection.sources.filter { $0.received != .unknown }.map(\.id) == [])
        let watch = await SourceDetector(env: env, picked: ["apple_watch"]).detect(tally: nil, received: nil)
        guard case .detected(let watchDetection) = watch else { Issue.record("not detected: \(watch)"); return }
        #expect(watchDetection.trackerIDs == ["apple_watch"] && phone.probeReads == 0)
        // The wizard pre-selects nothing from demo data.
        #expect(await SourceDetector(env: env, picked: []).trackerIDs() == nil)
    }

    @Test func checkSyncAndSourcesPickTheStoreInOnePlace() throws {
        let store = MockHealthStore()
        let env = AppEnvironment.test(health: store, clock: TestClock(now: now))
        let live = HealthProbe.store(env: env, trackers: ["garmin"])
        #expect(live.health === store && live.trackers == ["garmin"])
        let demo = AppEnvironment.preview()
        let garmin = HealthProbe.store(env: demo, trackers: ["garmin"])
        #expect(garmin.health !== demo.health && garmin.trackers == ["garmin"])
        let scripted = try #require(garmin.health as? MockHealthStore)
        #expect(Set(scripted.samples.map(\.source)).contains(.mockGarmin))
        let watch = try #require(HealthProbe.store(env: demo, trackers: ["apple_watch"]).health as? MockHealthStore)
        let watchSources = Set(watch.samples.map(\.source))
        #expect(watchSources.contains(.mockWatch) && !watchSources.contains(.mockGarmin))
    }

    @Test func notAskedShowsAllowAccessAndReadsNothing() async {
        let store = MockHealthStore.garminLike(now: now)
        store.access = .notAsked
        let env = AppEnvironment.test(health: store, clock: TestClock(now: now))
        #expect(await SourceDetector(env: env, picked: ["garmin"]).detect(tally: nil, received: nil) == .notAsked)
        #expect(await SourceDetector(env: env, picked: ["garmin"]).trackerIDs() == nil)
        #expect(store.probeReads == 0 && store.authorizationRequests == 0)
        let none = MockHealthStore()
        none.isAvailable = false
        let noHealth = AppEnvironment.test(health: none, clock: TestClock(now: now))
        #expect(await SourceDetector(env: noHealth, picked: []).detect(tally: nil, received: nil) == .unavailable)
        #expect(none.probeReads == 0)
    }

    @Test func aLockedPhoneWaitsForTheUnlockAndAFailureSaysSo() async {
        let store = MockHealthStore.garminLike(now: now)
        let env = AppEnvironment.test(health: store, clock: TestClock(now: now))
        let detector = SourceDetector(env: env, picked: ["garmin"])
        store.nextError = HKError(.errorDatabaseInaccessible)
        #expect(await detector.detect(tally: nil, received: nil) == .locked)
        store.nextError = HKError(.errorHealthDataUnavailable)
        #expect(await detector.detect(tally: nil, received: nil) == .failed)
        guard case .detected = await detector.detect(tally: nil, received: nil) else {
            Issue.record("pull to refresh after the unlock reads again")
            return
        }
    }

    @Test func theWizardsPreselectionNeedsAskedAccessAndNeverPrompts() async {
        let store = MockHealthStore.garminLike(now: now)
        let env = AppEnvironment.test(health: store, clock: TestClock(now: now))
        #expect(await SourceDetector(env: env, picked: []).trackerIDs() == ["garmin"])
        store.access = .unknown
        #expect(await SourceDetector(env: env, picked: []).trackerIDs() == nil)
        store.access = .asked
        store.nextError = HKError(.errorDatabaseInaccessible)
        #expect(await SourceDetector(env: env, picked: []).trackerIDs() == nil)
        let empty = MockHealthStore()
        #expect(await SourceDetector(env: AppEnvironment.test(health: empty, clock: TestClock(now: now)), picked: [])
            .trackerIDs() == [])
        #expect(store.authorizationRequests == 0 && empty.authorizationRequests == 0)
    }
}

// MARK: - helpers

/// `hour:minute` on the day `days` from `now` (negative: before).
private func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let date = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
    return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
}

/// `n` records of `type` from `source`, a minute apart from `ago` before `now`.
private func page(_ n: Int, _ type: SampleType, from source: SourceRef, ago: TimeInterval) -> HealthDelta {
    let start = now.addingTimeInterval(-ago)
    return HealthDelta(samples: (0..<n).map {
        Sample(type: type, start: start.addingTimeInterval(Double($0) * 60), end: start.addingTimeInterval(Double($0) * 60),
               value: 1, unit: "count", source: source.name, sourceBundleId: source.bundleID)
    })
}
