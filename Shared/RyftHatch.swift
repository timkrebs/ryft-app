// The hatch as geometry: where its lines are, not what colour they get (ADR 0010). The caller fills it and clips it to
// the shape it textures.
import SwiftUI

/// Parallel 45 degree lines, bottom left to top right. `line` is their width and `pitch` the distance from one line to
/// the next, both measured across the lines, so ink covers `line / pitch` of the area. The first line starts at the
/// rect's origin, so a pattern in a fixed rect stays put while the shape clipping it grows.
struct RyftHatch: Shape {
    var line: CGFloat = 1
    var pitch: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard line > 0, pitch > 0, !rect.isEmpty else { return p }
        // Along x, a 45 degree line's width and pitch are longer by the square root of 2.
        let step = pitch * 2.0.squareRoot(), half = line * 2.0.squareRoot() / 2
        var x = rect.minX
        let end = rect.maxX + rect.height + half
        while x < end {
            p.move(to: CGPoint(x: x - half, y: rect.minY))
            p.addLine(to: CGPoint(x: x + half, y: rect.minY))
            p.addLine(to: CGPoint(x: x + half - rect.height, y: rect.maxY))
            p.addLine(to: CGPoint(x: x - half - rect.height, y: rect.maxY))
            p.closeSubpath()
            x += step
        }
        return p
    }
}
