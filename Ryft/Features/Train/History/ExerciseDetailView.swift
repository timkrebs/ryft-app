import Charts
import SwiftUI

/// One exercise over time: e1RM chart (90 days), PR badges, recent sets.
struct ExerciseDetailView: View {
    let exerciseID: UUID
    var name: String? = nil

    @EnvironmentObject private var library: TrainLibrary
    @State private var history: ExerciseHistory?
    @State private var loaded = false

    private var exercise: Exercise? { library.exercise(id: exerciseID) }

    /// The chart window: the last 90 days.
    private var points: [E1RMPoint] {
        let from = DayFormat.string(from: DayFormat.shift(.now, days: -89))
        return (history?.e1rm ?? []).filter { $0.day >= from }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Metrics.sectionSpacing) {
                header
                chartCard
                if let prs = history?.prs, !prs.isEmpty {
                    prCard(prs)
                }
                recentSets
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(exercise?.name ?? name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            history = library.cachedHistory(for: exerciseID)
            history = await library.history(for: exerciseID) ?? history
            loaded = true
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Estimated 1RM").ryftLabelStyle()
            Text(points.last.map { Fmt.kg($0.value) } ?? Fmt.placeholder)
                .font(.ryftNumber(size: 44))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            if let e = exercise {
                Text(([e.kind.title] + e.primaryMuscles.map(\.title)).joined(separator: " · "))
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            if let change = change {
                Text(change)
                    .font(.ryft(.callout))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// "+6.5 kg in 90 days".
    private var change: String? {
        guard let first = points.first?.value, let last = points.last?.value, points.count > 1 else { return nil }
        let delta = last - first
        let sign = delta >= 0 ? "+" : "−"
        return String(localized: "\(sign)\(Fmt.kg(abs(delta))) in 90 days")
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "e1RM", trailing: "90 days")
                if points.count >= 2 {
                    E1RMChart(points: points, best: history?.prs.first { $0.kind == .e1rm }?.value)
                        .frame(height: 180)
                } else {
                    Text(loaded ? String(localized: "Log this exercise twice to see a trend.") : String(localized: "Loading…"))
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }

    private func prCard(_ prs: [PersonalRecord]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Personal records")
                ForEach(PRKind.allCases, id: \.self) { kind in
                    if let pr = prs.first(where: { $0.kind == kind }) {
                        PRBadge(record: pr, showsDate: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentSets: some View {
        let entries = Array((history?.sessions ?? []).prefix(10))
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent sets").ryftLabelStyle()
            if entries.isEmpty {
                InlineMessage(message: loaded ? String(localized: "No sets logged for this exercise yet.")
                                              : String(localized: "Loading…"),
                              systemImage: "list.bullet")
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { i, entry in
                            if i > 0 { Divider().overlay(Theme.separator) }
                            row(entry)
                        }
                    }
                }
            }
        }
    }

    private func row(_ entry: ExerciseHistorySession) -> some View {
        let working = entry.sets.filter { !$0.isWarmup }
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.startedAt.formatted(.dateTime.day().month(.abbreviated)))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 58, alignment: .leading)
            Text(working.map(SetText.short).joined(separator: "  ·  "))
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let best = E1RM.best(of: working) {
                Text(Fmt.kgNumber(E1RM.rounded(best)))
                    .font(.ryft(.callout))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(Text("e1RM \(Fmt.kg(E1RM.rounded(best)))"))
            }
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// e1RM over time with the best as a dashed rule.
struct E1RMChart: View {
    let points: [E1RMPoint]
    var best: Double?

    private var values: [Double] { points.map(\.value) }

    var body: some View {
        let lo = (values.min() ?? 0), hi = max(values.max() ?? 1, best ?? 0)
        let pad = max(2.5, (hi - lo) * 0.15)
        Chart {
            ForEach(points) { p in
                    AreaMark(x: .value("Day", p.date), yStart: .value("Base", lo - pad), yEnd: .value("e1RM", p.value))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.25), Theme.accent.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", p.date), y: .value("e1RM", p.value))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Day", p.date), y: .value("e1RM", p.value))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(18)
            }
            if let best {
                RuleMark(y: .value("Best", best))
                    .foregroundStyle(Theme.warning.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("PR \(Fmt.kgNumber(best))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.warning)
                    }
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.separator)
                AxisValueLabel().foregroundStyle(Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Estimated one-rep max, last 90 days"))
        .accessibilityValue(Text(summary))
        .accessibilityChartDescriptor(SeriesChartDescriptor(title: String(localized: "Estimated 1RM"), valueName: "kg",
                                                            points: points.map { ($0.date, $0.value) },
                                                            valueText: { Fmt.kg($0) }))
    }

    private var summary: String {
        guard let first = values.first, let last = values.last else { return String(localized: "No data") }
        return String(localized: "From \(Fmt.kg(first)) to \(Fmt.kg(last)), best \(Fmt.kg(best ?? values.max() ?? last)).")
    }
}

#Preview("Exercise detail · dark") {
    NavigationStack { ExerciseDetailView(exerciseID: MockTrain.bench.id) }
        .previewEnvironment()
}

#Preview("Exercise detail · light") {
    NavigationStack { ExerciseDetailView(exerciseID: MockTrain.squat.id) }
        .previewEnvironment(scheme: .light)
}
