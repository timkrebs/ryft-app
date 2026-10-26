@testable import Ryft

extension SyncService {
    /// A sync whose gate is open. The app connects `OnboardingCoordinator.uploadGate(for: .healthKit)` (ScreenModels)
    /// and the gate is closed until then; tests about what happens past it open it here, and tests about the gate set
    /// their own.
    @MainActor
    static func ungated(env: AppEnvironment) -> SyncService {
        let sync = SyncService(env: env)
        sync.gate = { nil }
        return sync
    }
}
