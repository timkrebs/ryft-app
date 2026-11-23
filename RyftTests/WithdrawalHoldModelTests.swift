import Foundation
import Testing
@testable import Ryft

/// D6, security review S-1: while a consent withdrawal is on its way, the model logs nobody out and doesn't switch Demo
/// data, whatever its view shows. Log out's "Send first" waits up to 10 s for the queue; a withdrawal begun during that
/// wait used to end unsent, because the log-out followed the upload. When the upload went up, it logged out; when the
/// wait ended with items left, the dialog came back with "Log out anyway" under a held pill. S-2: the withdrawal fails
/// fast (offline at once, no answer at `SettingsWrite.deadline`), so the hold lasts seconds. Synthetic data only (Alex Doe).
@MainActor
@Suite("D6: the model holds log-out and Demo data while a consent withdrawal runs, for seconds", .serialized)
struct WithdrawalHoldModelTests {
    nonisolated static let a = UUID(uuidString: "0000000A-0000-4000-8000-0000000000F3") ?? UUID()

    /// What the model handed VoiceOver, in order.
    @MainActor
    private final class Spoken {
        var lines: [String] = []
    }

    /// A signed-in account with Send first available: the test clock, consent given, an onboarding coordinator that
    /// knows the account, and a recorder for announcements.
    @MainActor
    private struct Graph {
        let clock = TestClock()
        let api = MockPlatformAPI()
        let client = MockAuthClient(session: .preview(id: WithdrawalHoldModelTests.a))
        let auth: AuthService
        let env: AppEnvironment
        let state: AppState
        let onboarding: OnboardingCoordinator
        let profile: ProfileViewModel
        let spoken = Spoken()

        init() {
            let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)") ?? .standard
            auth = AuthService(client: client, settings: Settings(defaults: defaults), defaults: defaults,
                               wipeLocalData: { _ in true },
                               deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                               postAppleAuthorization: { _ in })
            env = .test(api: api, clock: clock, auth: auth, flags: [.activitiesManual: true])
            // An account's switch, off (the setting falls back to `demoDefault`, on here): a held switch leaves it so.
            env.settings.demoMode = false
            env.uploader.random = { $0.lowerBound }
            env.uploader.gate = { _ in nil } // consent given: what goes up, goes up
            state = AppState(env: env)
            state.bindAccountHooks(auth, apiStatus: APIStatus())
            onboarding = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
            let sync = SyncService.ungated(env: env)
            profile = ProfileViewModel(state: state, sync: sync,
                                       coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: clock),
                                       onboarding: onboarding, apiStatus: APIStatus())
            profile.announce = { [spoken] in spoken.lines.append($0) }
        }

        /// A run that ended an hour ago, saved for the signed-in account: one item Log out would delete.
        func saveRun() -> UUID? {
            let end = clock.now().addingTimeInterval(-3_600)
            return env.activities.save(manual: ActivityDraft(sport: .running, start: end.addingTimeInterval(-1_800), end: end))?.id
        }
    }

    /// How Send first's wait ended once the withdrawal had begun.
    enum Ending: String, CaseIterable, Sendable {
        /// The queue went up: nothing left, so the log-out followed.
        case uploaded
        /// The 10 s were up with the item still out: the dialog asked again ("Log out anyway").
        case waitEnded
    }

    @Test("Send first with a withdrawal begun during its wait: nobody is logged out, nothing asks again, the withdrawal goes once and is announced",
          .timeLimit(.minutes(1)), arguments: Ending.allCases)
    func sendFirstNeverEndsAWithdrawal(_ ending: Ending) async throws {
        let g = Graph()
        await g.onboarding.check()
        try #require(g.saveRun() != nil)
        try #require(g.profile.sendFirst == .available && g.profile.unconfirmedActivities == 1)
        let upload = RequestHold()
        g.api.activitySource.beforeWrite = { await upload.wait() }
        let revoke = Gate()
        g.api.beforeRevokeConsent = { await revoke.wait() }

        let sending = Task { await g.profile.sendFirstThenLogOut() }
        #expect(await eventually { upload.waiting == 1 }, "the run's PUT is out")
        let withdrawing = Task { await g.profile.withdrawConsent() }
        #expect(await eventually { g.profile.withdrawingConsent }, "the withdrawal began during Send first's wait")

        switch ending {
        case .uploaded: upload.release()
        case .waitEnded: g.clock.advance(by: ActivityUploader.sendFirstLimit)
        }
        // Held, not `.loggedOut` (uploaded) or `.unsent(1)` (the view would ask again with "Log out anyway").
        #expect(await sending.value == .held, "\(ending)")
        #expect(g.auth.isSignedIn, "\(ending): still signed in")

        // "Log out anyway" from a dialog shown before the hold, and the Demo data switch: neither does anything.
        await g.profile.logOut()
        await g.profile.setDemoMode(true)
        // The switch's setting, not `demoMode`: the test environment pins `isDemo` off.
        #expect(g.auth.isSignedIn && !g.env.settings.demoMode, "\(ending): held, no sign-out and no Demo data")

        await revoke.open()
        await withdrawing.value
        upload.release()
        #expect(g.api.count("revokeConsent") == 1, "\(ending): \(g.api.calls)")
        #expect(g.auth.isSignedIn && !g.profile.withdrawingConsent)
        #expect(g.spoken.lines == [ProfileViewModel.consentWithdrawnAnnouncement], "\(ending): \(g.spoken.lines)")
    }

    @Test("Send first tapped while a withdrawal runs does nothing; once it ended, Log out works again", .timeLimit(.minutes(1)))
    func sendFirstDuringAWithdrawalIsHeldThenLogOutWorks() async throws {
        let g = Graph()
        await g.onboarding.check()
        try #require(g.saveRun() != nil)
        let revoke = Gate()
        g.api.beforeRevokeConsent = { await revoke.wait() }
        let withdrawing = Task { await g.profile.withdrawConsent() }
        #expect(await eventually { g.profile.withdrawingConsent })

        #expect(await g.profile.sendFirstThenLogOut() == .held)
        #expect(g.api.count("putActivity") == 0 && g.auth.isSignedIn, "nothing sent, nobody logged out")

        await revoke.open()
        await withdrawing.value
        await g.profile.logOut()
        #expect(!g.auth.isSignedIn, "live again: Log out logs out")
    }

    // MARK: round 3, C: no withdrawal while Log out runs

    @Test("Log out still deleting the push registration: a withdrawal is refused and sends nothing", .timeLimit(.minutes(1)))
    func noWithdrawalWhileLoggingOut() async throws {
        let g = Graph()
        await g.onboarding.check()
        let signOut = Gate()
        g.auth.beforeSignOut = { await signOut.wait() }

        let loggingOut = Task { await g.profile.logOut() }
        #expect(await eventually { g.profile.loggingOut }, "the sign-out waits for the push registration")
        await g.profile.withdrawConsent()
        #expect(g.api.count("revokeConsent") == 0 && !g.onboarding.isWithdrawing, "nothing sent: \(g.api.calls)")
        #expect(g.auth.isSignedIn)

        await signOut.open()
        await loggingOut.value
        #expect(!g.auth.isSignedIn && !g.profile.loggingOut)
    }

    // MARK: N-3: it ends when the answer is recorded

    @Test("The hold ends once the withdrawal is recorded, while its re-check is still out: Log out works, VoiceOver heard it",
          .timeLimit(.minutes(1)))
    func holdEndsWhenRecorded() async throws {
        let g = Graph()
        await g.onboarding.check()
        let asked = g.api.count("me")
        let check = Gate()
        g.api.beforeMeRead = { await check.wait() }

        let withdrawing = Task { await g.profile.withdrawConsent() }
        #expect(await eventually { g.api.count("revokeConsent") == 1 && g.api.count("me") > asked }, "recorded; the re-check is out")
        #expect(g.onboarding.isWithdrawing, "the withdrawal still runs: its re-check is held")
        #expect(!g.profile.withdrawingConsent && g.state.user?.consent == nil, "released with the recording")
        #expect(g.spoken.lines == [ProfileViewModel.consentWithdrawnAnnouncement], "heard as it was released: \(g.spoken.lines)")
        await g.profile.logOut()
        #expect(!g.auth.isSignedIn, "live: the withdrawal is on the platform and on this phone")

        await check.open()
        await withdrawing.value
        #expect(g.api.count("revokeConsent") == 1 && g.spoken.lines.count == 1)
    }

    // MARK: S-2: it fails fast, so the hold lasts seconds

    static let noConnection = "No connection. Check your internet and try again."

    @Test("Offline: the withdrawal fails at once and sends nothing; Log out is live again", .timeLimit(.minutes(1)))
    func offlineFailsAtOnce() async throws {
        let g = Graph()
        await g.onboarding.check()
        try #require(g.state.user?.consent != nil)
        g.env.connectivityMonitor.update(false)

        // No clock moves: it ends on its own, without waiting for a network.
        await g.profile.withdrawConsent()
        #expect(g.api.count("revokeConsent") == 0, "nothing sent: \(g.api.calls)")
        #expect(g.profile.consentError == Self.noConnection)
        #expect(!g.profile.withdrawingConsent && g.state.user?.consent != nil, "not held; the consent stays")
        #expect(g.spoken.lines.isEmpty)
        await g.profile.logOut()
        #expect(!g.auth.isSignedIn, "live: Log out logs out")
    }

    /// RYFT, asked again in time, still showed the consent: the withdrawal didn't reach it (round 5, option B).
    static let notReached = "Your withdrawal didn't reach RYFT, so syncing continues. Try again to stop it."

    @Test("No answer within SettingsWrite's deadline: RYFT is asked again; still given, it didn't reach RYFT, and Log out is live again",
          .timeLimit(.minutes(1)))
    func noAnswerFailsAtTheDeadline() async throws {
        let g = Graph()
        await g.onboarding.check()
        let revoke = Gate()
        g.api.beforeRevokeConsent = { await revoke.wait() }
        let sleeps = g.clock.pendingSleeps, reads = g.api.count("me")

        let withdrawing = Task { await g.profile.withdrawConsent() }
        #expect(await eventually { g.profile.withdrawingConsent && g.clock.pendingSleeps > sleeps }, "out, its deadline running")
        g.clock.advance(by: SettingsWrite.deadline)
        #expect(await eventually(timeout: .seconds(5)) { !g.profile.withdrawingConsent }, "ended at the deadline, not by an answer")
        // Not "No connection": it went out, and RYFT, asked again, still shows the consent.
        #expect(g.api.count("me") == reads + 1, "asked again: \(g.api.calls)")
        #expect(g.profile.consentError == Self.notReached)
        #expect(g.state.user?.consent != nil && g.profile.consentText == String(localized: "Given") && g.spoken.lines.isEmpty)
        await g.profile.logOut()
        #expect(!g.auth.isSignedIn, "live: Log out logs out")

        // Let go after the deadline: the request was cancelled while held here, before the mock takes a call, so the mock
        // never takes it. (A real DELETE cancelled that late may have reached RYFT: `noAnswerButItArrived`.)
        await revoke.open()
        await withdrawing.value
        #expect(await eventually(timeout: .seconds(1)) { g.api.count("revokeConsent") > 0 } == false, "\(g.api.calls)")
    }

    @Test("The fail-fast session's own timeout (20 s, before the deadline) reads as no answer too, never as no connection",
          .timeLimit(.minutes(1)))
    func sessionTimeoutAsksAgain() async throws {
        let g = Graph()
        await g.onboarding.check()
        g.api.faults["revokeConsent"] = .init(.timeout)
        let reads = g.api.count("me")

        await g.profile.withdrawConsent()
        #expect(g.api.count("me") == reads + 1, "asked again: \(g.api.calls)")
        #expect(g.profile.consentError == Self.notReached)
        #expect(!g.profile.withdrawingConsent && g.state.user?.consent != nil)
    }

    @Test("No answer, but RYFT has it: asked again, the consent is gone, so it is recorded as withdrawn (the row, the gate, no sheet)",
          .timeLimit(.minutes(1)))
    func noAnswerButItArrived() async throws {
        let g = Graph()
        await g.onboarding.check()
        try #require(g.onboarding.uploadGate(for: .healthKit) == nil, "open while consent is given")
        let revoke = Gate()
        // RYFT records the withdrawal, and its answer never comes.
        g.api.beforeRevokeConsent = { [api = g.api] in
            api.accountConsent = nil
            await revoke.wait()
        }
        let sleeps = g.clock.pendingSleeps, reads = g.api.count("me")

        let withdrawing = Task { await g.profile.withdrawConsent() }
        #expect(await eventually { g.profile.withdrawingConsent && g.clock.pendingSleeps > sleeps }, "out, its deadline running")
        g.clock.advance(by: SettingsWrite.deadline)
        await withdrawing.value
        #expect(g.api.count("me") == reads + 1, "asked again once: \(g.api.calls)")
        #expect(g.profile.consentError == nil, "it arrived: \(g.profile.consentError ?? "nil")")
        #expect(g.state.user?.consent == nil && g.profile.consentText == String(localized: "Not given"), "the row says so")
        #expect(g.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired), "uploads stop")
        #expect(g.onboarding.deferred.contains(.consent), "not asked about again on its own")
        #expect(!g.profile.withdrawingConsent && g.spoken.lines == [ProfileViewModel.consentWithdrawnAnnouncement])
        await revoke.open()
    }

    @Test("A 503 fails at once in RYFT's words, and trying again withdraws", .timeLimit(.minutes(1)))
    func busyPlatformFailsRetryably() async throws {
        let g = Graph()
        await g.onboarding.check()
        g.api.faults["revokeConsent"] = .init(.status(503, retryAfter: nil))

        await g.profile.withdrawConsent()
        #expect(g.profile.consentError == "RYFT is catching up. Try again in a moment.")
        #expect(!g.profile.withdrawingConsent && g.state.user?.consent != nil)

        g.api.faults["revokeConsent"] = nil
        await g.profile.withdrawConsent()
        #expect(g.profile.consentError == nil && g.state.user?.consent == nil, "withdrawn on the second try")
        #expect(g.spoken.lines == [ProfileViewModel.consentWithdrawnAnnouncement])
    }
}
