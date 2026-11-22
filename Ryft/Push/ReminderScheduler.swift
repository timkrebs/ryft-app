import Foundation
import OSLog
import UIKit
import UserNotifications

/// Why a pass was asked for (coalesced; the signpost names them).
enum ReminderReason: String, Sendable {
    case appActive, backgroundRefresh, synced, journal, journalSettings, preferences, push, bedtime, account, demo, timeChange
}

/// What the plans read, from their owners, never a stored copy (design.md §3.1). The settings, flags, push record and
/// last sync come from the environment; these two from the app's models.
@MainActor
struct ReminderInputs {
    /// The cached user (`Repository.user()`): its notification preferences and quiet hours, as last fetched.
    var user: () -> User?
    /// The journal (`ScreenModels` connects the app's). Nil: not known, so the journal's reminders stay as they are.
    var journal: () -> JournalStore?
    /// Reads what changes with the cached user (its revision), for the preferences' watch: no fetch until a pass needs one.
    var observeUser: () -> Void = {}

    static let none = ReminderInputs(user: { nil }, journal: { nil })
}

/// The one writer of RYFT's local notification requests (ADR 0024): bedtime's wind-down, the journal reminder and the
/// "not syncing" fallback. Each kind is a pure plan (`ReminderPlans.swift`); a pass diffs what the plans want against
/// the ledger of what it put on iOS and adds and removes only the difference, so a pass that changes nothing makes no
/// system call. One pass at a time; triggers are coalesced into one pass per 500 ms (`reschedule`), a successful sync
/// and bedtime's offer run one at once.
///
/// - **iOS is read once per process** (`pending()`, at the first pass, and again only after `forget()`). The owner key
///   (`notifications.owner`) says whose requests iOS holds: another account's, or none, and ours go first.
/// - **Owner.** Every pass captures the account binding, the store's epoch and its own generation, and re-checks them
///   after each await. Signed out, it tears our kinds down; with Demo data on it freezes (adds, moves and removes
///   nothing: the account's stay, as bedtime's always did). Adds that landed after the owner changed are taken away again.
/// - **Unknown never removes:** a kind whose inputs aren't known yet keeps what it has (a background launch before the
///   journal's catalog is read, bedtime before the planner's first offer).
@MainActor
final class ReminderScheduler {
    /// The scheduler's own kinds at most (19 today with the wake alarms, against iOS's 64). Debug asserts; Release keeps the
    /// soonest.
    static let budget = 32
    static let debounce: Duration = .milliseconds(500)
    /// Whose requests iOS holds (per install).
    static let ownerKey = "notifications.owner"
    static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "reminders")

    private let env: AppEnvironment
    var inputs: ReminderInputs
    private let calendar: Calendar
    /// The journal reminder's switch and time (the page writes it; a change asks for a pass).
    let journalSettings: JournalReminderStore

    /// What this scheduler put on iOS, by id. Nil: not read from iOS in this process yet (or forgotten).
    private var ledger: [String: LocalReminder]?
    /// iOS's answer, read once per process and on every app active (nil: not read yet).
    private var authorization: UNAuthorizationStatus?
    /// Bedtime's last offer, and whose it was: only that owner's is used.
    private var bedtime: (wish: ReminderWish, owner: AccountBinding)?
    /// Bumped by `forget()`: a pass that began before it adds nothing after it.
    private var generation = 0
    private var debounced: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var again = false
    /// The next pass reads Notification Center (app active): a journal reminder about a day before yesterday goes.
    private var readsDelivered = false
    /// Journal days whose reminder went at their answer in this process (pending and delivered): never added again.
    private var answeredDays: Set<String> = []
    private var watches: [ObservationWatch] = []
    private var timeObserver: NSObjectProtocol?

    /// Wishes over the budget (Debug asserts; tests count).
    var overBudget: (Int) -> Void = { count in
        assertionFailure("ReminderScheduler: \(count) local reminders wished, over the budget of \(ReminderScheduler.budget)")
    }
    /// Passes run (tests, the profiler).
    private(set) var passes = 0

    init(env: AppEnvironment, inputs: ReminderInputs, calendar: Calendar = .current) {
        self.env = env
        self.inputs = inputs
        self.calendar = calendar
        journalSettings = JournalReminderStore(env: env)
        journalSettings.onChange = { [weak self] in self?.reschedule(.journalSettings) }
    }

    private var now: Date { env.clock.now() }
    private var defaults: UserDefaults { env.defaults }
    private var yesterday: String { reminderDay(calendar.date(byAdding: .day, value: -1, to: now) ?? now, calendar: calendar) }

    // MARK: triggers

    /// A pass soon: coalesced with every other trigger within 500 ms on the app's clock. Returns at once.
    func reschedule(_ reason: ReminderReason) {
        if reason == .appActive {
            // Allowed or turned off in Settings meanwhile; and Notification Center is looked at once.
            authorization = nil
            readsDelivered = true
        }
        guard debounced == nil else { return }
        // An absolute due time: a task that starts late fires at once rather than a whole step late.
        let due = now.addingTimeInterval(Self.debounce.timeInterval)
        let gen = generation
        debounced = Task { [weak self] in
            guard let self else { return }
            let wait = due.timeIntervalSince(self.now)
            if wait > 0 { try? await self.env.clock.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, gen == self.generation else { return }
            self.debounced = nil
            await self.passNow()
        }
    }

    /// One pass now, awaited (the BG refresh's completion waits for it). A pending debounce is folded into it.
    func rescheduleNow() async {
        debounced?.cancel()
        debounced = nil
        await passNow()
    }

    /// `Settings.lastSync` moved (a run that uploaded): the fallback follows at once, without a debounce, on the next
    /// main-actor turn. A HealthKit delivery's completion isn't held for it.
    func synced() {
        Task { [weak self] in await self?.passNow() }
    }

    /// `BedtimePlanner`'s only write (design.md §12 (d)): its requests for `owner`, applied in a pass now and awaited, so
    /// they're on iOS when the planner's pass ends. An offer for an owner that isn't current is dropped.
    func offerBedtime(_ wish: ReminderWish, owner: BedtimePlanner.Owner) async {
        guard owner.account.isCurrent(in: env), owner.epoch == env.persistence.epoch.current else { return }
        bedtime = (wish, owner.account)
        await passNow()
    }

    /// Yesterday's journal was answered (the sheet's save, or a read that found it answered, also from another device):
    /// its reminder goes from iOS, pending and delivered, in this turn, before any pass. Demo data's answers never take the
    /// account's away.
    /// Days before yesterday have none pending, and a delivered one goes at the next app active: no call for them.
    func answered(journalDay day: String) {
        guard !env.isDemo, env.auth.accountID != nil, !answeredDays.contains(day), day >= yesterday else { return }
        answeredDays.insert(day)
        let id = ReminderKind.journal.prefix + day
        env.notifier.removePending(ids: [id])
        env.notifier.removeDelivered(ids: [id])
        ledger?[id] = nil
    }

    /// Another account (or none): this side's requests go from the ledger at once, then a pass for whoever is current
    /// (RyftApp's account change, and `finishOwedWipe`). That account starts with no journal setting, schedule or last sync.
    func accountChanged() async {
        generation += 1
        debounced?.cancel()
        debounced = nil
        bedtime = nil
        answeredDays = []
        tearDown()
        await passNow()
    }

    /// The sign-out wipe's turn (an account-state forgetter, as `BedtimePlanner.forget` is): a pass that began for the
    /// leaving account adds nothing after it, the ledger is dropped (the next pass reads iOS again) and the debounce goes.
    func forget() {
        generation += 1
        debounced?.cancel()
        debounced = nil
        ledger = nil
        bedtime = nil
        answeredDays = []
    }

    /// The sign-out wipe (any reason): every pending and delivered RYFT notification, without an enumeration, and whose
    /// they were. Never reads `AppEnvironment.live` (ADR 0020): the caller hands the centre in.
    static func wipe(_ center: NotificationWiping, defaults: UserDefaults) {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        defaults.removeObject(forKey: ownerKey)
        JournalReminderStore.wipe(defaults: defaults)
    }

    /// The journal the plans read (`ScreenModels`): its habits, whether it's live and its answers; a day it finds answered
    /// takes its reminder away at once.
    func connect(journal: JournalStore) {
        inputs.journal = { [weak journal] in journal }
        journal.onAnswered = { [weak self] day in self?.answered(journalDay: day) }
    }

    /// The app's triggers (RyftApp, once; tests that need them): a successful sync, the user's notification preferences,
    /// `push.enabled`, the journal's habits and whether it's live, an accepted or removed push registration, a time zone or
    /// clock change.
    func watch(journal: JournalStore, push: PushRegistrar) {
        connect(journal: journal)
        push.onRecordChanged = { [weak self] in self?.reschedule(.push) }
        let settings = env.settings, flags = env.flags, user = inputs.observeUser
        watches = [
            ObservationWatch(read: { _ = settings.lastSync }, changed: { [weak self] in self?.synced() }),
            ObservationWatch(read: { user() }, changed: { [weak self] in self?.reschedule(.preferences) }),
            ObservationWatch(read: { _ = flags.isOn(.pushEnabled) }, changed: { [weak self] in self?.reschedule(.push) }),
            ObservationWatch(read: { [weak journal] in
                _ = journal?.availability
                _ = journal?.enabledBehaviors.isEmpty
            }, changed: { [weak self] in self?.reschedule(.journal) }),
        ]
        timeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reschedule(.timeChange) }
        }
    }

    /// The BG refresh's one journal read (design.md §4.3, lead decision Q5): yesterday's answer through the read pipeline,
    /// only when the reminder is on, yesterday isn't known answered and today's reminder is still ahead. A day answered on
    /// another device then takes its reminder away (`answered`) before the refresh's pass.
    func readYesterdayIfOwed() async {
        guard let journal = inputs.journal(), let account = env.auth.accountID, !env.isDemo, journal.isLive else { return }
        let yesterday = yesterday
        guard journal.cachedDay(yesterday)?.answered != true,
              case .these(let ahead) = JournalReminderPlan.wish(journalSettings.settings(for: account), habits: true,
                                                                answered: { _ in nil }, allowed: true, quiet: quiet,
                                                                account: account, now: now, calendar: calendar),
              ahead.contains(where: { $0.day == yesterday }) else { return }
        await journal.loadDay(yesterday)
    }

    // MARK: the pass

    /// A pass now, or once more after the one running; returns when the passes asked for so far are done.
    private func passNow() async {
        if let running {
            again = true
            await running.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.again = false
                await self.pass()
            } while self.again
            self.running = nil
        }
        running = task
        await task.value
    }

    private var allowed: Bool? {
        authorization.map { $0 == .authorized || $0 == .provisional || $0 == .ephemeral }
    }

    private var quiet: QuietHours? { inputs.user()?.notifications.quietHours }

    private func pass() async {
        passes += 1
        let gen = generation, binding = AccountBinding(env), epoch = env.persistence.epoch.current
        func current() -> Bool { gen == generation && binding == AccountBinding(env) && epoch == env.persistence.epoch.current }
        let signpost = Signposts.sync.beginInterval("reminders.pass", id: Signposts.sync.makeSignpostID())
        var added = 0, removed = 0
        defer { Signposts.sync.endInterval("reminders.pass", signpost, "adds \(added) removes \(removed)") }

        // iOS's pending requests, once per process: whose they are is the owner key's.
        if ledger == nil {
            let pending = await env.notifier.pending()
            guard current() else { return }
            ledger = Dictionary(pending.compactMap(LocalReminder.init).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        guard let account = binding.account else {
            // Signed out: nothing of ours stays (Demo data shown or not).
            removed += tearDown()
            defaults.removeObject(forKey: Self.ownerKey)
            return
        }
        if defaults.string(forKey: Self.ownerKey) != account {
            // Another account's, or nobody knows whose (a kill between a wipe and its removals, a wipe resumed store-only,
            // a restore): ours go first.
            removed += tearDown()
            defaults.set(account, forKey: Self.ownerKey)
        }
        // Demo data: the account's stay exactly as they are.
        guard !binding.demo else { return }
        if authorization == nil {
            let status = await env.notifier.authorizationStatus()
            guard current() else { return }
            authorization = status
        }
        if readsDelivered {
            readsDelivered = false
            removed += await removeOldDeliveredJournal()
            guard current() else { return }
        }

        let wishes = budgeted([
            .bedtime: bedtime.flatMap { $0.owner == binding ? $0.wish : nil } ?? .unknown,
            .journal: journalWish(account: account),
            .syncStale: syncStaleWish(account: account),
        ])
        guard var ledger else { return }
        var remove: [String] = [], add: [LocalReminder] = []
        for (kind, wish) in wishes {
            guard case .these(let want) = wish else { continue }
            let ids = Set(want.map(\.id))
            for (id, have) in ledger where have.kind == kind && !ids.contains(id) {
                // A one-shot that fired isn't pending any more: it leaves the ledger without a call.
                if let at = have.fireDate(in: calendar), at <= now {
                    ledger[id] = nil
                } else {
                    remove.append(id)
                }
            }
            add += want.filter { ledger[$0.id] != $0 && !($0.kind == .journal && answeredDays.contains($0.day)) }
        }
        if !remove.isEmpty {
            env.notifier.removePending(ids: remove.sorted())
            for id in remove { ledger[id] = nil }
            removed += remove.count
        }
        self.ledger = ledger
        var landed: [LocalReminder] = []
        for reminder in add.sorted(by: soonest) {
            guard current() else { break }
            do {
                try await env.notifier.add(reminder.request)
                landed.append(reminder)
            } catch {
                // Not allowed (any more): not in the ledger, so a later pass (app active reads the status again) tries.
                Self.log.notice("reminder not added: \(reminder.kind.rawValue, privacy: .public)")
            }
        }
        added = landed.count
        guard current() else {
            // The owner changed during the adds: what landed for the one that left goes again.
            if !landed.isEmpty { env.notifier.removePending(ids: landed.map(\.id)) }
            removed += landed.count
            return
        }
        // A day answered while its reminder was on its way to iOS: it goes again at once.
        let late = landed.filter { $0.kind == .journal && answeredDays.contains($0.day) }.map(\.id)
        if !late.isEmpty {
            env.notifier.removePending(ids: late)
            removed += late.count
        }
        for reminder in landed where !late.contains(reminder.id) { self.ledger?[reminder.id] = reminder }
        defaults.set(account, forKey: Self.ownerKey)
    }

    private func soonest(_ a: LocalReminder, _ b: LocalReminder) -> Bool {
        (a.fireDate(in: calendar) ?? .distantFuture) < (b.fireDate(in: calendar) ?? .distantFuture)
    }

    /// Removes every request of ours the ledger knows, in one call; returns how many.
    @discardableResult
    private func tearDown() -> Int {
        guard let ids = ledger?.keys, !ids.isEmpty else { return 0 }
        env.notifier.removePending(ids: ids.sorted())
        ledger = [:]
        return ids.count
    }

    /// A delivered journal reminder about a day other than yesterday says "yesterday" about the wrong day (ui.md §10).
    private func removeOldDeliveredJournal() async -> Int {
        let yesterday = yesterday
        let old = await env.notifier.delivered().filter {
            ReminderKind(id: $0) == .journal && $0 != ReminderKind.journal.prefix + yesterday
        }
        if !old.isEmpty { env.notifier.removeDelivered(ids: old) }
        return old.count
    }

    private func journalWish(account: String) -> ReminderWish {
        guard let journal = inputs.journal() else { return .unknown }
        let habits: Bool? = switch journal.availability {
        case .unknown: nil
        case .notLive: false
        case .live: !journal.enabledBehaviors.isEmpty
        }
        return JournalReminderPlan.wish(journalSettings.settings(for: account), habits: habits,
                                        answered: { journal.cachedDay($0)?.answered }, allowed: allowed, quiet: quiet,
                                        account: account, now: now, calendar: calendar)
    }

    private func syncStaleWish(account: String) -> ReminderWish {
        // Not known before the user's preferences or the authorization are: what's scheduled stays.
        let prefs = inputs.user()?.notifications
        let route = allowed.flatMap { allowed in prefs.map { prefs in
            SyncStaleRoute.decide(category: prefs.isOn(.syncStale),
                                  pushEnabled: env.flags.isOn(.pushEnabled), allowed: allowed,
                                  registered: env.persistence.document(PushRegistrar.Record.self,
                                                                       key: PushRegistrar.recordKey)?.account == account)
        } }
        let scheduled = (ledger ?? [:]).values.filter { $0.kind == .syncStale }.sorted { $0.id < $1.id }
        return SyncStalePlan.wish(lastSync: env.settings.lastSync, route: route, allowed: allowed, quiet: quiet,
                                  scheduled: scheduled, account: account, now: now, calendar: calendar)
    }

    /// The wishes within the budget: over it, Debug asserts and the soonest are kept.
    private func budgeted(_ wishes: [ReminderKind: ReminderWish]) -> [ReminderKind: ReminderWish] {
        let all = wishes.values.flatMap { wish -> [LocalReminder] in
            guard case .these(let list) = wish else { return [] }
            return list
        }
        guard all.count > Self.budget else { return wishes }
        overBudget(all.count)
        let kept = Set(all.sorted(by: soonest).prefix(Self.budget).map(\.id))
        return wishes.mapValues { wish in
            guard case .these(let list) = wish else { return wish }
            return .these(list.filter { kept.contains($0.id) })
        }
    }

    #if DEBUG
    /// Tests: what the scheduler believes iOS holds (nil: not read yet).
    var ledgerIDs: [String]? { ledger.map { $0.keys.sorted() } }
    #endif
}
