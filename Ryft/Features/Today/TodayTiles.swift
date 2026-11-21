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
            return String(localized: "Slept enough on \(enough) of the last 7\u{00A0}nights; the last is the night shown",
                          comment: "VoiceOver on the 7 dots of Today's Sleep tile: nights asleep 90 % of the need or more; the last is the night shown.")
        }
        return String(localized: "Slept enough on \(enough) of the last 7\u{00A0}nights; the last is the night shown; \(unknown)\u{00A0}nights have no data",
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
        return String(localized: "HRV \(today)\u{00A0}milliseconds, lowest \(lowest) and highest \(highest) over the last 7\u{00A0}days",
                      comment: "VoiceOver on Today's Recovery tile: the HRV sparkline, the shown day's value and the week's range.")
    }

    /// "82 percent, High. HRV 66 milliseconds, …"; "75 percent, Yesterday, not today's score. …"; "No data, calibrating".
    var recoverySpoken: String {
        let main: String
        if let recovery {
            let percent = String(localized: "\(recovery)\u{00A0}percent")
            if isEarlierDay, let caption = recoveryCaption {
                main = String(localized: "\(percent), \(caption), not today's score")
            } else if let caption = recoveryCaption {
                main = String(localized: "\(recovery)\u{00A0}percent, \(caption)",
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

    private var recoveryWords: TodayTwoUpWords {
        TodayTwoUpWords(title: String(localized: "Recovery"), value: content.recoveryText,
                        unit: content.recovery == nil ? nil : "%", caption: content.recoveryCaption)
    }

    private var sleepWords: TodayTwoUpWords {
        TodayTwoUpWords(title: String(localized: "Sleep"), value: content.sleepText,
                        unit: content.sleepMinutes == nil ? nil : TodayTwoUpTile<DotRow>.hoursUnit, caption: content.caption)
    }

    private var recovery: some View {
        TodayTwoUpTile(metric: Theme.recovery, words: recoveryWords, partner: sleepWords, spoken: content.recoverySpoken,
                       hint: String(localized: "Opens Insights"), identifier: "today.tile.recovery",
                       reduceTransparency: reduceTransparency, action: { open(.insights) }) {
            Sparkline(values: content.hrvWeek)
        }
    }

    private var sleep: some View {
        TodayTwoUpTile(metric: Theme.metricSleep, words: sleepWords, partner: recoveryWords, spoken: content.sleepSpoken,
                       hint: String(localized: "Opens Sleep"), identifier: "today.tile.sleep",
                       reduceTransparency: reduceTransparency, action: { open(.sleep) }) {
            // Its summary is the tile's to read: the tile is the one element.
            DotRow(content.sleepWeek.marks, accessibilityLabel: Text(verbatim: content.sleepWeek.summary))
        }
    }
}

/// What a 2-up tile writes: its label, value, unit and caption.
struct TodayTwoUpWords: Equatable, Sendable {
    let title: String
    let value: String
    var unit: String?
    var caption: String?
}

/// A 2-up glow tile (§P4-1 row 11): the label top-leading with its series trailing on the label's baseline, the value
/// (34 Light) and its unit bottom-left, the caption bottom-right. From AX1 the rows stack (label, series, value, caption).
/// Below AX1 the pair arranges alike (`partner`, the other tile's words): a series goes under the label, and a caption
/// above the value, in both tiles when either tile needs it.
struct TodayTwoUpTile<Series: View>: View {
    let metric: Color
    let words: TodayTwoUpWords
    var partner: TodayTwoUpWords?
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
                    TodayTwoUpBoard(words: words, partner: partner, series: series)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: words.title))
        .accessibilityValue(Text(verbatim: spoken))
        .accessibilityHint(Text(verbatim: hint))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    /// AX1 and up: one under the other, nothing truncated; the numerals keep their size.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: TodayLayout.tileRowGap) {
            Text(verbatim: words.title)
                .ryftGlowLabelStyle()
                .fixedSize(horizontal: false, vertical: true)
            series()
            TodayTwoUpValue(value: words.value, unit: words.unit)
            if let caption = words.caption {
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
/// a caption never moves it (`TodayTwoUpValueRow`). `partner`, the other tile's words, is measured, never shown: the
/// pair arranges alike (`TodayTwoUpLabelRow`, `TodayTwoUpValueRow`).
struct TodayTwoUpBoard<Series: View>: View {
    let words: TodayTwoUpWords
    var partner: TodayTwoUpWords?
    @ViewBuilder var series: () -> Series

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodayTwoUpLabelRow {
                Text(verbatim: words.title)
                    .ryftGlowLabelStyle()
                    .lineLimit(1)
                series()
                if let partner {
                    Text(verbatim: partner.title)
                        .ryftGlowLabelStyle()
                        .lineLimit(1)
                        .partnerOnly()
                }
            }
            Spacer(minLength: TodayLayout.tileRowGap)
            TodayTwoUpValueRow {
                TodayTwoUpValue(value: words.value, unit: words.unit)
                if let caption = words.caption { Self.caption(caption) }
                if let partner {
                    TodayTwoUpValue(value: partner.value, unit: partner.unit).partnerOnly()
                    if let caption = partner.caption { Self.caption(caption).partnerOnly() }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: TodayLayout.twoUpContentHeight, maxHeight: .infinity, alignment: .topLeading)
    }

    private static func caption(_ caption: String) -> some View {
        Text(verbatim: caption)
            .ryftGlowLabelStyle()
            .multilineTextAlignment(.trailing)
            .minimumScaleFactor(TodayTwoUpValueRow.minimumScale)
    }
}

/// Whose a subview of a 2-up row is: the tile's own, or the other tile's, which the row measures to arrange as the
/// other tile does and never shows.
private struct TodayTwoUpPartnerKey: LayoutValueKey {
    static let defaultValue = false
}

private extension View {
    /// The other tile's words in a 2-up row: measured, hidden, not read by VoiceOver.
    func partnerOnly() -> some View {
        hidden().accessibilityHidden(true).layoutValue(key: TodayTwoUpPartnerKey.self, value: true)
    }
}

private extension LayoutSubviews {
    /// The tile's own subviews, in order, and the other tile's.
    var ownAndPartner: (own: [LayoutSubview], partner: [LayoutSubview]) {
        (filter { !$0[TodayTwoUpPartnerKey.self] }, filter { $0[TodayTwoUpPartnerKey.self] })
    }
}

/// A 2-up tile's top row: the label leading, the series trailing on the label's baseline with `seriesClearance` kept
/// for it. When the label, or the other tile's, would be cut there (larger text, a narrow phone), the series goes under
/// the label, leading and `tileRowGap` below, in both tiles: the label is never cut (B). Subviews: the label, the
/// series, and the other tile's label (`partnerOnly`).
struct TodayTwoUpLabelRow: Layout {
    /// Whether the series sits beside labels `labels` wide (one line each) in a row `width` wide.
    static func seriesBeside(width: CGFloat, labels: [CGFloat]) -> Bool {
        (labels.max() ?? 0) <= width - TodayLayout.seriesClearance
    }

    private static func beside(width: CGFloat, title: LayoutSubview, partner: [LayoutSubview]) -> Bool {
        seriesBeside(width: width, labels: ([title] + partner).map { $0.sizeThatFits(.unspecified).width })
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (own, partner) = subviews.ownAndPartner
        guard let title = own.first else { return .zero }
        let line = title.sizeThatFits(.unspecified)
        let width = proposal.width ?? line.width + TodayLayout.seriesClearance
        guard own.count > 1, !Self.beside(width: width, title: title, partner: partner) else {
            // Beside: as high as the label; the series may reach above it, as an overlay would.
            return CGSize(width: width, height: line.height)
        }
        return CGSize(width: width, height: line.height + TodayLayout.tileRowGap + own[1].sizeThatFits(.unspecified).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (own, partner) = subviews.ownAndPartner
        for hidden in partner { hidden.place(at: bounds.origin, proposal: .unspecified) }
        guard let title = own.first else { return }
        guard own.count > 1 else {
            title.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
            return
        }
        let series = own[1]
        if Self.beside(width: bounds.width, title: title, partner: partner) {
            let offer = ProposedViewSize(width: bounds.width - TodayLayout.seriesClearance, height: nil)
            title.place(at: bounds.origin, proposal: offer)
            // The series' baseline (its bottom: it has no text) on the label's, at the trailing edge.
            let baseline = bounds.minY + title.dimensions(in: offer)[.firstTextBaseline]
            let placed = series.dimensions(in: .unspecified)
            series.place(at: CGPoint(x: bounds.maxX - placed.width, y: baseline - placed[.firstTextBaseline]),
                         proposal: .unspecified)
        } else {
            let offer = ProposedViewSize(width: bounds.width, height: nil)
            title.place(at: bounds.origin, proposal: offer)
            series.place(at: CGPoint(x: bounds.minX, y: bounds.minY + title.dimensions(in: offer).height + TodayLayout.tileRowGap),
                         proposal: .unspecified)
        }
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
/// still doesn't goes above the value, trailing, wrapping if it must, and then the other tile's goes above too (C: the
/// pair's tiles are as wide, so the one with less room decides). The value's line is the row's bottom in every
/// arrangement, so its baseline never moves and no word is broken. Subviews: the value, the caption, and the other
/// tile's value and caption (`partnerOnly`).
struct TodayTwoUpValueRow: Layout {
    /// The least the caption shrinks to before it leaves the value's line.
    static let minimumScale: CGFloat = 0.8

    enum Arrangement: Equatable { case beside, besideScaled, above }

    /// Where the caption goes for a row `width` wide, a value `value` wide and a caption `caption` wide on one line.
    /// Scaled, it keeps 1 pt of slack over `minimumScale`: a text that only just fits at 0.8 can still be cut by
    /// rounding ("calibrat…"), so such a caption goes above.
    static func arrangement(width: CGFloat, value: CGFloat, caption: CGFloat) -> Arrangement {
        let room = width - value - TodayLayout.tileRowGap
        if caption <= room { return .beside }
        return caption * minimumScale + 1 <= room ? .besideScaled : .above
    }

    /// The arrangement of a row whose pair's other row has `partner` (its value's and caption's widths): above when
    /// either row's caption goes above, else this row's own.
    static func arrangement(width: CGFloat, value: CGFloat, caption: CGFloat,
                            partner: (value: CGFloat, caption: CGFloat)?) -> Arrangement {
        let own = arrangement(width: width, value: value, caption: caption)
        guard let partner, own != .above else { return own }
        return arrangement(width: width, value: partner.value, caption: partner.caption) == .above ? .above : own
    }

    /// The other row's value and caption widths, one line each; `nil` without a caption there.
    private static func partnerWidths(_ partner: [LayoutSubview]) -> (value: CGFloat, caption: CGFloat)? {
        guard partner.count > 1 else { return nil }
        return (partner[0].sizeThatFits(.unspecified).width, partner[1].sizeThatFits(.unspecified).width)
    }

    /// The row's depth under the value's baseline: the deeper descent of the line's texts (the value's, 34 pt against
    /// 13, in practice), or the value's alone with the caption above it.
    private static func below(value: LayoutSubview, caption: LayoutSubview?, arrangement: Arrangement?) -> CGFloat {
        let valueDescent = value.dimensions(in: .unspecified).height - value.dimensions(in: .unspecified)[.firstTextBaseline]
        guard let caption, arrangement != .above else { return valueDescent }
        let line = caption.dimensions(in: .unspecified)
        return max(valueDescent, line.height - line[.firstTextBaseline])
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (own, partner) = subviews.ownAndPartner
        guard let value = own.first else { return .zero }
        let valueSize = value.sizeThatFits(.unspecified)
        let width = proposal.width ?? valueSize.width
        guard own.count > 1 else { return CGSize(width: width, height: valueSize.height) }
        let caption = own[1]
        let line = caption.sizeThatFits(.unspecified)
        let arrangement = Self.arrangement(width: width, value: valueSize.width, caption: line.width,
                                           partner: Self.partnerWidths(partner))
        switch arrangement {
        case .beside, .besideScaled:
            // On the value's baseline: as high as the taller ascent and the deeper descent.
            let below = Self.below(value: value, caption: caption, arrangement: arrangement)
            let above = max(value.dimensions(in: .unspecified)[.firstTextBaseline],
                            caption.dimensions(in: .unspecified)[.firstTextBaseline])
            return CGSize(width: width, height: above + below)
        case .above:
            let wrapped = caption.sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: width, height: wrapped.height + TodayLayout.pendingLineGap + valueSize.height)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (own, partner) = subviews.ownAndPartner
        for hidden in partner { hidden.place(at: bounds.origin, proposal: .unspecified) }
        guard let value = own.first else { return }
        let valueDimensions = value.dimensions(in: .unspecified)
        let caption = own.count > 1 ? own[1] : nil
        let line = caption?.sizeThatFits(.unspecified) ?? .zero
        let arrangement = caption.map { _ in
            Self.arrangement(width: bounds.width, value: valueDimensions.width, caption: line.width,
                             partner: Self.partnerWidths(partner))
        }
        // The value's baseline sits `below` over the row's bottom: no descent hangs out of the row, and with the value's
        // the deeper one (always, at these sizes) its line ends on the bottom padding in every arrangement.
        let below = Self.below(value: value, caption: caption, arrangement: arrangement)
        let valueTop = bounds.maxY - below - valueDimensions[.firstTextBaseline]
        value.place(at: CGPoint(x: bounds.minX, y: valueTop), proposal: .unspecified)
        guard let caption, let arrangement else { return }
        switch arrangement {
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
                        TodayStrainValueRow(value: content.strainText, caption: content.strainCaption)
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

    private var value: some View { Self.value(content.strainText) }

    private var caption: some View {
        Self.caption(content.strainCaption)
            .lineLimit(1)
            .fixedSize()
    }

    static func value(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.ryftNumber(size: TodayLayout.strainNumeral, weight: .light))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }

    static func caption(_ text: String) -> some View {
        Text(verbatim: text).ryftGlowLabelStyle()
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

/// The strain tile's value and caption at accessibility sizes: the caption beside the value on its baseline when the
/// line fits, else under the value from the tile's leading edge, wrapping there (VN4), never a ragged column beside it.
struct TodayStrainValueRow: View {
    let value: String
    let caption: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: TodayLayout.strainCaptionGap) {
                TodayStrainTile.value(value)
                TodayStrainTile.caption(caption).lineLimit(1).fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) {
                TodayStrainTile.value(value)
                TodayStrainTile.caption(caption)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

/// xxxLarge at 390 (`DarkPreview`'s width), the largest size the pair stays side by side: the series under the label in
/// both tiles, and where a caption goes above its value the other tile's too (B, C): yesterday's and calibrating's
/// captions are above in both; the board's "High" stays beside.
#Preview("Today tiles · xxxLarge, the pair arranged alike") {
    DarkPreview { TodayTilesPreview.all().environment(\.dynamicTypeSize, .xxxLarge) }
}

#Preview("Today tiles · AX3") {
    DarkPreview { TodayTilesPreview.all().environment(\.dynamicTypeSize, .accessibility3) }
}

#Preview("Today tiles · Reduce Transparency") {
    DarkPreview { TodayTilesPreview.all(reduceTransparency: true) }
}

/// The strain tile's AX value row: beside the value where the line fits (AX3 in the tile at 390), under it from the
/// leading edge where it doesn't (AX5).
#Preview("Today strain value row · AX3 beside, AX5 under") {
    DarkPreview {
        VStack(alignment: .leading, spacing: 24) {
            TodayStrainValueRow(value: "12.4", caption: TodayStrainBand.moderate.caption)
                .environment(\.dynamicTypeSize, .accessibility3)
            TodayStrainValueRow(value: "12.4", caption: TodayStrainBand.moderate.caption)
                .environment(\.dynamicTypeSize, .accessibility5)
        }
        .frame(width: 318)
        .padding(20)
    }
}
