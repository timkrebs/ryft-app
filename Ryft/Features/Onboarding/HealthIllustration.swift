import SwiftUI

/// "Connect Apple Health": a heart, and the pulse line that RYFT reads from it
/// drawing itself in, a 2 s ease-out loop. It says what happens next (Health data
/// flowing in) rather than decorating. Static and complete under Reduce Motion.
struct HealthIllustration: View {
    var size: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.10))
            HeartShape()
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                .frame(width: size * 0.56, height: size * 0.5)
                .offset(y: -size * 0.04)
            if reduceMotion {
                PulseShape(progress: 1)
                    .stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.7, height: size * 0.22)
            } else {
                TimelineView(.animation) { context in
                    PulseShape(progress: Self.progress(at: context.date))
                        .stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: size * 0.7, height: size * 0.22)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// 0 → 1 over 1.6 s with ease-out, then 0.4 s held drawn: one 2 s loop.
    static func progress(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2)
        let x = min(t / 1.6, 1)
        return 1 - pow(1 - x, 3)
    }
}

/// An ECG-like beat across the width, drawn up to `progress`.
private struct PulseShape: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, mid = rect.midY
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: mid))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.30, y: mid))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.38, y: mid - h * 0.30))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.46, y: mid + h * 0.50))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.54, y: mid - h * 0.50))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.62, y: mid + h * 0.20))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.68, y: mid))
        p.addLine(to: CGPoint(x: rect.maxX, y: mid))
        return p.trimmedPath(from: 0, to: progress)
    }
}

private struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.32),
                   control1: CGPoint(x: rect.minX + w * 0.30, y: rect.maxY - h * 0.22),
                   control2: CGPoint(x: rect.minX, y: rect.minY + h * 0.62))
        p.addArc(center: CGPoint(x: rect.minX + w * 0.25, y: rect.minY + h * 0.30), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: rect.minX + w * 0.75, y: rect.minY + h * 0.30), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                   control1: CGPoint(x: rect.maxX, y: rect.minY + h * 0.62),
                   control2: CGPoint(x: rect.maxX - w * 0.30, y: rect.maxY - h * 0.22))
        return p
    }
}

#Preview("Health illustration", traits: .sizeThatFitsLayout) {
    SchemePair {
        HStack(spacing: 24) {
            HealthIllustration()
            HealthIllustration(size: 64)
        }
    }
}
