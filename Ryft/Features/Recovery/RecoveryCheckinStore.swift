import Foundation
import Observation

/// Today's recovery status and the account's small check-in outbox.
@MainActor
@Observable
final class RecoveryCheckinStore {
    enum Availability: Equatable { case unknown, live, notLive }
    enum CardState: Equatable { case due, skipped, done(RecoveryCheckin), waiting }
    enum SaveResult: Equatable { case saved, waiting, consentRequired, unavailable }

    struct Pending: Codable, Hashable, Sendable {
        let date: String
        let body: RecoveryCheckinPut
    }

    struct Owner: Equatable {
        fileprivate let binding: AccountBinding
        fileprivate let generation: Int
    }

    static let statusKey = "recovery.status"
    static let pendingKey = "recovery.pending"
    private static let skippedKey = "recovery.skipped"

    private let env: AppEnvironment
    private let apiStatus: APIStatus
    private var generation = 0
    private var restored = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    private var writes = 0
    private var skippedDate: String?
    private var statusReadOnDay: String?
    private(set) var status: RecoveryStatus?
    private(set) var availability: Availability = .unknown
    private(set) var pending: [Pending] = []
    private var rejectedDates: [String] = []
    var rejectedDate: String? { rejectedDates.first }
    private(set) var isSending = false
    var isPresentingSheet = false

    init(env: AppEnvironment, apiStatus: APIStatus? = nil) {
        self.env = env
        self.apiStatus = apiStatus ?? .shared
    }

    convenience init(state: AppState, apiStatus: APIStatus) {
        self.init(env: state.env, apiStatus: apiStatus)
        state.forgetsAccountState { [weak self] in self?.accountChanged() }
    }

    var owner: Owner { Owner(binding: AccountBinding(env), generation: generation) }
    func owns(_ owner: Owner) -> Bool { owner == self.owner }

    var now: Date { env.clock.now() }
    var today: String { DayFormat.string(from: now) }
    private var online: Bool { env.isDemo || env.connectivity.isOnline }

    var enabled: Bool { env.recoveryCheckinEnabled }
    private var consentBlocked: Bool {
        !env.isDemo && (apiStatus.gates.contains(.consentRequired) || env.consent.refusals.contains(.consentRequired)
            || env.consent.withdrawnAt != nil || env.consent.withdrawalUnresolvedSince != nil)
    }

    /// A fresh status names the account's wake day. Restored status is usable only on the device's current day.
    private var wakeDay: String { online && statusReadOnDay == today ? status?.date ?? today : today }

    var offersSheet: Bool {
        enabled && availability != .notLive && (status?.date != wakeDay
            || (status?.source != .wearable && status?.checkin?.superseded != true))
    }

    var card: CardState? {
        let day = wakeDay
        return Self.card(flag: enabled && availability != .notLive, today: day, status: status,
                         pending: pending.contains { $0.date == day }, skipped: skippedDate == day)
    }

    static func card(flag: Bool, today: String, status: RecoveryStatus?, pending: Bool, skipped: Bool) -> CardState? {
        guard flag else { return nil }
        let current: RecoveryStatus? = status.flatMap { $0.date == today ? $0 : nil }
        guard current?.source != .wearable, current?.checkin?.superseded != true else { return nil }
        if pending { return .waiting }
        guard let current else { return nil }
        if current.source == .checkin, let checkin = current.checkin, checkin.date == today { return .done(checkin) }
        if current.needsCheckin { return skipped ? .skipped : .due }
        return nil
    }

    func accountChanged() {
        generation += 1
        restored = false
        loadTask?.cancel()
        loadTask = nil
        isSending = false
        isPresentingSheet = false
        status = nil
        statusReadOnDay = nil
        availability = .unknown
        pending = []
        skippedDate = nil
        rejectedDates = []
    }

    private func restore() {
        guard !restored else { return }
        restored = true
        guard let disk = env.accountDocuments else { return }
        status = disk.document(RecoveryStatus.self, key: Self.statusKey)
        pending = disk.document([Pending].self, key: Self.pendingKey) ?? []
        skippedDate = disk.document(String.self, key: Self.skippedKey)
    }

    func load(userInitiated: Bool = false) async {
        guard enabled, !Task.isCancelled else { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let owner = self.owner
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.load(as: owner, userInitiated: userInitiated)
        }
        loadTask = task
        await task.value
    }

    private func load(as owner: Owner, userInitiated: Bool) async {
        defer { if owns(owner) { loadTask = nil } }
        guard owns(owner), enabled, !Task.isCancelled else { return }
        restore()
        discardExpired()
        guard online else { return }
        let api = env.api

        // Restored queues and known missing routes confirm status before sending anything.
        let shouldProbeFirst = availability != .live && !pending.isEmpty
        if !shouldProbeFirst, availability != .notLive {
            guard await retryPending(owner: owner, api: api) else { return }
        }
        guard owns(owner), enabled else { return }

        let revision = writes
        do {
            let result = try await env.reads.run(ReadKey(.recovery, id: String(owner.generation)),
                                                 userInitiated: userInitiated) { () async throws -> RecoveryStatus? in
                guard self.owns(owner), self.enabled else { throw ReadScheduler.NotSent() }
                return try await APIClient.$recoveryRequestAllowed.withValue({ self.owns(owner) && self.enabled }) {
                    do {
                        return try await api.recoveryStatus()
                    } catch where error.isEndpointMissing {
                        return nil
                    }
                }
            }
            guard owns(owner), enabled, revision == writes else { return }
            switch result {
            case .some(.some(let fresh)):
                availability = .live
                cache(fresh)
                if shouldProbeFirst { _ = await retryPending(owner: owner, api: api) }
            case .some(.none):
                availability = .notLive
            case .none:
                break
            }
        } catch {
            // A failed read leaves today's cached status and the queue available.
        }
    }

    func skip() {
        guard enabled, availability != .notLive, card == .due else { return }
        skippedDate = wakeDay
        env.accountDocuments?.saveDocument(wakeDay, key: Self.skippedKey, at: now)
        env.analytics.track(.recoveryCheckin(.skipped))
    }

    func opened(as owner: Owner) {
        guard owns(owner), enabled, availability != .notLive else { return }
        env.analytics.track(.recoveryCheckin(.opened))
    }

    func dismissRejection() { if !rejectedDates.isEmpty { rejectedDates.removeFirst() } }

    func save(date: String, body: RecoveryCheckinPut, as owner: Owner) async throws -> SaveResult {
        guard owns(owner), enabled, availability != .notLive, !isSending else { throw CancellationError() }
        restore()
        let entry = Pending(date: date, body: body)
        if consentBlocked {
            _ = queued(entry)
            return .consentRequired
        }
        guard online else { return queued(entry) }

        let api = env.api
        isSending = true
        writes += 1
        defer { if owns(owner) { isSending = false; writes += 1 } }
        do {
            let answer = try await send(entry, owner: owner, api: api)
            guard owns(owner) else { throw CancellationError() }
            accept(answer, for: date)
            if enabled { env.analytics.track(.recoveryCheckin(.saved)) }
            return .saved
        } catch {
            guard owns(owner), !error.isCancellation else { throw CancellationError() }
            if (error as? APIError)?.status == 404 {
                availability = .notLive
                return .unavailable
            }
            if error.gate == .consentRequired {
                if !env.isDemo { _ = queued(entry) }
                reportGate(error, api: api)
                return .consentRequired
            }
            if !env.isDemo, Self.shouldQueue(error) { return queued(entry) }
            if (error as? APIError)?.isFieldError == true {
                let fallback = String(localized: "Check the times and try again.",
                                      comment: "Morning check-in: the server rejected the values without field details.")
                throw RecoveryWriteError.field(error, fallback: fallback)
            }
            throw error
        }
    }

    /// Stop the pass on a refusal that also applies to the rest of the queue.
    private func retryPending(owner: Owner, api: PlatformAPI) async -> Bool {
        guard !isSending, !pending.isEmpty, !consentBlocked else { return true }
        isSending = true
        defer { if owns(owner) { isSending = false } }
        for entry in pending.sorted(by: { $0.date < $1.date }) {
            guard owns(owner), enabled, online, !consentBlocked, !Task.isCancelled else { return false }
            do {
                let answer = try await send(entry, owner: owner, api: api)
                guard owns(owner) else { return false }
                accept(answer, for: entry.date)
            } catch {
                guard owns(owner), !error.isCancellation else { return false }
                switch (error as? APIError)?.status {
                case 404:
                    availability = .notLive
                    return false
                case 422:
                    removePending(date: entry.date)
                    rejectedDates.append(entry.date)
                default:
                    reportGate(error, api: api)
                    return error.gate == nil && FailureKind.of(error) != .signedOut
                }
            }
        }
        return true
    }

    private func send(_ entry: Pending, owner: Owner, api: PlatformAPI) async throws -> RecoveryCheckin {
        try await SettingsWrite.answer(in: env) {
            guard self.owns(owner), self.enabled else { throw CancellationError() }
            guard self.online else { throw SettingsWrite.NoAnswer() }
            guard !self.consentBlocked else { throw APIError.http(403, "", code: .consentRequired) }
            return try await APIClient.$recoveryRequestAllowed.withValue({ self.owns(owner) && self.enabled }) {
                try await api.putRecoveryCheckin(date: entry.date, entry.body)
            }
        }
    }

    private func reportGate(_ error: Error, api: PlatformAPI) {
        // APIClient already reports refusals for the request's account. The mock has no APIStatus of its own.
        if let gate = error.gate, !(api is APIClient) { apiStatus.observe([gate], enforced: true) }
    }

    private static func shouldQueue(_ error: Error) -> Bool {
        if let status = (error as? APIError)?.status, (500...599).contains(status) { return true }
        let kind = FailureKind.of(error)
        return kind == .transient || kind == .signedOut || error is SettingsWrite.NoAnswer
    }

    private func queued(_ entry: Pending) -> SaveResult {
        pending.removeAll { $0.date == entry.date }
        pending.append(entry)
        persistPending()
        if enabled { env.analytics.track(.recoveryCheckin(.saved)) }
        return .waiting
    }

    private func removePending(date: String) {
        guard pending.contains(where: { $0.date == date }) else { return }
        pending.removeAll { $0.date == date }
        persistPending()
    }

    private func persistPending() {
        if pending.isEmpty {
            env.accountDocuments?.removeDocument(key: Self.pendingKey)
        } else {
            env.accountDocuments?.saveDocument(pending, key: Self.pendingKey, at: now)
        }
    }

    private func discardExpired() {
        let firstDay = DayFormat.string(from: DayFormat.shift(now, days: -14))
        let priorCount = pending.count
        pending.removeAll { $0.date < firstDay }
        if pending.count != priorCount { persistPending() }
    }

    private func accept(_ answer: RecoveryCheckin, for date: String) {
        removePending(date: date)
        guard answer.date == wakeDay, status?.source != .wearable || status?.date != wakeDay else { return }
        availability = .live
        let previous = status?.date == date ? status : nil
        cache(RecoveryStatus(date: answer.date, source: .checkin, confidence: answer.confidence,
                             recoveryScore: answer.recoveryScore, needsCheckin: false, checkin: answer,
                             suggestedBedtime: previous?.suggestedBedtime, suggestedWakeTime: previous?.suggestedWakeTime,
                             suggestionBasis: previous?.suggestionBasis))
    }

    private func cache(_ status: RecoveryStatus) {
        self.status = status
        statusReadOnDay = today
        env.accountDocuments?.saveDocument(status, key: Self.statusKey, at: now)
    }
}

struct RecoveryWriteError: LocalizedError {
    let message: String
    let details: String?
    var errorDescription: String? { message }

    static func field(_ error: Error, fallback: String) -> Self {
        if case .http(422, let message, _, _, _)? = error as? APIError,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self(message: message, details: error.diagnosticDetails)
        }
        return Self(message: fallback, details: error.diagnosticDetails)
    }
}
