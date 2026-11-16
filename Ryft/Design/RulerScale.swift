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

        /// The ruler's height: 8 top + the tick row + 6 bottom (36; compact 32, derived).
        var height: CGFloat { tickRowTop + tickRowHeight + 6 }
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

    /// Volt: the needle is one of the signal's five marks (brief §1).
    static let needleColor = Theme.signal
    /// The smallest gap between two labels before they no longer fit on one line.
    static let labelMinGap: CGFloat = 8

    private let range: ClosedRange<Double>
    private let value: Double?
    private let zone: ClosedRange<Double>?
    private let zoneTint: Color
    private let zoneOpacity: Double?
    private let tickCount: Int
    private let labels: [String]
    private let size: Size
    private let accessibilityLabel: Text
    private let accessibilityValue: Text
    private let forcedReduceMotion: Bool?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.displayScale) private var displayScale

    /// - Parameters:
    ///   - zoneOpacity: `nil` is 0.55 (compact 0.60); Sleep passes 0.85 with `metricSleep`, Strain 0.95 with `metricStrain`.
    ///   - labels: already localized, spread edge to edge under the ruler ("0", "low", "moderate", "high", "100").
    ///   - reduceMotion: previews and tests; `nil` follows the system.
    init(range: ClosedRange<Double>, value: Double?, zone: ClosedRange<Double>? = nil,
         zoneTint: Color = Theme.textPrimary, zoneOpacity: Double? = nil, tickCount: Int,
         labels: [String] = [], size: Size = .regular,
         accessibilityLabel: Text, accessibilityValue: Text, reduceMotion: Bool? = nil) {
        self.range = range
        self.value = value
        self.zone = zone
        self.zoneTint = zoneTint
        self.zoneOpacity = zoneOpacity
        self.tickCount = tickCount
        self.labels = labels
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.forcedReduceMotion = reduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                .fill(zoneTint.opacity(zoneOpacity ?? size.defaultZoneOpacity))
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

    /// The labels on one line, first leading and last trailing; when they do not fit (large text), one wrapping line.
    private var labelRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    if index > 0 { Spacer(minLength: Self.labelMinGap) }
                    Text(verbatim: label).lineLimit(1).fixedSize()
                }
            }
            Text(verbatim: labels.joined(separator: " · "))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.ryft(.axis))
        .foregroundStyle(Theme.textTertiary)
    }

    // MARK: layout (pure)

    /// Tick `i` of `max(count, 2)` is centred at `i / (n − 1) × width`: the outer ticks' centres are the edges.
    nonisolated static func tickCentres(count: Int, width: CGFloat) -> [CGFloat] {
        let n = max(count, 2)
        return (0..<n).map { CGFloat($0) * width / CGFloat(n - 1) }
    }

    /// The ticks whose value `lo + i·(hi − lo)/(n − 1)` lies in `zone` (± 1e-9). None without a zone or for an empty range.
    nonisolated static func zoneTickIndices(count: Int, range: ClosedRange<Double>, zone: ClosedRange<Double>?) -> [Int] {
        let n = max(count, 2)
        let lo = range.lowerBound, hi = range.upperBound
        guard let zone, hi > lo else { return [] }
        return (0..<n).filter { i in
            let v = lo + Double(i) * (hi - lo) / Double(n - 1)
            return v >= zone.lowerBound - 1e-9 && v <= zone.upperBound + 1e-9
        }
    }

    /// The needle's centre: `clamp((value − lo) / (hi − lo), 0, 1) · width`. `nil` without a value, for NaN, or when
    /// `hi ≤ lo`.
    nonisolated static func needleX(value: Double?, range: ClosedRange<Double>, width: CGFloat) -> CGFloat? {
        needleFraction(value: value, range: range).map { CGFloat($0) * width }
    }

    /// The needle's place as a fraction of the width, clamped to 0…1.
    nonisolated static func needleFraction(value: Double?, range: ClosedRange<Double>) -> Double? {
        let lo = range.lowerBound, hi = range.upperBound
        guard let value, !value.isNaN, hi > lo else { return nil }
        return min(max((value - lo) / (hi - lo), 0), 1)
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
            RulerScale(range: 0...10, value: 7.8, zone: 7.5...8.3, zoneTint: Theme.metricSleep, zoneOpacity: 0.85,
                       tickCount: RulerScale.Ticks.sleep, labels: ["0 h", "need 8:18", "10 h"],
                       accessibilityLabel: Text("Sleep scale"),
                       accessibilityValue: Text("7 hours 48 minutes, need 8 hours 18 minutes, on a scale from 0 to 10 hours"))
            RulerScale(range: 0...21, value: 12.4, zone: 10...14, zoneTint: Theme.metricStrain, zoneOpacity: 0.95,
                       tickCount: RulerScale.Ticks.strain, labels: ["0", "target 10–14", "21"],
                       accessibilityLabel: Text("Strain scale"),
                       accessibilityValue: Text("12.4, in target 10 to 14, on a scale from 0 to 21"))
            GlowTile(Theme.metricStrain, minHeight: GlowTileSpec.twoUpMinHeight) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Strain").ryftGlowLabelStyle()
                    Text(verbatim: "12.4").font(.ryft(.metric))
                    Spacer(minLength: 0)
                    RulerScale(range: 0...21, value: 12.4, zone: 10...14, tickCount: RulerScale.Ticks.strainCompact,
                               size: .compact, accessibilityLabel: Text("Strain scale"),
                               accessibilityValue: Text("12.4, in target 10 to 14, on a scale from 0 to 21"))
                }
            }
            .frame(width: 169)
            RulerScale(range: 0...100, value: nil, zone: 67...100, tickCount: RulerScale.Ticks.today,
                       labels: ["0", "low", "moderate", "high", "100"],
                       accessibilityLabel: Text("Readiness scale"),
                       accessibilityValue: Text("No value yet, on a scale from 0 to 100"))
            RulerScale(range: 0...21, value: 23.5, zone: 10...14, zoneTint: Theme.metricStrain, zoneOpacity: 0.95,
                       tickCount: RulerScale.Ticks.strain, labels: ["0", "target 10–14", "21"],
                       accessibilityLabel: Text("Strain scale"),
                       accessibilityValue: Text("23.5, above target, on a scale from 0 to 21"))
        }
    }
}

#Preview("RulerScale · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 24) {
            RulerScale(range: 0...100, value: 84, zone: 67...100, tickCount: RulerScale.Ticks.today,
                       labels: ["0", "low", "moderate", "high", "100"],
                       accessibilityLabel: Text("Readiness scale"),
                       accessibilityValue: Text("84, high, on a scale from 0 to 100"))
            RulerScale(range: 0...10, value: 7.8, zone: 7.5...8.3, zoneTint: Theme.metricSleep, zoneOpacity: 0.85,
                       tickCount: RulerScale.Ticks.sleep, labels: ["0 h", "need 8:18", "10 h"],
                       accessibilityLabel: Text("Sleep scale"),
                       accessibilityValue: Text("7 hours 48 minutes, need 8 hours 18 minutes, on a scale from 0 to 10 hours"))
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
