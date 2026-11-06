import Foundation
import SwiftData
import Testing
@testable import Ryft

// No session is published over an owed wipe, except its own account coming back to its own rows (design.md §4, At
// sign-in). Synthetic values only.

private typealias Wipe = AuthService.Wipe

@MainActor
struct SignInHoldTests {
    private let a = WipeValues.accountA.uuidString, b = WipeValues.accountB.uuidString
    private let accountB = WipeValues.accountB

    /// A's sign-out, refused: the debt B runs into.
    private func refused(_ ending: AuthService.SignOutReason = .user) async throws -> WipingAuth {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        try rig.disk.refuseDeletes()
        await rig.end(ending)
        #expect(rig.ledgerOnDisk?.wipe.account == a)
        return rig
    }

    /// A debt no pass of this process has refused: signed out, a new launch, and an entry that reads late. A session's
    /// rows are in the store.
    private func lateDebt(_ reason: AuthService.SignOutReason = .user) async throws -> WipingAuth {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        await rig.end(.user)
        rig.relaunch(signedInAs: nil)
        await rig.settle()
        rig.disk.session(checked: true)
        WipeLedger(file: rig.ledgerFile).begin(Wipe(reason: reason, account: a), at: rig.clock.now())
        return rig
    }

    private func expectHeld(_ rig: WipingAuth, for stored: UUID) {
        #expect(rig.auth.accountID == nil)
        #expect(rig.auth.session == nil && rig.auth.user == nil)
        #expect(rig.auth.state == .signedOut)
        #expect(rig.auth.phase == .signedOut)
        #expect(rig.auth.errorMessage == AuthMessage.signInHeld)
        #expect(rig.client.currentSession?.user.id == stored, "the next launch publishes it without a login")
    }

    private func logIn(_ rig: WipingAuth, as id: UUID) async -> Bool {
        rig.client.signInSession = .preview(id: id)
        let ok = await rig.auth.logIn(email: "synthetic@example.com", password: "0123456789")
        await rig.settle()
        return ok
    }

    /// Records what the account hooks heard.
    private func watchHooks(_ rig: WipingAuth) -> Hooks {
        let hooks = Hooks()
        rig.auth.onAccountWillChange = { from, to, reason in hooks.changes.append(.init(from: from, to: to, reason: reason)) }
        return hooks
    }

    @MainActor
    private final class Hooks {
        struct Change: Equatable {
            let from: String?, to: String?, reason: AuthService.SignOutReason?
        }
        var changes: [Change] = []
    }

    /// An unsent row of `account`, saved through a context of its own: a refused wipe's deletes stay pending in the
    /// store's.
    @discardableResult
    private func unsent(of account: String, in rig: WipingAuth) throws -> UUID {
        let row = LocalActivity(account: account, sport: .running, origin: .manual, start: WipeValues.earlier,
                                end: WipeValues.now, movingSec: 1_800, localRevision: 2, confirmedRevision: 1,
                                createdAt: WipeValues.earlier)
        let context = ModelContext(rig.disk.store.container)
        context.insert(row)
        try context.save()
        return row.id
    }

    private func activities(_ rig: WipingAuth) throws -> Set<UUID> {
        Set(try ModelContext(rig.disk.store.container).fetch(FetchDescriptor<LocalActivity>()).map(\.id))
    }

    // MARK: the hold

    @Test func aSignInOverARefusedWipeIsHeld() async throws {
        let rig = try await refused()
        let changes = rig.auth.accountChanges
        let hooks = watchHooks(rig)

        #expect(await logIn(rig, as: accountB) == false)

        expectHeld(rig, for: accountB)
        #expect(rig.auth.accountChanges == changes)
        #expect(hooks.changes.isEmpty)
        #expect(rig.lastUser == a, "the store still holds A's rows")
        #expect(rig.ledgerOnDisk?.wipe.account == a)
    }

    @Test func aHeldSignUpReportsNoOutcome() async throws {
        let rig = try await refused()
        rig.client.signInSession = .preview(id: accountB)

        #expect(await rig.auth.signUp(name: "Synthetic", email: "synthetic@example.com", password: "0123456789") == nil)

        expectHeld(rig, for: accountB)
    }

    /// The link was ours, and it signs nobody in: no new-password screen for an account that isn't here.
    @Test func aHeldLinkShowsTheHold() async throws {
        let rig = try await refused()
        rig.client.signInSession = .preview(id: accountB)

        let url = try #require(URL(string: "ryft://auth/callback?code=synthetic&type=recovery"))
        #expect(await rig.auth.handle(url))

        expectHeld(rig, for: accountB)
        #expect(rig.auth.needsNewPassword == false)
    }

    /// The link is spent, so the launch that lets its account in asks for the new password, once.
    @Test(arguments: [("ryft://auth/callback?code=synthetic&type=recovery", false, true),
                      ("ryft://auth/callback?code=synthetic", true, true),
                      ("ryft://auth/callback?code=synthetic", false, false)])
    func aHeldRecoveryLinkAsksAtTheLaunchThatPublishes(_ link: (url: String, requested: Bool, asks: Bool)) async throws {
        let rig = try await refused()
        if link.requested { await rig.auth.sendPasswordReset(email: "synthetic@example.com") }
        rig.client.signInSession = .preview(id: accountB)
        #expect(await rig.auth.handle(try #require(URL(string: link.url))))
        #expect(rig.auth.needsNewPassword == false)

        rig.relaunch(signedInAs: accountB)
        #expect(rig.auth.accountID == b)
        #expect(rig.auth.needsNewPassword == link.asks)

        rig.relaunch(signedInAs: accountB)
        #expect(rig.auth.needsNewPassword == false)
    }

    /// The request alone isn't a link: this account just remembered its password.
    @Test func aResetRequestWithNoLinkAsksNothingAtALaterLaunch() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        await rig.end(.user)
        await rig.auth.sendPasswordReset(email: "synthetic@example.com")
        #expect(await logIn(rig, as: accountB))

        rig.relaunch(signedInAs: accountB)

        #expect(rig.auth.accountID == b)
        #expect(rig.auth.needsNewPassword == false)
    }

    /// The held session went away, so the link's question is over: that account logging in later isn't asked.
    @Test(arguments: [true, false])
    func aHeldRecoveryLinkEndsWithItsSession(_ byEvent: Bool) async throws {
        let rig = try await refused()
        rig.client.signInSession = .preview(id: accountB)
        #expect(await rig.auth.handle(try #require(URL(string: "ryft://auth/callback?code=synthetic&type=recovery"))))

        if byEvent {
            rig.client.emit(.signedOut, nil)
            await rig.settle()
        } else {
            await rig.auth.signOut()
        }
        rig.relaunch(signedInAs: nil)
        await rig.settle()
        #expect(await logIn(rig, as: accountB))

        #expect(rig.auth.needsNewPassword == false)
    }

    /// Held twice, the session stays stored throughout, and its launch still asks.
    @Test func aHeldRecoveryLinkOutlivesALaunchThatHolds() async throws {
        let rig = try await refused()
        rig.client.signInSession = .preview(id: accountB)
        #expect(await rig.auth.handle(try #require(URL(string: "ryft://auth/callback?code=synthetic&type=recovery"))))
        rig.wipesAnswer = false
        rig.relaunch(signedInAs: accountB)
        expectHeld(rig, for: accountB)

        rig.wipesAnswer = nil
        rig.relaunch(signedInAs: accountB)

        #expect(rig.auth.accountID == b)
        #expect(rig.auth.needsNewPassword)
    }

    /// The link was for the account that's held: another one coming in isn't asked, and the link's turn is over.
    @Test func aHeldRecoveryLinkIsntAnotherAccounts() async throws {
        let rig = try await refused()
        rig.client.signInSession = .preview(id: accountB)
        #expect(await rig.auth.handle(try #require(URL(string: "ryft://auth/callback?code=synthetic&type=recovery"))))

        #expect(await logIn(rig, as: WipeValues.accountA))
        #expect(rig.auth.needsNewPassword == false)

        rig.relaunch(signedInAs: accountB)
        #expect(rig.auth.needsNewPassword == false)
    }

    /// A link that isn't held asks at once, and leaves no request behind to misread the next one.
    @Test func aRecoveryLinkThatIsntHeldAsksAtOnce() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        await rig.end(.user)
        await rig.auth.sendPasswordReset(email: "synthetic@example.com")
        rig.client.signInSession = .preview(id: accountB)
        #expect(await rig.auth.handle(try #require(URL(string: "ryft://auth/callback?code=synthetic"))))
        #expect(rig.auth.accountID == b)
        #expect(rig.auth.needsNewPassword)
        rig.auth.needsNewPassword = false

        #expect(await rig.auth.handle(try #require(URL(string: "ryft://auth/callback?code=synthetic"))))
        #expect(rig.auth.needsNewPassword == false)
    }

    /// Nothing runs under a held account, this call included.
    @Test func aHeldAppleSignInSendsNothing() async throws {
        let rig = try await refused()
        rig.client.signInSession = .preview(id: accountB)

        await rig.auth.signInWithApple(idToken: "synthetic", nonce: "synthetic", fullName: nil, authorizationCode: "synthetic")

        expectHeld(rig, for: accountB)
        #expect(rig.appleCodes.isEmpty)
    }

    /// The control for the one above.
    @Test func anAppleSignInWithNoDebtSendsItsCode() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        await rig.end(.user)
        rig.client.signInSession = .preview(id: accountB)

        await rig.auth.signInWithApple(idToken: "synthetic", nonce: "synthetic", fullName: nil, authorizationCode: "synthetic")

        #expect(rig.auth.accountID == b)
        #expect(rig.appleCodes == ["synthetic"])
    }

    /// The tokens are in the SDK, and none comes out. Every upload asks here, so a nil-owner op of A's that `belongs` to
    /// the nil owner stays queued, and no row of A's can be bound to B.
    @Test func aHeldAccountGetsNoToken() async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: accountB) == false)

        await #expect(throws: APIError.self) { try await rig.auth.accessToken() }
        await #expect(throws: APIError.self) { try await rig.auth.refreshedAccessToken() }
        #expect(rig.auth.phase == .signedOut)
        #expect(rig.client.refreshCount == 0)
    }

    @Test func theNextLaunchPublishesAHeldAccount() async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: accountB) == false)

        rig.relaunch(signedInAs: accountB)

        #expect(rig.auth.accountID == b)
        #expect(rig.auth.errorMessage == nil)
        #expect(rig.lastUser == b)
        #expect(rig.ledgerOnDisk == nil)
        try rig.disk.expectNothingLeft()
    }

    /// A deep link signing B in over a published A.
    @Test func aHeldSignInEndsThePublishedAccount() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        try rig.disk.refuseDeletes()
        await rig.settle()
        rig.auth.needsNewPassword = true
        let changes = rig.auth.accountChanges
        let hooks = watchHooks(rig)

        #expect(await logIn(rig, as: accountB) == false)

        expectHeld(rig, for: accountB)
        #expect(rig.auth.needsNewPassword == false)
        #expect(rig.auth.accountChanges == changes + 1)
        #expect(hooks.changes == [.init(from: a, to: nil, reason: nil)])
        #expect(rig.ledgerOnDisk?.wipe.account == a)
        #expect(rig.ledgerOnDisk?.wipe.reason == nil)
        #expect(rig.wipes.allSatisfy { $0.reason == nil && $0.account == a }, "its session's end is no wipe of its own")
    }

    /// Review 2's sequence: A fails, B fails, a healthy launch, and B signs in.
    @Test func noRowOfASurvivesTheRefusalsAndARelaunch() async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: accountB) == false)

        try rig.disk.allowDeletes()
        rig.relaunch(signedInAs: nil)
        #expect(await logIn(rig, as: accountB))

        #expect(rig.auth.accountID == b)
        try rig.disk.expectNothingLeft()
    }

    /// Once a pass was refused, nothing in this process tries again, however healthy the store looks by now: only the
    /// next launch can prove the wipe.
    @Test func aRefreshWhileHeldPublishesNothingUntilTheNextLaunch() async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: accountB) == false)
        let changes = rig.auth.accountChanges, wipes = rig.wipes.count

        rig.client.emit(.tokenRefreshed, .preview(id: accountB))
        await rig.settle()
        expectHeld(rig, for: accountB)

        try rig.disk.allowDeletes()
        rig.client.emit(.tokenRefreshed, .preview(id: accountB))
        await rig.settle()

        expectHeld(rig, for: accountB)
        #expect(rig.auth.accountChanges == changes)
        #expect(rig.wipes.count == wipes)
        #expect(rig.ledgerOnDisk != nil)

        rig.relaunch(signedInAs: accountB)
        #expect(rig.auth.accountID == b)
        #expect(rig.lastUser == b)
        #expect(rig.ledgerOnDisk == nil)
        try rig.disk.expectNothingLeft()
    }

    /// Why: the refused save leaves an inserted row in the context, the next pass's batch delete doesn't see it, and that
    /// pass's save answers true and writes it. The debt has to outlive that answer.
    @Test func aTruePassAfterARefusalDoesntEndTheDebt() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        try rig.disk.refuseDeletes()
        WipedTable.cachedDay.insertRow(into: rig.disk.store.context)
        await rig.end(.user)
        #expect(rig.answers == [false])
        #expect(try rig.disk.inFile[.cachedDay] == 0)
        try rig.disk.allowDeletes()

        #expect(await logIn(rig, as: WipeValues.accountA))

        #expect(rig.answers == [false, true])
        #expect(try rig.disk.inFile[.cachedDay] == 1, "the row a true wipe left")
        #expect(rig.ledgerOnDisk != nil)

        await rig.end(.user)
        #expect(rig.answers == [false, true, true])
        #expect(rig.ledgerOnDisk != nil)
        #expect(await rig.firstFrame() == false)
        #expect(await logIn(rig, as: accountB) == false)
        #expect(rig.answers.count == 3)
        #expect(rig.auth.accountID == nil)

        rig.relaunch(signedInAs: accountB)
        #expect(rig.auth.accountID == b)
        #expect(try rig.disk.inFile[.cachedDay] == 0)
    }

    /// A later sign-in is held the same way, with no attempt.
    @Test(arguments: [WipeValues.accountB, WipeValues.accountB2])
    func aSignInAfterARefusalMakesNoAttempt(_ id: UUID) async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: accountB) == false)
        let wipes = rig.wipes.count
        try rig.disk.allowDeletes()

        #expect(await logIn(rig, as: id) == false)

        expectHeld(rig, for: id)
        #expect(rig.wipes.count == wipes)
    }

    /// No refusal in this process, and nobody stored at the end: the hold's over when the debt is.
    @Test func theHoldEndsWithTheDebtWhenNobodyIsStored() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.relaunch(signedInAs: nil)
        WipeLedger(file: rig.ledgerFile).begin(Wipe(reason: .user, account: a), at: rig.clock.now())
        rig.client.unlock(.preview(id: WipeValues.accountA))
        await rig.settle()
        #expect(rig.auth.errorMessage == AuthMessage.signInHeld)

        rig.client.emit(.signedOut, nil)
        await rig.settle()
        #expect(rig.auth.errorMessage == AuthMessage.signInHeld, "the debt's still there")

        #expect(await rig.firstFrame())
        #expect(rig.ledgerOnDisk == nil)
        #expect(rig.auth.errorMessage == nil)
    }

    /// A stored session is what the hold is for: that one still comes in at the next launch, so the message stands.
    @Test func theHoldOutlivesTheDebtWhileAccountIsStored() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        WipeLedger(file: rig.ledgerFile).begin(Wipe(reason: .user, account: a), at: rig.clock.now())
        let hold = Hold()
        rig.relaunch(signedInAs: WipeValues.accountA) { await hold.wait() }
        let client = rig.client
        #expect(await eventually { client.signOutCount == 1 })
        #expect(await logIn(rig, as: accountB) == false)
        client.onSignOutLeavesTheSession = true

        hold.open()

        #expect(await eventually { rig.ledgerOnDisk == nil })
        #expect(rig.auth.errorMessage == AuthMessage.signInHeld)
        rig.relaunch(signedInAs: accountB)
        #expect(rig.auth.accountID == b)
    }

    /// The hold outlives Welcome's `onAppear`, and a failure of its own shows until the next screen does.
    @Test func theMessageOutlivesAScreenAppearing() async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: accountB) == false)

        rig.auth.errorMessage = nil
        #expect(rig.auth.errorMessage == AuthMessage.signInHeld)

        rig.auth.errorMessage = "synthetic"
        #expect(rig.auth.errorMessage == "synthetic")
        rig.auth.errorMessage = nil
        #expect(rig.auth.errorMessage == AuthMessage.signInHeld)
    }

    // MARK: at launch

    /// The launch's retry failed. One try: the launch doesn't ask again, and neither does the SDK's first event.
    @Test func aRefusedResumeHoldsTheStoredAccount() async throws {
        let rig = try await refused()
        rig.wipesAnswer = false
        let before = rig.wipes.count

        rig.relaunch(signedInAs: accountB)

        expectHeld(rig, for: accountB)
        await rig.settle()
        expectHeld(rig, for: accountB)
        #expect(rig.wipes.count == before + 1)
        #expect(rig.ledgerOnDisk?.wipe.account == a)
    }

    /// A kept id from before the ledger: no entry, and nothing but `publish` to stop B.
    @Test func aKeptIdWithNoEntryHoldsTheStoredAccount() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        await rig.end(.user)
        rig.defaults.set(a, forKey: AccountScope.defaultsKey)
        rig.wipesAnswer = false

        rig.relaunch(signedInAs: accountB)

        expectHeld(rig, for: accountB)
        #expect(rig.ledgerOnDisk?.wipe.account == a)
    }

    /// The launch couldn't read the session or the entry, and the first event brings both: an interrupted sign-out, not
    /// a sign-in. Published, the next launch would take this session's live work.
    @Test func aLateInitialSessionOfTheEntrysOwnAccountIsHeld() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.relaunch(signedInAs: nil)
        WipeLedger(file: rig.ledgerFile).begin(Wipe(reason: .user, account: a), at: rig.clock.now())
        rig.client.unlock(.preview(id: WipeValues.accountA))
        await rig.settle()

        expectHeld(rig, for: WipeValues.accountA)
        #expect(rig.wipes.isEmpty)
        #expect(rig.ledgerOnDisk != nil)

        rig.relaunch(signedInAs: WipeValues.accountA)
        #expect(rig.auth.accountID == nil)
        #expect(await eventually { rig.client.signOutCount == 1 })
    }

    /// The same event of another account is a sign-in over a debt like any other.
    @Test func aLateInitialSessionOfAnotherAccountClearsTheDebtFirst() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.relaunch(signedInAs: nil)
        WipeLedger(file: rig.ledgerFile).begin(Wipe(reason: .user, account: a), at: rig.clock.now())
        rig.client.unlock(.preview(id: accountB))
        await rig.settle()

        #expect(rig.auth.accountID == b)
        #expect(rig.wipes.map(\.account) == [a])
        #expect(rig.ledgerOnDisk == nil)
    }

    /// W3's bullet on the interrupted sign-out, built in W2.
    @Test func theEntrysOwnStoredAccountIsSignedOutOnce() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        WipeLedger(file: rig.ledgerFile).begin(Wipe(reason: .user, account: a), at: rig.clock.now())

        rig.relaunch(signedInAs: WipeValues.accountA)

        #expect(rig.auth.accountID == nil)
        #expect(await eventually { rig.client.signOutCount == 1 })
        #expect(await eventually { rig.ledgerOnDisk == nil })
        await rig.settle()
        #expect(rig.auth.accountID == nil)
        #expect(rig.client.signOutCount == 1)
    }

    // MARK: while the SDK call of an interrupted sign-out runs

    /// The entry stands and a true wipe has taken the id: only the ledger says so. A kill here would resume the entry
    /// over whoever was published.
    @Test(arguments: [WipeValues.accountB, WipeValues.accountA])
    func aSignInDuringTheSDKCallIsHeld(_ id: UUID) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        WipeLedger(file: rig.ledgerFile).begin(Wipe(reason: .user, account: a), at: rig.clock.now())
        let hold = Hold()
        rig.relaunch(signedInAs: WipeValues.accountA) { await hold.wait() }
        let client = rig.client
        #expect(await eventually { client.signOutCount == 1 })
        #expect(rig.lastUser == nil)
        #expect(rig.ledgerOnDisk != nil)
        let wipes = rig.wipes.count

        #expect(await logIn(rig, as: id) == false)

        #expect(rig.auth.accountID == nil)
        #expect(rig.auth.errorMessage == AuthMessage.signInHeld)
        #expect(rig.wipes.count == wipes)
        #expect(rig.ledgerOnDisk?.wipe.account == a, "only the SDK call's end may end it")

        hold.open()
        #expect(await eventually { rig.ledgerOnDisk == nil })
        #expect(rig.auth.accountID == nil)
        #expect(rig.auth.errorMessage == nil, "the call took the session, and the debt went with it")

        #expect(await logIn(rig, as: id))
        #expect(rig.auth.accountID == id.uuidString)
    }

    // MARK: the same account

    /// Published either way. After a refused pass the debt stands, marked as published over: as it was, the next launch
    /// would read an interrupted sign-out and take this account's live work. That launch ends it, and wipes nothing.
    @Test(arguments: [true, false])
    func theEntrysOwnAccountIsPublishedEitherWay(_ healthy: Bool) async throws {
        let rig = try await refused()
        if healthy { try rig.disk.allowDeletes() }
        let before = rig.wipes.count

        #expect(await logIn(rig, as: WipeValues.accountA))

        #expect(rig.auth.accountID == a)
        #expect(rig.auth.errorMessage == nil)
        #expect(rig.wipes.count == before + 1, "the call and the mock's event: the second is a refresh")
        #expect(rig.wipes.last?.storeOnly == true)
        #expect(rig.ledgerOnDisk?.publishedOver == true)
        #expect(rig.ledgerOnDisk?.endsOwnSession == true)
        #expect(rig.lastUser == a)

        rig.relaunch(signedInAs: WipeValues.accountA)
        #expect(rig.auth.accountID == a)
        #expect(rig.wipes.count == before + 1)
        #expect(rig.client.signOutCount == 0)
        #expect(rig.ledgerOnDisk == nil)
    }

    /// With no refusal in this process a true attempt ends it. A first refusal here stands like one before it.
    @Test(arguments: [true, false])
    func aReturnEndsTheDebtOnlyOnATruePass(_ healthy: Bool) async throws {
        let rig = try await lateDebt()
        if !healthy { try rig.disk.refuseDeletes() }

        #expect(await logIn(rig, as: WipeValues.accountA))

        #expect(rig.auth.accountID == a)
        #expect(rig.answers.last == healthy)
        #expect(rig.ledgerOnDisk?.publishedOver == (healthy ? nil : true))
    }

    /// Published over the entry, and then it signs out: from here it's that sign-out again, so a kill before the SDK
    /// call ends it at the next launch instead of publishing it.
    @Test func aReturnedAccountSigningOutOwesItsOwnEnd() async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: WipeValues.accountA))
        #expect(rig.ledgerOnDisk?.publishedOver == true)

        await rig.end(.user)
        #expect(rig.ledgerOnDisk?.publishedOver == false)

        rig.relaunch(signedInAs: WipeValues.accountA)
        #expect(rig.auth.accountID == nil)
        #expect(await eventually { rig.client.signOutCount == 1 })
    }

    /// A debt with no id left names who's leaving through its entry.
    @Test func aDebtWithNoOwnerNamesItsAccount() async throws {
        let rig = try await lateDebt()
        rig.defaults.removeObject(forKey: AccountScope.defaultsKey)
        rig.wipesAnswer = false

        #expect(await logIn(rig, as: accountB) == false)

        #expect(rig.wipes.last?.account == a)
        expectHeld(rig, for: accountB)
    }

    /// The store keeps refusing: A's wipe fails, B is held and leaves, and A comes back and works. Nothing was published
    /// over an entry, so the relaunch finds no debt, and what A has is still there.
    @Test func aHeldAccountLeavingDoesntCostTheReturningOneItsWork() async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: accountB) == false)
        await rig.auth.signOut()
        await rig.settle()
        #expect(rig.client.currentSession == nil)

        #expect(await logIn(rig, as: WipeValues.accountA))
        let work = try unsent(of: a, in: rig)

        rig.relaunch(signedInAs: WipeValues.accountA)

        #expect(rig.auth.accountID == a)
        #expect(rig.ledgerOnDisk == nil)
        #expect(rig.client.signOutCount == 0)
        #expect(try activities(rig).contains(work))
        #expect(try rig.disk.inFreshContext == .init(sessions: 1, exercises: 2, sets: 6), "no replace")
    }

    /// An expiry's parked row keeps its date through the attempt.
    @Test func aReturnKeepsWhatTheEntryParks() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let work = try unsent(of: a, in: rig)
        rig.disk.fill([.cachedDay])
        try rig.disk.refuseDeletes(of: .cachedDay)
        await rig.end(.sessionExpired)
        try rig.disk.allowDeletes()

        #expect(await logIn(rig, as: WipeValues.accountA))

        #expect(try activities(rig).contains(work))
        #expect(rig.ledgerOnDisk?.wipe.parking == a)
    }

    /// No id says otherwise, so the entry's name stands: a true wipe that ran during the SDK call, or a repeat of one,
    /// can take the id and leave the debt.
    @Test func aReturnWithNoOwnerLeftIsStillAReturn() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let work = try unsent(of: a, in: rig)
        rig.disk.fill([.cachedDay])
        try rig.disk.refuseDeletes(of: .cachedDay)
        await rig.end(.sessionExpired)
        rig.defaults.removeObject(forKey: AccountScope.defaultsKey)
        try rig.disk.allowDeletes()

        #expect(await logIn(rig, as: WipeValues.accountA))

        #expect(rig.wipes.last?.parking == a)
        #expect(try activities(rig).contains(work))
    }

    /// The name on the entry isn't enough: `lastUserKey` says the store holds someone else's rows.
    @Test(arguments: [true, false])
    func aReturnOverAnotherOwnersRowsWipesThem(_ healthy: Bool) async throws {
        let rig = try await lateDebt()
        rig.defaults.set(b, forKey: AccountScope.defaultsKey)
        if !healthy { try rig.disk.refuseDeletes() }

        #expect(await logIn(rig, as: WipeValues.accountA) == healthy)

        #expect(rig.wipes.last?.account == b)
        if healthy {
            #expect(rig.auth.accountID == a)
            #expect(rig.lastUser == a)
            try rig.disk.expectNothingLeft()
        } else {
            expectHeld(rig, for: WipeValues.accountA)
            #expect(rig.ledgerOnDisk != nil)
        }
    }

    /// A build before the hold may have published someone over the entry, whose sign-out then died after `begin`: the
    /// entry names A, the owner reads A, and the rows may be anyone's. Nothing of it is kept for A.
    @Test(arguments: [true, false])
    func aReturnToAnEntryFromBeforeTheHoldWipes(_ healthy: Bool) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.fill([.cachedDay])
        let other = try unsent(of: a, in: rig)
        await rig.settle()
        rig.relaunch(signedInAs: nil)
        await rig.settle()
        rig.defaults.set(a, forKey: AccountScope.defaultsKey)
        let w1 = WipeEntries.fromAW1Build(reason: .sessionExpired, account: a, since: WipeValues.now)
        try w1.write(to: rig.ledgerFile)
        if !healthy { rig.wipesAnswer = false }

        #expect(await logIn(rig, as: WipeValues.accountA) == healthy)

        #expect(rig.wipes.last?.parking == nil)
        if healthy {
            #expect(rig.auth.accountID == a)
            #expect(try !activities(rig).contains(other))
        } else {
            expectHeld(rig, for: WipeValues.accountA)
            #expect(rig.ledgerOnDisk?.endsOwnSession == false, "a sign-in's wipe doesn't change what the entry says")
        }
    }

    /// Only that account's own end makes the entry an interrupted sign-out again.
    @Test func anAccountsOwnEndIsWhatSetsTheKeyBack() throws {
        let ledger = WipeLedger(file: nil)
        ledger.begin(Wipe(reason: .user, account: a), at: WipeValues.now)
        ledger.update { $0.publishedOver = true }

        ledger.begin(Wipe(reason: .user, account: b), at: WipeValues.now)
        #expect(ledger.entry?.publishedOver == true)
        ledger.begin(Wipe(reason: nil, account: a), at: WipeValues.now)
        #expect(ledger.entry?.publishedOver == true)
        ledger.begin(Wipe(reason: .user, account: a), at: WipeValues.now)
        #expect(ledger.entry?.publishedOver == false)
    }

    /// A W1 build's entry stays one: its own account's end doesn't turn it into a W2 sign-out.
    @Test func aW1BuildsEntryKeepsItsMissingKey() throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        try WipeEntries.fromAW1Build(reason: .user, account: a, since: WipeValues.now).write(to: rig.ledgerFile)
        let ledger = WipeLedger(file: rig.ledgerFile)

        ledger.begin(Wipe(reason: .user, account: a), at: WipeValues.now)

        #expect(ledger.entry?.endsOwnSession == false)
        #expect(ledger.entry?.publishedOver == false)
    }

    @Test func aMarkOnAnEntryReadsBack() throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let ledger = WipeLedger(file: rig.ledgerFile)
        ledger.begin(Wipe(reason: .user, account: a), at: WipeValues.now)
        #expect(rig.ledgerOnDisk?.publishedOver == false)
        ledger.update { $0.publishedOver = true }
        #expect(rig.ledgerOnDisk?.publishedOver == true)
    }

    /// The launch before the first unlock reads neither the entry nor the session. Both come back with `route`.
    private func aLaunchBeforeTheFirstUnlock(_ rig: WipingAuth, reads session: UUID, firstEvent: Bool) async throws {
        let aside = rig.ledgerFile.appendingPathExtension("locked")
        try FileManager.default.moveItem(at: rig.ledgerFile, to: aside)
        rig.relaunch(signedInAs: nil)
        if firstEvent { await rig.settle() }
        try FileManager.default.moveItem(at: aside, to: rig.ledgerFile)
        if firstEvent {
            rig.client.emit(.tokenRefreshed, .preview(id: session))
        } else {
            rig.client.unlock(.preview(id: session))
        }
        await rig.settle()
    }

    /// A marked entry's account comes back as `.forget` would have it, however the session reaches `publish`: its unsent
    /// rows are live, and no wipe of it runs.
    @Test(arguments: [(false, true), (false, false), (true, true), (true, false)])
    func aLaunchThatCouldntReadTheMarkPublishesTheLiveWork(_ route: (firstEvent: Bool, owned: Bool)) async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: WipeValues.accountA))
        let work = try unsent(of: a, in: rig)
        let wipes = rig.wipes.count
        if !route.owned { rig.defaults.removeObject(forKey: AccountScope.defaultsKey) }

        try await aLaunchBeforeTheFirstUnlock(rig, reads: WipeValues.accountA, firstEvent: route.firstEvent)

        #expect(rig.auth.accountID == a)
        #expect(rig.auth.errorMessage == nil)
        #expect(rig.ledgerOnDisk == nil)
        #expect(rig.wipes.count == wipes)
        #expect(try activities(rig).contains(work))
    }

    /// The mark speaks for its own account's rows only: with another id in the store, the first event wipes as before.
    @Test func aMarkOverAnotherOwnerIsNoForget() async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: WipeValues.accountA))
        rig.defaults.set(b, forKey: AccountScope.defaultsKey)
        try rig.disk.allowDeletes()

        try await aLaunchBeforeTheFirstUnlock(rig, reads: WipeValues.accountA, firstEvent: true)

        #expect(rig.wipes.last?.account == b)
        #expect(rig.auth.accountID == a)
        #expect(rig.ledgerOnDisk == nil)
    }

    /// Another account's session never reads the mark as its own.
    @Test func aMarkDoesntLetAnotherAccountIn() async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: WipeValues.accountA))
        rig.wipesAnswer = false

        try await aLaunchBeforeTheFirstUnlock(rig, reads: accountB, firstEvent: true)

        expectHeld(rig, for: accountB)
        #expect(rig.ledgerOnDisk?.wipe.account == a)
    }

    /// A hold ended the marked account, and it comes back to its own live rows in that process: no pass, and with a
    /// refusal behind it the debt stands.
    @Test func aMarkedAccountComingBackInTheSameProcessTakesNoPass() async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: WipeValues.accountA))
        #expect(await logIn(rig, as: accountB) == false)
        #expect(rig.auth.accountID == nil)
        let wipes = rig.wipes.count

        #expect(await logIn(rig, as: WipeValues.accountA))

        #expect(rig.auth.accountID == a)
        #expect(rig.wipes.count == wipes)
        #expect(rig.ledgerOnDisk?.publishedOver == true)
    }

    /// A marked entry at a launch that can read it, with its account stored.
    @Test func theLaunchTableForgetsAMarkedEntry() {
        var owed = OwedWipe(wipe: Wipe(reason: .user, account: a, since: WipeValues.now))
        owed.publishedOver = true
        #expect(WipeResume.decide(owed, stored: a, now: WipeValues.now) == .forget)
        #expect(WipeResume.decide(owed, stored: b, now: WipeValues.now) == .wipeNow(narrow: false, endSession: false))
        #expect(WipeResume.decide(owed, stored: nil, now: WipeValues.now) == .wipeNow(narrow: false, endSession: false))
    }

    /// A full disk: the mark doesn't reach the file, which would read as an interrupted sign-out. No file reads as no
    /// debt over A, and this process still has the entry, so B stays out.
    @Test func aMarkTheDiskRefusesRemovesTheFile() async throws {
        let rig = try await refused()
        try FileManager.default.removeItem(at: rig.ledgerFile)
        let inTheWay = rig.ledgerFile.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: inTheWay, withIntermediateDirectories: true)

        #expect(await logIn(rig, as: WipeValues.accountA))

        #expect(rig.auth.accountID == a)
        #expect(!FileManager.default.fileExists(atPath: rig.ledgerFile.path))
        let work = try unsent(of: a, in: rig)

        #expect(await logIn(rig, as: accountB) == false)
        #expect(rig.auth.accountID == nil)

        rig.relaunch(signedInAs: WipeValues.accountA)
        #expect(rig.auth.accountID == a)
        #expect(rig.client.signOutCount == 0)
        #expect(try activities(rig).contains(work))
    }

    /// The control: a write that works leaves the file, marked.
    @Test func aMarkTheDiskTakesKeepsTheFile() async throws {
        let rig = try await refused()
        #expect(await logIn(rig, as: WipeValues.accountA))
        #expect(FileManager.default.fileExists(atPath: rig.ledgerFile.path))
    }

    /// `accountDeleted(background: true)`: the account signs in while its removal runs. That isn't a return.
    @Test(arguments: [true, false])
    func aDeletedAccountSigningInIsntAReturn(_ healthy: Bool) async throws {
        let rig = try await lateDebt(.accountDeleted(background: true))
        if !healthy { try rig.disk.refuseDeletes() }

        #expect(await logIn(rig, as: WipeValues.accountA) == healthy)

        if healthy {
            #expect(rig.auth.accountID == a)
            #expect(rig.ledgerOnDisk == nil)
            try rig.disk.expectNothingLeft()
        } else {
            expectHeld(rig, for: WipeValues.accountA)
            #expect(rig.ledgerOnDisk?.wipe.reason?.isDeletion == true)
        }
    }

    /// A sign-out's notice goes with a sign-in, not with a refresh of the session that's ending.
    @Test func aRefreshDuringASignOutKeepsItsNotice() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        await rig.settle()
        let hold = Hold(), auth = rig.auth, client = rig.client
        client.onSignOut = { await hold.wait() }
        let signOut = Task { await auth.signOut(reason: .sessionExpired) }
        #expect(await eventually { client.signOutCount == 1 })

        client.emit(.tokenRefreshed, .preview(id: WipeValues.accountA))
        await rig.settle()
        #expect(auth.signOutNotice != nil)

        hold.open()
        await signOut.value
        #expect(auth.signOutNotice != nil)
    }

    // MARK: whose state is this

    /// Anchors, the workout's account and the outbox read `AccountScope`: it's the published account from before the
    /// hooks run, through a sign-in, a refresh, a held sign-in, a release and a switch.
    @Test func accountScopeIsAlwaysThePublishedAccount() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let seen = ScopeSeen()
        func watch() {
            rig.auth.onAccountWillChange = { [weak rig] _, to, _ in
                if let to { seen.atHooks.append(to == rig?.lastUser) }
            }
        }
        watch()
        func check() {
            #expect(rig.auth.accountID != nil)
            #expect(rig.lastUser == rig.auth.accountID)
        }
        check()
        rig.client.emit(.tokenRefreshed, .preview(id: WipeValues.accountA))
        await rig.settle()
        check()

        #expect(await logIn(rig, as: accountB))
        check()
        rig.client.emit(.tokenRefreshed, .preview(id: accountB))
        await rig.settle()
        check()

        rig.disk.session(checked: true)
        try rig.disk.refuseDeletes()
        await rig.end(.user)
        #expect(await logIn(rig, as: WipeValues.accountB2) == false)
        rig.relaunch(signedInAs: WipeValues.accountB2)
        watch()
        check()

        #expect(await logIn(rig, as: WipeValues.accountA))
        check()
        #expect(seen.atHooks == [true, true])

        rig.relaunch(signedInAs: WipeValues.accountA)
        check()
    }

    @MainActor
    private final class ScopeSeen {
        var atHooks: [Bool] = []
    }

    /// A scrub isn't a debt: nothing is held over it, and the session ends it.
    @Test func aScrubHoldsNobody() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        await rig.end(.user)
        rig.relaunch(signedInAs: nil)
        await rig.settle()
        let ledger = WipeLedger(file: rig.ledgerFile)
        ledger.begin(Wipe(reason: .user, account: a), at: rig.clock.now())
        ledger.update { $0.scrubOnly = true }
        let wipes = rig.wipes.count

        #expect(await logIn(rig, as: accountB))

        #expect(rig.auth.accountID == b)
        #expect(rig.wipes.count == wipes)
        #expect(rig.ledgerOnDisk == nil)
    }
}
