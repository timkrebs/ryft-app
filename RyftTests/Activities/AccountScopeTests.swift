import Auth
import Foundation
import SwiftData
import Testing
@testable import Ryft

/// A real `AuthService` on `MockAuthClient`, whose wipe works on the test store (as the live one does on
/// `TrainStore.shared`), with `AppState`'s account hooks bound as RyftApp binds them.
@MainActor
private final class AccountHarness {
    nonisolated static let a = UUID(uuidString: "0000000A-0000-4000-8000-00000000000A") ?? UUID()
    nonisolated static let b = UUID(uuidString: "0000000B-0000-4000-8000-00000000000B") ?? UUID()
    static var accountA: String { a.uuidString }
    static var accountB: String { b.uuidString }

    let clock = TestClock()
    let api = MockPlatformAPI()
    let persistence = TrainStore(inMemory: true)
    let client: MockAuthClient
    let auth: AuthService
    let env: AppEnvironment
    let state: AppState
    private(set) var wipes: [AuthService.Wipe] = []
    /// Runs inside `DELETE /v1/me` (a concurrent 401 or refresh failure, scripted), and what it answers.
    final class DuringDeletion: @unchecked Sendable {
        var run: (@MainActor @Sendable () async -> Void)?
        var authUserDeleted = true
        /// Thrown after `run` (the deletion failed or was cut short).
        var error: Error?
    }
    let duringDeletion = DuringDeletion()

    init(signedInAs account: UUID? = AccountHarness.a, demo: Bool = false, bindHooks: Bool = true) {
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let settings = Settings(defaults: defaults)
        settings.demoMode = demo
        client = MockAuthClient(session: account.map { .preview(id: $0) })
        let persistence = persistence, clock = clock, duringDeletion = duringDeletion
        var recorded: (AuthService.Wipe) -> Void = { _ in }
        auth = AuthService(client: client, settings: settings, defaults: defaults,
                           wipeLocalData: { wipe in
                               persistence.wipe(parkingActivitiesOf: wipe.parking, at: clock.now())
                               recorded(wipe)
                           },
                           deleteRemoteAccount: {
                               await duringDeletion.run?()
                               if let error = duringDeletion.error { throw error }
                               return AccountDeleted(status: "deleted", authUserDeleted: duringDeletion.authUserDeleted)
                           },
                           postAppleAuthorization: { _ in })
        api.now = { clock.now() }
        env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: api, demoAPI: api, auth: auth,
                             persistence: persistence, clock: clock, notifier: MockNotifier(), flags: StaticFlags([:]),
                             connectivity: .preview(online: true), defaults: defaults, demoOverride: demo ? nil : false)
        env.reads.random = { $0.lowerBound }
        state = AppState(env: env)
        env.uploader.random = { $0.lowerBound }
        env.uploader.gate = { _ in nil }
        if bindHooks { state.bindAccountHooks(auth, apiStatus: APIStatus()) }
        recorded = { [weak self] in self?.wipes.append($0) }
    }

    /// Lets the auth observation task run.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func signIn(_ id: UUID) async {
        client.signInSession = .preview(id: id)
        _ = await auth.logIn(email: "tim@example.com", password: "0123456789")
    }

    /// A row written straight into the store (as A4's finish or another account's session left it).
    @discardableResult
    func insert(_ account: String, revision: Int = 1, confirmed: Int = 0, deleted: Bool = false,
                phase: String = LocalActivity.savedPhase, chunks: Int = 0) -> UUID {
        let end = clock.now().addingTimeInterval(-3_600)
        let row = LocalActivity(account: account, sport: .running, origin: .manual, phase: phase,
                                start: end.addingTimeInterval(-1_800), end: end, movingSec: 1_800,
                                localRevision: revision, confirmedRevision: confirmed, createdAt: clock.now())
        if deleted { row.deletedAt = clock.now() }
        persistence.context.insert(row)
        for seq in 0..<chunks {
            persistence.context.insert(ActivityTrackChunk(activityID: row.id, account: account, seq: seq, kind: .profile,
                                                          data: Data([1]), count: 1, first: end, last: end))
        }
        persistence.save()
        return row.id
    }

    @discardableResult
    func insertNight(_ account: String, daysBack: Int, revision: Int = 1, confirmed: Int = 0) -> String {
        let wake = DayFormat.shift(clock.now(), days: -daysBack).addingTimeInterval(-3_600)
        let day = DayFormat.string(from: wake)
        persistence.context.insert(LocalManualSleep(day: day, account: account, bed: wake.addingTimeInterval(-8 * 3_600),
                                                    wake: wake, localRevision: revision, confirmedRevision: confirmed))
        persistence.save()
        return day
    }

    func rows() -> [LocalActivity] { (try? persistence.context.fetch(FetchDescriptor<LocalActivity>())) ?? [] }
    func nights() -> [LocalManualSleep] { (try? persistence.context.fetch(FetchDescriptor<LocalManualSleep>())) ?? [] }
    func chunks() -> [ActivityTrackChunk] { (try? persistence.context.fetch(FetchDescriptor<ActivityTrackChunk>())) ?? [] }
    func rows(of account: String) -> [LocalActivity] { rows().filter { $0.account == account } }
}

@Suite("Accounts: activities scoped, parked and purged (design.md §8.4)")
@MainActor
struct AccountScopeTests {
    @Test func everyReadIsScopedToTheSignedInAccount() async {
        let h = AccountHarness()
        let own = h.insert(AccountHarness.accountA)
        h.insert(AccountHarness.accountB)
        let night = h.insertNight(AccountHarness.accountA, daysBack: 0)
        h.insertNight(AccountHarness.accountB, daysBack: 1)
        #expect(h.env.activities.unconfirmed().map(\.id) == [own])
        #expect(h.env.activities.manualSleeps().map(\.day) == [night])
        #expect(h.env.uploader.pendingCount == 2)
        await h.auth.signOut(reason: .sessionExpired)
        #expect(h.env.activities.unconfirmed().isEmpty && h.env.activities.manualSleeps().isEmpty)
        #expect(h.env.activities.allSnapshots().isEmpty && h.env.uploader.pendingCount == 0)
    }

    @Test func expiryParksExactlyTheUnconfirmedRowsAndDeletesTheRest() async throws {
        let h = AccountHarness()
        let a = AccountHarness.accountA
        let pending = h.insert(a, revision: 2, confirmed: 1, chunks: 2)
        let confirmed = h.insert(a, revision: 1, confirmed: 1, chunks: 3)
        let deleting = h.insert(a, revision: 1, confirmed: 1, deleted: true)
        let recording = h.insert(a, revision: 0, phase: "recording", chunks: 2)
        let other = h.insert(AccountHarness.accountB, chunks: 1)
        let pendingNight = h.insertNight(a, daysBack: 0)
        h.insertNight(a, daysBack: 1, revision: 1, confirmed: 1)
        h.persistence.context.insert(CachedDay(day: "2026-10-18", date: h.clock.now()))
        h.persistence.save()

        await h.auth.rejectedAfterRefresh() // a final 401
        #expect(h.auth.state == .signedOut)
        #expect(h.wipes == [AuthService.Wipe(reason: .sessionExpired, account: a)])

        let kept = Set(h.rows().map(\.id))
        #expect(kept == [pending, deleting, recording])
        #expect(!kept.contains(confirmed) && !kept.contains(other))
        let allParked = h.rows().allSatisfy { $0.parkedAt == h.clock.now() && $0.account == a }
        #expect(allParked)
        #expect(Set(h.chunks().map(\.activityID)) == [pending, recording] && h.chunks().count == 4)
        #expect(h.nights().map(\.day) == [pendingNight] && h.nights().first?.parkedAt == h.clock.now())
        #expect((try? h.persistence.context.fetchCount(FetchDescriptor<CachedDay>())) == 0) // the rest as before
        // Signed out, nothing reads them.
        #expect(h.env.activities.snapshot(id: pending) == nil)
    }

    @Test func aUserSignOutDeletesEveryActivityRow() async {
        let h = AccountHarness()
        h.insert(AccountHarness.accountA, chunks: 1)
        h.insertNight(AccountHarness.accountA, daysBack: 0)
        await h.auth.signOut()
        #expect(h.wipes.map(\.parking) == [nil])
        #expect(h.rows().isEmpty && h.nights().isEmpty && h.chunks().isEmpty)
    }

    @Test func accountDeletionKeepsNothing() async {
        let h = AccountHarness()
        h.insert(AccountHarness.accountA)
        #expect(await h.auth.deleteAccount())
        #expect(h.wipes.map(\.reason) == [.accountDeleted(background: false)] && h.rows().isEmpty)
    }

    @Test func theSDKEndingTheSessionIsAnExpiry() async {
        let h = AccountHarness()
        h.insert(AccountHarness.accountA)
        await h.settle()
        h.client.emit(.signedOut, nil) // a revoked refresh token
        await h.settle()
        #expect(h.wipes.map(\.parking) == [AccountHarness.accountA])
        #expect(h.rows().count == 1)
    }

    @Test func accountBAfterAsExpiryPurgesBeforeTheFirstFlushAndRead() async throws {
        let h = AccountHarness()
        let a = AccountHarness.accountA
        let parked = h.insert(a, chunks: 2)
        h.insertNight(a, daysBack: 0)
        await h.auth.rejectedAfterRefresh()
        #expect(h.rows(of: a).count == 1) // parked, and `lastUserKey` is gone with the sign-out

        // What the store held when B's session became visible to the app.
        var seenAtChange: (account: String?, rowsOfA: Int, nightsOfA: Int)?
        let bound = h.auth.onAccountWillChange
        h.auth.onAccountWillChange = { [weak h] from, to, reason in
            bound?(from, to, reason)
            guard let h else { return }
            seenAtChange = (h.auth.accountID, h.rows(of: a).count, h.nights().filter { $0.account == a }.count)
        }
        await h.signIn(AccountHarness.b)
        #expect(h.auth.accountID == AccountHarness.accountB)
        let seen = try #require(seenAtChange)
        #expect(seen.account == nil) // the hook ran before B's session was published
        #expect(seen.rowsOfA == 0 && seen.nightsOfA == 0)
        #expect(h.chunks().isEmpty)
        // B's first flush and first My Day read find nothing of A's.
        await h.env.uploader.flush(userInitiated: true)
        #expect(h.api.calls.isEmpty)
        let input = MyDayInput.cached(day: h.clock.now(), state: h.state, store: h.persistence)
        #expect(input.local.isEmpty && input.localSleep == nil)
        #expect(h.env.activities.snapshot(id: parked) == nil)
    }

    @Test func theUploaderNeverSendsAnotherAccountsRowEvenWithThePurgeStubbed() async throws {
        let h = AccountHarness(bindHooks: false)
        let a = AccountHarness.accountA
        h.insert(a)
        h.insertNight(a, daysBack: 0)
        await h.auth.rejectedAfterRefresh()
        await h.signIn(AccountHarness.b)
        #expect(h.rows(of: a).count == 1) // no purge ran
        await h.env.uploader.flush(userInitiated: true)
        #expect(h.api.calls.isEmpty)
        #expect(MyDayInput.cached(day: h.clock.now(), state: h.state, store: h.persistence).local.isEmpty)
        // B's own row goes up, and only it.
        let end = h.clock.now().addingTimeInterval(-600)
        let own = try #require(h.env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900), end: end)))
        await h.env.uploader.flush(userInitiated: true)
        #expect(h.api.activitySource.puts.map(\.id) == [own.id])
        #expect(h.api.count("putManualSleep") == 0)
    }

    @Test func theSameAccountSigningInAgainUnparksAndUploads() async throws {
        let h = AccountHarness()
        let a = AccountHarness.accountA
        let parked = h.insert(a)
        let night = h.insertNight(a, daysBack: 0)
        await h.auth.rejectedAfterRefresh()
        await h.signIn(AccountHarness.a)
        #expect(h.rows().map(\.parkedAt) == [nil] && h.nights().map(\.parkedAt) == [nil])
        #expect(h.env.activities.snapshot(id: parked)?.needsUpload == true)
        await h.env.uploader.flush()
        #expect(h.api.activitySource.puts.map(\.id) == [parked])
        #expect(h.api.activitySource.sleepPuts[night] != nil)
        #expect(h.env.uploader.pendingCount == 0)
    }

    @Test func parkedRowsGoAfterThirtyDaysWithTheirChunks() async {
        let h = AccountHarness()
        let a = AccountHarness.accountA
        h.insert(a, chunks: 2)
        h.insertNight(a, daysBack: 0)
        await h.auth.rejectedAfterRefresh()
        h.clock.advance(by: .seconds(30 * 86_400)) // exactly 30 days: still kept
        #expect(h.env.activities.deleteExpiredParked() == 0)
        #expect(h.rows().count == 1 && h.nights().count == 1)
        h.clock.advance(by: .seconds(1))
        #expect(h.env.activities.deleteExpiredParked() == 2)
        #expect(h.rows().isEmpty && h.nights().isEmpty && h.chunks().isEmpty)
    }

    @Test func aSecondExpiryKeepsTheFirstParkingTime() async {
        let h = AccountHarness()
        let id = h.insert(AccountHarness.accountA)
        let first = h.clock.now()
        h.persistence.wipe(parkingActivitiesOf: AccountHarness.accountA, at: first)
        h.clock.advance(by: .seconds(86_400))
        h.persistence.wipe(parkingActivitiesOf: AccountHarness.accountA, at: h.clock.now())
        #expect(h.rows().first { $0.id == id }?.parkedAt == first)
    }

    @Test func anAnswerInFlightAtTheExpiryIsDroppedInsideTheWipe() async throws {
        let h = AccountHarness()
        let hold = RequestHold()
        h.api.activitySource.beforeWrite = { await hold.wait() }
        let end = h.clock.now().addingTimeInterval(-600)
        let row = try #require(h.env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900), end: end)))
        let flush = Task { await h.env.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        let before = h.env.uploader.generation.count
        await h.auth.rejectedAfterRefresh()
        // Moved by the hooks inside the sign-out itself: no app-level account-change handler runs in this test.
        #expect(h.env.uploader.generation.count > before)
        hold.release()
        await flush.value
        #expect(h.rows().first?.confirmedRevision == 0 && h.rows().first?.parkedAt != nil)
        #expect(h.rows().first?.id == row.id)
    }

    @Test func thePurgeTakesTheIncomingAccountNeverDemoData() async {
        // Demo data is on: the store reads as "demo", but A's own unsent rows survive A's own sign-in.
        let h = AccountHarness(demo: true)
        let a = AccountHarness.accountA
        h.insert(a)
        await h.auth.rejectedAfterRefresh()
        #expect(h.env.activities.account == ActivityStore.demoAccount)
        await h.signIn(AccountHarness.a)
        #expect(h.rows(of: a).count == 1 && h.rows(of: a).first?.parkedAt == nil)
        // Another account's sign-in purges them.
        await h.auth.signOut(reason: .sessionExpired)
        await h.signIn(AccountHarness.b)
        #expect(h.rows(of: a).isEmpty)
    }

    @Test func signOutsTellTheHookWhyAndSignInsDont() async {
        let h = AccountHarness()
        var changes: [(String?, String?, AuthService.SignOutReason?)] = []
        let bound = h.auth.onAccountWillChange
        h.auth.onAccountWillChange = { from, to, reason in
            bound?(from, to, reason)
            changes.append((from, to, reason))
        }
        await h.auth.signOut()
        await h.signIn(AccountHarness.b)
        await h.auth.rejectedAfterRefresh()
        #expect(changes.map(\.0) == [AccountHarness.accountA, nil, AccountHarness.accountB])
        #expect(changes.map(\.1) == [nil, AccountHarness.accountB, nil])
        #expect(changes.map(\.2) == [.user, nil, .sessionExpired])
    }
}

@Suite("Accounts: the A2 review (deletion, consent, launch, parked rows, export)")
@MainActor
struct AccountReviewTests {
    @Test func aRefreshFailureDuringDeletionStillDeletesEverything() async {
        let h = AccountHarness()
        let a = AccountHarness.accountA
        h.insert(a, chunks: 2)
        h.insertNight(a, daysBack: 0)
        // A concurrent final 401 while the platform deletes: the expiry path runs in the middle of the deletion. A
        // row written under the account after that (as a recording's checkpoint keeps its own account) goes too.
        h.duringDeletion.run = { [weak h] in
            await h?.auth.rejectedAfterRefresh()
            h?.insert(a, revision: 0, phase: "recording", chunks: 1)
        }
        #expect(await h.auth.deleteAccount())
        #expect(h.rows().isEmpty && h.nights().isEmpty && h.chunks().isEmpty)
        let nothingParked = h.wipes.allSatisfy { $0.parking == nil }
        #expect(nothingParked && !h.wipes.isEmpty)
        #expect(h.auth.signOutNotice == AuthService.SignOutReason.accountDeleted(background: false).notice)
        #expect(h.env.activities.parkedCount() == 0)
    }

    @Test func aDeletionStopsTheUploadAndDropsTheAnswerInFlight() async throws {
        let h = AccountHarness()
        let hold = RequestHold()
        h.api.activitySource.beforeWrite = { await hold.wait() }
        let end = h.clock.now().addingTimeInterval(-600)
        _ = try #require(h.env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900), end: end)))
        let flush = Task { await h.env.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        let count = h.env.uploader.generation.count
        var seenDuring: Int?
        h.duringDeletion.run = { [weak h] in seenDuring = h?.env.uploader.generation.count }
        #expect(await h.auth.deleteAccount())
        #expect((seenDuring ?? 0) > count) // stopped before the platform was asked
        hold.release()
        await flush.value
        #expect(h.rows().isEmpty)
    }

    @Test func theSameAccountsUnparkSendsNothingBeforeConsent() async {
        let h = AccountHarness()
        var gate: UploadGate? = .gate(.consentRequired)
        h.env.uploader.gate = { _ in gate }
        h.insert(AccountHarness.accountA)
        await h.auth.rejectedAfterRefresh()
        await h.signIn(AccountHarness.a)
        #expect(h.rows().first?.parkedAt == nil)
        await h.env.uploader.flush()
        #expect(h.api.calls.isEmpty)
        gate = nil
        await h.env.uploader.flush()
        #expect(h.api.activitySource.puts.count == 1)
    }

    @Test func signedInAtLaunchTheStoreIsPutRightOnce() {
        let h = AccountHarness(bindHooks: false)
        let a = AccountHarness.accountA
        let other = h.insert(AccountHarness.accountB)
        let parked = h.insert(a)
        h.persistence.wipe(parkingActivitiesOf: a, at: h.clock.now()) // parked by an expiry before a kill
        #expect(h.rows(of: a).first?.parkedAt != nil)
        h.state.bindAccountHooks(h.auth, apiStatus: APIStatus()) // the launch
        let otherLeft = h.rows().contains { $0.id == other }
        #expect(!otherLeft)
        #expect(h.rows().map(\.id) == [parked] && h.rows().first?.parkedAt == nil)
    }

    @Test func parkedRowsCanBeCountedAndDeletedWhileSignedOut() async {
        let h = AccountHarness()
        let a = AccountHarness.accountA
        h.insert(a, chunks: 2)
        h.insert(a, revision: 1, confirmed: 1)
        h.insertNight(a, daysBack: 0)
        #expect(h.env.activities.parkedCount() == 0)
        await h.auth.rejectedAfterRefresh()
        #expect(h.env.activities.parkedCount() == 2) // the unconfirmed row and the night
        #expect(h.env.activities.purgeParked() == 2)
        #expect(h.env.activities.parkedCount() == 0)
        #expect(h.rows().isEmpty && h.nights().isEmpty && h.chunks().isEmpty)
    }

    @Test func everyAccountChangeIsCountedSoABAIsNotTheSameAccount() async {
        let h = AccountHarness()
        let start = h.auth.accountChanges
        await h.auth.signOut()
        await h.signIn(AccountHarness.b)
        await h.auth.signOut()
        await h.signIn(AccountHarness.a)
        #expect(h.auth.accountID == AccountHarness.accountA)
        #expect(h.auth.accountChanges == start + 4)
    }

    @Test func theWipeForgetsThePreviousAccountsExport() async {
        let h = AccountHarness()
        var forgotten = 0
        h.state.onForgetAccountState = { forgotten += 1 }
        await h.auth.signOut()
        #expect(forgotten >= 1)
    }

    @Test func theExportReadsThePhoneRowsOfTheAccountItStartedFor() async throws {
        // No purge on B's sign-in here, so both accounts' rows stay in the store.
        let h = AccountHarness(bindHooks: false)
        let a = AccountHarness.accountA
        let mine = h.insert(a)
        h.insert(AccountHarness.accountB)
        // While the platform's list is read, A's session expires and B signs in.
        h.api.activitySource.beforeList = { @MainActor [weak h] in
            guard let h else { return }
            h.api.activitySource.beforeList = nil
            await h.auth.signOut(reason: .sessionExpired)
            await h.signIn(AccountHarness.b)
        }
        let archive = try await DataExport.archive(source: h.api, train: h.api, activities: h.api,
                                                   onPhone: h.env.activities, now: h.clock.now())
        #expect(h.auth.accountID == AccountHarness.accountB)
        #expect(archive.unconfirmedActivities.map(\.activity.id) == [mine]) // A's, never B's
    }
}

@Suite("Accounts: the A2 privacy re-check")
@MainActor
struct AccountRecheckTests {
    @Test func aDeletionThatEndsAfterAnotherAccountSignedInLeavesThatAccountAlone() async throws {
        let h = AccountHarness()
        h.insert(AccountHarness.accountA)
        var deletingForB: Bool?
        // A's session ends during DELETE /v1/me (its 503 retries take up to about 90 s), and B signs in meanwhile.
        h.duringDeletion.run = { [weak h] in
            guard let h else { return }
            await h.auth.rejectedAfterRefresh()
            await h.signIn(AccountHarness.b)
            h.insert(AccountHarness.accountB)
            h.insertNight(AccountHarness.accountB, daysBack: 0)
            deletingForB = h.auth.isDeletingAccount
        }
        let wipesBefore = h.wipes.count
        #expect(await h.auth.deleteAccount())
        #expect(h.auth.accountID == AccountHarness.accountB && h.auth.isSignedIn)
        #expect(h.rows(of: AccountHarness.accountB).count == 1 && h.nights().count == 1)
        #expect(h.rows(of: AccountHarness.accountA).isEmpty)
        #expect(h.auth.signOutNotice == nil)
        #expect(deletingForB == false) // B's uploads weren't held, B's end wouldn't count as A's deletion
        #expect(h.wipes.count == wipesBefore + 1) // A's session ending, and nothing after B signed in
    }

    @Test func anotherAccountThatCameAndWentDuringTheDeletionGetsNoNoticeAndKeepsWhatItParked() async {
        let h = AccountHarness()
        h.insert(AccountHarness.accountA)
        // A's session ends; B signs in, adds a row, and its own session expires, all before DELETE /v1/me returns.
        h.duringDeletion.run = { [weak h] in
            guard let h else { return }
            await h.auth.rejectedAfterRefresh()
            await h.signIn(AccountHarness.b)
            h.insert(AccountHarness.accountB)
            await h.auth.rejectedAfterRefresh()
        }
        #expect(await h.auth.deleteAccount())
        #expect(!h.auth.isSignedIn)
        #expect(h.auth.signOutNotice == AuthService.SignOutReason.sessionExpired.notice) // B's own, not A's deletion
        #expect(h.rows(of: AccountHarness.accountB).count == 1 && h.rows(of: AccountHarness.accountB).first?.parkedAt != nil)
        #expect(h.rows(of: AccountHarness.accountA).isEmpty)
    }

    @Test func aDeletionCutShortByAnAccountSwitchShowsNoError() async {
        let h = AccountHarness()
        h.duringDeletion.run = { [weak h] in
            guard let h else { return }
            await h.auth.rejectedAfterRefresh()
            await h.signIn(AccountHarness.b)
        }
        h.duringDeletion.error = CancellationError()
        #expect(await h.auth.deleteAccount() == false)
        #expect(h.auth.errorMessage == nil && h.auth.errorDetails == nil)
        #expect(h.auth.accountID == AccountHarness.accountB)
    }

    @Test func aDeletionThatFailsForTheSameAccountSaysSo() async {
        let h = AccountHarness()
        h.duringDeletion.error = APIError.http(503, "busy", requestID: "req-503")
        #expect(await h.auth.deleteAccount() == false)
        #expect(h.auth.errorMessage != nil && h.auth.errorDetails?.contains("req-503") == true)
        #expect(h.auth.accountID == AccountHarness.accountA)
    }

    @Test func aDeletionKeepsItsOwnBackgroundFlag() async {
        let h = AccountHarness()
        h.duringDeletion.authUserDeleted = false // Supabase finishes in the background
        var reasons: [AuthService.SignOutReason?] = []
        let bound = h.auth.onAccountWillChange
        h.auth.onAccountWillChange = { from, to, reason in
            bound?(from, to, reason)
            reasons.append(reason)
        }
        #expect(await h.auth.deleteAccount())
        #expect(reasons == [.accountDeleted(background: true)])
        #expect(h.wipes.last?.reason == .accountDeleted(background: true))
    }

    @Test func parkedUntilIsTheFirstParkingPlusThirtyDays() async {
        let h = AccountHarness()
        #expect(h.env.activities.parkedUntil() == nil)
        h.insert(AccountHarness.accountA)
        let parkedAt = h.clock.now()
        await h.auth.rejectedAfterRefresh()
        #expect(h.env.activities.parkedUntil() == parkedAt.addingTimeInterval(30 * 86_400))
        // A night parked later doesn't move the date.
        h.clock.advance(by: .seconds(86_400))
        h.persistence.context.insert(LocalManualSleep(day: "2026-10-18", account: AccountHarness.accountA,
                                                      bed: parkedAt.addingTimeInterval(-36_000),
                                                      wake: parkedAt.addingTimeInterval(-7_200)))
        h.persistence.save()
        h.persistence.wipe(parkingActivitiesOf: AccountHarness.accountA, at: h.clock.now())
        #expect(h.env.activities.parkedUntil() == parkedAt.addingTimeInterval(30 * 86_400))
        h.env.activities.purgeParked()
        #expect(h.env.activities.parkedUntil() == nil)
    }

    @Test func aLaunchWithNothingToPutRightWritesNothing() {
        let h = AccountHarness(bindHooks: false)
        h.insert(AccountHarness.accountA) // A's own, not parked
        let revision = h.env.activities.revision
        h.state.bindAccountHooks(h.auth, apiStatus: APIStatus())
        #expect(h.env.activities.revision == revision)
        #expect(!h.persistence.context.hasChanges)
    }
}

/// `OnboardingCoordinator.uploadGate` for activity uploads (privacy re-check A-1, then ADR 0008): the uploader waits
/// for a fresh policy the consent matches. The rule itself is table-tested in `ConsentGateTests`.
@Suite("Onboarding: the upload gate")
@MainActor
struct UploadGateTests {
    @Test func aConsentToAnOlderPolicyWaitsUntilThePolicyIsKnownAndMatches() async throws {
        let clock = TestClock()
        let api = MockPlatformAPI()
        // A consent to an older policy than the one in force; neither `GET /v1/config` nor `GET /v1/me/sync` has
        // answered yet, so this phone knows the account but not the policy.
        api.accountConsent = Consent(policyVersion: "2026-10-01", grantedAt: clock.now())
        api.faults["config"] = .init(.status(404, retryAfter: nil))
        api.faults["syncStatus"] = .init(.status(404, retryAfter: nil))
        let env = AppEnvironment.test(api: api, clock: clock)
        let state = AppState(env: env)
        let onboarding = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        env.uploader.gate = { onboarding.uploadGate(for: .activities, write: $0) }
        await onboarding.check(force: true)
        #expect(onboarding.user != nil && onboarding.policyVersion == nil)
        #expect(onboarding.uploadGate(for: .activities) == .policyUnknown)
        let end = clock.now().addingTimeInterval(-3_600)
        let id = try #require(env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900),
                                                                         end: end))?.id)
        await env.uploader.flush(userInitiated: true) // asks the config once more: still refused
        #expect(api.count("putActivity") == 0 && env.uploader.state(of: id) == .pending(.gated))
        // The config arrives with the newer policy: still held (the consent step asks again).
        api.faults["config"] = nil
        api.faults["syncStatus"] = nil
        api.remoteConfig = Self.config(policy: "2026-11-01")
        await onboarding.check(force: true)
        #expect(onboarding.uploadGate(for: .activities) == .gate(.consentRequired))
        await env.uploader.flush()
        #expect(api.count("putActivity") == 0)
        // It matches the consent: the queue goes.
        api.remoteConfig = Self.config(policy: "2026-10-01")
        await onboarding.check(force: true)
        #expect(onboarding.uploadGate(for: .activities) == nil)
        await env.uploader.flush()
        #expect(env.uploader.state(of: id) == .confirmed)
    }

    /// A cold start that never ran `check()` (a background wake): the account's cached user and its consent record
    /// are all there is. `recorded`: a policy answer stored for `account` (nil: the signed-in one) `age` ago.
    private static func coldStart(consent: String, recorded: (account: String?, policy: String, age: TimeInterval)?,
                                  online: Bool = true) async throws
        -> (AppEnvironment, OnboardingCoordinator, UUID, MockPlatformAPI) {
        let clock = TestClock()
        let api = MockPlatformAPI()
        api.accountConsent = Consent(policyVersion: consent, grantedAt: clock.now())
        let env = AppEnvironment.test(api: api, clock: clock, online: online)
        let state = AppState(env: env)
        state.user = try await api.me() // the cached account
        if let recorded {
            let record = ConsentState.Record(policyVersion: recorded.policy, policyURL: nil,
                                             answeredAt: clock.now().addingTimeInterval(-recorded.age))
            let account = recorded.account ?? env.auth.accountID ?? "-"
            env.persistence.saveDocument(record, key: ConsentState.key(account), at: clock.now())
        }
        let onboarding = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        env.uploader.gate = { onboarding.uploadGate(for: .activities, write: $0) }
        let end = clock.now().addingTimeInterval(-3_600)
        let id = try #require(env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900),
                                                                         end: end))?.id)
        return (env, onboarding, id, api)
    }

    @Test func aColdStartWithAFreshMatchingRecordUploadsWithoutAskingTheConfig() async throws {
        let (env, onboarding, id, api) = try await Self.coldStart(consent: "2026-10-20", recorded: (nil, "2026-10-20", 60))
        #expect(onboarding.policyVersion == "2026-10-20" && onboarding.uploadGate(for: .activities) == nil)
        await env.uploader.flush()
        #expect(env.uploader.state(of: id) == .confirmed && api.count("config") == 0)
    }

    @Test func aColdStartWithAStaleRecordAsksOnceThenUploads() async throws {
        let (env, onboarding, id, api) = try await Self.coldStart(consent: MockData.policyVersion,
                                                                   recorded: (nil, MockData.policyVersion, 6 * 3_600))
        #expect(onboarding.uploadGate(for: .activities) == .policyUnknown)
        await env.uploader.flush()
        #expect(api.count("config") == 1 && env.uploader.state(of: id) == .confirmed)
    }

    @Test func aColdStartOfflineWithoutARecordIsHeldAndAsksNothing() async throws {
        let (env, onboarding, id, api) = try await Self.coldStart(consent: "2026-10-20", recorded: nil, online: false)
        #expect(onboarding.uploadGate(for: .activities) == .policyUnknown)
        await env.uploader.flush(userInitiated: true)
        #expect(env.uploader.state(of: id) == .pending(.offline) && api.calls == ["me"]) // only the setup's read
    }

    @Test func aColdStartWithARecordTheConsentDoesntMatchIsHeld() async throws {
        let (env, onboarding, id, api) = try await Self.coldStart(consent: "2026-10-01", recorded: (nil, "2026-10-20", 60))
        #expect(onboarding.uploadGate(for: .activities) == .gate(.consentRequired))
        await env.uploader.flush(userInitiated: true)
        #expect(env.uploader.state(of: id) == .pending(.gated) && api.count("config") == 0)
    }

    @Test func anotherAccountsRecordIsNeverUsed() async throws {
        let (_, onboarding, _, _) = try await Self.coldStart(consent: "2026-10-20",
                                                              recorded: ("someone-else", "2026-10-20", 60), online: false)
        #expect(onboarding.policyVersion == nil && onboarding.uploadGate(for: .activities) == .policyUnknown)
    }

    @Test func anOfflineStartAsksForThePolicyOnReconnectThenUploads() async throws {
        let (env, onboarding, id, api) = try await Self.coldStart(consent: MockData.policyVersion, recorded: nil,
                                                                   online: false)
        await onboarding.check() // offline: no answer
        #expect(onboarding.uploadGate(for: .activities) == .policyUnknown)
        #expect(env.uploader.state(of: id) == .pending(.offline))
        env.connectivityMonitor.update(true) // the uploader's own reconnect: it asks the config, then sends
        #expect(await eventually { env.uploader.state(of: id) == .confirmed })
        #expect(api.count("config") == 1 && api.count("me") == 1) // the setup's read only: no forced check
    }

    @Test func demoDataHasNoUploadGate() {
        let onboarding = OnboardingCoordinator(state: AppState.preview(), apiStatus: APIStatus()) {}
        #expect(onboarding.uploadGate(for: .activities) == nil)
    }

    private static func config(policy: String) -> RemoteConfig {
        RemoteConfig(flags: [:], evaluatedAt: .now, ttlSec: 21_600, privacyPolicyVersion: policy,
                     privacyPolicyUrl: "https://ryftapp.de/privacy")
    }
}

@Suite("Accounts: the sign-out confirmation's numbers")
@MainActor
struct SignOutConfirmationTests {
    @Test func theCountIsTheAccountsUnconfirmedRowsInTheAccountsStore() {
        let h = AccountHarness()
        let a = AccountHarness.accountA
        h.insert(a)                                   // pending
        h.insert(a, revision: 1, confirmed: 1)        // confirmed: not counted
        h.insert(a, revision: 0, phase: "recording")  // not saved: counted
        h.insertNight(a, daysBack: 0)                 // pending night
        h.insert(AccountHarness.accountB)             // someone else's
        #expect(h.env.activities.unconfirmedCount(ofAccount: a) == 3)
        #expect(h.env.activities.unconfirmedCount(ofAccount: nil) == 0)
    }
}

// MARK: - T3 re-review: the widget after a sign-out

@Suite("Accounts: the widget keeps nothing of the account that left")
@MainActor
struct AccountWidgetWipeTests {
    /// The widget's publish reads the store plus two values the store doesn't hold: `GET /v1/me/sync`'s word about
    /// today and tonight's bedtime. A publish after the wipe (the tracker watch fires on sign-out, a background 401)
    /// must carry neither of the old account's.
    @Test func aSignOutLeavesNoStatusOrBedtimeForTheNextPublish() async throws {
        let h = AccountHarness()
        let now = h.clock.now()
        let key = DayFormat.string(from: now)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("readiness-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        h.state.repository.widgetFile = file
        h.state.repository.reloadWidget = {}
        func written() -> ReadinessSnapshot? {
            (try? Data(contentsOf: file)).flatMap { try? ReadinessSnapshot.decoder.decode(ReadinessSnapshot.self, from: $0) }
        }
        // Account A: yesterday scored, today's night being scored, a bedtime tonight.
        h.state.history = [DailyScore(day: DayFormat.string(from: DayFormat.shift(now, days: -1)), readiness: 76, recovery: 74,
                                      baselineDays: 30, computedAt: now.addingTimeInterval(-86_400), scoringState: .scored)]
        h.state.syncStatus = SyncStatus(gate: nil, lastSyncAt: now, lastSyncDevice: nil, latest: [:],
                                        today: TodayState(day: key, state: .pending, scoredAt: nil, modelVersion: "x"),
                                        pendingDays: [key], expectedWithinSec: 20, resyncRequestedAt: nil)
        h.state.repository.tonightBedtime = now.addingTimeInterval(3 * 3_600)
        h.state.repository.publishWidget()
        let before = try #require(written())
        #expect(before.kind == .pending && before.bedtime != nil && before.previousReadiness == 76)

        await h.auth.signOut(reason: .user)
        await h.settle()
        #expect(h.state.syncStatus == nil && h.state.repository.todayStatus == nil)
        #expect(h.state.repository.tonightBedtime == nil)
        // The next publish (whatever starts it) has nothing of A: no status, no bedtime, no readiness.
        h.state.repository.publishWidget()
        let after = written()
        #expect(after?.bedtime == nil && after?.kind != .pending && after?.previousReadiness == nil, "\(String(describing: after))")
    }
}
