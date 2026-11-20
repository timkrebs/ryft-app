// The small trend line of an Insights trend card (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-5.2 and §P5-5.3): the
// series as a 1.4 pt line over its 30-day range, no axes. A missing day breaks the line, a point alone is a 3 pt dot, the y scale
// spans the series and the range with a 2 pt inset. While the series loads (or has no point) it is a flat 1 pt line, no
// spinner. The card around it (name, value, delta, note) is T5.3's; the detailed chart stays `TrendChart`.
import SwiftUI

struct TrendLine: View {
    /// Where the series' last point is against the range: what VoiceOver's sentence ends with.
    enum Ending: Equatable, Sendable {
        case above, within, below
    }

    /// The line: 1.4 pt, round caps and joins. A lone point: a 3 pt dot.
    nonisolated static let lineWidth: CGFloat = 1.4, dotSize: CGFloat = 3
    /// The space kept above the highest and below the lowest value (series or range).
    nonisolated static let inset: CGFloat = 2
    /// The pending line: 1 pt, ink at 22 %, across the middle.
    nonisolated static let pendingWidth: CGFloat = 1, pendingOpacity = 0.22
    /// The range's fill: the line colour at 12 % (`textPrimary` at 6 % for readiness, the caller's `bandOpacity`).
    nonisolated static let bandOpacity = 0.12
    /// The card's chart box at 390: 318 × 48.
    nonisolated static let height: CGFloat = 48

    private let values: [Double?]
    private let band: ClosedRange<Double>?
    private let color: Color
    private let bandOpacity: Double
    private let isPending: Bool
    private let accessibilityLabel: Text
    private let spokenLatest: Text?

    /// - Parameters:
    ///   - values: one per day, oldest first; `nil` is a day without a value (the line breaks there).
    ///   - band: the 30-day range drawn behind the line; `nil` draws none (calibrating).
    ///   - color: the line's (`recovery`, `metricSleep`, `metricStrain`, `textPrimary`); the band is the same colour.
    ///   - bandOpacity: 12 %, or 6 % for an ink line.
    ///   - isPending: loading with nothing cached: the flat line, whatever `values` holds.
    ///   - accessibilityLabel: "Readiness over 30 days".
    ///   - spokenLatest: the last value as VoiceOver reads it ("78"), for the sentence's end when there is no band.
    init(values: [Double?], band: ClosedRange<Double>? = nil, color: Color, bandOpacity: Double = TrendLine.bandOpacity,
         isPending: Bool = false, accessibilityLabel: Text, spokenLatest: Text? = nil) {
        self.values = values
        self.band = band
        self.color = color
        self.bandOpacity = bandOpacity
        self.isPending = isPending
        self.accessibilityLabel = accessibilityLabel
        self.spokenLatest = spokenLatest
    }

    /// Flat: loading, or a series without a point.
    private var isFlat: Bool { isPending || !values.contains { $0 != nil } }

    var body: some View {
        Canvas { context, size in
            if isFlat {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(line, with: .color(Theme.textPrimary.opacity(Self.pendingOpacity)), lineWidth: Self.pendingWidth)
                return
            }
            let geometry = TrendLineGeometry(values: values, band: band, size: size)
            if let rect = geometry.bandRect {
                context.fill(Path(rect), with: .color(color.opacity(bandOpacity)))
            }
            let style = StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
            for run in geometry.runs {
                if run.count == 1, let point = run.first {
                    let r = Self.dotSize / 2
                    context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: Self.dotSize, height: Self.dotSize)),
                                 with: .color(color))
                } else {
                    var path = Path()
                    path.addLines(run)
                    context.stroke(path, with: .color(color), style: style)
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(spokenValue)
    }

    private var spokenValue: Text {
        if isPending { return Text("Loading…") }
        if let ending = Self.ending(values: values, band: band) { return Text(Self.spoken(ending)) }
        if let spokenLatest { return Text("ending at \(spokenLatest)", comment: "VoiceOver: a trend line without a range ends at this value.") }
        return Text("No data")
    }

    /// The last value against the range: above it, within it (its bounds included) or below; `nil` without a range or a value.
    nonisolated static func ending(values: [Double?], band: ClosedRange<Double>?) -> Ending? {
        guard let band, let last = values.compactMap({ $0 }).last else { return nil }
        if last > band.upperBound { return .above }
        if last < band.lowerBound { return .below }
        return .within
    }

    /// "ending above its usual range" (§P5-5.2's VoiceOver: the card reads "Readiness over 30 days, ending above its usual range").
    static func spoken(_ ending: Ending) -> String {
        switch ending {
        case .above: return String(localized: "ending above its usual range", comment: "VoiceOver: the end of a trend line's sentence.")
        case .within: return String(localized: "ending within its usual range", comment: "VoiceOver: the end of a trend line's sentence.")
        case .below: return String(localized: "ending below its usual range", comment: "VoiceOver: the end of a trend line's sentence.")
        }
    }
}

/// Where a trend line draws, as values (tests read it): the y scale over the series and the band with the 2 pt inset, the runs of
/// consecutive days as points, and the band's rectangle.
struct TrendLineGeometry: Equatable, Sendable {
    /// The values' span: the series' values and the band's bounds; `nil` without a value.
    let domain: ClosedRange<Double>?
    /// Runs of consecutive days with a value, as points; a run of one is a dot.
    let runs: [[CGPoint]]
    /// The band across the whole width; `nil` without one.
    let bandRect: CGRect?

    init(values: [Double?], band: ClosedRange<Double>?, size: CGSize) {
        let present = values.compactMap { $0 }
        var all = present
        if let band { all += [band.lowerBound, band.upperBound] }
        let domain = all.min().flatMap { lo in all.max().map { lo...$0 } }
        self.domain = domain
        let n = values.count
        func x(_ i: Int) -> CGFloat {
            n > 1 ? size.width * CGFloat(i) / CGFloat(n - 1) : size.width / 2
        }
        func y(_ v: Double) -> CGFloat { Self.y(v, domain: domain, height: size.height) }
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []
        for (i, value) in values.enumerated() {
            if let value {
                current.append(CGPoint(x: x(i), y: y(value)))
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        self.runs = runs
        if let band {
            let top = y(band.upperBound), bottom = y(band.lowerBound)
            bandRect = CGRect(x: 0, y: top, width: size.width, height: max(bottom - top, 0))
        } else {
            bandRect = nil
        }
    }

    /// `v`'s y in a box `height` high: the domain's top at 2, its bottom at `height` − 2; a domain of one value (a flat series
    /// without a band) at mid height.
    static func y(_ v: Double, domain: ClosedRange<Double>?, height: CGFloat) -> CGFloat {
        guard let domain, domain.upperBound > domain.lowerBound else { return height / 2 }
        let inset = TrendLine.inset
        let t = (v - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
        return inset + (height - 2 * inset) * CGFloat(1 - t)
    }
}

// MARK: previews

private struct TrendLinePreview: View {
    /// 30 days around 62 with a gap of three days, the last day `last`.
    private func series(last: Double, gap: Bool = true) -> [Double?] {
        (0..<30).map { i -> Double? in
            if gap, (12...14).contains(i) { return nil }
            if i == 29 { return last }
            return 62 + 6 * sin(Double(i) / 3)
        }
    }

    private func card(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title).font(.ryft(.label)).foregroundStyle(Theme.textSecondary)
            content()
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    var body: some View {
        VStack(spacing: 12) {
            card("Readiness · ending above (ink, 6 % band)") {
                TrendLine(values: series(last: 74), band: 56...68, color: Theme.textPrimary, bandOpacity: 0.06,
                          accessibilityLabel: Text(verbatim: "Readiness over 30 days"))
            }
            card("HRV · within, broken") {
                TrendLine(values: series(last: 63), band: 56...68, color: Theme.recovery,
                          accessibilityLabel: Text(verbatim: "HRV over 30 days"))
            }
            card("Sleep · below") {
                TrendLine(values: series(last: 50, gap: false), band: 56...68, color: Theme.metricSleep,
                          accessibilityLabel: Text(verbatim: "Sleep over 30 days"))
            }
            card("Strain · no band, a lone point") {
                TrendLine(values: [nil, nil, 9, nil, 11, 12, 10, nil, 14], color: Theme.metricStrain,
                          accessibilityLabel: Text(verbatim: "Strain over 9 days"), spokenLatest: Text(verbatim: "14"))
            }
            card("Pending") {
                TrendLine(values: [], color: Theme.recovery, isPending: true, accessibilityLabel: Text(verbatim: "HRV over 30 days"))
            }
        }
    }
}

#Preview("TrendLine", traits: .sizeThatFitsLayout) {
    DarkPreview { TrendLinePreview() }
}

#Preview("TrendLine · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { TrendLinePreview() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
