import SwiftUI

/// Profile's identity, five groups and Log out. The stack builds each subpage; the prompts sit above it.
struct ProfileView: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(\.appEnvironment) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var prompts = ProfilePrompts()
    @State private var legal: LegalPage?
    @State private var path: NavigationPath
    /// The identity row's tap: Sync details, pushed.
    @State private var showsSyncDetails = false

    private var model: ProfileViewModel { screens.profile }

    private typealias L = ProfileLayout

    /// Previews and hosted tests can start with a page already on the stack.
    init(initialRoute: ProfileRoute? = nil) {
        var path = NavigationPath()
        if let initialRoute { path.append(initialRoute) }
        _path = State(initialValue: path)
    }

    var body: some View {
        @Bindable var prompts = prompts
        NavigationStack(path: $path) {
            ScreenScaffold(showsHeader: false) {
                page
            }
            .navigationDestination(for: ProfileRoute.self) { destination($0) }
            .navigationDestination(isPresented: $showsSyncDetails) { SyncDetailsView(model: model.syncDetails) }
        }
        .environment(prompts)
        .safariSheet($legal)
        // The export file goes as soon as the share sheet is done with it (or closed by a swipe).
        .sheet(item: Bindable(model).exported, onDismiss: { model.removeExportFiles() }) {
            DataExportShareSheet(file: $0, completion: { model.removeExportFiles() }).presentationDetents([.medium, .large])
                .presentedRoot()
        }
        .bodySettingSheet($prompts.editing, editor: model.bodySettings)
        .task { await model.refreshHealthStatus() }
        // The Journal row is there while the journal is live: after the Demo data switch forgot the other side's, this
        // side's is asked for here too (as Today and Insights ask), so the row doesn't wait for them.
        .task(id: model.demoMode) {
            if screens.journal.availability == .unknown { await screens.journal.load() }
        }
        .confirmationDialog("Log out of RYFT?", isPresented: $prompts.showLogOutConfirm, titleVisibility: .visible) {
            if prompts.unsentAtLogOut > 0 {
                // Send first (10 s at most), then log out if nothing is left and it's still the same account;
                // otherwise ask again with what's left. Not offered when nothing can be sent now.
                if model.sendFirst == .available {
                    Button {
                        Task {
                            prompts.sendsFirst = true
                            let outcome = await model.sendFirstThenLogOut()
                            prompts.sendsFirst = false
                            // Asked again with what's left; never under a held Log out (D6: `.held`, or a withdrawal
                            // that began as the wait ended).
                            if case .unsent(let left) = outcome, !model.withdrawingConsent {
                                prompts.unsentAtLogOut = left
                                prompts.showLogOutConfirm = true
                            }
                        }
                    } label: {
                        Text("Send first", comment: "Log out: upload the activities and nights not at RYFT yet, then log out.")
                    }
                    .accessibilityIdentifier(ProfileRows.logOutSendFirst)
                }
                Button(role: .destructive) {
                    Task { await model.logOut() }
                } label: {
                    Text("Log out anyway", comment: "Log out: delete the activities and nights not at RYFT yet.")
                }
                .accessibilityIdentifier(ProfileRows.logOutAnyway)
            } else {
                Button("Log out", role: .destructive) {
                    Task { await model.logOut() }
                }
            }
        } message: {
            if prompts.unsentAtLogOut > 0, model.sendFirst == .offline {
                Text("\(prompts.unsentAtLogOut) activities or nights haven't reached RYFT yet, and you're offline. Logging out deletes them from this iPhone.",
                     comment: "Log out offline with uploads pending (Send first isn't offered); the number of activities and nights.")
            } else if prompts.unsentAtLogOut > 0 {
                Text("\(prompts.unsentAtLogOut) activities or nights haven't reached RYFT yet. Logging out deletes them from this iPhone.",
                     comment: "Log out with uploads pending; the number of activities and nights.")
            } else {
                Text("Cached scores and Health sync progress are removed from this iPhone. Your account and data stay on the RYFT platform.")
            }
        }
        .alert("Delete your RYFT account?",
               isPresented: Binding(get: { prompts.deleteConfirmation != nil }, set: { if !$0 { prompts.deleteConfirmation = nil } }),
               presenting: prompts.deleteConfirmation) { confirmation in
            Button("Delete account", role: .destructive) {
                Task { await model.deleteAccount(confirmedFor: confirmation) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently deletes your account and everything RYFT stores for you: all synced Health samples, sleep, workouts, scores, devices and your profile. It can't be undone. Apple Health on this iPhone isn't touched.")
        }
        .sheet(isPresented: $prompts.showChangePassword) {
            SetNewPasswordView(mode: .change).presentedRoot()
        }
        .confirmationDialog("Withdraw your consent?", isPresented: $prompts.showWithdrawConfirm, titleVisibility: .visible) {
            Button("Withdraw consent", role: .destructive) {
                Task { await model.withdrawConsent() }
            }
            if model.canExport {
                Button("Export my data first") { Task { await model.export() } }
            }
            Button("Delete account instead", role: .destructive) { prompts.deleteConfirmation = AccountBinding(env) }
        } message: {
            Text("RYFT stops syncing and scoring your health data. Nothing is deleted: your scores stay readable, and you can export your data or delete your account at any time.")
        }
        // Cancel keeps the demo running: nothing is called. Confirm works out again what goes (`endDemo`).
        .confirmationDialog(Text("Turn off Demo data?",
                                 comment: "Profile → Demo data switched off while workouts logged in the demo exist"),
                            isPresented: Binding(get: { prompts.confirmDemoExit != nil },
                                                 set: { if !$0 { prompts.confirmDemoExit = nil } }),
                            titleVisibility: .visible, presenting: prompts.confirmDemoExit) { _ in
            Button(role: .destructive) {
                Task { await model.endDemo() }
            } label: {
                Text("Discard and turn off", comment: "Deletes them and turns Demo data off")
            }
            .accessibilityIdentifier(ProfileRows.demoDiscard)
            Button(role: .cancel) {} label: {
                Text("Keep Demo data", comment: "Demo data stays on; nothing is deleted")
            }
            .accessibilityIdentifier(ProfileRows.demoKeep)
        } message: { workouts in
            Text("The \(workouts.count) workouts you logged with Demo data will be discarded. This can't be undone.",
                 comment: "The count includes one in progress. They're deleted from this iPhone; they only ever reached the demo's sample platform.")
        }
    }

    // MARK: - the page

    private var page: some View {
        let facts = ProfileRowFacts(model, journalLive: screens.journal.isLive, bedtimeEnabled: screens.bedtime.isEnabled)
        return VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: Text("Profile"))
            ProfileIdentitySection(showsSyncDetails: $showsSyncDetails)
                .padding(.top, L.headerToIdentity)
            // The RYFT Plus slot stays hidden until StoreKit ships (ProfileRowFacts.showsPlus).
            ForEach(ProfileRows.groups(facts)) { entry in
                if entry.group == .legal {
                    BrandLockup()
                        .frame(maxWidth: .infinity)
                        .padding(.top, L.groupGap)
                }
                group(entry)
                    .padding(.top, entry.group == .legal ? L.lockUpToGroup
                        : entry.group == .you ? L.identityToFirstGroup : L.groupGap)
            }
            if ProfileRows.buttons(facts).contains(.logOut) { logOutButton }
        }
    }

    private func group(_ entry: ProfileRows.Shown) -> some View {
        let footer = entry.group == .legal
            ? Text("RYFT is a wellness tool, not a medical device. Talk to a doctor about health concerns.") : nil
        return GroupedCard(entry.group.title, footer: footer) { ProfileRowList(rows: entry.rows) }
    }

    // MARK: - Log out

    /// While a consent withdrawal is on its way (D6), the pill dims, with the reason under it and in its VoiceOver hint.
    private var logOutButton: some View {
        let held = model.withdrawingConsent
        return VStack(alignment: .leading, spacing: L.buttonsToMessage) {
            PillButton(Text("Log out"), style: .secondary, busy: prompts.sendsFirst || model.loggingOut) {
                prompts.confirmLogOut(model)
            }
            .disabled(held)
            .accessibilityHint(prompts.logOutHint(model))
            .accessibilityIdentifier(ProfileButton.logOut.identifier)
            if held {
                Text(verbatim: ProfileViewModel.withdrawalHoldReason)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
        }
        .animation(Theme.Motion.respecting(reduceMotion), value: held)
        .padding(.top, L.buttonsTop)
    }

    // MARK: - subpages

    @ViewBuilder private func destination(_ route: ProfileRoute) -> some View {
        switch route {
        case .body: ProfilePageView(page: .body)
        case .account: ProfilePageView(page: .account)
        case .display: ProfilePageView(page: .display)
        case .training: ProfilePageView(page: .training)
        case .privacyAndData: ProfilePageView(page: .privacyAndData)
        case .whatsNew: ProfilePageView(page: .whatsNew)
        case .devices: ProfileDevicesAndSyncPage()
        case .syncDetails: SyncDetailsView(model: model.syncDetails)
        case .notifications: NotificationSettingsView()
        case .journal: JournalSettingsView(store: screens.journal)
        case .bedtime: SleepScheduleView(planner: screens.bedtime)
        case .signInMethods: SignInMethodsView()
        case .reportProblem: ReportProblemView(model: model.report)
        case .licences: LicensesView()
        case .nutritionPrivacy: NutritionPrivacyEntryView()
        #if DEBUG
        case .catalog: DebugComponentCatalog()
        case .flags: FeatureFlagsDebugView()
        #endif
        }
    }

    static let healthAppHint = Text("Opens the Health app", comment: "VoiceOver hint of Profile's Open Health row.")

    static var version: String { AppInfo.version }
}

/// A card's footer parts, 8 apart (`GroupedListSpec.footerGap`); nothing when there are none.
struct FooterStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.footerGap) { content() }
    }
}

extension ProfileRowFacts {
    /// The model's account, flags and switches, and the two shared stores' availability.
    @MainActor
    init(_ model: ProfileViewModel, journalLive: Bool, bedtimeEnabled: Bool, showsAnalytics: Bool = false) {
        // Profile's own Health rows show only without tracker setup, so `canAskForHealth` is the model's.
        self.init(isSignedIn: model.isSignedIn, devicesEnabled: model.devices.isEnabled, canAskForHealth: model.canAskForHealth,
                  showsTraining: model.showsTraining, showsImport: model.showsImport, showsSessionLayout: model.showsSessionLayout,
                  showsNotifications: model.showsNotifications, journalLive: journalLive, bedtimeEnabled: bedtimeEnabled,
                  consentIsCurrent: model.consentIsCurrent, consentAwaitsConfirmation: model.consentAwaitsConfirmation,
                  showsAnalytics: showsAnalytics, isDemo: model.demoMode, canChangePassword: model.canChangePassword,
                  hasTimezone: model.timezone != nil, showsEmail: model.showsEmailRow, canExport: model.canExport,
                  nutritionAvailable: model.nutritionAvailable)
    }
}

// MARK: - the identity row's models

/// The identity row, reading the sync's line in its own body: the line changes with every sync step, and only this row
/// shows it, so the page's groups don't re-render for it.
private struct ProfileIdentitySection: View {
    @Binding var showsSyncDetails: Bool
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        let model = screens.profile
        let status = model.status(line: screens.today.syncLine)
        ProfileIdentityRow(identity: model.identity, status: status) {
            if model.tapStatus(status.tap) { showsSyncDetails = true }
        }
    }
}

// MARK: - previews (dark; default and AX3; design.md §P5-11)

#if DEBUG
/// Profile on a graph of its own: signed in or not, Demo data on or off, the account and today's strain as the state needs.
/// Syncing is the identity row's preview (`ProfileIdentity.swift`): the line comes from the sync's own state.
@MainActor
enum ProfilePreview {
    enum Case {
        case signedIn, noName, noStrain, signedOutDemo, signedInDemo, offline, consentOutdated
        /// A consent withdrawal on its way that never answers: Demo data, Log out and the overrides held (D6).
        case withdrawing
        /// Agreed on this iPhone, RYFT's word on it never coming: Given, the footer on what this iPhone waits for; Check with
        /// RYFT and Withdraw.
        case consentUnconfirmed
        /// The same, offline: Check with RYFT dimmed, and the footer says this iPhone asks again once back online.
        case consentUnconfirmedOffline
        /// The same, Check with RYFT tapped and its `/v1/me` never answering: the row busy, its spinner bright.
        case consentChecking
        /// The same, Check with RYFT answered `503`: RYFT's own words under Privacy, with Details.
        case consentCheckFailed
    }

    static func page(_ kind: Case, route: ProfileRoute? = nil, devicesEnabled: Bool = true, ax3: Bool = false) -> some View {
        let demo = kind == .signedOutDemo || kind == .signedInDemo
        let defaults = UserDefaults(suiteName: "ryft.preview.profile") ?? .standard
        let settings = Settings(defaults: defaults)
        // Apple Health uploaded a minute ago: "up to date" needs it.
        settings.lastSync = demo ? nil : .now.addingTimeInterval(-60)
        let api = MockPlatformAPI(activities: .demoSource())
        let withdrawing = kind == .withdrawing
        // Never answered while the preview is open; on a clock that stands still, so `SettingsWrite.deadline` never ends it.
        if withdrawing { api.beforeRevokeConsent = { try? await Task.sleep(for: .seconds(86_400)) } }
        let checking = kind == .consentChecking, checkFailed = kind == .consentCheckFailed
        let unconfirmed = kind == .consentUnconfirmed || kind == .consentUnconfirmedOffline || checking || checkFailed
        // RYFT's word never comes, or comes back as a 503 past the read's Retry-After cap (it fails at once).
        if checkFailed {
            api.faults["me"] = .init(.status(503, retryAfter: 600))
        } else if unconfirmed {
            api.beforeMe = { try? await Task.sleep(for: .seconds(86_400)) }
        }
        // Demo data on over a signed-in Apple account: the account's rows are the session's, never the demo's person.
        let env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: api, demoAPI: api,
                                 auth: .preview(signedIn: kind != .signedOutDemo, provider: kind == .signedInDemo ? "apple" : "email"),
                                 persistence: TrainStore(inMemory: true),
                                 clock: withdrawing || checking ? TestClock(now: .now) : SystemClock(), notifier: MockNotifier(),
                                 flags: StaticFlags([.devicesSetup: devicesEnabled]),
                                 connectivity: .preview(online: kind != .offline && kind != .consentUnconfirmedOffline),
                                 defaults: defaults, demoOverride: demo)
        env.uploader.gate = { _ in nil }
        // The 204 on this iPhone, RYFT's own word on it still out (on the graph's clock: one after now is void).
        if unconfirmed { env.consent.consented(to: MockData.policyVersion, at: env.clock.now()) }
        let state = AppState(env: env)
        state.history = MockData.history
        state.user = user(kind)
        var today = MockData.todayDetail
        if kind == .noStrain { today.score.strain = nil }
        state.today = today
        let sync = SyncService(env: env)
        let screens = ScreenModels(state: state, sync: sync,
                                   coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                                   store: TrainPreview.store, library: TrainPreview.library)
        return ProfileView(initialRoute: route)
            // The confirmation's Withdraw consent, tapped; or Check with RYFT.
            .task {
                if withdrawing { await screens.profile.withdrawConsent() }
                if checking || checkFailed { await screens.profile.checkConsent() }
            }
            .environment(\.appEnvironment, env)
            .environment(screens)
            .environment(settings)
            .environment(env.auth)
            .environment(sync)
            .environment(state)
            .environment(TrainPreview.library)
            .environment(TrainPreview.sync)
            .environment(TrainPreview.coordinator)
            .environment(env.connectivityMonitor)
            .toggleStyle(.ryft)
            .preferredColorScheme(.dark)
            .tint(Theme.textPrimary)
            .environment(\.dynamicTypeSize, ax3 ? .accessibility3 : .large)
    }

    private static func user(_ kind: Case) -> User {
        let u = MockData.user
        switch kind {
        case .noName:
            return User(id: u.id, name: "", email: u.email, provider: u.provider, tz: u.tz, maxHr: u.maxHr,
                        sleepBaseMin: u.sleepBaseMin, consent: u.consent, birthYear: u.birthYear)
        case .consentOutdated, .consentUnconfirmed, .consentUnconfirmedOffline, .consentChecking, .consentCheckFailed:
            return User(id: u.id, name: u.name, email: u.email, provider: u.provider, tz: u.tz, maxHr: u.maxHr,
                        sleepBaseMin: u.sleepBaseMin, birthYear: u.birthYear)
        default:
            return u
        }
    }
}

#Preview("Profile · signed in") { ProfilePreview.page(.signedIn) }
#Preview("Profile · signed in · AX3") { ProfilePreview.page(.signedIn, ax3: true) }
#Preview("Profile · no name (email)") { ProfilePreview.page(.noName) }
#Preview("Profile · no name (email) · AX3") { ProfilePreview.page(.noName, ax3: true) }
#Preview("Profile · no strain today") { ProfilePreview.page(.noStrain) }
#Preview("Profile · no strain today · AX3") { ProfilePreview.page(.noStrain, ax3: true) }
#Preview("Profile · signed out / demo") { ProfilePreview.page(.signedOutDemo) }
#Preview("Profile · signed out / demo · AX3") { ProfilePreview.page(.signedOutDemo, ax3: true) }
#Preview("Profile · signed in / demo") { ProfilePreview.page(.signedInDemo) }
#Preview("Profile · signed in / demo · AX3") { ProfilePreview.page(.signedInDemo, ax3: true) }
#Preview("Profile · offline") { ProfilePreview.page(.offline) }
#Preview("Profile · offline · AX3") { ProfilePreview.page(.offline, ax3: true) }
#Preview("Profile · consent outdated") { ProfilePreview.page(.consentOutdated) }
#Preview("Profile · consent outdated · AX3") { ProfilePreview.page(.consentOutdated, ax3: true) }
#Preview("Profile · consent not confirmed yet") { ProfilePreview.page(.consentUnconfirmed, route: .privacyAndData) }
#Preview("Profile · consent not confirmed yet · AX3") { ProfilePreview.page(.consentUnconfirmed, route: .privacyAndData, ax3: true) }
#Preview("Profile · consent not confirmed yet · offline") { ProfilePreview.page(.consentUnconfirmedOffline, route: .privacyAndData) }
#Preview("Profile · consent not confirmed yet · checking") { ProfilePreview.page(.consentChecking, route: .privacyAndData) }
#Preview("Profile · consent not confirmed yet · check failed") { ProfilePreview.page(.consentCheckFailed, route: .privacyAndData) }
#Preview("Profile · consent not confirmed yet · check failed · AX3") { ProfilePreview.page(.consentCheckFailed, route: .privacyAndData, ax3: true) }
#Preview("Profile · withdrawing consent") { ProfilePreview.page(.withdrawing) }
#Preview("Profile · withdrawing consent · AX3") { ProfilePreview.page(.withdrawing, ax3: true) }
#endif
