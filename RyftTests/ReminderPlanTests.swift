import Foundation
import Testing
import UserNotifications
@testable import Ryft

// N3 (design.md §3–§5, ADR 0024): the local reminders' pure parts. Every time is Europe/Berlin through an injected
// calendar, DST days included; nothing reads the device's zone. Synthetic data only.

enum Berlin {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return c
    }()

    static func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? .distantPast
    }

    /// A floating wall-clock minute, as a one-shot trigger carries it.
    static func wall(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> DateComponents {
        DateComponents(year: y, month: m, day: d, hour: h, minute: min)
    }
}

private func quiet(_ from: String, _ to: String) -> QuietHours { QuietHours(from: from, to: to) }

@Suite("Quiet hours on local reminders")
struct QuietWindowTests {
    @Test("Inside from `from` up to, not including, `to`; equal times are none; across midnight both sides")
    func insideTheWindow() {
        let night = quiet("22:30", "07:00")
        #expect(QuietWindow.isQuiet(22 * 60 + 30, quiet: night) && QuietWindow.isQuiet(6 * 60 + 59, quiet: night))
        #expect(QuietWindow.isQuiet(0, quiet: night))
        #expect(!QuietWindow.isQuiet(7 * 60, quiet: night) && !QuietWindow.isQuiet(22 * 60 + 29, quiet: night))
        let lunch = quiet("12:00", "14:00")
        #expect(QuietWindow.isQuiet(12 * 60, quiet: lunch) && !QuietWindow.isQuiet(14 * 60, quiet: lunch))
        #expect(!QuietWindow.isQuiet(11 * 60 + 59, quiet: lunch))
        #expect(!QuietWindow.isQuiet(8 * 60, quiet: quiet("08:00", "08:00")), "equal times: none")
        #expect(!QuietWindow.isQuiet(8 * 60, quiet: quiet("8h", "09:00")), "malformed: none")
        #expect(!QuietWindow.isQuiet(8 * 60, quiet: nil))
    }

    @Test("A minute inside moves to the end: the same day, or the next for one after `from` across midnight")
    func movesToTheEnd() throws {
        let night = quiet("22:30", "07:00")
        let late = try #require(QuietWindow.firstAllowed(minute: 23 * 60, quiet: night, daytime: nil))
        #expect(late.days == 1 && late.minute == 7 * 60)
        let early = try #require(QuietWindow.firstAllowed(minute: 5 * 60, quiet: night, daytime: nil))
        #expect(early.days == 0 && early.minute == 7 * 60)
        let outside = try #require(QuietWindow.firstAllowed(minute: 9 * 60, quiet: night, daytime: nil))
        #expect(outside.days == 0 && outside.minute == 9 * 60)
    }

    @Test("With 09:00–21:00 too: before it moves to 09:00, after it to tomorrow's, and on out of quiet hours")
    func daytime() throws {
        let day = SyncStalePlan.daytime
        let before = try #require(QuietWindow.firstAllowed(minute: 6 * 60, quiet: nil, daytime: day))
        #expect(before.days == 0 && before.minute == 9 * 60)
        let after = try #require(QuietWindow.firstAllowed(minute: 21 * 60 + 1, quiet: nil, daytime: day))
        #expect(after.days == 1 && after.minute == 9 * 60)
        let edge = try #require(QuietWindow.firstAllowed(minute: 21 * 60, quiet: nil, daytime: day))
        #expect(edge.days == 0 && edge.minute == 21 * 60, "21:00 itself is inside")
        // 09:00 is quiet until 12:00.
        let held = try #require(QuietWindow.firstAllowed(minute: 6 * 60, quiet: quiet("08:00", "12:00"), daytime: day))
        #expect(held.days == 0 && held.minute == 12 * 60)
        // 23:00 is quiet until 07:00, which is before 09:00.
        let night = try #require(QuietWindow.firstAllowed(minute: 23 * 60, quiet: quiet("22:30", "07:00"), daytime: day))
        #expect(night.days == 1 && night.minute == 9 * 60)
        #expect(QuietWindow.firstAllowed(minute: 10 * 60, quiet: quiet("08:00", "22:00"), daytime: day) == nil,
                "quiet over the whole daytime: no minute is allowed")
    }

    @Test("From a date: floating components in the calendar's zone, the next day across a month's end")
    func fromADate() {
        let moved = QuietWindow.firstAllowed(atOrAfter: Berlin.at(2026, 11, 30, 23, 10), quiet: quiet("22:30", "07:00"),
                                             daytime: nil, calendar: Berlin.calendar)
        #expect(moved == Berlin.wall(2026, 12, 1, 7, 0))
        #expect(moved?.timeZone == nil && moved?.calendar == nil)
    }
}

@Suite("The journal reminder's plan")
struct JournalReminderPlanTests {
    private func wish(_ settings: JournalReminderSettings? = .default, habits: Bool? = true,
                      answered: [String: Bool] = [:], allowed: Bool? = true, quiet: QuietHours? = nil,
                      now: Date) -> ReminderWish {
        JournalReminderPlan.wish(settings, habits: habits, answered: { answered[$0] }, allowed: allowed, quiet: quiet,
                                 account: "acct-a", now: now, calendar: Berlin.calendar)
    }

    private func reminders(_ wish: ReminderWish) -> [LocalReminder] {
        guard case .these(let list) = wish else { return [] }
        return list
    }

    @Test("Three mornings at 09:00, floating, each asking about the day before: journal.<D−1>")
    func threeMornings() {
        let list = reminders(wish(now: Berlin.at(2026, 11, 22, 8)))
        #expect(list.map(\.id) == ["journal.2026-11-21", "journal.2026-11-22", "journal.2026-11-23"])
        #expect(list.map(\.fire) == [Berlin.wall(2026, 11, 22, 9), Berlin.wall(2026, 11, 23, 9), Berlin.wall(2026, 11, 24, 9)])
        #expect(list.allSatisfy { $0.kind == .journal && $0.category == "JOURNAL_REMINDER" && $0.account == "acct-a" })
        #expect(list.map(\.day) == ["2026-11-21", "2026-11-22", "2026-11-23"])
        #expect(list.first?.route == "https://ryftlab.de/journal/2026-11-21")
        #expect(list.allSatisfy { $0.title == ReminderCopy.journalTitle && $0.body == ReminderCopy.journalBody })
    }

    @Test("Today's 09:00 gone: the next three, from tomorrow")
    func pastTodaysTime() {
        let list = reminders(wish(now: Berlin.at(2026, 11, 22, 9, 0)))
        #expect(list.map(\.id) == ["journal.2026-11-22", "journal.2026-11-23", "journal.2026-11-24"])
        #expect(list.last?.fire == Berlin.wall(2026, 11, 25, 9))
    }

    @Test("None with the switch off, no habit, the journal not live or iOS saying no; unknown inputs keep what's there")
    func nothingOrUnknown() {
        let now = Berlin.at(2026, 11, 22, 8)
        #expect(wish(JournalReminderSettings(on: false, minute: 540), now: now) == .these([]))
        #expect(wish(habits: false, now: now) == .these([]), "no habit chosen (or not live)")
        #expect(wish(allowed: false, now: now) == .these([]), "denied")
        #expect(wish(habits: nil, now: now) == .unknown, "the catalog not known yet")
        #expect(wish(allowed: nil, now: now) == .unknown, "the authorization not read yet")
        #expect(wish(nil, now: now) == .unknown, "no account's settings")
        #expect(wish(JournalReminderSettings(on: false, minute: 540), habits: nil, now: now) == .these([]),
                "off is known even before the catalog")
    }

    @Test("An answered day has none; its morning still counts, so the window stays three mornings")
    func answeredDay() {
        let list = reminders(wish(answered: ["2026-11-21": true, "2026-11-22": false], now: Berlin.at(2026, 11, 22, 8)))
        #expect(list.map(\.id) == ["journal.2026-11-22", "journal.2026-11-23"])
    }

    @Test("A time inside quiet hours arrives at their end, never dropped")
    func quietHoursMoveIt() {
        let early = reminders(wish(JournalReminderSettings(on: true, minute: 6 * 60 + 30), quiet: quiet("22:30", "07:00"),
                                   now: Berlin.at(2026, 11, 22, 5)))
        #expect(early.map(\.fire) == [Berlin.wall(2026, 11, 22, 7), Berlin.wall(2026, 11, 23, 7), Berlin.wall(2026, 11, 24, 7)])
        #expect(early.first?.id == "journal.2026-11-21")
        let held = reminders(wish(quiet: quiet("08:00", "10:00"), now: Berlin.at(2026, 11, 22, 9, 30)))
        #expect(held.first?.fire == Berlin.wall(2026, 11, 22, 10), "09:00 is quiet until 10:00, still ahead at 09:30")
        #expect(held.first?.id == "journal.2026-11-21")
    }

    @Test("Quiet hours across midnight move a late time into the next morning, and it asks about the day before that")
    func acrossMidnight() {
        // 23:30 is quiet until 07:00: yesterday's 23:30 arrives this morning, about yesterday.
        let list = reminders(wish(JournalReminderSettings(on: true, minute: 23 * 60 + 30), quiet: quiet("22:30", "07:00"),
                                  now: Berlin.at(2026, 11, 22, 5)))
        #expect(list.map(\.fire) == [Berlin.wall(2026, 11, 22, 7), Berlin.wall(2026, 11, 23, 7), Berlin.wall(2026, 11, 24, 7)])
        #expect(list.map(\.id) == ["journal.2026-11-21", "journal.2026-11-22", "journal.2026-11-23"])
    }

    @Test("The days the clocks change keep 09:00 as the wall time: 23 h apart in spring, 25 h in autumn")
    func daylightSaving() throws {
        let spring = reminders(wish(now: Berlin.at(2026, 3, 28, 20)))
        #expect(spring.map(\.fire) == [Berlin.wall(2026, 3, 29, 9), Berlin.wall(2026, 3, 30, 9), Berlin.wall(2026, 3, 31, 9)])
        #expect(spring.map(\.id) == ["journal.2026-03-28", "journal.2026-03-29", "journal.2026-03-30"])
        let gap = try #require(Berlin.calendar.date(from: spring[0].fire))
            .timeIntervalSince(Berlin.at(2026, 3, 28, 9))
        #expect(gap == 23 * 3600)
        let autumn = reminders(wish(now: Berlin.at(2026, 10, 24, 20)))
        #expect(autumn.first?.fire == Berlin.wall(2026, 10, 25, 9))
        let longer = try #require(Berlin.calendar.date(from: autumn[0].fire)).timeIntervalSince(Berlin.at(2026, 10, 24, 9))
        #expect(longer == 25 * 3600)
    }
}

@Suite("The not-syncing fallback's plan")
struct SyncStalePlanTests {
    private let account = "acct-a"

    private func wish(lastSync: Date?, route: SyncStaleRoute? = .thisIPhone, allowed: Bool? = true,
                      quiet: QuietHours? = nil, scheduled: [LocalReminder] = [], now: Date) -> ReminderWish {
        SyncStalePlan.wish(lastSync: lastSync, route: route, allowed: allowed, quiet: quiet, scheduled: scheduled,
                           account: account, now: now, calendar: Berlin.calendar)
    }

    private func reminders(_ wish: ReminderWish) -> [LocalReminder] {
        guard case .these(let list) = wish else { return [] }
        return list
    }

    @Test("20 h and 72 h after the last sync, each in 09:00–21:00")
    func twentyAndSeventyTwo() {
        let sync = Berlin.at(2026, 11, 22, 14)
        let list = reminders(wish(lastSync: sync, now: sync))
        #expect(list.map(\.id) == ["sync.stale.1", "sync.stale.2"])
        #expect(list.map(\.fire) == [Berlin.wall(2026, 11, 23, 10), Berlin.wall(2026, 11, 25, 14)])
        #expect(list.allSatisfy { $0.category == "SYNC_STALE" && $0.kind == .syncStale && $0.route == nil })
        #expect(list.map(\.title) == [ReminderCopy.syncStaleTitle, ReminderCopy.syncStaleLaterTitle])
        // 10:00 + 20 h is 06:00: held to 09:00. 01:00 + 20 h is 21:00: inside. 02:00 + 20 h is 22:00: tomorrow's 09:00.
        #expect(reminders(wish(lastSync: Berlin.at(2026, 11, 22, 10), now: sync)).first?.fire == Berlin.wall(2026, 11, 23, 9))
        #expect(reminders(wish(lastSync: Berlin.at(2026, 11, 22, 1), now: sync)).first?.fire == Berlin.wall(2026, 11, 22, 21))
        #expect(reminders(wish(lastSync: Berlin.at(2026, 11, 22, 2), now: sync)).first?.fire == Berlin.wall(2026, 11, 23, 9))
    }

    @Test("Out of quiet hours too: the first minute outside them and inside the daytime")
    func quietHours() {
        let sync = Berlin.at(2026, 11, 22, 14)
        let held = reminders(wish(lastSync: sync, quiet: quiet("08:00", "12:00"), now: sync))
        #expect(held.first?.fire == Berlin.wall(2026, 11, 23, 12))
        let night = reminders(wish(lastSync: Berlin.at(2026, 11, 22, 3), quiet: quiet("22:30", "07:00"), now: sync))
        #expect(night.first?.fire == Berlin.wall(2026, 11, 23, 9), "23:00 is quiet; 07:00 is before the daytime")
    }

    @Test("None without a last sync, on the server's route or switched off; unknown route or authorization keeps them")
    func routes() {
        let now = Berlin.at(2026, 11, 22, 14)
        #expect(wish(lastSync: nil, now: now) == .these([]))
        #expect(wish(lastSync: now, route: .server, now: now) == .these([]), "the server says it where push reaches")
        #expect(wish(lastSync: now, route: .off, now: now) == .these([]))
        #expect(wish(lastSync: now, allowed: false, now: now) == .these([]), "iOS doesn't allow it")
        #expect(wish(lastSync: now, route: nil, now: now) == .unknown)
        #expect(wish(lastSync: now, allowed: nil, now: now) == .unknown)
    }

    @Test("The route: off with the switch off; the server's only with the flag, permission and this account's record")
    func decide() {
        #expect(SyncStaleRoute.decide(category: false, pushEnabled: true, allowed: true, registered: true) == .off)
        #expect(SyncStaleRoute.decide(category: true, pushEnabled: true, allowed: true, registered: true) == .server)
        #expect(SyncStaleRoute.decide(category: true, pushEnabled: false, allowed: true, registered: true) == .thisIPhone)
        #expect(SyncStaleRoute.decide(category: true, pushEnabled: true, allowed: false, registered: true) == .thisIPhone)
        #expect(SyncStaleRoute.decide(category: true, pushEnabled: true, allowed: true, registered: false) == .thisIPhone)
    }

    @Test("A sync less than an hour later keeps both; an hour or more later, or earlier, moves both")
    func hysteresis() {
        let first = Berlin.at(2026, 11, 22, 14)
        let scheduled = reminders(wish(lastSync: first, now: first))
        let soon = first.addingTimeInterval(59 * 60)
        #expect(wish(lastSync: soon, scheduled: scheduled, now: soon) == .these(scheduled), "59 minutes later: kept")
        let hour = first.addingTimeInterval(3600)
        let moved = reminders(wish(lastSync: hour, scheduled: scheduled, now: hour))
        #expect(moved.map(\.fire) == [Berlin.wall(2026, 11, 23, 11), Berlin.wall(2026, 11, 25, 15)], "an hour later: moved")
        let earlier = first.addingTimeInterval(-10 * 60)
        let back = reminders(wish(lastSync: earlier, scheduled: scheduled, now: first))
        #expect(back.first?.fire == Berlin.wall(2026, 11, 23, 9, 50), "earlier (the clock set back): moved")
    }

    @Test("One already past isn't asked for: a gap of a day keeps only the 72 h one")
    func pastOne() {
        let sync = Berlin.at(2026, 11, 21, 10)
        let list = reminders(wish(lastSync: sync, now: Berlin.at(2026, 11, 22, 12)))
        #expect(list.map(\.id) == ["sync.stale.2"])
    }

    @Test("Across the spring clock change: 20 h of elapsed time, at the new wall time")
    func daylightSaving() {
        let sync = Berlin.at(2026, 3, 28, 14)
        #expect(reminders(wish(lastSync: sync, now: sync)).first?.fire == Berlin.wall(2026, 3, 29, 11))
    }
}

@MainActor
@Suite("A local reminder on iOS and back")
struct LocalReminderTests {
    private let journal = LocalReminder(id: "journal.2026-11-21", kind: .journal, fire: Berlin.wall(2026, 11, 22, 9),
                                        title: "How was yesterday?", body: "A few taps.", category: "JOURNAL_REMINDER",
                                        route: "https://ryftlab.de/journal/2026-11-21", day: "2026-11-21", account: "acct-a")

    @Test("The request carries the server alerts' userInfo, the category as its thread, and a one-shot floating trigger")
    func request() throws {
        let request = journal.request
        #expect(request.identifier == "journal.2026-11-21")
        let info = try #require(request.content.userInfo["ryft"] as? [String: String])
        #expect(info == ["category": "JOURNAL_REMINDER", "day": "2026-11-21", "url": "https://ryftlab.de/journal/2026-11-21",
                         "account": "acct-a"])
        #expect(request.content.threadIdentifier == "JOURNAL_REMINDER" && request.content.categoryIdentifier == "JOURNAL_REMINDER")
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats && trigger.dateComponents == Berlin.wall(2026, 11, 22, 9))
        #expect(request.content.sound != nil)
        let stale = LocalReminder(id: "sync.stale.1", kind: .syncStale, fire: Berlin.wall(2026, 11, 23, 9), title: "t",
                                  body: "b", category: "SYNC_STALE", route: nil, day: "2026-11-23", account: "acct-a")
        #expect(stale.request.content.sound == nil, "the not-syncing hint arrives quietly")
        #expect((stale.request.content.userInfo["ryft"] as? [String: String])?["url"] == nil)
    }

    @Test("Read back from iOS it equals what was asked for; the one decoder reads it as an alert")
    func roundTrip() throws {
        #expect(LocalReminder(journal.request) == journal)
        let message = PushMessage(userInfo: journal.request.content.userInfo)
        #expect(message == .alert(category: nil, url: URL(string: "https://ryftlab.de/journal/2026-11-21")))
    }

    @Test("Any request with one of the prefixes is the scheduler's, also one without `ryft`; a wake alarm's isn't")
    func ours() {
        let bare = UNNotificationRequest(identifier: "bedtime.2026-11-20", content: UNMutableNotificationContent(), trigger: nil)
        let read = LocalReminder(bare)
        #expect(read?.kind == .bedtime && read?.account == "" && read?.fire == DateComponents())
        #expect(LocalReminder(UNNotificationRequest(identifier: "wake.0", content: UNMutableNotificationContent(),
                                                    trigger: nil)) == nil)
        #expect(ReminderKind(id: "sync.stale.2") == .syncStale && ReminderKind(id: "MORNING_SCORE") == nil)
    }

    @Test("A bedtime request as the planner builds it: its wake day and the account it was planned for")
    func bedtime() throws {
        let content = UNMutableNotificationContent()
        content.title = "Wind down"
        content.body = "In bed by 22:40."
        content.categoryIdentifier = PushCategories.bedtime
        let request = UNNotificationRequest(identifier: "bedtime.2026-11-23", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: Berlin.wall(2026, 11, 22, 22, 10),
                                                                                   repeats: false))
        let reminder = try #require(LocalReminder.bedtime(request, account: "acct-a"))
        #expect(reminder.day == "2026-11-23" && reminder.account == "acct-a" && reminder.route == nil)
        #expect(reminder.fire == Berlin.wall(2026, 11, 22, 22, 10) && reminder.request.content.sound != nil)
        #expect(LocalReminder(reminder.request) == reminder)
    }
}
