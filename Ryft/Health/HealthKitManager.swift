// Reads everything the backend needs out of HealthKit.
//
// Garmin Connect writes heart rate, resting HR, HRV, respiratory rate, SpO2,
// sleep (with stages on recent firmware), workouts, steps and active energy
// into Apple Health — enable it in Garmin Connect → More → Settings → Apple
// Health. From there this class is watch-agnostic.
//
// Incremental reads use HKAnchoredObjectQuery: HealthKit hands back only the
// samples added since the stored anchor, so a sync after the first backfill
// is small. Anchors are persisted per type after each successful upload.
import Foundation
import HealthKit

struct HealthDelta {
    var samples: [Sample] = []
    var sleep: [SleepSegment] = []
    var workouts: [Workout] = []
    var isEmpty: Bool { samples.isEmpty && sleep.isEmpty && workouts.isEmpty }
    var count: Int { samples.count + sleep.count + workouts.count }
}

/// Who the per-user local state belongs to: the Supabase user id AuthService stores.
enum AccountScope {
    static let defaultsKey = "auth.lastUserID"

    static func current(_ defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: defaultsKey)
    }
}

final class HealthKitManager {
    static let shared = HealthKitManager()
    let store = HKHealthStore()

    /// How far back the very first sync reaches. 90 days gives the scoring
    /// service enough history to build baselines on day one.
    var backfillDays = 90
    /// The most samples one anchored page may hold; `SyncEngine` sizes pages below it by bytes.
    var pageSize = 20_000

    struct QuantitySpec {
        let hkType: HKQuantityType
        let type: SampleType
        let unit: HKUnit
        let scale: Double // multiply the HK value (SpO2 is 0..1 in HealthKit)
        let unitLabel: String
    }

    let quantities: [QuantitySpec] = [
        .init(hkType: HKQuantityType(.heartRate), type: .heartRate, unit: .count().unitDivided(by: .minute()), scale: 1, unitLabel: "bpm"),
        .init(hkType: HKQuantityType(.heartRateVariabilitySDNN), type: .hrvSDNN, unit: .secondUnit(with: .milli), scale: 1, unitLabel: "ms"),
        .init(hkType: HKQuantityType(.restingHeartRate), type: .restingHR, unit: .count().unitDivided(by: .minute()), scale: 1, unitLabel: "bpm"),
        .init(hkType: HKQuantityType(.respiratoryRate), type: .respiratoryRate, unit: .count().unitDivided(by: .minute()), scale: 1, unitLabel: "brpm"),
        .init(hkType: HKQuantityType(.oxygenSaturation), type: .spo2, unit: .percent(), scale: 100, unitLabel: "%"),
        .init(hkType: HKQuantityType(.vo2Max), type: .vo2max, unit: HKUnit(from: "ml/kg*min"), scale: 1, unitLabel: "ml/kg/min"),
        .init(hkType: HKQuantityType(.activeEnergyBurned), type: .activeEnergy, unit: .kilocalorie(), scale: 1, unitLabel: "kcal"),
        .init(hkType: HKQuantityType(.stepCount), type: .steps, unit: .count(), scale: 1, unitLabel: "count"),
    ]
    let sleepType = HKCategoryType(.sleepAnalysis)
    let workoutType = HKObjectType.workoutType()

    var readTypes: Set<HKObjectType> {
        Set(quantities.map { $0.hkType as HKObjectType } + [sleepType, workoutType])
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: authorization

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: anchors

    private let defaults = UserDefaults.standard

    /// Anchors belong to the signed-in user, so another account on this phone
    /// starts its own 90-day backfill.
    private func anchorKey(_ id: String) -> String {
        "hk.anchor.\(AccountScope.current(defaults) ?? "signed-out").\(id)"
    }

    private var anchorIDs: [String] { quantities.map(\.type.rawValue) + ["sleep", "workouts"] }

    /// Anchors from before they were per user move to the current user once.
    func migrateLegacyAnchors() {
        guard AccountScope.current(defaults) != nil else { return }
        for id in anchorIDs {
            let legacy = "hk.anchor.\(id)"
            guard let data = defaults.data(forKey: legacy) else { continue }
            if defaults.data(forKey: anchorKey(id)) == nil { defaults.set(data, forKey: anchorKey(id)) }
            defaults.removeObject(forKey: legacy)
        }
    }

    func anchor(for id: String) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: anchorKey(id)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    func save(anchor: HKQueryAnchor, for id: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            defaults.set(data, forKey: anchorKey(id))
        }
    }

    /// The current user's anchors (called on log out and account switch, before the new id is stored).
    func resetAnchors() {
        for id in anchorIDs { defaults.removeObject(forKey: anchorKey(id)) }
    }

    /// Only applied on the first query for a type (no anchor yet).
    var backfillPredicate: NSPredicate {
        let start = Calendar.current.date(byAdding: .day, value: -backfillDays, to: .now)!
        return HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
    }

    // MARK: incremental reads
    //
    // Each function returns one page plus the anchor that marks its end. The
    // caller uploads the page, then persists the anchor, then asks for the next
    // page until `more` is false. That ordering is what makes sync crash-safe.

    struct Page<T> {
        let items: [T]
        let anchor: HKQueryAnchor?
        let more: Bool
        /// Records deleted in Apple Health since the anchor (`deletedObjects`).
        var deleted: [UUID] = []
    }

    func quantityPage(_ spec: QuantitySpec, anchor: HKQueryAnchor?, predicate: NSPredicate?,
                      limit: Int) async throws -> Page<Sample> {
        let desc = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: spec.hkType, predicate: predicate)], anchor: anchor, limit: limit)
        let result = try await desc.result(for: store)
        MainThread.assertOff("Mapping \(spec.type.rawValue)")
        let items = result.addedSamples.map { s in
            Sample(type: spec.type, start: s.startDate, end: s.endDate,
                   value: s.quantity.doubleValue(for: spec.unit) * spec.scale,
                   unit: spec.unitLabel, source: Self.sourceName(s), sourceBundleId: Self.sourceBundleID(s))
        }
        return Page(items: items, anchor: result.newAnchor, more: result.addedSamples.count >= limit,
                    deleted: result.deletedObjects.map(\.uuid))
    }

    func sleepPage(anchor: HKQueryAnchor?, predicate: NSPredicate?, limit: Int) async throws -> Page<SleepSegment> {
        let desc = HKAnchoredObjectQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)], anchor: anchor, limit: limit)
        let result = try await desc.result(for: store)
        MainThread.assertOff("Mapping sleep")
        let items = result.addedSamples.compactMap { s -> SleepSegment? in
            guard let stage = Self.sleepStage(s.value) else { return nil }
            return SleepSegment(start: s.startDate, end: s.endDate, stage: stage, source: Self.sourceName(s),
                                sourceBundleId: Self.sourceBundleID(s))
        }
        return Page(items: items, anchor: result.newAnchor, more: result.addedSamples.count >= limit,
                    deleted: result.deletedObjects.map(\.uuid))
    }

    func workoutPage(anchor: HKQueryAnchor?, predicate: NSPredicate?, limit: Int) async throws -> Page<Workout> {
        let desc = HKAnchoredObjectQueryDescriptor(predicates: [.workout(predicate)], anchor: anchor, limit: limit)
        let result = try await desc.result(for: store)
        MainThread.assertOff("Mapping workouts")
        let items = result.addedSamples.map { Self.map(workout: $0) }
        return Page(items: items, anchor: result.newAnchor, more: result.addedSamples.count >= limit,
                    deleted: result.deletedObjects.map(\.uuid))
    }

    // MARK: background delivery
    //
    // HealthKit wakes the app (briefly) when new samples of an observed type arrive;
    // we use that to run an incremental sync. The observers must be registered during
    // launch (RyftApp.init): in a background launch nothing else runs before HealthKit
    // delivers. Needs the HealthKit "Background Delivery" entitlement.

    /// Sleep, workouts and HRV: the records that change a score. Heart rate arrives
    /// constantly and would wake the app too often; it rides along with these syncs.
    var observedTypes: [HKSampleType] { [sleepType, workoutType, HKQuantityType(.heartRateVariabilitySDNN)] }

    /// `.immediate` for the observed types only. Idempotent: called on every launch.
    func enableBackgroundDelivery() async {
        for t in observedTypes {
            try? await store.enableBackgroundDelivery(for: t, frequency: .immediate)
        }
    }

    private var observers: [HKObserverQuery] = []

    /// `onChange` gets the delivery's completion and must call it, right after the upload
    /// (not after scoring and refreshes): a late completion makes HealthKit back off.
    func startObserving(onChange: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void) {
        guard observers.isEmpty else { return }
        for t in observedTypes {
            let q = HKObserverQuery(sampleType: t, predicate: nil) { _, completion, error in
                guard error == nil else { return completion() }
                onChange { completion() }
            }
            store.execute(q)
            observers.append(q)
        }
    }

    // MARK: mapping

    static func sourceName(_ s: HKSample) -> String {
        s.sourceRevision.source.name
    }

    /// e.g. `com.ouraring.oura`; Profile → Data sources shows which app sent what.
    static func sourceBundleID(_ s: HKSample) -> String? {
        let id = s.sourceRevision.source.bundleIdentifier
        return id.isEmpty ? nil : id
    }

    static func sleepStage(_ raw: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: raw) {
        case .inBed: return .inBed
        case .asleepUnspecified: return .asleep
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        case .awake: return .awake
        default: return nil
        }
    }

    static func map(workout w: HKWorkout) -> Workout {
        func avg(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) -> Double? {
            w.statistics(for: HKQuantityType(id))?.averageQuantity()?.doubleValue(for: unit)
        }
        func max(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) -> Double? {
            w.statistics(for: HKQuantityType(id))?.maximumQuantity()?.doubleValue(for: unit)
        }
        func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) -> Double? {
            w.statistics(for: HKQuantityType(id))?.sumQuantity()?.doubleValue(for: unit)
        }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let distance = sum(.distanceWalkingRunning, .meter()) ?? sum(.distanceCycling, .meter())
            ?? sum(.distanceSwimming, .meter()) ?? sum(.distanceWheelchair, .meter())
        return Workout(id: w.uuid, activity: activityName(w.workoutActivityType),
                       start: w.startDate, end: w.endDate,
                       avgHr: avg(.heartRate, bpm), maxHr: max(.heartRate, bpm),
                       energyKcal: sum(.activeEnergyBurned, .kilocalorie()), distanceM: distance,
                       source: sourceName(w), strain: nil, sourceBundleId: sourceBundleID(w))
    }

    static func activityName(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "running"
        case .walking: return "walking"
        case .hiking: return "hiking"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .rowing: return "rowing"
        case .elliptical: return "elliptical"
        case .stairClimbing: return "stairs"
        case .traditionalStrengthTraining: return "strength"
        case .functionalStrengthTraining: return "functional_strength"
        case .crossTraining: return "crossfit"
        case .highIntensityIntervalTraining: return "hiit"
        case .yoga: return "yoga"
        case .coreTraining: return "core"
        case .soccer: return "soccer"
        case .tennis: return "tennis"
        case .crossCountrySkiing: return "xc_skiing"
        case .downhillSkiing: return "skiing"
        case .snowboarding: return "snowboarding"
        case .cooldown: return "cooldown"
        default: return "other"
        }
    }
}
