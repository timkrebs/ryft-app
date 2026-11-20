// The icon disc (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-1.4): a thin ink glyph in a faint ring, where the
// app had teal medallions. A graphic, not a button.
import SwiftUI

/// A 36 pt disc (`.regular`; `.large` 40 for a row's leading icon): no fill, a 1 pt ring in `textPrimary` at 16 % (the
/// circle button's), the glyph `textPrimary` at 16 pt `.light` (about the board's 1.2 pt stroke). It does not scale with
/// Dynamic Type. Hidden from VoiceOver unless the caller passes a label; then it is one image element with that label.
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

    /// `nonisolated`: `Size` reads them (P2-D9).
    nonisolated static let regularDiameter: CGFloat = 36, largeDiameter: CGFloat = 40
    /// The ring: `CircleButton.borderOpacity`, 1 pt.
    static let ringOpacity = CircleButton.borderOpacity, ringWidth = Theme.Metrics.hairline
    static let glyphSize: CGFloat = 16

    private let systemImage: String
    private let size: Size
    private let accessibilityLabel: Text?

    init(systemImage: String, size: Size = .regular, accessibilityLabel: Text? = nil) {
        self.systemImage = systemImage
        self.size = size
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: Self.glyphSize, weight: .light))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: size.diameter, height: size.diameter)
            .overlay {
                Circle().strokeBorder(Theme.textPrimary.opacity(Self.ringOpacity), lineWidth: Self.ringWidth)
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
