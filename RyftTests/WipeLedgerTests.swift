import Foundation
import SwiftData
import Testing
@testable import Ryft

// A wipe is written down before it starts, and only a wipe that returned true ends the entry. Synthetic values only.

private typealias Wipe = AuthService.Wipe

/// A folder of its own for a ledger's file.
private final class LedgerFolder {
    let url: URL
    var file: URL { url.appendingPathComponent("account-wipe.json") }

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ryft-wipe-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }
}

private enum Ledger {
    static let a = "account-a", b = "account-b"
    static let first = Date(timeIntervalSinceReferenceDate: 800_000_000.5)
    static let later = first.addingTimeInterval(60)
    static let earlier = first.addingTimeInterval(-60)
}

/// What's owed, what comes next, what the entry says afterwards.
struct WipeMerge: CustomTestStringConvertible, Sendable {
    let name: String
    let owed: AuthService.SignOutReason?
    let next: AuthService.SignOutReason?
    var nextAccount = "account-a"
    let reason: AuthService.SignOutReason?
    let parking: String?
    var testDescription: String { name }

    static let all = [
        WipeMerge(name: "the same parking stays", owed: .sessionExpired, next: .sessionExpired, reason: .sessionExpired,
                  parking: "account-a"),
        WipeMerge(name: "another account's expiry narrows", owed: .sessionExpired, next: .sessionExpired,
                  nextAccount: "account-b", reason: nil, parking: nil),
        WipeMerge(name: "another account's sign-in narrows", owed: .sessionExpired, next: nil, nextAccount: "account-b",
                  reason: nil, parking: nil),
        WipeMerge(name: "a nil reason narrows", owed: .sessionExpired, next: nil, reason: nil, parking: nil),
        WipeMerge(name: "a log out narrows", owed: .sessionExpired, next: .user, reason: .user, parking: nil),
        WipeMerge(name: "a deletion narrows and says so", owed: .sessionExpired, next: .accountDeleted(background: true),
                  reason: .accountDeleted(background: true), parking: nil),
        WipeMerge(name: "an expiry doesn't widen a log out", owed: .user, next: .sessionExpired, reason: .user, parking: nil),
        WipeMerge(name: "an expiry doesn't widen a deletion", owed: .accountDeleted(background: false), next: .sessionExpired,
                  reason: .accountDeleted(background: false), parking: nil),
        WipeMerge(name: "an expiry doesn't widen a nil reason", owed: nil, next: .sessionExpired, reason: nil, parking: nil),
    ]
}

@MainActor
struct WipeLedgerTests {
    // MARK: the file

    @Test(arguments: [AuthService.SignOutReason.user, .sessionExpired, .accountDeleted(background: true),
                      .accountDeleted(background: false)])
    func anEntrySurvivesARestart(_ reason: AuthService.SignOutReason) throws {
        let folder = try LedgerFolder()
        WipeLedger(file: folder.file).begin(Wipe(reason: reason, account: Ledger.a), at: Ledger.first)

        let entry = try #require(WipeLedger(file: folder.file).entry)
        #expect(entry.wipe.reason == reason)
        #expect(entry.wipe.account == Ledger.a)
        #expect(entry.since == Ledger.first, "to the bit: a retry parks with it")
        #expect(!entry.deviceStepsDone && !entry.scrubOnly)
    }

    @Test func anEntryForAnotherAccountsSignInHasNoReason() throws {
        let folder = try LedgerFolder()
        WipeLedger(file: folder.file).begin(Wipe(reason: nil, account: Ledger.a), at: Ledger.first)
        let entry = try #require(WipeLedger(file: folder.file).entry)
        #expect(entry.wipe.reason == nil && entry.wipe.parking == nil)
    }

    /// The format outlives the build: a later build reads what this one wrote, and one it can't decode is never acted on.
    @Test func theFormatIsPinned() throws {
        let folder = try LedgerFolder()
        let json = """
        {"wipe":{"reason":{"sessionExpired":{}},"account":"account-a","since":800000000.5},\
        "deviceStepsDone":true,"scrubOnly":false}
        """
        try Data(json.utf8).write(to: folder.file)
        let entry = try #require(WipeLedger(file: folder.file).entry)
        #expect(entry.wipe.reason == .sessionExpired && entry.wipe.parking == Ledger.a)
        #expect(entry.since == Ledger.first)
        #expect(entry.deviceStepsDone && !entry.scrubOnly)

        let deleted = #"{"wipe":{"reason":{"accountDeleted":{"background":true}},"since":1},"deviceStepsDone":false,"scrubOnly":true}"#
        try Data(deleted.utf8).write(to: folder.file)
        let other = try #require(WipeLedger(file: folder.file).entry)
        #expect(other.wipe.reason == .accountDeleted(background: true) && other.wipe.account == nil && other.scrubOnly)

        WipeLedger(file: folder.file).begin(Wipe(reason: .user, account: Ledger.b), at: Ledger.first)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.file)) as? [String: Any]
        #expect(Set(object?.keys.map { $0 } ?? []) == ["wipe", "deviceStepsDone", "scrubOnly"], "both flags from the start")
    }

    /// The options, not the file: the simulator reports no protection class.
    @Test func aWriteIsAtomicWithTheSessionsProtectionClass() {
        #expect(WipeLedger.writeOptions == [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    @Test func itMakesItsFolder() throws {
        let folder = try LedgerFolder()
        let nested = folder.url.appendingPathComponent("Application Support").appendingPathComponent("account-wipe.json")
        WipeLedger(file: nested).begin(Wipe(reason: .user, account: Ledger.a), at: Ledger.first)
        #expect(WipeLedger(file: nested).entry != nil)
    }

    // MARK: merging

    @Test func theEarliestDateStaysEitherWay() throws {
        let folder = try LedgerFolder()
        let ledger = WipeLedger(file: folder.file)
        let wipe = Wipe(reason: .sessionExpired, account: Ledger.a)
        ledger.begin(wipe, at: Ledger.first)
        ledger.begin(wipe, at: Ledger.later)
        #expect(ledger.entry?.since == Ledger.first)
        #expect(ledger.entry?.wipe.since == Ledger.first, "a retry runs the entry's wipe, and it parks with this date")
        ledger.begin(wipe, at: Ledger.earlier)
        #expect(ledger.entry?.since == Ledger.earlier)
        #expect(WipeLedger(file: folder.file).entry?.since == Ledger.earlier, "and on disk")
    }

    /// The date inside the wipe that comes in is the caller's; `at` is the one that counts.
    @Test func theDateIsTheBeginsNotTheWipes() {
        let ledger = WipeLedger(file: nil)
        ledger.begin(Wipe(reason: .user, account: Ledger.a, since: Ledger.earlier), at: Ledger.first)
        #expect(ledger.entry?.since == Ledger.first)
    }

    @Test(arguments: WipeMerge.all)
    func aMergeOnlyNarrows(_ merge: WipeMerge) throws {
        let folder = try LedgerFolder()
        let ledger = WipeLedger(file: folder.file)
        ledger.begin(Wipe(reason: merge.owed, account: Ledger.a), at: Ledger.first)
        ledger.begin(Wipe(reason: merge.next, account: merge.nextAccount), at: Ledger.later)

        let entry = try #require(WipeLedger(file: folder.file).entry)
        #expect(entry.wipe.reason == merge.reason)
        #expect(entry.wipe.parking == merge.parking)
        #expect(entry.wipe.account == Ledger.a, "the oldest data's owner")
        #expect(entry.since == Ledger.first)
    }

    @Test func narrowedOnceItNeverWidensBack() throws {
        let ledger = WipeLedger(file: nil)
        ledger.begin(Wipe(reason: .sessionExpired, account: Ledger.a), at: Ledger.first)
        ledger.begin(Wipe(reason: .sessionExpired, account: Ledger.b), at: Ledger.later)
        ledger.begin(Wipe(reason: .sessionExpired, account: Ledger.a), at: Ledger.later)
        ledger.begin(Wipe(reason: .sessionExpired, account: Ledger.b), at: Ledger.later)
        let entry = try #require(ledger.entry)
        #expect(entry.wipe.parking == nil)
    }

    /// An entry that parks nobody, with no account: a later expiry's account mustn't turn it into a parking one.
    @Test func anEntryWithoutAnAccountDoesntTakeOne() throws {
        let ledger = WipeLedger(file: nil)
        ledger.begin(Wipe(reason: .sessionExpired, account: nil), at: Ledger.first)
        ledger.begin(Wipe(reason: .sessionExpired, account: Ledger.a), at: Ledger.later)
        let entry = try #require(ledger.entry)
        #expect(entry.wipe.parking == nil)
    }

    @Test func aMergeKeepsTheFlags() {
        let ledger = WipeLedger(file: nil)
        ledger.begin(Wipe(reason: .user, account: Ledger.a), at: Ledger.first)
        ledger.update { $0.deviceStepsDone = true }
        ledger.begin(Wipe(reason: .user, account: Ledger.a), at: Ledger.later)
        #expect(ledger.entry?.deviceStepsDone == true)
    }

    // MARK: update, clear

    @Test func anUpdateReachesTheFile() throws {
        let folder = try LedgerFolder()
        let ledger = WipeLedger(file: folder.file)
        ledger.begin(Wipe(reason: .user, account: Ledger.a), at: Ledger.first)
        ledger.update { $0.deviceStepsDone = true }
        #expect(ledger.entry?.deviceStepsDone == true)
        #expect(WipeLedger(file: folder.file).entry?.deviceStepsDone == true)
    }

    @Test func anUpdateWithNothingOwedWritesNothing() throws {
        let folder = try LedgerFolder()
        let ledger = WipeLedger(file: folder.file)
        ledger.update { $0.scrubOnly = true }
        #expect(ledger.entry == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.file.path))
    }

    @Test func clearRemovesTheFile() throws {
        let folder = try LedgerFolder()
        let ledger = WipeLedger(file: folder.file)
        ledger.begin(Wipe(reason: .user, account: Ledger.a), at: Ledger.first)
        ledger.clear()
        #expect(ledger.entry == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.file.path))
        ledger.clear() // nothing there is no failure
        #expect(ledger.entry == nil)
    }

    /// A debt nothing could remove is still a debt: the next launch reads it, so this run says so too.
    @Test func anEntryThatCantBeRemovedStaysOwed() throws {
        let folder = try LedgerFolder()
        let ledger = WipeLedger(file: folder.file)
        ledger.begin(Wipe(reason: .user, account: Ledger.a), at: Ledger.first)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.url.path)
        ledger.clear()
        #expect(ledger.entry?.wipe.account == Ledger.a)
    }

    // MARK: a file that can't be read or written

    @Test func anEntryThatCantBeReadIsNoEntryAndTheFileStays() throws {
        let folder = try LedgerFolder()
        let garbage = Data("not an entry".utf8)
        try garbage.write(to: folder.file)
        let ledger = WipeLedger(file: folder.file)
        #expect(ledger.entry == nil)
        ledger.update { $0.scrubOnly = true }
        #expect(try Data(contentsOf: folder.file) == garbage)
    }

    /// A newer wipe doesn't wait on it: what's owed now is on disk before it starts.
    @Test func aBeginReplacesAnEntryThatCantBeRead() throws {
        let folder = try LedgerFolder()
        try Data("not an entry".utf8).write(to: folder.file)
        WipeLedger(file: folder.file).begin(Wipe(reason: .user, account: Ledger.a), at: Ledger.first)
        #expect(WipeLedger(file: folder.file).entry?.wipe.account == Ledger.a)
    }

    /// Before the first unlock the file can't be read; once it can, the same ledger finds what's owed.
    @Test func anEntryIsReadOnceItCanBe() throws {
        let folder = try LedgerFolder()
        let ledger = WipeLedger(file: folder.file)
        #expect(ledger.entry == nil)
        WipeLedger(file: folder.file).begin(Wipe(reason: .sessionExpired, account: Ledger.a), at: Ledger.first)
        ledger.begin(Wipe(reason: .sessionExpired, account: Ledger.a), at: Ledger.later)
        #expect(ledger.entry?.since == Ledger.first)
    }

    /// A file where the folder should be: every write fails, as on a full disk.
    @Test func aFileThatCantBeWrittenKeepsTheEntryInMemoryForTheRun() throws {
        let folder = try LedgerFolder()
        let inTheWay = folder.url.appendingPathComponent("blocked")
        try Data([1]).write(to: inTheWay)
        let file = inTheWay.appendingPathComponent("account-wipe.json")

        let ledger = WipeLedger(file: file)
        ledger.begin(Wipe(reason: .sessionExpired, account: Ledger.a), at: Ledger.first)
        #expect(ledger.entry?.wipe.parking == Ledger.a)
        #expect(WipeLedger(file: file).entry == nil, "nothing reached the disk")

        ledger.update { $0.deviceStepsDone = true }
        ledger.begin(Wipe(reason: nil, account: Ledger.a), at: Ledger.later)
        #expect(ledger.entry?.deviceStepsDone == true && ledger.entry?.wipe.parking == nil)
        #expect(ledger.entry?.since == Ledger.first)

        ledger.clear()
        #expect(ledger.entry == nil)
    }

    /// The disk comes back: the next write carries everything memory held.
    @Test func aLaterBeginWritesWhatAnEarlierOneCouldnt() throws {
        let folder = try LedgerFolder()
        let inTheWay = folder.url.appendingPathComponent("blocked")
        try Data([1]).write(to: inTheWay)
        let file = inTheWay.appendingPathComponent("account-wipe.json")
        let ledger = WipeLedger(file: file)
        ledger.begin(Wipe(reason: .user, account: Ledger.a), at: Ledger.first)

        try FileManager.default.removeItem(at: inTheWay)
        ledger.begin(Wipe(reason: .user, account: Ledger.a), at: Ledger.later)
        #expect(WipeLedger(file: file).entry?.since == Ledger.first)
    }

    /// Previews and the tests that don't care: no file anywhere.
    @Test func aLedgerWithoutAFileWorksInMemory() {
        let ledger = WipeLedger(file: nil)
        #expect(ledger.entry == nil)
        ledger.begin(Wipe(reason: .user, account: Ledger.a), at: Ledger.first)
        #expect(ledger.entry?.wipe.account == Ledger.a)
        ledger.clear()
        #expect(ledger.entry == nil)
    }

    @Test func theLiveFileIsInApplicationSupport() {
        #expect(WipeLedger.liveFile == URL.applicationSupportDirectory.appendingPathComponent("account-wipe.json"))
    }
}

// MARK: - the ledger in `AuthService`, on a store on disk

/// What a hook saw, for the test to read afterwards.
@MainActor
private final class Seen {
    var entries: [OwedWipe?] = []
    var wipes: [AuthService.Wipe] = []
    var rows: StoreOnDisk.Rows?
    var firstEntry: OwedWipe? { entries.compactMap { $0 }.first }
}

/// Holds `MockAuthClient.signOut()` where it is: the process is gone as far as the test cares.
private final class Hold: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream<Void>.makeStream()
    }

    func wait() async {
        for await _ in stream {}
    }

    func open() {
        continuation.finish()
    }
}

@MainActor
struct WipeLedgerAuthTests {
    private let a = WipeValues.accountA.uuidString, b = WipeValues.accountB.uuidString

    private func unsentActivity(of account: String, parkedAt: Date? = nil) -> LocalActivity {
        let row = LocalActivity(account: account, sport: .running, origin: .manual, start: WipeValues.earlier,
                                end: WipeValues.now, movingSec: 1_800, localRevision: 2, confirmedRevision: 1,
                                createdAt: WipeValues.earlier)
        row.parkedAt = parkedAt
        return row
    }

    private func insert(_ row: LocalActivity, into rig: WipingAuth) {
        rig.disk.store.context.insert(row)
        rig.disk.store.save()
    }

    /// Through a fresh context: what was saved.
    private func parkedDates(_ rig: WipingAuth) throws -> [UUID: Date?] {
        let rows = try ModelContext(rig.disk.store.container).fetch(FetchDescriptor<LocalActivity>())
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.parkedAt) })
    }

    /// Records what's on disk when the SDK is asked to drop the session.
    private func watchSignOut(_ rig: WipingAuth) -> Seen {
        let seen = Seen()
        rig.client.onSignOut = { @MainActor in
            seen.entries.append(rig.ledgerOnDisk)
            seen.rows = try? rig.disk.inFreshContext
        }
        return seen
    }

    /// Records what's on disk as the store's wipe starts.
    private func watchWipes(_ rig: WipingAuth) -> Seen {
        let seen = Seen()
        rig.atTheWipe = { [weak rig] wipe in
            seen.entries.append(rig?.ledgerOnDisk)
            seen.wipes.append(wipe)
        }
        return seen
    }

    /// Starts a sign-out and leaves it inside the SDK call, with the session still stored and nothing wiped.
    private func signOutStopped(_ rig: WipingAuth, reason: AuthService.SignOutReason) async -> (Hold, Task<Void, Never>) {
        let hold = Hold(), auth = rig.auth
        rig.client.onSignOut = { await hold.wait() }
        let task = Task { await auth.signOut(reason: reason) }
        let client = rig.client
        #expect(await eventually { client.signOutCount == 1 })
        return (hold, task)
    }

    // MARK: written down first

    @Test(arguments: WipeValues.endings)
    func theEntryIsOnDiskWhenTheSDKIsAsked(_ ending: AuthService.SignOutReason) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        let seen = watchSignOut(rig)

        await rig.end(ending)

        #expect(rig.client.signOutCount == 1)
        let entry = try #require(seen.firstEntry)
        #expect(entry.wipe.reason == ending)
        #expect(entry.wipe.account == a)
        #expect(entry.since == WipeValues.now)
        #expect(seen.rows == .init(sessions: 1, exercises: 2, sets: 6), "and nothing had gone yet")
    }

    /// A final 401 while the account is being deleted ends as the deletion, on disk too: a kill right there must not
    /// leave a debt that parks the deleted account's rows.
    @Test func aRejectionDuringADeletionIsWrittenAsTheDeletion() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let seen = watchSignOut(rig)
        rig.duringDeletion = { [weak rig] in await rig?.auth.rejectedAfterRefresh() }

        #expect(await rig.auth.deleteAccount())

        let entry = try #require(seen.firstEntry)
        #expect(entry.wipe.reason == .accountDeleted(background: false))
        #expect(entry.wipe.parking == nil)
    }

    /// Nobody's session is ending: nothing would ever end an entry.
    @Test func aSignOutWithNoSessionOwesNothing() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.relaunch(signedInAs: nil)
        await rig.auth.signOut(reason: .sessionExpired)
        #expect(rig.client.signOutCount == 1)
        #expect(!FileManager.default.fileExists(atPath: rig.ledgerFile.path))
    }

    /// The SDK ended the session by itself: nothing was written ahead of the event, and the wipe still writes first.
    @Test func anExpiryTheSDKReportsIsWrittenBeforeTheWipe() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        await rig.settle()
        let seen = watchWipes(rig)

        rig.client.emit(.signedOut, nil)
        #expect(await eventually { !seen.wipes.isEmpty })

        let entry = try #require(seen.firstEntry)
        #expect(entry.wipe.reason == .sessionExpired && entry.wipe.account == a)
        await rig.settle()
        #expect(rig.ledgerOnDisk == nil)
    }

    @Test func aSignInOverAnotherAccountIsWrittenBeforeTheWipe() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let seen = watchWipes(rig)

        await rig.signIn(WipeValues.accountB)

        let entry = try #require(seen.firstEntry)
        #expect(entry.wipe.reason == nil && entry.wipe.account == a)
        #expect(rig.ledgerOnDisk == nil)
        #expect(rig.auth.accountID == b)
    }

    /// Its own wipe, unledgered: nothing in it is an account's debt, and it leaves the ledger as it was.
    @Test func apiKeyModeLeavesTheLedgerAlone() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let settings = Settings(defaults: rig.defaults)
        settings.apiKeyMode = true
        rig.relaunch(signedInAs: nil)
        WipeLedger(file: rig.ledgerFile).begin(.init(reason: .user, account: a), at: WipeValues.earlier)
        let seen = watchWipes(rig)

        await rig.auth.signOut()

        #expect(seen.wipes.count == 1)
        #expect(seen.wipes.first?.account == nil)
        #expect(rig.ledgerOnDisk?.since == WipeValues.earlier)
        #expect(rig.ledgerOnDisk?.wipe.account == a)
    }

    // MARK: how it ends

    @Test(arguments: WipeValues.endings)
    func aWipeThatReturnedTrueEndsTheEntry(_ ending: AuthService.SignOutReason) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        await rig.end(ending)
        #expect(!FileManager.default.fileExists(atPath: rig.ledgerFile.path))
        try rig.disk.expectNothingLeft()
    }

    @Test(arguments: WipeValues.endings)
    func aWipeThatReturnedFalseKeepsTheEntryOverARestart(_ ending: AuthService.SignOutReason) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        try rig.disk.refuseDeletes()

        await rig.end(ending)

        #expect(rig.auth.accountID == nil)
        #expect(rig.lastUser == a, "the kept id stays until the sign-in side moves to the ledger")
        rig.relaunch(signedInAs: nil)
        let entry = try #require(rig.ledgerOnDisk)
        #expect(entry.wipe.reason == ending && entry.wipe.account == a)
        #expect(entry.since == WipeValues.now)
    }

    /// The session ended while the platform deleted, and the deletion's own wipe, refused, owes the deletion.
    @Test func aRefusedWipeAfterADeletionIsOwed() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.duringDeletion = { [weak rig] in
            await rig?.auth.rejectedAfterRefresh()
            rig?.disk.session(checked: true)
            try? rig?.disk.refuseDeletes()
        }

        #expect(await rig.auth.deleteAccount())

        let entry = try #require(rig.ledgerOnDisk)
        #expect(entry.wipe.reason == .accountDeleted(background: false))
        #expect(entry.wipe.account == a)
    }

    /// The retry that `lastUserKey` still drives ends the debt too.
    @Test func aRefusedWipeAtSignInEndsWithItsRetry() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        try rig.disk.refuseDeletes()

        await rig.signIn(WipeValues.accountB)
        #expect(rig.auth.accountID == b, "today's behaviour, until the hold")
        #expect(rig.ledgerOnDisk?.wipe.account == a)

        rig.relaunch(signedInAs: WipeValues.accountB)
        #expect(rig.ledgerOnDisk != nil, "refused again")
        try rig.disk.allowDeletes()
        rig.relaunch(signedInAs: WipeValues.accountB)
        #expect(rig.ledgerOnDisk == nil)
        try rig.disk.expectNothingLeft()
    }

    /// Another account's wipe keeps nothing, so the entry can't either, and its date stays the first one.
    @Test func aSignInOverAParkedDebtNarrowsIt() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        insert(unsentActivity(of: a), into: rig)
        rig.disk.fill([.cachedDay])
        try rig.disk.refuseDeletes(of: .cachedDay)
        await rig.end(.sessionExpired)
        #expect(rig.ledgerOnDisk?.wipe.parking == a)

        rig.relaunch(signedInAs: nil)
        rig.clock.advance(by: .seconds(3_600))
        await rig.signIn(WipeValues.accountB)

        let entry = try #require(rig.ledgerOnDisk)
        #expect(entry.wipe.parking == nil && entry.wipe.reason == nil && entry.wipe.account == a)
        #expect(entry.since == WipeValues.now)
    }

    // MARK: a kill between `begin` and the wipe

    @Test(arguments: WipeValues.endings)
    func aKillAfterTheSDKDroppedTheSessionLeavesTheDebt(_ ending: AuthService.SignOutReason) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        let (hold, task) = await signOutStopped(rig, reason: ending)

        rig.relaunch(signedInAs: nil)

        let entry = try #require(rig.ledgerOnDisk)
        #expect(entry.wipe.reason == ending && entry.wipe.account == a)
        #expect(rig.auth.accountID == nil)
        #expect(rig.lastUser == a)
        #expect(try rig.disk.inFreshContext == .init(sessions: 1, exercises: 2, sets: 6), "this ticket resumes nothing")

        await rig.signIn(WipeValues.accountB)
        #expect(rig.auth.accountID == b)
        #expect(rig.ledgerOnDisk == nil)
        try rig.disk.expectNothingLeft()

        hold.open()
        await task.value
    }

    /// The session survived, so the account is still signed in, as it was before there was a ledger. The entry goes:
    /// it would otherwise tell a later launch that this account's live work is a debt.
    @Test(arguments: WipeValues.endings)
    func aKillBeforeTheSDKDroppedTheSessionChangesNothing(_ ending: AuthService.SignOutReason) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        let (hold, task) = await signOutStopped(rig, reason: ending)
        #expect(rig.ledgerOnDisk != nil)

        rig.relaunch(signedInAs: WipeValues.accountA)
        let seen = watchWipes(rig)
        await rig.settle()

        #expect(rig.auth.accountID == a)
        #expect(seen.wipes.isEmpty)
        #expect(rig.ledgerOnDisk == nil)
        #expect(try rig.disk.inFreshContext == .init(sessions: 1, exercises: 2, sets: 6))

        rig.atTheWipe = nil
        hold.open()
        await task.value
    }

    // MARK: the same account comes back

    /// No attempt and no wipe: what a sign-in does today, with the debt over.
    @Test func theEntrysOwnAccountSigningInEndsItAndWipesNothing() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.fill([.cachedDay])
        try rig.disk.refuseDeletes(of: .cachedDay)
        await rig.end(.user)
        #expect(rig.ledgerOnDisk != nil)

        rig.relaunch(signedInAs: nil)
        try rig.disk.allowDeletes()
        let seen = watchWipes(rig)
        await rig.signIn(WipeValues.accountA)

        #expect(rig.auth.accountID == a)
        #expect(seen.wipes.isEmpty)
        #expect(rig.ledgerOnDisk == nil)
        #expect(rig.lastUser == a)
        #expect(try rig.disk.inFile[.cachedDay] == 1)
    }

    /// Another account signing in over the entry's: that isn't its return, and that entry stays with the refused wipe.
    @Test func anotherAccountsSignInDoesntEndTheEntry() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.fill([.cachedDay])
        try rig.disk.refuseDeletes(of: .cachedDay)
        await rig.end(.user)

        await rig.signIn(WipeValues.accountB)

        #expect(rig.ledgerOnDisk?.wipe.account == a)
    }

    /// The entry is the old session's. Left standing, its date would be this expiry's, and the row would be 30 days
    /// nearer its deletion than it is: a loss of work that a build without the ledger doesn't have.
    @Test func aLaterExpiryOfTheReturnedAccountParksAtItsOwnDate() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.fill([.cachedDay])
        try rig.disk.refuseDeletes(of: .cachedDay)
        await rig.end(.sessionExpired)
        try rig.disk.allowDeletes()
        await rig.signIn(WipeValues.accountA)

        rig.clock.advance(by: .seconds(40 * 86_400))
        let unsent = unsentActivity(of: a)
        let id = unsent.id
        insert(unsent, into: rig)
        await rig.end(.sessionExpired)

        #expect(try parkedDates(rig)[id] == rig.clock.now())
        #expect(rig.ledgerOnDisk == nil)
    }

    /// A refresh while the sign-out runs: the account never left, and the debt stands.
    @Test func aTokenRefreshDuringASignOutDoesntEndTheEntry() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        await rig.settle()
        let (hold, task) = await signOutStopped(rig, reason: .user)

        rig.client.emit(.tokenRefreshed, .preview(id: WipeValues.accountA))
        await rig.settle()

        #expect(rig.ledgerOnDisk?.wipe.account == a)
        hold.open()
        await task.value
        await rig.settle()
        #expect(rig.ledgerOnDisk == nil)
    }

    // MARK: the parking date

    /// The first `begin`, not the moment the store got to it: the wait inside the SDK doesn't move the 30 days.
    @Test func aWipeParksAtTheFirstBegin() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let unsent = unsentActivity(of: a), clock = rig.clock
        let id = unsent.id
        insert(unsent, into: rig)
        rig.client.onSignOut = { clock.advance(by: .seconds(600)) }

        await rig.end(.sessionExpired)

        #expect(rig.clock.now() > WipeValues.now)
        #expect(try parkedDates(rig)[id] == WipeValues.now)
    }

    /// An older mark stays: the limit never restarts.
    @Test func anAlreadyParkedRowKeepsItsOlderDate() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let parked = unsentActivity(of: a, parkedAt: WipeValues.earlier), fresh = unsentActivity(of: a)
        let parkedID = parked.id, freshID = fresh.id
        insert(parked, into: rig)
        insert(fresh, into: rig)

        await rig.end(.sessionExpired)

        let dates = try parkedDates(rig)
        #expect(dates[parkedID] == WipeValues.earlier)
        #expect(dates[freshID] == WipeValues.now)
    }

    /// What's still owed is the earlier account's: this expiry's rows park as they do today, at their own date, and
    /// the wipe that took everything else ends the debt.
    @Test func anotherDebtsDateIsntThisExpirysAndItsRowsStillPark() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.fill([.cachedDay])
        try rig.disk.refuseDeletes(of: .cachedDay)
        await rig.end(.user)
        await rig.signIn(WipeValues.accountB)
        #expect(rig.auth.accountID == b)
        try rig.disk.allowDeletes()

        rig.clock.advance(by: .seconds(86_400))
        let unsent = unsentActivity(of: b)
        let id = unsent.id
        insert(unsent, into: rig)
        await rig.end(.sessionExpired)

        #expect(try parkedDates(rig)[id] == rig.clock.now())
        #expect(rig.ledgerOnDisk == nil)
    }

    // MARK: a ledger that fails changes nothing else

    /// A directory that can't be replaced: every write fails, and a sign-out still ends and still wipes.
    @Test func aLedgerThatCantBeWrittenStopsNothing() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        let inTheWay = rig.ledgerFile.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: inTheWay, withIntermediateDirectories: true)

        await rig.end(.user)

        #expect(rig.auth.accountID == nil)
        #expect(rig.lastUser == nil)
        try rig.disk.expectNothingLeft()
    }

    @Test func aLedgerThatCantBeWrittenStillReportsARefusal() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        try rig.disk.refuseDeletes()
        let inTheWay = rig.ledgerFile.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: inTheWay, withIntermediateDirectories: true)

        await rig.end(.user)

        #expect(rig.auth.accountID == nil)
        #expect(rig.lastUser == a)
        #expect(rig.ledgerOnDisk == nil)
    }

    /// An entry that can't be read: no wipe, the account is published as usual, and the file stays.
    @Test(arguments: [true, false])
    func anUnreadableEntryDoesNothingAtLaunch(_ signedIn: Bool) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        let garbage = Data("not an entry".utf8)
        try garbage.write(to: rig.ledgerFile)

        rig.relaunch(signedInAs: signedIn ? WipeValues.accountA : nil)
        let seen = watchWipes(rig)
        await rig.settle()

        #expect(rig.auth.accountID == (signedIn ? a : nil))
        #expect(seen.wipes.isEmpty)
        #expect(try Data(contentsOf: rig.ledgerFile) == garbage)
        #expect(try rig.disk.inFreshContext == .init(sessions: 1, exercises: 2, sets: 6))
    }

    // MARK: nothing a user can notice

    /// One launch, one sign-in, one sign-out: the same wipes as without a ledger's entry to consider.
    @Test func aCleanLedgerCostsNoWipe() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let seen = watchWipes(rig)
        rig.relaunch(signedInAs: WipeValues.accountA)
        await rig.settle()
        #expect(seen.wipes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rig.ledgerFile.path))
    }

    /// Without a file of its own a service writes nowhere the live app would read: previews and other tests stay out.
    @Test func aServiceWithoutALedgerStillWipes() async {
        let client = MockAuthClient(session: .preview(id: WipeValues.accountA))
        var wipes = 0
        let defaults = UserDefaults(suiteName: "ryft.tests.wipe.\(UUID().uuidString)") ?? .standard
        let auth = AuthService(client: client, settings: Settings(defaults: defaults), defaults: defaults,
                               wipeLocalData: { _ in wipes += 1; return true },
                               deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                               postAppleAuthorization: { _ in })
        await auth.signOut()
        #expect(wipes == 1)
    }
}
