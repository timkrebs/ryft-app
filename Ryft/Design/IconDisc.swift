// The icon disc (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-1.4): a thin ink glyph in a faint ring, where the
// app had teal medallions. A graphic, not a button.
import SwiftUI

/// A 36 pt disc (`.regular`; `.large` 40 for a row's leading icon): no fill, a 1 pt ring in `textPrimary` at 16 % (the
/// circle button's), the glyph `textPrimary` at 16 pt `.light` (about the board's 1.2 pt stroke). It does not scale with
/// Dynamic Type. Hidden from VoiceOver unless the caller passes a label; then it is one image element with that label.
///
/// `.filled` (PR 6 B §6.1, T6B.0): the disc filled with `textPrimary` and the glyph in `background`, no ring: the one row
/// that is "this one" (Plans' enrolled plan, with `checkmark`). The row says so in words too; the fill is never the only cue.
struct IconDisc: View {
    enum Size {
        case regular, large

        var diameter: CGFloat {
            switch self {
            case .regular: return IconDisc.regularDiameter
            case .large: return IconDisc.largeDiameter
            }
        }
    }

    /// The outline disc, or the filled one that marks the chosen row.
    enum Style: Equatable, Sendable { case outline, filled }

    /// `nonisolated`: `Size` reads them (P2-D9).
    nonisolated static let regularDiameter: CGFloat = 36, largeDiameter: CGFloat = 40
    /// The ring: `CircleButton.borderOpacity`, 1 pt.
    static let ringOpacity = CircleButton.borderOpacity, ringWidth = Theme.Metrics.hairline
    static let glyphSize: CGFloat = 16

    private let systemImage: String
    private let size: Size
    private let style: Style
    private let accessibilityLabel: Text?

    init(systemImage: String, size: Size = .regular, style: Style = .outline, accessibilityLabel: Text? = nil) {
        self.systemImage = systemImage
        self.size = size
        self.style = style
        self.accessibilityLabel = accessibilityLabel
    }

    /// The glyph's ink: `textPrimary`, or `background` on the filled disc (17.35:1 either way).
    static func glyphInk(_ style: Style) -> Color { style == .filled ? Theme.background : Theme.textPrimary }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: Self.glyphSize, weight: .light))
            .foregroundStyle(Self.glyphInk(style))
            .frame(width: size.diameter, height: size.diameter)
            .background {
                if style == .filled { Circle().fill(Theme.textPrimary) }
            }
            .overlay {
                if style == .outline {
                    Circle().strokeBorder(Theme.textPrimary.opacity(Self.ringOpacity), lineWidth: Self.ringWidth)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel ?? Text(verbatim: ""))
            .accessibilityAddTraits(.isImage)
            .accessibilityHidden(accessibilityLabel == nil)
    }
}

#Preview("IconDisc", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ForEach(["figure.run", "dumbbell", "bed.double", "heart", "bell", "applewatch"], id: \.self) {
                    IconDisc(systemImage: $0)
                }
            }
            HStack(spacing: 12) {
                ForEach(["figure.run", "dumbbell", "bed.double", "heart", "bell", "applewatch"], id: \.self) {
                    IconDisc(systemImage: $0, size: .large)
                }
            }
            HStack(spacing: 12) {
                IconDisc(systemImage: "checkmark", style: .filled)
                IconDisc(systemImage: "checkmark", size: .large, style: .filled)
            }
            // A row's leading icon on `surface`.
            HStack(spacing: 12) {
                IconDisc(systemImage: "figure.run", size: .large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Morning run").font(.ryft(.body)).foregroundStyle(Theme.textPrimary)
                    Text(verbatim: "07:10 · 42 min · 7.8 km").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.neutralTileRadius, style: .continuous))
        }
    }
}

#Preview("IconDisc · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        HStack(spacing: 12) {
            IconDisc(systemImage: "figure.run")
            IconDisc(systemImage: "figure.run", size: .large)
            Text(verbatim: "The disc does not scale").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
