import SwiftUI

struct RecoveryScoreGuide: View {
    @Environment(AppState.self) private var state

    var body: some View {
        SubpageScaffold(Text("What shapes your scores?")) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                GroupedCard(Text("Recovery"), footer: Text("Recovery combines your overnight HRV, resting heart rate, breathing rate and sleep performance. HRV above your usual level and a resting heart rate below your usual level tend to raise the score.")) {
                    if let score = state.today?.score {
                        measurement(Text("Heart rate variability"), score.hrvMs, baseline: score.hrvBaselineMs, unit: "ms")
                        measurement(Text("Resting heart rate"), score.rhr, baseline: score.rhrBaseline, unit: "bpm")
                        if let sleep = score.sleepPerformance {
                            GroupedRow.value(Text("Sleep performance"), value: Text("\(sleep)%"))
                        }
                    }
                }
                GroupedCard(Text("Readiness"), footer: Text("Readiness combines Recovery and sleep performance. High strain yesterday can lower it when today’s recovery is low.")) {
                    if let value = state.today?.score.readiness {
                        GroupedRow.value(Text("Today"), value: Text("\(value)%"))
                    }
                }
                GroupedCard(Text("Strain"), footer: Text("Strain reflects the intensity and duration of your heart-rate activity plus logged strength work. Higher values mean more load accumulated today.")) {
                    if let value = state.today?.score.strain {
                        GroupedRow.value(Text("Today"), value: NutritionDisplay.score(value, max: 21))
                    }
                }
                GroupFooter(Text("Nutrition-to-Recovery scores your logged food, timing and fueling around training. Coaching uses these entries to adjust fueling targets and give context to changes in your overnight readings."))
            }
        }
    }

    @ViewBuilder
    private func measurement(_ title: Text, _ value: Double?, baseline: Double?, unit: String) -> some View {
        if let value {
            let detail = baseline.map { Text("Usual: \(NutritionDisplay.number($0)) \(unit)") }
            GroupedRow.value(title, value: NutritionDisplay.amount(value, unit: unit), detail: detail)
        }
    }
}
