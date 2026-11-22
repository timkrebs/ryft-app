// The header of a pushed page (Nocturne PR 6 B §1.2 "Pushed"; T6B.0; Nocturne gate DG-6, one rule for every pushed page):
// Back on the left, the page's title over a subtitle in the middle, and a trailing circle or an empty 40 pt slot. Area B's
// pushed pages (Plans, plan detail, History, session detail, the exercise page, My Day, activity detail), the workout detail,
// and every pushed `SubpageScaffold` (Profile's and the journal's subpages, the signed-out forms, the import's steps 2–5)
// draw it. The tab roots keep `ScreenHeader`; a sheet's root has `SheetHeader`.
import SwiftUI

/// The pushed header's numbers.
enum PushedHeaderSpec {
    /// The title → the subtitle under it: 2 (Sleep's header; the workout detail's sport over its day and time).
    nonisolated static let subtitleGap: CGFloat = 2
}

/// Three slots: `CircleButton("chevron.left")` labelled "Back" · the title (`callout`, `textPrimary`) with the
/// subtitle 2 under it (`caption`, `textTertiary`, tabular digits) · the caller's `CircleButton` (a menu, "Add") or, without one,
/// an empty 40 pt slot, so the title stays centred. 40 high; it grows only when the title or the subtitle wraps (large text).
/// A subtitle of facts ("Fri, Nov 13 · 55 min · 17 sets") comes as `subtitleParts`: one line joined, one part per line from
/// AX1 (`PartsLine`), so no "·" dangles at a line's end. With a `subtitle` as well, that is the line below AX1 (the page's
/// own wording: "Today · Wed, Nov 18", "Barbell · Chest") and the parts are only how it stands from AX1.
/// Below AX1 the middle is centred on the row whatever the slots hold (two circles trailing, Back alone leading): the wider
/// slot's width stays free on both sides (`SheetHeaderLayout`), and a long title wraps there, never under the circles.
/// From AX1 (C §2.9): Back and the trailing circle on the first 40 pt line, 12 under it the title and then the subtitle,
/// from the leading inset across the whole width, wrapping; never squeezed between the circles.
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
    /// The outline drawn where the title goes while it isn't known (`init(loading:placeholder:)`).
    private var titlePlaceholder: CGSize?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `subtitleParts`: the subtitle as parts, one per line from AX1 (`PartsLine`). Below AX1 `subtitle` is drawn when there
    /// is one, else the parts joined (`MyDayText.join`); VoiceOver hears `spokenSubtitle`, else `subtitle`, else the parts
    /// joined. Nil or empty: `subtitle` at every size.
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
            // Each circle laid out as its 40 pt circle, the edges on the insets; the title never stacks below AX1.
            SheetHeaderLayout(minHeight: ScreenHeaderSpec.height, minGap: ScreenHeaderSpec.minGap, minTitleWidth: 0) {
                backButton
                    .headerEdgeButton()
                middle(.center)
                HStack(spacing: 0) { trailing }
                    .headerEdgeButton()
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
        }
    }

    /// From AX1: the circles' line (each laid out as its 40 pt circle, the edges on the insets), then the title and the
    /// subtitle under it, leading.
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
        CircleButton(systemImage: "chevron.left", accessibilityLabel: CircleButton.backLabel) {
            if let onBack { onBack() } else { dismiss() }
        }
        .accessibilityIdentifier("\(identifierPrefix).back")
    }

    /// The title over the subtitle: one header element.
    private func middle(_ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: PushedHeaderSpec.subtitleGap) {
            titleLine(alignment)
            if let subtitleParts, subtitle == nil || typeSize.isAccessibilitySize {
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
        .accessibilityValue(spokenSubtitle ?? subtitle ?? subtitleParts.map { Text(verbatim: MyDayText.join($0)) }
            ?? Text(verbatim: ""))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("\(identifierPrefix).header")
    }

    /// The title; while it isn't known, the outline capsule in its place: on the title's one line (the header keeps its
    /// height), centred like the title below AX1 and from the leading inset under Back from AX1.
    @ViewBuilder private func titleLine(_ alignment: HorizontalAlignment) -> some View {
        if let titlePlaceholder {
            title
                .font(.ryft(.callout))
                .foregroundStyle(.clear)
                .lineLimit(1)
                .overlay(alignment: alignment == .leading ? .leading : .center) {
                    PlaceholderOutline(Capsule())
                        .frame(width: titlePlaceholder.width, height: titlePlaceholder.height)
                }
        } else {
            title
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

extension PushedHeader where Trailing == PushedHeaderEmptySlot {
    /// A page with nothing at the trailing edge (History, the exercise page): the slot stays, empty.
    init(_ title: Text, subtitle: Text? = nil, subtitleParts: [String]? = nil, spokenSubtitle: Text? = nil,
         identifierPrefix: String = "header", onBack: (() -> Void)? = nil) {
        self.init(title, subtitle: subtitle, subtitleParts: subtitleParts, spokenSubtitle: spokenSubtitle,
                  identifierPrefix: identifierPrefix, onBack: onBack) { PushedHeaderEmptySlot() }
    }

    /// A page whose title isn't known yet (a session opened from outside History while it loads): an outline capsule of
    /// `placeholder`'s size where the title goes, which follows the header's layout (centred below AX1, under Back from
    /// AX1). VoiceOver hears `label` as the header ("Loading the workout").
    init(loading label: Text, placeholder: CGSize, identifierPrefix: String = "header", onBack: (() -> Void)? = nil) {
        self.init(label, identifierPrefix: identifierPrefix, onBack: onBack)
        titlePlaceholder = placeholder
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
            PushedHeader(Text(verbatim: "My Day"), subtitle: Text(verbatim: "Today · Wed, Nov 18"),
                         subtitleParts: ["Today", "Wed, Nov 18"]) {
                CircleButton(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add")) {}
            }
            PushedHeader(Text(verbatim: "Upper/Lower 4× (copy) for the winter block"),
                         subtitleParts: ["Hypertrophy", "4 days/week", "repeating"]) {
                CircleButton(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "More")) {}
            }
            PushedHeader(loading: Text(verbatim: "Loading the workout"), placeholder: CGSize(width: 120, height: 14))
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
