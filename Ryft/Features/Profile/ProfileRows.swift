// Profile's groups and subpages: which rows they hold, in order, and when they show.
import SwiftUI

/// The groups on Profile's main page, top to bottom.
enum ProfileGroup: String, CaseIterable, Identifiable, Sendable {
    case you, general, data, resources, legal

    var id: String { rawValue }

    var title: Text {
        switch self {
        case .you: return Text("You", comment: "Profile group for body settings and baselines.")
        case .general: return Text("General", comment: "Profile group for account and app preferences.")
        case .data: return Text("Data", comment: "Profile group for sync and data privacy.")
        case .resources: return Text("Resources", comment: "Profile group for version, support and App Store rating.")
        case .legal: return Text("Legal", comment: "Profile group for policies, terms and licences.")
        }
    }
}

/// One row of Profile, with its accessibility identifier.
enum ProfileRow: String, CaseIterable, Hashable, Identifiable, Sendable {
    // About you
    case birthYear, maxHR, sleepBase, rescore
    // Devices and sync
    case devices, appleHealth, allowHealth, openHealth, lastSync, deviceID, syncNow, syncDetails, importTraining, demoMode
    // Training
    case jumpToNext, sessionLayout, saveWorkouts
    // Display and existing destinations
    case notifications, journal, heroNumerals, bedtime
    // Privacy
    case consent, reviewConsent, checkConsent, withdrawConsent, nutritionPrivacy, analytics
    // Account
    case email, timezone, signInMethods, changePassword, deleteAccount, signedIn
    // Resources and legal
    case version, reportProblem, privacyPolicy, terms, appleHealthPrivacy, garminHealth, licences

    // Since P1: the rows that open a page, Rate RYFT, Account's Log out and Your data's Export. `devices` is the top
    // "Devices and sync" row and `reportProblem` the "Help and feedback" row: the pre-P1 rows, their identifiers kept.
    case bodyAndBaselines, account, display, training, privacyAndData, whatsNew, rateApp, logOutRow
    case export

    var id: String { rawValue }

    /// `profile.<case>` (UI tests find rows by it).
    var identifier: String { "profile.\(rawValue)" }
}

/// What decides the page's rows: the account, the flags and the screens' switches (`ProfileViewModel` and the shared
/// stores give them; tests set them).
struct ProfileRowFacts: Equatable, Sendable {
    var isSignedIn = true
    /// The slot stays hidden until StoreKit ships.
    var showsPlus: Bool { false }
    /// `devices.setup`: the tracker sections and the catalog’s Apple Health steps.
    var devicesEnabled = false
    /// RYFT may still ask for Health access: "Allow access" before "Open Health".
    var canAskForHealth = false
    var showsTraining = true
    /// `train.import`: the import and Clear remembered matches rows (`ImportProfileRows`). Independent of `train.enabled`, as
    /// before P1, so imported data can still be managed with Train switched off.
    var showsImport = false
    var showsSessionLayout = false
    var showsNotifications = true
    var journalLive = false
    var bedtimeEnabled = true
    var consentIsCurrent = true
    /// Given on this iPhone, RYFT's confirmation still out (`ProfileViewModel.consentAwaitsConfirmation`): Check with
    /// RYFT and Withdraw, never Review and agree.
    var consentAwaitsConfirmation = false
    /// "Share usage analytics" (`Analytics.showsToggle`): where the prompt could show, and while opted in.
    var showsAnalytics = false
    /// Demo data is on: the account's consent is neither known nor reachable (every consent call goes to the demo's
    /// platform), so Privacy says so instead of acting.
    var isDemo = false
    var canChangePassword = false
    var hasTimezone = true
    /// The account has an email to show on its own page.
    var showsEmail = false
    var canExport = true
    /// Nutrition (diary or full) is available for the account: Privacy gets its Nutrition privacy row.
    var nutritionAvailable = false
}

/// The pages whose rows come from the Profile inventory.
enum ProfilePage: CaseIterable, Hashable, Sendable {
    case body, account, display, training, devicesAndSync, privacyAndData, whatsNew

    struct Section: Identifiable, Equatable, Sendable {
        enum ID: Hashable, Sendable {
            case body, account, display, training, healthAccess, sync, healthWrites, advanced, syncDetails
            case consent, analytics, nutritionPrivacy, yourData, version
        }

        let id: ID
        let rows: [ProfileRow]

        init(_ id: ID, _ rows: [ProfileRow]) {
            self.id = id
            self.rows = rows
        }

        var title: Text? {
            switch id {
            case .healthAccess:
                return Text("Apple Health", comment: "Devices and sync card for Apple Health read access.")
            case .sync:
                return Text("Sync", comment: "Devices and sync card for the last sync, manual sync and device ID.")
            case .healthWrites:
                return Text("Apple Health", comment: "Devices and sync card for writing workouts to Apple Health.")
            case .advanced:
                return Text("Advanced", comment: "Devices and sync card for rescoring and Demo data.")
            case .consent:
                return Text("Health-data consent", comment: "Privacy and data card for managing consent to health-data processing.")
            case .analytics:
                return Text("Analytics", comment: "Privacy and data card for the usage analytics preference.")
            case .yourData:
                return Text("Your data", comment: "Privacy and data card for data export and account deletion.")
            default:
                return nil
            }
        }
    }

    var title: Text {
        switch self {
        case .body: return Text("Body and baselines", comment: "Profile row and page title for birth year, heart rate and sleep need.")
        case .account: return Text("Account", comment: "Profile row and page title for account details and sign-in.")
        case .display: return Text("Units and display", comment: "Profile row and page title for display preferences.")
        case .training: return Text("Training", comment: "Profile row and page title for training preferences and import.")
        case .devicesAndSync: return Text("Devices and sync", comment: "Profile row that opens the page for trackers, Apple Health and sync.")
        case .privacyAndData: return Text("Privacy and data", comment: "Profile row and page title for consent, analytics and personal data.")
        case .whatsNew: return Text("What's new", comment: "Profile row and page title for the installed app version.")
        }
    }

    /// The cards on a subpage. An empty card stays out of the page.
    static func sections(_ page: ProfilePage, _ f: ProfileRowFacts) -> [Section] {
        switch page {
        case .body:
            // C1: Add sex, weight and goal here when Profile has those settings.
            return [.init(.body, [.birthYear, .maxHR, .sleepBase])]
        case .account:
            let account: [ProfileRow] = (f.showsEmail ? [.email] : []) + (f.hasTimezone ? [.timezone] : []) + [.signInMethods]
                + (f.canChangePassword ? [.changePassword] : []) + [.logOutRow, .deleteAccount]
            return [.init(.account, f.isSignedIn ? account : [.signedIn])]
        case .display:
            return [.init(.display, [.heroNumerals])]
        case .training:
            let train: [ProfileRow] = f.showsTraining
                ? [.jumpToNext] + (f.showsSessionLayout ? [.sessionLayout] : []) + [.saveWorkouts] : []
            return [.init(.training, train + (f.showsImport ? [.importTraining] : []))].filter { !$0.rows.isEmpty }
        case .devicesAndSync:
            // With tracker setup on, DevicesAndSyncView draws RYFT's read access and Sync details itself (its own
            // `devices.*` controls), so these two cards are only Profile's without it.
            let own = !f.devicesEnabled
            return [
                .init(.healthAccess, own ? [.appleHealth] + (f.canAskForHealth ? [.allowHealth] : []) + [.openHealth] : []),
                .init(.sync, [.lastSync, .syncNow, .deviceID]),
                .init(.healthWrites, f.showsTraining ? [.saveWorkouts] : []),
                .init(.advanced, [.rescore, .demoMode]),
                .init(.syncDetails, own ? [.syncDetails] : []),
            ].filter { !$0.rows.isEmpty }
        case .privacyAndData:
            return [
                .init(.consent, consentRows(f)),
                .init(.analytics, f.isSignedIn && f.showsAnalytics ? [.analytics] : []),
                .init(.nutritionPrivacy, f.isSignedIn && !f.isDemo && f.nutritionAvailable ? [.nutritionPrivacy] : []),
                .init(.yourData, (f.canExport ? [.export] : []) + (f.isSignedIn ? [.deleteAccount] : [])),
            ].filter { !$0.rows.isEmpty }
        case .whatsNew:
            return [.init(.version, [.version])]
        }
    }

    private static func consentRows(_ f: ProfileRowFacts) -> [ProfileRow] {
        guard f.isSignedIn else { return [] }
        // In demo mode, consent actions would reach the demo's platform.
        if f.isDemo { return [.consent] }
        if f.consentAwaitsConfirmation { return [.consent, .checkConsent, .withdrawConsent] }
        return [.consent, f.consentIsCurrent ? .withdrawConsent : .reviewConsent]
    }
}

/// The Log out pill at the end of Profile.
enum ProfileButton: String, Hashable, Identifiable, Sendable {
    case logOut

    var id: String { rawValue }
    var identifier: String { "profile.\(rawValue)" }
}

enum ProfileRows {
    /// The Log out dialog's buttons and the Demo data dialog's.
    static let logOutSendFirst = "profile.logOut.sendFirst", logOutAnyway = "profile.logOut.anyway"
    static let demoDiscard = "profile.demo.discard", demoKeep = "profile.demo.keep"
    /// The Advanced card's push rows (Debug builds).
    static let devCatalog = "dev.catalog", devFlags = "dev.flags"
    /// The Developer group's platform overrides and API key mode, held while a consent withdrawal is on its way.
    static let devAPIURL = "profile.dev.apiURL", devIngestURL = "profile.dev.ingestURL", devAPIKeyMode = "profile.dev.apiKeyMode"

    /// A top group's rows in order.
    static func rows(_ group: ProfileGroup, _ f: ProfileRowFacts) -> [ProfileRow] {
        switch group {
        case .you:
            return [.bodyAndBaselines]
        case .general:
            return [.account] + (f.showsNotifications ? [.notifications] : []) + [.display]
                + (f.showsTraining || f.showsImport ? [.training] : []) + (f.journalLive ? [.journal] : []) + (f.bedtimeEnabled ? [.bedtime] : [])
        case .data:
            return [.devices, .privacyAndData]
        case .resources:
            // How RYFT scores goes here once there are links to explain the scores.
            return [.whatsNew, .reportProblem, .rateApp]
        case .legal:
            return [.privacyPolicy, .terms, .appleHealthPrivacy] + (f.devicesEnabled ? [] : [.garminHealth]) + [.licences]
        }
    }

    /// A group that shows, with its rows.
    struct Shown: Identifiable, Equatable, Sendable {
        let group: ProfileGroup
        let rows: [ProfileRow]
        var id: ProfileGroup { group }
    }

    static func groups(_ f: ProfileRowFacts) -> [Shown] {
        ProfileGroup.allCases.map { Shown(group: $0, rows: rows($0, f)) }
    }

    enum Home: Equatable, Sendable {
        case top(ProfileGroup)
        case page(ProfilePage, ProfilePage.Section.ID)
        case multiple([Home])
        case hidden
    }

    /// The visible home for these facts, including both homes of rows shared between pages.
    static func home(of row: ProfileRow, _ f: ProfileRowFacts) -> Home {
        var homes = groups(f).filter { $0.rows.contains(row) }.map { Home.top($0.group) }
        for page in ProfilePage.allCases {
            homes += ProfilePage.sections(page, f).filter { $0.rows.contains(row) }.map { .page(page, $0.id) }
        }
        if homes.count > 1 { return .multiple(homes) }
        return homes.first ?? .hidden
    }

    static func buttons(_ f: ProfileRowFacts) -> [ProfileButton] {
        f.isSignedIn ? [.logOut] : []
    }
}

/// Where a push row goes (`GroupedRow.push(route:)`; the stack builds its destination).
enum ProfileRoute: Hashable, Sendable {
    case body, account, display, training, privacyAndData, whatsNew
    case devices, syncDetails, notifications, journal, bedtime, signInMethods, reportProblem, licences, nutritionPrivacy
    #if DEBUG
    case catalog, flags
    #endif
}

// MARK: - menu rows (§P5-6.2: birth year, session layout, hero numbers)

/// Units and display → Hero numbers: Dots or Thin, as a menu row (the choice applies at once, design.md §P4-6).
struct HeroNumbersMenuRow: View {
    @Binding var selection: HeroNumerals

    var body: some View {
        GroupedRow.menu(Text("Hero numbers", comment: "Profile → Display: how the large numbers on Today, Sleep and Strain are drawn."),
                        value: Text(verbatim: selection.title), identifier: ProfileRow.heroNumerals.identifier) {
            Picker(selection: $selection) {
                ForEach(HeroNumerals.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text("Hero numbers", comment: "Profile → Display: how the large numbers on Today, Sleep and Strain are drawn.")
            }
        }
    }
}

/// Training → Session layout: Focused or List, as a menu row (L5: only with `train.focused_session`).
struct SessionLayoutMenuRow: View {
    @Binding var selection: SessionLayout

    var body: some View {
        GroupedRow.menu(Text("Session layout", comment: "Profile → Training: how a workout shows its exercises, one per page or all in one list."),
                        value: Text(verbatim: selection.title), identifier: ProfileRow.sessionLayout.identifier) {
            Picker(selection: $selection) {
                ForEach(SessionLayout.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text("Session layout", comment: "Profile → Training: how a workout shows its exercises, one per page or all in one list.")
            }
        }
    }
}

/// Body and baselines → Birth year: the editor's years, newest first, and "Not set" while there is none. Disabled while the editor
/// saves or rescores.
struct BirthYearMenuRow: View {
    let editor: BodySettingsEditor

    var body: some View {
        let selection = Binding<Int?>(get: { editor.birthYear }, set: { year in
            if let year { Task { await editor.setBirthYear(year) } }
        })
        GroupedRow.menu(Text("Birth year"), value: value, identifier: ProfileRow.birthYear.identifier) {
            Picker(selection: selection) {
                if editor.birthYear == nil { Text("Not set").tag(Int?.none) }
                ForEach(editor.birthYears, id: \.self) { Text(verbatim: "\($0)").tag(Int?.some($0)) }
            } label: {
                Text("Birth year")
            }
        }
        .disabled(editor.isBusy)
    }

    private var value: Text {
        editor.birthYear.map { Text(verbatim: "\($0)") } ?? Text("Not set")
    }
}
