// Profile's groups and rows in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-6.2): which rows each group holds, in
// order, and when they show. Pure, so test 33 asserts the inventory (every row of the page before Nocturne has a place)
// without a view; `ProfileView` draws exactly these, each with its identifier.
import SwiftUI

/// The page's groups, top to bottom (the Developer group of Debug builds comes after the buttons row, outside this list).
enum ProfileGroup: String, CaseIterable, Identifiable, Sendable {
    case aboutYou, devicesAndSync, training, settings, privacy, account, about

    var id: String { rawValue }

    var title: Text {
        switch self {
        case .aboutYou: return Text("About you")
        case .devicesAndSync: return Text("Devices and sync", comment: "Profile: the group with what you wear, Apple Health, the sync and Demo data.")
        case .training: return Text("Training")
        case .settings: return Text("Settings", comment: "Profile: the group with notifications, the journal, hero numbers and bedtime.")
        case .privacy: return Text("Privacy")
        case .account: return Text("Account")
        case .about: return Text("About")
        }
    }
}

/// One row of the page. The case is the identifier's last part: `profile.<case>` (UI tests find rows by it).
enum ProfileRow: String, CaseIterable, Hashable, Identifiable, Sendable {
    // About you
    case birthYear, maxHR, sleepBase, rescore
    // Devices and sync
    case devices, appleHealth, allowHealth, openHealth, lastSync, deviceID, syncNow, syncDetails, importTraining, demoMode
    // Training
    case jumpToNext, sessionLayout, saveWorkouts
    // Settings
    case notifications, journal, heroNumerals, bedtime
    // Privacy
    case consent, reviewConsent, withdrawConsent
    // Account
    case email, timezone, signInMethods, changePassword, deleteAccount, signedIn
    // About
    case version, reportProblem, privacyPolicy, terms, appleHealthPrivacy, garminHealth, licences

    var id: String { rawValue }

    /// `profile.<case>`.
    var identifier: String { "profile.\(rawValue)" }

    /// The training import's rows carry their own identifiers (`profile.importTraining`, `profile.clearMatches`,
    /// `ImportProfileRows`): the page adds none around them.
    var setsOwnIdentifier: Bool { self == .importTraining }
}

/// What decides the page's rows: the account, the flags and the screens' switches (`ProfileViewModel` and the shared
/// stores give them; tests set them).
struct ProfileRowFacts: Equatable, Sendable {
    var isSignedIn = true
    /// `devices.setup`: the Devices & sync page, and its Health steps instead of the Garmin sentence.
    var devicesEnabled = false
    /// RYFT may still ask for Health access: "Allow access" before "Open Health".
    var canAskForHealth = false
    var showsTraining = true
    var showsSessionLayout = false
    var showsNotifications = true
    var journalLive = false
    var bedtimeEnabled = true
    var consentIsCurrent = true
    var canChangePassword = false
    var hasTimezone = true
    /// The account's email when the name is the title (it was the account card's second line).
    var showsEmail = false
    var canExport = true
}

/// The page's buttons row (§P5-6.1 row 4), each only when it applies.
enum ProfileButton: String, Hashable, Identifiable, Sendable {
    case export, logOut

    var id: String { rawValue }
    var identifier: String { "profile.\(rawValue)" }
}

enum ProfileRows {
    /// The Log out dialog's buttons (unchanged) and the Demo data dialog's.
    static let logOutSendFirst = "profile.logOut.sendFirst", logOutAnyway = "profile.logOut.anyway"
    static let demoDiscard = "profile.demo.discard", demoKeep = "profile.demo.keep"
    /// The Developer group's push rows (Debug builds).
    static let devCatalog = "dev.catalog", devFlags = "dev.flags"

    /// A group's rows in order; empty when the group doesn't show.
    static func rows(_ group: ProfileGroup, _ f: ProfileRowFacts) -> [ProfileRow] {
        switch group {
        case .aboutYou:
            return [.birthYear, .maxHR, .sleepBase, .rescore]
        case .devicesAndSync:
            return (f.devicesEnabled ? [.devices] : [])
                + [.appleHealth] + (f.canAskForHealth ? [.allowHealth] : [])
                + [.openHealth, .lastSync, .deviceID, .syncNow, .syncDetails, .importTraining, .demoMode]
        case .training:
            guard f.showsTraining else { return [] }
            return [.jumpToNext] + (f.showsSessionLayout ? [.sessionLayout] : []) + [.saveWorkouts]
        case .settings:
            return (f.showsNotifications ? [.notifications] : []) + (f.journalLive ? [.journal] : []) + [.heroNumerals]
                + (f.bedtimeEnabled ? [.bedtime] : [])
        case .privacy:
            return [.consent, f.consentIsCurrent ? .withdrawConsent : .reviewConsent]
        case .account:
            guard f.isSignedIn else { return [.signedIn] }
            return (f.showsEmail ? [.email] : []) + (f.hasTimezone ? [.timezone] : []) + [.signInMethods]
                + (f.canChangePassword ? [.changePassword] : []) + [.deleteAccount]
        case .about:
            return [.version, .reportProblem, .privacyPolicy, .terms, .appleHealthPrivacy]
                + (f.devicesEnabled ? [] : [.garminHealth]) + [.licences]
        }
    }

    /// A group that shows, with its rows.
    struct Shown: Identifiable, Equatable, Sendable {
        let group: ProfileGroup
        let rows: [ProfileRow]
        var id: ProfileGroup { group }
    }

    /// The groups that show, in order, with their rows.
    static func groups(_ f: ProfileRowFacts) -> [Shown] {
        ProfileGroup.allCases.map { Shown(group: $0, rows: rows($0, f)) }.filter { !$0.rows.isEmpty }
    }

    /// The buttons row: Export data when there is something to export, Log out when signed in.
    static func buttons(_ f: ProfileRowFacts) -> [ProfileButton] {
        (f.canExport ? [.export] : []) + (f.isSignedIn ? [.logOut] : [])
    }
}

/// Where a push row goes (`GroupedRow.push(route:)`; the page's `navigationDestination(for:)` builds it).
enum ProfileRoute: Hashable, Sendable {
    case devices, syncDetails, notifications, journal, bedtime, signInMethods, reportProblem, licences
    #if DEBUG
    case catalog, flags
    #endif
}

// MARK: - menu rows (§P5-6.2: birth year, session layout, hero numbers)

/// Settings → Hero numbers: Dots or Thin, as a menu row (the choice applies at once, design.md §P4-6).
struct HeroNumbersMenuRow: View {
    @Binding var selection: HeroNumerals

    var body: some View {
        GroupedRow.menu(Text("Hero numbers", comment: "Profile → Display: how the large numbers on Today, Sleep and Strain are drawn."),
                        value: Text(verbatim: selection.title)) {
            Picker(selection: $selection) {
                ForEach(HeroNumerals.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text("Hero numbers", comment: "Profile → Display: how the large numbers on Today, Sleep and Strain are drawn.")
            }
        }
        .accessibilityIdentifier(ProfileRow.heroNumerals.identifier)
    }
}

/// Training → Session layout: Focused or List, as a menu row (L5: only with `train.focused_session`).
struct SessionLayoutMenuRow: View {
    @Binding var selection: SessionLayout

    var body: some View {
        GroupedRow.menu(Text("Session layout", comment: "Profile → Training: how a workout shows its exercises, one per page or all in one list."),
                        value: Text(verbatim: selection.title)) {
            Picker(selection: $selection) {
                ForEach(SessionLayout.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text("Session layout", comment: "Profile → Training: how a workout shows its exercises, one per page or all in one list.")
            }
        }
        .accessibilityIdentifier(ProfileRow.sessionLayout.identifier)
    }
}

/// About you → Birth year: the editor's years, newest first, and "Not set" while there is none. Disabled while the editor
/// saves or rescores.
struct BirthYearMenuRow: View {
    let editor: BodySettingsEditor

    var body: some View {
        let selection = Binding<Int?>(get: { editor.birthYear }, set: { year in
            if let year { Task { await editor.setBirthYear(year) } }
        })
        GroupedRow.menu(Text("Birth year"), value: value) {
            Picker(selection: selection) {
                if editor.birthYear == nil { Text("Not set").tag(Int?.none) }
                ForEach(editor.birthYears, id: \.self) { Text(verbatim: "\($0)").tag(Int?.some($0)) }
            } label: {
                Text("Birth year")
            }
        }
        .disabled(editor.isBusy)
        .accessibilityIdentifier(ProfileRow.birthYear.identifier)
    }

    private var value: Text {
        editor.birthYear.map { Text(verbatim: "\($0)") } ?? Text("Not set")
    }
}
