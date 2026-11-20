// Sleep → Day's 2 × 2 neutral tiles (Nocturne, docs/work/2026-11-16-nocturne/design.md §P4-2 row 7, §P4-8): Consistency,
// Sleep debt, Efficiency, Restorative on `surface`, label top-left, value bottom-left, a dot row or a note bottom-right.
// Not buttons; each is one VoiceOver element with a sentence.
import SwiftUI

/// One neutral tile's content, formatted. Built by the `SleepTile` factories; `SleepNeutralTile` draws it.
struct SleepTile: Equatable, Identifiable {
    enum Kind: String, CaseIterable {
        case consistency, debt, efficiency, restorative
        /// Week and Month (§P5-7.2): the average quality; Bedtime (§P5-7.3): tonight's need and time in bed.
        case quality, need, timeInBed

        /// The UI tests' handle: `sleep.tile.consistency` …
        var identifier: String { "sleep.tile.\(rawValue)" }

        var title: String {
            switch self {
            case .consistency: return String(localized: "Consistency")
            case .debt: return String(localized: "Sleep debt")
            case .efficiency: return String(localized: "Efficiency")
            case .restorative: return String(localized: "Restorative")
            case .quality: return String(localized: "Quality")
            case .need: return String(localized: "Sleep need", comment: "Sleep → Bedtime's tile: tonight's sleep need (\"8:01 h\").")
            case .timeInBed: return String(localized: "Time in bed")
            }
        }
    }

    /// A note after the value, in its ink. Never the only cue: arrows and words carry the meaning.
    struct Note: Equatable {
        enum Ink: Equatable {
            /// The debt went down: the sleep colour.
            case sleep
            /// The debt went up: `textSecondary`.
            case secondary
            /// A description ("Deep + REM"): `textTertiary`.
            case tertiary
            /// A high debt: `warning`.
            case warning
        }

        let text: String
        let ink: Ink
    }

    /// A night counts as regular from this consistency: the platform's own line (`sleep-consistency-low` fires below it).
    static let regularThreshold = 60
    /// A debt above this many minutes is high (as before Nocturne).
    static let highDebt = 45

    let kind: Kind
    /// "86", "0:30", "None"; "–" without a value.
    let value: String
    /// "%" or "h" after the value; none with "–" or "None".
    let unit: String?
    /// Bottom-right, after the value: the debt's change and "high", Restorative's "Deep + REM".
    let notes: [Note]
    /// Consistency's nights, oldest first, the last the night shown; empty for the others.
    let marks: [DotRow.Mark]
    let spokenValue: String

    var id: Kind { kind }
    var title: String { kind.title }

    // MARK: factories (pure)

    /// The four tiles with "–" (loading, a failed load, no night).
    static func placeholders(locale: Locale = .autoupdatingCurrent) -> [SleepTile] {
        [consistency(nil, week: [], locale: locale), debt(nil, before: nil, locale: locale),
         efficiency(nil, locale: locale), SleepTile(kind: .restorative, value: Fmt.placeholder, unit: nil, notes: [],
                                                    marks: [], spokenValue: String(localized: "No data"))]
    }

    /// "86" + "%" and seven dots: full from 60, missed below, a small dot without a value, the last the night shown
    /// (`.today`). `week`: `sleepConsistency` oldest first, the last the night shown; empty draws no dots.
    static func consistency(_ value: Int?, week: [Int?], locale: Locale = .autoupdatingCurrent) -> SleepTile {
        let padding = [Int?](repeating: nil, count: max(0, SleepBoard.weekNights - week.count))
        let nights: [Int?] = week.isEmpty ? [] : Array((padding + week).suffix(SleepBoard.weekNights))
        let marks: [DotRow.Mark] = nights.enumerated().map { index, night in
            guard index < nights.count - 1 else { return .today }
            guard let night else { return .noData }
            return night >= regularThreshold ? .full : .missed
        }
        let spokenPercent = value.map { String(localized: "\($0) percent") } ?? String(localized: "No data")
        var spoken = spokenPercent
        if !nights.isEmpty {
            let regular = nights.filter { $0.map { $0 >= regularThreshold } ?? false }.count
            let irregular = nights.filter { $0.map { $0 < regularThreshold } ?? false }.count
            let unknown = nights.filter { $0 == nil }.count
            var parts = [String(localized: "\(regular) of the last 7 nights were regular",
                                comment: "VoiceOver, Sleep's Consistency tile: nights of the seven that were regular (60+). Plural: one \"was regular\".")]
            if irregular > 0 {
                parts.append(String(localized: "\(irregular) were not",
                                    comment: "VoiceOver, Sleep's Consistency tile, after the regular nights: those that were not. Plural: one \"was not\"."))
            }
            if unknown > 0 {
                parts.append(String(localized: "\(unknown) have no data",
                                    comment: "VoiceOver on Sleep's Consistency tile: nights without a consistency value. Needs a plural: one \"has no data\"."))
            }
            let last = String(localized: "the last is the night shown",
                              comment: "VoiceOver on Sleep's Consistency tile, after the counts: the last dot (in Volt) is the night on screen.")
            spoken = "\(spokenPercent). \(parts.joined(separator: ", ")); \(last)"
        }
        return SleepTile(kind: .consistency, value: value.map(String.init) ?? Fmt.placeholder, unit: value.map { _ in "%" },
                         notes: [], marks: marks, spokenValue: spoken)
    }

    /// "0:30" + "h", "None" at 0, "–" without one; the change against the night before ("▼ 0:42" in the sleep colour
    /// when it fell, "▲ 0:20" in `textSecondary` when it grew, none without both nights or without a change) and
    /// "high" in `warning` above 45 minutes.
    static func debt(_ minutes: Int?, before: Int?, locale: Locale = .autoupdatingCurrent) -> SleepTile {
        guard let minutes else {
            return SleepTile(kind: .debt, value: Fmt.placeholder, unit: nil, notes: [], marks: [],
                             spokenValue: String(localized: "No data"))
        }
        var notes: [Note] = [], spoken: [String] = []
        if minutes == 0 {
            spoken.append(String(localized: "None"))
        } else {
            spoken.append(Fmt.spokenDuration(minutes: minutes, locale: locale))
        }
        if let before, minutes != before {
            let change = abs(minutes - before), spokenChange = Fmt.spokenDuration(minutes: change, locale: locale)
            if minutes < before {
                notes.append(Note(text: "▼ \(Fmt.clock(minutes: change))", ink: .sleep))
                spoken.append(String(localized: "down \(spokenChange) from the night before",
                                     comment: "VoiceOver, Sleep's Sleep debt tile: the debt fell (\"down 42 minutes from the night before\")."))
            } else {
                notes.append(Note(text: "▲ \(Fmt.clock(minutes: change))", ink: .secondary))
                spoken.append(String(localized: "up \(spokenChange) from the night before",
                                     comment: "VoiceOver, Sleep's Sleep debt tile: the debt grew (\"up 20 minutes from the night before\")."))
            }
        }
        if minutes > highDebt {
            let high = String(localized: "sleep.debt.high", defaultValue: "high",
                              comment: "Sleep's Sleep debt tile, after the change (\"▼ 0:42 · high\"), also spoken: the debt is above 45 minutes. Lower case.")
            notes.append(Note(text: high, ink: .warning))
            spoken.append(high)
        }
        return SleepTile(kind: .debt, value: minutes == 0 ? String(localized: "None") : Fmt.clock(minutes: minutes),
                         unit: minutes == 0 ? nil : hours, notes: notes, marks: [], spokenValue: spoken.joined(separator: ", "))
    }

    /// "95" + "%" from `SleepDetail.efficiencyPercent`; "–" without it.
    static func efficiency(_ percent: Double?, locale: Locale = .autoupdatingCurrent) -> SleepTile {
        let rounded = percent.map { Int($0.rounded()) }
        return SleepTile(kind: .efficiency, value: rounded.map(String.init) ?? Fmt.placeholder, unit: rounded.map { _ in "%" },
                         notes: [], marks: [],
                         spokenValue: rounded.map { String(localized: "\($0) percent") } ?? String(localized: "No data"))
    }

    /// Deep + REM minutes from the stages ("3:20" + "h", D4-9), "Deep + REM" under it; the platform's 0–100
    /// `restorative` score is spoken. "–" without stages.
    static func restorative(_ sleep: SleepDetail, locale: Locale = .autoupdatingCurrent) -> SleepTile {
        let minutes = sleep.stageMinutes(.deep) + sleep.stageMinutes(.rem)
        let note = Note(text: String(localized: "Deep + REM",
                                     comment: "Sleep's Restorative tile, under the value: the time is deep plus REM sleep."),
                        ink: .tertiary)
        guard sleep.hasStages, minutes > 0 else {
            return SleepTile(kind: .restorative, value: Fmt.placeholder, unit: nil, notes: [note], marks: [],
                             spokenValue: String(localized: "No data"))
        }
        var spoken = String(localized: "\(Fmt.spokenDuration(minutes: minutes, locale: locale)) of deep and REM sleep",
                            comment: "VoiceOver on Sleep's Restorative tile: the deep and REM time (\"3 hours 20 minutes of deep and REM sleep\").")
        if let score = sleep.restorative {
            spoken += ", " + String(localized: "\(score) percent of the target",
                                    comment: "VoiceOver, Sleep's Restorative tile, after the time: its score, 0–100 (\"100 percent of the target\").")
        }
        return SleepTile(kind: .restorative, value: Fmt.clock(minutes: minutes), unit: hours, notes: [note], marks: [],
                         spokenValue: spoken)
    }

    /// The unit after a clock value ("0:30 h").
    private static var hours: String {
        String(localized: "h", comment: "Hours, the unit after a clock duration on Today's Sleep tile and on Sleep's tiles: \"7:48 h\", \"0:30 h\".")
    }
}

/// The four tiles: two columns 12 apart, one column from AX1 (§P4-8).
struct SleepTileGrid: View {
    let tiles: [SleepTile]
    /// Loading and a failed load: outlines (§P4-5).
    var isOutline = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: SleepLayout.tileGap) {
                ForEach(tiles) { SleepNeutralTile(tile: $0, isOutline: isOutline) }
            }
        } else {
            // A row is as high as its taller tile, and both fill it (a larger text size can grow one).
            Grid(horizontalSpacing: SleepLayout.tileGap, verticalSpacing: SleepLayout.tileGap) {
                ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { row in
                    GridRow {
                        SleepNeutralTile(tile: tiles[row], isOutline: isOutline)
                        if row + 1 < tiles.count {
                            SleepNeutralTile(tile: tiles[row + 1], isOutline: isOutline)
                        }
                    }
                }
            }
        }
    }
}

/// One neutral tile, 88 high (it grows with its text), radius 22, padding 14 / 16 / 12: the label 13 `textSecondary`;
/// at the bottom the value (`.metric`, 26 Light) and its unit (12 `textTertiary`), the dots or notes at the right. From AX1, and
/// whenever the row doesn't fit even with the note shrunk to `tileNoteMinimumScale`, the notes go under the value.
struct SleepNeutralTile: View {
    let tile: SleepTile
    var isOutline = false

    @Environment(\.dynamicTypeSize) private var typeSize

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SleepLayout.tileRadius, style: .continuous)
    }

    var body: some View {
        let padding = SleepLayout.tilePadding
        SleepTileLayout(minHeight: SleepLayout.tileHeight - padding.top - padding.bottom, gap: SleepLayout.tileInnerGap) {
            Text(tile.title)
                .ryftLabelStyle()
                .fixedSize(horizontal: false, vertical: true)
            SleepValueRowLayout(stacks: typeSize.isAccessibilitySize, gap: SleepLayout.tileNoteGap,
                                stackGap: SleepLayout.tileStackGap,
                                minimumScale: tile.marks.isEmpty ? SleepLayout.tileNoteMinimumScale : 1) {
                value
                trailing
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if isOutline {
                PlaceholderOutline(shape)
            } else {
                shape.fill(Theme.surface)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tile.title))
        .accessibilityValue(Text(tile.spokenValue))
        .accessibilityIdentifier(tile.kind.identifier)
    }

    private var value: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            // `.metric`: 26 Light at the default size, scaled with the text like its unit.
            Text(tile.value)
                .font(.ryft(.metric))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let unit = tile.unit {
                Text(unit)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var trailing: some View {
        if !tile.marks.isEmpty {
            DotRow(tile.marks, accessibilityLabel: Text(tile.spokenValue))
        } else if !tile.notes.isEmpty {
            if typeSize.isAccessibilitySize {
                notes
                    .font(.ryft(.caption))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // On the value's row it may shrink a little rather than drop under the value (SleepValueRowLayout).
                notes
                    .font(.ryft(.caption))
                    .lineLimit(1)
                    .minimumScaleFactor(SleepLayout.tileNoteMinimumScale)
            }
        }
    }

    /// The notes on one line, " · " between them, each in its ink.
    private var notes: Text {
        tile.notes.enumerated().reduce(Text(verbatim: "")) { line, item in
            let (index, note) = item
            let separator = index > 0 ? Text(verbatim: " · ").foregroundStyle(Self.ink(note.ink)) : Text(verbatim: "")
            return line + separator + Text(note.text).foregroundStyle(Self.ink(note.ink))
        }
    }

    private static func ink(_ ink: SleepTile.Note.Ink) -> Color {
        switch ink {
        case .sleep: return Theme.metricSleep
        case .secondary: return Theme.textSecondary
        case .tertiary: return Theme.textTertiary
        case .warning: return Theme.warning
        }
    }
}

/// A tile's label at the top and its value row at the bottom: at least `minHeight` high (the space between them takes
/// the rest), and as high as the two and `gap` when larger text needs more, so nothing overflows the tile.
struct SleepTileLayout: Layout {
    let minHeight: CGFloat
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        let content = sizes.reduce(0) { $0 + $1.height } + gap * CGFloat(max(sizes.count - 1, 0))
        // A taller row (the other tile grew) is filled, so the value rows stay level.
        let offered = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 0
        return CGSize(width: proposal.width ?? sizes.map(\.width).max() ?? 0, height: max(minHeight, content, offered))
    }

    /// The first subview top-leading, the last bottom-leading; any between follow the first.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = ProposedViewSize(width: bounds.width, height: nil)
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            if index == subviews.count - 1, index > 0 {
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading, proposal: width)
            } else {
                subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: width)
                y += subview.sizeThatFits(width).height + gap
            }
        }
    }
}

/// A tile's value and what follows it: on one row, the value at the left and the dots or the note at the right on its
/// baseline; the note may shrink to `minimumScale` to stay there. Otherwise, and when `stacks` (from AX1), the note goes
/// under the value. One subview (no note) is the value alone.
struct SleepValueRowLayout: Layout {
    let stacks: Bool
    /// The least space between the value and the note on one row.
    let gap: CGFloat
    /// The value → note space when stacked.
    let stackGap: CGFloat
    /// The least scale of the note on the row (1: it can't shrink, as the dots).
    let minimumScale: CGFloat

    private enum Arrangement { case alone, row(trailingWidth: CGFloat), stacked }

    private func arrangement(width: CGFloat?, subviews: Subviews) -> Arrangement {
        guard subviews.count > 1 else { return .alone }
        guard !stacks else { return .stacked }
        let value = subviews[0].sizeThatFits(.unspecified).width
        let trailing = subviews[1].sizeThatFits(.unspecified).width
        guard let width, width.isFinite else { return .row(trailingWidth: trailing) }
        let room = width - value - gap
        if room >= trailing { return .row(trailingWidth: trailing) }
        if room >= trailing * minimumScale { return .row(trailingWidth: room) }
        return .stacked
    }

    /// The row's height above and below the shared baseline.
    private func rowMetrics(_ subviews: Subviews, trailingWidth: CGFloat)
        -> (ascent: CGFloat, descent: CGFloat, value: ViewDimensions, trailing: ViewDimensions) {
        let value = subviews[0].dimensions(in: .unspecified)
        let trailing = subviews[1].dimensions(in: ProposedViewSize(width: trailingWidth, height: nil))
        let ascent = max(value[VerticalAlignment.firstTextBaseline], trailing[VerticalAlignment.firstTextBaseline])
        let descent = max(value.height - value[VerticalAlignment.firstTextBaseline],
                          trailing.height - trailing[VerticalAlignment.firstTextBaseline])
        return (ascent, descent, value, trailing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        switch arrangement(width: proposal.width, subviews: subviews) {
        case .alone:
            let value = subviews.first?.sizeThatFits(.unspecified) ?? .zero
            return CGSize(width: proposal.width ?? value.width, height: value.height)
        case .row(let trailingWidth):
            let m = rowMetrics(subviews, trailingWidth: trailingWidth)
            return CGSize(width: proposal.width ?? m.value.width + gap + m.trailing.width, height: m.ascent + m.descent)
        case .stacked:
            let value = subviews[0].sizeThatFits(.unspecified)
            let trailing = subviews[1].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            return CGSize(width: proposal.width ?? max(value.width, trailing.width),
                          height: value.height + stackGap + trailing.height)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        switch arrangement(width: bounds.width, subviews: subviews) {
        case .alone:
            subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading, proposal: .unspecified)
        case .row(let trailingWidth):
            let m = rowMetrics(subviews, trailingWidth: trailingWidth)
            let baseline = bounds.maxY - m.descent
            subviews[0].place(at: CGPoint(x: bounds.minX, y: baseline - m.value[VerticalAlignment.firstTextBaseline]),
                              proposal: .unspecified)
            subviews[1].place(at: CGPoint(x: bounds.maxX - m.trailing.width,
                                          y: baseline - m.trailing[VerticalAlignment.firstTextBaseline]),
                              proposal: ProposedViewSize(width: trailingWidth, height: nil))
        case .stacked:
            let value = subviews[0].sizeThatFits(.unspecified)
            let width = ProposedViewSize(width: bounds.width, height: nil)
            let trailing = subviews[1].sizeThatFits(width)
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading, proposal: width)
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - trailing.height - stackGap - value.height),
                              proposal: .unspecified)
        }
    }
}
