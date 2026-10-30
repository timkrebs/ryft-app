// The app icon's tile, colours and mark scale, shared by scripts/render-icon.swift (the PNGs
// in the asset catalog) and scripts/mark-svg.swift (design/ryft-app-icon-{light,dark}.svg),
// so the two can never drift apart. Both are compiled together with this file and
// Ryft/Design/RyftMark.swift (see the Makefile: `make icon`, `make mark-svg`).
import Foundation

enum IconSpec {
    /// The App Store icon tile, px.
    static let tile = 1024.0

    /// How large the mark sits on the tile: the outer ring's span (outer edge to outer edge)
    /// divided by the tile width. 0.869 is 95 % of the previous 0.915 (0.86925 rounded to three
    /// places; 0.915 was itself 95 % of the 2026-10-28 reference's 0.963, see
    /// ../docs/briefs/assets/2026-10-28-new-app-icon-reference.jpg). The user asked for the mark
    /// 5 % smaller on 2026-10-30, after the 0.915 one. `make icon` also renders 0.963, 0.915 and 0.80
    /// (closer to Apple's icon grid) into build/icon-compare/ to compare.
    static let defaultRingSpan = 0.869

    /// The outer ring's span in RyftMark's 100-box: its stroke-centreline diameter plus one
    /// stroke (half a stroke on either side), 2 x 44 + 3.16 = 91.16 with the 2026-10-28 numbers.
    /// Nominal stroke: the optical-size rule only thickens marks smaller than 39.6 pt.
    static var outerSpanInBox: Double {
        2 * RyftMarkGeometry.outer.radius + RyftMarkGeometry.stroke
    }

    /// Side of the mark's frame (its 100-box) in px for a ring span:
    /// tile x ringSpan x 100 / 91.16, i.e. 976.3 px at 0.869 on a 1024 tile.
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

    // MARK: Gauge colours

    /// The part colours of the Light and Dark icons, read from the asset catalog so they can't drift from the
    /// gauge (Shared/OrbitGaugePalette.swift names the same colour sets): Strain = MetricStrain, Sleep =
    /// MetricSleep, Recovery = Accent, Readiness = Accent (the "High" band). Light icon: the sets' light values;
    /// Dark icon: their dark values. Run from the repo root (the Makefile does).
    static let catalog = "Ryft/Assets.xcassets"

    /// A colour set's hex ("5B8DEF") for the light or the dark appearance, read from its Contents.json.
    static func catalogHex(_ name: String, dark: Bool) -> String {
        let url = URL(fileURLWithPath: "\(catalog)/\(name).colorset/Contents.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let colors = root["colors"] as? [[String: Any]]
        else { fatalError("icon-spec: cannot read \(url.path)") }
        let entry = colors.first { c in
            let appearances = c["appearances"] as? [[String: Any]]
            let isDark = appearances?.contains { ($0["value"] as? String) == "dark" } ?? false
            return isDark == dark
        } ?? colors[0]
        guard let comps = (entry["color"] as? [String: Any])?["components"] as? [String: String] else {
            fatalError("icon-spec: no components in \(url.path)")
        }
        func byte(_ key: String) -> String {
            let v = Int((comps[key] ?? "0").dropFirst(2), radix: 16) ?? 0
            return String(format: "%02X", v)
        }
        return byte("red") + byte("green") + byte("blue")
    }

    /// The hex of a mark part on the Light (`dark: false`) or Dark icon.
    static func partHex(_ part: RyftMarkGeometry.Part, dark: Bool) -> String {
        switch part {
        case .strainRing, .strainDot: return catalogHex("MetricStrain", dark: dark)
        case .sleepArc, .sleepDot: return catalogHex("MetricSleep", dark: dark)
        case .recoveryArc, .recoveryDot, .readinessRing: return catalogHex("Accent", dark: dark)
        }
    }

    /// WCAG contrast ratio of two hex colours.
    static func contrast(_ a: String, _ b: String) -> Double {
        func lum(_ hex: String) -> Double {
            let c = rgb(hex)
            func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
        }
        let (x, y) = (lum(a), lum(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Every distinct part colour must reach 3:1 on its tile (graphics, WCAG 1.4.11).
    static let minContrast = 3.0
}
