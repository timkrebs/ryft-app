import Foundation

enum SleepMode: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return String(localized: "Day")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        }
    }

    var rangeKind: SleepRangeKind? {
        switch self {
        case .day: return nil
        case .week: return .week
        case .month: return .month
        }
    }
}

@MainActor
final class SleepViewModel: ObservableObject {
    /// `-RyftSleepMode week` preselects a mode (screenshots).
    @Published var mode: SleepMode = UserDefaults.standard.string(forKey: "RyftSleepMode")
        .flatMap(SleepMode.init(rawValue:)) ?? .day
    /// The night shown in Day mode, identified by the morning it ended.
    @Published private(set) var date = Calendar.current.startOfDay(for: .now)
    @Published private(set) var detail: DayDetail?
    @Published private(set) var range: SleepRange?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    var isToday: Bool { Calendar.current.isDateInToday(date) }
    var sleep: SleepDetail? { detail?.resolvedSleep }

    func step(by days: Int, state: AppState) async {
        let next = DayFormat.shift(date, days: days)
        guard next <= Calendar.current.startOfDay(for: .now) else { return }
        date = next
        await load(state: state)
    }

    func load(state: AppState) async {
        error = nil
        if let kind = mode.rangeKind {
            if range?.range != kind.rawValue { range = nil }
            isLoading = true
            range = await state.sleepRange(kind)
            isLoading = false
            return
        }
        // Instant paint from cache, then refresh.
        detail = state.cachedDayDetail(for: date)
        guard state.hasDataSource else { return }
        isLoading = detail == nil
        defer { isLoading = false }
        do {
            detail = try await state.dayDetail(for: date)
        } catch {
            if detail == nil { self.error = error.localizedDescription }
        }
    }
}
