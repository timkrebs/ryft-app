// The header of a page pushed from Train, My Day or an activity (Nocturne PR 6 B §1.2 "Pushed"; T6B.0): Back on the left, the
// page's title over a subtitle in the middle, and a trailing circle or an empty 40 pt slot. Sleep's header and PR 5's workout
// detail draw the same row by hand; area B's seven pushed pages (Plans, plan detail, History, session detail, the exercise
// page, My Day, activity detail) share this one. A/C's subpages, with a 26 pt title leading, are `SubpageScaffold`.
import SwiftUI

/// The pushed header's numbers.
enum PushedHeaderSpec {
    /// The title → the subtitle under it: 2 (Sleep's header, `StrainLayout.headerSubtitleGap`).
    nonisolated static let subtitleGap: CGFloat = 2
}

/// `ScreenHeader`'s three slots: `CircleButton("chevron.left")` labelled "Back" · the title (`callout`, `textPrimary`) with the
/// subtitle 2 under it (`caption`, `textTertiary`, tabular digits) · the caller's `CircleButton` (a menu, "Add") or, without one,
/// an empty 40 pt slot, so the title stays centred. 40 high; it grows only when the title or the subtitle wraps (large text).
/// A subtitle of facts ("Fri, Nov 13 · 55 min · 17 sets") comes as `subtitleParts`: one line joined, one part per line from
/// AX1 (`PartsLine`), so no "·" dangles at a line's end.
/// From AX1 (C §2.9, as `SubpageHeader` stacks): Back and the trailing circle on the first 40 pt line, 12 under it the title
/// and then the subtitle, from the leading inset across the whole width, wrapping; never squeezed between the circles.
///
/// VoiceOver reads Back, then the middle as one header element (the title, with the subtitle as its value, or
/// `spokenSubtitle` when the drawn one abbreviates: "Fri, Nov 13 · 55 min" → "Friday 13 November, 55 minutes"), then the
/// trailing slot; from AX1 in the order drawn: Back, the trailing circle, the title. `onBack` is the caller's; nil pops
/// through `dismiss`. Identifiers: `<identifierPrefix>.back` and `<identifierPrefix>.header`. The page itself hides the
/// navigation bar and keeps the back swipe (`.keepsBackSwipe()`).
struct PushedHeader<Trailing: View>: View {
    private let title: Text
    private let subtitle: Text?
    private let subtitleParts: [String]?
    private let spokenSubtitle: Text?
    private let identifierPrefix: String
    private let onBack: (() -> Void)?
    private let trailing: Trailing

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `subtitleParts`: the subtitle as parts (`PartsLine`), in place of `subtitle`; nil or empty: `subtitle`.
    init(_ title: Text, subtitle: Text? = nil, subtitleParts: [String]? = nil, spokenSubtitle: Text? = nil,
         identifierPrefix: String = "header", onBack: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleParts = subtitleParts?.isEmpty == false ? subtitleParts : nil
        self.spokenSubtitle = spokenSubtitle
        self.identifierPrefix = identifierPrefix
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            stacked
        } else {
            ScreenHeader {
                backButton
            } center: {
                middle(.center)
            } trailing: {
                trailing
            }
        }
    }

    /// From AX1: the circles' line (each laid out as its 40 pt circle, the edges on the insets), then the title and the
    /// subtitle under it, leading (`SubpageHeader`'s stacked layout).
    private var stacked: some View {
        VStack(alignment: .leading, spacing: SubpageSpec.stackedGap) {
            HStack(spacing: 0) {
                backButton
                    .padding(-ScreenHeaderSpec.buttonOverhang)
                Spacer(minLength: ScreenHeaderSpec.minGap)
                trailing
                    .padding(-ScreenHeaderSpec.buttonOverhang)
            }
            .frame(minHeight: ScreenHeaderSpec.height)
            middle(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private var backButton: some View {
        CircleButton(systemImage: "chevron.left", accessibilityLabel: SubpageHeader<EmptyView>.backLabel) {
            if let onBack { onBack() } else { dismiss() }
        }
        .accessibilityIdentifier("\(identifierPrefix).back")
    }

    /// The title over the subtitle: one header element.
    private func middle(_ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: PushedHeaderSpec.subtitleGap) {
            title
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
            if let subtitleParts {
                PartsLine(subtitleParts)
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            } else if let subtitle {
                subtitle
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .multilineTextAlignment(alignment == .leading ? .leading : .center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenSubtitle ?? subtitleParts.map { Text(verbatim: MyDayText.join($0)) } ?? subtitle
            ?? Text(verbatim: ""))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("\(identifierPrefix).header")
    }
}

extension PushedHeader where Trailing == PushedHeaderEmptySlot {
    /// A page with nothing at the trailing edge (History, the exercise page): the slot stays, empty.
    init(_ title: Text, subtitle: Text? = nil, subtitleParts: [String]? = nil, spokenSubtitle: Text? = nil,
         identifierPrefix: String = "header", onBack: (() -> Void)? = nil) {
        self.init(title, subtitle: subtitle, subtitleParts: subtitleParts, spokenSubtitle: spokenSubtitle,
                  identifierPrefix: identifierPrefix, onBack: onBack) { PushedHeaderEmptySlot() }
    }
}

/// The trailing slot without a button: a circle button's 44 pt box, empty and hidden, so the title is centred between
/// the edges as on a page with a button.
struct PushedHeaderEmptySlot: View {
    var body: some View {
        Color.clear
            .frame(width: CircleButton.hitSize, height: CircleButton.hitSize)
            .accessibilityHidden(true)
    }
}

// MARK: - previews (dark only; verbatim: the screens own the strings)

private struct PushedHeaderPreviewList: View {
    var body: some View {
        VStack(spacing: 24) {
            PushedHeader(Text(verbatim: "Plans"))
            PushedHeader(Text(verbatim: "History"), subtitleParts: ["25 workouts", "last 90 days"])
            PushedHeader(Text(verbatim: "Upper A"), subtitleParts: ["Fri, Nov 13", "55 min", "17 sets"])
            PushedHeader(Text(verbatim: "My Day"), subtitle: Text(verbatim: "Today · Wed, Nov 18")) {
                CircleButton(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add")) {}
            }
            PushedHeader(Text(verbatim: "Upper/Lower 4× (copy) for the winter block"),
                         subtitleParts: ["Hypertrophy", "4 days/week", "repeating"]) {
                CircleButton(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "More")) {}
            }
        }
    }
}

#Preview("PushedHeader", traits: .sizeThatFitsLayout) {
    DarkPreview { PushedHeaderPreviewList() }
}

#Preview("PushedHeader · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { PushedHeaderPreviewList() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
