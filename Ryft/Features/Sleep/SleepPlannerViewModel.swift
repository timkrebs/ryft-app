import Foundation
import Observation

/// Sleep → Planner (`GET /v1/sleep/plan?wake=HH:MM`, behind `sleep.planner`):
/// three bedtimes for a wake time and the need behind them. A wake-time change
/// asks again after 300 ms of quiet; offline, the last plan stays with its time.
@MainActor
@Observable
final class SleepPlannerViewModel {
    private let state: AppState

    static let cacheKey = "sleep.plan"
    static let debounce: Duration = .milliseconds(300)

    /// The last plan and when it was fetched (offline-first).
    struct Cached: Codable, Equatable {
        let plan: SleepPlan
        let wake: String
        let fetchedAt: Date
    }

    /// The wake time asked for, local.
    private(set) var wake: Date
    private(set) var plan: SleepPlan?
    /// Set when `plan` is a cached one (offline or the request failed).
    private(set) var asOf: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
        let now = state.env.clock.now()
        wake = Self.defaultWake(state: state, now: now)
        if let cached = state.env.persistence.document(Cached.self, key: Self.cacheKey) {
            plan = cached.plan
            asOf = cached.fetchedAt
        }
    }

    /// The most recent wake time from the week's bedtimes, else 07:00.
    static func defaultWake(state: AppState, now: Date) -> Date {
        let cal = Calendar.current
        let last = state.cachedSleepRange(.week)?.bedtimes.max { $0.wake < $1.wake }?.wake
        let parts = last.map { cal.dateComponents([.hour, .minute], from: $0) } ?? DateComponents(hour: 7, minute: 0)
        return cal.date(bySettingHour: parts.hour ?? 7, minute: parts.minute ?? 0, second: 0, of: now) ?? now
    }

    var wakeText: String { Self.hhmm(wake) }

    static func hhmm(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: what the screen shows

    struct Option: Identifiable, Equatable {
        let share: Int
        let bedtime: Date
        /// Sleep at that share of the need.
        let sleepMin: Int
        var id: Int { share }
    }

    /// 100 %, 85 %, 70 %, earliest first (the API's order).
    var options: [Option] {
        guard let plan else { return [] }
        return [(100, plan.bedtime100), (85, plan.bedtime85), (70, plan.bedtime70)].map { share, bed in
            Option(share: share, bedtime: bed, sleepMin: Int((Double(plan.needMin) * Double(share) / 100).rounded()))
        }
    }

    // MARK: loading

    func load() async {
        await fetch()
    }

    /// The picker moved: ask again once it has been still for 300 ms.
    func setWake(_ date: Date) {
        wake = date
        pending?.cancel()
        let clock = state.env.clock
        pending = Task { [weak self] in
            do { try await clock.sleep(for: Self.debounce) } catch { return }
            await self?.fetch()
        }
    }

    /// Waits for a debounced request (tests).
    func settle() async { await pending?.value }

    private func fetch() async {
        let hhmm = wakeText
        guard state.hasDataSource else { return }
        guard state.env.connectivity.isOnline else {
            if plan != nil, asOf == nil { asOf = state.env.clock.now() }
            return
        }
        isLoading = plan == nil
        defer { isLoading = false }
        do {
            let fresh = try await state.env.api.sleepPlan(wake: hhmm)
            guard hhmm == wakeText else { return }   // superseded by a newer wake time
            plan = fresh
            asOf = nil
            error = nil
            state.env.persistence.saveDocument(Cached(plan: fresh, wake: hhmm, fetchedAt: state.env.clock.now()),
                                               key: Self.cacheKey, at: state.env.clock.now())
        } catch {
            // 422 only for a malformed time, which the picker can't make.
            assert((error as? APIError)?.status != 422, "sleep/plan rejected wake \(hhmm)")
            if plan == nil {
                self.error = error.localizedDescription
            } else if asOf == nil {
                asOf = state.env.persistence.document(Cached.self, key: Self.cacheKey)?.fetchedAt ?? state.env.clock.now()
            }
        }
    }
}
