// Read-side cache of what the API returns. Views bind to this; SyncService
// writes to HealthKit→backend, this reads backend→UI.
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var today: DailyScore?
    @Published var todayWorkouts: [Workout] = []
    @Published var history: [DailyScore] = []   // last 30 days, oldest first
    @Published var user: User?
    @Published var error: String?
    @Published var isLoading = false

    private let api = APIClient.shared

    func refresh() async {
        guard Settings.shared.isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let detail = api.day(.now)
            async let days = api.days(from: Calendar.current.date(byAdding: .day, value: -29, to: .now)!, to: .now)
            async let me = api.me()
            let (d, h, u) = try await (detail, days, me)
            today = d.score
            todayWorkouts = d.workouts
            history = h
            user = u
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateUser(_ patch: UserPatch) async {
        do {
            user = try await api.patchMe(patch)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
