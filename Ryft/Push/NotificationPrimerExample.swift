import Foundation
import UserNotifications

/// The one notification the first run's primer shows on its lock screen (first-run ui.md §4.3): one that **will** arrive for
/// this account, or the mock lies. The morning score with `push.enabled`; without it the journal reminder when
/// `notifications.reminders` is on and the journal is live, else "not syncing" while `notifications.reminders` is on; with
/// neither flag nothing can arrive, and there is no primer (`choose` is nil). No health value, no habit name, no count in a title or message
/// (the lock-screen rule, notifications ui.md §5); the morning title is the form a locked phone shows with iOS's default
/// "Show Previews: When Unlocked" (lead decision 1).
enum NotificationPrimerExample: Equatable, Sendable, CaseIterable {
    case morningScore, journal, syncStale

    /// A notification that can arrive, or nil when none can. `pushEnabled`: `push.enabled` (the morning score is a push).
    /// `remindersOn`: `notifications.reminders`, which gates the journal reminder and the "not syncing" fallback
    /// (`ReminderScheduler`). `journalLive`: the journal is available (`JournalStore.isLive`).
    static func choose(pushEnabled: Bool, remindersOn: Bool, journalLive: Bool) -> Self? {
        if pushEnabled { return .morningScore }
        guard remindersOn else { return nil }
        return journalLive ? .journal : .syncStale
    }

    /// `choose` from the flags, read as the registrar and `ReminderScheduler` read them: `push.enabled` as `isOn` (what
    /// `PushRegistrar` registers by), `notifications.reminders` as `known` (the scheduler adds a new kind only once it is
    /// known on; not known yet is not on here either). No second source of truth.
    @MainActor
    static func current(flags: FeatureFlagProvider, journalLive: Bool) -> Self? {
        choose(pushEnabled: flags.isOn(.pushEnabled), remindersOn: flags.known(.notificationsReminders) == true,
               journalLive: journalLive)
    }

    /// The notification's title.
    var title: String {
        switch self {
        case .morningScore: return String(localized: "Your morning score is ready")
        case .journal: return String(localized: "How was yesterday?")
        case .syncStale: return String(localized: "Your data hasn't synced")
        }
    }

    /// The notification's message.
    var message: String {
        switch self {
        case .morningScore: return String(localized: "Open RYFT to see how you recovered overnight.")
        case .journal: return String(localized: "A few taps, and RYFT shows how your habits change the morning after.")
        case .syncStale: return String(localized: "Open RYFT to bring it up to date.")
        }
    }

    /// The screen's lead: what RYFT would send, for this example.
    var lead: String {
        switch self {
        case .morningScore:
            return String(localized: "RYFT can tell you when your morning score is ready, and when your data stops syncing. You choose which in Profile.",
                          comment: "First run, notification primer: the lead while morning-score pushes are on.")
        case .journal:
            return String(localized: "RYFT can remind you to log your day, and tell you when your data stops syncing. You choose which in Profile.",
                          comment: "First run, notification primer: the lead while pushes are off and the journal is live.")
        case .syncStale:
            return String(localized: "RYFT can tell you when your data stops syncing, so a quiet watch doesn't go unnoticed.",
                          comment: "First run, notification primer: the lead while pushes are off and the journal isn't live.")
        }
    }

    /// What VoiceOver reads for the whole mock: the clock and the stacked bars are decoration. (No catalog comment here or
    /// on the notification's words and "now": `LockScreenMock`'s previews look up the same keys.)
    var accessibilityLabel: String {
        String(localized: "Example notification from RYFT. \(title). \(message)")
    }

    /// The lock screen's time: 7:30 for the morning score, 9:00 for the others; on `now`'s day.
    func clock(on now: Date, calendar: Calendar = .current) -> Date {
        let hour = self == .morningScore ? 7 : 9
        let minute = self == .morningScore ? 30 : 0
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    /// The screen's title, for every example.
    static var screenTitle: String {
        String(localized: "Hear from RYFT when it matters", comment: "First run, notification primer: the title.")
    }

    /// Under the mock, for every example.
    static var caption: String {
        String(localized: "An example. What your lock screen shows follows your iOS setting for previews. Change what RYFT sends in Profile → Notifications.",
               comment: "First run, notification primer: the caption under the lock-screen mock.")
    }

    /// The notification's time label.
    static var timeLabel: String {
        String(localized: "now")
    }
}

/// When the primer is a step of the first run (first-run ui.md §4.3). Pure: the caller reads the status and the answer.
enum NotificationPrimerFacts {
    /// iOS hasn't been asked (`notDetermined`). `provisional` (quiet delivery granted without a prompt), `authorized`,
    /// `denied` and `ephemeral` skip the primer (§4.3).
    static func iOSCanAsk(_ status: UNAuthorizationStatus) -> Bool {
        status == .notDetermined
    }

    /// The plan counts it (taken when the first run starts, before Apple Health): not demo data, iOS can ask, this account
    /// hasn't answered the primer on this phone, and a notification can arrive (`example`, from
    /// `NotificationPrimerExample.current`: nil when neither `push.enabled` nor `notifications.reminders` is on, and then the
    /// permission would be asked for nothing).
    static func counts(demo: Bool, status: UNAuthorizationStatus, answered: Bool, example: NotificationPrimerExample?) -> Bool {
        !demo && iOSCanAsk(status) && !answered && example != nil
    }

    /// It shows now: the first run, after Apple Health's step was answered, and the plan's conditions still hold.
    static func shows(firstRun: Bool, demo: Bool, status: UNAuthorizationStatus, answered: Bool,
                      healthIntroAnswered: Bool, example: NotificationPrimerExample?) -> Bool {
        firstRun && healthIntroAnswered && counts(demo: demo, status: status, answered: answered, example: example)
    }
}
