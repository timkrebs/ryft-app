// The one place a HealthKit read type is declared (ADR 0027, docs/work/2026-11-23-first-run/health-groups.md §3).
// Plain values without HealthKit, so previews, the mock and the tests use them as they are; the mapping to
// `HKObjectType` is in `HealthPermissionGroup+HealthKit.swift` and only ever built on demand.
import Foundation

/// Every type RYFT reads, or will read once its feature ships. The raw value is HealthKit's identifier.
enum HealthDataType: String, CaseIterable, Sendable {
    // core
    case heartRate = "HKQuantityTypeIdentifierHeartRate"
    case hrvSDNN = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
    case restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
    case respiratoryRate = "HKQuantityTypeIdentifierRespiratoryRate"
    case oxygenSaturation = "HKQuantityTypeIdentifierOxygenSaturation"
    case vo2Max = "HKQuantityTypeIdentifierVO2Max"
    case activeEnergy = "HKQuantityTypeIdentifierActiveEnergyBurned"
    case steps = "HKQuantityTypeIdentifierStepCount"
    case sleepAnalysis = "HKCategoryTypeIdentifierSleepAnalysis"
    case workout = "HKWorkoutTypeIdentifier"
    // about
    case dateOfBirth = "HKCharacteristicTypeIdentifierDateOfBirth"
    // body
    case biologicalSex = "HKCharacteristicTypeIdentifierBiologicalSex"
    case height = "HKQuantityTypeIdentifierHeight"
    case bodyMass = "HKQuantityTypeIdentifierBodyMass"
    case bodyFatPercentage = "HKQuantityTypeIdentifierBodyFatPercentage"
    case leanBodyMass = "HKQuantityTypeIdentifierLeanBodyMass"
    // fuel
    case dietaryEnergy = "HKQuantityTypeIdentifierDietaryEnergyConsumed"
    case dietaryProtein = "HKQuantityTypeIdentifierDietaryProtein"
    case dietaryCarbohydrates = "HKQuantityTypeIdentifierDietaryCarbohydrates"
    case dietaryFat = "HKQuantityTypeIdentifierDietaryFatTotal"
    case dietaryWater = "HKQuantityTypeIdentifierDietaryWater"
    case basalEnergy = "HKQuantityTypeIdentifierBasalEnergyBurned"
    // habits
    case dietaryCaffeine = "HKQuantityTypeIdentifierDietaryCaffeine"
    case alcoholicBeverages = "HKQuantityTypeIdentifierNumberOfAlcoholicBeverages"
    case mindfulSession = "HKCategoryTypeIdentifierMindfulSession"
    case timeInDaylight = "HKQuantityTypeIdentifierTimeInDaylight"
    // physiology
    case sleepingWristTemperature = "HKQuantityTypeIdentifierAppleSleepingWristTemperature"
    case heartbeatSeries = "HKDataTypeIdentifierHeartbeatSeries"

    /// The type as `NSHealthShareUsageDescription` names it. Never shown on its own: the usage-description tests
    /// match it, so a requestable group's types are all named there and no other group's are (§8). Each name is
    /// distinct enough not to occur in the description by accident ("dietary energy", not "energy").
    var usageName: String {
        switch self {
        case .heartRate: "heart rate"
        case .hrvSDNN: "HRV"
        case .restingHeartRate: "resting heart rate"
        case .respiratoryRate: "breathing rate"
        case .oxygenSaturation: "blood oxygen"
        case .vo2Max: "VO₂ max"
        case .activeEnergy: "active energy"
        case .steps: "steps"
        case .sleepAnalysis: "sleep"
        case .workout: "workouts"
        case .dateOfBirth: "date of birth"
        case .biologicalSex: "biological sex"
        case .height: "height"
        case .bodyMass: "body weight"
        case .bodyFatPercentage: "body fat percentage"
        case .leanBodyMass: "lean body mass"
        case .dietaryEnergy: "dietary energy"
        case .dietaryProtein: "protein"
        case .dietaryCarbohydrates: "carbohydrates"
        case .dietaryFat: "total fat"
        case .dietaryWater: "water"
        case .basalEnergy: "resting energy"
        case .dietaryCaffeine: "caffeine"
        case .alcoholicBeverages: "alcoholic beverages"
        case .mindfulSession: "mindful minutes"
        case .timeInDaylight: "time in daylight"
        case .sleepingWristTemperature: "wrist temperature"
        case .heartbeatSeries: "heartbeat series"
        }
    }
}

/// What reads a group: the code a requestable group's types exist for.
enum HealthConsumer: String, Sendable {
    /// The sync engine's uploads, which the platform scores.
    case scores
    /// About you's "Use my birth year from Apple Health".
    case birthYearPrefill
    /// Fuel (M12).
    case fuel
    /// The journal's autofill.
    case journalAutofill
    /// The physiology card.
    case physiologyCard
}

/// The groups Apple Health is asked for, each by its own feature (ADR 0027). Making a group requestable is a reviewed
/// change with its feature: its consumer, its primer and its words in the usage description, which the tests demand.
enum HealthPermissionGroup: String, CaseIterable, Codable, Sendable {
    case core, about, body, fuel, habits, physiology

    var types: [HealthDataType] {
        switch self {
        case .core:
            [.heartRate, .hrvSDNN, .restingHeartRate, .respiratoryRate, .oxygenSaturation, .vo2Max, .activeEnergy, .steps,
             .sleepAnalysis, .workout]
        case .about: [.dateOfBirth]
        case .body: [.biologicalSex, .height, .bodyMass, .bodyFatPercentage, .leanBodyMass]
        case .fuel: [.dietaryEnergy, .dietaryProtein, .dietaryCarbohydrates, .dietaryFat, .dietaryWater, .basalEnergy]
        case .habits: [.dietaryCaffeine, .alcoholicBeverages, .mindfulSession, .timeInDaylight]
        case .physiology: [.sleepingWristTemperature, .heartbeatSeries]
        }
    }

    /// The one line on the group's primer.
    var reason: LocalizedStringResource {
        switch self {
        case .core: "RYFT reads what your watch writes to Apple Health to calculate your recovery, strain and sleep scores."
        case .about: "RYFT reads your date of birth and keeps only the year."
        case .body: "RYFT reads your body measurements to work out your energy needs."
        case .fuel: "RYFT reads the food and drink you log to compare them with what you burn."
        case .habits: "RYFT reads caffeine, alcohol, mindful minutes and time in daylight to fill in your journal."
        case .physiology: "RYFT reads your wrist temperature and heartbeat series for the physiology card."
        }
    }

    var consumer: HealthConsumer {
        switch self {
        case .core: .scores
        case .about: .birthYearPrefill
        case .body, .fuel: .fuel
        case .habits: .journalAutofill
        case .physiology: .physiologyCard
        }
    }

    /// Whether anything may ask for it. A group that isn't is never in a request: the live store throws
    /// `HealthPermissionError.notRequestable` before HealthKit is reached.
    var isRequestable: Bool {
        switch self {
        case .core, .about: true
        case .body, .fuel, .habits, .physiology: false
        }
    }

    /// Its anchored uploads, in the order a sync drains them: the night and the overnight vitals first (what the
    /// morning's score waits for), then workouts, then the high-volume day streams.
    var streams: [HealthStream] {
        switch self {
        case .core:
            [.sleep, .quantity(.hrvSDNN), .quantity(.restingHR), .quantity(.respiratoryRate), .quantity(.spo2),
             .workouts, .quantity(.heartRate), .quantity(.steps), .quantity(.activeEnergy), .quantity(.vo2max)]
        // A characteristic has no anchor and no upload; the other groups aren't requestable yet.
        case .about, .body, .fuel, .habits, .physiology: []
        }
    }

    /// Its background-delivery types: the records that change a score. Heart rate arrives constantly and would wake
    /// the app too often; it rides along with these syncs.
    var observed: [HealthDataType] {
        switch self {
        case .core: [.sleepAnalysis, .workout, .hrvSDNN]
        // A characteristic has no observer; the other groups aren't requestable yet.
        case .about, .body, .fuel, .habits, .physiology: []
        }
    }
}

enum HealthPermissionError: Error, Equatable {
    /// The group's feature hasn't shipped (`isRequestable` is false).
    case notRequestable(HealthPermissionGroup)
}
