// Today's glow tiles in Nocturne (docs/work/2026-11-16-nocturne/design.md §P4-1 rows 11 and 12, §P4-3, §P4-4 T9–T14,
// §P4-8 rows 8–10): Recovery and Sleep side by side (169 × 124 on a 350 pt column; stacked from AX1), then the strain tile
// (350 × 96). One day for all three, the gauge's (ui.md §1): an earlier day or "calibrating" is a caption, never dimmed
// ink. Each tile is one button and one VoiceOver element; the colour is the legend, never the message.
import SwiftUI

// MARK: - what the tiles show (pure)

/// The sleep tile's seven nights (§P4-4 T12): enough at ≥ 90 % of the night's need (L24, the band the Sleep ruler's need
/// zone shows), short below it, unknown without both numbers. The app's rule over two server values, never a score.
struct TodaySleepWeek: Equatable, Sendable {
    enum Night: Equatable, Sendable { case enough, short, unknown }

    /// L24: `sleep_actual_min ≥ 0.9 × sleep_need_min`, in whole tenths so no rounding decides a night.
    static let enoughTenths = 9

    /// Oldest first; the last is the tiles' day.
    let nights: [Night]

    init(nights: [Night]) {
        self.nights = nights
    }

    init(_ week: [DailyScore?]) {
        nights = week.map(Self.night)
    }

    static func night(_ score: DailyScore?) -> Night {
        guard let actual = score?.sleepActualMin, let need = score?.sleepNeedMin, need > 0 else { return .unknown }
        return actual * 10 >= need * enoughTenths ? .enough : .short
    }

    /// Full, missed, a no-data dot; the last is `.today` (Volt), the night shown: its place is the cue (brief §6), and the
    /// summary names it.
    var marks: [DotRow.Mark] {
        nights.indices.map { i in
            if i == nights.count - 1 { return .today }
            switch nights[i] {
            case .enough: return .full
            case .short: return .missed
            case .unknown: return .noData
            }
        }
    }

    var enoughCount: Int { nights.count { $0 == .enough } }
    var unknownCount: Int { nights.count { $0 == .unknown } }

    /// "Slept enough on 4 of the last 7 nights; the last is the night shown", and "; 1 nights have no data" when
    /// some can't be told (the catalog's plural variants say "1 night has").
    var summary: String {
        let enough = enoughCount, unknown = unknownCount
        guard unknown > 0 else {
            return String(localized: "Slept enough on \(enough) of the last 7 nights; the last is the night shown",
                          comment: "VoiceOver on the 7 dots of Today's Sleep tile: nights asleep 90 % of the need or more; the last is the night shown.")
        }
        return String(localized: "Slept enough on \(enough) of the last 7 nights; the last is the night shown; \(unknown) nights have no data",
                      comment: "VoiceOver on the 7-night dots of Today's Sleep tile, when some nights lack the numbers to tell (no sleep or no need).")
    }
}

/// The strain tile's band (§P4-4 T14): `MetricSpec.strainBand`'s thresholds (10 / 14 / 18). The zone the compact ruler
/// marks is the moderate band, never "a target" (R-N1: the platform has no personal one yet).
enum TodayStrainBand: Equatable, Sendable, CaseIterable {
    case light, moderate, high, allOut

    /// `MetricSpec.strainBand`'s: moderate from 10, high from 14, all out from 18.
    static let moderateFrom = 10.0, highFrom = 14.0, allOutFrom = 18.0

    init(_ strain: Double) {
        switch strain {
        case Self.allOutFrom...: self = .allOut
        case Self.highFrom...: self = .high
        case Self.moderateFrom...: self = .moderate
        default: self = .light
        }
    }

    /// The compact ruler's zone: the moderate band.
    static var zone: ClosedRange<Double>? { RulerScale.zone(lo: moderateFrom, hi: highFrom) }

    /// After the value: "of 21 · moderate".
    var caption: String {
        switch self {
        case .light: return String(localized: "of 21 · light", comment: "After Today's strain value: the scale and the band (under 10).")
        case .moderate: return String(localized: "of 21 · moderate", comment: "After Today's strain value: the scale and the band (10 to 14).")
        case .high: return String(localized: "of 21 · high", comment: "After Today's strain value: the scale and the band (14 to 18).")
        case .allOut: return String(localized: "of 21 · all out", comment: "After Today's strain value: the scale and the band (18 and up).")
        }
    }

    /// For VoiceOver: the band as Strain's own screen names it ("Moderate strain", `MetricSpec.strainBand`).
    var spoken: String {
        switch self {
        case .light: return MetricSpec.strainBand(0).label
        case .moderate: return MetricSpec.strainBand(Self.moderateFrom).label
        case .high: return MetricSpec.strainBand(Self.highFrom).label
        case .allOut: return MetricSpec.strainBand(Self.allOutFrom).label
        }
    }

    /// "of 21" with no value to put in a band.
    static var scaleOnly: String {
        String(localized: "of 21", comment: "After Today's strain value when there is none (\"–\"): the scale alone.")
    }
}

/// Everything the three tiles show, from one `TodayContent` (one `facts` build): values, captions, series and the
/// sentences VoiceOver reads (§P4-8 rows 8–10). A value, so the rows are tested without a view.
struct TodayTilesContent: Equatable {
    /// "82", or "–" (the unit then goes).
    var recovery: Int?
    /// "High", the day ("Yesterday"), or "calibrating".
    var recoveryCaption: String?
    var hrvWeek: [Double?]
    var sleepMinutes: Int?
    /// The day or "calibrating" (`TodayContent.tileCaption`), also the strain tile's.
    var caption: String?
    var sleepWeek: TodaySleepWeek
    var strain: Double?
    /// The tiles show an earlier day than today (the night is being scored, row D): said, never dimmed.
    var isEarlierDay: Bool

    var recoveryText: String { recovery.map(String.init) ?? Fmt.placeholder }
    var sleepText: String { Fmt.clock(minutes: sleepMinutes) }
    var strainText: String { Fmt.strain(strain) }
    var strainBand: TodayStrainBand? { strain.map(TodayStrainBand.init) }
    /// "of 21 · moderate", or "of 21" without a value.
    var strainCaption: String { strainBand?.caption ?? TodayStrainBand.scaleOnly }
    /// "Strain", or "Strain · Yesterday" / "Strain · calibrating" while the tiles show another day or the baselines fill.
    var strainLabel: String {
        guard let caption else { return String(localized: "Strain") }
        return String(localized: "Strain · \(caption)",
                      comment: "The strain tile's label while it shows another day (\"Yesterday\") or \"calibrating\".")
    }

    // MARK: VoiceOver (§P4-8)

    /// "HRV 66 milliseconds, lowest 51 and highest 66 over the last 7 days": only with the day's own value and a line to
    /// read (two values or more), the sparkline's pending look says nothing.
    var hrvSentence: String? {
        let present = hrvWeek.compactMap { $0 }.filter(\.isFinite)
        guard !Sparkline.isPending(hrvWeek), let last = hrvWeek.last.flatMap({ $0 }), last.isFinite,
              let low = present.min(), let high = present.max() else { return nil }
        let (today, lowest, highest) = (Int(last.rounded()), Int(low.rounded()), Int(high.rounded()))
        return String(localized: "HRV \(today) milliseconds, lowest \(lowest) and highest \(highest) over the last 7 days",
                      comment: "VoiceOver on Today's Recovery tile: the HRV sparkline, the shown day's value and the week's range.")
    }

    /// "82 percent, High. HRV 66 milliseconds, …"; "75 percent, Yesterday, not today's score. …"; "No data, calibrating".
    var recoverySpoken: String {
        let main: String
        if let recovery {
            let percent = String(localized: "\(recovery) percent")
            if isEarlierDay, let caption = recoveryCaption {
                main = String(localized: "\(percent), \(caption), not today's score")
            } else if let caption = recoveryCaption {
                main = String(localized: "\(recovery) percent, \(caption)",
                              // swiftlint:disable:next line_length
                              comment: "VoiceOver, two places. Training import: the progress value. Today's Recovery tile: the score, then its band or the day (\"82 percent, High\", \"75 percent, Yesterday, not today's score\").")
            } else {
                main = percent
            }
        } else {
            main = Self.noData(recoveryCaption)
        }
        return [main, hrvSentence].compactMap { $0 }.joined(separator: ". ")
    }

    /// "7 hours 48 minutes. Slept enough on 4 of the last 7 nights; the last is the night shown".
    var sleepSpoken: String {
        let main: String
        if let sleepMinutes {
            let spoken = Fmt.spokenDuration(minutes: sleepMinutes)
            if isEarlierDay, let caption {
                main = String(localized: "\(spoken), \(caption), not today's score")
            } else if let caption {
                main = "\(spoken), \(caption)"
            } else {
                main = spoken
            }
        } else {
            main = Self.noData(caption)
        }
        return main + ". " + sleepWeek.summary
    }

    /// "12.4, Moderate strain, on a scale from 0 to 21. The moderate range is 10 to 14."; another day's or a calibrating
    /// one's: "0.9, Yesterday, not today's score" / "0.9, calibrating".
    var strainSpoken: String {
        guard let strain, let band = strainBand else { return Self.noData(caption) }
        let value = Fmt.strain(strain)
        if isEarlierDay, let caption { return String(localized: "\(value), \(caption), not today's score") }
        if let caption { return "\(value), \(caption)" }
        // The catalog's key keeps its positional form (design.md §P4-9).
        let format = String(localized: "%1$@, %2$@, on a scale from 0 to 21. The moderate range is 10 to 14.",
                            comment: "VoiceOver on Today's strain tile: the value (12.4), its band (Moderate strain), the scale and the ruler's band.")
        return String(format: format, value, band.spoken)
    }

    private static func noData(_ caption: String?) -> String {
        guard let caption else { return String(localized: "No data") }
        return String(localized: "No data, \(caption)",
                      comment: "VoiceOver value of a Today tile without a number, with the line under it, e.g. “No data, calibrating”.")
    }
}

extension TodayTilesContent {
    /// The tiles of one `TodayContent`: the same day for all three.
    init(_ day: TodayContent) {
        self.init(recovery: day.recovery, recoveryCaption: day.recoveryCaption, hrvWeek: day.hrvWeek,
                  sleepMinutes: day.sleepMinutes, caption: day.tileCaption, sleepWeek: day.sleepWeek, strain: day.strain,
                  isEarlierDay: day.tilesDimmed)
    }
}

// MARK: - the tiles

/// Recovery and Sleep, then Strain (§P4-1 rows 11–12): 12 apart, the pair stacked from AX1.
struct TodayTiles: View {
    let content: TodayTilesContent
    /// Previews and tests; `nil` follows the system.
    var reduceTransparency: Bool?
    let open: (AppTab) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: TodayLayout.tilesToStrain) {
            if typeSize.isAccessibilitySize {
                VStack(spacing: TodayLayout.tileGap) {
                    recovery
                    sleep
                }
            } else {
                // One height for the pair: the taller tile's (the glow tile has a minimum, never a maximum).
                HStack(alignment: .top, spacing: TodayLayout.tileGap) {
                    recovery
                    sleep
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            TodayStrainTile(content: content, reduceTransparency: reduceTransparency) { open(.strain) }
        }
    }

    private var recovery: some View {
        TodayTwoUpTile(metric: Theme.recovery, title: String(localized: "Recovery"), value: content.recoveryText,
                       unit: content.recovery == nil ? nil : "%", caption: content.recoveryCaption,
                       spoken: content.recoverySpoken, hint: String(localized: "Opens Insights"),
                       identifier: "today.tile.recovery", reduceTransparency: reduceTransparency,
                       action: { open(.insights) }) {
            Sparkline(values: content.hrvWeek)
        }
    }

    private var sleep: some View {
        TodayTwoUpTile(metric: Theme.metricSleep, title: String(localized: "Sleep"), value: content.sleepText,
                       unit: content.sleepMinutes == nil ? nil : TodayTwoUpTile<DotRow>.hoursUnit, caption: content.caption,
                       spoken: content.sleepSpoken, hint: String(localized: "Opens Sleep"), identifier: "today.tile.sleep",
                       reduceTransparency: reduceTransparency, action: { open(.sleep) }) {
            // Its summary is the tile's to read: the tile is the one element.
            DotRow(content.sleepWeek.marks, accessibilityLabel: Text(verbatim: content.sleepWeek.summary))
        }
    }
}

/// A 2-up glow tile (§P4-1 row 11): the label top-leading with its series trailing on the label's baseline, the value
/// (34 Light) and its unit bottom-left, the caption bottom-right. From AX1 the rows stack (label, series, value, caption).
struct TodayTwoUpTile<Series: View>: View {
    let metric: Color
    let title: String
    let value: String
    var unit: String?
    var caption: String?
    let spoken: String
    let hint: String
    let identifier: String
    var reduceTransparency: Bool?
    let action: () -> Void
    @ViewBuilder var series: () -> Series

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The unit after a clock value ("7:48 h").
    static var hoursUnit: String {
        String(localized: "h", comment: "Hours, the unit after a clock duration on Today's Sleep tile and on Sleep's tiles: \"7:48 h\", \"0:30 h\".")
    }

    var body: some View {
        Button(action: action) {
            GlowTile(metric, kind: .twoUp, reduceTransparency: reduceTransparency) {
                if typeSize.isAccessibilitySize {
                    stacked
                } else {
                    TodayTwoUpBoard(title: title, value: value, unit: unit, caption: caption, series: series)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: spoken))
        .accessibilityHint(Text(verbatim: hint))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    /// AX1 and up: one under the other, nothing truncated; the numerals keep their size.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: TodayLayout.tileRowGap) {
            Text(verbatim: title)
                .ryftGlowLabelStyle()
                .fixedSize(horizontal: false, vertical: true)
            series()
            TodayTwoUpValue(value: value, unit: unit)
            if let caption {
                Text(verbatim: caption)
                    .ryftGlowLabelStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A 2-up tile's content below AX1 (§P4-1 row 11): the label row on top, the value row on the bottom, the space between
/// them flexible. At least the board's 98 pt (124 less the padding), and as tall as its content asks at larger text, so
/// the pair (`TodayTiles`: the taller tile's height for both) never clips. The value sits on the bottom in every state:
/// a caption never moves it (`TodayTwoUpValueRow`).
struct TodayTwoUpBoard<Series: View>: View {
    let title: String
    let value: String
    var unit: String?
    var caption: String?
    @ViewBuilder var series: () -> Series

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .ryftGlowLabelStyle()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, TodayLayout.seriesClearance)
                // The series sits on the label's baseline at the trailing inset, without moving the label off the
                // tile's top padding (derived, not measured: the board names the content, not its place).
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) { series() }
            Spacer(minLength: TodayLayout.tileRowGap)
            TodayTwoUpValueRow {
                TodayTwoUpValue(value: value, unit: unit)
                if let caption {
                    Text(verbatim: caption)
                        .ryftGlowLabelStyle()
                        .multilineTextAlignment(.trailing)
                        .minimumScaleFactor(TodayTwoUpValueRow.minimumScale)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: TodayLayout.twoUpContentHeight, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The value (34 Light, a fixed size) and its unit on one baseline.
struct TodayTwoUpValue: View {
    let value: String
    var unit: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TodayLayout.unitGap) {
            Text(verbatim: value)
                .font(.ryft(.numberLarge))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
            if let unit {
                Text(verbatim: unit).ryftGlowLabelStyle().fixedSize()
            }
        }
    }
}

/// A 2-up tile's bottom row (VF3): the value leading, the caption ("High", "Yesterday", "calibrating") trailing on the
/// value's baseline. A caption that doesn't fit beside the value shrinks, to 80 % at most, on its one line; one that
/// still doesn't goes above the value, trailing, wrapping if it must. The value's line is the row's bottom in every
/// arrangement, so its baseline never moves and no word is broken.
struct TodayTwoUpValueRow: Layout {
    /// The least the caption shrinks to before it leaves the value's line.
    static let minimumScale: CGFloat = 0.8

    enum Arrangement: Equatable { case beside, besideScaled, above }

    /// Where the caption goes for a row `width` wide, a value `value` wide and a caption `caption` wide on one line.
    static func arrangement(width: CGFloat, value: CGFloat, caption: CGFloat) -> Arrangement {
        let room = width - value - TodayLayout.tileRowGap
        if caption <= room { return .beside }
        return caption * minimumScale <= room ? .besideScaled : .above
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let value = subviews.first else { return .zero }
        let valueSize = value.sizeThatFits(.unspecified)
        let width = proposal.width ?? valueSize.width
        guard subviews.count > 1 else { return CGSize(width: width, height: valueSize.height) }
        let caption = subviews[1]
        let line = caption.sizeThatFits(.unspecified)
        switch Self.arrangement(width: width, value: valueSize.width, caption: line.width) {
        case .beside, .besideScaled:
            // On the value's baseline: the value's line box is the taller one (34 pt against 13).
            let below = max(valueSize.height - value.dimensions(in: .unspecified)[.firstTextBaseline],
                            line.height - caption.dimensions(in: .unspecified)[.firstTextBaseline])
            let above = max(value.dimensions(in: .unspecified)[.firstTextBaseline],
                            caption.dimensions(in: .unspecified)[.firstTextBaseline])
            return CGSize(width: width, height: above + below)
        case .above:
            let wrapped = caption.sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: width, height: wrapped.height + TodayLayout.pendingLineGap + valueSize.height)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let value = subviews.first else { return }
        let valueDimensions = value.dimensions(in: .unspecified)
        // The value's line at the bottom of the row, always.
        let valueTop = bounds.maxY - valueDimensions.height
        value.place(at: CGPoint(x: bounds.minX, y: valueTop), proposal: .unspecified)
        guard subviews.count > 1 else { return }
        let caption = subviews[1]
        let line = caption.sizeThatFits(.unspecified)
        switch Self.arrangement(width: bounds.width, value: valueDimensions.width, caption: line.width) {
        case .beside, .besideScaled:
            let room = bounds.width - valueDimensions.width - TodayLayout.tileRowGap
            let offer = ProposedViewSize(width: min(line.width, room), height: line.height)
            let placed = caption.dimensions(in: offer)
            let baseline = valueTop + valueDimensions[.firstTextBaseline]
            caption.place(at: CGPoint(x: bounds.maxX - placed.width, y: baseline - placed[.firstTextBaseline]), proposal: offer)
        case .above:
            let offer = ProposedViewSize(width: bounds.width, height: nil)
            let placed = caption.dimensions(in: offer)
            caption.place(at: CGPoint(x: bounds.maxX - placed.width, y: valueTop - TodayLayout.pendingLineGap - placed.height),
                          proposal: offer)
        }
    }
}

/// The strain tile (§P4-1 row 12): "Strain", the value (30 Light) pushed right and "of 21 · moderate" 6 after it, on one
/// row; the compact ruler 16 in from the sides and 12 above the bottom, its zone the moderate band (10–14). From AX1:
/// the label, then the value and the caption, then the ruler.
struct TodayStrainTile: View {
    let content: TodayTilesContent
    var reduceTransparency: Bool?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            GlowTile(Theme.metricStrain, kind: .strain, reduceTransparency: reduceTransparency) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: TodayLayout.tileRowGap) {
                        label.fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .firstTextBaseline, spacing: TodayLayout.strainCaptionGap) {
                            value
                            caption
                        }
                        ruler
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        label
                        Spacer(minLength: TodayLayout.tileRowGap)
                        value
                        caption.padding(.leading, TodayLayout.strainCaptionGap)
                    }
                    // The row on top, the ruler on the tile's bottom padding: the value's line box (40.5) reaches 2.5 pt
                    // into the ruler's top (where only the needle's head is), so the tile keeps the board's 96.
                    .frame(maxWidth: .infinity, minHeight: TodayLayout.strainContentHeight, alignment: .top)
                    .overlay(alignment: .bottom) { ruler }
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Strain"))
        .accessibilityValue(Text(verbatim: content.strainSpoken))
        .accessibilityHint(Text("Opens Strain"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("today.tile.strain")
    }

    private var label: some View {
        Text(verbatim: content.strainLabel)
            .ryftGlowLabelStyle()
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }

    private var value: some View {
        Text(verbatim: content.strainText)
            .font(.ryftNumber(size: TodayLayout.strainNumeral, weight: .light))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }

    private var caption: some View {
        Text(verbatim: content.strainCaption)
            .ryftGlowLabelStyle()
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: typeSize.isAccessibilitySize ? false : true, vertical: true)
    }

    /// No labels on Today (the row says the scale); the zone and the needle only. Inside the tile's element: VoiceOver
    /// reads the tile.
    private var ruler: some View {
        RulerScale(range: 0...OrbitGaugeValues.strainScale, value: content.strain, zone: TodayStrainBand.zone,
                   zoneStyle: .standard, tickCount: RulerScale.Ticks.strainCompact, size: .compact,
                   accessibilityLabel: Text("Strain scale", comment: "VoiceOver label of a strain ruler (0 to 21)."),
                   accessibilityValue: Text(verbatim: content.strainSpoken))
    }
}

// MARK: - previews (dark only, default and AX3)

private enum TodayTilesPreview {
    static let week = TodaySleepWeek(nights: [.enough, .short, .unknown, .enough, .short, .enough, .enough])

    /// The board's day, yesterday's (the night is being scored), calibrating, and nothing to show.
    static let rows: [TodayTilesContent] = [
        TodayTilesContent(recovery: 82, recoveryCaption: "High", hrvWeek: [58, 61, 55, 60, 57, 63, 66], sleepMinutes: 468,
                          caption: nil, sleepWeek: week, strain: 12.4, isEarlierDay: false),
        TodayTilesContent(recovery: 75, recoveryCaption: "Yesterday", hrvWeek: [57, 56, 55, 54, 53, 52, 51], sleepMinutes: 430,
                          caption: "Yesterday", sleepWeek: week, strain: 0.9, isEarlierDay: true),
        TodayTilesContent(recovery: nil, recoveryCaption: "calibrating", hrvWeek: [nil, nil, nil, nil, 55, 60, nil],
                          sleepMinutes: 431, caption: "calibrating",
                          sleepWeek: TodaySleepWeek(nights: [.unknown, .unknown, .unknown, .enough, .short, .short, .enough]),
                          strain: nil, isEarlierDay: false),
        TodayTilesContent(recovery: nil, recoveryCaption: nil, hrvWeek: [], sleepMinutes: nil, caption: nil,
                          sleepWeek: TodaySleepWeek(nights: Array(repeating: .unknown, count: 7)), strain: nil,
                          isEarlierDay: false),
    ]

    static func all(reduceTransparency: Bool? = nil) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    TodayTiles(content: row, reduceTransparency: reduceTransparency) { _ in }
                }
            }
        }
    }
}

#Preview("Today tiles · board, yesterday, calibrating, empty") {
    DarkPreview { TodayTilesPreview.all() }
}

#Preview("Today tiles · AX3") {
    DarkPreview { TodayTilesPreview.all().environment(\.dynamicTypeSize, .accessibility3) }
}

#Preview("Today tiles · Reduce Transparency") {
    DarkPreview { TodayTilesPreview.all(reduceTransparency: true) }
}
