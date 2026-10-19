import SwiftUI
import Charts

/// Sleep: Day (stages, quality, details) and Week / Month (nightly bars).
struct SleepView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var model = SleepViewModel()

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                titleRow
                SegmentedPicker(selection: $model.mode, options: SleepMode.allCases, title: \.title)
                switch model.mode {
                case .day: day
                case .week, .month: SleepRangeSection(range: model.range, isLoading: model.isLoading)
                }
            }
        }
        .task(id: TaskKey(mode: model.mode, refreshed: state.lastUpdated)) { await model.load(state: state) }
    }

    private struct TaskKey: Equatable {
        let mode: SleepMode
        let refreshed: Date?
    }

    // MARK: title with day picker

    private var titleRow: some View {
        HStack {
            stepButton("chevron.left", label: "Previous night", days: -1, enabled: model.mode == .day)
            Spacer()
            VStack(spacing: 2) {
                Text("Sleep")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(model.mode == .day ? (model.isToday ? String(localized: "Last night") : Fmt.dayTitle(model.date))
                                        : model.mode == .week ? String(localized: "Last 7 nights")
                                                              : String(localized: "Last 30 nights"))
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            stepButton("chevron.right", label: "Next night", days: 1, enabled: model.mode == .day && !model.isToday)
        }
    }

    private func stepButton(_ icon: String, label: LocalizedStringKey, days: Int, enabled: Bool) -> some View {
        Button {
            Task { await model.step(by: days, state: state) }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary.opacity(0.4))
        .disabled(!enabled)
        .opacity(model.mode == .day ? 1 : 0)
        .accessibilityLabel(Text(label))
    }

    // MARK: day

    @ViewBuilder
    private var day: some View {
        if let sleep = model.sleep {
            SleepDaySection(sleep: sleep, score: model.detail?.score)
        } else if model.isLoading {
            ProgressView().tint(Theme.accent).padding(.top, 40)
        } else if let error = model.error {
            InlineMessage(message: error, retry: { await model.load(state: state) })
        } else {
            InlineMessage(message: String(localized: "No sleep recorded for this night."),
                          systemImage: "moon.zzz")
            if state.hasNoHealthData { HealthAccessHint() }
        }
    }
}

/// Day mode content, separated so previews can feed it directly.
struct SleepDaySection: View {
    let sleep: SleepDetail
    let score: DailyScore?

    var body: some View {
        VStack(spacing: Theme.Metrics.sectionSpacing) {
            VStack(spacing: 4) {
                Text(Fmt.duration(minutes: sleep.totalMin))
                    .font(.ryft(.numberLarge))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("Total sleep")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)

            stages
            quality
            details
        }
    }

    @ViewBuilder
    private var stages: some View {
        let shares = sleep.displayStages
        if sleep.hasStages, shares.contains(where: { $0.min > 0 }) {
            VStack(spacing: 14) {
                StageBar(stages: shares, height: 28)
                if !sleep.segments.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeader(title: "Hypnogram")
                            Hypnogram(segments: sleep.segments)
                        }
                    }
                }
                Card {
                    VStack(spacing: 14) {
                        ForEach(shares) { StageRow(share: $0) }
                    }
                }
            }
        } else {
            InlineMessage(message: String(localized: "Your watch didn't record sleep stages for this night — only the total."),
                          systemImage: "waveform.path")
        }
    }

    private var quality: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sleep quality")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(sleep.resolvedQualityLabel ?? Fmt.placeholder)
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Text(Fmt.percent(sleep.quality))
                        .font(.ryft(.headline))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                ProgressBar(value: sleep.quality.map { Double($0) / 100 })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep quality"))
        .accessibilityValue(Text("\(sleep.resolvedQualityLabel ?? Fmt.placeholder), \(Fmt.percent(sleep.quality))"))
    }

    private var details: some View {
        let need = score?.sleepNeedMin
        let actual = score?.sleepActualMin ?? sleep.totalMin
        let debt = score?.sleepDebtMin
        return Card {
            VStack(spacing: 14) {
                StatRow(title: "Bedtime", value: Fmt.time(sleep.start))
                StatRow(title: "Wake time", value: Fmt.time(sleep.end))
                Divider().overlay(Theme.separator)
                StatRow(title: "Time in bed", value: Fmt.duration(minutes: sleep.timeInBedMin))
                StatRow(title: "Efficiency", value: Fmt.percent(sleep.efficiencyPercent))
                Divider().overlay(Theme.separator)
                StatRow(title: "Sleep need", value: Fmt.duration(minutes: need))
                StatRow(title: "Actual", value: Fmt.duration(minutes: actual),
                        detail: need.flatMap { n in actual.map { a in
                            String(localized: "\(Int((Double(a) / Double(max(n, 1)) * 100).rounded()))% of need")
                        } })
                StatRow(title: "Sleep debt", value: debt == 0 ? String(localized: "None") : Fmt.duration(minutes: debt),
                        valueColor: (debt ?? 0) > 45 ? Theme.warning : Theme.textPrimary)
            }
        }
    }
}

/// Thin rounded progress bar in the accent colour.
struct ProgressBar: View {
    let value: Double?
    var color: Color = Theme.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.14))
                Capsule().fill(color).frame(width: geo.size.width * shown)
            }
        }
        .frame(height: 6)
        .onAppear {
            let target = min(max(value ?? 0, 0), 1)
            if reduceMotion { shown = target } else { withAnimation(Theme.ringAnimation) { shown = target } }
        }
        .onChange(of: value) { _, v in shown = min(max(v ?? 0, 0), 1) }
        .accessibilityHidden(true)
    }
}

/// Week / Month: nightly stacked bars, averages, bedtime consistency.
struct SleepRangeSection: View {
    let range: SleepRange?
    let isLoading: Bool

    private struct Bar: Identifiable {
        let date: Date
        let stage: String
        let hours: Double
        var id: String { "\(date.timeIntervalSince1970)-\(stage)" }
    }

    private static let asleep = String(localized: "Asleep")
    private static let stageOrder = [SleepStageKind.deep, .light, .rem]

    private var bars: [Bar] {
        (range?.days ?? []).flatMap { night -> [Bar] in
            let staged = Self.stageOrder.compactMap { s -> Bar? in
                let m = night.minutes(for: s)
                return m > 0 ? Bar(date: night.date, stage: s.title, hours: Double(m) / 60) : nil
            }
            if !staged.isEmpty { return staged }
            guard let total = night.totalMin, total > 0 else { return [] }
            return [Bar(date: night.date, stage: Self.asleep, hours: Double(total) / 60)]
        }
    }

    var body: some View {
        if let range {
            VStack(spacing: Theme.Metrics.sectionSpacing) {
                averages(range)
                chart(range)
                consistency(range)
            }
        } else if isLoading {
            ProgressView().tint(Theme.accent).padding(.top, 40)
        } else {
            InlineMessage(message: String(localized: "No sleep data for this range yet."), systemImage: "moon.zzz")
        }
    }

    private func averages(_ range: SleepRange) -> some View {
        HStack(spacing: 10) {
            average(title: "Avg sleep", value: Fmt.duration(minutes: range.avgTotalMin))
            average(title: "Avg quality", value: Fmt.percent(range.avgQuality))
            average(title: "Nights", value: "\(range.nights)")
        }
    }

    private func average(title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 8) {
            Text(title).ryftLabelStyle().lineLimit(1).minimumScaleFactor(0.8)
            Text(value)
                .font(.ryft(.metric))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func chart(_ range: SleepRange) -> some View {
        let bars = bars
        let hasUnstaged = bars.contains { $0.stage == Self.asleep }
        let names = Self.stageOrder.map(\.title) + (hasUnstaged ? [Self.asleep] : [])
        let colors = Self.stageOrder.map(Theme.color(for:)) + (hasUnstaged ? [Theme.accentSecondary] : [])
        let isMonth = range.range == SleepRangeKind.month.rawValue
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Sleep per night")
                Chart {
                    ForEach(bars) { b in
                        BarMark(x: .value("Night", b.date, unit: .day), y: .value("Hours", b.hours))
                            .foregroundStyle(by: .value("Stage", b.stage))
                            .cornerRadius(isMonth ? 2 : 4)
                    }
                    if let avg = range.avgTotalMin {
                        RuleMark(y: .value("Average", Double(avg) / 60))
                            .foregroundStyle(Theme.textTertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartForegroundStyleScale(domain: names, range: colors)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: isMonth ? 7 : 1)) { _ in
                        AxisValueLabel(format: isMonth ? .dateTime.day().month(.abbreviated) : .dateTime.weekday(.narrow))
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Theme.separator)
                        AxisValueLabel {
                            if let h = value.as(Double.self) {
                                Text("\(Int(h))h").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .accessibilityLabel(Text("Sleep per night"))
                .accessibilityValue(Text("Average \(Fmt.duration(minutes: range.avgTotalMin))"))
            }
        }
    }

    private func consistency(_ range: SleepRange) -> some View {
        let deviation = SleepMath.bedtimeDeviation(range.days.compactMap(\.start))
        let color: Color = deviation.map { $0 < 30 ? Theme.accent : $0 < 60 ? Theme.accentSecondary : Theme.warning }
            ?? Theme.textTertiary
        return Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Consistency")
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    Text(SleepMath.consistencyHint(deviation: deviation))
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Sleep · dark") {
    SleepView().previewEnvironment()
}

#Preview("Sleep · light") {
    SleepView().previewEnvironment(scheme: .light)
}

#Preview("Sleep week", traits: .sizeThatFitsLayout) {
    SchemePair {
        SleepRangeSection(range: MockData.sleepRange(.week), isLoading: false)
    }
    .previewEnvironment()
}
