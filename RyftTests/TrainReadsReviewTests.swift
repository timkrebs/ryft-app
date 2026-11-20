import Foundation
import SwiftUI
import Testing
@testable import Ryft

/// PR 6 review, round R1 (F-Train): Train's reads (History, the session detail, the exercise page, the plan page) go
/// through the read pipeline, write nothing for a binding that's over, change nothing when cancelled, carry the failure's
/// Details, and the Demo data switch and a finished workout retire what was read before them.
@MainActor
@Suite("R1 F-Train: Train's reads", .serialized)
struct TrainReadsReviewTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")
    private static let width: CGFloat = 390
    private let bench = MockTrain.bench.id
    /// A session of demo data's history (the platform's), not logged on the phone.
    private var platformSession: UUID { MockTrain.history[MockTrain.history.count - 1].id }
    /// The answer to a read that failed with a status and a request ID, and its Details.
    private let refused = APIError.http(400, "bad request", requestID: "rid-r1-400")
    private let refusedDetails = "HTTP 400 · Request ID rid-r1-400"

    /// The rig: a library and its outbox on one in-memory store, both on `source`, whose binding's owner a test switches
    /// as Profile's Demo data switch does (`owner.id`). The exercises are cached, as after a first refresh.
    private func rig(held: Bool = true, owner: TrainOwner? = nil)
        -> (library: TrainLibrary, outbox: TrainSyncService, store: TrainStore, source: HeldTrainSource) {
        let owner = owner ?? TrainOwner()
        let store = TrainStore(inMemory: true)
        store.cache(exercises: MockTrain.exercises)
        let source = HeldTrainSource(held: held)
        let outbox = TrainSyncService(store: store, remote: { source }, owner: { owner.id }, monitorsNetwork: false)
        outbox.gate = { _ in nil }
        return (TrainLibrary(store: store, remote: { source }, outbox: { outbox }, restore: false), outbox, store, source)
    }

    /// A finished Upper A `days` before `now`, as History's list carries it.
    private func summary(daysAgo days: Int, now: Date = .now) -> SessionSummary {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        return SessionSummary(TrainSession(title: "Upper A", startedAt: start, endedAt: start.addingTimeInterval(55 * 60),
                                           status: .completed, muscularTrimp: 85, strain: 10.4, volumeKg: 7_500, exercises: []))
    }

    /// `load` ended within two seconds (offline the pipeline sends nothing and ends at once). A load still running then is
    /// cancelled.
    private func endsAtOnce(_ load: @escaping @MainActor () async -> Void) async -> Bool {
        let done = DoneMark()
        let task = Task { @MainActor in
            await load()
            done.on = true
        }
        let ended = await eventually(timeout: .seconds(2)) { done.on }
        task.cancel()
        return ended
    }

    private func ids(_ w: HostedWindow) -> [String] { w.nodes().compactMap(\.identifier) }

    // MARK: S-1: a binding that's over writes nothing

    /// Security S-1: History's list, an exercise's history, a session, a plan and the refresh are out when the account's
    /// wipe runs; their answers (the old account's) arrive after it. None of them is written into the store or memory, and
    /// History shows nothing of the old account.
    @Test func answersAfterAWipeWriteNothingOfTheOldAccount() async throws {
        let rig = rig()
        let history = TrainHistoryViewModel(library: rig.library)
        let exercise = ExerciseDetailViewModel(exerciseID: bench, library: rig.library, clock: TestClock(now: .now))
        let session = SessionDetailViewModel(sessionID: platformSession, library: rig.library)
        let list = Task { await history.load() }
        let past = Task { await exercise.load() }
        let one = Task { await session.load() }
        let plan = Task { await rig.library.loadPlan(id: MockTrain.fullBody.id) }
        let refresh = Task { await rig.library.refresh() }
        #expect(await eventually { rig.source.allReads == 5 }, "the list, a history, a session, a plan and the plans held")

        _ = rig.store.wipe()
        rig.source.release()
        await list.value
        await past.value
        await one.value
        #expect(await plan.value.plan == nil)
        await refresh.value

        #expect(rig.store.document([SessionSummary].self, key: "train.sessions") == nil)
        #expect(rig.store.documentKeys(prefix: "train.history.").isEmpty)
        #expect(rig.library.cachedHistory(for: bench) == nil, "nothing in memory either")
        #expect(rig.store.plan(id: MockTrain.fullBody.id) == nil)
        #expect(rig.library.catalog == nil && rig.store.document(PlansOverview.self, key: "train.plans") == nil)
        #expect(rig.library.today == nil && rig.store.document(PlanToday.self, key: "train.today") == nil)
        #expect(history.sessions.isEmpty && !history.fresh, "nothing of the old account's in History")
        #expect(exercise.history == nil && !exercise.fresh)
        #expect(session.session == nil)
    }

    /// The same for Profile's Demo data switch while the reads are out: the demo's answers aren't the account's.
    @Test func answersAfterTheDemoSwitchWriteNothingOfTheOtherSide() async throws {
        let owner = TrainOwner()
        owner.id = TrainSyncService.demoOwner
        let rig = rig(owner: owner)
        let history = TrainHistoryViewModel(library: rig.library)
        let exercise = ExerciseDetailViewModel(exerciseID: bench, library: rig.library, clock: TestClock(now: .now))
        let list = Task { await history.load() }
        let past = Task { await exercise.load() }
        let plan = Task { await rig.library.loadPlan(id: MockTrain.fullBody.id) }
        #expect(await eventually { rig.source.allReads == 3 })

        owner.id = "alex-doe"
        rig.source.release()
        await list.value
        await past.value
        #expect(await plan.value.plan == nil)

        #expect(rig.store.document([SessionSummary].self, key: "train.sessions") == nil)
        #expect(rig.store.documentKeys(prefix: "train.history.").isEmpty)
        #expect(rig.library.cachedHistory(for: bench) == nil)
        #expect(rig.store.plan(id: MockTrain.fullBody.id) == nil)
        #expect(history.sessions.isEmpty && exercise.history == nil)
    }

    // MARK: B1: offline, nothing is sent and the page says so at once

    @Test func offlineHistoryEndsAtOnce() async {
        let env = AppEnvironment.test(online: false)
        let rig = rig()
        rig.library.reads = env.reads
        let empty = TrainHistoryViewModel(library: rig.library)
        #expect(await endsAtOnce { await empty.load() }, "a held read would keep the outlines")
        #expect(empty.state == .failed && !empty.isLoading, "nothing cached: the message, not outlines")
        // With the copy on this phone: the copy, said to be one.
        rig.store.saveDocument([summary(daysAgo: 3)], key: "train.sessions", at: .now.addingTimeInterval(-3_600))
        let cached = TrainHistoryViewModel(library: rig.library)
        #expect(await endsAtOnce { await cached.load() })
        #expect(cached.state == .list && cached.isOffline && !cached.fresh)
        #expect(rig.source.allReads == 0, "nothing sent")
        rig.source.release()
        withExtendedLifetime(env) {}
    }

    @Test func offlineExercisePageEndsAtOnce() async {
        let env = AppEnvironment.test(online: false)
        let rig = rig()
        rig.library.reads = env.reads
        let vm = ExerciseDetailViewModel(exerciseID: bench, library: rig.library, clock: env.clock)
        #expect(await endsAtOnce { await vm.load() })
        #expect(vm.failed && !vm.isLoading && rig.source.allReads == 0)
        rig.source.release()
        withExtendedLifetime(env) {}
    }

    @Test func offlineSessionDetailEndsAtOnce() async {
        let env = AppEnvironment.test(online: false)
        let rig = rig()
        rig.library.reads = env.reads
        let vm = SessionDetailViewModel(sessionID: platformSession, library: rig.library)
        #expect(await endsAtOnce { await vm.load() })
        #expect(vm.loaded && vm.content(locale: english).state == .failed && rig.source.allReads == 0)
        rig.source.release()
        withExtendedLifetime(env) {}
    }

    @Test func offlinePlanPageEndsAtOnceOnItsOwnLine() async {
        let env = AppEnvironment.test(online: false)
        let rig = rig()
        rig.library.reads = env.reads
        let vm = PlanDetailViewModel(planID: MockTrain.fullBody.id, library: rig.library)
        #expect(await endsAtOnce { await vm.load() })
        #expect(vm.isOffline && vm.failure == nil && vm.plan == nil, "offline: the calm line, not a failure")
        #expect(rig.source.allReads == 0)
        rig.source.release()
        withExtendedLifetime(env) {}
    }

    /// Back online, History reads again by itself (`task(id:)` on the connectivity).
    @Test func historyReadsAgainWhenTheIPhoneIsBackOnline() async throws {
        let env = AppEnvironment.test(online: false)
        let rig = rig(held: false)
        rig.library.reads = env.reads
        let view = NavigationStack { TrainHistoryView() }.environment(rig.library).environment(\.appEnvironment, env)
        try await HostedWindow.run(width: Self.width, height: 844, view) { w in
            try await w.wait("the failure, offline") { ids(w).contains("history.failure.retry") }
            #expect(rig.source.allReads == 0)
            env.connectivityMonitor.update(true)
            try await w.wait("rows, read again online") { ids(w).contains { $0.hasPrefix("history.row.") } }
        }
        withExtendedLifetime(env) {}
    }

    // MARK: S3: a cancelled read changes nothing

    @Test func aCancelledHistoryReadChangesNothing() async {
        let rig = rig()
        let vm = TrainHistoryViewModel(library: rig.library)
        let load = Task { await vm.load() }
        #expect(await eventually { rig.source.allReads == 1 })
        load.cancel()
        rig.source.release()
        await load.value
        #expect(!vm.loaded && vm.state == .loading && vm.sessions.isEmpty && !vm.fresh && vm.fetchedAt == nil)
    }

    @Test func aCancelledExerciseReadChangesNothing() async {
        let rig = rig()
        let vm = ExerciseDetailViewModel(exerciseID: bench, library: rig.library, clock: TestClock(now: .now))
        let load = Task { await vm.load() }
        #expect(await eventually { rig.source.allReads == 1 })
        load.cancel()
        rig.source.release()
        await load.value
        #expect(!vm.loaded && vm.isLoading && vm.history == nil && !vm.fresh)
    }

    // MARK: S1: the failure's Details

    @Test func aFailedReadCarriesItsStatusAndRequestID() async {
        let rig = rig(held: false)
        rig.source.failure = refused
        let history = TrainHistoryViewModel(library: rig.library)
        let exercise = ExerciseDetailViewModel(exerciseID: bench, library: rig.library, clock: TestClock(now: .now))
        let session = SessionDetailViewModel(sessionID: platformSession, library: rig.library)
        await history.load()
        await exercise.load()
        await session.load()
        #expect(history.failed && history.failureDetails == refusedDetails)
        #expect(exercise.failed && exercise.failureDetails == refusedDetails)
        #expect(session.failureDetails == refusedDetails)
        // Try again, answered: no Details left over.
        rig.source.failure = nil
        await history.refresh()
        await exercise.load(userInitiated: true)
        await session.load(userInitiated: true)
        #expect(history.failureDetails == nil && exercise.failureDetails == nil && session.failureDetails == nil)
    }

    /// The page's failure (`prefix`) with Details, and the request ID behind it.
    private func expectDetails(_ prefix: String, on page: some View) async throws {
        let rig = rig(held: false)
        rig.source.failure = refused
        let view = NavigationStack { page }.environment(rig.library)
        try await HostedWindow.run(width: Self.width, height: 1_400, bottomInset: 0, view) { w in
            try await w.wait("\(prefix)'s Try again") { ids(w).contains("\(prefix).retry") }
            let details = try #require(w.nodes().first { $0.label == "Details" }, "\(prefix): Details")
            details.activate()
            try await w.wait("\(prefix)'s request ID") { w.nodes().contains { $0.label.contains("Request ID rid-r1-400") } }
        }
    }

    @Test func historysFailureShowsItsDetails() async throws {
        try await expectDetails("history.failure", on: TrainHistoryView())
    }

    @Test func theExercisePagesFailureShowsItsDetails() async throws {
        try await expectDetails("exerciseDetail.failure", on: ExerciseDetailView(exerciseID: bench))
    }

    @Test func theSessionDetailsFailureShowsItsDetails() async throws {
        try await expectDetails("sessionDetail.failure", on: SessionDetailView(sessionID: platformSession))
    }

    // MARK: N-1: the Demo data switch

    /// Demo data on, an exercise opened; then off, before RyftApp's onChange: the history in memory was the demo's, so the
    /// account's page asks the platform rather than show it as fresh.
    @Test func theDemoSwitchRetiresTheHistoriesInMemory() async {
        let owner = TrainOwner()
        owner.id = TrainSyncService.demoOwner
        let rig = rig(held: false, owner: owner)
        #expect(await rig.library.historyRead(for: bench)?.fresh == true)
        _ = await rig.library.historyRead(for: bench)
        #expect(rig.source.reads(.history) == 1, "read once per run while the binding holds")
        owner.id = "alex-doe"
        _ = await rig.library.historyRead(for: bench)
        #expect(rig.source.reads(.history) == 2, "the demo's copy isn't the account's")
    }

    /// Demo data off (RyftApp's onChange), the account offline: neither the demo's exercise history, nor its session
    /// list, plans overview or plan day is served as the account's.
    @Test func afterTheDemoSwitchNothingOfTheDemoIsServedOffline() async {
        let owner = TrainOwner()
        owner.id = TrainSyncService.demoOwner
        let rig = rig(held: false, owner: owner)
        _ = await rig.library.historyRead(for: bench)
        _ = await rig.library.sessionsRead()
        await rig.library.refresh()
        #expect(rig.library.catalog != nil && rig.library.today != nil)

        owner.id = "alex-doe"
        rig.library.demoModeChanged()
        rig.source.failure = URLError(.notConnectedToInternet)
        let past = await rig.library.historyRead(for: bench)
        #expect(past?.value == nil && past?.fresh == false && past?.fetchedAt == nil)
        let list = await rig.library.sessionsRead()
        #expect(list?.value.isEmpty == true && list?.fetchedAt == nil)
        #expect(rig.library.catalog == nil && rig.library.today == nil)
        #expect(rig.store.document(PlansOverview.self, key: "train.plans") == nil)
        #expect(rig.store.document(PlanToday.self, key: "train.today") == nil)
        let page = ExerciseDetailViewModel(exerciseID: bench, library: rig.library, clock: TestClock(now: .now))
        await page.load()
        #expect(page.failed && page.history == nil, "the account's page: the failure, not the demo's history")
    }

    // MARK: N3: a finished workout retires the histories

    /// The platform's completion lands after Finish stopped waiting (the library wasn't told): the history read before
    /// it isn't served as fresh, the platform is asked again.
    @Test func aCompletionRetiresTheHistoriesReadBeforeIt() async {
        let rig = rig(held: false)
        _ = await rig.library.historyRead(for: bench)
        _ = await rig.library.historyRead(for: bench)
        #expect(rig.source.reads(.history) == 1)
        _ = await rig.outbox.finish(SessionFactory.empty(in: rig.store))
        #expect(await eventually { rig.outbox.lastCompletion != nil })
        _ = await rig.library.historyRead(for: bench)
        #expect(rig.source.reads(.history) == 2, "the copy in memory is from before that workout")
    }

    /// A history read out while the completion lands answers from before it: shown, not kept as fresh.
    @Test func aHistoryAnsweredAcrossACompletionIsNotKept() async {
        let rig = rig()
        let read = Task { await rig.library.historyRead(for: bench) }
        #expect(await eventually { rig.source.reads(.history) == 1 })
        _ = await rig.outbox.finish(SessionFactory.empty(in: rig.store))
        #expect(await eventually { rig.outbox.lastCompletion != nil })
        rig.source.release()
        #expect(await read.value?.fresh == true)
        _ = await rig.library.historyRead(for: bench)
        #expect(rig.source.reads(.history) == 2)
    }

    // MARK: N2, N4: one window, the app's clock

    /// `sessions()` ("Repeat last session") writes History's 90 days, not 30: the offline copy keeps the older one.
    @Test func everySessionListReadCachesHistorysWindow() async {
        let recent = summary(daysAgo: 10), older = summary(daysAgo: 60)
        let rig = TrainHistoryFixtures.rig(cached: false, list: [recent, older])
        #expect(await rig.library.sessions().map(\.id) == [recent.id, older.id])
        rig.source.fails = true
        let offline = await rig.library.sessionsRead()
        #expect(offline?.fresh == false && offline?.value.map(\.id) == [recent.id, older.id])
    }

    /// History's window ends on the app's clock's day, not the device's.
    @Test func historysWindowFollowsTheAppsClock() async throws {
        let past = Date.now.addingTimeInterval(-200 * 86_400)
        let env = AppEnvironment.test(clock: TestClock(now: past))
        let shown = summary(daysAgo: 10, now: past)
        let rig = TrainHistoryFixtures.rig(cached: false, list: [shown])
        let view = NavigationStack { TrainHistoryView() }.environment(rig.library).environment(\.appEnvironment, env)
        try await HostedWindow.run(width: Self.width, height: 844, view) { w in
            try await w.wait("the session 10 days before the clock's today") {
                ids(w).contains("history.row.\(shown.id.uuidString)")
            }
        }
        withExtendedLifetime(env) {}
    }

    // MARK: N8: the session detail's model reads nothing when it's made

    @Test func theSessionDetailReadsItsSummaryWhenItFirstDraws() {
        let rig = TrainHistoryFixtures.rig(cached: false)
        let summary = summary(daysAgo: 2)
        let vm = SessionDetailViewModel(sessionID: summary.id, library: rig.library)
        // Saved after the model was made (one of the throwaway ones SwiftUI builds each render): the kept one still finds it.
        rig.store.saveDocument([summary], key: "train.sessions")
        #expect(vm.summary?.id == summary.id)
        #expect(vm.content(locale: english).title == "Upper A")
    }
}

/// Whose requests the rig's outbox sends (`TrainSyncService.Binding.owner`): a test switches it as the Demo data switch
/// does. Alex Doe's account by default.
@MainActor
final class TrainOwner {
    var id: String? = "alex-doe"
}

@MainActor
private final class DoneMark {
    var on = false
}

/// Demo data's platform whose reads of History's pages and the plans (the session list, a session, an exercise's history,
/// a plan, the plans overview) wait at a gate while `held`, then answer as demo data does or throw `failure`. Counts the
/// reads that reached it, by kind. Everything else answers at once.
final class HeldTrainSource: TrainDataSource, @unchecked Sendable {
    enum Read: Hashable { case sessions, session, history, plan, plans }

    private let base = MockTrainSource()
    private let lock = NSLock()
    private var held: Bool
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var counts: [Read: Int] = [:]
    private var thrown: Error?

    init(held: Bool) {
        self.held = held
    }

    /// Thrown by the gated reads once they pass the gate (offline, a refusal).
    var failure: Error? {
        get { lock.withLock { thrown } }
        set { lock.withLock { thrown = newValue } }
    }

    func reads(_ kind: Read) -> Int { lock.withLock { counts[kind, default: 0] } }
    var allReads: Int { lock.withLock { counts.values.reduce(0, +) } }

    /// Opens the gate: the reads waiting go on, and later ones don't wait.
    func release() {
        let parked = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            held = false
            defer { waiting = [] }
            return waiting
        }
        for continuation in parked { continuation.resume() }
    }

    private func pass(_ kind: Read) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let open = lock.withLock { () -> Bool in
                counts[kind, default: 0] += 1
                if held { waiting.append(continuation) }
                return !held
            }
            if open { continuation.resume() }
        }
        if let error = failure { throw error }
    }

    func exercises() async throws -> [Exercise] { try await base.exercises() }
    func createExercise(_ e: Exercise) async throws -> Exercise { try await base.createExercise(e) }
    func exerciseHistory(id: UUID) async throws -> ExerciseHistory {
        try await pass(.history)
        return try await base.exerciseHistory(id: id)
    }
    func plans() async throws -> PlansOverview {
        try await pass(.plans)
        return try await base.plans()
    }
    func plan(id: UUID) async throws -> Plan {
        try await pass(.plan)
        return try await base.plan(id: id)
    }
    func savePlan(_ p: Plan) async throws -> Plan { try await base.savePlan(p) }
    func deletePlan(id: UUID) async throws { try await base.deletePlan(id: id) }
    func enroll(planID: UUID) async throws -> Enrollment { try await base.enroll(planID: planID) }
    func pauseEnrollment() async throws { try await base.pauseEnrollment() }
    func planToday() async throws -> PlanToday? { try await base.planToday() }
    func sessions(from: Date, to: Date) async throws -> [SessionSummary] {
        try await pass(.sessions)
        return try await base.sessions(from: from, to: to)
    }
    func session(id: UUID) async throws -> TrainSession {
        try await pass(.session)
        return try await base.session(id: id)
    }
    func putSession(_ s: TrainSession) async throws -> SessionPutResult { try await base.putSession(s) }
    func completeSession(id: UUID, _ body: SessionComplete) async throws -> TrainSession {
        try await base.completeSession(id: id, body)
    }
    func deleteSession(id: UUID) async throws { try await base.deleteSession(id: id) }
}
