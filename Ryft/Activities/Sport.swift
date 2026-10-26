import Foundation
import HealthKit

/// How a sport is measured while it's recorded: the parameters the track pipeline (`Recording/`) takes,
/// read from the catalogue (`Sport.trackProfile`).
struct TrackProfile: Equatable, Sendable {
    /// `primary` asks for Motion & Fitness and uses the barometer; `secondary` uses the barometer only if
    /// Motion is already allowed, else GPS altitude; `none` shows no elevation.
    enum Elevation: Sendable { case primary, secondary, none }
    /// Minutes per kilometre, or km/h.
    enum PaceStyle: Sendable { case pace, speed }

    /// m/s: the fastest the sport is done. Above it a step adds no distance and the recording reports "too fast"; the
    /// speed gate also uses it to reject jumps (ADR 0003, amendment 2). `nil`: no GPS.
    var maxSpeed: Double?
    /// m/s²: the Kalman filter's process noise. `nil`: no GPS.
    var sigmaA: Double?
    /// m/s below which auto-pause starts (`indoor_running`: cadence 0, so 0). `nil`: no auto-pause.
    var autoPauseThreshold: Double?
    /// Whether auto-pause is on until the user changes it.
    var autoPauseDefault: Bool
    var elevation: Elevation
    var paceStyle: PaceStyle
}

/// The sport catalogue (design.md §2.1): one table that Add activity, Start activity, the recorder, My Day
/// and Apple Health all read. The enum itself is a wire type (`Networking/Models.swift`).
extension Sport {
    /// Sports the platform merges with a tracker's workout (API request R10) and Apple Health's overlap rule
    /// compares (A6).
    enum Family: String, CaseIterable, Sendable {
        case foot, cycle, water, gym, snow, ball, other
    }

    /// The HealthKit quantity a recording of the sport saves its distance as (iOS 17's types).
    enum DistanceType: CaseIterable, Sendable {
        case walkingRunning, cycling, downhillSnowSports, swimming

        var identifier: HKQuantityTypeIdentifier {
            switch self {
            case .walkingRunning: return .distanceWalkingRunning
            case .cycling: return .distanceCycling
            case .downhillSnowSports: return .distanceDownhillSnowSports
            case .swimming: return .distanceSwimming
            }
        }
    }

    /// One row of the table.
    struct Spec: Sendable {
        /// SF Symbol (iOS 16 or older, so it exists on iOS 17; ui.md §3.2).
        let symbol: String
        let family: Family
        let healthKit: HKWorkoutActivityType
        let location: HKWorkoutSessionLocationType
        let elevation: TrackProfile.Elevation
        let autoPauseDefault: Bool
        let autoPauseThreshold: Double?
        /// m/s: the fastest the sport is done (`TrackProfile.maxSpeed`); `nil`: no GPS.
        let maxSpeed: Double?
        /// m/s²; `nil`: no GPS.
        let sigmaA: Double?
        let distance: DistanceType?

        /// A sport recorded with GPS.
        init(_ symbol: String, _ family: Family, _ healthKit: HKWorkoutActivityType, elevation: TrackProfile.Elevation,
             autoPause: Bool, threshold: Double, maxSpeed: Double, sigmaA: Double, distance: DistanceType?) {
            self.symbol = symbol
            self.family = family
            self.healthKit = healthKit
            location = .outdoor
            self.elevation = elevation
            autoPauseDefault = autoPause
            autoPauseThreshold = threshold
            self.maxSpeed = maxSpeed
            self.sigmaA = sigmaA
            self.distance = distance
        }

        /// A sport recorded without GPS (time; for `indoor_running` the pedometer's distance).
        init(_ symbol: String, _ family: Family, _ healthKit: HKWorkoutActivityType,
             location: HKWorkoutSessionLocationType = .unknown, autoPause: Bool = false, threshold: Double? = nil,
             distance: DistanceType? = nil) {
            self.symbol = symbol
            self.family = family
            self.healthKit = healthKit
            self.location = location
            elevation = .none
            autoPauseDefault = autoPause
            autoPauseThreshold = threshold
            maxSpeed = nil
            sigmaA = nil
            self.distance = distance
        }
    }

    // The table. Symbols: ui.md §3.2 (`figure.run.treadmill` is iOS 18, so indoor runs use `figure.run`).
    // Padel and ski touring use Apple's closest types (plan D1-8). Rowing has no GPS in v1.
    var spec: Spec {
        switch self {
        case .running:
            return Spec("figure.run", .foot, .running, elevation: .secondary, autoPause: true, threshold: 1.0,
                        maxSpeed: 9, sigmaA: 1.5, distance: .walkingRunning)
        case .trailRunning:
            return Spec("figure.run", .foot, .running, elevation: .primary, autoPause: true, threshold: 0.8,
                        maxSpeed: 8, sigmaA: 1.5, distance: .walkingRunning)
        case .walking:
            return Spec("figure.walk", .foot, .walking, elevation: .secondary, autoPause: false, threshold: 0.4,
                        maxSpeed: 6, sigmaA: 1.0, distance: .walkingRunning)
        case .hiking:
            return Spec("figure.hiking", .foot, .hiking, elevation: .primary, autoPause: false, threshold: 0.3,
                        maxSpeed: 6, sigmaA: 1.0, distance: .walkingRunning)
        case .cycling:
            return Spec("figure.outdoor.cycle", .cycle, .cycling, elevation: .secondary, autoPause: true,
                        threshold: 1.5, maxSpeed: 36, sigmaA: 3.0, distance: .cycling)
        case .mountainBiking:
            return Spec("figure.outdoor.cycle", .cycle, .cycling, elevation: .primary, autoPause: true,
                        threshold: 1.2, maxSpeed: 25, sigmaA: 3.0, distance: .cycling)
        case .gravel:
            return Spec("figure.outdoor.cycle", .cycle, .cycling, elevation: .secondary, autoPause: true,
                        threshold: 1.5, maxSpeed: 30, sigmaA: 3.0, distance: .cycling)
        case .indoorRunning:
            // The pedometer measures; auto-pause is cadence 0 for 10 s.
            return Spec("figure.run", .foot, .running, location: .indoor, autoPause: true, threshold: 0,
                        distance: .walkingRunning)
        case .indoorCycling:
            return Spec("figure.indoor.cycle", .cycle, .cycling, location: .indoor, distance: .cycling)
        case .rowing:
            return Spec("figure.rower", .water, .rowing)
        case .swimming:
            return Spec("figure.pool.swim", .water, .swimming, distance: .swimming)
        case .strength:
            return Spec("dumbbell.fill", .gym, .traditionalStrengthTraining)
        case .hiit:
            return Spec("figure.highintensity.intervaltraining", .gym, .highIntensityIntervalTraining)
        case .yoga:
            return Spec("figure.yoga", .gym, .yoga)
        case .mobility:
            return Spec("figure.flexibility", .gym, .flexibility)
        case .climbing:
            return Spec("figure.climbing", .gym, .climbing)
        case .skiing:
            return Spec("figure.skiing.downhill", .snow, .downhillSkiing, elevation: .secondary, autoPause: false,
                        threshold: 1.0, maxSpeed: 40, sigmaA: 5.0, distance: .downhillSnowSports)
        case .skiTouring:
            return Spec("figure.skiing.crosscountry", .snow, .crossCountrySkiing, elevation: .primary,
                        autoPause: false, threshold: 0.3, maxSpeed: 30, sigmaA: 5.0, distance: .downhillSnowSports)
        case .football:
            return Spec("figure.soccer", .ball, .soccer)
        case .tennis:
            return Spec("figure.tennis", .ball, .tennis)
        case .padel:
            return Spec("figure.racquetball", .ball, .tennis)
        case .other:
            return Spec("figure.mixed.cardio", .other, .other)
        }
    }

    var symbol: String { spec.symbol }
    var family: Family { spec.family }
    var healthKitActivity: HKWorkoutActivityType { spec.healthKit }
    var healthKitLocation: HKWorkoutSessionLocationType { spec.location }
    var elevation: TrackProfile.Elevation { spec.elevation }
    var autoPauseDefault: Bool { spec.autoPauseDefault }
    var autoPauseThreshold: Double? { spec.autoPauseThreshold }
    var maxSpeed: Double? { spec.maxSpeed }
    var sigmaA: Double? { spec.sigmaA }
    var distanceType: DistanceType? { spec.distance }
    /// Recorded with GPS: Start shows the map and asks for location.
    var hasGPS: Bool { spec.maxSpeed != nil }
    /// Recorded with the pedometer's distance (an indoor run).
    var usesPedometer: Bool { self == .indoorRunning }
    /// Speed for cycling, pace for the rest.
    var paceStyle: TrackProfile.PaceStyle { family == .cycle ? .speed : .pace }

    var trackProfile: TrackProfile {
        let s = spec
        return TrackProfile(maxSpeed: s.maxSpeed, sigmaA: s.sigmaA, autoPauseThreshold: s.autoPauseThreshold,
                            autoPauseDefault: s.autoPauseDefault, elevation: s.elevation, paceStyle: paceStyle)
    }

    /// The name's key in `Localizable.xcstrings` (its own keys: "Running" is already a status there).
    var nameKey: String { "sport.\(rawValue)" }

    /// The sport's name, as the picker, My Day and the recording screen show it.
    var name: String {
        switch self {
        case .running:
            return String(localized: "sport.running", defaultValue: "Running", comment: "Sport name.")
        case .trailRunning:
            return String(localized: "sport.trail_running", defaultValue: "Trail running", comment: "Sport name.")
        case .walking:
            return String(localized: "sport.walking", defaultValue: "Walking", comment: "Sport name.")
        case .hiking:
            return String(localized: "sport.hiking", defaultValue: "Hiking", comment: "Sport name.")
        case .cycling:
            return String(localized: "sport.cycling", defaultValue: "Cycling", comment: "Sport name.")
        case .mountainBiking:
            return String(localized: "sport.mountain_biking", defaultValue: "Mountain biking", comment: "Sport name.")
        case .gravel:
            return String(localized: "sport.gravel", defaultValue: "Gravel", comment: "Sport name: gravel cycling.")
        case .indoorRunning:
            return String(localized: "sport.indoor_running", defaultValue: "Indoor run",
                          comment: "Sport name: a run indoors (treadmill), measured by the pedometer.")
        case .indoorCycling:
            return String(localized: "sport.indoor_cycling", defaultValue: "Indoor cycling", comment: "Sport name.")
        case .rowing:
            return String(localized: "sport.rowing", defaultValue: "Rowing", comment: "Sport name.")
        case .swimming:
            return String(localized: "sport.swimming", defaultValue: "Swimming", comment: "Sport name.")
        case .strength:
            return String(localized: "sport.strength", defaultValue: "Strength", comment: "Sport name: strength training.")
        case .hiit:
            return String(localized: "sport.hiit", defaultValue: "HIIT",
                          comment: "Sport name: high-intensity interval training.")
        case .yoga:
            return String(localized: "sport.yoga", defaultValue: "Yoga", comment: "Sport name.")
        case .mobility:
            return String(localized: "sport.mobility", defaultValue: "Mobility",
                          comment: "Sport name: mobility and stretching.")
        case .climbing:
            return String(localized: "sport.climbing", defaultValue: "Climbing", comment: "Sport name.")
        case .skiing:
            return String(localized: "sport.skiing", defaultValue: "Skiing", comment: "Sport name: downhill skiing.")
        case .skiTouring:
            return String(localized: "sport.ski_touring", defaultValue: "Ski touring", comment: "Sport name.")
        case .football:
            return String(localized: "sport.football", defaultValue: "Football", comment: "Sport name: soccer.")
        case .tennis:
            return String(localized: "sport.tennis", defaultValue: "Tennis", comment: "Sport name.")
        case .padel:
            return String(localized: "sport.padel", defaultValue: "Padel", comment: "Sport name.")
        case .other:
            return String(localized: "sport.other", defaultValue: "Other",
                          comment: "Sport name: any sport not in the list.")
        }
    }

    /// The sport for a workout's `activity` (`HealthKitManager.activityName`, a tracker's or Apple Health's
    /// workout), where one corresponds; `nil` for activities that have no sport (elliptical, stairs, cool-down,
    /// core, snowboarding, cross-country skiing), which `ActivityStyle` names itself.
    init?(healthKitActivity name: String) {
        switch name {
        case "soccer": self = .football
        case "functional_strength": self = .strength
        case "crossfit": self = .hiit
        default:
            guard let sport = Sport(rawValue: name) else { return nil }
            self = sport
        }
    }
}
