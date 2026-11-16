// The one glow tile per screen section (Nocturne, docs/work/2026-11-16-nocturne/design.md §P2-3, brief §1 "Glow"): the
// metric colour under a radial `background` overlay, so the tile's edge glows in the legend's colour and its text sits
// in the dark core. Under Reduce Transparency it is flat `surface` with a 2 pt border in the metric colour.
import SwiftUI

/// The glow tile's measurements. A separate, non-generic type: `GlowTile` is generic and cannot hold static stored
/// properties.
enum GlowTileSpec {
    enum Radius {
        /// 24: Today's 2-up tiles. `hero` 28: the Sleep and Strain hero tiles.
        case tile, hero

        var points: CGFloat {
            switch self {
            case .tile: return Theme.Metrics.glowTileRadius
            case .hero: return Theme.Metrics.heroTileRadius
            }
        }
    }

    /// The overlay's `background` opacity at each radius fraction (0 the centre, 1 the ellipse; brief §2).
    static let stopOpacities: [(location: Double, opacity: Double)] = [(0, 0.97), (0.34, 0.92), (0.68, 0.55), (1, 0.10)]
    static let stops: [Gradient.Stop] = stopOpacities.map {
        Gradient.Stop(color: Theme.background.opacity($0.opacity), location: CGFloat($0.location))
    }
    /// The CSS ellipse `90% 110% at 50% 55%`: radii as fractions of the tile's width and height, the centre's y as a
    /// fraction of its height. Fixed at the dark end of the boards' ranges (design.md P2-D1).
    static let ellipse = (rx: 0.90, ry: 1.10, cy: 0.55)
    static let padding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    static let twoUpMinHeight: CGFloat = 124, heroMinHeight: CGFloat = 172
    /// Labels in a glow tile: `textPrimary` at 78 %. The flat variant's border width.
    static let labelOpacity = 0.78, flatBorder: CGFloat = 2

    /// The overlay's opacity at radius fraction `t`: linear between the stops, 0.97 at and before the centre, 0.10 on and
    /// beyond the ellipse.
    static func overlayOpacity(atRadiusFraction t: Double) -> Double {
        guard let first = stopOpacities.first, let last = stopOpacities.last else { return 0 }
        guard t > first.location else { return first.opacity }
        for (a, b) in zip(stopOpacities, stopOpacities.dropFirst()) where t <= b.location {
            return a.opacity + (b.opacity - a.opacity) * (t - a.location) / (b.location - a.location)
        }
        return last.opacity
    }

    /// The glow label's opacity at a text size: 78 % up to xxxLarge, full `textPrimary` from AX1. A tile grows tall at
    /// accessibility sizes and a label can end up in an outer corner, where 78 % can fall under 4.5:1 (design.md
    /// §P2-3, "Known limit").
    static func labelOpacity(for typeSize: DynamicTypeSize) -> Double {
        typeSize.isAccessibilitySize ? 1 : labelOpacity
    }
}

/// A tile filled with `metric` under the dark radial core, content top-leading inside 14/16 pt padding, `textPrimary`
/// by default. Content-sized with an optional `minHeight` (it grows with Dynamic Type; radius and padding are fixed). The
/// colour is decoration: the tile adds no accessibility element and no label.
struct GlowTile<Content: View>: View {
    private let metric: Color
    private let radius: GlowTileSpec.Radius
    private let minHeight: CGFloat?
    private let forcedReduceTransparency: Bool?
    private let content: Content

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    /// - Parameters:
    ///   - metric: the legend colour (`Theme.recovery`, `metricSleep`, `metricStrain`).
    ///   - minHeight: `GlowTileSpec.twoUpMinHeight` (124) or `heroMinHeight` (172); `nil` is content-sized.
    ///   - reduceTransparency: previews and tests; `nil` follows the system.
    init(_ metric: Color, radius: GlowTileSpec.Radius = .tile, minHeight: CGFloat? = nil,
         reduceTransparency: Bool? = nil, @ViewBuilder content: () -> Content) {
        self.metric = metric
        self.radius = radius
        self.minHeight = minHeight
        self.forcedReduceTransparency = reduceTransparency
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius.points, style: .continuous)
        content
            .foregroundStyle(Theme.textPrimary)
            .padding(GlowTileSpec.padding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background {
                if forcedReduceTransparency ?? systemReduceTransparency {
                    shape.fill(Theme.surface)
                        .overlay { shape.strokeBorder(metric, lineWidth: GlowTileSpec.flatBorder) }
                } else {
                    shape.fill(metric)
                        .overlay { GlowOverlay() }
                }
            }
            .clipShape(shape)
            .accessibilityElement(children: .contain)
    }
}

/// `radial-gradient(ellipse 90% 110% at 50% 55%, …)`: the unit circle scaled to the ellipse, so the radii are exact.
private struct GlowOverlay: View {
    var body: some View {
        Canvas { context, size in
            let e = GlowTileSpec.ellipse
            context.translateBy(x: size.width * 0.5, y: size.height * e.cy)
            context.scaleBy(x: size.width * e.rx, y: size.height * e.ry)
            // Covers the tile in unit space.
            context.fill(Path(CGRect(x: -4, y: -4, width: 8, height: 8)),
                         with: .radialGradient(Gradient(stops: GlowTileSpec.stops), center: .zero,
                                               startRadius: 0, endRadius: 1))
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// A label in a glow tile: `Font.ryft(.label)` (13 pt) in `textPrimary` at 78 % (`GlowTileSpec.labelOpacity`) at the
    /// default sizes. From AX1 up (`dynamicTypeSize.isAccessibilitySize`) it is full `textPrimary`: the tile grows tall
    /// there and a 78 % label in an outer corner can fall under 4.5:1 (`GlowTileSpec.labelOpacity(for:)`).
    func ryftGlowLabelStyle() -> some View {
        modifier(GlowLabelStyle())
    }
}

private struct GlowLabelStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .font(.ryft(.label))
            .foregroundStyle(Theme.textPrimary.opacity(GlowTileSpec.labelOpacity(for: typeSize)))
    }
}

#Preview("GlowTile", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                GlowTile(Theme.recovery, minHeight: GlowTileSpec.twoUpMinHeight) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery").ryftGlowLabelStyle()
                        Text(verbatim: "82").font(.ryft(.metric))
                    }
                }
                GlowTile(Theme.recovery, minHeight: GlowTileSpec.twoUpMinHeight) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HRV").ryftGlowLabelStyle()
                        Text(verbatim: "58").font(.ryft(.metric))
                    }
                }
            }
            GlowTile(Theme.metricSleep, radius: .hero, minHeight: GlowTileSpec.heroMinHeight) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Time asleep").ryftGlowLabelStyle()
                    DotNumeral("7:48", glyphGap: DotNumeral.glyphGapDetail,
                               accessibilityLabel: Text("7 hours 48 minutes asleep"))
                }
            }
            GlowTile(Theme.metricStrain, radius: .hero, minHeight: GlowTileSpec.heroMinHeight) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Strain").ryftGlowLabelStyle()
                    DotNumeral("12.4", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("Strain 12.4 of 21"))
                }
            }
        }
    }
}

#Preview("GlowTile · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            GlowTile(Theme.recovery, minHeight: GlowTileSpec.twoUpMinHeight) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recovery").ryftGlowLabelStyle()
                    Text(verbatim: "82").font(.ryft(.metric))
                }
            }
            GlowTile(Theme.metricSleep, radius: .hero, minHeight: GlowTileSpec.heroMinHeight) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Time asleep").ryftGlowLabelStyle()
                    DotNumeral("7:48", glyphGap: DotNumeral.glyphGapDetail,
                               accessibilityLabel: Text("7 hours 48 minutes asleep"))
                }
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("GlowTile · Reduce Transparency", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                GlowTile(Theme.recovery, minHeight: GlowTileSpec.twoUpMinHeight, reduceTransparency: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery").ryftGlowLabelStyle()
                        Text(verbatim: "82").font(.ryft(.metric))
                    }
                }
                GlowTile(Theme.metricSleep, minHeight: GlowTileSpec.twoUpMinHeight, reduceTransparency: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sleep").ryftGlowLabelStyle()
                        Text(verbatim: "7:48").font(.ryft(.metric))
                    }
                }
            }
            GlowTile(Theme.metricStrain, radius: .hero, minHeight: GlowTileSpec.heroMinHeight, reduceTransparency: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Strain").ryftGlowLabelStyle()
                    DotNumeral("12.4", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("Strain 12.4 of 21"))
                }
            }
        }
    }
}
