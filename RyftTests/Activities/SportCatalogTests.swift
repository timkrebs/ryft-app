import Foundation
import HealthKit
import Testing
import UIKit
@testable import Ryft

/// The sport catalogue (design.md §2.1, §11.1 Catalogue).
@Suite("Sport catalogue")
struct SportCatalogTests {
    @Test func everyRawValueIsTheAPIsAndUnique() {
        #expect(Sport.allCases.count == 22)
        #expect(Set(Sport.allCases.map(\.rawValue)).count == Sport.allCases.count)
        #expect(Sport.allCases.map(\.rawValue) == [
            "running", "trail_running", "walking", "hiking", "cycling", "mountain_biking", "gravel", "indoor_running",
            "indoor_cycling", "rowing", "swimming", "strength", "hiit", "yoga", "mobility", "climbing", "skiing",
            "ski_touring", "football", "tennis", "padel", "other",
        ])
    }

    @Test(arguments: Sport.allCases)
    func everySportHasANameASymbolAHealthKitTypeAndAFamily(_ sport: Sport) {
        #expect(!sport.name.isEmpty)
        #expect(sport.name != sport.nameKey, "\(sport.nameKey) isn't in the string catalog")
        #expect(sport.nameKey == "sport.\(sport.rawValue)")
        #expect(UIImage(systemName: sport.symbol) != nil, "\(sport.symbol) isn't an SF Symbol")
        #expect(Sport.Family.allCases.contains(sport.family))
        #expect((sport.healthKitActivity == .other) == (sport == .other))
    }

    @Test(arguments: Sport.allCases)
    func gpsSportsHaveASpeedGateAndProcessNoiseTheOthersNone(_ sport: Sport) {
        #expect((sport.maxSpeed != nil) == sport.hasGPS)
        #expect((sport.sigmaA != nil) == sport.hasGPS)
        if sport.hasGPS {
            #expect(sport.healthKitLocation == .outdoor)
            #expect(sport.elevation != .none)
            #expect(sport.autoPauseThreshold != nil)
            #expect(sport.distanceType != nil)
        } else {
            #expect(sport.elevation == .none)
        }
        // Auto-pause on by default needs a threshold to pause at.
        if sport.autoPauseDefault { #expect(sport.autoPauseThreshold != nil) }
    }

    @Test func theTableAsDesigned() {
        let gps = Sport.allCases.filter(\.hasGPS)
        #expect(gps == [.running, .trailRunning, .walking, .hiking, .cycling, .mountainBiking, .gravel, .skiing,
                        .skiTouring])
        #expect(Sport.allCases.filter { $0.elevation == .primary } == [.trailRunning, .hiking, .mountainBiking,
                                                                           .skiTouring])
        #expect(Sport.allCases.filter(\.autoPauseDefault) == [.running, .trailRunning, .cycling, .mountainBiking,
                                                               .gravel, .indoorRunning])
        #expect(Sport.running.maxSpeed == 9 && Sport.running.sigmaA == 1.5 && Sport.running.autoPauseThreshold == 1.0)
        #expect(Sport.cycling.maxSpeed == 25 && Sport.cycling.sigmaA == 3.0)
        #expect(Sport.skiing.maxSpeed == 40 && Sport.skiing.sigmaA == 5.0)
        // Indoor runs: the pedometer, auto-pause on cadence 0.
        #expect(Sport.indoorRunning.usesPedometer && !Sport.indoorRunning.hasGPS)
        #expect(Sport.indoorRunning.autoPauseThreshold == 0 && Sport.indoorRunning.healthKitLocation == .indoor)
        #expect(Sport.allCases.filter(\.usesPedometer) == [.indoorRunning])
        // Apple's closest types (plan D1-8).
        #expect(Sport.padel.healthKitActivity == .tennis)
        #expect(Sport.skiTouring.healthKitActivity == .crossCountrySkiing)
        #expect(Sport.football.healthKitActivity == .soccer)
        #expect(Sport.mobility.healthKitActivity == .flexibility)
    }

    @Test func familiesAndPaceStyles() {
        let families = Dictionary(grouping: Sport.allCases, by: \.family)
        #expect(families[.foot] == [.running, .trailRunning, .walking, .hiking, .indoorRunning])
        #expect(families[.cycle] == [.cycling, .mountainBiking, .gravel, .indoorCycling])
        #expect(families[.water] == [.rowing, .swimming])
        #expect(families[.gym] == [.strength, .hiit, .yoga, .mobility, .climbing])
        #expect(families[.snow] == [.skiing, .skiTouring])
        #expect(families[.ball] == [.football, .tennis, .padel])
        #expect(families[.other] == [.other])
        #expect(Sport.allCases.filter { $0.paceStyle == .speed } == families[.cycle])
    }

    @Test func distanceTypes() {
        #expect(Sport.running.distanceType?.identifier == .distanceWalkingRunning)
        #expect(Sport.indoorRunning.distanceType?.identifier == .distanceWalkingRunning)
        #expect(Sport.gravel.distanceType?.identifier == .distanceCycling)
        #expect(Sport.skiing.distanceType?.identifier == .distanceDownhillSnowSports)
        #expect(Sport.swimming.distanceType?.identifier == .distanceSwimming)
        // iOS 17 has no distance type for these.
        for sport in [Sport.rowing, .strength, .hiit, .yoga, .mobility, .climbing, .football, .tennis, .padel, .other] {
            #expect(sport.distanceType == nil)
        }
    }

    @Test func theTrackProfileIsTheTables() {
        let run = Sport.running.trackProfile
        #expect(run == TrackProfile(maxSpeed: 9, sigmaA: 1.5, autoPauseThreshold: 1.0, autoPauseDefault: true,
                                    elevation: .secondary, paceStyle: .pace))
        #expect(Sport.mountainBiking.trackProfile == TrackProfile(maxSpeed: 22, sigmaA: 3.0, autoPauseThreshold: 1.2,
                                                                  autoPauseDefault: true, elevation: .primary,
                                                                  paceStyle: .speed))
        #expect(Sport.indoorRunning.trackProfile == TrackProfile(maxSpeed: nil, sigmaA: nil, autoPauseThreshold: 0,
                                                                 autoPauseDefault: true, elevation: .none,
                                                                 paceStyle: .pace))
        #expect(Sport.yoga.trackProfile == TrackProfile(maxSpeed: nil, sigmaA: nil, autoPauseThreshold: nil,
                                                        autoPauseDefault: false, elevation: .none, paceStyle: .pace))
    }

    @Test func healthKitActivityNamesMapWhereASportCorresponds() {
        let cases: [(String, Sport?)] = [
            ("running", .running), ("walking", .walking), ("hiking", .hiking), ("cycling", .cycling),
            ("swimming", .swimming), ("rowing", .rowing), ("strength", .strength), ("functional_strength", .strength),
            ("crossfit", .hiit), ("hiit", .hiit), ("yoga", .yoga), ("soccer", .football), ("tennis", .tennis),
            ("skiing", .skiing), ("other", .other),
            // No sport: ActivityStyle names these itself.
            ("elliptical", nil), ("stairs", nil), ("cooldown", nil), ("core", nil), ("snowboarding", nil),
            ("xc_skiing", nil), ("something_new", nil),
        ]
        for (name, sport) in cases { #expect(Sport(healthKitActivity: name) == sport, "\(name)") }
    }

    /// Every name `HealthKitManager.activityName` produces is either a sport or one of the names without one.
    @Test func everyHealthKitActivityNameIsCovered() {
        let types: [HKWorkoutActivityType] = [.running, .walking, .hiking, .cycling, .swimming, .rowing, .elliptical,
                                              .stairClimbing, .traditionalStrengthTraining, .functionalStrengthTraining,
                                              .crossTraining, .highIntensityIntervalTraining, .yoga, .coreTraining,
                                              .soccer, .tennis, .crossCountrySkiing, .downhillSkiing, .snowboarding,
                                              .cooldown, .golf]
        let withoutSport: Set = ["elliptical", "stairs", "core", "xc_skiing", "snowboarding", "cooldown"]
        for type in types {
            let name = HealthKitManager.activityName(type)
            #expect(Sport(healthKitActivity: name) != nil || withoutSport.contains(name), "\(name)")
        }
    }

    @Test func anUnknownWireValueDecodesAsOther() throws {
        let decoded = try APIClient.jsonDecoder.decode([Sport].self, from: Data(#"["padel", "kitesurfing"]"#.utf8))
        #expect(decoded == [.padel, .other])
        let encoded = try APIClient.jsonEncoder.encode([Sport.skiTouring, .indoorRunning])
        #expect(String(bytes: encoded, encoding: .utf8) == #"["ski_touring","indoor_running"]"#)
    }

    /// The deployment target is iOS 17: every symbol must exist there, not only on the simulator's newer iOS
    /// (`figure.run.treadmill`, for one, is iOS 18). Read from the system's own availability table when the
    /// runtime has it.
    @Test(.enabled(if: SymbolAvailability.table != nil))
    func everySymbolExistsOnIOS17() throws {
        let table = try #require(SymbolAvailability.table)
        for sport in Sport.allCases {
            let release = try #require(table.iOS(for: sport.symbol), "\(sport.symbol) isn't in the table")
            #expect(release.compare("17.0", options: .numeric) != .orderedDescending, "\(sport.symbol): iOS \(release)")
        }
    }
}

/// CoreGlyphs' `name_availability.plist`: symbol → year, year → iOS release.
private struct SymbolAvailability {
    let symbols: [String: String]
    let releases: [String: [String: String]]

    func iOS(for symbol: String) -> String? { symbols[symbol].flatMap { releases[$0]?["iOS"] } }

    static let table: SymbolAvailability? = {
        let relative = "System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist"
        let roots = [ProcessInfo.processInfo.environment["SIMULATOR_ROOT"],
                     ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"], "/"].compactMap { $0 }
        var urls = roots.map { URL(fileURLWithPath: $0).appendingPathComponent(relative) }
        if let bundled = Bundle(identifier: "com.apple.CoreGlyphs")?.url(forResource: "name_availability",
                                                                          withExtension: "plist") {
            urls.insert(bundled, at: 0)
        }
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let symbols = plist["symbols"] as? [String: String],
                  let releases = plist["year_to_release"] as? [String: [String: String]] else { continue }
            return SymbolAvailability(symbols: symbols, releases: releases)
        }
        return nil
    }()
}
