import Foundation
import HealthKit
import SwiftUI

extension HealthKitManager {
    /// Only reads the selected day. Import review precedes sending any readings to the Platform.
    func nutritionGlucose(on date: Date, timezone: String) async throws -> NutritionGlucoseBatch {
        let type = HKQuantityType(.bloodGlucose)
        try await store.requestAuthorization(toShare: [], read: [type])
        let calendar = NutritionDay.calendar(timezone)
        guard let window = calendar.dateInterval(of: .day, for: date) else { throw NutritionInputError.invalidGlucoseFile }
        let period = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: .strictStartDate)
        let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: period)],
                                            sortDescriptors: [SortDescriptor(\.startDate)])
        let unit = HKUnit(from: "mg/dL")
        let samples = try await query.result(for: store)
        var readings = [Int64: NutritionGlucoseReading]()
        for sample in samples where sample.startDate < window.end {
            // The sync JSON contract records whole-second timestamps.
            let key = Int64(sample.startDate.timeIntervalSince1970.rounded(.down))
            let value = sample.quantity.doubleValue(for: unit)
            if value > 0, value <= 10_000 {
                readings[key] = .init(timestamp: Date(timeIntervalSince1970: Double(key)), glucoseMgDl: value)
            }
        }
        return NutritionGlucoseBatch(samples: readings.values.sorted { $0.timestamp < $1.timestamp })
    }
}

struct NutritionWeightSharingView: View {
    let model: NutritionDiaryModel
    var allowsEnrollment = true
    @Environment(\.appEnvironment) private var env
    @Environment(ScreenModels.self) private var screens
    @State private var enabled: Bool?
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        if let health = env.health as? HealthKitManager, health.isAvailable {
            let isSharing = enabled ?? health.sharesBodyMass
            if (allowsEnrollment && model.hasFullAccess) || isSharing {
                GroupedCard(Text("Apple Health weigh-ins"),
                            footer: Text("Shared weigh-ins inform your coaching weight trend. You can stop future sharing here.")) {
                    GroupedRow.action(isSharing ? Text("Stop sharing weigh-ins") : Text("Share weigh-ins"),
                                      systemImage: "heart", busy: busy) {
                        Task { await toggle(health, isSharing: isSharing) }
                    }
                    if let failure {
                        Text(verbatim: failure).font(.ryft(.caption)).foregroundStyle(Theme.textSecondary).nutritionField()
                    }
                }
            }
        }
    }

    private func toggle(_ health: HealthKitManager, isSharing: Bool) async {
        guard !busy, let account = model.account else { return }
        busy = true
        defer { busy = false }
        failure = nil
        do {
            try model.needsSignedInAccount()
            if isSharing {
                health.stopBodyMass()
                enabled = false
            } else if allowsEnrollment {
                try model.needsFullAccess()
                try await health.requestBodyMass(for: account)
                if model.hasSignedInAccount && !model.hasFullAccess {
                    health.stopBodyMass()
                }
                try model.needsFullAccess()
                enabled = health.sharesBodyMass
                await health.enableBackgroundDelivery()
                await screens.coordinator.run(.userInitiated)
            }
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }
}
