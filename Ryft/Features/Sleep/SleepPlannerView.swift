import SwiftUI

/// Sleep → Planner: pick a wake time, get three bedtimes (100 / 85 / 70 % of
/// tonight's need), the time in bed behind them, and why the need is what it is.
struct SleepPlannerSection: View {
    let model: SleepPlannerViewModel
    @State private var showsWhy = false

    var body: some View {
        VStack(spacing: Theme.Metrics.sectionSpacing) {
            Card {
                DatePicker("Wake up at", selection: Binding(get: { model.wake }, set: { model.setWake($0) }),
                           displayedComponents: .hourAndMinute)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
            }
            if let plan = model.plan {
                bedtimes(plan)
                why(plan)
                if let asOf = model.asOf {
                    Label(String(localized: "As of \(asOf.formatted(date: .abbreviated, time: .shortened))"),
                          systemImage: "clock.arrow.circlepath")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else if model.isLoading {
                ProgressView().tint(Theme.accent).padding(.top, 40)
            } else if let error = model.error {
                InlineMessage(message: error, retry: { await model.load() })
            }
        }
    }

    private func bedtimes(_ plan: SleepPlan) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Go to bed")
                ForEach(model.options) { option in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.time(option.bedtime))
                            .font(.ryft(.metric))
                            .monospacedDigit()
                            .foregroundStyle(option.share == 100 ? Theme.textPrimary : Theme.textSecondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(option.share) % of your need")
                                .font(.ryft(.callout))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(Fmt.duration(minutes: option.sleepMin)) asleep")
                                .font(.ryft(.caption))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if option.share != 70 { Divider().overlay(Theme.separator) }
                }
                Text("Time in bed \(Fmt.duration(minutes: plan.inBedMin)) at \(plan.efficiency) % efficiency.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func why(_ plan: SleepPlan) -> some View {
        Card {
            DisclosureGroup(isExpanded: $showsWhy) {
                VStack(spacing: 10) {
                    StatRow(title: "Baseline", value: Fmt.duration(minutes: plan.basis.base))
                    StatRow(title: "Today's strain so far", value: "+" + Fmt.duration(minutes: plan.basis.strainTopup))
                    StatRow(title: "Sleep debt", value: "+" + Fmt.duration(minutes: plan.basis.debtTopup))
                    if plan.basis.napCredit > 0 {
                        StatRow(title: "Nap credit", value: Fmt.duration(minutes: -plan.basis.napCredit))
                    }
                    Divider().overlay(Theme.separator)
                    StatRow(title: "Tonight's need", value: Fmt.duration(minutes: plan.needMin))
                }
                .padding(.top, 10)
            } label: {
                Text("Why this need")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.textSecondary)
        }
    }
}

#Preview("Planner · dark") {
    let state = AppState.preview(flags: [.sleepPlanner: true])
    let model = SleepPlannerViewModel(state: state)
    return ScrollView { SleepPlannerSection(model: model).padding() }
        .background(Theme.background)
        .task { await model.load() }
        .previewEnvironment(state)
}

#Preview("Planner · light") {
    let state = AppState.preview(flags: [.sleepPlanner: true])
    let model = SleepPlannerViewModel(state: state)
    return ScrollView { SleepPlannerSection(model: model).padding() }
        .background(Theme.background)
        .task { await model.load() }
        .previewEnvironment(state, scheme: .light)
}
