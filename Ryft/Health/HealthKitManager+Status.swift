// Read-permission status for the Profile screen. HealthKit never reveals
// whether *read* access was granted, only whether the prompt still needs to be
// shown — so "asked" is the best we can report.
import HealthKit

extension HealthKitManager {
    enum AccessStatus {
        case unavailable, notAsked, asked, unknown
    }

    func accessStatus() async -> AccessStatus {
        guard Self.isAvailable else { return .unavailable }
        do {
            switch try await store.statusForAuthorizationRequest(toShare: [], read: readTypes) {
            case .shouldRequest: return .notAsked
            case .unnecessary: return .asked
            default: return .unknown
            }
        } catch {
            return .unknown
        }
    }
}
