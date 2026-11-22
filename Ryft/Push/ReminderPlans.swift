import Foundation
import UserNotifications

// The local reminders' values and plans (ADR 0024, design.md §3): what each kind wants on iOS, as pure values. The one
// writer is `ReminderScheduler`; nothing here touches the notification centre.

/// RYFT's local notification kinds, by the prefix of their request ids.
enum ReminderKind: String, CaseIterable, Sendable {
    case bedtime, journal, syncStale

    var prefix: String {
        switch self {
        case .bedtime: "bedtime."
        case .journal: "journal."
        case .syncStale: "sync.stale."
        }
    }

    /// The kind whose prefix `id` has; nil for anything that isn't the scheduler's (a wake alarm, a server alert).
    init?(id: String) {
        guard let kind = Self.allCases.first(where: { id.hasPrefix($0.prefix) }) else { return nil }
        self = kind
    }

    /// Bedtime's wind-down and the journal's question play the default sound; the "not syncing" hint arrives quietly.
    var plays: Bool { self != .syncStale }
}

/// One request as RYFT wants it on iOS: pure and Equatable, so the scheduler's ledger compares these and tests assert them.
/// `fire` is a floating local time (year…minute, no time zone): a one-shot calendar trigger at that wall-clock minute.
struct LocalReminder: Equatable, Sendable {
    let id: String
    let kind: ReminderKind
    let fire: DateComponents
    let title: String
    let body: String
    let category: String
    /// `ryft.url`: where a tap goes (nil: Today).
    let route: String?
    /// `ryft.day`: the day it is about.
    let day: String
    /// `ryft.account`: whose it is. A tap or a foreground presentation for another account (or Demo data) opens Today only.
    let account: String

    init(id: String, kind: ReminderKind, fire: DateComponents, title: String, body: String, category: String,
         route: String?, day: String, account: String) {
        self.id = id
        self.kind = kind
        self.fire = Self.wallClock(fire)
        self.title = title
        self.body = body
        self.category = category
        self.route = route
        self.day = day
        self.account = account
    }

    /// Read back from iOS (the first pass of a process, design.md §3.4). Any request with one of the scheduler's prefixes
    /// is its own, also one an earlier build wrote without `ryft` (missing parts read empty, so no wish equals it and the
    /// next known wish replaces or removes it); nil for anything else.
    init?(_ request: UNNotificationRequest) {
        guard let kind = ReminderKind(id: request.identifier) else { return nil }
        let content = request.content
        let info = content.userInfo["ryft"] as? [String: Any] ?? [:]
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        self.init(id: request.identifier, kind: kind, fire: trigger?.dateComponents ?? DateComponents(),
                  title: content.title, body: content.body, category: content.categoryIdentifier,
                  route: info["url"] as? String, day: info["day"] as? String ?? "", account: info["account"] as? String ?? "")
    }

    /// A request `BedtimePlanner.reminders` built, as the scheduler keeps it: the account it was planned for, and its wake
    /// day (the id's suffix) as `ryft.day`. Nil for a request that isn't a bedtime reminder.
    static func bedtime(_ request: UNNotificationRequest, account: String) -> LocalReminder? {
        guard ReminderKind(id: request.identifier) == .bedtime else { return nil }
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        return LocalReminder(id: request.identifier, kind: .bedtime, fire: trigger?.dateComponents ?? DateComponents(),
                             title: request.content.title, body: request.content.body,
                             category: request.content.categoryIdentifier, route: nil,
                             day: String(request.identifier.dropFirst(ReminderKind.bedtime.prefix.count)), account: account)
    }

    /// The request iOS gets: the server alerts' `userInfo` shape (`ryft: {category, day, url, account}`), so one decoder and
    /// one tap path serve both (design.md §1.3); the thread is the category.
    var request: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if kind.plays { content.sound = .default }
        content.categoryIdentifier = category
        content.threadIdentifier = category
        var info: [String: String] = ["category": category, "day": day, "account": account]
        if let route { info["url"] = route }
        content.userInfo = ["ryft": info]
        return UNNotificationRequest(identifier: id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: fire, repeats: false))
    }

    /// When it fires in `calendar`'s time zone (nil for a request read back without a full date).
    func fireDate(in calendar: Calendar) -> Date? {
        guard fire.year != nil, fire.month != nil, fire.day != nil, fire.hour != nil, fire.minute != nil else { return nil }
        return calendar.date(from: fire)
    }

    /// Year, month, day, hour and minute only: what iOS hands back compares equal to what was asked for.
    static func wallClock(_ c: DateComponents) -> DateComponents {
        DateComponents(year: c.year, month: c.month, day: c.day, hour: c.hour, minute: c.minute)
    }
}

/// What a kind wants on iOS. `.unknown`: its inputs aren't known yet (a background launch before the journal's catalog
/// is read, bedtime before the planner's first pass), and its requests stay exactly as they are. Only a known wish removes.
enum ReminderWish: Equatable {
    case unknown
    case these([LocalReminder])
}

// MARK: - quiet hours

/// Quiet hours on local kinds (design.md §3.6): `User.notifications.quiet_hours`, as last fetched. Equal times mean none;
/// `from > to` spans midnight; a minute inside moves to the window's end. Bedtime and the wake alarm don't ask (ADR 0024 §4).
enum QuietWindow {
    /// "HH:MM" as minutes after midnight; nil when malformed.
    static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }

    /// Whether `minute` (after midnight) is inside quiet hours: from `from` up to, not including, `to`.
    static func isQuiet(_ minute: Int, quiet: QuietHours?) -> Bool {
        guard let quiet, let from = minutes(quiet.from), let to = minutes(quiet.to), from != to else { return false }
        return from < to ? (from..<to).contains(minute) : minute >= from || minute < to
    }

    /// The first minute at or after `minute` that is outside quiet hours and, with `daytime`, inside it (minutes after
    /// midnight, both ends allowed), as days after the given one and a minute. Nil when no minute of a day is allowed
    /// (quiet hours cover all of `daytime`).
    static func firstAllowed(minute: Int, quiet: QuietHours?, daytime: ClosedRange<Int>?) -> (days: Int, minute: Int)? {
        var days = 0, m = minute
        for _ in 0..<4 {
            var moved = false
            if isQuiet(m, quiet: quiet), let quiet, let from = minutes(quiet.from), let to = minutes(quiet.to) {
                // Across midnight, a minute after `from` ends tomorrow.
                if from > to, m >= from { days += 1 }
                m = to
                moved = true
            }
            if let daytime {
                if m < daytime.lowerBound {
                    m = daytime.lowerBound
                    moved = true
                } else if m > daytime.upperBound {
                    days += 1
                    m = daytime.lowerBound
                    moved = true
                }
            }
            if !moved { return (days, m) }
        }
        return nil
    }

    /// `firstAllowed` for a wall-clock day (year, month, day) and minute: the floating components of the allowed minute.
    static func firstAllowed(day: DateComponents, minute: Int, quiet: QuietHours?, daytime: ClosedRange<Int>?,
                             calendar: Calendar) -> DateComponents? {
        guard let (days, m) = firstAllowed(minute: minute, quiet: quiet, daytime: daytime),
              let start = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)),
              let moved = calendar.date(byAdding: .day, value: days, to: start) else { return nil }
        let d = calendar.dateComponents([.year, .month, .day], from: moved)
        return DateComponents(year: d.year, month: d.month, day: d.day, hour: m / 60, minute: m % 60)
    }

    /// The first allowed minute at or after `date` in `calendar`'s time zone, as floating components.
    static func firstAllowed(atOrAfter date: Date, quiet: QuietHours?, daytime: ClosedRange<Int>?,
                             calendar: Calendar) -> DateComponents? {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let hour = c.hour, let minute = c.minute else { return nil }
        return firstAllowed(day: c, minute: hour * 60 + minute, quiet: quiet, daytime: daytime, calendar: calendar)
    }
}

/// "YYYY-MM-DD" of `date` in `calendar` (the app passes `.current`, as `DayFormat` reads it).
func reminderDay(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

// MARK: - journal

/// The journal reminder's switch and time, on this iPhone per account (design.md §4.4): one time for every day, in
/// minutes after midnight (15-minute steps on the page). On by default at 09:00 for an account that chose habits (lead
/// decision Q1): it fires only for a journal set up and not answered.
struct JournalReminderSettings: Codable, Equatable, Sendable {
    var on: Bool
    var minute: Int

    static let `default` = JournalReminderSettings(on: true, minute: 9 * 60)
}

/// The journal reminder's plan (design.md §4): one request per morning for the next 3 mornings whose time (after the
/// quiet-hours move) is still ahead, each asking about the day before the one it fires on (`journal.<asked day>`), so its
/// "yesterday" is always right, also when quiet hours across midnight move it into the next day. None for a day already
/// answered (that morning still counts). Nothing while the switch is off, no habit is chosen, the journal isn't live or
/// iOS doesn't allow notifications; `.unknown` while the catalog or the authorization isn't known.
enum JournalReminderPlan {
    static let mornings = 3
    static let category = "JOURNAL_REMINDER"

    // swiftlint:disable function_parameter_count
    /// `habits`: some habit is on (nil: the catalog isn't known yet; false also when the journal isn't live). `answered`:
    /// what this iPhone knows of a day (nil: nothing). `allowed`: iOS lets RYFT notify (nil: not read yet).
    static func wish(_ settings: JournalReminderSettings?, habits: Bool?, answered: (String) -> Bool?, allowed: Bool?,
                     quiet: QuietHours?, account: String, now: Date, calendar: Calendar) -> ReminderWish {
        guard let settings else { return .unknown }
        guard settings.on, allowed != false, habits != false else { return .these([]) }
        guard habits != nil, allowed != nil else { return .unknown }
        let today = calendar.startOfDay(for: now)
        var reminders: [LocalReminder] = []
        var ahead: [String] = []
        // From yesterday's time (moved past midnight, it may still be ahead) until three are ahead.
        for offset in -1...mornings where ahead.count < mornings {
            guard let set = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = QuietWindow.firstAllowed(day: calendar.dateComponents([.year, .month, .day], from: set),
                                                      minute: settings.minute, quiet: quiet, daytime: nil, calendar: calendar),
                  let at = calendar.date(from: fire), at > now,
                  let asked = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: at)) else { continue }
            let day = reminderDay(asked, calendar: calendar)
            guard !ahead.contains(day) else { continue }
            ahead.append(day)
            guard answered(day) != true else { continue }
            reminders.append(LocalReminder(id: ReminderKind.journal.prefix + day, kind: .journal, fire: fire,
                                           title: ReminderCopy.journalTitle, body: ReminderCopy.journalBody,
                                           category: category, route: route(day), day: day, account: account))
        }
        return .these(reminders)
    }
    // swiftlint:enable function_parameter_count

    /// `ryft.url`: the journal sheet on the day it asks about.
    static func route(_ day: String) -> String { "https://\(AppRoute.host)/journal/\(day)" }
}

// MARK: - not syncing

/// Which path says "not syncing" for this iPhone (design.md §5.2): one switch (`categories.SYNC_STALE`) and one delivery
/// path at a time. The server's where push reaches this iPhone (`push.enabled` on, notifications allowed, this account's
/// registration accepted); otherwise the local fallback.
enum SyncStaleRoute: Equatable, Sendable {
    case off, server, thisIPhone

    static func decide(category: Bool, pushEnabled: Bool, allowed: Bool, registered: Bool) -> SyncStaleRoute {
        guard category else { return .off }
        return pushEnabled && allowed && registered ? .server : .thisIPhone
    }
}

/// The local "not syncing" fallback (design.md §5.1): `sync.stale.1` 20 h after the last successful sync and
/// `sync.stale.2` 72 h after it, each at the first minute outside quiet hours and inside 09:00–21:00, as the server's
/// `SYNC_STALE`. A sync moves them only when the new time is at least an hour later, or earlier: a burst of syncs costs
/// no system call, and at worst it fires an hour early.
enum SyncStalePlan {
    static let first: TimeInterval = 20 * 3600
    static let second: TimeInterval = 72 * 3600
    /// A later time within this keeps what's scheduled.
    static let keepWithin: TimeInterval = 3600
    /// 09:00–21:00, minutes after midnight.
    static let daytime = (9 * 60)...(21 * 60)
    static let firstID = ReminderKind.syncStale.prefix + "1"
    static let secondID = ReminderKind.syncStale.prefix + "2"

    // swiftlint:disable function_parameter_count
    /// `scheduled`: the `sync.stale.*` the scheduler put on iOS for this account (its ledger). `allowed`: iOS lets RYFT
    /// notify (nil: not read yet). `route` nil: not known yet.
    static func wish(lastSync: Date?, route: SyncStaleRoute?, allowed: Bool?, quiet: QuietHours?,
                     scheduled: [LocalReminder], account: String, now: Date, calendar: Calendar) -> ReminderWish {
        guard route != nil, allowed != nil else { return .unknown }
        guard route == .thisIPhone, allowed == true, let lastSync else { return .these([]) }
        let one = QuietWindow.firstAllowed(atOrAfter: lastSync.addingTimeInterval(first), quiet: quiet, daytime: daytime,
                                           calendar: calendar)
        if let one, let want = calendar.date(from: one),
           let kept = scheduled.first(where: { $0.id == firstID }), let keptAt = kept.fireDate(in: calendar),
           want >= keptAt, want.timeIntervalSince(keptAt) < keepWithin {
            // Kept: `.2` moves with `.1`.
            return .these(scheduled)
        }
        let two = QuietWindow.firstAllowed(atOrAfter: lastSync.addingTimeInterval(second), quiet: quiet, daytime: daytime,
                                           calendar: calendar)
        var reminders: [LocalReminder] = []
        for (id, fire, title, body) in [(firstID, one, ReminderCopy.syncStaleTitle, ReminderCopy.syncStaleBody),
                                        (secondID, two, ReminderCopy.syncStaleLaterTitle, ReminderCopy.syncStaleLaterBody)] {
            guard let fire, let at = calendar.date(from: fire), at > now else { continue }
            reminders.append(LocalReminder(id: id, kind: .syncStale, fire: fire, title: title, body: body,
                                           category: NotificationCategory.syncStale.rawValue, route: nil,
                                           day: reminderDay(at, calendar: calendar), account: account))
        }
        return .these(reminders)
    }
    // swiftlint:enable function_parameter_count
}

// MARK: - words

/// The local reminders' words (ui.md §5): static, so a request can sit pending for days and still be true; no health value
/// in a title, no habit name anywhere, no relative time beyond the journal's "yesterday" (its id is the day it asks about).
/// Symbolic keys, as the server's `loc-key`s.
enum ReminderCopy {
    static var journalTitle: String {
        String(localized: "JOURNAL_REMINDER_TITLE", defaultValue: "How was yesterday?",
               comment: "The journal reminder (a local notification, the morning after the day it asks about): its title. No habit names, no health values.")
    }

    static var journalBody: String {
        String(localized: "JOURNAL_REMINDER_BODY",
               defaultValue: "A few taps, and RYFT shows how your habits change the morning after.",
               comment: "The journal reminder's body: Today's journal card's sentence. No habit names.")
    }

    static var syncStaleTitle: String {
        String(localized: "SYNC_STALE_LOCAL_1_TITLE", defaultValue: "Your data hasn't synced",
               comment: "The local \"not syncing\" notification (sync.stale.1, about 20 hours after the last successful sync, 09:00–21:00): its title.")
    }

    static var syncStaleBody: String {
        String(localized: "SYNC_STALE_LOCAL_1_BODY",
               defaultValue: "Open RYFT to bring it up to date. Closing RYFT from the app switcher can stop background sync.",
               comment: "The local \"not syncing\" notification's body (sync.stale.1). No hour count: it can fire 19 to about 30 hours after the last sync.")
    }

    static var syncStaleLaterTitle: String {
        String(localized: "SYNC_STALE_LOCAL_2_TITLE", defaultValue: "Your data is still behind",
               comment: "The second local \"not syncing\" notification (sync.stale.2, about 72 hours after the last successful sync): its title.")
    }

    static var syncStaleLaterBody: String {
        String(localized: "SYNC_STALE_LOCAL_2_BODY",
               defaultValue: "It's been about three days since RYFT last synced. Open RYFT to catch up on your scores.",
               comment: "The second local \"not syncing\" notification's body (sync.stale.2).")
    }
}
