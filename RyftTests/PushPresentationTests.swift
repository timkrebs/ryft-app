import Foundation
import Testing
import UserNotifications
@testable import Ryft

// N3 (design.md §7, ui.md §5.5): every category's placeholder, the foreground and the tap per row, and `/journal/<day>`.

struct PushCategoryPlaceholderTests {
    @Test("Every category has a placeholder saying what kind it is, with no number in it; no actions, no title shown")
    func placeholders() throws {
        #expect(Set(PushCategories.ids) == ["MORNING_SCORE", "SESSION_SCORED", "PR", "SYNC_STALE", "ACTIVITY_SCORED",
                                            "BEDTIME", "JOURNAL_REMINDER", "WAKE"])
        for category in PushCategories.all {
            let text = category.hiddenPreviewsBodyPlaceholder
            #expect(!text.isEmpty, "\(category.identifier)")
            #expect(text.rangeOfCharacter(from: .decimalDigits) == nil, "\(category.identifier): \(text)")
            #expect(category.actions.isEmpty && !category.options.contains(.hiddenPreviewsShowTitle))
        }
        #expect(PushCategories.placeholder("BEDTIME") == String(localized: "Bedtime reminder"))
        #expect(PushCategories.placeholder("JOURNAL_REMINDER") == "Journal reminder")
        #expect(PushCategories.placeholder("SYNC_STALE") == "Your data may be behind")
        #expect(PushCategories.placeholder("WAKE") == "Wake-up time")
        #expect(PushCategories.placeholder("UNKNOWN") == nil)
    }

    @Test("No local title or body names a value: no digit in the journal's or the fallback's words")
    func localWords() {
        for text in [ReminderCopy.journalTitle, ReminderCopy.journalBody, ReminderCopy.syncStaleTitle, ReminderCopy.syncStaleBody,
                     ReminderCopy.syncStaleLaterTitle, ReminderCopy.syncStaleLaterBody] {
            #expect(!text.isEmpty && text.rangeOfCharacter(from: .decimalDigits) == nil, "\(text)")
        }
    }
}

struct PushPresentationTests {
    private let all: UNNotificationPresentationOptions = [.banner, .list, .sound]
    private let quiet: UNNotificationPresentationOptions = [.banner, .list]

    @Test("The foreground per row of §7.1")
    func foreground() {
        func options(_ category: String, local: Bool) -> UNNotificationPresentationOptions {
            PushPresentation.options(category: category, isLocal: local, accountMatches: true)
        }
        #expect(options("MORNING_SCORE", local: false) == all)
        #expect(options("SESSION_SCORED", local: false) == quiet && options("PR", local: false) == quiet)
        #expect(options("ACTIVITY_SCORED", local: false) == quiet)
        #expect(options("SYNC_STALE", local: false) == quiet, "the server's: the gap is data")
        #expect(options("SYNC_STALE", local: true) == [], "this iPhone's: the open app syncs, so it moved instead")
        #expect(options("BEDTIME", local: true) == all && options("WAKE", local: true) == all)
        #expect(options("JOURNAL_REMINDER", local: true) == quiet)
        #expect(PushPresentation.options(category: "BEDTIME", isLocal: true, accountMatches: false) == [])
    }

    @Test("Whose: a local one needs the signed-in account and no Demo data; a server alert without one is shown")
    func accounts() {
        #expect(PushPresentation.accountMatches(isLocal: true, account: "a", currentAccount: "a", isDemo: false))
        #expect(!PushPresentation.accountMatches(isLocal: true, account: "a", currentAccount: "b", isDemo: false))
        #expect(!PushPresentation.accountMatches(isLocal: true, account: "a", currentAccount: "a", isDemo: true))
        #expect(!PushPresentation.accountMatches(isLocal: true, account: nil, currentAccount: "a", isDemo: false),
                "an earlier build's, without one")
        #expect(!PushPresentation.accountMatches(isLocal: true, account: "a", currentAccount: nil, isDemo: false))
        #expect(PushPresentation.accountMatches(isLocal: false, account: nil, currentAccount: "a", isDemo: true),
                "until API.md carries ryft.account (NT1)")
        #expect(!PushPresentation.accountMatches(isLocal: false, account: "a", currentAccount: "b", isDemo: false),
                "once it does, the same check")
        #expect(!PushPresentation.accountMatches(isLocal: false, account: nil, currentAccount: nil, isDemo: false),
                "nobody signed in: an alert that came after the wipe isn't shown")
    }

    @Test("The tap: ryft.url, Today then a sync for SYNC_STALE, Today for bedtime and for another account's")
    func taps() throws {
        let journal = try #require(URL(string: "https://ryftlab.de/journal/2026-11-21"))
        let message = PushMessage.alert(category: nil, url: journal)
        #expect(PushPresentation.route(message: message, category: "JOURNAL_REMINDER", accountMatches: true) == .open(journal))
        #expect(PushPresentation.route(message: message, category: "JOURNAL_REMINDER", accountMatches: false) == .today)
        #expect(PushPresentation.route(message: .alert(category: .syncStale, url: nil), category: "SYNC_STALE",
                                       accountMatches: true) == .todayThenSync)
        #expect(PushPresentation.route(message: .alert(category: nil, url: nil), category: "BEDTIME",
                                       accountMatches: true) == .today)
        #expect(PushPresentation.route(message: nil, category: "BEDTIME", accountMatches: true) == .today)
        for link in ["https://ryftlab.de/auth/callback?code=abc", "https://ryftlab.de/invite/RYFT-7K3M-QX9P"] {
            let url = try #require(URL(string: link))
            #expect(PushPresentation.route(message: .alert(category: .morningScore, url: url), category: "MORNING_SCORE",
                                           accountMatches: true) == .today, "never from a notification: \(link)")
        }
    }

    @Test("The account read from a local request's userInfo")
    func accountInUserInfo() {
        let reminder = LocalReminder(id: "journal.2026-11-21", kind: .journal, fire: DateComponents(), title: "t", body: "b",
                                     category: "JOURNAL_REMINDER", route: nil, day: "2026-11-21", account: "acct-a")
        #expect(PushPresentation.account(in: reminder.request.content.userInfo) == "acct-a")
        #expect(PushPresentation.account(in: [:]) == nil)
    }
}

@MainActor
struct JournalRouteTests {
    @Test("/journal/<day> parses, from the web and ryft://, and writes itself back; a day that isn't one opens Today")
    func parses() throws {
        let day = try #require(DayFormat.date(from: "2026-11-21"))
        let url = try #require(URL(string: "https://ryftlab.de/journal/2026-11-21"))
        #expect(AppRoute(url: url) == .journal(day))
        #expect(AppRoute(url: try #require(URL(string: "ryft://journal/2026-11-21"))) == .journal(day))
        #expect(AppRoute.journal(day).url == url)
        #expect(AppRoute(url: try #require(URL(string: "https://ryftlab.de/journal/yesterday"))) == .today)
        #expect(AppRoute(url: try #require(URL(string: JournalReminderPlan.route("2026-11-21")))) == .journal(day))
    }

    @Test("The router selects Today and asks it for the journal on that day, once")
    func routes() async throws {
        let state = AppState(env: .test(auth: .preview(signedIn: true)))
        let router = DeepLinkRouter(state: state, sleep: SleepViewModel(state: state),
                                    strain: StrainViewModel(state: state, store: TrainStore(inMemory: true)),
                                    insights: InsightsViewModel(state: state))
        state.selectedTab = .profile
        await router.open(try #require(URL(string: "https://ryftlab.de/journal/2026-11-21")))
        #expect(state.selectedTab == .today && router.requestedJournalDay == "2026-11-21")
        router.journalOpened()
        #expect(router.requestedJournalDay == nil)

        await router.open(try #require(URL(string: "https://ryftlab.de/journal/2026-11-20")))
        state.reset()
        #expect(router.requestedJournalDay == nil, "the account's change forgets it")
    }

    @Test("The sheet offers yesterday and the 13 days before it")
    func offers() {
        #expect(JournalSheetModel.offers("2026-11-21", yesterday: "2026-11-21"))
        #expect(JournalSheetModel.offers("2026-11-08", yesterday: "2026-11-21"))
        #expect(!JournalSheetModel.offers("2026-11-07", yesterday: "2026-11-21"))
        #expect(!JournalSheetModel.offers("2026-11-22", yesterday: "2026-11-21"))
    }
}

/// Review S-3: below iOS 26 the wake notification is a local request like the others, so it presents while RYFT is open.
@MainActor
struct WakeNotificationTests {
    @Test("Monday's wake notification: its id, weekday and time, its category and thread, and whose it is")
    func shape() throws {
        let request = try #require(SystemWakeAlarms.request(index: 0, at: "06:45", account: "acct-a"))
        #expect(request.identifier == "wake.0" && request.content.interruptionLevel == .timeSensitive)
        #expect(request.content.categoryIdentifier == "WAKE" && request.content.threadIdentifier == "WAKE")
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats && trigger.dateComponents == DateComponents(hour: 6, minute: 45, weekday: 2))
        #expect(PushPresentation.account(in: request.content.userInfo) == "acct-a")
        #expect(SystemWakeAlarms.request(index: 6, at: "07:30", account: "acct-a")?.identifier == "wake.6")
        #expect(SystemWakeAlarms.request(index: 1, at: "7", account: "acct-a") == nil)
    }

    @Test("Open on its account: shown with its sound; another account's, or with Demo data on, not shown, and its tap opens Today")
    func presents() throws {
        let request = try #require(SystemWakeAlarms.request(index: 2, at: "06:00", account: "acct-a"))
        let account = PushPresentation.account(in: request.content.userInfo)
        let mine = PushPresentation.accountMatches(isLocal: true, account: account, currentAccount: "acct-a", isDemo: false)
        #expect(mine && PushPresentation.options(category: "WAKE", isLocal: true, accountMatches: mine) == [.banner, .list, .sound])
        for (current, demo) in [("acct-b", false), ("acct-a", true)] {
            let matches = PushPresentation.accountMatches(isLocal: true, account: account, currentAccount: current, isDemo: demo)
            #expect(!matches && PushPresentation.options(category: "WAKE", isLocal: true, accountMatches: matches) == [])
        }
        let message = PushMessage(userInfo: request.content.userInfo)
        #expect(PushPresentation.route(message: message, category: "WAKE", accountMatches: mine) == .today)
    }
}
