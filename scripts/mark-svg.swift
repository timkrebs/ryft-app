// Writes (or checks) the RYFT mark's SVGs from RyftMarkGeometry, the same numbers the app
// draws. Compiled together with scripts/icon-spec.swift and Ryft/Design/RyftMark.swift;
// `make mark-svg` writes, `make check-mark-svg` (part of `make lint`) checks:
//
//   .build/mark-svg [--check] [dir]      # default dir: design
//
// Files, all the nominal mark (no optical-size bump), same arcs and dots:
//   ryft-mark.svg               viewBox 0 0 100 100, currentColor
//   ryft-app-icon-light.svg     1024 x 1024, the mark in the gauge's light colours on a full-bleed Mist square
//   ryft-app-icon-dark.svg      1024 x 1024, its dark colours on a full-bleed Graphite square
// (colours per part from the asset catalog via IconSpec.partHex; ryft-mark.svg stays currentColor)
// The icons place the 100-box with one transform, scaled so the outer ring spans
// IconSpec.defaultRingSpan of the tile, exactly like the PNGs from scripts/render-icon.swift.
//
// --check exits 1 if any file on disk differs from what the Swift geometry produces.
import Foundation

@main
struct MarkSVG {
    static func num(_ v: Double, digits: Int = 3) -> String {
        var s = String(format: "%.\(digits)f", v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    /// The mark's two groups (stroked rings, filled dots) in 100-box units, indented by `pad`.
    static func markGroups(stroke: String, fill: String, pad: String) -> String {
        let g = RyftMarkGeometry.self
        let m = g.metrics(forSide: 1024)  // nominal: the optical rule does not kick in
        var arcs: [String] = []
        for ring in [g.outer, g.middle] {
            for a in g.arcs(of: ring, metrics: m) {
                let s = g.point(radius: ring.radius, degrees: a.start)
                let e = g.point(radius: ring.radius, degrees: a.end)
                let large = (a.end - a.start) > 180 ? 1 : 0
                let r = num(ring.radius)
                arcs.append("\(pad)  <path d=\"M\(num(s.x)) \(num(s.y))A\(r) \(r) 0 \(large) 1 \(num(e.x)) \(num(e.y))\"/>")
            }
        }
        arcs.append("\(pad)  <circle cx=\"\(num(g.centre))\" cy=\"\(num(g.centre))\" r=\"\(num(g.innerRadius))\"/>")
        var dots: [String] = []
        for ring in [g.outer, g.middle] {
            for d in ring.dots {
                let p = g.point(radius: ring.radius, degrees: d)
                dots.append("\(pad)  <circle cx=\"\(num(p.x))\" cy=\"\(num(p.y))\" r=\"\(num(m.dotRadius))\"/>")
            }
        }
        return """
        \(pad)<g fill="none" stroke="\(stroke)" stroke-width="\(num(m.stroke))" stroke-linecap="round">
        \(arcs.joined(separator: "\n"))
        \(pad)</g>
        \(pad)<g fill="\(fill)">
        \(dots.joined(separator: "\n"))
        \(pad)</g>
        """
    }

    /// The mark with one colour per part (the gauge's colours), same arcs and dots as `markGroups`.
    static func colouredGroups(dark: Bool, pad: String) -> String {
        let g = RyftMarkGeometry.self
        let m = g.metrics(forSide: 1024)
        func arc(_ ring: RyftMarkGeometry.Ring, _ a: (start: Double, end: Double), _ part: RyftMarkGeometry.Part) -> String {
            let s = g.point(radius: ring.radius, degrees: a.start)
            let e = g.point(radius: ring.radius, degrees: a.end)
            let large = (a.end - a.start) > 180 ? 1 : 0
            let r = num(ring.radius)
            return "\(pad)  <path stroke=\"#\(IconSpec.partHex(part, dark: dark))\" d=\"M\(num(s.x)) \(num(s.y))A\(r) \(r) 0 \(large) 1 \(num(e.x)) \(num(e.y))\"/>"
        }
        func dot(_ ring: RyftMarkGeometry.Ring, _ d: Double, _ part: RyftMarkGeometry.Part) -> String {
            let p = g.point(radius: ring.radius, degrees: d)
            return "\(pad)  <circle fill=\"#\(IconSpec.partHex(part, dark: dark))\" cx=\"\(num(p.x))\" cy=\"\(num(p.y))\" r=\"\(num(m.dotRadius))\"/>"
        }
        let middleArcs = g.arcs(of: g.middle, metrics: m)
        var rings: [String] = []
        for a in g.arcs(of: g.outer, metrics: m) { rings.append(arc(g.outer, a, .strainRing)) }
        rings.append(arc(g.middle, middleArcs[0], .sleepArc))
        rings.append(arc(g.middle, middleArcs[1], .recoveryArc))
        rings.append("\(pad)  <circle stroke=\"#\(IconSpec.partHex(.readinessRing, dark: dark))\" cx=\"\(num(g.centre))\" cy=\"\(num(g.centre))\" r=\"\(num(g.innerRadius))\"/>")
        let dots = [dot(g.outer, g.outer.dots[0], .strainDot),
                    dot(g.middle, g.middle.dots[0], .sleepDot),
                    dot(g.middle, g.middle.dots[1], .recoveryDot)]
        return """
        \(pad)<!-- Strain: outer ring and dot. Sleep: inner orbit clockwise of the top. Recovery: inner orbit counter-clockwise. Readiness (High band): centre ring. -->
        \(pad)<g fill="none" stroke-width="\(num(m.stroke))" stroke-linecap="round">
        \(rings.joined(separator: "\n"))
        \(pad)</g>
        \(pad)<g>
        \(dots.joined(separator: "\n"))
        \(pad)</g>
        """
    }

    static func markSVG() -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100" role="img" aria-label="RYFT">
        \(markGroups(stroke: "currentColor", fill: "currentColor", pad: "  "))
        </svg>

        """
    }

    static func iconSVG(background: String, dark: Bool) -> String {
        let tile = IconSpec.tile
        let span = IconSpec.defaultRingSpan
        let frame = IconSpec.markFrame(ringSpan: span)
        let scale = frame / RyftMarkGeometry.box
        let offset = (tile - frame) / 2
        let t = num(tile)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(t) \(t)" width="\(t)" height="\(t)" role="img" aria-label="RYFT">
          <rect width="\(t)" height="\(t)" fill="#\(background)"/>
          <!-- outer ring spans \(num(span)) of the tile: the 100-box at \(num(frame, digits: 2)) px -->
          <g transform="translate(\(num(offset, digits: 5)) \(num(offset, digits: 5))) scale(\(num(scale, digits: 6)))">
        \(colouredGroups(dark: dark, pad: "    "))
          </g>
        </svg>

        """
    }

    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        let check = args.contains("--check")
        args.removeAll { $0 == "--check" }
        let dir = URL(fileURLWithPath: args.first ?? "design")
        let files = [
            ("ryft-mark.svg", markSVG()),
            ("ryft-app-icon-light.svg", iconSVG(background: IconSpec.mistHex, dark: false)),
            ("ryft-app-icon-dark.svg", iconSVG(background: IconSpec.graphiteHex, dark: true)),
        ]
        var stale = false
        for (name, out) in files {
            let url = dir.appendingPathComponent(name)
            if check {
                if (try? String(contentsOf: url, encoding: .utf8)) != out {
                    FileHandle.standardError.write(Data("\(url.path) is out of date; run make mark-svg\n".utf8))
                    stale = true
                }
                continue
            }
            do {
                try out.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                FileHandle.standardError.write(Data("cannot write \(url.path): \(error)\n".utf8))
                exit(1)
            }
        }
        if stale { exit(1) }
    }
}
