import Foundation
import HealthKit
import Testing
@testable import Ryft

// ADR 0027, docs/work/2026-11-23-first-run/health-groups.md §9: the registry, the requests, the record and `about`.

/// Today's ten read types, as HealthKit names them: pinned once, so `core` can't drift from 1.x.
private let todaysTen: Set<String> = [
    "HKQuantityTypeIdentifierHeartRate", "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
    "HKQuantityTypeIdentifierRestingHeartRate", "HKQuantityTypeIdentifierRespiratoryRate",
    "HKQuantityTypeIdentifierOxygenSaturation", "HKQuantityTypeIdentifierVO2Max",
    "HKQuantityTypeIdentifierActiveEnergyBurned", "HKQuantityTypeIdentifierStepCount",
    "HKCategoryTypeIdentifierSleepAnalysis", "HKWorkoutTypeIdentifier",
]

/// Today's observers, in today's order.
private let todaysObservers = ["HKCategoryTypeIdentifierSleepAnalysis", "HKWorkoutTypeIdentifier",
                               "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"]

/// Today's stream order (what scoring waits for first).
private let todaysStreams: [HealthStream] = [
    .sleep, .quantity(.hrvSDNN), .quantity(.restingHR), .quantity(.respiratoryRate), .quantity(.spo2),
    .workouts, .quantity(.heartRate), .quantity(.steps), .quantity(.activeEnergy), .quantity(.vo2max),
]

private let notRequestable: [HealthPermissionGroup] = [.body, .fuel, .habits, .physiology]

private func suite() -> UserDefaults {
    UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
}

/// A suite whose signed-in account (`AccountScope`) is `account`.
private func suite(account: String?, introDone: Bool = false) -> UserDefaults {
    let d = suite()
    if let account { d.set(account, forKey: AccountScope.defaultsKey) }
    d.set(introDone, forKey: HealthPermissionLedger.introDoneKey)
    return d
}

@Suite("Health permission groups: the registry")
struct HealthPermissionRegistryTests {
    @Test func everyTypeIsInExactlyOneGroup() {
        for type in HealthDataType.allCases {
            let groups = HealthPermissionGroup.allCases.filter { $0.types.contains(type) }
            #expect(groups.count == 1, "\(type) is in \(groups)")
        }
        for group in HealthPermissionGroup.allCases {
            #expect(Set(group.types).count == group.types.count, "\(group) lists a type twice")
        }
    }

    @Test func onlyCoreAndAboutAreRequestable() {
        #expect(HealthPermissionGroup.allCases.filter(\.isRequestable) == [.core, .about])
        #expect(HealthPermissionGroup.allCases == [.core, .about, .body, .fuel, .habits, .physiology])
    }

    /// Every requestable group's types have a consumer: core's are the sync's streams, about's the birth year.
    @Test func requestableGroupsHaveTheirConsumers() {
        let hk = HealthKitManager.shared
        #expect(HealthPermissionGroup.core.consumer == .scores)
        #expect(HealthPermissionGroup.about.consumer == .birthYearPrefill)
        #expect(HealthPermissionGroup.about.types == [.dateOfBirth])
        let streamTypes = Set(hk.streams.map { stream -> String in
            switch stream {
            case .quantity(let type): hk.quantities.first { $0.type == type }?.hkType.identifier ?? "missing \(type)"
            case .sleep: hk.sleepType.identifier
            case .workouts: hk.workoutType.identifier
            }
        })
        #expect(Set(HealthPermissionGroup.core.types.map(\.rawValue)) == streamTypes)
        #expect(streamTypes == Set(hk.quantities.map(\.hkType.identifier) + [hk.sleepType.identifier, hk.workoutType.identifier]))
        #expect(HealthPermissionGroup.body.consumer == .fuel && HealthPermissionGroup.fuel.consumer == .fuel)
        #expect(HealthPermissionGroup.habits.consumer == .journalAutofill)
        #expect(HealthPermissionGroup.physiology.consumer == .physiologyCard)
    }

    @Test func everyTypeMapsToItsHealthKitType() {
        for type in HealthDataType.allCases {
            #expect(type.objectType.identifier == type.rawValue)
        }
        #expect(HealthDataType.dateOfBirth.objectType is HKCharacteristicType)
    }

    /// §5 (a)–(d): core is exactly 1.x's ten types, three observers and stream order.
    @Test func coreIsTodaysTenTypesObserversAndStreams() {
        let hk = HealthKitManager.shared
        let core = Set(HealthKitManager.readTypes([.core]).map(\.identifier))
        #expect(core == todaysTen)
        #expect(core == Set(hk.quantities.map(\.hkType.identifier) + [hk.sleepType.identifier, hk.workoutType.identifier]))
        #expect(HealthKitManager.observedTypes([.core]).map(\.identifier) == todaysObservers)
        #expect(HealthKitManager.observedTypes([.core, .about]).map(\.identifier) == todaysObservers)
        #expect(HealthPermissionGroup.core.streams == todaysStreams)
        #expect(hk.streams == todaysStreams)
        #expect(HealthPermissionGroup.core.observed == [.sleepAnalysis, .workout, .hrvSDNN])
    }

    /// A characteristic has no anchor, no observer and no upload.
    @Test func aboutHasNoStreamsAndNoObservers() {
        #expect(HealthPermissionGroup.about.streams.isEmpty)
        #expect(HealthPermissionGroup.about.observed.isEmpty)
        #expect(HealthKitManager.observedTypes([.about]).isEmpty)
        #expect(HealthKitManager.readTypes([.about]).map(\.identifier) == ["HKCharacteristicTypeIdentifierDateOfBirth"])
    }

    /// The type-set builder gives nothing for a group that isn't requestable, whatever the record says.
    @Test func aGroupThatIsNotRequestableAddsNoType() {
        #expect(HealthKitManager.readTypes(Set(notRequestable)).isEmpty)
        #expect(HealthKitManager.observedTypes(Set(HealthPermissionGroup.allCases)).map(\.identifier) == todaysObservers)
        let all = Set(HealthKitManager.readTypes(Set(HealthPermissionGroup.allCases)).map(\.identifier))
        #expect(all == todaysTen.union(["HKCharacteristicTypeIdentifierDateOfBirth"]))
        for group in notRequestable {
            #expect(group.streams.isEmpty && group.observed.isEmpty, "\(group)")
        }
    }

    /// §5 (e): the launch gate is unchanged.
    @Test func theLaunchGateIsSignedInIntroDoneAndAvailable() {
        #expect(RyftApp.observesAtLaunch(signedIn: true, healthIntroDone: true, available: true))
        #expect(!RyftApp.observesAtLaunch(signedIn: false, healthIntroDone: true, available: true))
        #expect(!RyftApp.observesAtLaunch(signedIn: true, healthIntroDone: false, available: true))
        #expect(!RyftApp.observesAtLaunch(signedIn: true, healthIntroDone: true, available: false))
    }
}

@Suite("Health permission groups: requests")
@MainActor
struct HealthPermissionRequestTests {
    private func coordinator(_ env: AppEnvironment) -> SyncCoordinator {
        let state = AppState(env: env)
        return SyncCoordinator(steps: LiveSyncSteps(state: state, sync: SyncService.ungated(env: env)), clock: env.clock)
    }

    /// The live store throws before HealthKit: no sheet, no record.
    @Test("A group that isn't requestable throws before HealthKit", arguments: notRequestable)
    func aGroupThatIsNotRequestableThrows(_ group: HealthPermissionGroup) async {
        await #expect(throws: HealthPermissionError.notRequestable(group)) {
            try await HealthKitManager.shared.requestAuthorization(group)
        }
        let status = await HealthKitManager.shared.accessStatus(group)
        #expect(status == (HealthKitManager.isAvailable ? .unknown : .unavailable))
    }

    @Test func theFirstRunAsksForCore() async {
        let health = MockHealthStore()
        health.access = .notAsked
        let env = AppEnvironment.test(health: health)
        env.settings.healthIntroDone = false
        await HealthOnboardingViewModel(env: env).connect()
        #expect(health.requests == [.core])
        #expect(health.statusQueries == [.core])
        #expect(health.asked == [.core])
    }

    @Test func profileAsksForCore() async {
        let health = MockHealthStore()
        health.access = .notAsked
        let env = AppEnvironment.test(health: health)
        let state = AppState(env: env)
        let sync = SyncService.ungated(env: env)
        let profile = ProfileViewModel(state: state, sync: sync,
                                       coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                                       apiStatus: APIStatus())
        await profile.requestHealthAccess()
        #expect(health.requests == [.core])
        #expect(health.statusQueries == [.core])
    }

    @Test func devicesAndSyncAsksForCore() async {
        let health = MockHealthStore()
        health.access = .notAsked
        let env = AppEnvironment.test(health: health)
        let devices = DevicesViewModel(state: AppState(env: env), selection: TrackerSelectionStore(env: env))
        await devices.requestHealthAccess()
        #expect(health.requests == [.core])
        #expect(health.statusQueries == [.core])
    }

    @Test func checkSyncsAllowAccessAsksForCore() async {
        let health = MockHealthStore()
        health.access = .notAsked
        let model = TrackerCheckModel(env: AppEnvironment.test(health: health), health: health, trackers: ["garmin"])
        await model.requestAccess()
        #expect(health.requests == [.core])
        #expect(Set(health.statusQueries) == [.core])
    }

    /// Bootstrap asks for core only, even when the record has about.
    @Test func bootstrapNeverRequestsAbout() async {
        let health = MockHealthStore()
        health.asked = [.core, .about]
        let env = AppEnvironment.test(health: health)
        await RyftApp.connectHealth(health, coordinator: coordinator(env))
        #expect(health.requests == [.core])
        #expect(health.observerRegistrations == 1)
    }

    /// "Not now" on Connect Apple Health: no sheet at bootstrap, and nothing recorded (the lead's PR 3 fix).
    @Test func afterNotNowBootstrapMakesNoRequest() async {
        let health = MockHealthStore()
        health.access = .notAsked
        let env = AppEnvironment.test(health: health)
        env.settings.healthIntroDone = false
        HealthOnboardingViewModel(env: env).notNow()
        #expect(env.settings.healthIntroDone)
        await RyftApp.connectHealth(health, coordinator: coordinator(env))
        #expect(health.requests.isEmpty)
        #expect(health.statusQueries == [.core])
        #expect(health.asked.isEmpty)
    }

    /// Continue requests core and records it; bootstrap then requests it exactly once more (HealthKit shows no sheet
    /// for what was answered).
    @Test func afterContinueBootstrapRequestsCoreOnce() async {
        let health = MockHealthStore()
        health.access = .notAsked
        let env = AppEnvironment.test(health: health)
        env.settings.healthIntroDone = false
        await HealthOnboardingViewModel(env: env).connect()
        #expect(health.requests == [.core] && health.asked == [.core])
        await RyftApp.connectHealth(health, coordinator: coordinator(env))
        #expect(health.requests == [.core, .core])
    }

    /// An account from before the record that answered the sheet: bootstrap requests core once (no sheet) and records it.
    @Test func bootstrapRecordsCoreForAnAccountThatAnsweredBefore() async {
        let health = MockHealthStore()
        health.access = .asked
        let env = AppEnvironment.test(health: health)
        #expect(health.asked.isEmpty)
        await RyftApp.connectHealth(health, coordinator: coordinator(env))
        #expect(health.requests == [.core])
        #expect(health.asked == [.core])
    }

    /// A refused or failed request at bootstrap still registers the observers, and records nothing.
    @Test func aThrowingBootstrapRequestRecordsNothing() async {
        let health = MockHealthStore()
        health.access = .asked
        health.authorizationError = HKError(.errorHealthDataUnavailable)
        let env = AppEnvironment.test(health: health)
        await RyftApp.connectHealth(health, coordinator: coordinator(env))
        #expect(health.requests == [.core])
        #expect(health.asked.isEmpty)
        #expect(health.observerRegistrations == 1)
    }

    /// An upgraded account that had granted: its first launch is a background one, before any bootstrap. The launch
    /// gate holds, the observed groups give today's three observers without a record, and nothing is requested.
    @Test func anUpgradedAccountKeepsItsObserversWithoutAPrompt() async {
        let defaults = suite(account: "A", introDone: true)
        let ledger = HealthPermissionLedger(defaults: defaults, account: "A")
        #expect(ledger.asked.isEmpty)
        #expect(ledger.observedGroups == [.core])
        #expect(HealthKitManager.observedTypes(ledger.observedGroups).map(\.identifier) == todaysObservers)
        #expect(RyftApp.observesAtLaunch(signedIn: true, healthIntroDone: Settings(defaults: defaults).healthIntroDone,
                                         available: true))
        let health = MockHealthStore()
        let env = AppEnvironment.test(health: health)
        RyftApp.observeHealthKit(health, coordinator: coordinator(env))
        #expect(health.observerRegistrations == 1)
        #expect(health.requests.isEmpty && health.statusQueries.isEmpty)
        #expect(defaults.object(forKey: HealthPermissionLedger.key("A")) == nil)
    }
}

@Suite("Health permission groups: the per-account record")
struct HealthPermissionLedgerTests {
    @Test func aRecordIsPerAccount() {
        let d = suite()
        HealthPermissionLedger(defaults: d, account: "A").record(.about)
        #expect(HealthPermissionLedger(defaults: d, account: "A").asked == [.about])
        #expect(HealthPermissionLedger(defaults: d, account: "B").asked.isEmpty)
        #expect(d.stringArray(forKey: "health.asked.A") == ["about"])
    }

    @Test func aSignOutKeepsTheRecordAndADeletionRemovesIt() {
        let d = suite(account: "A")
        HealthPermissionLedger(defaults: d, account: "A").record(.core)
        HealthPermissionLedger(defaults: d, account: "B").record(.about)
        for reason: AuthService.SignOutReason? in [.user, .sessionExpired, nil] {
            HealthPermissionLedger.wipe(AuthService.Wipe(reason: reason, account: "A"), defaults: d)
            #expect(HealthPermissionLedger(defaults: d, account: "A").asked == [.core], "\(String(describing: reason))")
        }
        HealthPermissionLedger.wipe(AuthService.Wipe(reason: .accountDeleted(background: true), account: "A"), defaults: d)
        #expect(d.object(forKey: "health.asked.A") == nil)
        #expect(HealthPermissionLedger(defaults: d, account: "B").asked == [.about])
    }

    @Test func aDeletionWithoutItsAccountRemovesTheSignedInOne() {
        let d = suite(account: "B").withRecord(.about, for: "B").withRecord(.core, for: "C")
        HealthPermissionLedger.wipe(AuthService.Wipe(reason: .accountDeleted(background: false), account: nil), defaults: d)
        #expect(d.object(forKey: "health.asked.B") == nil)
        #expect(d.stringArray(forKey: "health.asked.C") == ["core"])
    }

    /// Signed out or Demo data: nothing is written, even through a request.
    @Test func withoutAnAccountNothingIsWritten() async throws {
        let d = suite(account: nil, introDone: true)
        let before = Set(d.dictionaryRepresentation().keys)
        let ledger = HealthPermissionLedger(defaults: d, account: nil)
        ledger.record(.core)
        ledger.remove()
        await HealthPermissionLedger.recording(.about, defaults: d) {}
        #expect(ledger.asked.isEmpty)
        #expect(ledger.observedGroups == [.core])
        #expect(Set(d.dictionaryRepresentation().keys) == before)
    }

    /// The migration's synchronous part covers the observers only: `asked` holds what a request ran for.
    @Test func theIntroCoversTheObserversButRecordsNothing() {
        let done = suite(account: "A", introDone: true)
        let ledger = HealthPermissionLedger(defaults: done, account: "A")
        #expect(ledger.asked.isEmpty && ledger.observedGroups == [.core])
        #expect(done.object(forKey: "health.asked.A") == nil)

        let notDone = HealthPermissionLedger(defaults: suite(account: "A"), account: "A")
        #expect(notDone.asked.isEmpty && notDone.observedGroups.isEmpty)

        let aboutOnly = suite(account: "A", introDone: true).withRecord(.about, for: "A")
        let onlyAbout = HealthPermissionLedger(defaults: aboutOnly, account: "A")
        #expect(onlyAbout.asked == [.about] && onlyAbout.observedGroups == [.core, .about])
        #expect(HealthKitManager.observedTypes(onlyAbout.observedGroups).map(\.identifier) == todaysObservers)
    }

    /// `Settings.healthIntroDone` is what the record reads.
    @Test func theIntroFlagIsSettings() {
        let d = suite(account: "A")
        let settings = Settings(defaults: d)
        settings.healthIntroDone = true
        #expect(HealthPermissionLedger(defaults: d, account: "A").observedGroups == [.core])
        settings.healthIntroDone = false
        #expect(HealthPermissionLedger(defaults: d, account: "A").observedGroups.isEmpty)
    }

    /// A newer build's groups survive a rewrite; a second record of a group changes nothing.
    @Test func unknownGroupsAreKeptAndRecordingIsIdempotent() {
        let d = suite()
        d.set(["sensors", "about"], forKey: "health.asked.A")
        let ledger = HealthPermissionLedger(defaults: d, account: "A")
        ledger.record(.core)
        ledger.record(.core)
        ledger.record(.about)
        #expect(d.stringArray(forKey: "health.asked.A") == ["sensors", "about", "core"])
        #expect(ledger.asked == [.about, .core])
        #expect(ledger.contains(.core) && !ledger.contains(.body))
    }

    @Test func aThrowingRequestRecordsNothing() async {
        let d = suite(account: "A")
        await #expect(throws: HKError.self) {
            try await HealthPermissionLedger.recording(.core, defaults: d) { throw HKError(.errorAuthorizationDenied) }
        }
        #expect(d.object(forKey: "health.asked.A") == nil)
    }

    /// The account is the one signed in when the sheet went up.
    @Test func anAccountSwitchDuringTheRequestRecordsForTheAccountThatAsked() async throws {
        let d = suite(account: "A")
        await HealthPermissionLedger.recording(.about, defaults: d) {
            d.set("B", forKey: AccountScope.defaultsKey)
        }
        #expect(d.stringArray(forKey: "health.asked.A") == ["about"])
        #expect(d.object(forKey: "health.asked.B") == nil)
    }
}

@Suite("Health permission groups: about")
struct HealthAboutTests {
    @Test func theYearIsGregorian() throws {
        let gregorian = Calendar(identifier: .gregorian)
        #expect(HealthKitManager.gregorianYear(DateComponents(calendar: gregorian, year: 1990, month: 5, day: 17)) == 1990)
        #expect(HealthKitManager.gregorianYear(DateComponents(year: 1990, month: 5, day: 17)) == 1990)
        #expect(HealthKitManager.gregorianYear(DateComponents(calendar: gregorian, month: 5, day: 17)) == nil)
        let buddhist = Calendar(identifier: .buddhist)
        #expect(HealthKitManager.gregorianYear(DateComponents(calendar: buddhist, year: 2533, month: 5, day: 17)) == 1990)
        #expect(HealthKitManager.gregorianYear(DateComponents(calendar: buddhist, month: 5, day: 17)) == nil)
        // Early January in the Buddhist calendar is the same Gregorian year (no off-by-one at the boundary).
        #expect(HealthKitManager.gregorianYear(DateComponents(calendar: buddhist, year: 2533, month: 1, day: 2)) == 1990)
    }

    @Test func theMockAnswersItsBirthYear() async {
        let health = MockHealthStore()
        #expect(await health.birthYear() == nil)
        health.birthYearValue = 1990
        #expect(await health.birthYear() == 1990)
    }

    /// A request for `about` adds one key, `health.asked.<account>`, which holds group names and no date.
    @Test func theRecordHoldsNoDate() async throws {
        let d = suite(account: "A")
        let before = d.dictionaryRepresentation()
        await HealthPermissionLedger.recording(.about, defaults: d) {}
        let after = d.dictionaryRepresentation()
        #expect(Set(after.keys).subtracting(before.keys) == ["health.asked.A"])
        let value = try #require(d.stringArray(forKey: "health.asked.A"))
        #expect(value == ["about"])
        #expect(!value.joined().contains { $0.isNumber })
    }
}

private extension UserDefaults {
    func withRecord(_ group: HealthPermissionGroup, for account: String) -> UserDefaults {
        HealthPermissionLedger(defaults: self, account: account).record(group)
        return self
    }
}
