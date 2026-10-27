// The training import's batch endpoint in memory (design §7, the draft until C2): demo data, previews and tests.
// `MockPlatformAPI` forwards to it, so its `failure`, `failNext` and `-RyftFault` apply unchanged, and it lists what
// was imported in its sessions and plans.
import Foundation

/// Behaves like the platform brief: plans and sessions upsert by id; identical content answers `unchanged`, different
/// content `updated`; `rejectIDs` answer `rejected` with a reason; more than 50 sessions or 5 plans, or a body over
/// 1 MiB, is a `413`.
final class MockTrainImportSource: TrainImportAPI, @unchecked Sendable {
    /// One request as the platform received it.
    struct Request: Equatable, Sendable {
        let source: String
        let planIDs: [UUID]
        let sessionIDs: [UUID]
        let bytes: Int
        /// Refused as a whole (`refuseRequestsWith`); nothing of it was stored.
        var refused = false
    }

    private let lock = NSLock()
    private var storedPlans: [UUID: Plan] = [:]
    private var storedSessions: [UUID: TrainSession] = [:]
    private var log: [Request] = []
    private var rejected: [UUID: String] = [:]
    private var omitted: Set<UUID> = []
    private var publishes = true
    private var refusing: Set<UUID> = []
    private var finishesCancelled = false
    private var holdHook: (@Sendable () async -> Void)?
    private var codes: [UUID: String] = [:]
    private var busyAnswers = 0
    private var disabled = false
    private var stubborn = false

    init() {}

    /// `unknown_plan_reference` answers also a session sent without plan references (a platform that disagrees twice).
    var refusesUnlinkedSessions: Bool {
        get { lock.withLock { stubborn } }
        set { lock.withLock { stubborn = newValue } }
    }

    /// The `code` a `rejectIDs` item is answered with (default `invalid`), e.g. `newer_on_server`, `unknown_plan_reference`.
    var rejectCodes: [UUID: String] {
        get { lock.withLock { codes } }
        set { lock.withLock { codes = newValue } }
    }

    /// The next this many requests are answered `429 import_in_progress` (`Retry-After: 10`), nothing processed.
    var importInProgressAnswers: Int {
        get { lock.withLock { busyAnswers } }
        set { lock.withLock { busyAnswers = newValue } }
    }

    /// `403 import_not_enabled`: the flag is off for the account.
    var notEnabled: Bool {
        get { lock.withLock { disabled } }
        set { lock.withLock { disabled = newValue } }
    }

    /// False: a platform before the contract (`TrainImportAPI.publishesTrainImport`).
    var publishesTrainImport: Bool {
        get { lock.withLock { publishes } }
        set { lock.withLock { publishes = newValue } }
    }

    /// Items answered `rejected`, with the platform's reason.
    var rejectIDs: [UUID: String] {
        get { lock.withLock { rejected } }
        set { lock.withLock { rejected = newValue } }
    }

    /// Items left out of every answer (an answer that doesn't name them).
    var omitIDs: Set<UUID> {
        get { lock.withLock { omitted } }
        set { lock.withLock { omitted = newValue } }
    }

    /// A request that holds any of these is refused as a whole (`422`, request ID `req-422`), as a platform that
    /// validates the batch before storing anything.
    var refuseRequestsWith: Set<UUID> {
        get { lock.withLock { refusing } }
        set { lock.withLock { refusing = newValue } }
    }

    /// A request whose task was cancelled while held is still answered (its answer was on its way).
    var finishesCancelledRequests: Bool {
        get { lock.withLock { finishesCancelled } }
        set { lock.withLock { finishesCancelled = newValue } }
    }

    /// Runs before each request is stored (tests hold a request open with it). A request whose task was cancelled
    /// meanwhile throws `CancellationError`, as a cancelled URL request does.
    var beforeImport: (@Sendable () async -> Void)? {
        get { lock.withLock { holdHook } }
        set { lock.withLock { holdHook = newValue } }
    }

    /// Every request, oldest first.
    var requests: [Request] { lock.withLock { log } }
    var plans: [Plan] { lock.withLock { Array(storedPlans.values) } }
    var sessions: [TrainSession] { lock.withLock { Array(storedSessions.values) } }

    /// Another account, or demo switched: nothing imported is left.
    func reset() {
        lock.withLock {
            storedPlans = [:]
            storedSessions = [:]
            log = []
        }
    }

    func importTraining(encoded body: Data) async throws -> TrainImportResponse {
        guard publishesTrainImport else { throw APIError.http(404, "not found") }
        if let hook = beforeImport {
            await hook()
            if !finishesCancelledRequests { try Task.checkCancellation() }
        }
        if notEnabled { throw APIError.http(403, "import is not enabled", requestID: "req-403", code: .importNotEnabled) }
        let busy = lock.withLock { () -> Bool in
            guard busyAnswers > 0 else { return false }
            busyAnswers -= 1
            return true
        }
        if busy {
            throw APIError.http(429, "another import is running", requestID: "req-429", code: .importInProgress, retryAfter: 10)
        }
        guard body.count <= 1 << 20 else { throw APIError.http(413, "request body too large") }
        let request = try APIClient.jsonDecoder.decode(Body.self, from: body)
        guard request.plans.count <= 5, request.sessions.count <= 50 else {
            throw APIError.http(413, "too many items")
        }
        guard request.sessions.reduce(0, { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }) <= 2_500 else {
            throw APIError.http(422, "at most 2500 sets per request", requestID: "req-422")
        }
        let refused = refuseRequestsWith
        if !refused.isDisjoint(with: request.plans.map(\.id) + request.sessions.map(\.id)) {
            lock.withLock {
                log.append(Request(source: request.source, planIDs: request.plans.map(\.id),
                                   sessionIDs: request.sessions.map(\.id), bytes: body.count, refused: true))
            }
            throw APIError.http(422, "invalid item", requestID: "req-422")
        }
        return lock.withLock {
            log.append(Request(source: request.source, planIDs: request.plans.map(\.id),
                               sessionIDs: request.sessions.map(\.id), bytes: body.count))
            var results: [ImportResult] = []
            for plan in request.plans where !omitted.contains(plan.id) {
                results.append(answer(.plan, plan.id, old: storedPlans[plan.id], new: plan) { storedPlans[plan.id] = plan })
            }
            for session in request.sessions where !omitted.contains(session.id) {
                // `unknown_plan_reference` holds only while the session still names a plan day or row (T5).
                let linked = session.planDayId != nil || session.exercises.contains { $0.planExerciseId != nil }
                let refuses = codes[session.id] != "unknown_plan_reference" || linked || stubborn
                results.append(answer(.session, session.id, old: storedSessions[session.id], new: session, rejects: refuses) {
                    storedSessions[session.id] = session
                })
            }
            let days = Set(request.sessions.filter { storedSessions[$0.id] != nil }
                .map { DayFormat.string(from: $0.startedAt) })
            return TrainImportResponse(results: results, daysTouched: days.sorted(), requestID: "mock-req-\(log.count)")
        }
    }

    /// In the lock.
    private func answer<T: Equatable>(_ kind: ImportKind, _ id: UUID, old: T?, new: T, rejects: Bool = true,
                                      store: () -> Void) -> ImportResult {
        if rejects, let reason = rejected[id] {
            return ImportResult(kind: kind, id: id, status: .rejected, code: codes[id] ?? "invalid", message: reason)
        }
        let status: ImportStatus = old == nil ? .created : old == new ? .unchanged : .updated
        store()
        return ImportResult(kind: kind, id: id, status: status)
    }

    /// Imported sessions as `GET /v1/sessions` lists them.
    func summaries(from: Date, to: Date) -> [SessionSummary] {
        sessions.filter { $0.startedAt >= from && $0.startedAt <= to }.map { session in
            var scored = session
            scored.volumeKg = Volume.of(session.exercises.flatMap(\.sets))
            return SessionSummary(scored)
        }
    }

    func session(id: UUID) -> TrainSession? { lock.withLock { storedSessions[id] } }
    func plan(id: UUID) -> Plan? { lock.withLock { storedPlans[id] } }

    /// The request as the platform decodes it.
    private struct Body: Decodable {
        let source: String
        let plans: [Plan]
        let sessions: [TrainSession]
    }
}

#if DEBUG
/// Step 6 and the resume row in each state (ui.md §12.1), for previews.
enum MockTrainImport {
    static let createdAt = Date(timeIntervalSince1970: 1_792_400_000)
    static let planID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1))

    static func status(_ phase: ImportJobStatus.Phase, sessions done: Int = 8, of total: Int = 12,
                       rejected: Int = 0, leftAsIs: Int = 0, items: [ImportItemSummary]? = nil) -> ImportJobStatus {
        let rows = items ?? (0..<rejected).map { index in
            ImportItemSummary(id: UUID(), kind: .session, title: "Upper", date: createdAt.addingTimeInterval(Double(-index) * 86_400),
                              reason: "exercise not found", requestID: "01JB7Z3Q8M", blocked: false, code: "unknown_exercise")
        }
        return ImportJobStatus(
            phase: phase, createdAt: createdAt, source: .alphaProgression, timeZoneID: "Europe/Berlin",
            exercises: ImportItemCounts(total: 1, done: 1), plans: ImportItemCounts(total: 1, done: 1),
            sessions: ImportItemCounts(total: total, done: done, rejected: rows.count), setsDone: max(0, done - leftAsIs) * 3,
            planSummaries: [ImportPlanSummary(id: planID, name: "Upper/Lower", weeks: 6, daysPerWeek: 4, state: .done)],
            skipped: ImportSkipCounts(alreadyImported: 2, skippedSets: 3), rejected: rows, duplicatesFound: [],
            lastFailure: nil, planIDs: [planID], enrolledPlanID: nil, resultSeen: false,
            leftAsIs: leftAsIs, leftAsIsSessions: leftAsIs)
    }

    /// One refused item per code the platform answers, with a request ID and a message (Details).
    static let rejectionSamples: [ImportItemSummary] = [
        ("invalid", "set 2 reps out of range"), ("unknown_exercise", "exercise not found"),
        ("unknown_plan_reference", "plan day not found"), ("id_taken", "id belongs to another item"),
        ("newer_on_server", "changed in the app"), ("future_code", "something new"), (nil, "")
    ].enumerated().map { index, pair in
        ImportItemSummary(id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0x50, 0, 0x80, 0, 0, 0, 0, 0, 0, UInt8(index))),
                          kind: .session, title: "Upper", date: createdAt.addingTimeInterval(Double(-index) * 86_400),
                          reason: pair.1.isEmpty ? nil : pair.1, requestID: "01JB7Z3Q8M\(index)", blocked: false, code: pair.0)
    }

    static let mixedRejections = status(.finished, sessions: 9, of: 16, items: Array(rejectionSamples.prefix(4)))
    static let leftAsIsDone = status(.finished, sessions: 12, of: 12, leftAsIs: 3)

    static let uploading = status(.uploading)
    static let done = status(.finished, sessions: 12, of: 12)
    static let partlyDone = status(.finished, sessions: 9, of: 12, rejected: 3)
    static let offline = status(.paused(.offline))
    static let retrying = status(.paused(.retrying(at: createdAt.addingTimeInterval(30))))
    static let savedOnPhone = status(.paused(.notAvailable), sessions: 0)
}
#endif
