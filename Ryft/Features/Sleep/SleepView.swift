import SwiftUI
import Charts

/// Sleep: Day (stages, quality, details) and Week / Month (nightly bars).
struct SleepView: View {
    @Environment(AppState.self) private var state
    @Environment(ScreenModels.self) private var screens

    private var model: SleepViewModel { screens.sleep }

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                titleRow
                SegmentedPicker(selection: Bindable(model).mode, options: model.modes, title: \.title)
                switch model.mode {
                case .day: day
                case .week, .month: SleepRangeSection(range: model.range, isLoading: model.isLoading)
                case .plan: SleepPlannerSection(model: model.planner)
                }
            }
        }
        .task(id: TaskKey(mode: model.mode, refreshed: state.lastUpdated)) { await model.load() }
    }

    private struct TaskKey: Equatable {
        let mode: SleepMode
        let refreshed: Date?
    }

    // MARK: title with day picker

    private var titleRow: some View {
        HStack {
            stepButton("chevron.left", label: "Previous night", days: -1, enabled: model.canStepBack)
            Spacer()
            VStack(spacing: 2) {
                Text("Sleep")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 5) {
                    Text(model.subtitle)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                    if model.mode == .day, model.marker != nil { DayMarker(kind: model.marker) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text(model.mode == .day ? model.marker?.spoken ?? "" : ""))
            }
            Spacer()
            stepButton("chevron.right", label: "Next night", days: 1, enabled: model.canStepForward)
        }
    }

    private func stepButton(_ icon: String, label: LocalizedStringKey, days: Int, enabled: Bool) -> some View {
        Button {
            Task { await model.step(by: days) }
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
            SleepDaySection(sleep: sleep, score: model.score)
        } else if model.isLoading {
            ProgressView().tint(Theme.accent).padding(.top, 40)
        } else if let error = model.error {
            InlineMessage(message: error, retry: { await model.load() })
        } else {
            InlineMessage(message: String(localized: "No sleep recorded for this night."),
                          systemImage: "moon.zzz")
            if model.hasNoHealthData { HealthAccessHint() }
        }
    }
}

/// Day mode content, separated so previews can feed it directly.
struct SleepDaySection: View {
    let sleep: SleepDetail
    let score: DailyScore?

    private var summary: SleepNightSummary { SleepNightSummary(sleep: sleep, score: score) }

    var body: some View {
        VStack(spacing: Theme.Metrics.sectionSpacing) {
            VStack(spacing: 4) {
                Text(summary.total)
                    .font(.ryft(.numberLarge))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("Total sleep")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)

            if let nap = summary.nap {
                VStack(spacing: 6) {
                    Label(nap, systemImage: "powersleep")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceRaised, in: Capsule())
                    Text("A nap lowers tonight's sleep need.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
                .accessibilityElement(children: .combine)
            }
            if let need = sleep.need {
                Card { SleepNeedBar(need: need) }
            }
            stages
            scores
            details
        }
    }

    /// Performance, efficiency, quality and restorative as tiles; consistency
    /// as a fifth when the platform has it.
    private var scores: some View {
        let summary = summary
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                SleepScoreTile(title: "Performance", value: summary.performance, detail: String(localized: "of your need"))
                SleepScoreTile(title: "Efficiency", value: summary.efficiency, detail: String(localized: "asleep in bed"))
                SleepScoreTile(title: "Quality", value: summary.quality, detail: summary.qualityLabel)
                SleepScoreTile(title: "Restorative", value: summary.restorative, detail: String(localized: "deep + REM"))
                if let consistency = summary.consistency {
                    SleepScoreTile(title: "Consistency", value: consistency, detail: String(localized: "last 7 nights"))
                }
            }
            Text("Quality is 60 % performance, 20 % efficiency and 20 % restorative sleep.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
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
        let summary = summary
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sleep quality")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(summary.qualityLabel)
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Text(summary.quality)
                        .font(.ryft(.headline))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                ProgressBar(value: summary.qualityFraction)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep quality"))
        .accessibilityValue(Text("\(summary.qualityLabel), \(summary.quality)"))
    }

    private var details: some View {
        let summary = summary
        return Card {
            VStack(spacing: 14) {
                StatRow(title: "Bedtime", value: summary.bedtime)
                StatRow(title: "Wake time", value: summary.wake)
                Divider().overlay(Theme.separator)
                StatRow(title: "Time in bed", value: summary.timeInBed)
                StatRow(title: "Efficiency", value: summary.efficiency)
                Divider().overlay(Theme.separator)
                if summary.needBreakdown == nil {
                    StatRow(title: "Sleep need", value: summary.need)
                }
                StatRow(title: "Actual", value: summary.actual, detail: summary.actualOfNeed)
                StatRow(title: "Sleep debt", value: summary.debt,
                        valueColor: summary.debtIsHigh ? Theme.warning : Theme.textPrimary)
            }
        }
    }
}

/// A small score tile on Sleep → Day: title, number, one line of context.
struct SleepScoreTile: View {
    let title: LocalizedStringKey
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).ryftLabelStyle().lineLimit(1).minimumScaleFactor(0.8)
            Text(value)
                .font(.ryft(.metric))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(detail)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
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

    var body: some View {
        if let range {
            let summary = SleepRangeSummary(range: range)
            VStack(spacing: Theme.Metrics.sectionSpacing) {
                averages(summary)
                chart(summary)
                consistency(summary)
                nights(summary)
            }
        } else if isLoading {
            ProgressView().tint(Theme.accent).padding(.top, 40)
        } else {
            InlineMessage(message: String(localized: "No sleep data for this range yet."), systemImage: "moon.zzz")
        }
    }

    private func averages(_ summary: SleepRangeSummary) -> some View {
        HStack(spacing: 10) {
            average(title: "Avg sleep", value: summary.averageSleep)
            average(title: "Avg quality", value: summary.averageQuality)
            average(title: "Consistency", value: summary.averageConsistency)
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

    private func chart(_ summary: SleepRangeSummary) -> some View {
        let order = SleepRangeSummary.stageOrder
        let names = order.map(\.title) + (summary.hasUnstaged ? [SleepRangeSummary.asleep] : [])
        let colors = order.map(Theme.color(for:)) + (summary.hasUnstaged ? [Theme.accentSecondary] : [])
        let window = summary.window
        let end = summary.end
        let scale = ChartStyle.niceScale([summary.tallestNight, summary.averageHours ?? 0, 0], steps: ChartStyle.hourSteps)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                ChartHeader(spec: .sleepMin, value: summary.totals.last?.value, delta: .vsSevenDayMean(summary.totals),
                            window: window.title)
                Chart {
                    ForEach(summary.bars) { b in
                        BarMark(x: .value("Night", b.date, unit: .day), y: .value("Hours", b.hours))
                            .foregroundStyle(by: .value("Stage", b.stage))
                            .cornerRadius(1)
                    }
                    if let avg = summary.averageHours {
                        BaselineRule(value: avg, label: String(localized: "avg \(summary.averageSleep)"))
                    }
                }
                .chartForegroundStyleScale(domain: names, range: colors)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                // Bars fill whole day bins: the domain runs to the end of the last day.
                .chartXScale(domain: window.start(endingAt: end)...DayFormat.shift(Calendar.current.startOfDay(for: end), days: 1))
                .chartYScale(domain: scale.domain)
                .chartXAxis {
                    ChartStyle.xAxis(window.ticks(endingAt: end), format: window.format, centered: window == .week)
                }
                .chartYAxis { ChartStyle.yAxis(scale.ticks, unit: "h") { $0.formatted(.number.precision(.fractionLength(0...1))) } }
                .frame(height: 200)
                .chartAppear()
                .accessibilityLabel(Text("Sleep per night"))
                .accessibilityValue(Text("Average \(summary.averageSleep)"))
            }
        }
    }

    private func consistency(_ summary: SleepRangeSummary) -> some View {
        let color: Color
        switch summary.regularity {
        case .steady: color = Theme.accent
        case .fair: color = Theme.accentSecondary
        case .irregular: color = Theme.warning
        case .unknown: color = Theme.textTertiary
        }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bedtime and wake time")
                            .font(.ryft(.headline))
                            .foregroundStyle(Theme.textPrimary)
                        Text(summary.consistencyHint)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                if !summary.bedtimes.isEmpty {
                    BedtimeStrip(bedtimes: summary.bedtimes, rowHeight: summary.bedtimes.count > 10 ? 7 : 14)
                }
            }
        }
    }

    /// Each night with its consistency and nap.
    private func nights(_ summary: SleepRangeSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "\(summary.nights) nights")
                ForEach(summary.nightRows) { row in
                    HStack(spacing: 10) {
                        Text(row.title)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if let nap = row.nap {
                            Label(nap, systemImage: "powersleep")
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(row.total)
                            .font(.ryft(.callout).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        Label(row.consistency ?? Fmt.placeholder, systemImage: "metronome")
                            .font(.ryft(.caption).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(row.title))
                    .accessibilityValue(Text(String(localized: "\(row.total) asleep, quality \(row.quality)")
                                             + (row.consistency.map { ", " + String(localized: "consistency \($0)") } ?? "")
                                             + (row.nap.map { ", " + String(localized: "nap \($0)") } ?? "")))
                }
            }
        }
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
