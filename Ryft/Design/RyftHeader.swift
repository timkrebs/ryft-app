import SwiftUI

/// Small mark + wide-tracked "RYFT" wordmark, centred at the top of every screen.
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

/// "RYFT" in wide-tracked uppercase.
struct Wordmark: View {
    var size: CGFloat = 17

    var body: some View {
        Text(verbatim: "RYFT")
            .font(.ryftNumber(size: size, weight: .medium))
            .tracking(size * 0.32)
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
                .tracking(4)
        }
        .foregroundStyle(Theme.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("RYFT — Your whole health."))
    }
}

#Preview("Header", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 28) {
            RyftHeader()
            BrandLockup()
        }
    }
}
