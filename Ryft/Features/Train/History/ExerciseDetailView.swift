import Charts
import SwiftUI

/// One exercise over time: e1RM chart (90 days), PR badges, recent sets.
struct ExerciseDetailView: View {
    let exerciseID: UUID
    var name: String? = nil

    @Environment(TrainLibrary.self) private var library
    @Environment(\.appEnvironment) private var env

    var body: some View {
        ExerciseDetailScreen(model: ExerciseDetailViewModel(exerciseID: exerciseID, name: name,
                                                            library: library, clock: env.clock))
    }
}

/// Layout only; the first model handed in is kept for the screen's lifetime.
private struct ExerciseDetailScreen: View {
    @State var model: ExerciseDetailViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Metrics.sectionSpacing) {
                header
                chartCard
                if !model.records.isEmpty {
                    prCard(model.records)
                }
                recentSets
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await model.load() }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Estimated 1RM").ryftLabelStyle()
            Text(model.current)
                .font(.ryftNumber(size: 44))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            if let subtitle = model.subtitle {
                Text(subtitle)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            if let change = model.change {
                Text(change)
                    .font(.ryft(.callout))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                ChartHeader(spec: .e1rm, value: model.points.last?.value, delta: model.lastDelta,
                            deltaReference: String(localized: "vs last"), window: ChartWindow.quarter.title)
                if model.hasTrend {
                    E1RMChart(points: model.points, best: model.bestE1RM)
                        .frame(height: 180)
                } else {
                    Text(model.emptyChartText)
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
        let rows = model.recentRows
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent sets").ryftLabelStyle()
            if rows.isEmpty {
                InlineMessage(message: model.emptySetsText, systemImage: "list.bullet")
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            if row.id > 0 { Divider().overlay(Theme.separator) }
                            rowView(row)
                        }
                    }
                }
            }
        }
    }

    private func rowView(_ row: ExerciseDetailViewModel.RecentRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.date)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 58, alignment: .leading)
            Text(row.sets)
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let best = row.bestText {
                Text(best)
                    .font(.ryft(.callout))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(Text(row.bestSpoken ?? best))
            }
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// e1RM over the last 90 days: 1.5 pt linear line, markers at the latest
/// session and the window's best, the PR as a dashed reference, nice kg bounds,
/// monthly ticks.
struct E1RMChart: View {
    let points: [E1RMPoint]
    var best: Double?

    private var values: [Double] { points.map(\.value) }

    var body: some View {
        let spec = MetricSpec.e1rm
        let window = ChartWindow.quarter
        let scale = ChartStyle.scale(for: values + [best].compactMap { $0 }, spec: spec)
        let last = points.last
        let top = points.max { $0.value < $1.value }
        Chart {
            if let best {
                BaselineRule(value: best, label: String(localized: "PR \(Fmt.kg(best))"))
            }
            ForEach(points) { p in
                LineMark(x: .value("Day", p.date), y: .value("e1RM", p.value))
                    .interpolationMethod(.linear)
                    .foregroundStyle(spec.color)
                    .lineStyle(ChartStyle.line)
            }
            if let top, top.date != last?.date {
                PointMark(x: .value("Day", top.date), y: .value("e1RM", top.value))
                    .symbol {
                        Circle()
                            .strokeBorder(spec.color, lineWidth: 1)
                            .background(Circle().fill(Theme.surface))
                            .frame(width: ChartStyle.marker.width, height: ChartStyle.marker.height)
                    }
            }
            if let last {
                PointMark(x: .value("Day", last.date), y: .value("e1RM", last.value))
                    .foregroundStyle(spec.color)
                    .symbolSize(ChartStyle.marker)
                    .annotation(position: .top, spacing: 3) {
                        Text(Fmt.kgNumber(last.value))
                            .font(ChartStyle.axisFont)
                            .foregroundStyle(Theme.textPrimary)
                    }
            }
        }
        .chartXScale(domain: window.domain(endingAt: .now))
        .chartYScale(domain: scale.domain)
        .chartXAxis { ChartStyle.xAxis(window.ticks(endingAt: .now), format: window.format) }
        .chartYAxis { ChartStyle.yAxis(scale.ticks, unit: "kg", label: spec.axis) }
        .chartAppear()
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
