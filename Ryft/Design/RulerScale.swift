// A ruler under a hero value (Nocturne, docs/work/2026-11-16-nocturne/design.md §P2-2): evenly spaced ticks across the
// range, the band or target zone as longer, thicker ticks, and the Volt needle at the value. The ticks and the needle
// are fixed-size graphics; only the labels under them scale with Dynamic Type.
import SwiftUI

/// A 0…max scale with a zone and a needle. One accessibility element: the caller's label names the subject, the
/// caller's value is the sentence ("84, high, on a scale from 0 to 100"), because the state is never colour alone.
struct RulerScale: View {
    enum Size {
        /// Today, Sleep, Strain. `compact`: the ruler inside Today's strain glow tile.
        case regular, compact

        /// The ruler's height: 8 top + the tick row + 6 bottom (36; compact 32, derived). The next block is measured
        /// from this box, not from the labels (the board, VF1).
        var height: CGFloat { tickRowTop + tickRowHeight + 6 }
        /// The labels' top: 2 under the tick row (the board's margin), so they overflow the box (+32 regular).
        var labelTop: CGFloat { tickRowTop + tickRowHeight + 2 }
        /// The tick row starts under 8 pt of top padding, where the needle's head sits.
        var tickRowTop: CGFloat { 8 }
        var tickRowHeight: CGFloat { self == .regular ? 22 : 18 }
        /// Ticks are centred vertically in their row.
        var tickRowMidY: CGFloat { tickRowTop + tickRowHeight / 2 }
        /// A tick outside the zone, and its strength (`textPrimary` at this opacity).
        var outsideTick: CGSize { self == .regular ? CGSize(width: 1, height: 8) : CGSize(width: 1, height: 7) }
        var outsideOpacity: Double { self == .regular ? 0.22 : 0.26 }
        /// A tick inside the zone, and the zone tint's opacity when the caller passes none.
        var zoneTick: CGSize { self == .regular ? CGSize(width: 1.5, height: 14) : CGSize(width: 1.5, height: 12) }
        var defaultZoneOpacity: Double { self == .regular ? 0.55 : 0.60 }
        /// The needle: a triangle pointing down with its apex at the tick row's top, then a line into the row.
        var needleHead: CGSize { CGSize(width: 12, height: 8) }
        var needleLine: CGSize { self == .regular ? CGSize(width: 1.5, height: 20) : CGSize(width: 1.5, height: 16) }
    }

    /// Tick counts per board, chosen so the zone edges land on ticks.
    enum Ticks { static let today = 61, sleep = 61, strain = 64, strainCompact = 43 }

    /// The zone ticks' ink: a tint at an opacity. Callers pick a preset; the init is private, so there are no literals.
    struct ZoneStyle: Equatable {
        let tint: Color
        /// The preset's own opacity; `nil` is the size's default (0.55 regular, 0.60 compact). Read `opacity(for:)`.
        let fixedOpacity: Double?

        private init(tint: Color, fixedOpacity: Double?) {
            self.tint = tint
            self.fixedOpacity = fixedOpacity
        }

        /// Today's readiness band and the compact strain tile: `textPrimary` at the size's default.
        static let standard = ZoneStyle(tint: Theme.textPrimary, fixedOpacity: nil)
        /// Sleep's need zone: `metricSleep` at 85 %.
        static let sleep = ZoneStyle(tint: Theme.metricSleep, fixedOpacity: 0.85)
        /// Strain's target zone: `metricStrain` at 95 %.
        static let strain = ZoneStyle(tint: Theme.metricStrain, fixedOpacity: 0.95)

        /// The opacity the zone ticks are drawn at in `size`.
        func opacity(for size: Size) -> Double { fixedOpacity ?? size.defaultZoneOpacity }
    }

    /// Volt: the needle is one of the signal's five marks (brief §1).
    static let needleColor = Theme.signal
    /// The smallest gap between two labels before they no longer fit on one line: the row then falls back before the
    /// labels run together (`RulerLabels`: below AX1 to lines of labels joined by " · ", from AX1 to fewer labels).
    static let labelMinGap: CGFloat = 16
    /// What stays clear under the labels when they grow past the caller's gap (AX sizes): the next block is at
    /// `max(box + gap, labels' bottom + 8)`.
    nonisolated static let labelClearance: CGFloat = 8

    private let range: ClosedRange<Double>
    private let value: Double?
    private let zone: ClosedRange<Double>?
    private let zoneStyle: ZoneStyle
    private let tickCount: Int
    private let labels: [String]
    private let size: Size
    private let accessibilityLabel: Text
    private let accessibilityValue: Text
    private let forcedReduceMotion: Bool?
    private let followingGap: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Inside a glow tile: its label ink (`GlowTile` sets it), which the compact ruler's labels take.
    @Environment(\.glowLabelOpacity) private var glowLabelOpacity

    /// - Parameters:
    ///   - zone: the band or target in the range's units. Build one from server data with `RulerScale.zone(lo:hi:)`,
    ///     which is `nil` where `lo...hi` would trap (a missing, non-finite or reversed bound).
    ///   - zoneStyle: `.standard` (`textPrimary` at 0.55, compact 0.60), `.sleep` or `.strain`.
    ///   - labels: already localized, spread edge to edge under the ruler ("0", "low", "moderate", "high", "100").
    ///   - reduceMotion: previews and tests; `nil` follows the system.
    ///   - followingGap: the gap the caller puts under the ruler before the next block. The labels hang 2 under the tick
    ///     row and overflow the 36 pt box; the ruler is as tall as the box, or more where the labels would come within
    ///     `labelClearance` of the next block (`layoutHeight`). `nil`: the ruler encloses its labels.
    init(range: ClosedRange<Double>, value: Double?, zone: ClosedRange<Double>? = nil,
         zoneStyle: ZoneStyle = .standard, tickCount: Int,
         labels: [String] = [], size: Size = .regular,
         accessibilityLabel: Text, accessibilityValue: Text, reduceMotion: Bool? = nil, followingGap: CGFloat? = nil) {
        self.range = range
        self.value = value
        self.zone = zone
        self.zoneStyle = zoneStyle
        self.tickCount = tickCount
        self.labels = labels
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.forcedReduceMotion = reduceMotion
        self.followingGap = followingGap
    }

    var body: some View {
        RulerStack(size: size, followingGap: followingGap) {
            graphic
            if !labels.isEmpty { labelRow }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var graphic: some View {
        let count = max(tickCount, 2)
        let inZone = Self.zoneTickIndices(count: count, range: range, zone: zone)
        let zoneSet = Set(inZone)
        let outside = (0..<count).filter { !zoneSet.contains($0) }
        let fraction = Self.needleFraction(value: value, range: range)
        return ZStack {
            RulerTicks(count: count, indices: outside, tick: size.outsideTick, midY: size.tickRowMidY, scale: displayScale)
                .fill(Theme.textPrimary.opacity(size.outsideOpacity))
            RulerTicks(count: count, indices: inZone, tick: size.zoneTick, midY: size.tickRowMidY, scale: displayScale)
                .fill(zoneStyle.tint.opacity(zoneStyle.opacity(for: size)))
            if let fraction {
                RulerNeedle(fraction: fraction, head: size.needleHead, line: size.needleLine, top: size.tickRowTop)
                    .fill(Self.needleColor)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: size.height)
        // Only the needle moves; the first appearance does not animate, Reduce Motion jumps.
        .animation(Theme.Motion.respecting(forcedReduceMotion ?? systemReduceMotion, Theme.Motion.quick), value: fraction)
    }

    /// The labels on one line, first leading and last trailing; when they do not fit (large text), lines of whole
    /// labels below AX1 and fewer labels from AX1 (`RulerLabels`).
    private var labelRow: some View {
        RulerLabels(labels: labels)
            .font(.ryft(.axis))
            .foregroundStyle(Self.labelColor(size: size, dynamicTypeSize: typeSize, glowLabelOpacity: glowLabelOpacity))
    }

    // MARK: layout (pure)

    /// The ruler's height for labels `labelsHeight` tall (0 without labels): the box, or more where the labels' bottom
    /// plus `labelClearance` would pass the box plus the caller's gap. Without a gap it encloses the labels.
    nonisolated static func layoutHeight(size: Size, labelsHeight: CGFloat, followingGap: CGFloat?) -> CGFloat {
        guard labelsHeight > 0 else { return size.height }
        let labelsBottom = size.labelTop + labelsHeight
        guard let followingGap else { return max(size.height, labelsBottom) }
        return max(size.height, labelsBottom + labelClearance - followingGap)
    }

    /// The labels' ink as an opacity of `textPrimary`; `nil` is `textTertiary`. A regular ruler sits on the screen and
    /// keeps `textTertiary`. The compact ruler only lives inside a glow tile, where its edge labels sit in the lighter
    /// outer region: it takes the tile's label ink (`glowLabelOpacity`: full in a recovery tile, else 78 %, full from AX1;
    /// §P4-3), or without a tile the glow label's `GlowTileSpec.labelOpacity(for:)`.
    nonisolated static func labelOpacity(size: Size, dynamicTypeSize: DynamicTypeSize, glowLabelOpacity: Double? = nil) -> Double? {
        switch size {
        case .regular: return nil
        case .compact: return glowLabelOpacity ?? GlowTileSpec.labelOpacity(for: dynamicTypeSize)
        }
    }

    /// The labels' colour: `textPrimary` at `labelOpacity(size:dynamicTypeSize:glowLabelOpacity:)`, or `textTertiary`
    /// where that is `nil`.
    nonisolated static func labelColor(size: Size, dynamicTypeSize: DynamicTypeSize, glowLabelOpacity: Double? = nil) -> Color {
        labelOpacity(size: size, dynamicTypeSize: dynamicTypeSize, glowLabelOpacity: glowLabelOpacity)
            .map { Theme.textPrimary.opacity($0) } ?? Theme.textTertiary
    }

    /// A zone from server data (the strain target, a sleep need): `nil` unless both bounds are present and finite and
    /// `lo ≤ hi`, so a reversed or missing bound draws no zone instead of trapping in `lo...hi`.
    nonisolated static func zone(lo: Double?, hi: Double?) -> ClosedRange<Double>? {
        guard let lo, let hi, lo.isFinite, hi.isFinite, lo <= hi else { return nil }
        return lo...hi
    }

    /// Tick `i` of `max(count, 2)` is centred at `i / (n − 1) × width`: the outer ticks' centres are the edges.
    nonisolated static func tickCentres(count: Int, width: CGFloat) -> [CGFloat] {
        let n = max(count, 2)
        return (0..<n).map { CGFloat($0) * width / CGFloat(n - 1) }
    }

    /// The ticks whose value `lo + i·(hi − lo)/(n − 1)` lies in `zone` (± 1e-9). A zone that overlaps the range but is
    /// narrower than the tick pitch still marks one tick: the one nearest the zone's midpoint (clamped into the range;
    /// a tie goes to the higher tick), so the graphic agrees with a sentence that says "in target". None without a
    /// zone, for a zone entirely outside the range, or for an empty range.
    nonisolated static func zoneTickIndices(count: Int, range: ClosedRange<Double>, zone: ClosedRange<Double>?) -> [Int] {
        let n = max(count, 2)
        let lo = range.lowerBound, hi = range.upperBound
        let tolerance = 1e-9
        guard let zone, hi > lo else { return [] }
        let inside = (0..<n).filter { i in
            let v = lo + Double(i) * (hi - lo) / Double(n - 1)
            return v >= zone.lowerBound - tolerance && v <= zone.upperBound + tolerance
        }
        guard inside.isEmpty else { return inside }
        guard zone.upperBound >= lo - tolerance, zone.lowerBound <= hi + tolerance else { return [] }
        let middle = min(max((zone.lowerBound + zone.upperBound) / 2, lo), hi)
        let position = (middle - lo) / (hi - lo) * Double(n - 1)
        guard position.isFinite else { return [] }
        // + tolerance: a tie computed as 25.499999999999996 still goes to the higher tick.
        return [min(max(Int((position + tolerance).rounded()), 0), n - 1)]
    }

    /// The needle's centre: `clamp((value − lo) / (hi − lo), 0, 1) · width`. `nil` without a value, for NaN, or when
    /// `hi ≤ lo`.
    nonisolated static func needleX(value: Double?, range: ClosedRange<Double>, width: CGFloat) -> CGFloat? {
        needleFraction(value: value, range: range).map { CGFloat($0) * width }
    }

    /// The ways to set `count` labels on lines of whole labels, in the order `RulerLabels` tries them: fewer lines first,
    /// and among as many lines the fuller earlier lines first, as text wraps. Each is the lines' ranges of labels.
    nonisolated static func labelLines(count: Int) -> [[Range<Int>]] {
        guard count > 0 else { return [] }
        func lines(from start: Int, into parts: Int) -> [[Range<Int>]] {
            guard parts > 1 else { return [[start..<count]] }
            return stride(from: count - start - (parts - 1), through: 1, by: -1).flatMap { first in
                lines(from: start + first, into: parts - 1).map { [start..<start + first] + $0 }
            }
        }
        return (1...count).flatMap { lines(from: 0, into: $0) }
    }

    /// From AX1, the label sets `RulerLabels` tries on one line, in order (Nocturne gate D9 row 4): all of them; the two
    /// ends; the first alone. By priority, the ends first; the interior labels come only all together, so a ruler never
    /// shows one band word without its neighbours ("0 · moderate · 100" would read as if low and high were not there).
    nonisolated static func accessibilityLabelSets(_ labels: [String]) -> [[String]] {
        guard let first = labels.first, let last = labels.last else { return [] }
        var sets = [labels]
        if labels.count > 2 { sets.append([first, last]) }
        if labels.count > 1 { sets.append([first]) }
        return sets
    }

    /// The needle's place as a fraction of the width, clamped to 0…1.
    nonisolated static func needleFraction(value: Double?, range: ClosedRange<Double>) -> Double? {
        let lo = range.lowerBound, hi = range.upperBound
        guard let value, !value.isNaN, hi > lo else { return nil }
        return min(max((value - lo) / (hi - lo), 0), 1)
    }
}

/// A ruler's labels (D): on one line, first leading and last trailing, at least `RulerScale.labelMinGap` apart. When
/// they don't fit:
/// - Below AX1, the fewest lines of whole labels with " · " between them, the earlier lines the fuller
///   (`RulerScale.labelLines`), so no line starts or ends with a separator ("0 · low · moderate", "high · 100", never
///   "· high · 100"); when a label doesn't fit on a line of its own either, one label per line, wrapping.
/// - From AX1 (Nocturne gate D9 row 4), by priority: the two end labels, each under its end tick (first leading, last
///   trailing), and the interior labels only while all of them keep the 16 pt gap on the one line
///   (`RulerScale.accessibilityLabelSets`). A label that doesn't fit is dropped, never joined with "·" and never set
///   flush left away from its tick: at AX3 Today's "0 · low · moderate · high · 100" reads "0 … 100". Nothing is lost:
///   the band word is in the numeral's caption and in the ruler's VoiceOver value (the ruler is one element and ignores
///   its labels). When not even the first label fits, none shows.
///
/// The caller sets the font and ink.
///
/// Limits (N4): the candidates are every way to cut the labels into runs, 2^(n − 1) of them, which `ViewThatFits`
/// measures in turn: fine for the rulers' 2 to 5 labels (16 at most), not for long lists, so it asserts 6 or fewer.
/// Not mirrored for right-to-left: the ticks and the needle run left to right while the labels follow the layout
/// direction (RYFT is English only).
struct RulerLabels: View {
    let labels: [String]

    @Environment(\.dynamicTypeSize) private var typeSize

    init(labels: [String]) {
        // 2^(n − 1) candidates, each measured by `ViewThatFits`: 6 labels is 32; more would make every layout pass slow.
        assert(labels.count <= 6, "RulerLabels tries every cut of the labels into lines: keep a ruler to 6 or fewer")
        self.labels = labels
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(RulerScale.accessibilityLabelSets(labels).enumerated()), id: \.offset) { _, set in
                    Self.line(set)
                }
                // Always fits: the ruler keeps its box, and VoiceOver its value.
                Color.clear.frame(width: 0, height: 0)
            }
        } else {
            standardLayout
        }
    }

    /// The labels on one line, spread edge to edge, at least `RulerScale.labelMinGap` apart.
    private static func line(_ labels: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                if index > 0 { Spacer(minLength: RulerScale.labelMinGap) }
                Text(verbatim: label).lineLimit(1).fixedSize()
            }
        }
    }

    /// Below AX1: one line, else lines of whole labels joined by " · ", else one label per line.
    private var standardLayout: some View {
        ViewThatFits(in: .horizontal) {
            Self.line(labels)
            ForEach(Array(RulerScale.labelLines(count: labels.count).enumerated()), id: \.offset) { _, lines in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines, id: \.lowerBound) { line in
                        Text(verbatim: labels[line].joined(separator: " · ")).lineLimit(1).fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(verbatim: label).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The graphic at the top, the labels (if any) at `labelTop`, overflowing the box; as tall as
/// `RulerScale.layoutHeight(size:labelsHeight:followingGap:)`.
private struct RulerStack: Layout {
    let size: RulerScale.Size
    let followingGap: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let labels = subviews.count > 1 ? subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height : 0
        return CGSize(width: width, height: RulerScale.layoutHeight(size: size, labelsHeight: labels, followingGap: followingGap))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let graphic = subviews.first else { return }
        graphic.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: size.height))
        if subviews.count > 1 {
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + size.labelTop),
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

/// Ticks at the given indices, centred vertically on `midY`, their left edge snapped to the device pixel. Not clipped:
/// the outer ticks overhang the edges by half their width.
private struct RulerTicks: Shape {
    let count: Int
    let indices: [Int]
    let tick: CGSize
    let midY: CGFloat
    let scale: CGFloat

    func path(in rect: CGRect) -> Path {
        let centres = RulerScale.tickCentres(count: count, width: rect.width)
        let scale = max(scale, 1)
        var path = Path()
        for i in indices where centres.indices.contains(i) {
            let x = ((rect.minX + centres[i] - tick.width / 2) * scale).rounded() / scale
            path.addRect(CGRect(x: x, y: rect.minY + midY - tick.height / 2, width: tick.width, height: tick.height))
        }
        return path
    }
}

/// The needle: a triangle pointing down, apex at `top`, then a line. Its x animates as a fraction of the width.
private struct RulerNeedle: Shape {
    var fraction: Double
    let head: CGSize
    let line: CGSize
    let top: CGFloat

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let x = rect.minX + CGFloat(fraction) * rect.width
        let apex = rect.minY + top
        var path = Path()
        path.move(to: CGPoint(x: x - head.width / 2, y: apex - head.height))
        path.addLine(to: CGPoint(x: x + head.width / 2, y: apex - head.height))
        path.addLine(to: CGPoint(x: x, y: apex))
        path.closeSubpath()
        path.addRect(CGRect(x: x - line.width / 2, y: apex, width: line.width, height: line.height))
        return path
    }
}

#Preview("RulerScale", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 24) {
            RulerScale(range: 0...100, value: 84, zone: 67...100, tickCount: RulerScale.Ticks.today,
                       labels: ["0", "low", "moderate", "high", "100"],
                       accessibilityLabel: Text("Readiness scale"),
                       accessibilityValue: Text("84, high, on a scale from 0 to 100"))
            RulerScale(range: 0...10, value: 7.8, zone: 7.5...8.3, zoneStyle: .sleep,
                       tickCount: RulerScale.Ticks.sleep, labels: ["0 h", "need 8:18", "10 h"],
                       accessibilityLabel: Text("Sleep scale"),
                       accessibilityValue: Text("7 hours 48 minutes, need 8 hours 18 minutes, on a scale from 0 to 10 hours"))
            RulerScale(range: 0...21, value: 12.4, zone: 10...14, zoneStyle: .strain,
                       tickCount: RulerScale.Ticks.strain, labels: ["0", "target 10–14", "21"],
                       accessibilityLabel: Text("Strain scale"),
                       accessibilityValue: Text("12.4, in target 10 to 14, on a scale from 0 to 21"))
            GlowTile(Theme.metricStrain, kind: .strain) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Strain").ryftGlowLabelStyle()
                    Spacer(minLength: 0)
                    RulerScale(range: 0...21, value: 12.4, zone: 10...14, tickCount: RulerScale.Ticks.strainCompact,
                               labels: ["0", "21"], size: .compact, accessibilityLabel: Text("Strain scale"),
                               accessibilityValue: Text("12.4, in target 10 to 14, on a scale from 0 to 21"))
                }
            }
            RulerScale(range: 0...100, value: nil, zone: 67...100, tickCount: RulerScale.Ticks.today,
                       labels: ["0", "low", "moderate", "high", "100"],
                       accessibilityLabel: Text("Readiness scale"),
                       accessibilityValue: Text("No value yet, on a scale from 0 to 100"))
            RulerScale(range: 0...21, value: 23.5, zone: 10...14, zoneStyle: .strain,
                       tickCount: RulerScale.Ticks.strain, labels: ["0", "target 10–14", "21"],
                       accessibilityLabel: Text("Strain scale"),
                       accessibilityValue: Text("23.5, above target, on a scale from 0 to 21"))
        }
    }
}

/// The three screens' rulers at an accessibility size: from AX1 the labels that don't fit on one line are dropped, ends last
/// (at AX3 Today's reads "0 … 100", Sleep's and Strain's keep all three; at AX5 every ruler shows its ends).
@MainActor
private func rulersAtSize(_ size: DynamicTypeSize) -> some View {
    DarkPreview {
        VStack(alignment: .leading, spacing: 24) {
            RulerScale(range: 0...100, value: 84, zone: 67...100, tickCount: RulerScale.Ticks.today,
                       labels: ["0", "low", "moderate", "high", "100"],
                       accessibilityLabel: Text("Readiness scale"),
                       accessibilityValue: Text("84, high, on a scale from 0 to 100"))
            RulerScale(range: 0...10, value: 7.8, zone: 7.5...8.3, zoneStyle: .sleep,
                       tickCount: RulerScale.Ticks.sleep, labels: ["0 h", "need 8:18", "10 h"],
                       accessibilityLabel: Text("Sleep scale"),
                       accessibilityValue: Text("7 hours 48 minutes, need 8 hours 18 minutes, on a scale from 0 to 10 hours"))
            RulerScale(range: 0...21, value: 12.4, zone: 10...14, zoneStyle: .strain,
                       tickCount: RulerScale.Ticks.strain, labels: StrainHero.rulerLabels,
                       accessibilityLabel: Text("Strain scale"),
                       accessibilityValue: Text("12.4, in target 10 to 14, on a scale from 0 to 21"))
        }
    }
    .environment(\.dynamicTypeSize, size)
}

#Preview("RulerScale · AX3", traits: .sizeThatFitsLayout) { rulersAtSize(.accessibility3) }

#Preview("RulerScale · AX5", traits: .sizeThatFitsLayout) { rulersAtSize(.accessibility5) }
