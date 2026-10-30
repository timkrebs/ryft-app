// The app icon's tile, colours and mark scale, shared by scripts/render-icon.swift (the PNGs
// in the asset catalog) and scripts/mark-svg.swift (design/ryft-app-icon-{light,dark}.svg),
// so the two can never drift apart. Both are compiled together with this file and
// Ryft/Design/RyftMark.swift (see the Makefile: `make icon`, `make mark-svg`).
import Foundation

enum IconSpec {
    /// The App Store icon tile, px.
    static let tile = 1024.0

    /// How large the mark sits on the tile: the outer ring's span (outer edge to outer edge)
    /// divided by the tile width. 0.915 is 95 % of the 2026-10-28 reference's 0.963
    /// (../docs/briefs/assets/2026-10-28-new-app-icon-reference.jpg): on the home screen the
    /// reference's ring looked stretched to the tile's edge (the user, 2026-10-30, on device).
    /// `make icon` also renders 0.963 and 0.80 (closer to Apple's icon grid) into
    /// build/icon-compare/ to compare.
    static let defaultRingSpan = 0.915

    /// The outer ring's span in RyftMark's 100-box: its stroke-centreline diameter plus one
    /// stroke (half a stroke on either side), 2 x 44 + 3.16 = 91.16 with the 2026-10-28 numbers.
    /// Nominal stroke: the optical-size rule only thickens marks smaller than 39.6 pt.
    static var outerSpanInBox: Double {
        2 * RyftMarkGeometry.outer.radius + RyftMarkGeometry.stroke
    }

    /// Side of the mark's frame (its 100-box) in px for a ring span:
    /// tile x ringSpan x 100 / 91.16, i.e. 1027.82 px at 0.915 on a 1024 tile.
    static func markFrame(ringSpan: Double, tile: Double = tile) -> Double {
        tile * ringSpan * RyftMarkGeometry.box / outerSpanInBox
    }

    /// The smallest distance (px) from any dot's edge to the tile's edge; negative = cut off.
    /// The dots are what reaches farthest out: the outer ring's dot at 65 deg sits on r 44 with
    /// r 6, so its edge touches the 100-box (50 from the centre) while the ring stops at 45.58.
    static func dotMargin(ringSpan: Double, tile: Double = tile) -> Double {
        let g = RyftMarkGeometry.self
        let frame = markFrame(ringSpan: ringSpan, tile: tile)
        let u = frame / g.box
        let m = g.metrics(forSide: frame)
        var margin = Double.infinity
        for ring in [g.outer, g.middle] {
            for d in ring.dots {
                let p = g.point(radius: ring.radius, degrees: d)
                let x = tile / 2 + (p.x - g.centre) * u
                let y = tile / 2 + (p.y - g.centre) * u
                let r = m.dotRadius * u
                margin = min(margin, x - r, y - r, tile - x - r, tile - y - r)
            }
        }
        return margin
    }

    /// The token colours (Ryft/Assets.xcassets Mist / Graphite, Design/Theme.swift).
    static let mistHex = "E8E7E3"
    static let graphiteHex = "0B0F0E"

    /// sRGB components 0...1 of a six-digit hex colour.
    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let v = UInt32(hex, radix: 16) ?? 0
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}
