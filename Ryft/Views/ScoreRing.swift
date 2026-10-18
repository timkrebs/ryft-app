import SwiftUI

/// Whoop-style ring: 0..1 progress, colour by band.
struct ScoreRing: View {
    let value: Double?      // 0..1
    let label: String
    let display: String     // text in the middle, e.g. "67%" or "14.2"
    let color: Color
    var lineWidth: CGFloat = 12
    var size: CGFloat = 120

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(value ?? 0, 0), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: value)
                Text(display)
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(value == nil ? .secondary : .primary)
            }
            .frame(width: size, height: size)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
}

enum Bands {
    static func recovery(_ v: Int?) -> Color {
        guard let v else { return .gray }
        switch v {
        case 67...: return .green
        case 34...: return .yellow
        default: return .red
        }
    }

    static func strain(_ v: Double?) -> Color {
        guard let v else { return .gray }
        switch v {
        case 18...: return .purple
        case 14...: return .blue
        case 10...: return .teal
        default: return .mint
        }
    }

    static func sleep(_ v: Int?) -> Color {
        guard let v else { return .gray }
        return v >= 85 ? .green : v >= 70 ? .yellow : .red
    }
}

extension Int {
    var asHoursMinutes: String {
        "\(self / 60)h \(String(format: "%02d", self % 60))m"
    }
}
