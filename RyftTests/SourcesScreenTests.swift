import Foundation
import HealthKit
import Testing
@testable import Ryft

/// 09:12 on 2026-10-19 (local), as in the source detection suite.
private let now = Calendar.current.date(bySettingHour: 9, minute: 12, second: 0,
                                        of: Date(timeIntervalSince1970: 1_792_400_000)) ?? .now

/// Garmin Connect and the iPhone (`garminLike`), Oura beside them when asked.
private func store(oura: Bool = false, restingHR: Bool = true) -> MockHealthStore {
    let store = MockHealthStore.garminLike(now: now, restingHR: restingHR)
    if oura {
        store.samples += MockHealthStore.ouraLike(now: now).samples
        store.visible.formUnion(MockHealthStore.ouraLike(now: now).visible)
    }
    return store
}

/// The screen over a test environment (never demo): `picked` is the account's choice, `platform` its
/// `User.sources`.
@MainActor
private func screen(_ health: MockHealthStore, picked: [String] = ["garmin"], platform: [UserSource] = [],
                    online: Bool = true) -> (SourcesViewModel, AppState, MockPlatformAPI) {
    let api = MockPlatformAPI()
    let env = AppEnvironment.test(api: api, health: health, clock: TestClock(now: now), flags: [.devicesSetup: true],
                                  online: online)
    let state = AppState(env: env)
    var user = MockData.user
    user.sources = platform
    state.user = user
    let selection = TrackerSelectionStore(env: env)
    selection.set(picked)
    return (SourcesViewModel(state: state, selection: selection), state, api)
}

@Suite("Sources screen")
@MainActor
struct SourcesScreenTests {
    @Test func loadingUntilTheFirstReadThenOneRowPerSourceWithChipsAndNotes() async throws {
        let health = store()
        let (model, _, _) = screen(health, picked: ["garmin", "oura"])
        #expect(model.screen == .loading && model.rows.isEmpty && model.silentRows.isEmpty && model.summary == nil)

        await model.appeared()
        #expect(model.screen == .sources)
        #expect(health.readsOnMainThread == 0 && health.authorizationRequests == 0)
        let garmin = try #require(model.rows.first { $0.name == "Garmin Connect" })
        #expect(garmin.symbol == "watch.analog" && garmin.known)
        // The fixed order, the rest collapsed: resting heart rate is the "+1".
        let words = [TrackerSignal.heartRate, .sleep, .steps, .workouts].map(SourcesViewModel.chipWord)
        #expect(garmin.chips == words + ["+1"])
        #expect(garmin.count == nil) // no tally before T2's hook
        #expect(garmin.lastSeen == SyncLine.dataTime(now.addingTimeInterval(-1_200), now: now))
        // Note B, neutral, in the wording for a source that wrote resting heart rate and sleep.
        #expect(garmin.notes.map(\.kind) == [.noHRV])
        #expect(garmin.notes.first?.glyph == "minus.circle")
        #expect(garmin.notes.first?.text
            == String(localized: "Garmin Connect doesn't share HRV with Apple Health; recovery uses resting heart rate and sleep."))
        #expect(garmin.spoken.hasPrefix("Garmin Connect. "))
        // Oura was picked and wrote nothing: note A, amber glyph, the App Store page.
        let oura = try #require(model.silentRows.first)
        #expect(model.silentRows.map(\.id) == ["oura"])
        #expect(oura.note.kind == .silent && oura.note.glyph == "exclamationmark.circle")
        #expect(oura.note.text == String(localized: "Nothing from \("Oura") in 7 days. Open \("Oura"), then pull to refresh."))
        #expect(oura.storeURL != nil && oura.storeTitle == String(localized: "\("Oura") in the App Store"))
        #expect(model.summary == String(localized: "\(2) sources in the last 7 days")) // Garmin and the iPhone
    }

    @Test func withoutRestingHeartRateNoteBIsTheCatalogsSentence() async throws {
        let (model, _, _) = screen(store(restingHR: false))
        await model.appeared()
        let garmin = try #require(model.rows.first { $0.name == "Garmin Connect" })
        #expect(garmin.notes.first?.text == "Garmin Connect doesn't send HRV, breathing rate or blood oxygen to Apple Health.")
    }

    @Test func anAppleDeviceThatWroteNothingGetsNoStoreButton() async throws {
        let (model, _, _) = screen(store(), picked: ["apple_watch"])
        await model.appeared()
        let watch = try #require(model.silentRows.first)
        #expect(watch.id == "apple_watch" && watch.storeURL == nil && watch.storeTitle == nil)
        #expect(watch.name == "Apple Watch" && watch.note.text.hasPrefix("Nothing from Apple Watch in 7 days."))
    }

    /// Note C matches what Apple Health has against the platform's newest list, and pull to refresh re-reads both.
    @Test func noteCComesFromTheNewestPlatformListAndAPullRereadsIt() async throws {
        let garminListed = UserSource(name: "Connect", bundleId: "com.garmin.connect.mobile",
                                      kinds: [.hr, .sleep, .steps, .workout], lastSeen: now)
        let (model, state, api) = screen(store(oura: true), picked: ["garmin", "oura"], platform: [garminListed])
        await model.appeared()
        let oura = try #require(model.rows.first { $0.name == "Oura" })
        // C before B (design.md §D4.3): Oura's catalog entry doesn't share HRV either.
        #expect(oura.notes.map(\.kind) == [.notReceived, .noHRV])
        #expect(oura.notes.first?.glyph == "arrow.triangle.2.circlepath")
        #expect(oura.notes.first?.text.hasSuffix(String(localized: "Pull to refresh.")) == true)
        #expect(model.rows.first { $0.name == "Garmin Connect" }?.notes.map(\.kind) == [.noHRV]) // listed: no C
        #expect(!model.isPlatformOffline)

        // The platform now lists Oura: the note goes without another read of Apple Health.
        var user = try #require(state.user)
        user.sources = [garminListed, UserSource(name: "Oura", bundleId: "com.ouraring.oura",
                                                 kinds: [.hr, .sleep, .resp, .steps, .workout], lastSeen: now)]
        state.user = user
        #expect(model.rows.first { $0.name == "Oura" }?.notes.map(\.kind) == [.noHRV])

        let meCalls = api.calls.filter { $0 == "me" }.count
        await model.refresh()
        #expect(api.calls.filter { $0 == "me" }.count == meCalls + 1, "pull to refresh asks GET /v1/me again")
    }

    @Test func offlineTheRowsAreApplesAloneWithoutNoteC() async throws {
        let (model, _, api) = screen(store(oura: true), picked: ["garmin"], platform: [], online: false)
        await model.appeared()
        #expect(model.screen == .sources && model.isPlatformOffline)
        #expect(model.rows.flatMap(\.notes).allSatisfy { $0.kind != .notReceived })
        #expect(!api.calls.contains("me"))
    }

    @Test func anAppearanceRightAfterAReadReusesItAndAPullReadsAgain() async {
        let health = store()
        let (model, _, _) = screen(health)
        await model.appeared()
        #expect(health.probeReads == 2)
        await model.appeared() // Devices & sync read for its row, then Sources opened
        #expect(health.probeReads == 2)
        await model.refresh()
        #expect(health.probeReads == 4)
    }

    @Test func nothingInSevenDaysSaysBothAndStillListsThePickedTrackers() async throws {
        let (model, _, _) = screen(MockHealthStore(), picked: ["garmin"])
        await model.appeared()
        #expect(model.screen == .nothing && model.rows.isEmpty)
        #expect(model.detection?.mayNotRead == true)
        #expect(model.silentRows.map(\.id) == ["garmin"])
        #expect(model.canCheckSync && model.checkTrackers == ["garmin"])
    }

    @Test func notAskedReadsNothingUntilAllowAccess() async {
        let health = store()
        health.access = .notAsked
        let (model, _, _) = screen(health)
        await model.appeared()
        #expect(model.screen == .notAsked && model.rows.isEmpty && model.silentRows.isEmpty)
        #expect(health.probeReads == 0 && health.authorizationRequests == 0)
        await model.requestAccess()
        #expect(health.authorizationRequests == 1 && model.screen == .sources)
    }

    @Test func aLockedPhoneSaysUnlockAndAPullAfterwardsReads() async {
        let health = store()
        let (model, _, _) = screen(health)
        health.nextError = HKError(.errorDatabaseInaccessible)
        await model.appeared()
        #expect(model.screen == .locked)
        health.nextError = HKError(.errorHealthDataUnavailable)
        await model.refresh()
        #expect(model.screen == .failed)
        await model.refresh()
        #expect(model.screen == .sources)
    }

    @Test func demoShowsTheMockSourcesAndNeverReadsThisPhone() async throws {
        let state = AppState.preview(flags: [.devicesSetup: true])
        let phone = try #require(state.env.health as? MockHealthStore)
        let selection = TrackerSelectionStore(env: state.env)
        selection.stage(["garmin"])
        let model = SourcesViewModel(state: state, selection: selection)
        await model.appeared()
        #expect(model.isDemo && phone.probeReads == 0)
        let garmin = try #require(model.rows.first { $0.name == "Garmin Connect" })
        #expect(garmin.notes.map(\.kind) == [.noHRV]) // the demo account's list never makes note C
        #expect(!model.isPlatformOffline)
    }

    @Test func chipsKeepTheFixedOrderAndCollapseTheRest() {
        let all: [TrackerSignal] = [.heartRate, .hrv, .sleep, .steps, .workouts, .restingHR, .respiratoryRate, .spo2]
        let words = DetectedSource.chipOrder.map(SourcesViewModel.chipWord)
        #expect(SourcesViewModel.chips(all) == words + ["+3"])
        #expect(SourcesViewModel.chips([.sleep]) == [SourcesViewModel.chipWord(.sleep)])
        #expect(SourcesViewModel.chips([]) == [])
    }
}

@Suite("What do you wear?: detected trackers")
@MainActor
struct WearPreselectionTests {
    /// A reinstall, a second account, Devices & sync → Edit: access was granted, so what Apple Health shows is
    /// pre-filled as detected tiles; Confirm saves it, and nothing is saved before.
    @Test func theWearStepPreselectsWhatIsDetectedWhenAccessWasGranted() async {
        let health = MockHealthStore.garminLike(now: now)
        let env = AppEnvironment.test(health: health, clock: TestClock(now: now), flags: [.devicesSetup: true])
        let onboarding = OnboardingCoordinator(state: AppState(env: env), apiStatus: APIStatus()) {}
        #expect(onboarding.detected == nil)
        await onboarding.detectTrackers()
        #expect(onboarding.detected == ["garmin"])
        #expect(onboarding.devices.trackers.isEmpty, "nothing saved on detection alone")

        var choice = WearChoice()
        choice.seed(onboarding.detected)
        #expect(choice.state(of: "garmin") == .detected && choice.state(of: "oura") == .none)
        #expect(choice.hasDetection && choice.confirms && choice.canSave && choice.saved == ["garmin"])
        onboarding.answerWear(choice.saved)
        #expect(onboarding.devices.trackers == ["garmin"] && onboarding.wearAsked)
        #expect(health.authorizationRequests == 0)

        // Devices & sync → Edit: the same, over the account's choice.
        let devices = DevicesViewModel(state: AppState(env: env), selection: TrackerSelectionStore(env: env))
        devices.save(["oura"])
        var sheet = WearChoice(picked: devices.selection.trackers)
        sheet.seed(await devices.detectedTrackers())
        #expect(sheet.state(of: "oura") == .chosen && sheet.state(of: "garmin") == .detected)
        #expect(sheet.saved == ["oura", "garmin"])
    }

    /// The first run: Apple Health wasn't asked yet, so nothing is detected, nothing pre-filled, and RYFT never
    /// prompts from this step. Demo data never pre-fills either.
    @Test func notAskedPreselectsNothingAndNeverPrompts() async {
        let health = MockHealthStore.garminLike(now: now)
        health.access = .notAsked
        let env = AppEnvironment.test(health: health, clock: TestClock(now: now), flags: [.devicesSetup: true])
        let onboarding = OnboardingCoordinator(state: AppState(env: env), apiStatus: APIStatus()) {}
        await onboarding.detectTrackers()
        #expect(onboarding.detected == nil && onboarding.offeredTrackers.isEmpty)
        var choice = WearChoice()
        choice.seed(onboarding.detected)
        #expect(!choice.hasDetection && !choice.confirms && !choice.canSave)
        #expect(health.authorizationRequests == 0 && health.probeReads == 0)

        let demo = OnboardingCoordinator(state: AppState.preview(), apiStatus: APIStatus()) {}
        await demo.detectTrackers()
        #expect(demo.detected == nil)
        // Found nothing: the step is exactly today's.
        var empty = WearChoice()
        empty.seed([])
        #expect(!empty.hasDetection && !empty.confirms)
    }

    @Test func aTouchedSelectionIsNeverOverwritten() {
        // A tile tapped before detection lands: detection changes nothing.
        var early = WearChoice()
        early.toggle("oura")
        early.seed(["garmin"])
        #expect(early.picked == ["oura"] && early.state(of: "garmin") == .none && !early.confirms)

        // Pre-filled once: confirming and clearing a detected tile, then a second detection, adds nothing back.
        var choice = WearChoice()
        choice.seed(["garmin", "oura"])
        #expect(choice.confirms)
        choice.toggle("garmin") // confirms it
        #expect(choice.state(of: "garmin") == .chosen && !choice.confirms, "the first change turns Confirm to Continue")
        choice.toggle("garmin") // clears it
        choice.seed(["garmin", "oura", "polar"])
        #expect(choice.state(of: "garmin") == .none && choice.state(of: "polar") == .none)
        #expect(choice.saved == ["oura"], "Oura, still standing as detected, is confirmed by the button")
    }

    @Test func justMyIPhoneStaysOnItsOwn() {
        var choice = WearChoice()
        choice.seed(["garmin", "oura"])
        let cleared = choice.toggle(TrackerSelectionStore.iPhone)
        #expect(cleared, "the detected tiles went: announced")
        #expect(choice.saved == [TrackerSelectionStore.iPhone] && !choice.hasDetection)
        choice.toggle("garmin")
        #expect(choice.saved == ["garmin"])

        // The iPhone alone is never pre-filled next to a choice, and a choice of the iPhone isn't overridden.
        var picked = WearChoice(picked: ["garmin"])
        picked.seed([TrackerSelectionStore.iPhone])
        #expect(!picked.hasDetection)
        var phone = WearChoice(picked: [TrackerSelectionStore.iPhone])
        phone.seed(["garmin"])
        #expect(!phone.hasDetection && phone.saved == [TrackerSelectionStore.iPhone])
        // Nothing but the iPhone wrote: it is the detection.
        var alone = WearChoice()
        alone.seed([TrackerSelectionStore.iPhone])
        #expect(alone.saved == [TrackerSelectionStore.iPhone])
    }

    /// After Apple Health access (wear step left where it is, lead decision 5.2): what was found and not picked is
    /// offered on the setup step; "Add" saves it into the choice.
    @Test func theSetupStepOffersWhatWasFoundAndNotPicked() async {
        let health = MockHealthStore.garminLike(now: now)
        health.samples += MockHealthStore.ouraLike(now: now).samples
        let env = AppEnvironment.test(health: health, clock: TestClock(now: now), flags: [.devicesSetup: true])
        let onboarding = OnboardingCoordinator(state: AppState(env: env), apiStatus: APIStatus()) {}
        onboarding.answerWear(["garmin"])
        #expect(onboarding.offeredTrackers.isEmpty, "nothing detected yet")
        await onboarding.detectTrackers()
        #expect(onboarding.offeredTrackers.map(\.id) == ["oura"])
        onboarding.addDetected("oura")
        #expect(onboarding.devices.trackers == ["garmin", "oura"] && onboarding.offeredTrackers.isEmpty)
        #expect(onboarding.setupTrackers.map(\.id) == ["garmin", "oura"])
        #expect(health.authorizationRequests == 0)
    }
}
