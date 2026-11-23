import Foundation
import UserNotifications

/// The one notification the first run's primer shows on its lock screen (first-run ui.md §4.3): one that **will** arrive for
/// this account, or the mock lies. The morning score with `push.enabled`; without it the journal reminder when the journal is
/// live, else "not syncing", which is live in every mode. No health value, no habit name, no count in a title or message
/// (the lock-screen rule, notifications ui.md §5); the morning title is the form a locked phone shows with iOS's default
/// "Show Previews: When Unlocked" (lead decision 1).
enum NotificationPrimerExample: Equatable, Sendable, CaseIterable {
    case morningScore, journal, syncStale

    /// `pushEnabled`: the `push.enabled` flag. `journalLive`: the journal is available (`JournalStore.isLive`).
    static func choose(pushEnabled: Bool, journalLive: Bool) -> Self {
        pushEnabled ? .morningScore : (journalLive ? .journal : .syncStale)
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
    /// iOS can still ask for alerts: never asked (`notDetermined`), or quiet delivery granted without a prompt
    /// (`provisional`), where asking for alerts still prompts. `authorized`, `denied` and `ephemeral` skip the primer.
    static func iOSCanAsk(_ status: UNAuthorizationStatus) -> Bool {
        status == .notDetermined || status == .provisional
    }

    /// The plan counts it (taken when the first run starts, before Apple Health): not demo data, iOS can ask, and this
    /// account hasn't answered the primer on this phone. Whatever `push.enabled` says: the local kinds need the permission
    /// too (notifications ui.md, lead decision 2).
    static func counts(demo: Bool, status: UNAuthorizationStatus, answered: Bool) -> Bool {
        !demo && iOSCanAsk(status) && !answered
    }

    /// It shows now: the first run, after Apple Health's step was answered, and the plan's conditions still hold.
    static func shows(firstRun: Bool, demo: Bool, status: UNAuthorizationStatus, answered: Bool,
                      healthIntroAnswered: Bool) -> Bool {
        firstRun && healthIntroAnswered && counts(demo: demo, status: status, answered: answered)
    }
}
