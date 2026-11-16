import SwiftUI

/// Small mark + "RYFT" wordmark, centred at the top of every screen.
struct RyftHeader: View {
    var markSize: CGFloat = 20

    var body: some View {
        HStack(spacing: markSize * 0.45) {
            RyftMark().frame(width: markSize, height: markSize)
            Wordmark(size: markSize * 0.85)
        }
        .foregroundStyle(Theme.textPrimary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "RYFT"))
        .accessibilityAddTraits(.isHeader)
    }
}

/// "RYFT" in Satoshi Light, tracked 0.32 em. The tracking is added after the last letter too, so the word is
/// pulled back by that much on the right and sits optically where its letters are.
struct Wordmark: View {
    /// The wordmark style's size: `RyftTextStyle.wordmark` is the source of truth.
    var size: CGFloat = RyftTextStyle.wordmark.size
    /// In em. Only the launch sets another one: it animates from 0.9 to `Wordmark.tracking` (design.md §P3-4).
    var tracking: CGFloat = Wordmark.tracking

    /// Tracking in em.
    static let tracking: CGFloat = 0.32

    var body: some View {
        Text(verbatim: "RYFT")
            .font(.ryftNumber(size: size, weight: .light))
            .tracking(size * tracking)
            .padding(.trailing, -size * tracking)
    }
}

/// The Nocturne header lock-up: the orbit mark, 10 pt of air, then the wordmark. At the default `markSize` of 26 pt
/// the wordmark is 15 pt; both scale with `markSize`. Not yet on the screens (PR 4 puts it in their headers).
struct WordmarkLockup: View {
    var markSize: CGFloat = 26

    var body: some View {
        HStack(spacing: markSize * 10 / 26) {
            RyftMark().frame(width: markSize, height: markSize)
            Wordmark(size: markSize * RyftTextStyle.wordmark.size / 26)
        }
        .foregroundStyle(Theme.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "RYFT"))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Logo lock-up with the tagline, for About and empty states.
struct BrandLockup: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                RyftMark().frame(width: 44, height: 44)
                Wordmark(size: 32)
            }
            Text("Your whole health.")
                .ryftLabelStyle()
        }
        .foregroundStyle(Theme.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("RYFT — Your whole health."))
    }
}

#Preview("Header", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 28) {
            RyftHeader()
            BrandLockup()
        }
    }
}

#Preview("Wordmark lock-up", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 28) {
            WordmarkLockup()
            WordmarkLockup(markSize: 44)
            Wordmark(size: 15)
            Wordmark(size: 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Wordmark lock-up · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        WordmarkLockup()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
