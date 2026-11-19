import SwiftUI

/// Splits (ui.md §7.1, Nocturne PR 6 B §10.3 item 4): one row per kilometre (the last one partial), its pace (or speed for
/// cycling), a bar scaled to the fastest, and the climb. The table is in the unit its splits were measured in, kilometres and
/// metres, whatever the locale (per-mile splits are A4's). The column header is `axis` in `textTertiary`; rows are at least
/// 40 high with a hairline between them; the bars are `metricStrain` at 60 %, the fastest split's in ink with the word
/// "Fastest" under its pace: never colour alone. Over 20 rows the table shows the first 10 and "Show all".
struct SplitsTable: View {
    let splits: [ActivitySplit]
    var paceStyle: TrackProfile.PaceStyle = .pace

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsAll = false
    /// Wide enough for "10:05 /km" or "24.3 km/h" on one line at the size in use.
    @ScaledMetric(relativeTo: .body) private var paceWidth: CGFloat = 96

    static let collapseOver = 20
    static let collapsedCount = 10

    private var shown: [ActivitySplit] {
        splits.count > Self.collapseOver && !showsAll ? Array(splits.prefix(Self.collapsedCount)) : splits
    }

    /// m/s per split; nil for a split without time or distance.
    private func speed(_ s: ActivitySplit) -> Double? {
        guard s.distanceM > 0, s.durationSec > 0 else { return nil }
        return s.distanceM / s.durationSec
    }

    private var fastest: Int? {
        splits.filter { speed($0) != nil }.max { (speed($0) ?? 0) < (speed($1) ?? 0) }?.index
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Splits").ryftLabelStyle()
                    .accessibilityHidden(true)
                if !typeSize.isAccessibilitySize {
                    header.padding(.top, ActivitiesLayout.splitsTitleGap)
                }
                ForEach(Array(shown.enumerated()), id: \.element.index) { offset, split in
                    if offset > 0 || !typeSize.isAccessibilitySize {
                        Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline)
                            .accessibilityHidden(true)
                    }
                    row(split)
                }
                if splits.count > Self.collapseOver, !showsAll {
                    Button { showsAll = true } label: {
                        Text("Show all \(splits.count)")
                    }
                    .ryftLink()
                    .padding(.top, 4)
                    .accessibilityIdentifier("splits.showAll")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Splits"))
        .accessibilityIdentifier("activityDetail.splits")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Km", comment: "Splits table: the kilometre column.").frame(width: Self.labelWidth, alignment: .leading)
            Text(paceStyle == .speed ? String(localized: "Speed")
                 : String(localized: "Pace", comment: "Splits table and pace chart: time per kilometre or mile."))
                .lineLimit(1)
                .frame(width: paceWidth, alignment: .leading)
            Spacer(minLength: 0)
            Text("Elev", comment: "Splits table: the climb column (elevation).").frame(width: Self.climbWidth, alignment: .trailing)
        }
        .font(.ryft(.axis))
        .foregroundStyle(Theme.textTertiary)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    /// Wide enough for the partial last split ("0.42 km").
    private static let labelWidth: CGFloat = 64
    private static let climbWidth: CGFloat = 52

    private func row(_ s: ActivitySplit) -> some View {
        let value = paceStyle == .speed
            ? ActivityFormat.speed(movingSec: s.durationSec, distanceM: s.distanceM, locale: locale, inKilometres: true)
            : ActivityFormat.pace(movingSec: s.durationSec, distanceM: s.distanceM, locale: locale, inKilometres: true)
        let climb = s.ascentM.flatMap { ActivityFormat.elevation($0, locale: locale, inMetres: true) }.map { "+\($0)" } ?? ""
        let isFastest = s.index == fastest && splits.count > 1
        let label = Text(verbatim: ActivityFormat.splitLabel(s, locale: locale))
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
        let pace = Text(verbatim: value ?? Fmt.placeholder)
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
        let word = Text("Fastest")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textPrimary)
        let elevation = Text(verbatim: climb)
            .font(.ryft(.caption))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
        return Group {
            if typeSize.isAccessibilitySize {
                // ui.md §7.1: at accessibility sizes the pace stacks under the kilometre; no bar.
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        label
                        Spacer(minLength: 8)
                        elevation
                    }
                    pace
                    if isFastest { word }
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    label
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: Self.labelWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        pace.minimumScaleFactor(0.8)
                        if isFastest { word.lineLimit(1).minimumScaleFactor(0.8) }
                    }
                    .frame(width: paceWidth, alignment: .leading)
                    bar(s, isFastest: isFastest)
                    elevation.frame(width: Self.climbWidth, alignment: .trailing)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: ActivitiesLayout.splitRowMinHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ActivityFormat.spokenSplit(s, locale: locale)))
        .accessibilityValue(Text(verbatim: spoken(s, isFastest: isFastest)))
    }

    /// The share of the fastest split's speed; the fastest bar in ink, the others `metricStrain` at 60 %.
    private func bar(_ s: ActivitySplit, isFastest: Bool) -> some View {
        let top = splits.compactMap(speed).max() ?? 1
        let share = (speed(s) ?? 0) / top
        return GeometryReader { geo in
            Capsule()
                .fill(isFastest ? Theme.textPrimary : Theme.metricStrain.opacity(ActivitiesLayout.splitBarOpacity))
                .frame(width: max(ActivitiesLayout.splitBarHeight, geo.size.width * share), height: ActivitiesLayout.splitBarHeight)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }

    /// "5 minutes, 34 seconds per kilometre, Fastest, plus 8 metres".
    private func spoken(_ s: ActivitySplit, isFastest: Bool) -> String {
        let rate = paceStyle == .speed
            ? ActivityFormat.spokenSpeed(movingSec: s.durationSec, distanceM: s.distanceM, locale: locale, inKilometres: true)
            : ActivityFormat.spokenPace(movingSec: s.durationSec, distanceM: s.distanceM, locale: locale, inKilometres: true)
        let climb = ActivityFormat.spokenClimb(s.ascentM, locale: locale, inMetres: true)
        let parts = [rate, isFastest ? String(localized: "Fastest") : nil, climb]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }
}

// MARK: - previews (dark only)

#Preview("Splits", traits: .sizeThatFitsLayout) {
    let run = MockActivitiesSource.demo().first { $0.splits != nil }
    SplitsTable(splits: run?.splits ?? [])
        .padding(Theme.Metrics.screenPadding)
        .background(Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("Splits · AX3", traits: .sizeThatFitsLayout) {
    let run = MockActivitiesSource.demo().first { $0.splits != nil }
    SplitsTable(splits: run?.splits ?? [])
        .padding(Theme.Metrics.screenPadding)
        .background(Theme.background)
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.dark)
}
