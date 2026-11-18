// Sleep → Day's hypnogram glow tile (Nocturne, docs/work/2026-11-16-nocturne/design.md §P4-2a): "Hypnogram" and the
// night's times, the stage column and the step line (`HypnogramPlot`), and the four stage totals. Without a timeline it
// keeps the header and the totals; without stages it says so. One VoiceOver element that says the night.
import SwiftUI

/// The tile's content for one night, formatted. Pure.
struct SleepHypnogramContent: Equatable {
    enum Body: Equatable {
        /// The step line over the night.
        case plot(segments: [SleepInterval], start: Date, end: Date)
        /// Stages are known, the timeline isn't: the header and the totals.
        case timelineMissing
        /// The watch recorded no stages: the header and the sentence.
        case stagesMissing
    }

    /// One stage's total: "Deep 1:35", "Deep –" without minutes.
    struct Total: Equatable, Identifiable {
        let stage: SleepStageKind
        let text: String
        let spoken: String
        var id: SleepStageKind { stage }
    }

    /// The totals, left to right.
    static let totalsOrder: [SleepStageKind] = [.deep, .rem, .light, .awake]
    /// The plot's stage names, top to bottom (`HypnogramPlot.Level`).
    static let plotOrder: [SleepStageKind] = [.awake, .rem, .light, .deep]

    let body: Body
    /// "22:50 – 07:00" in the locale's times; "–" for a missing end.
    let timeRange: String
    /// Empty without stages.
    let totals: [Total]
    /// "Hypnogram, 10:50 PM to 7:00 AM".
    let accessibilityLabel: String
    /// The totals spoken ("Deep 1 hour 35 minutes, REM …"), or the sentence of the variant.
    let accessibilityValue: String

    init(sleep: SleepDetail, locale: Locale = .autoupdatingCurrent) {
        // A night without its own ends takes the timeline's.
        let start = sleep.start ?? sleep.segments.map(\.start).min()
        let end = sleep.end ?? sleep.segments.map(\.end).max()
        timeRange = "\(Fmt.time(start, locale: locale)) – \(Fmt.time(end, locale: locale))"
        if let start, let end {
            accessibilityLabel = String(localized: "Hypnogram, \(Fmt.time(start, locale: locale)) to \(Fmt.time(end, locale: locale))",
                                        comment: "VoiceOver label of Sleep's hypnogram tile: the night's start and end (\"Hypnogram, 10:50 PM to 7:00 AM\").")
        } else {
            accessibilityLabel = String(localized: "Hypnogram")
        }
        let staged = sleep.hasStages && SleepStageKind.allCases.contains { sleep.stageMinutes($0) > 0 }
        guard staged else {
            body = .stagesMissing
            totals = []
            accessibilityValue = Self.noStages
            return
        }
        totals = Self.totalsOrder.map { stage in
            let minutes = sleep.stageMinutes(stage)
            return Total(stage: stage,
                         text: "\(stage.title) \(minutes > 0 ? Fmt.clock(minutes: minutes) : Fmt.placeholder)",
                         spoken: "\(stage.title) \(minutes > 0 ? Fmt.spokenDuration(minutes: minutes, locale: locale) : String(localized: "No data"))")
        }
        let spokenTotals = totals.map(\.spoken).joined(separator: ", ")
        if let start, let end, !HypnogramPlot.model(segments: sleep.segments, start: start, end: end).isEmpty {
            body = .plot(segments: sleep.segments, start: start, end: end)
            accessibilityValue = spokenTotals
        } else {
            body = .timelineMissing
            accessibilityValue = "\(spokenTotals). \(Self.noTimeline)"
        }
    }

    var hasPlot: Bool {
        if case .plot = body { return true }
        return false
    }

    static var noTimeline: String {
        String(localized: "The timeline isn't available for this night.",
               comment: "Sleep's hypnogram tile when the night has stage totals but no timeline.")
    }

    static var noStages: String {
        String(localized: "Your watch didn't record sleep stages for this night — only the total.")
    }
}

/// The hypnogram glow tile: 350 × 168, radius 28, the `.hypnogram` glow; 96 high in its two short variants. From AX1 the
/// header stacks, the stage column takes the widest name and the totals wrap to two rows of two.
struct SleepHypnogramTile: View {
    let content: SleepHypnogramContent
    /// Previews and tests; `nil` follows the system.
    var reduceTransparency: Bool?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GlowTile(Theme.metricSleep, kind: .hypnogram, minHeight: content.hasPlot ? nil : SleepLayout.hypnogramShortHeight,
                 reduceTransparency: reduceTransparency) {
            VStack(alignment: .leading, spacing: 0) {
                header
                switch content.body {
                case let .plot(segments, start, end):
                    HypnogramPlot(segments: segments, start: start, end: end,
                                  stageNames: SleepHypnogramContent.plotOrder.map(\.title))
                        .padding(.top, SleepLayout.plotGap)
                    totals
                        .padding(.top, SleepLayout.totalsGap)
                case .timelineMissing:
                    sentence(SleepHypnogramContent.noTimeline)
                        .padding(.top, SleepLayout.plotGap)
                    totals
                        .padding(.top, SleepLayout.totalsGap)
                case .stagesMissing:
                    sentence(SleepHypnogramContent.noStages)
                        .padding(.top, SleepLayout.plotGap)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(content.accessibilityLabel))
        .accessibilityValue(Text(content.accessibilityValue))
        .accessibilityIdentifier("sleep.hypnogram")
    }

    @ViewBuilder private var header: some View {
        let title = Text("Hypnogram").ryftGlowLabelStyle()
        let range = Text(content.timeRange).ryftGlowLabelStyle(.caption)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                title
                range
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title
                Spacer(minLength: 0)
                range.lineLimit(1)
            }
        }
    }

    private func sentence(_ text: String) -> some View {
        Text(text)
            .ryftGlowLabelStyle(.caption)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Four items spread edge to edge; from AX1 two rows of two.
    @ViewBuilder private var totals: some View {
        let items = content.totals
        if typeSize.isAccessibilitySize {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { row in
                    GridRow {
                        Text(items[row].text)
                        if row + 1 < items.count { Text(items[row + 1].text) }
                    }
                }
            }
            .ryftGlowLabelStyle(.caption)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, total in
                    if index > 0 { Spacer(minLength: 8) }
                    Text(total.text).lineLimit(1).fixedSize()
                }
            }
            .ryftGlowLabelStyle(.caption)
        }
    }
}

/// The hypnogram's slot while there is no night to draw (loading, no night): the placeholder outline (`PlaceholderOutline`),
/// 168 high, its title.
struct SleepHypnogramOutline: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SleepLayout.hypnogramRadius, style: .continuous)
        Text("Hypnogram")
            .ryftLabelStyle(Theme.textTertiary)
            .padding(GlowTileSpec.padding(for: .hypnogram))
            .frame(maxWidth: .infinity, minHeight: SleepLayout.hypnogramHeight, alignment: .topLeading)
            .background { PlaceholderOutline(shape) }
            .accessibilityHidden(true)
    }
}

extension SleepDetail {
    /// The minutes of `stage` in `stages`; 0 when it isn't there.
    func stageMinutes(_ stage: SleepStageKind) -> Int {
        stages.first { $0.stage == stage }?.min ?? 0
    }
}
