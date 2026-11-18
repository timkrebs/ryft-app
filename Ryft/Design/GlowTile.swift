// The one glow tile per screen section (Nocturne, docs/work/2026-11-16-nocturne/design.md §P2-3 and §P4-3, brief §1
// "Glow"): the metric colour under a radial `background` overlay, so the tile's edge glows in the legend's colour and
// its text sits in the dark core. Each kind has the board's own ellipse and stops: the glow is as bright as the board
// (user, 2026-11-16, superseding P2-D1). Under Reduce Transparency it is flat `surface` with a 2 pt border in the metric
// colour; so is an `.idea` tile taller than 420 pt (§P5-5.1, D5-20).
import SwiftUI

/// The glow tile's measurements. A separate, non-generic type: `GlowTile` is generic and cannot hold static stored
/// properties.
enum GlowTileSpec {
    /// The board's tiles (§P4-3). `twoUp`: Today's Recovery and Sleep, 169 × 124. `strain`: Today's strain tile, 350 × 96.
    /// `hypnogram`: Sleep's, 350 × 168. `panel`: PR 2's ellipse, for a large tile (Insights "An idea", PR 5), the 2-up's
    /// fallback when it is wide or tall, and the `init(_:radius:)` shim. `zones`: Strain's and the workout's zones tile, 350 × 176
    /// (§P5-3.3). `idea`: Insights' insight tile, 350 × 120, flat above 420 pt (§P5-5.1).
    enum Kind: CaseIterable, Sendable {
        case twoUp, strain, hypnogram, panel
        case zones, idea
    }

    /// The PR 2 radii, for the `init(_:radius:)` shim: `tile` 24, `hero` 28. New callers name a `Kind`.
    enum Radius {
        case tile, hero

        var points: CGFloat {
            switch self {
            case .tile: return Theme.Metrics.glowTileRadius
            case .hero: return Theme.Metrics.heroTileRadius
            }
        }
    }

    /// One stop of the overlay: `background` at `opacity`, at the radius fraction `location` (0 the centre, 1 the ellipse).
    struct Stop: Equatable, Sendable {
        let location: Double
        let opacity: Double
    }

    /// A kind's drawing: the CSS ellipse `rx × ry at 50 % cy` (radii as fractions of the tile's width and height, the
    /// centre's y as a fraction of its height), the overlay's stops, the corner radius and the minimum height.
    struct Shape: Equatable, Sendable {
        let rx: Double, ry: Double, cy: Double
        let stops: [Stop]
        let radius: CGFloat
        let minHeight: CGFloat

        /// The overlay's opacity at radius fraction `t`: linear between the stops, the first stop's at and before the
        /// centre, the last's on and beyond the ellipse.
        func overlayOpacity(atRadiusFraction t: Double) -> Double {
            guard let first = stops.first, let last = stops.last else { return 0 }
            guard t > first.location else { return first.opacity }
            for (a, b) in zip(stops, stops.dropFirst()) where t <= b.location {
                return a.opacity + (b.opacity - a.opacity) * (t - a.location) / (b.location - a.location)
            }
            return last.opacity
        }

        /// The radius fraction of the point (`x`, `y`) in a `size` tile: 0 at the ellipse's centre, 1 on the ellipse.
        func radiusFraction(x: Double, y: Double, in size: CGSize) -> Double {
            let w = Double(size.width), h = Double(size.height)
            guard w > 0, h > 0 else { return 0 }
            let dx = (x - 0.5 * w) / (rx * w), dy = (y - cy * h) / (ry * h)
            return (dx * dx + dy * dy).squareRoot()
        }

        /// The overlay's opacity at the point (`x`, `y`) in a `size` tile.
        func overlayOpacity(x: Double, y: Double, in size: CGSize) -> Double {
            overlayOpacity(atRadiusFraction: radiusFraction(x: x, y: y, in: size))
        }

        /// The same ellipse and stops with another corner radius and minimum height.
        fileprivate func with(radius: CGFloat, minHeight: CGFloat) -> Shape {
            Shape(rx: rx, ry: ry, cy: cy, stops: stops, radius: radius, minHeight: minHeight)
        }
    }

    /// The board's ellipses and stops per kind (§P4-3).
    static func shape(for kind: Kind) -> Shape {
        func stops(_ second: Double, _ third: Double) -> [Stop] {
            [Stop(location: 0, opacity: 0.97), Stop(location: second, opacity: 0.92),
             Stop(location: third, opacity: 0.55), Stop(location: 1, opacity: 0.10)]
        }
        switch kind {
        case .twoUp:
            return Shape(rx: 0.85, ry: 0.80, cy: 0.50, stops: stops(0.30, 0.65),
                         radius: Theme.Metrics.glowTileRadius, minHeight: 124)
        case .strain:
            return Shape(rx: 0.90, ry: 1.10, cy: 0.55, stops: stops(0.32, 0.66),
                         radius: Theme.Metrics.glowTileRadius, minHeight: 96)
        case .hypnogram:
            return Shape(rx: 0.90, ry: 0.95, cy: 0.55, stops: stops(0.34, 0.68),
                         radius: Theme.Metrics.heroTileRadius, minHeight: 168)
        case .panel:
            return Shape(rx: 0.90, ry: 1.10, cy: 0.55, stops: stops(0.34, 0.68),
                         radius: Theme.Metrics.heroTileRadius, minHeight: 172)
        case .zones:
            // The hypnogram's ellipse and stops (the board's zones tile), 176 high.
            return Shape(rx: 0.90, ry: 0.95, cy: 0.55, stops: stops(0.34, 0.68),
                         radius: Theme.Metrics.heroTileRadius, minHeight: zonesMinHeight)
        case .idea:
            return Shape(rx: 0.90, ry: 0.95, cy: 0.55, stops: stops(0.34, 0.68),
                         radius: Theme.Metrics.heroTileRadius, minHeight: ideaMinHeight)
        }
    }

    /// The shape a `kind` tile draws at `size`. A 2-up wider than `twoUpMaxSize.width` or taller than its height (the AX
    /// single column, 350 pt wide; a tile grown with its text) takes `panel`'s ellipse and stops and keeps its own radius
    /// and minimum height: the board's ellipse would put its corners under 4.5:1 there, even in full ink (350 × 124
    /// recovery: 4.41; D4-12).
    static func shape(for kind: Kind, size: CGSize) -> Shape {
        let own = shape(for: kind)
        guard kind == .twoUp, size.width > twoUpMaxSize.width || size.height > twoUpMaxSize.height else { return own }
        return shape(for: .panel).with(radius: own.radius, minHeight: own.minHeight)
    }

    /// The largest 2-up that keeps the board's ellipse.
    static let twoUpMaxSize = CGSize(width: 200, height: 160)

    /// Content padding: 14 top, 16 at the sides, 12 at the bottom on the board's kinds (their value rows, the compact ruler
    /// and the hypnogram's totals sit 12 above the bottom); the panel and the zones tile 14 below; the idea tile 16 / 18.
    static func padding(for kind: Kind) -> EdgeInsets {
        switch kind {
        case .idea: return EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        case .panel, .zones: return EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        case .twoUp, .strain, .hypnogram: return EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16)
        }
    }

    /// Whether a `kind` tile at `size` draws flat (`surface` and the 2 pt border, the Reduce Transparency look) whatever the
    /// setting: an `.idea` taller than `ideaFlatAbove`, where the glow's corners would put its full-ink text under 4.5:1
    /// (4.81 at 420, D5-20). The other kinds always glow.
    static func drawsFlat(_ kind: Kind, size: CGSize) -> Bool {
        kind == .idea && size.height > ideaFlatAbove
    }

    /// PR 2's padding, the panel's: the shim draws with it.
    static let padding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    /// The PR 2 minimum heights, for the shim's callers: 124 (the 2-up) and 172 (the panel).
    static let twoUpMinHeight: CGFloat = 124, heroMinHeight: CGFloat = 172
    /// A label outside the recovery tile: `textPrimary` at 78 %. The flat variant's border width.
    static let labelOpacity = 0.78, flatBorder: CGFloat = 2

    // MARK: T5.0-B

    /// The zones tile's and the idea tile's minimum heights (§P5-3.3, §P5-5.1).
    static let zonesMinHeight: CGFloat = 176, ideaMinHeight: CGFloat = 120
    /// The height above which an `.idea` tile is flat (`drawsFlat(_:size:)`).
    static let ideaFlatAbove: CGFloat = 420

    /// The glow label's opacity at a text size, without a tile's colour: 78 % up to xxxLarge, full `textPrimary` from
    /// AX1 (P2-D7). Outside a glow tile `ryftGlowLabelStyle()` falls back to it.
    static func labelOpacity(for typeSize: DynamicTypeSize) -> Double {
        typeSize.isAccessibilitySize ? 1 : labelOpacity
    }

    /// The ink of every word in a glow tile that is not its numeral (L23): full `textPrimary` in a recovery tile at
    /// every size (its corners are the lightest: a 78 % label there is 3.78:1), else 78 % below AX1 and full from AX1.
    /// `GlowTile` publishes it as `glowLabelOpacity`.
    static func labelOpacity(metric: Color, typeSize: DynamicTypeSize) -> Double {
        metric == Theme.recovery ? 1 : labelOpacity(for: typeSize)
    }
}

extension EnvironmentValues {
    /// The label ink inside a glow tile (`GlowTileSpec.labelOpacity(metric:typeSize:)`), set by `GlowTile` for its
    /// content; `nil` outside one. `ryftGlowLabelStyle()` and the compact ruler's labels read it.
    @Entry var glowLabelOpacity: Double?
}

/// A tile filled with `metric` under the dark radial core, content top-leading inside its padding, `textPrimary` by
/// default. Content-sized with a minimum height (it grows with Dynamic Type; radius and padding are fixed). The colour is
/// decoration: the tile adds no accessibility element and no label.
struct GlowTile<Content: View>: View {
    private let metric: Color
    private let kind: GlowTileSpec.Kind
    private let radius: CGFloat
    private let padding: EdgeInsets
    private let minHeight: CGFloat?
    private let forcedReduceTransparency: Bool?
    private let content: Content

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - metric: the legend colour (`Theme.recovery`, `metricSleep`, `metricStrain`).
    ///   - kind: the board's tile; it sets the ellipse, the stops, the radius, the padding and the minimum height.
    ///   - minHeight: `nil` is the kind's (124, 96, 168, 172, 176, 120).
    ///   - reduceTransparency: previews and tests; `nil` follows the system.
    init(_ metric: Color, kind: GlowTileSpec.Kind, minHeight: CGFloat? = nil,
         reduceTransparency: Bool? = nil, @ViewBuilder content: () -> Content) {
        let shape = GlowTileSpec.shape(for: kind)
        self.metric = metric
        self.kind = kind
        self.radius = shape.radius
        self.padding = GlowTileSpec.padding(for: kind)
        self.minHeight = minHeight ?? shape.minHeight
        self.forcedReduceTransparency = reduceTransparency
        self.content = content()
    }

    /// PR 2's initialiser, kept for the catalog and the component previews: the `panel` ellipse at the given radius
    /// (`tile` 24, `hero` 28), PR 2's padding, content-sized unless `minHeight` is given.
    init(_ metric: Color, radius: GlowTileSpec.Radius = .tile, minHeight: CGFloat? = nil,
         reduceTransparency: Bool? = nil, @ViewBuilder content: () -> Content) {
        self.metric = metric
        self.kind = .panel
        self.radius = radius.points
        self.padding = GlowTileSpec.padding
        self.minHeight = minHeight
        self.forcedReduceTransparency = reduceTransparency
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .foregroundStyle(Theme.textPrimary)
            .environment(\.glowLabelOpacity, GlowTileSpec.labelOpacity(metric: metric, typeSize: typeSize))
            .padding(padding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background {
                if forcedReduceTransparency ?? systemReduceTransparency {
                    flat(shape)
                } else if kind == .idea {
                    // Only the idea tile reads its size: it is flat above 420 pt.
                    GeometryReader { proxy in
                        if GlowTileSpec.drawsFlat(kind, size: proxy.size) {
                            flat(shape)
                        } else {
                            glow(shape)
                        }
                    }
                } else {
                    glow(shape)
                }
            }
            .clipShape(shape)
            .accessibilityElement(children: .contain)
    }

    private func flat(_ shape: RoundedRectangle) -> some View {
        shape.fill(Theme.surface)
            .overlay { shape.strokeBorder(metric, lineWidth: GlowTileSpec.flatBorder) }
    }

    private func glow(_ shape: RoundedRectangle) -> some View {
        shape.fill(metric)
            .overlay { GlowOverlay(kind: kind) }
    }
}

/// `radial-gradient(ellipse rx ry at 50% cy, …)`: the unit circle scaled to the kind's ellipse at the tile's size (the
/// 2-up's fallback is decided here, from the size the tile was given), so the radii are exact.
private struct GlowOverlay: View {
    let kind: GlowTileSpec.Kind

    var body: some View {
        Canvas { context, size in
            let shape = GlowTileSpec.shape(for: kind, size: size)
            let stops = shape.stops.map {
                Gradient.Stop(color: Theme.background.opacity($0.opacity), location: CGFloat($0.location))
            }
            context.translateBy(x: size.width * 0.5, y: size.height * shape.cy)
            context.scaleBy(x: size.width * shape.rx, y: size.height * shape.ry)
            // Covers the tile in unit space.
            context.fill(Path(CGRect(x: -4, y: -4, width: 8, height: 8)),
                         with: .radialGradient(Gradient(stops: stops), center: .zero, startRadius: 0, endRadius: 1))
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// A word in a glow tile that is not its numeral: `style` (13 pt `label` by default) in `textPrimary` at the tile's
    /// label opacity (`glowLabelOpacity`: full in a recovery tile, 78 % in the others below AX1, full from AX1). Outside a
    /// glow tile, 78 % below AX1 and full from AX1 (`GlowTileSpec.labelOpacity(for:)`).
    func ryftGlowLabelStyle(_ style: RyftTextStyle = .label) -> some View {
        modifier(GlowLabelStyle(style: style))
    }
}

private struct GlowLabelStyle: ViewModifier {
    let style: RyftTextStyle
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.glowLabelOpacity) private var tileOpacity

    func body(content: Content) -> some View {
        content
            .font(.ryft(style))
            .foregroundStyle(Theme.textPrimary.opacity(tileOpacity ?? GlowTileSpec.labelOpacity(for: typeSize)))
    }
}

// MARK: - previews

/// A label and a value, as the board's tiles carry them (the screens build their own rows).
private struct GlowPreviewText: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label).ryftGlowLabelStyle()
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value).font(.ryft(.numberLarge))
                Text(verbatim: "%").ryftGlowLabelStyle()
            }
        }
    }
}

#Preview("GlowTile · kinds", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                GlowTile(Theme.recovery, kind: .twoUp) { GlowPreviewText(label: "Recovery", value: "82") }
                GlowTile(Theme.metricSleep, kind: .twoUp) { GlowPreviewText(label: "Sleep", value: "7:48") }
            }
            GlowTile(Theme.metricStrain, kind: .strain) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "Strain").ryftGlowLabelStyle()
                    Spacer(minLength: 0)
                    Text(verbatim: "12.4").font(.ryftNumber(size: 30, weight: .light))
                    Text(verbatim: "of 21 · moderate").ryftGlowLabelStyle()
                }
            }
            GlowTile(Theme.metricSleep, kind: .hypnogram) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "Hypnogram").ryftGlowLabelStyle()
                    Spacer(minLength: 0)
                    Text(verbatim: "22:50 – 07:00").ryftGlowLabelStyle(.caption)
                }
            }
            GlowTile(Theme.recovery, kind: .panel) { GlowPreviewText(label: "An idea", value: "64") }
        }
    }
}

#Preview("GlowTile · 2-up fallback", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            // 350 wide (the AX single column): the panel's ellipse, not the board's.
            GlowTile(Theme.recovery, kind: .twoUp) { GlowPreviewText(label: "Recovery · 350 wide", value: "82") }
            GlowTile(Theme.recovery, kind: .twoUp) { GlowPreviewText(label: "Recovery · 169 wide", value: "82") }
                .frame(width: 169)
        }
    }
}

#Preview("GlowTile · kinds · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            GlowTile(Theme.recovery, kind: .twoUp) { GlowPreviewText(label: "Recovery", value: "82") }
            GlowTile(Theme.metricSleep, kind: .twoUp) { GlowPreviewText(label: "Sleep", value: "7:48") }
            GlowTile(Theme.metricStrain, kind: .strain) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Strain").ryftGlowLabelStyle()
                    Text(verbatim: "12.4").font(.ryftNumber(size: 30, weight: .light))
                    Text(verbatim: "of 21 · moderate").ryftGlowLabelStyle()
                }
            }
            GlowTile(Theme.metricSleep, kind: .hypnogram) {
                Text(verbatim: "Hypnogram").ryftGlowLabelStyle()
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("GlowTile · Reduce Transparency", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                GlowTile(Theme.recovery, kind: .twoUp, reduceTransparency: true) {
                    GlowPreviewText(label: "Recovery", value: "82")
                }
                GlowTile(Theme.metricSleep, kind: .twoUp, reduceTransparency: true) {
                    GlowPreviewText(label: "Sleep", value: "7:48")
                }
            }
            GlowTile(Theme.metricStrain, kind: .strain, reduceTransparency: true) {
                Text(verbatim: "Strain").ryftGlowLabelStyle()
            }
            GlowTile(Theme.metricSleep, kind: .hypnogram, reduceTransparency: true) {
                Text(verbatim: "Hypnogram").ryftGlowLabelStyle()
            }
        }
    }
}

#Preview("GlowTile · PR 2 shim", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            GlowTile(Theme.recovery, minHeight: GlowTileSpec.twoUpMinHeight) { GlowPreviewText(label: "Recovery", value: "82") }
            GlowTile(Theme.metricSleep, radius: .hero, minHeight: GlowTileSpec.heroMinHeight) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: "Time asleep").ryftGlowLabelStyle()
                    DotNumeral("7:48", glyphGap: DotNumeral.glyphGapDetail,
                               accessibilityLabel: Text(verbatim: "7 hours 48 minutes asleep"))
                }
            }
        }
    }
}

/// The zones tile's and the idea tile's text, as Strain and Insights carry it (the screens build their own).
private struct GlowPreviewIdea: View {
    let body_: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Theme.signal).frame(width: 6, height: 6)
                Text(verbatim: "Insight").font(.ryft(.label))
            }
            Text(verbatim: "Your HRV is up 12 % on last week").font(.ryftNumber(size: 17, weight: .light))
            Text(verbatim: body_).font(.ryft(.label)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("GlowTile · zones and idea", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            GlowTile(Theme.metricStrain, kind: .zones) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "Heart-rate zones").ryftGlowLabelStyle()
                    Spacer(minLength: 0)
                    Text(verbatim: "48 min").font(.ryft(.caption))
                }
            }
            GlowTile(Theme.recovery, kind: .idea) {
                GlowPreviewIdea(body_: "Three nights over 7 h in a row. Recovery follows.")
            }
            // 440 high: above 420 the idea tile is flat (surface and the 2 pt border), whatever the setting.
            GlowTile(Theme.recovery, kind: .idea, minHeight: 440) {
                GlowPreviewIdea(body_: "Taller than 420: drawn flat.")
            }
            GlowTile(Theme.metricStrain, kind: .zones, reduceTransparency: true) {
                Text(verbatim: "Heart-rate zones · Reduce Transparency").ryftGlowLabelStyle()
            }
        }
    }
}

#Preview("GlowTile · zones and idea · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            GlowTile(Theme.metricStrain, kind: .zones) {
                Text(verbatim: "Heart-rate zones").ryftGlowLabelStyle()
            }
            GlowTile(Theme.recovery, kind: .idea) {
                GlowPreviewIdea(body_: "Three nights over 7 h in a row. Recovery follows. A long body at AX3 grows the tile past 420, "
                                + "where it is drawn flat.")
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
