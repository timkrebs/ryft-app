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
///
/// VoiceOver reads Back, then the middle as one header element (the title, with the subtitle as its value, or
/// `spokenSubtitle` when the drawn one abbreviates: "Fri, Nov 13 · 55 min" → "Friday 13 November, 55 minutes"), then the
/// trailing slot. `onBack` is the caller's; nil pops through `dismiss`. Identifiers: `<identifierPrefix>.back` and
/// `<identifierPrefix>.header`. The page itself hides the navigation bar and keeps the back swipe (`.keepsBackSwipe()`).
struct PushedHeader<Trailing: View>: View {
    private let title: Text
    private let subtitle: Text?
    private let spokenSubtitle: Text?
    private let identifierPrefix: String
    private let onBack: (() -> Void)?
    private let trailing: Trailing

    @Environment(\.dismiss) private var dismiss

    init(_ title: Text, subtitle: Text? = nil, spokenSubtitle: Text? = nil, identifierPrefix: String = "header",
         onBack: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.spokenSubtitle = spokenSubtitle
        self.identifierPrefix = identifierPrefix
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        ScreenHeader {
            CircleButton(systemImage: "chevron.left", accessibilityLabel: SubpageHeader<EmptyView>.backLabel) {
                if let onBack { onBack() } else { dismiss() }
            }
            .accessibilityIdentifier("\(identifierPrefix).back")
        } center: {
            VStack(spacing: PushedHeaderSpec.subtitleGap) {
                title
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    subtitle
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(spokenSubtitle ?? subtitle ?? Text(verbatim: ""))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("\(identifierPrefix).header")
        } trailing: {
            trailing
        }
    }
}

extension PushedHeader where Trailing == PushedHeaderEmptySlot {
    /// A page with nothing at the trailing edge (History, the exercise page): the slot stays, empty.
    init(_ title: Text, subtitle: Text? = nil, spokenSubtitle: Text? = nil, identifierPrefix: String = "header",
         onBack: (() -> Void)? = nil) {
        self.init(title, subtitle: subtitle, spokenSubtitle: spokenSubtitle, identifierPrefix: identifierPrefix,
                  onBack: onBack) { PushedHeaderEmptySlot() }
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
            PushedHeader(Text(verbatim: "History"), subtitle: Text(verbatim: "8 workouts"))
            PushedHeader(Text(verbatim: "Upper A"), subtitle: Text(verbatim: "Fri, Nov 13 · 55 min · 17 sets"))
            PushedHeader(Text(verbatim: "My Day"), subtitle: Text(verbatim: "Today · Wed, Nov 18")) {
                CircleButton(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add")) {}
            }
            PushedHeader(Text(verbatim: "Upper/Lower 4× (copy) for the winter block"),
                         subtitle: Text(verbatim: "Hypertrophy · 4 days/week · repeating")) {
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
