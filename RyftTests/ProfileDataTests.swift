import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Profile's decisions (docs/work/2026-11-16-nocturne/design.md §P5-12 tests 31–33; §P5-6): the identity's title, initials
/// and arc, the status word, dot and tap for each sync line, and the rows of the top groups and each subpage.
@MainActor
@Suite("T5.4: Profile data")
struct ProfileDataTests {
    // MARK: 31. identity

    @Test("Spec 31: initials", arguments: [
        ("Alex Doe", "AD"), ("alex", "A"), ("Alex", "A"), ("Åsa Öhman", "ÅÖ"), ("Alex   Maria Doe", "AM"), ("  ", nil),
        ("alex@example.com", "A"), ("42 Alex", "A"),
    ] as [(String, String?)])
    func initials(_ title: String, _ expected: String?) {
        #expect(ProfileIdentity.initials(for: title) == expected)
    }

    @Test("Spec 31: no title, no letters: the glyph")
    func noInitials() {
        #expect(ProfileIdentity.initials(for: nil) == nil)
        #expect(ProfileIdentity.initials(email: "@example.com") == nil)
        #expect(ProfileIdentity.resolve(name: nil, email: nil, fallback: "Apple ID", strain: nil).initials == nil)
    }

    @Test("Spec 31: the title falls back name → email → the account's description")
    func titleFallback() {
        let named = ProfileIdentity.resolve(name: "Alex Doe", email: "alex@example.com", fallback: "Apple ID", strain: 12.4)
        #expect(named.title == "Alex Doe" && named.source == .name && named.initials == "AD")
        let email = ProfileIdentity.resolve(name: "  ", email: "alex@example.com", fallback: "Apple ID", strain: nil)
        #expect(email.title == "alex@example.com" && email.source == .email && email.initials == "A")
        let neither = ProfileIdentity.resolve(name: "", email: "", fallback: "Apple ID", strain: nil)
        #expect(neither.title == "Apple ID" && neither.source == .description && neither.initials == nil)
    }

    @Test("Spec 31: the arc for 12.4 of 21 ends at 212.6°; no strain, no arc and no dot; the share stays in 0…1")
    func arc() throws {
        let end = try #require(ProfileLayout.arcEndDegrees(12.4))
        #expect(abs(end - 212.571) < 0.001, "\(end)")
        #expect(ProfileLayout.arcEndDegrees(nil) == nil)
        #expect(ProfileLayout.strainShare(nil) == nil && ProfileLayout.strainShare(.nan) == nil)
        #expect(ProfileLayout.strainShare(0) == 0)
        #expect(ProfileLayout.strainShare(21) == 1 && ProfileLayout.strainShare(25) == 1 && ProfileLayout.strainShare(-1) == 0)
    }

    @Test("Spec 31 / §P5-6.4: the row reads as one sentence")
    func spoken() {
        let now = Date(timeIntervalSince1970: 1_792_300_000)
        let identity = ProfileIdentity.resolve(name: "Alex Doe", email: nil, fallback: "", strain: 12.4)
        let status = ProfileStatus.decide(.upToDate(now, demo: false), isDemo: false, lastUpdated: now, lastSync: now)
        // The number as the app writes it in the phone's region ("12.4", "12,4").
        #expect(identity.spokenLabel(status, now: now) == "Alex Doe. Apple Health, up to date. Strain today \(Fmt.strain(12.4)) of 21.")
        let none = ProfileIdentity.resolve(name: "Alex Doe", email: nil, fallback: "", strain: nil)
        #expect(none.spokenLabel(status, now: now).hasSuffix("No strain yet today."))
    }

    @Test("Spec 31: the model's identity: today's strain, the account's title, Demo data signed out")
    func modelIdentity() async throws {
        let graph = try await ProfileShotGraph.make("signed-in")
        defer { graph.tearDown() }
        let identity = graph.screens.profile.identity
        #expect(identity.title == "Alex Doe" && identity.initials == "AD")
        #expect(identity.strain == MockData.todayDetail.score.strain)
        let signedOut = try await ProfileShotGraph.make("signed-out")
        defer { signedOut.tearDown() }
        // The demo's account has a name; the description is the fallback only without one.
        #expect(signedOut.screens.profile.identity.title == "Alex Doe")
        #expect(signedOut.screens.profile.status(line: .upToDate(nil, demo: true)).source == "Demo data")
    }

    @Test("Security: Demo data on while signed in shows the account's session, never the demo's person")
    func demoWhileSignedIn() async throws {
        // Signed in with Apple (the session's email is a private relay address), Demo data on: the store holds MockData.user.
        let graph = try await ProfileShotGraph.make("demo")
        defer { graph.tearDown() }
        let model = graph.screens.profile
        #expect(graph.state.user?.name == "Alex Doe" && graph.state.user?.provider == "email", "the demo's person is in the store")
        #expect(model.isSignedIn && model.demoMode)
        #expect(model.provider == "apple" && !model.canChangePassword)
        #expect(model.identity.title == "alex@privaterelay.appleid.com" && model.identity.initials == "A")
        #expect(model.accountEmail == "alex@privaterelay.appleid.com", "the session's email")
        #expect(model.showsEmailRow, "Account also shows the email used as the Profile title")
        #expect(model.timezone == nil, "no zone of the demo's person")
        #expect(model.status(line: .upToDate(nil, demo: true)).source == "Demo data")
        let facts = ProfileRowFacts(model, journalLive: graph.screens.journal.isLive, bedtimeEnabled: graph.screens.bedtime.isEnabled)
        let rows = ProfilePage.sections(.account, facts).flatMap(\.rows)
        #expect(!rows.contains(.changePassword) && rows.contains(.email) && !rows.contains(.timezone))
        try await HostedWindow.run(width: 390, height: 4400, graph.page(.account)) { w in
            try await w.settle()
            let labels = w.nodes().map(\.label)
            #expect(!labels.contains { $0.contains("Alex Doe") }, "\(labels.filter { $0.contains("Alex") })")
            #expect(!labels.contains("Change password"))
        }
    }

    @Test("Security: Demo data on while signed in never shows the demo's consent; signed out there is no consent card")
    func demoConsent() async throws {
        let graph = try await ProfileShotGraph.make("demo")
        defer { graph.tearDown() }
        let state = graph.state
        // The account's own cached user has another consent (another date and policy) in the account's store; the demo's
        // store has the demo's person, agreed to the demo's policy on its date.
        let accountConsent = Consent(policyVersion: "2026-01-01", grantedAt: Date(timeIntervalSince1970: 1_772_500_000))
        var account = MockData.user
        account.consent = accountConsent
        state.repository.writingToAccountStore { state.user = account }
        let demoConsent = try #require(MockData.user.consent)
        #expect(state.user?.consent == demoConsent, "the store read in demo mode is the demo's")
        let model = graph.screens.profile
        #expect(!model.showsAccountConsent && !model.consentIsCurrent && !model.consentNeedsAttention)
        #expect(model.consentText == "Not shown")
        let detail = try #require(model.consentDetail)
        for shown in [Fmt.date(demoConsent.grantedAt), demoConsent.policyVersion, Fmt.date(accountConsent.grantedAt),
                      accountConsent.policyVersion] {
            #expect(!detail.contains(shown), "\(shown) in \(detail)")
        }
        #expect(detail.hasPrefix("Demo data is on"), "\(detail)")
        // No Review or Withdraw: in demo mode they would reach the demo's platform, never the account.
        let facts = ProfileRowFacts(model, journalLive: false, bedtimeEnabled: true)
        #expect(ProfilePage.sections(.privacyAndData, facts).first?.rows == [.consent])
        try await HostedWindow.run(width: 390, height: 4400, graph.page(.privacyAndData)) { w in
            try await w.settle()
            let labels = w.nodes().flatMap { [$0.label, $0.value ?? ""] }
            #expect(!labels.contains { $0.contains(Fmt.date(demoConsent.grantedAt)) || $0.contains("Agreed on") }, "\(labels)")
            #expect(!labels.contains("Withdraw consent") && !labels.contains("Review and agree"))
            #expect(w.nodes().first { $0.identifier == ProfileRow.consent.identifier }?.value == "Not shown")
        }
        let signedOut = try await ProfileShotGraph.make("signed-out")
        defer { signedOut.tearDown() }
        let outFacts = ProfileRowFacts(signedOut.screens.profile, journalLive: false, bedtimeEnabled: true)
        #expect(!ProfilePage.sections(.privacyAndData, outFacts).contains { $0.id == .consent })
        #expect(signedOut.screens.profile.consentDetail == nil)
    }

    // MARK: 32. status

    private nonisolated static let now = Date(timeIntervalSince1970: 1_792_300_000)
    private var now: Date { Self.now }
    private var fiveHoursAgo: Date { now.addingTimeInterval(-5 * 3_600) }

    /// Apple Health uploaded just now unless the test says otherwise.
    private func decide(_ line: SyncLine, demo: Bool = false, lastUpdated: Date? = nil,
                        lastSync: Date? = ProfileDataTests.now) -> ProfileStatus {
        ProfileStatus.decide(line, isDemo: demo, lastUpdated: lastUpdated, lastSync: lastSync)
    }

    @Test("Spec 32: up to date is a filled ink dot; updating a hollow one")
    func upToDateAndUpdating() {
        let fresh = decide(.upToDate(now, demo: false))
        #expect(fresh.word == .upToDate && fresh.dot == .filled && fresh.tap == .syncDetails)
        #expect(fresh.text(now: now) == "Apple Health · up to date")
        for line: SyncLine in [.reading(.quantity(.heartRate)), .uploading(records: 12), .scoring(night: true), .scoringSlow, .updating] {
            let s = decide(line)
            #expect(s.word == .updating && s.dot == .hollow && s.tap == .syncDetails, "\(line)")
            #expect(s.text(now: now) == "Apple Health · updating…")
        }
        // Nothing is read while the iPhone is locked: never "updating…", the last upload's age instead.
        let locked = decide(.waitingForUnlock, lastSync: fiveHoursAgo)
        #expect(locked.word == .updated(fiveHoursAgo) && locked.dot == .hollow && locked.tap == .none, "nothing to open")
        #expect(decide(.waitingForUnlock, lastSync: nil).word == .notUpdatedYet)
        let first = decide(.upToDate(nil, demo: false))
        #expect(first.word == .notUpdatedYet && first.dot == .hollow)
    }

    @Test("Spec 32: the row never claims a freshness it doesn't have: a failed upload and up to date need Apple Health's last upload")
    func freshness() {
        // The data loaded just now, but Apple Health never uploaded: "not updated yet", with the failure or without.
        #expect(decide(.paused, lastUpdated: now, lastSync: nil).word == .notUpdatedYet)
        #expect(decide(.upToDate(now, demo: false), lastUpdated: now, lastSync: nil).word == .notUpdatedYet)
        // A failed upload's age is the last good upload's, not the last load's.
        let paused = decide(.paused, lastUpdated: now, lastSync: fiveHoursAgo)
        #expect(paused.word == .updated(fiveHoursAgo) && paused.dot == .attention)
        // The demo's sample is always there.
        let demo = decide(.upToDate(now, demo: true), demo: true, lastUpdated: now, lastSync: nil)
        #expect(demo.word == .upToDate && demo.text(now: now) == "Demo data · up to date")
    }

    @Test("Spec 32: the model passes Settings.lastSync, not the last load, to the row")
    func modelFreshness() async throws {
        let graph = try await ProfileShotGraph.make("signed-in")
        defer { graph.tearDown() }
        let model = graph.screens.profile
        graph.settings.lastSync = nil
        #expect(model.status(line: .upToDate(now, demo: false)).word == .notUpdatedYet)
        #expect(model.status(line: .paused).word == .notUpdatedYet)
        graph.settings.lastSync = fiveHoursAgo
        #expect(model.status(line: .paused).word == .updated(fiveHoursAgo))
        #expect(model.status(line: .upToDate(now, demo: false)).word == .upToDate)
    }

    @Test("Spec 32: offline and old data are a warning dot; old data says when and taps to try again")
    func offlineAndStale() {
        let offline = decide(.offline)
        #expect(offline.word == .offline && offline.dot == .attention)
        #expect(offline.text(now: now) == "Apple Health · offline")
        let stale = decide(.stale(since: fiveHoursAgo))
        #expect(stale.word == .updated(fiveHoursAgo) && stale.dot == .attention && stale.tap == .retry)
        let text = stale.word.text(now: now, locale: Locale(identifier: "en_US"))
        #expect(text.hasPrefix("updated ") && text.contains("5") && text.hasSuffix("ago"), "\(text)")
        let failed = decide(.issue(.today), lastUpdated: fiveHoursAgo)
        #expect(failed.word == .updated(fiveHoursAgo) && failed.dot == .attention && failed.tap == .syncDetails)
        #expect(decide(.paused, lastSync: nil).word == .notUpdatedYet)
    }

    @Test("Spec 32: action needed is the alert dot, and opens the gate")
    func actionNeeded() {
        let consent = decide(.actionNeeded(.consent))
        #expect(consent.word == .actionNeeded && consent.dot == .alert && consent.tap == .gate(.consent))
        #expect(consent.text(now: now) == "Apple Health · action needed")
        #expect(decide(.actionNeeded(.invite)).tap == .gate(.invite))
        let signedOut = decide(.issue(.today, signedOut: true))
        #expect(signedOut.word == .actionNeeded && signedOut.dot == .alert && signedOut.tap == .signIn, "Today's card's Sign in")
    }

    @Test("Spec 32: the row's tap does what Today's line does: Sync details, the gate, sign in again")
    func tapRouting() async throws {
        let graph = try await ProfileShotGraph.make("signed-in")
        defer { graph.tearDown() }
        let model = graph.screens.profile
        #expect(model.tapStatus(.syncDetails), "the page pushes Sync details")
        #expect(!model.tapStatus(.none) && model.statusWork == nil)
        let onboarding = graph.screens.onboarding
        onboarding.later(.consent)
        #expect(onboarding.deferred.contains(.consent))
        #expect(!model.tapStatus(.gate(.consent)))
        #expect(!onboarding.deferred.contains(.consent), "the gate shows again")
        #expect(graph.state.env.auth.isSignedIn)
        #expect(!model.tapStatus(decide(.issue(.today, signedOut: true)).tap))
        await model.statusWork?.value
        #expect(!graph.state.env.auth.isSignedIn, "back to Welcome to sign in again")
    }

    @Test("Spec 32, hosted: the identity row's tap pushes Sync details")
    func hostedTap() async throws {
        let graph = try await ProfileShotGraph.make("signed-in")
        defer { graph.tearDown() }
        try await HostedWindow.run(width: 390, height: 844, graph.view) { w in
            try await w.settle()
            let row = try #require(w.nodes().first { $0.identifier == "profile.identity" })
            #expect(row.hint == "Opens sync details" && row.traits.contains(.button), "\(row.hint ?? "")")
            #expect(row.activate())
            try await w.settle()
            #expect(w.nodes().contains { $0.label.lowercased() == "engine" }, "Sync details is on screen")
        }
    }

    @Test("Spec 32: in the demo the source is Demo data, and it is always up to date")
    func demo() {
        let s = decide(.upToDate(nil, demo: true), demo: true)
        #expect(s.word == .upToDate && s.dot == .filled)
        #expect(s.text(now: now) == "Demo data · up to date")
        #expect(s.spoken(now: now) == "Demo data, up to date.")
    }

    @Test("Spec 32: never teal; each state also has its own word and shape")
    func neverTeal() {
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        func rgba(_ color: Color) -> [CGFloat] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b, a].map { ($0 * 255).rounded() }
        }
        for dot in ProfileStatus.Dot.allCases {
            #expect(rgba(dot.color) != rgba(Theme.recovery), "\(dot)")
        }
        // Colour is never the only cue: filled and hollow share the ink, and the words differ for every dot.
        let words = [decide(.upToDate(now, demo: false)), decide(.updating), decide(.offline), decide(.actionNeeded(.consent))]
            .map { $0.word.text(now: now) }
        #expect(Set(words).count == words.count)
    }

    // MARK: 33. rows

    private let oldRows: Set<ProfileRow> = [
        .birthYear, .maxHR, .sleepBase, .rescore, .devices, .appleHealth, .allowHealth, .openHealth, .lastSync,
        .deviceID, .syncNow, .syncDetails, .importTraining, .demoMode, .jumpToNext, .sessionLayout, .saveWorkouts,
        .notifications, .journal, .heroNumerals, .bedtime, .consent, .reviewConsent, .checkConsent, .withdrawConsent,
        .nutritionPrivacy, .analytics, .email, .timezone, .signInMethods, .changePassword, .deleteAccount, .signedIn,
        .version, .reportProblem, .privacyPolicy, .terms, .appleHealthPrivacy, .garminHealth, .licences,
    ]

    @Test("The five groups and their rows, in order")
    func groupOrder() {
        let facts = ProfileRowFacts(journalLive: true)
        let groups = ProfileRows.groups(facts)
        #expect(groups.map(\.group) == [.you, .general, .data, .resources, .legal])
        #expect(groups.map(\.rows) == [
            [.bodyAndBaselines], [.account, .notifications, .display, .training, .journal, .bedtime],
            [.devices, .privacyAndData], [.whatsNew, .reportProblem, .rateApp],
            [.privacyPolicy, .terms, .appleHealthPrivacy, .garminHealth, .licences],
        ])
        #expect(!facts.showsPlus)
        // The moved rows keep their pre-P1 identifiers (UI tests and support find them by these).
        #expect(ProfileRow.devices.identifier == "profile.devices")
        #expect(ProfileRow.reportProblem.identifier == "profile.reportProblem")
    }

    @Test("Every pre-P1 row has its home when visible across account, demo and devices states", arguments: [false, true])
    func homes(devicesEnabled: Bool) {
        var live = ProfileRowFacts(devicesEnabled: devicesEnabled, canAskForHealth: true, showsImport: true, showsSessionLayout: true,
                                   journalLive: true, showsAnalytics: true, canChangePassword: true, showsEmail: true,
                                   nutritionAvailable: true)
        var demo = live
        demo.isDemo = true
        var signedOutDemo = demo
        signedOutDemo.isSignedIn = false
        let consentActions: Set<ProfileRow> = [.reviewConsent, .checkConsent, .withdrawConsent]
        let accountRows: Set<ProfileRow> = [.email, .timezone, .signInMethods, .changePassword, .deleteAccount]
        // With tracker setup on, the Garmin link goes, and DevicesAndSyncView's own `devices.*` controls stand in for
        // RYFT's read access and Sync details (DevicesUITests covers them).
        let healthLink: Set<ProfileRow> = devicesEnabled
            ? [.garminHealth, .appleHealth, .allowHealth, .openHealth, .syncDetails] : []

        func check(_ facts: ProfileRowFacts, hidden: Set<ProfileRow>) {
            for group in ProfileRows.groups(facts) {
                #expect(Set(group.rows).count == group.rows.count)
            }
            for page in ProfilePage.allCases {
                for section in ProfilePage.sections(page, facts) {
                    #expect(Set(section.rows).count == section.rows.count)
                }
            }
            for row in oldRows {
                let home = ProfileRows.home(of: row, facts)
                #expect((home == .hidden) == hidden.contains(row), "\(row) → \(home)")
                switch row {
                case .saveWorkouts:
                    #expect(home == .multiple([.page(.training, .training), .page(.devicesAndSync, .healthWrites)]))
                case .deleteAccount where facts.isSignedIn:
                    #expect(home == .multiple([.page(.account, .account), .page(.privacyAndData, .yourData)]))
                default:
                    if case .multiple = home { Issue.record("\(row) has more than one home") }
                }
            }
        }

        check(live, hidden: healthLink.union([.signedIn, .reviewConsent, .checkConsent]))
        check(demo, hidden: healthLink.union(consentActions).union([.signedIn, .nutritionPrivacy]))
        check(signedOutDemo, hidden: healthLink.union(consentActions).union(accountRows).union([.consent, .analytics, .nutritionPrivacy]))
        live.consentIsCurrent = false
        check(live, hidden: healthLink.union([.signedIn, .withdrawConsent, .checkConsent]))
        live.consentAwaitsConfirmation = true
        check(live, hidden: healthLink.union([.signedIn, .reviewConsent]))

        #expect(ProfileRows.home(of: .devices, live) == .top(.data))
        #expect(ProfileRows.home(of: .reportProblem, live) == .top(.resources))
        #expect(ProfileRows.home(of: .version, live) == .page(.whatsNew, .version))
    }

    @Test("Page sections follow their flags and end with destructive actions")
    func visibility() {
        let gated = ProfileRowFacts(showsTraining: false, showsNotifications: false, bedtimeEnabled: false, canExport: false)
        #expect(ProfileRows.rows(.general, gated) == [.account, .display])
        #expect(ProfilePage.sections(.training, gated).isEmpty)
        #expect(ProfilePage.sections(.display, gated).flatMap(\.rows) == [.heroNumerals])
        #expect(ProfileRows.home(of: .saveWorkouts, gated) == .hidden)
        #expect(ProfileRows.home(of: .allowHealth, gated) == .hidden)
        #expect(ProfileRows.home(of: .changePassword, gated) == .hidden)
        #expect(ProfileRows.home(of: .export, gated) == .hidden)
        #expect(ProfileRows.home(of: .analytics, gated) == .hidden, "no Analytics card while the toggle can't show")

        // Train switched off with imports on: Training stays, with the import rows alone (as Devices and sync had them).
        var importOnly = gated
        importOnly.showsImport = true
        #expect(ProfileRows.rows(.general, importOnly) == [.account, .display, .training])
        #expect(ProfilePage.sections(.training, importOnly).flatMap(\.rows) == [.importTraining])

        let signedIn = ProfileRowFacts(showsImport: true, showsSessionLayout: true, consentAwaitsConfirmation: true, showsAnalytics: true,
                                      canChangePassword: true, showsEmail: true, nutritionAvailable: true)
        #expect(ProfilePage.sections(.account, signedIn).flatMap(\.rows) ==
                [.email, .timezone, .signInMethods, .changePassword, .logOutRow, .deleteAccount])
        #expect(ProfilePage.sections(.training, signedIn).flatMap(\.rows) ==
                [.jumpToNext, .sessionLayout, .saveWorkouts, .importTraining])
        #expect(ProfilePage.sections(.devicesAndSync, signedIn).map(\.rows) ==
                [[.appleHealth, .openHealth], [.lastSync, .syncNow, .deviceID], [.saveWorkouts], [.rescore, .demoMode], [.syncDetails]])
        #expect(ProfilePage.sections(.privacyAndData, signedIn).map(\.rows) ==
                [[.consent, .checkConsent, .withdrawConsent], [.analytics], [.nutritionPrivacy], [.export, .deleteAccount]])
        let destructive: Set<ProfileRow> = [.deleteAccount, .withdrawConsent]
        for page in ProfilePage.allCases {
            for section in ProfilePage.sections(page, signedIn) {
                #expect(section.rows.dropLast().allSatisfy { !destructive.contains($0) })
            }
        }

        let signedOutDemo = ProfileRowFacts(isSignedIn: false, isDemo: true)
        #expect(ProfilePage.sections(.account, signedOutDemo).flatMap(\.rows) == [.signedIn])
        #expect(ProfilePage.sections(.privacyAndData, signedOutDemo).flatMap(\.rows) == [.export])
        #expect(ProfileRows.buttons(signedIn) == [.logOut])
        #expect(ProfileRows.buttons(gated) == [.logOut])
        #expect(ProfileRows.buttons(signedOutDemo).isEmpty)
    }

    @Test("Hosted: the top page's identifiers and the moved identifiers on their own pages")
    func hostedIdentifiers() async throws {
        let graph = try await ProfileShotGraph.make("signed-in")
        defer { graph.tearDown() }
        let model = graph.screens.profile
        let facts = ProfileRowFacts(model, journalLive: graph.screens.journal.isLive, bedtimeEnabled: graph.screens.bedtime.isEnabled)
        #expect(facts.isSignedIn && facts.devicesEnabled && facts.canExport)
        let topIDs = ProfileRows.groups(facts).flatMap(\.rows).map(\.identifier) + ["profile.identity", "profile.logOut"]
        try await HostedWindow.run(width: 390, height: 4400, graph.view) { w in
            try await w.settle()
            let found = Self.identifiers(in: w.host.view)
            for id in topIDs { #expect(found[id] == 1, "\(id): \(found[id] ?? 0)") }
            #expect(found[ProfileRows.devCatalog] == nil && found[ProfileRows.devFlags] == nil)
        }

        let pages: [(ProfileRoute, [String])] = [
            (.body, ["profile.birthYear", "profile.maxHR", "profile.sleepBase"]),
            (.account, ["profile.signInMethods", "profile.logOutRow", "profile.deleteAccount"]),
            (.display, ["profile.heroNumerals"]),
            (.training, ["profile.jumpToNext", "profile.saveWorkouts", "profile.importTraining"]),
            (.devices, ["profile.lastSync", "profile.syncNow", "profile.demoMode", "profile.saveWorkouts"]),
            (.privacyAndData, ["profile.consent", "profile.export", "profile.deleteAccount"]),
            (.whatsNew, ["profile.version"]),
        ]
        for (route, rowIDs) in pages {
            try await HostedWindow.run(width: 390, height: 4400, graph.page(route)) { w in
                try await w.settle()
                let found = Self.identifiers(in: w.host.view)
                for id in rowIDs { #expect(found[id] == 1, "\(id): \(found[id] ?? 0)") }
                #if DEBUG
                if route == .devices { #expect(found[ProfileRows.devCatalog] == 1 && found[ProfileRows.devFlags] == 1) }
                #endif
            }
        }
    }

    /// How many elements carry each accessibility identifier in the tree, SwiftUI's nodes and UIKit's views alike (a menu is
    /// UIKit's); each object counts once.
    private static func identifiers(in root: UIView) -> [String: Int] {
        var found: [String: Int] = [:]
        var seen = Set<ObjectIdentifier>()
        func walk(_ object: NSObject, depth: Int) {
            guard depth < 60, seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let id = object.value(forKey: "accessibilityIdentifier") as? String, !id.isEmpty { found[id, default: 0] += 1 }
            if let elements = object.accessibilityElements {
                for case let child as NSObject in elements { walk(child, depth: depth + 1) }
            } else {
                let count = object.accessibilityElementCount()
                if count != NSNotFound, count > 0 {
                    for i in 0..<count { if let child = object.accessibilityElement(at: i) as? NSObject { walk(child, depth: depth + 1) } }
                }
            }
            if let view = object as? UIView { for sub in view.subviews { walk(sub, depth: depth + 1) } }
        }
        walk(root, depth: 0)
        return found
    }

    @Test("The Hero numbers menu row: the choice as its value, a 46 pt row, inside the window at AX3")
    func heroNumbersRow() async throws {
        let s = Settings(defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard)
        let row = GroupedCard { HeroNumbersMenuRow(selection: Bindable(s).heroNumerals) }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        for (typeSize, category) in [(DynamicTypeSize.large, UIContentSizeCategory.large), (.accessibility3, .accessibilityExtraLarge)] {
            try await HostedWindow.run(width: 390, height: 700, typeSize: typeSize, category: category, row) { w in
                try await w.settle()
                let menu = try #require(w.node("Hero numbers", exactly: true))
                #expect(menu.value == "Dots", "\(menu.value ?? "")")
                #expect(menu.frame.height >= ProfileLayout.rowMinHeight - 0.5 && menu.frame.maxX <= 390.5, "\(menu.frame)")
            }
        }
    }
}
