// The registry's types as HealthKit's (ADR 0027). Built on demand and never stored in a `Sendable` value, so
// `HKObjectType`'s missing `Sendable` conformance never matters.
import HealthKit

extension HealthDataType {
    var objectType: HKObjectType {
        switch self {
        case .heartRate: HKQuantityType(.heartRate)
        case .hrvSDNN: HKQuantityType(.heartRateVariabilitySDNN)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .respiratoryRate: HKQuantityType(.respiratoryRate)
        case .oxygenSaturation: HKQuantityType(.oxygenSaturation)
        case .vo2Max: HKQuantityType(.vo2Max)
        case .activeEnergy: HKQuantityType(.activeEnergyBurned)
        case .steps: HKQuantityType(.stepCount)
        case .sleepAnalysis: HKCategoryType(.sleepAnalysis)
        case .workout: HKObjectType.workoutType()
        case .dateOfBirth: HKCharacteristicType(.dateOfBirth)
        case .biologicalSex: HKCharacteristicType(.biologicalSex)
        case .height: HKQuantityType(.height)
        case .bodyMass: HKQuantityType(.bodyMass)
        case .bodyFatPercentage: HKQuantityType(.bodyFatPercentage)
        case .leanBodyMass: HKQuantityType(.leanBodyMass)
        case .dietaryEnergy: HKQuantityType(.dietaryEnergyConsumed)
        case .dietaryProtein: HKQuantityType(.dietaryProtein)
        case .dietaryCarbohydrates: HKQuantityType(.dietaryCarbohydrates)
        case .dietaryFat: HKQuantityType(.dietaryFatTotal)
        case .dietaryWater: HKQuantityType(.dietaryWater)
        case .basalEnergy: HKQuantityType(.basalEnergyBurned)
        case .dietaryCaffeine: HKQuantityType(.dietaryCaffeine)
        case .alcoholicBeverages: HKQuantityType(.numberOfAlcoholicBeverages)
        case .mindfulSession: HKCategoryType(.mindfulSession)
        case .timeInDaylight: HKQuantityType(.timeInDaylight)
        case .sleepingWristTemperature: HKQuantityType(.appleSleepingWristTemperature)
        case .heartbeatSeries: HKSeriesType.heartbeat()
        }
    }
}

extension HealthKitManager {
    /// What a request reads, from the asked groups: the union of their types, requestable groups only. A group that
    /// isn't requestable adds nothing, so no request can carry its types.
    static func readTypes(_ asked: Set<HealthPermissionGroup>) -> Set<HKObjectType> {
        Set(HealthPermissionGroup.allCases.filter { $0.isRequestable && asked.contains($0) }
            .flatMap(\.types).map(\.objectType))
    }

    /// Background delivery and the observers, from the asked groups: their `observed` types, in group order.
    /// Characteristics (`about`) have none.
    static func observedTypes(_ asked: Set<HealthPermissionGroup>) -> [HKSampleType] {
        HealthPermissionGroup.allCases.filter { $0.isRequestable && asked.contains($0) }
            .flatMap(\.observed).compactMap { $0.objectType as? HKSampleType }
    }
}
