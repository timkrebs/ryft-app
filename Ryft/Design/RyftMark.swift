// The RYFT "orbit" mark: a thin ring with two small dots sitting on it (upper
// right, lower left), a small inner orbit and a solid centre dot. Pure vector,
// filled with the current foreground style, so it scales to any size and takes
// any colour.
//
// This file only depends on SwiftUI so scripts/render-icon.swift can compile it
// for macOS and render the app icon from the exact same geometry.
import SwiftUI

struct RyftMarkShape: Shape {
    /// Draw the small inner orbit around the centre dot (as on the brand board).
    var showsInnerOrbit = true

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let stroke = side * 0.042
        let ringR = side * 0.43
        let dotR = side * 0.064
        let centreR = side * 0.07
        let innerR = side * 0.17
        // Angles in degrees, 0 = 3 o'clock, clockwise (y points down).
        let dots: [Double] = [-52, 128]
        // Leave a little air between ring and dot so the dot reads as "orbiting".
        let gap = asin(min(1, (dotR + stroke * 1.1) / ringR)) * 180 / .pi

        var p = Path()
        let style = StrokeStyle(lineWidth: stroke, lineCap: .round)

        // Outer ring as two arcs, broken where the dots sit.
        for (i, a) in dots.enumerated() {
            let next = dots[(i + 1) % dots.count] + (i == dots.count - 1 ? 360 : 0)
            var arc = Path()
            arc.addArc(center: c, radius: ringR,
                       startAngle: .degrees(a + gap), endAngle: .degrees(next - gap),
                       clockwise: false)
            p.addPath(arc.strokedPath(style))
        }
        for a in dots {
            let r = a * .pi / 180
            let pt = CGPoint(x: c.x + ringR * cos(r), y: c.y + ringR * sin(r))
            p.addEllipse(in: CGRect(x: pt.x - dotR, y: pt.y - dotR, width: dotR * 2, height: dotR * 2))
        }
        if showsInnerOrbit {
            var inner = Path()
            inner.addEllipse(in: CGRect(x: c.x - innerR, y: c.y - innerR, width: innerR * 2, height: innerR * 2))
            p.addPath(inner.strokedPath(StrokeStyle(lineWidth: stroke)))
        }
        p.addEllipse(in: CGRect(x: c.x - centreR, y: c.y - centreR, width: centreR * 2, height: centreR * 2))
        return p
    }
}

/// The mark as a view. Colour comes from `.foregroundStyle`, size from `.frame`.
struct RyftMark: View {
    var showsInnerOrbit = true

    var body: some View {
        RyftMarkShape(showsInnerOrbit: showsInnerOrbit)
            .fill(.foreground)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

#if os(iOS)
#Preview("Mark", traits: .sizeThatFitsLayout) {
    HStack(spacing: 24) {
        RyftMark().frame(width: 120)
        RyftMark().frame(width: 48)
        RyftMark().frame(width: 18)
    }
    .foregroundStyle(Theme.textPrimary)
    .padding(32)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}

#Preview("Mark · light", traits: .sizeThatFitsLayout) {
    HStack(spacing: 24) {
        RyftMark().frame(width: 120)
        RyftMark().frame(width: 48).foregroundStyle(Theme.accent)
        RyftMark().frame(width: 18)
    }
    .foregroundStyle(Theme.textPrimary)
    .padding(32)
    .background(Theme.background)
    .preferredColorScheme(.light)
}
#endif
