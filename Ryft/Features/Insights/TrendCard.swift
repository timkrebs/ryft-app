// An Insights trend card (docs/work/2026-11-16-nocturne/design.md §P5-5.2, §P5-5.3, D5-8): `surface`, radius 24, 132 high at
// least, padding 14 / 16. The head row (the name, a note, a 12 pt chevron), 2 below the latest value in 26 Light with its unit and
// the change against the 7 days before, 6 below the `TrendLine` over the 30-day range. A tap opens the card in place: the detailed
// `TrendChart` (150 high, axes, scrubbing, the baseline) and Avg · Min · Max. Fed with `TrendCardContent`, so previews and tests
// show every state.
import SwiftUI

struct TrendCard: View {
    let content: TrendCardContent
    var isExpanded = false
    var toggle: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                summary
                    .accessibilityElement(children: .ignore)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(content.title))
            .accessibilityValue(Text(content.spokenValue))
            .accessibilityHint(isExpanded ? Text("Hides the detailed chart", comment: "VoiceOver hint on an open trend card.")
                                          : Text("Shows the detailed chart", comment: "VoiceOver hint on a trend card."))
            .accessibilityIdentifier("insights.trend.\(content.metric.rawValue)")
            if isExpanded {
                detail
                    .padding(.top, InsightsLayout.summaryToDetail)
                    .transition(.opacity)
            }
        }
        .padding(InsightsLayout.trendCardPadding)
        .frame(maxWidth: .infinity, minHeight: InsightsLayout.trendCardMinHeight, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: InsightsLayout.trendCardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    // MARK: summary (name, value, line)

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            valueRow
                .padding(.top, InsightsLayout.headToValue)
            TrendLine(values: content.values, band: content.band, color: content.style.line,
                      bandOpacity: content.style.bandOpacity, isPending: content.isPending,
                      accessibilityLabel: Text(content.chartLabel),
                      spokenLatest: content.latest.map { Text(content.spec.text($0)) })
                .padding(.top, InsightsLayout.valueToChart)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The name leading, the note and the chevron trailing, first baselines aligned. From AX1 the note goes under the name.
    private var head: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: InsightsLayout.noteGap) {
                Text(content.title)
                    .font(.ryft(.label))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize, let note = content.note {
                    noteText(note)
                        .multilineTextAlignment(.trailing)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: InsightsLayout.chevron, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .padding(.leading, InsightsLayout.chevronGap - InsightsLayout.noteGap)
            }
            if typeSize.isAccessibilitySize, let note = content.note {
                noteText(note)
            }
        }
    }

    private func noteText(_ note: String) -> some View {
        Text(note)
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "78" (26 Light) "%" (12, `textTertiary`, 3 after), 8, "▲ +11 vs 7 d"; "–" while loading or without data. From AX1 the change
    /// goes under the value.
    private var valueRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: InsightsLayout.deltaGap))
        return layout {
            if let latest = content.latest, !content.isPending {
                let parts = TrendCardContent.valueParts(content.metric, latest)
                HStack(alignment: .firstTextBaseline, spacing: InsightsLayout.unitGap) {
                    Text(parts.number)
                        .font(.ryft(.metric))
                        .foregroundStyle(Theme.textPrimary)
                    if let unit = parts.unit {
                        Text(unit)
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                if let delta = content.delta {
                    deltaLine(delta)
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(Fmt.placeholder)
                    .font(.ryft(.metric))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// `DeltaLabel`'s words in the card's colour (§P5-5.2's table), then "vs 7 d": one paragraph, so at AX3 it wraps after
    /// "·" or before "vs 7 d", never between a number and its unit.
    private func deltaLine(_ delta: MetricDelta) -> Text {
        var change = AttributedString(TrendCardContent.keepingUnitsTogether(DeltaLabel.text(delta, spec: content.spec)))
        change.foregroundColor = content.style.deltaColor(delta, polarity: content.spec.polarity)
        var reference = AttributedString(" " + TrendCardContent.keepingUnitsTogether(TrendCardContent.deltaReference))
        reference.foregroundColor = Theme.textTertiary
        return Text(change + reference)
    }

    // MARK: detail (expanded)

    private var detail: some View {
        VStack(alignment: .leading, spacing: InsightsLayout.chartToStats) {
            TrendChart(points: content.points, spec: content.spec, window: ChartWindow(days: content.days), end: content.end,
                       baseline: content.baseline, band: content.band, showsHeader: false,
                       height: InsightsLayout.detailChartHeight, color: content.style.line)
                .accessibilityIdentifier("insights.trend.\(content.metric.rawValue).chart")
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: InsightsLayout.statsGap))
            layout {
                stat("Avg", content.avg)
                stat("Min", content.min)
                stat("Max", content.max)
            }
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .foregroundStyle(Theme.textTertiary)
            Text(value.map { TrendCardContent.valueText(content.metric, $0) } ?? Fmt.placeholder)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.ryft(.caption))
        .accessibilityElement(children: .combine)
    }
}

// MARK: previews (dark only)

/// Every state of a card, on the demo data (`MockData.trend`).
private struct TrendCardPreviews: View {
    private let today = Date.now

    private func card(_ metric: TrendMetric, range: TrendRange = .month, series: TrendSeries?? = nil, monthly: Bool = true,
                      loading: Bool = false, stale: Bool = false) -> TrendCardContent {
        let own = series ?? MockData.trend(metric, range: range)
        return .make(metric, range: range, series: own, monthly: monthly ? MockData.trend(metric, range: .month) : nil,
                     isLoading: loading, isStale: stale, today: today)
    }

    private var empty: TrendSeries {
        TrendSeries(metric: "hrv", range: "30d", points: [], avg: nil, min: nil, max: nil, baseline: nil)
    }

    var body: some View {
        VStack(spacing: InsightsLayout.trendCardGap) {
            TrendCard(content: card(.readiness))
            TrendCard(content: card(.hrv))
            TrendCard(content: card(.sleepMin))
            TrendCard(content: card(.strain))
            // Loading with nothing cached; no data in the range; the band still missing (calibrating); offline (stale).
            TrendCard(content: card(.hrv, series: .some(nil), loading: true))
            TrendCard(content: card(.hrv, series: .some(empty)))
            TrendCard(content: card(.rhr, range: .week, monthly: false))
            TrendCard(content: card(.readiness, stale: true))
            TrendCard(content: card(.hrv), isExpanded: true)
        }
    }
}

#Preview("TrendCard · states") {
    ScrollView {
        DarkPreview { TrendCardPreviews() }
    }
    .background(Theme.background)
}

#Preview("TrendCard · AX3") {
    ScrollView {
        DarkPreview { TrendCardPreviews() }
    }
    .background(Theme.background)
    .environment(\.dynamicTypeSize, .accessibility3)
}
