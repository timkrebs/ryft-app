import Foundation
import SwiftData
import Testing
@testable import Ryft

// An owed wipe finishes before the store opens, and the only code that deletes a live store runs on nothing else.
// Synthetic values only.

private typealias Wipe = AuthService.Wipe

enum WipeEntries {
    /// Exactly what a W1 build wrote: no `endsOwnSession`.
    static func fromAW1Build(reason: AuthService.SignOutReason, account: String, since: Date) -> Data {
        let json: String
        switch reason {
        case .user: json = #"{"user":{}}"#
        case .sessionExpired: json = #"{"sessionExpired":{}}"#
        case .accountDeleted(let background): json = #"{"accountDeleted":{"background":\#(background)}}"#
        }
        return Data(#"""
        {"wipe":{"reason":\#(json),"account":"\#(account)","since":\#(since.timeIntervalSinceReferenceDate),\#
        "storeOnly":false},"deviceStepsDone":false,"scrubOnly":false}
        """#.utf8)
    }
}

private let limit = ActivityStore.parkingLimit

// MARK: - the launch table

@MainActor
struct WipeResumeTableTests {
    private let a = "account-a", b = "account-b"
    private let since = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var within: Date { since.addingTimeInterval(3_600) }
    private var past: Date { since.addingTimeInterval(limit + 1) }

    private func owed(_ reason: AuthService.SignOutReason?, account: String? = "account-a", scrubOnly: Bool = false,
                      fromAW1Build: Bool = false) -> OwedWipe {
        OwedWipe(wipe: Wipe(reason: reason, account: account, since: since), scrubOnly: scrubOnly,
                 endsOwnSession: !fromAW1Build)
    }

    @Test(arguments: [AuthService.SignOutReason?.none, .user, .accountDeleted(background: true),
                      .accountDeleted(background: false)])
    func withoutParking(_ reason: AuthService.SignOutReason?) {
        let entry = owed(reason)
        #expect(WipeResume.decide(entry, stored: nil, now: within) == .wipeNow(narrow: false, endSession: false))
        #expect(WipeResume.decide(entry, stored: b, now: within) == .wipeNow(narrow: false, endSession: false))
        #expect(WipeResume.decide(entry, stored: a, now: within) == .wipeNow(narrow: false, endSession: true))
    }

    @Test func parkingWithinItsLimit() {
        let entry = owed(.sessionExpired)
        #expect(WipeResume.decide(entry, stored: nil, now: within) == .wipeAfterFirstFrame(endSession: false))
        #expect(WipeResume.decide(entry, stored: a, now: within) == .wipeAfterFirstFrame(endSession: true))
        #expect(WipeResume.decide(entry, stored: b, now: within) == .wipeNow(narrow: true, endSession: false))
    }

    @Test func parkingPastItsLimit() {
        let entry = owed(.sessionExpired)
        #expect(WipeResume.decide(entry, stored: nil, now: past) == .wipeNow(narrow: true, endSession: false))
        #expect(WipeResume.decide(entry, stored: a, now: past) == .wipeNow(narrow: true, endSession: true))
        #expect(WipeResume.decide(entry, stored: b, now: past) == .wipeNow(narrow: true, endSession: false))
    }

    /// `since + 30 days` itself is inside, one second on isn't, and a clock behind `since` expires nothing.
    @Test func theLimitsEdge() {
        let entry = owed(.sessionExpired)
        #expect(WipeResume.decide(entry, stored: nil, now: since.addingTimeInterval(limit)) == .wipeAfterFirstFrame(endSession: false))
        #expect(WipeResume.decide(entry, stored: nil, now: since.addingTimeInterval(limit + 1))
            == .wipeNow(narrow: true, endSession: false))
        #expect(WipeResume.decide(entry, stored: nil, now: since.addingTimeInterval(-(limit + 1)))
            == .wipeAfterFirstFrame(endSession: false))
    }

    @Test func aScrub() {
        let entry = owed(nil, scrubOnly: true)
        #expect(WipeResume.decide(entry, stored: nil, now: within) == .scrub)
        #expect(WipeResume.decide(entry, stored: a, now: within) == .forget)
        #expect(WipeResume.decide(entry, stored: b, now: within) == .forget)
    }

    /// The rows under a W1 build's entry may be live work, however old it is, unless the account is gone.
    @Test(arguments: [AuthService.SignOutReason?.none, .user, .sessionExpired])
    func aW1BuildsEntryOverItsOwnSessionIsForgotten(_ reason: AuthService.SignOutReason?) {
        let entry = owed(reason, fromAW1Build: true)
        #expect(WipeResume.decide(entry, stored: a, now: within) == .forget)
        #expect(WipeResume.decide(entry, stored: a, now: past) == .forget)
    }

    @Test(arguments: [true, false])
    func aW1BuildsDeletionStillResumes(_ background: Bool) {
        let entry = owed(.accountDeleted(background: background), fromAW1Build: true)
        #expect(WipeResume.decide(entry, stored: a, now: past) == .wipeNow(narrow: false, endSession: true))
    }

    /// Only over its own session: anywhere else the rows aren't that session's, and the table applies as ever.
    @Test func aW1BuildsEntryWithoutItsOwnSessionResumes() {
        let user = owed(.user, fromAW1Build: true), expiry = owed(.sessionExpired, fromAW1Build: true)
        #expect(WipeResume.decide(user, stored: nil, now: within) == .wipeNow(narrow: false, endSession: false))
        #expect(WipeResume.decide(user, stored: b, now: within) == .wipeNow(narrow: false, endSession: false))
        #expect(WipeResume.decide(expiry, stored: nil, now: within) == .wipeAfterFirstFrame(endSession: false))
        #expect(WipeResume.decide(expiry, stored: b, now: within) == .wipeNow(narrow: true, endSession: false))
    }

    /// An entry that doesn't know its account has none to match.
    @Test func anEntryWithoutAnAccount() {
        let entry = owed(.user, account: nil)
        #expect(WipeResume.decide(entry, stored: a, now: within) == .wipeNow(narrow: false, endSession: false))
        #expect(WipeResume.decide(entry, stored: nil, now: within) == .wipeNow(narrow: false, endSession: false))
    }
}

// MARK: - the replace, on a folder

/// A store's files with known bytes, and the rest of what shares its folder.
private final class StoreFolder {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ryft-store-reset-\(UUID().uuidString)")
    var group: URL { root.appendingPathComponent("group/Library/Application Support", isDirectory: true) }
    var app: URL { root.appendingPathComponent("app/Library/Application Support", isDirectory: true) }
    var store: URL { group.appendingPathComponent("Train.store") }
    var bystander: URL { group.appendingPathComponent("readiness.json") }
    var external: URL { group.appendingPathComponent(".Train_SUPPORT/_EXTERNAL_DATA/payload") }
    var orphan: URL { app.appendingPathComponent("Train.store") }
    var locations: OrphanedStoreCleanup.Locations {
        .init(orphanFolder: app, groupContainer: root.appendingPathComponent("group", isDirectory: true))
    }

    init(orphan hasOrphan: Bool = false) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: external.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        for name in ["Train.store", "Train.store-wal", "Train.store-shm", "readiness.json"] {
            try Data(name.utf8).write(to: group.appendingPathComponent(name))
        }
        try Data("payload".utf8).write(to: external)
        if hasOrphan { try Data("orphan".utf8).write(to: orphan) }
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: group.path)
        try? FileManager.default.removeItem(at: root)
    }

    /// Every file under the folder, with its bytes.
    var contents: [String: Data] {
        var found: [String: Data] = [:]
        let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let item = items?.nextObject() as? URL {
            if let data = try? Data(contentsOf: item) { found[item.path] = data }
        }
        return found
    }

    var storeIsGone: Bool {
        !["Train.store", "Train.store-wal", "Train.store-shm", ".Train_SUPPORT"].contains {
            FileManager.default.fileExists(atPath: group.appendingPathComponent($0).path)
        }
    }
}

struct StoreResetTests {
    private let since = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func owed(_ reason: AuthService.SignOutReason?, scrubOnly: Bool = false) -> OwedWipe {
        OwedWipe(wipe: Wipe(reason: reason, account: "account-a", since: since), scrubOnly: scrubOnly)
    }

    @Test func noEntryLeavesEveryByte() throws {
        let folder = try StoreFolder(orphan: true)
        let before = folder.contents
        let outcome = StoreReset.run(entry: nil, store: folder.store, orphans: folder.locations, now: since)
        #expect(outcome == .init())
        #expect(folder.contents == before)
    }

    @Test(arguments: [limit, -limit - 1, 0])
    func parkingWithinItsLimitLeavesEveryByte(_ age: TimeInterval) throws {
        let folder = try StoreFolder(orphan: true)
        let before = folder.contents
        let outcome = StoreReset.run(entry: owed(.sessionExpired), store: folder.store, orphans: folder.locations,
                                     now: since.addingTimeInterval(age))
        #expect(!outcome.replaced)
        #expect(folder.contents == before)
    }

    @Test func parkingPastItsLimitIsReplaced() throws {
        let folder = try StoreFolder()
        let outcome = StoreReset.run(entry: owed(.sessionExpired), store: folder.store, orphans: folder.locations,
                                     now: since.addingTimeInterval(limit + 1))
        #expect(outcome.replaced)
        #expect(folder.storeIsGone)
    }

    /// The database, its log and index, and external storage with what's in it; what shares the folder stays.
    @Test(arguments: [AuthService.SignOutReason?.none, .user, .accountDeleted(background: false)])
    func anEntryWithoutParkingTakesTheFiles(_ reason: AuthService.SignOutReason?) throws {
        let folder = try StoreFolder()
        let outcome = StoreReset.run(entry: owed(reason), store: folder.store, orphans: folder.locations, now: since)
        #expect(outcome.replaced && outcome.files == 4 && outcome.failures == 0)
        #expect(folder.storeIsGone)
        #expect(FileManager.default.fileExists(atPath: folder.bystander.path))
    }

    @Test func aScrubTakesTheFiles() throws {
        let folder = try StoreFolder()
        let entry = owed(.sessionExpired, scrubOnly: true)
        #expect(StoreReset.run(entry: entry, store: folder.store, orphans: folder.locations, now: since).replaced)
        #expect(folder.storeIsGone)
    }

    /// Run twice, or killed halfway: what's already gone isn't a failure.
    @Test func runningAgainIsHarmless() throws {
        let folder = try StoreFolder()
        StoreReset.run(entry: owed(.user), store: folder.store, orphans: folder.locations, now: since)
        let again = StoreReset.run(entry: owed(.user), store: folder.store, orphans: folder.locations, now: since)
        #expect(again.replaced && again.files == 0 && again.failures == 0)
    }

    @Test func theAppContainersCopyGoesToo() throws {
        let folder = try StoreFolder(orphan: true)
        let outcome = StoreReset.run(entry: owed(.user), store: folder.store, orphans: folder.locations, now: since)
        #expect(outcome.orphan?.decision == .delete)
        #expect(!FileManager.default.fileExists(atPath: folder.orphan.path))
    }

    /// `OrphanedStoreCleanup.decide`'s doubts count here too: the wipe after the replace still catches a copy.
    @Test func aCopyInDoubtStays() throws {
        let folder = try StoreFolder(orphan: true)
        let noGroup = OrphanedStoreCleanup.Locations(orphanFolder: folder.app, groupContainer: nil)
        let outcome = StoreReset.run(entry: owed(.user), store: folder.store, orphans: noGroup, now: since)
        #expect(outcome.replaced && outcome.orphan?.decision == .keep(.noGroupContainer))
        #expect(FileManager.default.fileExists(atPath: folder.orphan.path))
    }

    /// Nothing else is ever a store: a store in memory says `/dev/null`.
    @Test(arguments: ["/dev/null", "/tmp/ryft-store-reset/Other.store"])
    func onlyTheStoresOwnFile(_ path: String) throws {
        let folder = try StoreFolder()
        let outcome = StoreReset.run(entry: owed(.user), store: URL(fileURLWithPath: path), orphans: folder.locations, now: since)
        #expect(!outcome.replaced)
    }

    @Test func onlyAFile() throws {
        let folder = try StoreFolder()
        let remote = try #require(URL(string: "https://example.com/Train.store"))
        #expect(!StoreReset.run(entry: owed(.user), store: remote, orphans: folder.locations, now: since).replaced)
    }

    /// A file that can't go is counted, and the launch goes on: the wipe still runs.
    @Test func aFileThatWontGoIsCounted() throws {
        let folder = try StoreFolder()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.group.path)
        let outcome = StoreReset.run(entry: owed(.user), store: folder.store, orphans: folder.locations, now: since)
        #expect(outcome.replaced && outcome.failures == 4)
    }
}

// MARK: - a launch

@MainActor
struct OwedWipeLaunchTests {
    private let a = WipeValues.accountA.uuidString, b = WipeValues.accountB.uuidString
    nonisolated private static let noParking: [AuthService.SignOutReason] = [.user, .accountDeleted(background: false)]

    enum Stored: CaseIterable { case none, own, another }

    private func accountID(_ stored: Stored) -> UUID? {
        switch stored {
        case .none: return nil
        case .own: return WipeValues.accountA
        case .another: return WipeValues.accountB
        }
    }

    /// What a kill leaves: written down, and no attempt yet.
    private func owe(_ rig: WipingAuth, _ reason: AuthService.SignOutReason) {
        WipeLedger(file: rig.ledgerFile).begin(Wipe(reason: reason, account: a), at: rig.clock.now())
    }

    private func inode(_ rig: WipingAuth) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: rig.disk.url.path)
        return try #require(attributes[.systemFileNumber] as? Int)
    }

    /// A row a session expiry parks, and its chunk.
    @discardableResult
    private func unsentRow(_ rig: WipingAuth) -> UUID {
        let row = LocalActivity(account: a, sport: .running, origin: .manual, start: WipeValues.earlier, end: WipeValues.now,
                                movingSec: 1_800, localRevision: 2, confirmedRevision: 1, createdAt: WipeValues.earlier)
        let chunk = ActivityTrackChunk(activityID: row.id, account: a, seq: 0, kind: .profile, data: Data([1]), count: 1,
                                       first: WipeValues.earlier, last: WipeValues.now)
        rig.disk.store.context.insert(row)
        rig.disk.store.context.insert(chunk)
        rig.disk.store.save()
        return row.id
    }

    private func parkedAt(_ id: UUID, _ rig: WipingAuth) throws -> Date? {
        let rows = try ModelContext(rig.disk.store.container).fetch(FetchDescriptor<LocalActivity>())
        return try #require(rows.first { $0.id == id }).parkedAt
    }

    // MARK: every ending

    /// Every table, on every row of the launch table, however the kill left the session.
    @Test(arguments: WipeValues.endings, Stored.allCases)
    func everyEndingEndsWithEveryTableEmpty(_ ending: AuthService.SignOutReason, _ stored: Stored) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.fill()
        rig.disk.session(checked: true)
        owe(rig, ending)

        rig.relaunch(signedInAs: accountID(stored))
        await rig.firstFrame()

        #expect(try rig.disk.inFile.values.allSatisfy { $0 == 0 })
        #expect(rig.ledgerOnDisk == nil)
        #expect(rig.auth.accountID == (stored == .another ? b : nil))
        #expect(rig.lastUser == (stored == .another ? b : nil))
    }

    @Test(arguments: noParking)
    func theReplaceBeatsTheTrigger(_ ending: AuthService.SignOutReason) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.fill()
        try rig.disk.refuseDeletes()
        await rig.end(ending)
        #expect(rig.ledgerOnDisk?.deviceStepsDone == true, "refused, and written down")

        rig.relaunch(signedInAs: nil)

        #expect(try rig.disk.inFile.values.allSatisfy { $0 == 0 })
        #expect(rig.ledgerOnDisk == nil)
    }

    /// Past the limit a parked wipe goes the same way, which is what ends a refusal that parking can't replace.
    @Test func theReplaceBeatsTheTriggerPastTheLimit() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.fill()
        try rig.disk.refuseDeletes()
        await rig.end(.sessionExpired)
        rig.clock.advance(by: .seconds(limit + 1))

        rig.relaunch(signedInAs: nil)

        #expect(try rig.disk.inFile.values.allSatisfy { $0 == 0 })
        #expect(rig.ledgerOnDisk == nil)
    }

    /// The other side of it: within the limit nothing gets past a refusal, and the entry stays.
    @Test func aRefusedParkingStaysOwed() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.fill()
        try rig.disk.refuseDeletes()
        await rig.end(.sessionExpired)

        rig.relaunch(signedInAs: nil)
        await rig.firstFrame()

        #expect(rig.ledgerOnDisk?.wipe.parking == a)
        #expect(rig.lastUser == a)
        #expect(try rig.disk.inFile[.localSet] == 1)
    }

    // MARK: no replace

    @Test(arguments: [true, false])
    func noEntryChangesNothing(_ signedIn: Bool) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        let file = try inode(rig)

        rig.relaunch(signedInAs: signedIn ? WipeValues.accountA : nil)
        #expect(await rig.firstFrame() == false)

        #expect(rig.wipes.isEmpty)
        #expect(try inode(rig) == file)
        #expect(try rig.disk.inFreshContext == .init(sessions: 1, exercises: 2, sets: 6))
    }

    @Test(arguments: [Optional<UUID>.none, WipeValues.accountA])
    func anUndecodableEntryReplacesNothing(_ stored: UUID?) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        let garbage = Data("not an entry".utf8), file = try inode(rig)
        try garbage.write(to: rig.ledgerFile)

        rig.relaunch(signedInAs: stored)
        #expect(await rig.firstFrame() == false)

        #expect(rig.wipes.isEmpty)
        #expect(try inode(rig) == file)
        #expect(try Data(contentsOf: rig.ledgerFile) == garbage)
        #expect(rig.auth.accountID == stored?.uuidString)
    }

    // MARK: parking

    @Test func aParkingResumeKeepsItsRowsAtTheFirstDate() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let id = unsentRow(rig)
        rig.disk.fill([.cachedDay])
        owe(rig, .sessionExpired)
        let since = rig.clock.now(), file = try inode(rig)

        rig.clock.advance(by: .seconds(86_400))
        rig.relaunch(signedInAs: nil)
        #expect(rig.wipes.isEmpty, "not before the first frame")
        #expect(rig.ledgerOnDisk != nil)
        #expect(await rig.firstFrame())

        #expect(try inode(rig) == file, "no replace")
        #expect(try parkedAt(id, rig) == since)
        #expect(try rig.disk.inFile[.activityTrackChunk] == 1)
        #expect(try rig.disk.inFile[.cachedDay] == 0)
        #expect(rig.ledgerOnDisk == nil)
    }

    @Test func aParkingResumePastTheLimitIsAReplace() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        unsentRow(rig)
        owe(rig, .sessionExpired)
        let file = try inode(rig)

        rig.clock.advance(by: .seconds(limit + 1))
        rig.relaunch(signedInAs: nil)

        #expect(try inode(rig) != file)
        #expect(try rig.disk.inFile[.localActivity] == 0)
        #expect(try rig.disk.inFile[.activityTrackChunk] == 0)
        #expect(rig.ledgerOnDisk == nil, "narrowed, and done before anything ran")
    }

    /// A clock put back: nothing expires, and the rows still carry the first date, not the clock's.
    @Test func aClockBehindTheDateExpiresNothing() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let id = unsentRow(rig)
        owe(rig, .sessionExpired)
        let since = rig.clock.now(), file = try inode(rig)

        rig.clock.set(since.addingTimeInterval(-(limit + 1)))
        rig.relaunch(signedInAs: nil)
        #expect(await rig.firstFrame())

        #expect(try inode(rig) == file)
        #expect(try parkedAt(id, rig) == since)
        #expect(rig.ledgerOnDisk == nil)
    }

    /// Another account's stored session: nothing parks for it, so the rows go and the entry's reason with them.
    @Test func anotherAccountsSessionNarrowsAParking() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        unsentRow(rig)
        owe(rig, .sessionExpired)
        let file = try inode(rig)

        rig.relaunch(signedInAs: WipeValues.accountB)

        #expect(rig.wipes.map(\.parking) == [nil])
        #expect(try inode(rig) != file)
        #expect(try rig.disk.inFile[.localActivity] == 0)
        #expect(rig.auth.accountID == b)
    }

    // MARK: the app container

    /// A real store at the old path. SwiftData would copy it into the empty group folder as the store opens.
    @Test func withAnAppContainerCopyNeitherStoreHoldsARow() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.fill()
        try FileManager.default.createDirectory(at: rig.disk.appContainer, withIntermediateDirectories: true)
        let oldFile = rig.disk.appContainer.appendingPathComponent("Train.store")
        do {
            let old = TrainStore(url: oldFile)
            WipedTable.cachedDay.insertRow(into: old.context)
            old.save()
            withExtendedLifetime(old) {}
        }
        owe(rig, .user)

        rig.relaunch(signedInAs: nil)

        #expect(try rig.disk.inFile.values.allSatisfy { $0 == 0 })
        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
        let reopened = TrainStore(url: oldFile)
        let rows = try reopened.context.fetchCount(FetchDescriptor<CachedDay>())
        #expect(withExtendedLifetime(reopened) { rows } == 0)
    }

    // MARK: the device steps

    /// A permanent refusal doesn't restart the anchors and the backfill on every launch.
    @Test(arguments: [Optional<UUID>.none, WipeValues.accountB])
    func aRefusalThatLastsRunsTheDeviceStepsOnce(_ stored: UUID?) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.wipesAnswer = false
        owe(rig, .user)

        for _ in 0..<3 {
            rig.relaunch(signedInAs: stored)
            await rig.firstFrame()
        }

        #expect(rig.wipes.count >= 3)
        #expect(rig.wipes.filter { !$0.storeOnly }.count == 1)
        #expect(rig.wipes.first?.storeOnly == false)
        #expect(rig.ledgerOnDisk?.deviceStepsDone == true)
    }

    /// The same for one refused while the app ran: the launch is already a retry.
    @Test func aRefusedSignOutsRetryIsStoreOnly() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.wipesAnswer = false
        await rig.end(.user)
        rig.relaunch(signedInAs: nil)
        #expect(rig.wipes.map(\.storeOnly) == [false, true])
    }

    /// Done for one account says nothing about the next one's anchors and defaults.
    @Test func anotherAccountsDeviceStepsStillRun() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.wipesAnswer = false
        await rig.end(.user)
        await rig.signIn(WipeValues.accountB)
        #expect(rig.wipes.last?.account == a && rig.wipes.last?.storeOnly == true, "A's again, by the kept id")

        await rig.end(.user)
        #expect(rig.wipes.last?.account == b && rig.wipes.last?.storeOnly == false)
    }

    @Test func aRetryRunsOnlyTheStoreStep() {
        var ran: [String] = []
        let answer = AuthService.steps(of: Wipe(reason: .user, account: a, storeOnly: true), before: { ran.append("before") },
                                       store: { _ in ran.append("store"); return false }, after: { ran.append("after") })
        #expect(ran == ["store"])
        #expect(!answer)
    }

    @Test func aFirstPassRunsEveryStepInOrder() {
        var ran: [String] = []
        let answer = AuthService.steps(of: Wipe(reason: .user, account: a), before: { ran.append("before") },
                                       store: { _ in ran.append("store"); return true }, after: { ran.append("after") })
        #expect(ran == ["before", "store", "after"])
        #expect(answer)
    }

    // MARK: after a replace

    private func deletions(during launch: () -> Void, in rig: WipingAuth) -> Int {
        var saves: [(context: ObjectIdentifier?, deleted: Int)] = []
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { note in
            let key = ModelContext.NotificationKey.deletedIdentifiers.rawValue
            saves.append(((note.object as? ModelContext).map(ObjectIdentifier.init),
                          (note.userInfo?[key] as? [PersistentIdentifier])?.count ?? 0))
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        launch()
        let context = ObjectIdentifier(rig.disk.store.context)
        return saves.filter { $0.context == context }.map(\.deleted).reduce(0, +)
    }

    @Test func aResumeAfterAReplaceDeletesNoObjects() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        owe(rig, .user)
        let deleted = deletions(during: { rig.relaunch(signedInAs: nil) }, in: rig)
        #expect(rig.wipes.count == 1, "the wipe still ran")
        #expect(deleted == 0)
    }

    /// The control for that test, and what a launch falls back to when the store opens first: `forStoreStep` is nil, so
    /// nothing is replaced, and the object wipe does the work.
    @Test func aStoreOpenedFirstReplacesNothing() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        owe(rig, .user)
        let file = try inode(rig)
        let deleted = deletions(during: { rig.relaunchWithTheStoreFirst(signedInAs: nil) }, in: rig)
        #expect(deleted == 9)
        #expect(try inode(rig) == file)
        #expect(rig.ledgerOnDisk == nil)
        try rig.disk.expectNothingLeft()
    }

    /// Neither a stale entry nor a scrub with a session arms the store step.
    @Test func aStoreOpenedFirstTakesNoLiveWork() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        try WipeEntries.fromAW1Build(reason: .user, account: a, since: WipeValues.earlier).write(to: rig.ledgerFile)
        rig.relaunchWithTheStoreFirst(signedInAs: WipeValues.accountA)
        #expect(try rig.disk.inFreshContext == .init(sessions: 1, exercises: 2, sets: 6))
    }

    // MARK: a session a kill left stored

    /// The account stays on screen for nothing: not published, while the SDK's call is still running and afterwards.
    @Test(arguments: WipeValues.endings)
    func anInterruptedSignOutIsntPublished(_ ending: AuthService.SignOutReason) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        owe(rig, ending)

        let hold = Hold()
        rig.relaunch(signedInAs: WipeValues.accountA) { await hold.wait() }
        let client = rig.client
        #expect(await eventually { client.signOutCount == 1 })
        #expect(rig.auth.accountID == nil)
        #expect(rig.auth.state == .signedOut)

        hold.open()
        #expect(await eventually { client.currentSession == nil })
        await rig.firstFrame()

        #expect(rig.auth.accountID == nil)
        #expect(rig.auth.state == .signedOut)
        #expect(rig.client.signOutCount == 1)
        #expect(rig.ledgerOnDisk == nil)
        #expect(rig.lastUser == nil)
        #expect(try rig.disk.inFreshContext == .none)
    }

    /// What a session of the same account does while its sign-out runs doesn't bring it back.
    @Test func noEventOfTheEndingSessionPublishesIt() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        owe(rig, .user)
        let hold = Hold()
        rig.relaunch(signedInAs: WipeValues.accountA) { await hold.wait() }
        let client = rig.client
        #expect(await eventually { client.signOutCount == 1 })

        client.emit(.tokenRefreshed, .preview(id: WipeValues.accountA))
        await rig.settle()
        #expect(rig.auth.accountID == nil)

        hold.open()
        await rig.settle()
        #expect(rig.auth.accountID == nil)
    }

    /// Only a session of its own ends: another account is published as usual, with no call to the SDK.
    @Test func anotherAccountsSessionIsntEnded() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        owe(rig, .user)
        rig.relaunch(signedInAs: WipeValues.accountB)
        await rig.settle()
        #expect(rig.auth.accountID == b)
        #expect(rig.client.signOutCount == 0)
        #expect(rig.lastUser == b)
    }

    // MARK: what a W1 build left

    /// The account went on working over the entry for weeks: it stays signed in with its rows, nothing is wiped, and
    /// this launch resolves the entry.
    @Test(arguments: [AuthService.SignOutReason.user, .sessionExpired], [86_400.0, limit + 1])
    func aStaleEntryTakesNoLiveWork(_ reason: AuthService.SignOutReason, _ age: TimeInterval) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        let file = try inode(rig)
        try WipeEntries.fromAW1Build(reason: reason, account: a, since: rig.clock.now()).write(to: rig.ledgerFile)
        rig.clock.advance(by: .seconds(age))

        rig.relaunch(signedInAs: WipeValues.accountA)
        #expect(await rig.firstFrame() == false)

        #expect(rig.auth.accountID == a)
        #expect(rig.wipes.isEmpty)
        #expect(rig.client.signOutCount == 0)
        #expect(rig.ledgerOnDisk == nil)
        #expect(!FileManager.default.fileExists(atPath: rig.ledgerFile.path))
        #expect(try inode(rig) == file)
        #expect(try rig.disk.inFreshContext == .init(sessions: 1, exercises: 2, sets: 6))
    }

    /// The account is gone on the server, so however long the session outlived that, its rows go.
    @Test(arguments: [true, false], [86_400.0, limit + 1])
    func aW1BuildsDeletionResumes(_ background: Bool, _ age: TimeInterval) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        let file = try inode(rig)
        let reason = AuthService.SignOutReason.accountDeleted(background: background)
        try WipeEntries.fromAW1Build(reason: reason, account: a, since: rig.clock.now()).write(to: rig.ledgerFile)
        rig.clock.advance(by: .seconds(age))

        rig.relaunch(signedInAs: WipeValues.accountA)
        await rig.settle()

        #expect(rig.auth.accountID == nil)
        #expect(rig.client.signOutCount == 1)
        #expect(rig.ledgerOnDisk == nil)
        #expect(try inode(rig) != file)
        #expect(try rig.disk.inFreshContext == .none)
    }

    /// Without its own session a W1 build's entry is a debt like any other.
    @Test func aW1BuildsEntryWithNoSessionResumes() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        try WipeEntries.fromAW1Build(reason: .user, account: a, since: rig.clock.now()).write(to: rig.ledgerFile)
        rig.relaunch(signedInAs: nil)
        #expect(rig.ledgerOnDisk == nil)
        #expect(try rig.disk.inFreshContext == .none)
    }

    // MARK: a scrub

    /// The wipe succeeded, so the account's id went with it.
    private func owesAScrub(_ rig: WipingAuth) {
        owe(rig, .user)
        WipeLedger(file: rig.ledgerFile).update { $0.scrubOnly = true }
        rig.defaults.removeObject(forKey: AccountScope.defaultsKey)
    }

    @Test func aScrubReplacesWithNoWipe() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        owesAScrub(rig)
        let file = try inode(rig)

        rig.relaunch(signedInAs: nil)
        #expect(try inode(rig) != file)
        #expect(rig.ledgerOnDisk?.scrubOnly == true, "until the store is open")
        #expect(await rig.firstFrame() == false)

        #expect(rig.wipes.isEmpty)
        #expect(rig.ledgerOnDisk == nil)
        #expect(try rig.disk.inFreshContext == .none)
    }

    /// The session's rows are live: nothing goes, and the entry's over.
    @Test(arguments: [WipeValues.accountA, WipeValues.accountB])
    func aScrubWithASessionEnds(_ stored: UUID) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        owesAScrub(rig)
        let file = try inode(rig)

        rig.relaunch(signedInAs: stored)
        await rig.settle()

        #expect(rig.auth.accountID == stored.uuidString)
        #expect(rig.client.signOutCount == 0)
        #expect(rig.wipes.isEmpty)
        #expect(rig.ledgerOnDisk == nil)
        #expect(try inode(rig) == file)
    }

    // MARK: the retry

    /// Whatever the launch did, the first frame hears of it once, for the reminders.
    @Test func aResumeIsReportedOnce() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        owe(rig, .user)
        rig.relaunch(signedInAs: nil)
        #expect(await rig.firstFrame())
        #expect(await rig.firstFrame() == false)
    }

    /// Another account published: the first frame still follows it up, and the session isn't touched.
    @Test func aResumeUnderAnotherAccountIsReported() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        owe(rig, .user)
        rig.relaunch(signedInAs: WipeValues.accountB)
        #expect(await rig.firstFrame())
        #expect(rig.auth.accountID == b)
    }

    /// One try per process: a refusal doesn't get better for being asked again, and a wiped context is poisoned.
    @Test func aRefusedParkingIsTriedOncePerProcess() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.wipesAnswer = false
        owe(rig, .sessionExpired)
        rig.relaunch(signedInAs: nil)
        #expect(await rig.firstFrame())
        #expect(await rig.firstFrame() == false)
        #expect(rig.wipes.count == 1)
    }

    /// A launch that already tried leaves nothing for the first frame to try again.
    @Test func aRefusedLaunchWipeIsntTriedAgainAtTheFirstFrame() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.wipesAnswer = false
        owe(rig, .user)
        rig.relaunch(signedInAs: nil)
        await rig.firstFrame()
        #expect(rig.wipes.count == 1)
    }

    /// The nightly compaction: a wipe refused while the app ran, with no launch in between.
    @Test func theNightlyRetryFinishesARefusedSignOut() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.wipesAnswer = false
        await rig.end(.user)
        #expect(rig.ledgerOnDisk != nil)

        rig.wipesAnswer = true
        #expect(await rig.firstFrame())

        #expect(rig.wipes.map(\.storeOnly) == [false, true])
        #expect(rig.ledgerOnDisk == nil)
        #expect(rig.lastUser == nil)
    }

    /// Its rows are its own: a retry never runs under a published session.
    @Test func noRetryOverAPublishedSession() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.wipesAnswer = false
        await rig.end(.user)
        await rig.signIn(WipeValues.accountB)
        let wipes = rig.wipes.count

        rig.wipesAnswer = true
        #expect(await rig.firstFrame() == false)

        #expect(rig.wipes.count == wipes)
        #expect(rig.ledgerOnDisk != nil)
    }

    @Test func aFailedRetryKeepsTheAccountsID() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.wipesAnswer = false
        owe(rig, .user)
        rig.relaunch(signedInAs: nil)
        #expect(rig.lastUser == a)
    }

    // MARK: bedtime

    private func reminders(_ notifier: MockNotifier) -> [String] {
        notifier.requests.map(\.identifier).filter { $0.hasPrefix(BedtimePlanner.reminderPrefix) }
    }

    /// A's reminder, scheduled by the app before the kill.
    private func scheduleReminders(_ rig: WipingAuth, notifier: MockNotifier, clock: TestClock) async throws {
        clock.set(try #require(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: clock.now())))
        let planner = BedtimePlanner(state: AppState(env: .test(clock: clock, notifier: notifier, auth: rig.auth)),
                                     alarms: MockWakeAlarms())
        var schedule = SleepSchedule.default
        schedule.reminderOn = true
        await planner.update(schedule)
        #expect(!reminders(notifier).isEmpty)
    }

    /// nil → nil fires no `onChange`, so nothing else would take them. As `RyftApp`'s first-frame task does it.
    @Test(arguments: WipeValues.endings)
    func aResumeTakesTheAccountsReminders(_ ending: AuthService.SignOutReason) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let notifier = MockNotifier(), clock = TestClock(), alarms = MockWakeAlarms()
        try await scheduleReminders(rig, notifier: notifier, clock: clock)
        owe(rig, ending)

        rig.relaunch(signedInAs: nil)
        let planner = BedtimePlanner(state: AppState(env: .test(clock: clock, notifier: notifier, auth: rig.auth)),
                                     alarms: alarms)
        if await rig.firstFrame() { await planner.accountChanged() }

        #expect(reminders(notifier).isEmpty)
    }

    /// The control: without a resume the same launch leaves them alone.
    @Test func aCleanLaunchLeavesTheReminders() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        let notifier = MockNotifier(), clock = TestClock()
        try await scheduleReminders(rig, notifier: notifier, clock: clock)

        rig.relaunch(signedInAs: WipeValues.accountA)
        #expect(await rig.firstFrame() == false)
        #expect(!reminders(notifier).isEmpty)
    }

    // MARK: inside `AppEnvironment.live`

    /// A launch wipe runs inside `AppEnvironment.live`'s `swift_once` and the default owner reads that same value: read
    /// here, the app crashes at launch on every launch, entry still owed.
    @Test func anAccountChangeDoesntReadTheOwnerBeforeItReturns() async throws {
        var reads = 0
        let service = TrainSyncService(store: TrainStore(inMemory: true), remote: { MockPlatformAPI() }, owner: {
            reads += 1
            return nil
        }, monitorsNetwork: false)
        #expect(await eventually { reads == 1 }, "its own first count")

        service.accountChanged()
        #expect(reads == 1)
        #expect(await eventually { reads == 2 })
    }
}
