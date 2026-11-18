// The night as a step line (Nocturne, docs/work/2026-11-16-nocturne/design.md §P4-2a): the body of Sleep's hypnogram
// glow tile. A 38 pt column of stage names, then the plot: four grid lines (Awake, REM, Light, Deep, top to bottom), the
// stage step line in 85 % ink, and each Deep span as a sleep-colour bar on the Deep line. Time runs linearly from the
// night's start to its end with no tick labels (the tile's header has the range). The tile (header, totals, the
// no-timeline and no-stages variants, VoiceOver) is the screen's.
import SwiftUI

/// The stage column and the plot. No strings inside: the caller passes the four stage names. Hidden from VoiceOver: the
/// tile is one element that says the night.
struct HypnogramPlot: View {
    /// The plot's rows, top to bottom.
    enum Level: Int, CaseIterable, Sendable {
        case awake, rem, light, deep

        /// `asleep` (stage unknown) plots on Light, as the Charts hypnogram does.
        nonisolated init(_ stage: SleepIntervalStage) {
            switch stage {
            case .awake: self = .awake
            case .rem: self = .rem
            case .light, .asleep: self = .light
            case .deep: self = .deep
            }
        }
    }

    nonisolated static let columnWidth: CGFloat = 38
    nonisolated static let plotHeight: CGFloat = 90
    /// The first and last grid lines sit this far inside the plot: Awake at 4, Deep at height − 4 (86 in 90).
    nonisolated static let gridInset: CGFloat = 4
    nonisolated static let gridLineWidth: CGFloat = 1, gridOpacity = 0.08
    nonisolated static let lineWidth: CGFloat = 1.4, lineOpacity = 0.85
    nonisolated static let deepBarHeight: CGFloat = 8, deepBarRadius: CGFloat = 4, deepBarMinWidth: CGFloat = 3
    /// A gap between two segments shorter than this joins them: under a minute is under a point at this scale (a night
    /// of eight hours across 280 pt), and sources round their samples' ends.
    nonisolated static let joinTolerance: TimeInterval = 60
    /// The stage name's line height at the default size (Satoshi 11); the plot is at least four of them high.
    nonisolated static let nameLineHeight: CGFloat = 15
    /// How far the first and last names reach past the plot: half a line less the grid's inset, 3.5 at the default size.
    /// At accessibility sizes the inset grows instead, so they never reach farther into the tile's spacing.
    nonisolated static let nameOverhang: CGFloat = 3.5

    /// The night on a 0…1 time axis.
    struct Model: Equatable, Sendable {
        /// One stage held from `from` to `to` (fractions of the night).
        struct Step: Equatable, Sendable {
            var level: Level
            var from: Double
            var to: Double
        }

        /// Runs of touching steps, oldest first: each is one path; a gap between segments starts a new run.
        var runs: [[Step]]
        /// The Deep spans (touching Deep steps merged), fractions of the night.
        var deepSpans: [ClosedRange<Double>]

        var isEmpty: Bool { runs.isEmpty }
    }

    private let segments: [SleepInterval]
    private let start: Date
    private let end: Date
    private let stageNames: [String]

    @ScaledMetric(relativeTo: .caption2) private var scaledNameLine = HypnogramPlot.nameLineHeight

    /// - Parameters:
    ///   - segments: `SleepDetail.segments`, in any order; clamped to the night.
    ///   - start, end: the night (`SleepDetail.start`, `end`); x is linear between them.
    ///   - stageNames: already localized, top to bottom: Awake, REM, Light, Deep.
    init(segments: [SleepInterval], start: Date, end: Date, stageNames: [String]) {
        self.segments = segments
        self.start = start
        self.end = end
        self.stageNames = stageNames
    }

    var body: some View {
        let height = Self.plotHeight(nameLineHeight: scaledNameLine)
        let inset = Self.gridInset(nameLineHeight: scaledNameLine)
        let model = Self.model(segments: segments, start: start, end: end)
        HStack(alignment: .top, spacing: 0) {
            stageColumn(height: height, inset: inset)
            Canvas { context, size in draw(model, in: &context, size: size, inset: inset) }
                .frame(height: height)
        }
        .accessibilityHidden(true)
    }

    /// The names, each centred on its grid line; as wide as the widest name, at least 38.
    private func stageColumn(height: CGFloat, inset: CGFloat) -> some View {
        StageColumnLayout(height: height, inset: inset) {
            ForEach(Array(stageNames.prefix(Level.allCases.count).enumerated()), id: \.offset) { _, name in
                Text(verbatim: name).lineLimit(1)
            }
        }
        .ryftGlowLabelStyle(.axis)
    }

    private func draw(_ model: Model, in context: inout GraphicsContext, size: CGSize, inset: CGFloat) {
        var grid = Path()
        for level in Level.allCases {
            let y = Self.gridY(level, height: size.height, inset: inset)
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(Theme.textPrimary.opacity(Self.gridOpacity)), lineWidth: Self.gridLineWidth)
        for rect in Self.deepBarRects(model, size: size, inset: inset) {
            context.fill(Path(roundedRect: rect, cornerRadius: Self.deepBarRadius, style: .continuous),
                         with: .color(Theme.metricSleep))
        }
        context.stroke(Self.stepPath(model, size: size, inset: inset), with: .color(Theme.textPrimary.opacity(Self.lineOpacity)),
                       style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round))
    }

    // MARK: layout (pure)

    /// The plot's height: 90, or four stage names' lines when they are taller (accessibility sizes).
    nonisolated static func plotHeight(nameLineHeight: CGFloat) -> CGFloat {
        max(plotHeight, 4 * nameLineHeight)
    }

    /// The grid's inset for a name line: 4 at the default size; half a line less `nameOverhang` when that is more (the
    /// accessibility sizes), so the names keep to the board's reach past the plot and clear each other.
    nonisolated static func gridInset(nameLineHeight: CGFloat) -> CGFloat {
        max(gridInset, nameLineHeight / 2 - nameOverhang)
    }

    /// A level's grid line: evenly from `inset` (Awake) to height − `inset` (Deep); 4, 31.33, 58.67, 86 in 90.
    nonisolated static func gridY(_ level: Level, height: CGFloat, inset: CGFloat = gridInset) -> CGFloat {
        inset + CGFloat(level.rawValue) * (height - 2 * inset) / CGFloat(Level.allCases.count - 1)
    }

    /// The segments on the night's 0…1 axis: sorted, clamped to `start`…`end`, empty ones dropped, an overlap starting
    /// where the step before ends. A gap longer than `joinTolerance` breaks the path. Empty without a night (`end` ≤
    /// `start`).
    nonisolated static func model(segments: [SleepInterval], start: Date, end: Date) -> Model {
        let night = end.timeIntervalSince(start)
        guard night > 0 else { return Model(runs: [], deepSpans: []) }
        func fraction(_ d: Date) -> Double { min(max(d.timeIntervalSince(start) / night, 0), 1) }
        var runs: [[Model.Step]] = [], run: [Model.Step] = []
        var lastEnd: Date?
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            var from = max(segment.start, start)
            let to = min(segment.end, end)
            if let lastEnd, from < lastEnd { from = lastEnd }
            guard to > from else { continue }
            if let lastEnd, from.timeIntervalSince(lastEnd) > joinTolerance, !run.isEmpty {
                runs.append(run)
                run = []
            }
            // A join within the tolerance starts where the step before ended, so the path has no sliver of a gap.
            let fromFraction = run.last.map { $0.to } ?? fraction(from)
            run.append(Model.Step(level: Level(segment.stage), from: fromFraction, to: fraction(to)))
            lastEnd = to
        }
        if !run.isEmpty { runs.append(run) }
        var deep: [ClosedRange<Double>] = []
        for step in runs.joined() where step.level == .deep {
            if let last = deep.last, abs(last.upperBound - step.from) < 1e-9 {
                deep[deep.count - 1] = last.lowerBound...step.to
            } else {
                deep.append(step.from...step.to)
            }
        }
        return Model(runs: runs, deepSpans: deep)
    }

    /// The step line: per run a horizontal stroke at each step's level and a vertical join at each change.
    nonisolated static func stepPath(_ model: Model, size: CGSize, inset: CGFloat = gridInset) -> Path {
        var path = Path()
        for run in model.runs {
            guard let first = run.first else { continue }
            path.move(to: CGPoint(x: first.from * size.width, y: gridY(first.level, height: size.height, inset: inset)))
            for step in run {
                let y = gridY(step.level, height: size.height, inset: inset)
                path.addLine(to: CGPoint(x: step.from * size.width, y: y))
                path.addLine(to: CGPoint(x: step.to * size.width, y: y))
            }
        }
        return path
    }

    /// The Deep bars: centred on the Deep line, `deepBarHeight` high, at least `deepBarMinWidth` wide (a short span grows
    /// about its middle, inside the plot).
    nonisolated static func deepBarRects(_ model: Model, size: CGSize, inset: CGFloat = gridInset) -> [CGRect] {
        let y = gridY(.deep, height: size.height, inset: inset) - deepBarHeight / 2
        return model.deepSpans.map { span in
            var x = span.lowerBound * size.width, width = (span.upperBound - span.lowerBound) * size.width
            if width < deepBarMinWidth {
                x = min(max(x + width / 2 - deepBarMinWidth / 2, 0), max(size.width - deepBarMinWidth, 0))
                width = deepBarMinWidth
            }
            return CGRect(x: x, y: y, width: width, height: deepBarHeight)
        }
    }
}

/// The stage names, top to bottom, each with its vertical middle on its level's grid line and its leading edge at the
/// column's: as wide as the widest (never truncated), at least `columnWidth`; as high as the plot. The first and last
/// names reach `nameOverhang` past the plot's top and bottom, into the tile's spacing; nothing clips them.
private struct StageColumnLayout: Layout {
    let height: CGFloat
    let inset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return CGSize(width: max(HypnogramPlot.columnWidth, widest), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            guard let level = HypnogramPlot.Level(rawValue: index) else { continue }
            let y = bounds.minY + HypnogramPlot.gridY(level, height: height, inset: inset)
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .leading, proposal: .unspecified)
        }
    }
}

// MARK: - previews

private enum HypnogramPreview {
    static let names = ["Awake", "REM", "Light", "Deep"]
    static let start = Date(timeIntervalSince1970: 1_794_869_400) // 22:50 UTC
    static let end = start.addingTimeInterval(490 * 60)          // 07:00 UTC

    /// The board's night as steps, in minutes from the start.
    static var segments: [SleepInterval] {
        let plan: [(SleepIntervalStage, Int)] = [
            (.light, 20), (.deep, 32), (.light, 24), (.rem, 12), (.light, 26), (.deep, 26), (.light, 22), (.awake, 11),
            (.rem, 18), (.light, 30), (.deep, 20), (.light, 26), (.rem, 24), (.light, 30), (.deep, 13), (.light, 24),
            (.awake, 11), (.rem, 26), (.light, 32), (.deep, 4), (.light, 34), (.rem, 25),
        ]
        var t = start, out: [SleepInterval] = []
        for (stage, minutes) in plan {
            let next = t.addingTimeInterval(Double(minutes) * 60)
            out.append(SleepInterval(stage: stage, start: t, end: next))
            t = next
        }
        return out
    }
}

#Preview("HypnogramPlot", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            GlowTile(Theme.metricSleep, kind: .hypnogram) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: "Hypnogram").ryftGlowLabelStyle()
                    HypnogramPlot(segments: HypnogramPreview.segments, start: HypnogramPreview.start,
                                  end: HypnogramPreview.end, stageNames: HypnogramPreview.names)
                }
            }
            // A gap in the night breaks the line; a 1-minute Deep span still draws a 3 pt bar.
            GlowTile(Theme.metricSleep, kind: .hypnogram) {
                HypnogramPlot(segments: Array(HypnogramPreview.segments.prefix(6)) + Array(HypnogramPreview.segments.suffix(8))
                              + [SleepInterval(stage: .deep, start: HypnogramPreview.end.addingTimeInterval(-120),
                                               end: HypnogramPreview.end.addingTimeInterval(-60))],
                              start: HypnogramPreview.start, end: HypnogramPreview.end, stageNames: HypnogramPreview.names)
            }
        }
    }
}

#Preview("HypnogramPlot · AX3", traits: .sizeThatFitsLayout) {
    // The column takes the widest name and the plot grows to four of its lines.
    DarkPreview {
        GlowTile(Theme.metricSleep, kind: .hypnogram) {
            HypnogramPlot(segments: HypnogramPreview.segments, start: HypnogramPreview.start, end: HypnogramPreview.end,
                          stageNames: HypnogramPreview.names)
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
