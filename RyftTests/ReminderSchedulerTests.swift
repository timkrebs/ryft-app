import Foundation
import HealthKit
import Testing
import UIKit
import UserNotifications
@testable import Ryft

// N3 (design.md §10, criteria 1–6 and 8; §11): the one writer of RYFT's local requests, on a graph of its own (auth,
// flags, notifier, defaults, clock), synthetic data only. The not-syncing and account tests run on Europe/Berlin; the
// journal's on this iPhone's calendar and today's date, because the mock platform's journal answers by the real day.

private let accountA = UUID(uuidString: "0000000A-0000-4000-8000-00000000000A") ?? UUID()
private let accountB = UUID(uuidString: "0000000B-0000-4000-8000-00000000000B") ?? UUID()

/// The calendar `DayFormat` and the mock journal use.
private let local: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .autoupdatingCurrent
    return c
}()

@MainActor
private final class WipeTarget {
    var env: AppEnvironment?
    var notifier: MockNotifier?
    var wipesNotifications = true
}

@MainActor
private final class ReminderRig {
    let clock = TestClock()
    let notifier = MockNotifier()
    let api = MockPlatformAPI()
    let demoAPI = MockPlatformAPI()
    let client: MockAuthClient
    let auth: AuthService
    let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
    let flags: FlagStore
    let env: AppEnvironment
    let state: AppState
    let scheduler: ReminderScheduler
    let calendar: Calendar
    private let target = WipeTarget()
    var user: User? = MockData.user
    var overBudget: [Int] = []
    private(set) lazy var journal = JournalStore(env: env)
    private(set) lazy var push = PushRegistrar(env: env)

    /// `wipesNotifications: false`: a sign-out's wipe that leaves iOS's requests (one resumed `storeOnly`).
    init(at now: Date, calendar: Calendar = Berlin.calendar, health: MockHealthStore = MockHealthStore(),
         wipesNotifications: Bool = true) {
        clock.set(now)
        self.calendar = calendar
        client = MockAuthClient(session: .preview(id: accountA))
        let target = self.target
        target.wipesNotifications = wipesNotifications
        auth = AuthService(client: client, defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard,
                           wipeLocalData: { wipe in
                               guard let env = target.env, let notifier = target.notifier else { return true }
                               // The device step, on this graph's centre (the app's passes `UNUserNotificationCenter`).
                               if target.wipesNotifications {
                                   ReminderScheduler.wipe(notifier, defaults: env.defaults, parking: wipe.parking)
                               }
                               return env.persistence.wipe()
                           },
                           deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                           postAppleAuthorization: { _ in })
        let settings = Settings(defaults: defaults)
        settings.demoMode = false
        flags = FlagStore(store: TrainStore(inMemory: true), defaults: defaults)
        api.now = { [clock] in clock.now() }
        demoAPI.now = { [clock] in clock.now() }
        env = AppEnvironment(settings: settings, health: health, liveAPI: api, demoAPI: demoAPI, auth: auth,
                             persistence: TrainStore(inMemory: true), clock: clock, notifier: notifier, flags: flags,
                             connectivity: .preview(online: true), defaults: defaults, demoOverride: nil)
        env.reads.random = { $0.lowerBound }
        env.reads.budget = RequestBudget(clock: clock, maxStarts: .max)
        target.env = env
        target.notifier = notifier
        state = AppState(env: env)
        state.repository.widgetFile = nil
        state.bindAccountHooks(auth, apiStatus: APIStatus())
        // As `AppState.reminders` is wired, on this rig's calendar.
        let scheduler = ReminderScheduler(env: env, inputs: .none, calendar: calendar)
        state.forgetsAccountState { [weak scheduler] in scheduler?.forget() }
        self.scheduler = scheduler
        notifier.status = .authorized
        scheduler.inputs.user = { [weak self] in self?.user }
        scheduler.overBudget = { [weak self] in self?.overBudget.append($0) }
        flags.setOverride(.pushEnabled, false)
        // Dark on `main` (review B-1); these tests are about what the reminders do once it's open.
        flags.setOverride(.notificationsReminders, true)
    }

    /// A `GET /v1/config` answer for this account with `flags`.
    func answer(_ flags: [String: Bool]) {
        self.flags.apply(RemoteConfig(flags: flags, evaluatedAt: clock.now(), ttlSec: 21_600), fetchedAt: clock.now())
    }

    /// Bedtime's offer, as the planner makes it, for the current owner.
    func offerBedtime(_ reminders: [LocalReminder]) async {
        let owner = BedtimePlanner.Owner(account: AccountBinding(env), epoch: env.persistence.epoch.current)
        await scheduler.offerBedtime(.these(reminders), owner: owner)
    }

    /// The auth service's session observation is listening (before a sign-out or a sign-in).
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    /// The rig's own centre for the clock and time-zone notifications: a test posting there reaches only its scheduler.
    let center = NotificationCenter()

    func watch() {
        scheduler.watch(journal: journal, push: push, center: center)
    }

    /// One debounced pass: waits for its timer, moves the clock past it, waits for the pass.
    func afterDebounce() async {
        let passes = scheduler.passes
        #expect(await eventually { clock.pendingSleeps >= 1 })
        clock.advance(by: ReminderScheduler.debounce)
        #expect(await eventually { scheduler.passes > passes })
        await scheduler.rescheduleNow()   // folds in anything that came with it, and waits for every pass
    }

    func ids(_ kind: ReminderKind) -> [String] {
        notifier.requests.map(\.identifier).filter { $0.hasPrefix(kind.prefix) }.sorted()
    }

    func reminder(_ id: String) -> LocalReminder? {
        notifier.requests.first { $0.identifier == id }.flatMap(LocalReminder.init)
    }

    /// The system calls so far: enumerations, adds, removals, status and delivered reads.
    var calls: [Int] {
        [notifier.pendingReads, notifier.adds, notifier.removals, notifier.statusReads, notifier.deliveredReads]
    }

    func quiet(_ from: String, _ to: String) {
        user?.notifications = NotificationPrefs(categories: NotificationPrefs.allOn.categories,
                                                quietHours: QuietHours(from: from, to: to))
    }

    func record(_ account: UUID) {
        env.persistence.saveDocument(PushRegistrar.Record(account: account.uuidString, token: "0a0b", env: .sandbox,
                                                          locale: "en-DE"),
                                     key: PushRegistrar.recordKey, at: clock.now())
    }

    /// A request on iOS from before this process (a previous launch), with its owner key.
    func seed(_ reminders: [LocalReminder], owner: String?) async throws {
        for reminder in reminders { try await notifier.add(reminder.request) }
        defaults.set(owner, forKey: ReminderScheduler.ownerKey)
    }

    func switchDemo(on: Bool) {
        env.settings.demoMode = on
        state.reset()
    }
}

private func journalReminder(_ day: String, fire: DateComponents, account: UUID = accountA) -> LocalReminder {
    LocalReminder(id: "journal.\(day)", kind: .journal, fire: fire, title: "t", body: "b", category: "JOURNAL_REMINDER",
                  route: JournalReminderPlan.route(day), day: day, account: account.uuidString)
}

private func bedtimeReminder(_ wakeDay: String, fire: DateComponents, account: UUID = accountA) -> LocalReminder {
    LocalReminder(id: "bedtime.\(wakeDay)", kind: .bedtime, fire: fire, title: "Wind down", body: "In bed by 22:40.",
                  category: PushCategories.bedtime, route: nil, day: wakeDay, account: account.uuidString)
}

// MARK: - 3: the not-syncing fallback

@MainActor
@Suite("Reminders: not syncing on this iPhone")
struct ReminderFallbackTests {
    @Test("20 h and 72 h after the last sync, in 09:00–21:00, with the account and SYNC_STALE")
    func followsTheLastSync() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.syncStale) == ["sync.stale.1", "sync.stale.2"])
        let one = try #require(rig.reminder("sync.stale.1"))
        #expect(one.fire == Berlin.wall(2026, 11, 23, 10) && one.account == accountA.uuidString && one.category == "SYNC_STALE")
        #expect(rig.reminder("sync.stale.2")?.fire == Berlin.wall(2026, 11, 25, 14))
        #expect(rig.notifier.requests.allSatisfy { $0.content.threadIdentifier == $0.content.categoryIdentifier })
    }

    @Test("Out of quiet hours: their end, if that's inside the daytime")
    func leavesQuietHours() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.quiet("08:00", "12:00")
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        #expect(rig.reminder("sync.stale.1")?.fire == Berlin.wall(2026, 11, 23, 12))
        #expect(rig.reminder("sync.stale.2")?.fire == Berlin.wall(2026, 11, 25, 14))
    }

    @Test("None without a last sync")
    func noneWithoutASync() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.syncStale).isEmpty && rig.notifier.adds == 0)
    }

    @Test("A sync within the hour costs no call; one an hour later moves both; one earlier moves them back")
    func hysteresis() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.watch()
        let first = rig.clock.now()
        rig.env.settings.lastSync = first
        #expect(await eventually { rig.notifier.adds == 2 })
        let calls = rig.calls

        rig.clock.set(first.addingTimeInterval(59 * 60))
        rig.env.settings.lastSync = rig.clock.now()
        let passes = rig.scheduler.passes
        #expect(await eventually { rig.scheduler.passes > passes })
        await rig.scheduler.rescheduleNow()
        #expect(rig.calls == calls, "59 minutes later: kept, no system call")
        #expect(rig.reminder("sync.stale.1")?.fire == Berlin.wall(2026, 11, 23, 10))

        rig.clock.set(first.addingTimeInterval(3600))
        rig.env.settings.lastSync = rig.clock.now()
        #expect(await eventually { rig.notifier.adds == 4 }, "an hour later: both moved")
        #expect(rig.reminder("sync.stale.1")?.fire == Berlin.wall(2026, 11, 23, 11))
        #expect(rig.reminder("sync.stale.2")?.fire == Berlin.wall(2026, 11, 25, 15))

        rig.env.settings.lastSync = first.addingTimeInterval(-10 * 60)
        #expect(await eventually { rig.reminder("sync.stale.1")?.fire == Berlin.wall(2026, 11, 23, 9, 50) },
                "earlier (the clock set back): moved")
    }

    @Test("A held, a failed and a locked run write no last sync: nothing moves; a run that uploads does")
    func onlyASuccessfulRunMovesIt() async throws {
        let t = Date(timeIntervalSince1970: 1_792_300_000)
        let page = HealthDelta(samples: (0..<2).map {
            Sample(type: .heartRate, start: t.addingTimeInterval(Double($0) * 60), end: t.addingTimeInterval(Double($0) * 60),
                   value: 60, unit: "bpm", source: "Garmin")
        })
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [page]])
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14), health: health)
        rig.watch()
        let sync = SyncService.ungated(env: rig.env)

        sync.gate = { .gate(.consentRequired) }
        _ = try? await sync.upload()
        sync.gate = { nil }
        rig.api.failNext = APIError.http(500, "unavailable")
        _ = try? await sync.upload()
        health.nextError = HKError(.errorDatabaseInaccessible)
        _ = try? await sync.upload()
        #expect(sync.waitingForUnlock)
        await rig.scheduler.rescheduleNow()
        #expect(rig.env.settings.lastSync == nil && rig.ids(.syncStale).isEmpty)

        _ = try? await sync.upload()
        #expect(rig.env.settings.lastSync == rig.clock.now())
        #expect(await eventually { rig.ids(.syncStale) == ["sync.stale.1", "sync.stale.2"] })
    }

    @Test("A silent push refreshes days without an upload: no last sync, nothing scheduled")
    func silentPush() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.watch()
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: rig.state, sync: SyncService.ungated(env: rig.env),
                                                               apiStatus: APIStatus()),
                                          clock: rig.clock)
        _ = await coordinator.run(.silentPush(days: ["2026-11-21"]))
        await rig.scheduler.rescheduleNow()
        #expect(rig.env.settings.lastSync == nil && rig.notifier.adds == 0)
    }
}

// MARK: - 4: one path for "not syncing"

@MainActor
@Suite("Reminders: the server's or this iPhone's")
struct ReminderDedupeTests {
    @Test("push.enabled on with this account's registration: the server says it, ours go; off again, they're back")
    func aFlagFlip() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.record(accountA)
        rig.watch()
        rig.env.settings.lastSync = rig.clock.now()
        #expect(await eventually { rig.ids(.syncStale).count == 2 }, ".thisIPhone while the flag is off")

        rig.flags.setOverride(.pushEnabled, true)
        await rig.afterDebounce()
        #expect(rig.ids(.syncStale).isEmpty, ".server")

        rig.flags.setOverride(.pushEnabled, false)
        await rig.afterDebounce()
        #expect(rig.ids(.syncStale).count == 2)
    }

    @Test("An accepted registration takes them away; its removal at a sign-out's first step brings them back")
    func anAcceptedRegistration() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.flags.setOverride(.pushEnabled, true)
        rig.watch()
        rig.env.settings.lastSync = rig.clock.now()
        #expect(await eventually { rig.ids(.syncStale).count == 2 }, "no registration yet: this iPhone")

        await rig.push.didRegister(deviceToken: Data([0x0a, 0x0b]))
        #expect(rig.env.persistence.document(PushRegistrar.Record.self, key: PushRegistrar.recordKey) != nil)
        await rig.afterDebounce()
        #expect(rig.ids(.syncStale).isEmpty)

        await rig.push.signOut()
        await rig.afterDebounce()
        #expect(rig.ids(.syncStale).count == 2)
    }

    @Test("Another account's registration isn't this one's: this iPhone says it")
    func anotherAccountsRecord() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.record(accountB)
        rig.flags.setOverride(.pushEnabled, true)
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.syncStale).count == 2)
    }

    @Test("SYNC_STALE off: none, and the scheduled ones go when the preferences change")
    func off() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.syncStale).count == 2)
        var categories = NotificationPrefs.allOn.categories
        categories[NotificationCategory.syncStale.rawValue] = false
        rig.user?.notifications = NotificationPrefs(categories: categories, quietHours: nil)
        rig.scheduler.reschedule(.preferences)
        await rig.afterDebounce()
        #expect(rig.ids(.syncStale).isEmpty)
    }
}

// MARK: - 5: unknown never removes

@MainActor
@Suite("Reminders: what isn't known stays")
struct ReminderUnknownTests {
    @Test("A pass before the journal's catalog is known and before bedtime's first offer leaves theirs")
    func unknownStays() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 6))
        try await rig.seed([journalReminder("2026-11-21", fire: Berlin.wall(2026, 11, 22, 9)),
                            bedtimeReminder("2026-11-23", fire: Berlin.wall(2026, 11, 22, 22, 10))],
                           owner: accountA.uuidString)
        rig.scheduler.connect(journal: rig.journal)
        #expect(rig.journal.availability == .unknown)
        let calls = rig.calls
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.journal) == ["journal.2026-11-21"] && rig.ids(.bedtime) == ["bedtime.2026-11-23"])
        #expect(rig.notifier.removals == calls[2] && rig.notifier.adds == calls[1])
    }

    @Test("Before iOS's answer is read the plans aren't asked; the first pass reads pending and the status once")
    func readsOnce() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        #expect(rig.notifier.pendingReads == 1 && rig.notifier.statusReads == 1)
        let calls = rig.calls
        for _ in 0..<3 { await rig.scheduler.rescheduleNow() }
        #expect(rig.calls == calls, "a pass that changes nothing makes no system call")
    }
}

// MARK: - 6: accounts

@MainActor
@Suite("Reminders: whose they are")
struct ReminderAccountTests {
    @Test("The sign-out wipe leaves nothing, pending or delivered, wake alarms and server alerts included")
    func theWipe() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        try await rig.notifier.add(UNNotificationRequest(identifier: "wake.0", content: UNMutableNotificationContent(),
                                                         trigger: nil))
        rig.notifier.deliver("recovery-2026-11-22")
        rig.notifier.deliver("journal.2026-11-21")
        rig.scheduler.journalSettings.set(JournalReminderSettings(on: true, minute: 8 * 60))
        #expect(rig.defaults.string(forKey: ReminderScheduler.ownerKey) == accountA.uuidString)
        #expect(rig.defaults.data(forKey: JournalReminderStore.key(accountA.uuidString)) != nil)
        await rig.settle()

        await rig.auth.signOut()
        #expect(rig.notifier.requests.isEmpty && rig.notifier.deliveredIDs.isEmpty)
        #expect(rig.defaults.string(forKey: ReminderScheduler.ownerKey) == nil)
        #expect(rig.defaults.data(forKey: JournalReminderStore.key(accountA.uuidString)) == nil)
        #expect(rig.scheduler.ledgerIDs == nil, "forgotten in the same turn")
    }

    @Test("A pass on its way for A adds nothing after the wipe, and takes back what landed")
    func aPassInFlight() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.env.settings.lastSync = rig.clock.now()
        await rig.settle()
        let hold = AddHold()
        rig.notifier.beforeAdd = { _ in await hold.wait() }
        let pass = Task { await rig.scheduler.rescheduleNow() }
        #expect(await eventually { hold.waiting == 1 })

        await rig.auth.signOut()
        #expect(rig.notifier.requests.isEmpty)
        hold.release()
        await pass.value

        #expect(rig.notifier.requests.isEmpty, "the one that landed after the wipe went again")
        #expect(rig.notifier.adds == 1, "the second never went")
        #expect(rig.defaults.string(forKey: ReminderScheduler.ownerKey) == nil)
    }

    @Test("Another account: A's go before B's first one is added")
    func accountChanged() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14), wipesNotifications: false)
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        #expect(rig.notifier.requests.count == 2)
        await rig.settle()
        await rig.auth.signOut()
        rig.client.emit(.signedIn, .preview(id: accountB))
        #expect(await eventually { rig.auth.accountID == accountB.uuidString })
        #expect(rig.notifier.requests.count == 2, "a wipe resumed store-only left A's on iOS")

        var atFirstAdd: [String]?
        rig.notifier.beforeAdd = { _ in
            if atFirstAdd == nil { atFirstAdd = rig.notifier.requests.compactMap { LocalReminder($0)?.account } }
        }
        rig.env.settings.lastSync = rig.clock.now().addingTimeInterval(-3600)
        await rig.scheduler.accountChanged()
        #expect(atFirstAdd == [], "nothing of A's left when B's first one went")
        #expect(rig.notifier.requests.compactMap { LocalReminder($0)?.account } == [accountB.uuidString, accountB.uuidString])
        #expect(rig.defaults.string(forKey: ReminderScheduler.ownerKey) == accountB.uuidString)
    }

    @Test("Another owner at the first pass, or none and another account's requests: they go, bedtime's too; a wake alarm stays")
    func theOwnerCheck() async throws {
        for owner in [accountB.uuidString, nil] {
            let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
            try await rig.seed([journalReminder("2026-11-22", fire: Berlin.wall(2026, 11, 23, 9), account: accountB),
                                bedtimeReminder("2026-11-23", fire: Berlin.wall(2026, 11, 22, 22, 10), account: accountB)],
                               owner: owner)
            try await rig.notifier.add(UNNotificationRequest(identifier: "wake.3", content: UNMutableNotificationContent(),
                                                             trigger: nil))
            await rig.scheduler.rescheduleNow()
            #expect(rig.notifier.requests.map(\.identifier) == ["wake.3"], "owner \(owner ?? "none")")
            #expect(rig.defaults.string(forKey: ReminderScheduler.ownerKey) == accountA.uuidString)
        }
    }

    @Test("Demo data freezes the account's (no add, no remove); off again they follow")
    func demoFreezes() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        let before = rig.notifier.requests
        let (adds, removals) = (rig.notifier.adds, rig.notifier.removals)

        rig.switchDemo(on: true)
        rig.env.settings.lastSync = rig.clock.now().addingTimeInterval(2 * 3600)
        await rig.scheduler.rescheduleNow()
        rig.scheduler.reschedule(.demo)
        await rig.afterDebounce()
        #expect(rig.notifier.adds == adds && rig.notifier.removals == removals)
        #expect(zip(rig.notifier.requests, before).allSatisfy { $0 === $1 } && rig.notifier.requests.count == before.count)

        rig.switchDemo(on: false)
        await rig.scheduler.rescheduleNow()
        #expect(rig.reminder("sync.stale.1")?.fire == Berlin.wall(2026, 11, 23, 12), "the sync two hours later, now")
    }

    @Test("Signed out (Demo data or not): nothing of ours stays")
    func signedOut() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14), wipesNotifications: false)
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        await rig.settle()
        await rig.auth.signOut()
        rig.switchDemo(on: true)
        await rig.scheduler.accountChanged()
        #expect(rig.notifier.requests.isEmpty && rig.defaults.string(forKey: ReminderScheduler.ownerKey) == nil)
    }

    @Test("On app active a delivered journal reminder about a day other than yesterday goes; others stay")
    func oldDeliveredJournal() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        for id in ["journal.2026-11-20", "journal.2026-11-21", "journal.2026-11-19", "recovery-2026-11-22", "sync.stale.1"] {
            rig.notifier.deliver(id)
        }
        await rig.scheduler.rescheduleNow()
        #expect(rig.notifier.deliveredIDs.count == 5 && rig.notifier.deliveredReads == 0, "only app active looks")

        rig.scheduler.reschedule(.appActive)
        await rig.afterDebounce()
        #expect(rig.notifier.deliveredIDs == ["journal.2026-11-21", "recovery-2026-11-22", "sync.stale.1"])
        #expect(rig.notifier.deliveredReads == 1)
    }
}

// MARK: - 1, 2: the journal reminder

@MainActor
@Suite("Reminders: the journal")
struct ReminderJournalTests {
    private let today = local.startOfDay(for: .now)
    private func day(_ offset: Int) -> String {
        reminderDay(local.date(byAdding: .day, value: offset, to: today) ?? today, calendar: local)
    }
    private func at(_ hour: Int) -> Date { local.date(bySettingHour: hour, minute: 0, second: 0, of: today) ?? today }

    /// A rig at `hour` today whose journal is live with habits on.
    private func liveRig(at hour: Int) async -> ReminderRig {
        let rig = ReminderRig(at: at(hour), calendar: local)
        rig.scheduler.connect(journal: rig.journal)
        await rig.journal.load()
        #expect(rig.journal.isLive && !rig.journal.enabledBehaviors.isEmpty)
        return rig
    }

    @Test("Live with habits: the next three mornings; off, none; at another time, there")
    func followsItsSettings() async throws {
        let rig = await liveRig(at: 8)
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.journal) == ["journal.\(day(-1))", "journal.\(day(0))", "journal.\(day(1))"])
        let first = try #require(rig.reminder("journal.\(day(-1))"))
        #expect(first.fire.hour == 9 && first.route == "https://ryftlab.de/journal/\(day(-1))")

        rig.scheduler.journalSettings.set(JournalReminderSettings(on: false, minute: 9 * 60))
        await rig.afterDebounce()
        #expect(rig.ids(.journal).isEmpty)

        rig.scheduler.journalSettings.set(JournalReminderSettings(on: true, minute: 10 * 60 + 15))
        await rig.afterDebounce()
        #expect(rig.ids(.journal).count == 3 && rig.reminder("journal.\(day(-1))")?.fire.minute == 15)
    }

    @Test("Not allowed any more (read again at app active): they go")
    func denied() async {
        let rig = await liveRig(at: 8)
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.journal).count == 3)
        rig.notifier.status = .denied
        rig.scheduler.reschedule(.appActive)
        await rig.afterDebounce()
        #expect(rig.ids(.journal).isEmpty)
    }

    @Test("Saving yesterday takes its reminder off iOS in the same turn, before any pass")
    func savingYesterday() async throws {
        let rig = await liveRig(at: 8)
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.journal).contains("journal.\(day(-1))"))
        let passes = rig.scheduler.passes
        try await rig.journal.save(day: day(-1), entries: [])
        #expect(!rig.ids(.journal).contains("journal.\(day(-1))") && rig.scheduler.passes == passes)
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.journal) == ["journal.\(day(0))", "journal.\(day(1))"], "and no pass brings it back")
    }

    @Test("Saved after it was shown: the delivered one goes too")
    func savingDelivered() async throws {
        let rig = await liveRig(at: 8)
        await rig.scheduler.rescheduleNow()
        rig.clock.set(at(10))
        rig.notifier.deliver("journal.\(day(-1))")
        try await rig.journal.save(day: day(-1), entries: [])
        #expect(rig.notifier.deliveredIDs.isEmpty)
    }

    @Test("A read that finds yesterday answered (on another device) does the same")
    func answeredElsewhere() async {
        let rig = await liveRig(at: 8)
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.journal).contains("journal.\(day(-1))"))
        let answered = await rig.journal.loadDay(day(-1))
        #expect(answered?.answered == true, "the mock platform answers yesterday as answered")
        #expect(!rig.ids(.journal).contains("journal.\(day(-1))"))
    }

    @Test("A save in Demo data leaves the account's reminder")
    func demoSave() async throws {
        let rig = await liveRig(at: 8)
        await rig.scheduler.rescheduleNow()
        rig.switchDemo(on: true)
        await rig.journal.load()
        try await rig.journal.save(day: day(-1), entries: [])
        #expect(rig.ids(.journal).contains("journal.\(day(-1))"))
    }

    @Test("The background refresh reads yesterday only while its reminder is still to come, and not again once answered")
    func readYesterdayIfOwed() async {
        let rig = await liveRig(at: 8)
        await rig.scheduler.rescheduleNow()
        await rig.scheduler.readYesterdayIfOwed()
        #expect(rig.api.count("journal") == 1)
        #expect(!rig.ids(.journal).contains("journal.\(day(-1))"))
        await rig.scheduler.readYesterdayIfOwed()
        #expect(rig.api.count("journal") == 1, "known answered: not asked again")

        let late = ReminderRig(at: at(10), calendar: local)
        late.scheduler.connect(journal: late.journal)
        await late.journal.load()
        await late.scheduler.readYesterdayIfOwed()
        #expect(late.api.count("journal") == 0, "today's reminder is gone by: nothing to take away")
    }

    /// Review code 1: the read is the journal reminder's, so it waits behind the reminder's gates (the positive case is
    /// `readYesterdayIfOwed`: open, it reads once).
    @Test("Behind the reminder's gates: the flag known off, the flag not known, consent withdrawn; no journal read",
          arguments: ["flag off", "flag not known", "consent withdrawn"])
    func readYesterdayIsGated(_ gate: String) async {
        let rig = await liveRig(at: 8)
        switch gate {
        case "flag off":
            rig.flags.setOverride(.notificationsReminders, nil)
            rig.answer(["notifications.reminders": false])
            #expect(rig.flags.known(.notificationsReminders) == false)
        case "flag not known":
            rig.flags.setOverride(.notificationsReminders, nil)
            #expect(rig.flags.known(.notificationsReminders) == nil)
        default:
            rig.env.consent.withdrew(at: rig.clock.now())
            #expect(rig.env.consent.withdrawnAt != nil)
        }
        await rig.scheduler.readYesterdayIfOwed()
        #expect(rig.api.count("journal") == 0, "\(gate)")
    }

    @Test("The journal read is on the background session, with iOS's answer read first; not allowed, none")
    func readsInTheBackground() async {
        let rig = await liveRig(at: 8)
        await rig.scheduler.readYesterdayIfOwed()
        #expect(rig.api.backgroundCalls == ["journal"] && rig.notifier.statusReads == 1)

        let denied = await liveRig(at: 8)
        denied.notifier.status = .denied
        await denied.scheduler.readYesterdayIfOwed()
        #expect(denied.api.count("journal") == 0, "no reminder to take away")
    }
}

// MARK: - 8 and §11

@MainActor
@Suite("Reminders: the budget and the cost")
struct ReminderBudgetTests {
    @Test("More than 32 wished: Debug says so, and the soonest are kept")
    func overBudget() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 1, 12))
        let wished = (0..<40).map { i in
            bedtimeReminder(String(format: "2026-11-%02d", 2 + i % 28) + "-\(i)",
                            fire: Berlin.wall(2026, 11, 1, 13, 0).with(minute: i))
        }
        let owner = BedtimePlanner.Owner(account: AccountBinding(rig.env), epoch: rig.env.persistence.epoch.current)
        await rig.scheduler.offerBedtime(.these(wished), owner: owner)
        #expect(rig.overBudget == [40])
        #expect(rig.ids(.bedtime).count == ReminderScheduler.budget)
        #expect(Set(rig.notifier.requests.compactMap { LocalReminder($0)?.fire.minute }) == Set(0..<32))
    }

    @Test("50 syncs inside an hour move the fallback at most once")
    func fiftySyncs() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.watch()
        let first = rig.clock.now()
        rig.env.settings.lastSync = first
        #expect(await eventually { rig.notifier.adds == 2 })
        for i in 1...50 {
            rig.clock.set(first.addingTimeInterval(Double(i) * 72))
            rig.env.settings.lastSync = rig.clock.now()
            await Task.yield()
        }
        #expect(await eventually { rig.scheduler.passes > 1 }, "the syncs asked for passes")
        await rig.scheduler.rescheduleNow()   // and every one asked for is done
        #expect(rig.notifier.adds <= 4, "one move of .1 and .2 at most: \(rig.notifier.adds - 2) adds")
        #expect(rig.reminder("sync.stale.1")?.fire == Berlin.wall(2026, 11, 23, 11))
    }

    @Test("Ten app actives within 500 ms: one pass")
    func tenAppActives() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        for _ in 0..<10 {
            rig.scheduler.reschedule(.appActive)
            rig.clock.advance(by: .milliseconds(40))
        }
        #expect(await eventually { rig.clock.pendingSleeps == 1 })
        rig.clock.advance(by: .milliseconds(500))
        #expect(await eventually { rig.scheduler.passes == 1 })
        for _ in 0..<20 { await Task.yield() }
        #expect(rig.scheduler.passes == 1)
    }
}

private extension DateComponents {
    func with(minute: Int) -> DateComponents {
        var c = self
        c.minute = minute
        return c
    }
}

/// Holds calls until released (an `add` on its way); once released, later calls go straight through, so a pass that
/// goes on adding finishes and the test's checks (not its time limit) catch it.
@MainActor
private final class AddHold {
    private(set) var waiting = 0
    private var released = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        waiting += 1
        guard !released else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func release() {
        released = true
        let all = continuations
        continuations = []
        for c in all { c.resume() }
    }
}

// MARK: - 7: bedtime on the scheduler

@MainActor
@Suite("Reminders: bedtime's wind-down through the scheduler")
struct ReminderBedtimeTests {
    @Test("A bedtime that moves is offered again without reading iOS: only the first pass of the process enumerates")
    func noEnumeration() async throws {
        let api = MockPlatformAPI()
        let clock = TestClock()
        clock.set(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: clock.now()) ?? clock.now())
        let notifier = MockNotifier()
        notifier.status = .authorized
        let state = AppState(env: .test(api: api, clock: clock, notifier: notifier, flags: [.sleepPlanner: true]))
        let shift = ShiftBox(), now = clock.now()
        api.planFor = { _ in
            let wake = Calendar.current.date(byAdding: .day, value: 1,
                                             to: Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: now) ?? now) ?? now
            let bed = wake.addingTimeInterval(-578 * 60 + shift.value)
            return SleepPlan(wake: wake, needMin: 520, inBedMin: 578, efficiency: 90, bedtime100: bed,
                             bedtime85: bed.addingTimeInterval(3_600), bedtime70: bed.addingTimeInterval(7_200),
                             basis: SleepPlanBasis(base: 460, strainTopup: 30, debtTopup: 30, napCredit: 0, efficiency: 90))
        }
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var schedule = SleepSchedule.default
        schedule.reminderOn = true
        await planner.update(schedule)
        let tonight = try #require(notifier.requests.first { $0.identifier.hasPrefix("bedtime.") })
        #expect(notifier.pendingReads == 1)
        #expect(state.reminders.ledgerIDs?.contains(tonight.identifier) == true, "the planner's requests are the scheduler's")
        #expect(LocalReminder(tonight)?.account == state.env.auth.accountID)

        shift.value = 12 * 60
        await planner.refresh()
        #expect(notifier.requests.first { $0.identifier == tonight.identifier }?.content.body != tonight.content.body, "moved")
        schedule.reminderOn = false
        await planner.update(schedule)
        #expect(!notifier.requests.contains { $0.identifier.hasPrefix("bedtime.") }, "turned off: gone")
        #expect(notifier.pendingReads == 1, "neither the move nor the removal read iOS's pending set")
    }

    @Test("The wake notifications go by their fixed ids, without an enumeration")
    func wakeByID() async throws {
        let notifier = MockNotifier()
        for i in 0..<7 {
            try await notifier.add(UNNotificationRequest(identifier: "wake.\(i)", content: UNMutableNotificationContent(),
                                                         trigger: nil))
        }
        try await notifier.add(UNNotificationRequest(identifier: "bedtime.2026-11-23", content: UNMutableNotificationContent(),
                                                     trigger: nil))
        await SystemWakeAlarms(notifier: notifier).cancelAll()
        #expect(notifier.requests.map(\.identifier) == ["bedtime.2026-11-23"] && notifier.pendingReads == 0)
    }
}

// MARK: - round 2: a morning with every kind

/// 08:00 today on this iPhone's calendar (the mock journal answers by the real day): the journal live with habits and a
/// sync just now. `bedtime()` is a wind-down for tomorrow evening.
@MainActor
private enum LiveMorning {
    static var today: Date { local.startOfDay(for: .now) }

    static func day(_ offset: Int) -> String {
        reminderDay(local.date(byAdding: .day, value: offset, to: today) ?? today, calendar: local)
    }

    static func rig() async -> ReminderRig {
        let rig = ReminderRig(at: local.date(bySettingHour: 8, minute: 0, second: 0, of: today) ?? today, calendar: local)
        rig.scheduler.connect(journal: rig.journal)
        await rig.journal.load()
        rig.env.settings.lastSync = rig.clock.now()
        return rig
    }

    static func bedtime() -> LocalReminder {
        let tomorrow = local.dateComponents([.year, .month, .day], from: local.date(byAdding: .day, value: 1, to: today) ?? today)
        return bedtimeReminder(day(2), fire: DateComponents(year: tomorrow.year, month: tomorrow.month, day: tomorrow.day,
                                                            hour: 22, minute: 10))
    }

    /// A journal reminder for yesterday, at 09:00 today.
    static func journalForYesterday() -> LocalReminder {
        let fire = local.dateComponents([.year, .month, .day], from: today)
        return journalReminder(day(-1), fire: DateComponents(year: fire.year, month: fire.month, day: fire.day, hour: 9,
                                                             minute: 0))
    }
}

// MARK: - round 2, B-1: dark behind notifications.reminders

@MainActor
@Suite("Reminders: the journal's and the fallback's behind notifications.reminders")
struct ReminderFlagTests {
    private func day(_ offset: Int) -> String { LiveMorning.day(offset) }
    private func bedtime() -> LocalReminder { LiveMorning.bedtime() }

    /// `LiveMorning`'s, with the flag as `flag` says: an answer with the key on or off, or (nil) no answer and no override.
    private func rig(flag: Bool?) async -> ReminderRig {
        let rig = await LiveMorning.rig()
        rig.flags.setOverride(.notificationsReminders, nil)
        if let flag { rig.answer(["notifications.reminders": flag]) }
        return rig
    }

    @Test("On: the journal's three mornings and the fallback's two, beside bedtime's")
    func on() async {
        let rig = await rig(flag: true)
        await rig.offerBedtime([bedtime()])
        #expect(rig.ids(.journal).count == 3 && rig.ids(.syncStale).count == 2 && rig.ids(.bedtime) == ["bedtime.\(day(2))"])
    }

    @Test("Known off (the answer has it off, or doesn't name it): none of theirs; bedtime's is set")
    func off() async {
        for flags in [["notifications.reminders": false], [:]] {
            let rig = await rig(flag: nil)
            rig.answer(flags)
            #expect(rig.flags.known(.notificationsReminders) == false)
            await rig.offerBedtime([bedtime()])
            #expect(rig.ids(.journal).isEmpty && rig.ids(.syncStale).isEmpty, "\(flags)")
            #expect(rig.ids(.bedtime) == ["bedtime.\(day(2))"], "\(flags)")
        }
    }

    @Test("Not known (no config cached: a background launch): what's on iOS stays, nothing is added")
    func unknown() async throws {
        let rig = await rig(flag: nil)
        #expect(rig.flags.known(.notificationsReminders) == nil)
        let kept = LiveMorning.journalForYesterday()
        try await rig.seed([kept], owner: accountA.uuidString)
        let adds = rig.notifier.adds
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.journal) == [kept.id] && rig.ids(.syncStale).isEmpty)
        #expect(rig.notifier.adds == adds && rig.notifier.removals == 0)
    }

    @Test("On, then turned off (a newer answer, pending or not): theirs go at once, bedtime's stays")
    func onThenOff() async {
        let rig = await rig(flag: true)
        rig.watch()
        await rig.offerBedtime([bedtime()])
        #expect(rig.ids(.journal).count == 3 && rig.ids(.syncStale).count == 2)

        rig.answer(["notifications.reminders": false])
        #expect(rig.flags.isOn(.notificationsReminders), "pending: the screens still show the answer before")
        await rig.afterDebounce()
        #expect(rig.ids(.journal).isEmpty && rig.ids(.syncStale).isEmpty)
        #expect(rig.ids(.bedtime) == ["bedtime.\(day(2))"])
    }
}

// MARK: - round 2, S-1: consent

@MainActor
@Suite("Reminders: the journal's and the fallback's pause while consent is withdrawn or refused")
struct ReminderConsentTests {
    @Test("A withdrawal on this iPhone takes them away, bedtime's stays; agreeing again brings them back")
    func withdrawal() async {
        let rig = await LiveMorning.rig()
        rig.watch()
        await rig.offerBedtime([LiveMorning.bedtime()])
        #expect(rig.ids(.journal).count == 3 && rig.ids(.syncStale).count == 2)

        rig.env.consent.withdrew(at: rig.clock.now())
        await rig.afterDebounce()
        #expect(rig.ids(.journal).isEmpty && rig.ids(.syncStale).isEmpty)
        #expect(rig.ids(.bedtime) == ["bedtime.\(LiveMorning.day(2))"])

        rig.env.consent.consented(to: "2026-11-01", at: rig.clock.now())
        await rig.afterDebounce()
        #expect(rig.ids(.journal).count == 3 && rig.ids(.syncStale).count == 2)
    }

    @Test("A standing refusal at the consent or the invite gate holds them until the platform clears it",
          arguments: [APIErrorCode.consentRequired, .inviteRequired])
    func refusal(_ code: APIErrorCode) async {
        let rig = await LiveMorning.rig()
        rig.watch()
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.journal).count == 3 && rig.ids(.syncStale).count == 2)

        rig.env.consent.refused(code, at: rig.clock.now())
        await rig.afterDebounce()
        #expect(rig.ids(.journal).isEmpty && rig.ids(.syncStale).isEmpty, "\(code)")

        rig.env.consent.cleared(code)
        await rig.afterDebounce()
        #expect(rig.ids(.journal).count == 3 && rig.ids(.syncStale).count == 2, "\(code)")
    }

    /// Review N-3: a gate known shut takes what the two kinds left in Notification Center too (the fallback's two, the
    /// journal's for yesterday and today), in one call, once while it stays shut. Bedtime's and the server's stay.
    @Test("Shut: their delivered ones go once while it stays shut; open and shut again, again; the flag off, the same")
    func deliveredGo() async {
        let rig = await LiveMorning.rig()
        rig.watch()
        await rig.scheduler.rescheduleNow()
        let theirs = ["sync.stale.1", "sync.stale.2", "journal.\(LiveMorning.day(-1))", "journal.\(LiveMorning.day(0))"]
        let others = ["bedtime.\(LiveMorning.day(1))", "morning-score-\(LiveMorning.day(0))"]
        func deliverAll() { for id in theirs + others { rig.notifier.deliver(id) } }
        deliverAll()
        await rig.scheduler.rescheduleNow()
        #expect(rig.notifier.deliveredIDs.count == 6, "open: they stay")

        rig.env.consent.withdrew(at: rig.clock.now())
        await rig.afterDebounce()
        #expect(rig.notifier.deliveredIDs == others, "withdrawn")
        deliverAll()
        let removals = rig.notifier.removals
        await rig.scheduler.rescheduleNow()
        #expect(rig.notifier.removals == removals && rig.notifier.deliveredIDs.count == 6, "still shut: no call")

        rig.env.consent.consented(to: "2026-11-01", at: rig.clock.now())
        await rig.afterDebounce()
        #expect(rig.notifier.deliveredIDs.count == 6 && rig.ids(.syncStale).count == 2, "open again: theirs are back")
        rig.env.consent.refused(.inviteRequired, at: rig.clock.now())
        await rig.afterDebounce()
        #expect(rig.notifier.deliveredIDs == others, "shut again: again")

        let off = await LiveMorning.rig()
        off.flags.setOverride(.notificationsReminders, false)
        for id in theirs + others { off.notifier.deliver(id) }
        await off.scheduler.rescheduleNow()
        #expect(off.notifier.deliveredIDs == others, "the flag known off: from the first pass")
    }
}

// MARK: - round 2, S-2: after a session ends

@MainActor
@Suite("Reminders: Notification Center after a session ends")
struct ReminderExpiryTests {
    @Test("Signed out after an expiry: alerts that arrived after the wipe go, once while signed out and at every app active")
    func signedOut() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        await rig.settle()
        await rig.auth.signOut(reason: .sessionExpired)
        rig.notifier.deliver("morning-score-2026-11-23")
        await rig.scheduler.rescheduleNow()
        #expect(rig.notifier.deliveredIDs.isEmpty && rig.notifier.requests.isEmpty)

        rig.notifier.deliver("record-2026-11-23")
        let removals = rig.notifier.removals
        await rig.scheduler.rescheduleNow()
        #expect(rig.notifier.removals == removals, "a pass that changes nothing makes no call")
        rig.scheduler.reschedule(.appActive)
        await rig.afterDebounce()
        #expect(rig.notifier.deliveredIDs.isEmpty)
    }

    @Test("Another account's owner key: its alerts in Notification Center go with ours; no owner key (an upgrade): they stay")
    func anotherOwner() async throws {
        for owner in [accountB.uuidString, nil] {
            let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
            try await rig.seed([], owner: owner)
            rig.notifier.deliver("morning-score-2026-11-22")
            await rig.scheduler.rescheduleNow()
            #expect(rig.notifier.deliveredIDs.isEmpty == (owner != nil), "\(owner ?? "no owner")")
            #expect(rig.defaults.string(forKey: ReminderScheduler.ownerKey) == accountA.uuidString)
        }
    }

    @Test("Locked: a session that only looks signed out, or an owner key that only reads empty, takes nothing away; a sync still plans")
    func locked() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14), wipesNotifications: false)
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        rig.notifier.deliver("morning-score-2026-11-22")
        rig.scheduler.isProtectedDataAvailable = { false }
        rig.env.settings.lastSync = rig.clock.now().addingTimeInterval(2 * 3600)
        await rig.scheduler.rescheduleNow()
        #expect(rig.notifier.adds == 4, "the fallback moved with a sync two hours on, locked")

        rig.defaults.set(accountB.uuidString, forKey: ReminderScheduler.ownerKey)
        let removals = rig.notifier.removals
        await rig.scheduler.rescheduleNow()
        await rig.settle()
        await rig.auth.signOut()
        rig.scheduler.forget()
        await rig.scheduler.rescheduleNow()
        #expect(rig.notifier.removals == removals && rig.ids(.syncStale).count == 2)
        #expect(rig.notifier.deliveredIDs.count == 1)

        rig.scheduler.isProtectedDataAvailable = { true }
        await rig.scheduler.rescheduleNow()
        #expect(rig.notifier.requests.isEmpty && rig.notifier.deliveredIDs.isEmpty)
    }

    @Test("The wipe's notification step, every reason: all of ours, APNs, the owner key; the journal setting but an expiry's account's",
          arguments: [AuthService.SignOutReason.user, .sessionExpired, .accountDeleted(background: false)])
    func theStep(_ reason: AuthService.SignOutReason) async throws {
        let notifier = MockNotifier()
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        try await notifier.add(UNNotificationRequest(identifier: "wake.0", content: UNMutableNotificationContent(), trigger: nil))
        try await notifier.add(UNNotificationRequest(identifier: "journal.2026-11-21", content: UNMutableNotificationContent(),
                                                     trigger: nil))
        notifier.deliver("morning-score-2026-11-22")
        defaults.set(accountA.uuidString, forKey: ReminderScheduler.ownerKey)
        for account in [accountA, accountB] {
            defaults.set(Data("{\"on\":false,\"minute\":540}".utf8), forKey: JournalReminderStore.key(account.uuidString))
        }
        var unregistered = 0
        AuthService.notificationStep(AuthService.Wipe(reason: reason, account: accountA.uuidString), center: notifier,
                                     defaults: defaults, unregister: { unregistered += 1 })
        #expect(notifier.requests.isEmpty && notifier.deliveredIDs.isEmpty)
        #expect(defaults.string(forKey: ReminderScheduler.ownerKey) == nil && unregistered == 1)
        #expect((defaults.data(forKey: JournalReminderStore.key(accountA.uuidString)) != nil) == (reason == .sessionExpired))
        #expect(defaults.data(forKey: JournalReminderStore.key(accountB.uuidString)) == nil, "another account's goes")
    }

    @Test("The push registrar forgets its APNs token with the account: the next send waits for a new one")
    func theToken() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.flags.setOverride(.pushEnabled, true)
        await rig.push.didRegister(deviceToken: Data([0x0a, 0x0b]))
        #expect(rig.api.count("registerPush") == 1 && rig.push.token != nil)
        rig.env.persistence.removeDocument(key: PushRegistrar.recordKey)
        rig.push.forgetAccount()
        await rig.push.send()
        #expect(rig.push.token == nil && rig.api.count("registerPush") == 1)
    }
}

// MARK: - round 2, S-4: the journal reminder's "off" through a session expiry

@MainActor
@Suite("Reminders: the journal reminder's setting through a session expiry")
struct ReminderJournalSettingTests {
    @Test("Off, then the session expires: signed in again it's still off; a sign-out clears it")
    func survivesExpiry() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        let off = JournalReminderSettings(on: false, minute: 9 * 60)
        #expect(rig.scheduler.journalSettings.set(off))
        await rig.settle()
        await rig.auth.signOut(reason: .sessionExpired)
        rig.client.emit(.signedIn, .preview(id: accountA))
        #expect(await eventually { rig.auth.accountID == accountA.uuidString })
        #expect(rig.scheduler.journalSettings.current == off)

        await rig.settle()
        await rig.auth.signOut()
        #expect(rig.scheduler.journalSettings.settings(for: accountA.uuidString) == .default)
    }

    /// Review N-4: what an expiry parks stays only until an account signs in; then only that account's setting stays.
    @Test("Parked by an expiry: another account signing in drops it, and any other account's; its own starts at the default")
    func anotherAccountDropsIt() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        let off = JournalReminderSettings(on: false, minute: 9 * 60)
        #expect(rig.scheduler.journalSettings.set(off))
        await rig.settle()
        await rig.auth.signOut(reason: .sessionExpired)
        let parked = JournalReminderStore.key(accountA.uuidString), stray = JournalReminderStore.key("account-c")
        #expect(rig.defaults.object(forKey: parked) != nil, "parked")
        rig.defaults.set(Data("{\"on\":false,\"minute\":600}".utf8), forKey: stray)

        rig.client.emit(.signedIn, .preview(id: accountB))
        #expect(await eventually { rig.auth.accountID == accountB.uuidString })
        #expect(rig.defaults.object(forKey: parked) == nil && rig.defaults.object(forKey: stray) == nil)
        #expect(rig.scheduler.journalSettings.current == .default)
        let later = JournalReminderSettings(on: true, minute: 10 * 60)
        #expect(rig.scheduler.journalSettings.set(later))
        #expect(rig.scheduler.journalSettings.settings(for: accountB.uuidString) == later)
    }
}

// MARK: - round 2, S1: the first launch after the update

@MainActor
@Suite("Reminders: the first launch after the update (no owner key)")
struct ReminderUpgradeTests {
    /// What a build before N3 put on iOS for tonight and tomorrow: a bedtime reminder without `ryft.account` or a day.
    private func earlierBuilds(_ rig: ReminderRig) async throws {
        for (day, fire) in [("2026-11-23", Berlin.wall(2026, 11, 22, 22, 10)), ("2026-11-24", Berlin.wall(2026, 11, 23, 22, 10))] {
            let content = UNMutableNotificationContent()
            content.title = "Wind down"
            content.categoryIdentifier = PushCategories.bedtime
            try await rig.notifier.add(UNNotificationRequest(identifier: "bedtime.\(day)", content: content,
                                                             trigger: UNCalendarNotificationTrigger(dateMatching: fire,
                                                                                                     repeats: false)))
        }
    }

    @Test("A sync-started pass keeps an earlier build's bedtime reminders and Notification Center; the planner's first offer replaces them")
    func earlierBedtime() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        try await earlierBuilds(rig)
        rig.notifier.deliver("morning-score-2026-11-22")
        #expect(rig.defaults.string(forKey: ReminderScheduler.ownerKey) == nil)
        rig.watch()
        rig.env.settings.lastSync = rig.clock.now()
        #expect(await eventually { rig.ids(.syncStale).count == 2 })
        #expect(rig.ids(.bedtime) == ["bedtime.2026-11-23", "bedtime.2026-11-24"])
        #expect(rig.notifier.deliveredIDs == ["morning-score-2026-11-22"], "the upgrade removes nothing delivered")
        #expect(rig.defaults.string(forKey: ReminderScheduler.ownerKey) == accountA.uuidString)

        await rig.offerBedtime([bedtimeReminder("2026-11-24", fire: Berlin.wall(2026, 11, 23, 22, 10))])
        #expect(rig.ids(.bedtime) == ["bedtime.2026-11-24"])
        #expect(rig.reminder("bedtime.2026-11-24")?.account == accountA.uuidString, "replaced with whose it is")
    }

    @Test("No owner key: each request's own account decides; this account's stay, another's go")
    func perRequest() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        try await rig.seed([journalReminder("2026-11-22", fire: Berlin.wall(2026, 11, 23, 9)),
                            journalReminder("2026-11-23", fire: Berlin.wall(2026, 11, 24, 9), account: accountB),
                            bedtimeReminder("2026-11-23", fire: Berlin.wall(2026, 11, 22, 22, 10), account: accountB)],
                           owner: nil)
        let removals = rig.notifier.removals
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.bedtime).isEmpty && rig.ids(.journal) == ["journal.2026-11-22"])
        #expect(rig.notifier.removals == removals + 1, "another's in one call")
    }
}

// MARK: - round 2, S2: the time zone

@MainActor
@Suite("Reminders: a time-zone change")
struct ReminderTimeZoneTests {
    @Test("Berlin to New York between passes: the zone's notification asks for a pass; the fallback's wall times are New York's")
    func newYork() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.watch()
        let synced = rig.clock.now()
        rig.env.settings.lastSync = synced
        #expect(await eventually { rig.ids(.syncStale).count == 2 })
        let id = try #require(rig.ids(.syncStale).first)
        #expect(rig.reminder(id)?.fire == Berlin.wall(2026, 11, 23, 10), "20 hours after 14:00, Berlin's 10:00")

        var newYork = Berlin.calendar
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        rig.scheduler.calendar = newYork
        rig.center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await rig.afterDebounce()
        let moved = try #require(rig.reminder(id))
        #expect(moved.fire == DateComponents(year: 2026, month: 11, day: 23, hour: 9, minute: 0),
                "Berlin's 10:00 is New York's 04:00: the window's start, 09:00 there")
        let at = try #require(moved.fireDate(in: newYork))
        #expect(at >= synced.addingTimeInterval(20 * 3600))
    }

    @Test("The clock's significant change asks for a pass too")
    func clockChange() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.watch()
        await rig.scheduler.rescheduleNow()
        let passes = rig.scheduler.passes
        rig.center.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        await rig.afterDebounce()
        #expect(rig.scheduler.passes > passes)
    }
}

// MARK: - round 2, S3: notifications not allowed

@MainActor
@Suite("Reminders: notifications not allowed")
struct ReminderDeniedTests {
    @Test("Denied: no add is tried, bedtime's offer neither; a removal still goes; allowed again, they're added")
    func denied() async throws {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        await rig.offerBedtime([bedtimeReminder("2026-11-23", fire: Berlin.wall(2026, 11, 22, 22, 10))])
        #expect(rig.ids(.bedtime) == ["bedtime.2026-11-23"])

        rig.notifier.status = .denied
        rig.scheduler.reschedule(.appActive)
        await rig.afterDebounce()
        var tried = 0
        rig.notifier.beforeAdd = { _ in tried += 1 }
        let tonight = bedtimeReminder("2026-11-24", fire: Berlin.wall(2026, 11, 23, 22, 10))
        await rig.offerBedtime([tonight])
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        #expect(tried == 0 && rig.notifier.requests.isEmpty, "nothing tried; the bedtime one not wanted any more went")

        rig.notifier.status = .authorized
        rig.scheduler.reschedule(.appActive)
        await rig.afterDebounce()
        #expect(tried == 3 && rig.ids(.bedtime) == ["bedtime.2026-11-24"] && rig.ids(.syncStale).count == 2)
    }

    /// Review code 2: a pass decides by the answer it read. Here it reads "denied", then waits on Notification Center
    /// (an app active asked it to look), and the app becomes active again meanwhile, which forgets the answer. Its wishes
    /// and its adds still go by "denied": the fallback's go, and bedtime's offer isn't tried.
    @Test("The app active again while a denied pass reads Notification Center: the pass keeps the answer it read")
    func oneAnswerPerPass() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.syncStale).count == 2)

        rig.notifier.status = .denied
        rig.scheduler.reschedule(.appActive)
        var tried = 0, activeAgain = false
        rig.notifier.beforeAdd = { _ in tried += 1 }
        rig.notifier.beforeDelivered = {
            guard !activeAgain else { return }
            activeAgain = true
            rig.scheduler.reschedule(.appActive)
        }
        await rig.offerBedtime([bedtimeReminder("2026-11-23", fire: Berlin.wall(2026, 11, 22, 22, 10))])
        #expect(activeAgain && rig.notifier.deliveredReads == 1, "the pass waited on Notification Center")
        #expect(tried == 0 && rig.ids(.bedtime).isEmpty, "denied when read: no add tried")
        #expect(rig.ids(.syncStale).isEmpty, "the fallback's went by the same answer")
    }
}

// MARK: - round 2, S4: what a pass reads

@MainActor
@Suite("Reminders: a pass reads the journal's misses, the registration and the setting once")
struct ReminderCostTests {
    @Test("Misses aren't fetched again; a day stored, the account's change and a saved registration are read afresh")
    func memo() async throws {
        let rig = await LiveMorning.rig()
        let day = LiveMorning.day(-10)
        #expect(rig.journal.cachedDay(day) == nil)
        rig.env.accountDocuments?.saveDocument(JournalDay(day: day, answered: true, answeredAt: nil, editable: true, entries: []),
                                               key: JournalStore.dayKey(day), at: rig.clock.now())
        #expect(rig.journal.cachedDay(day) == nil, "a miss is remembered")
        rig.journal.accountChanged()
        #expect(rig.journal.cachedDay(day)?.answered == true, "forgotten with the account")

        rig.flags.setOverride(.pushEnabled, true)
        rig.watch()
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.syncStale).count == 2)
        await rig.push.didRegister(deviceToken: Data([0x0a, 0x0b]))
        await rig.afterDebounce()
        #expect(rig.ids(.syncStale).isEmpty, "the saved registration was read afresh")
    }

    @Test("The setting is decoded once per account; a write and the wipe's turn read it again")
    func settings() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        let store = rig.scheduler.journalSettings
        #expect(store.settings(for: accountA.uuidString) == .default)
        rig.defaults.set(Data("{\"on\":false,\"minute\":540}".utf8), forKey: JournalReminderStore.key(accountA.uuidString))
        #expect(store.settings(for: accountA.uuidString) == .default, "remembered")
        rig.scheduler.forget()
        #expect(store.settings(for: accountA.uuidString) == JournalReminderSettings(on: false, minute: 540))
        #expect(store.set(JournalReminderSettings(on: true, minute: 600)))
        #expect(store.settings(for: accountA.uuidString) == JournalReminderSettings(on: true, minute: 600))
    }
}

// MARK: - round 2, nits

@MainActor
@Suite("Reminders: Demo data during the adds, and the owner key's writes")
struct ReminderRoundTwoTests {
    @Test("Demo data switched on during the adds: what landed stays, the account's own")
    func demoDuringAdds() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14))
        rig.env.settings.lastSync = rig.clock.now()
        var switched = false
        rig.notifier.beforeAdd = { _ in
            guard !switched else { return }
            switched = true
            rig.switchDemo(on: true)
        }
        let removals = rig.notifier.removals
        await rig.scheduler.rescheduleNow()
        #expect(rig.ids(.syncStale) == ["sync.stale.1"] && rig.notifier.removals == removals)
    }

    @Test("A pass that changes nothing writes no default, the owner key included; signed out, neither")
    func ownerKeyWrites() async {
        let rig = ReminderRig(at: Berlin.at(2026, 11, 22, 14), wipesNotifications: false)
        rig.env.settings.lastSync = rig.clock.now()
        await rig.scheduler.rescheduleNow()
        var writes = 0
        let token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: rig.defaults,
                                                           queue: nil) { _ in writes += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        for _ in 0..<3 { await rig.scheduler.rescheduleNow() }
        #expect(writes == 0)

        await rig.settle()
        await rig.auth.signOut()
        await rig.scheduler.rescheduleNow()
        let afterSignOut = writes
        for _ in 0..<3 { await rig.scheduler.rescheduleNow() }
        #expect(writes == afterSignOut)
    }
}
