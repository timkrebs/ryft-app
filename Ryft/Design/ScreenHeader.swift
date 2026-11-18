// The header row of Nocturne's screens (docs/work/2026-11-16-nocturne/design.md §P4-1 row 1, §P4-2 row 1): 40 pt high,
// the content's first row (with `ScreenScaffold(showsHeader: false)`). Today: the lock-up leading and one circle button
// trailing. Sleep: a circle button each side and the title between them, centred. Strain, Insights and Profile (PR 5,
// §P5-3.1 row 1, §P5-5.1 row 1, §P5-6.1 row 1): the screen's title leading, 26 Light, and a circle button or a control
// trailing. A circle button at either edge puts its 40 pt circle's edge on the content inset; its 44 pt tap box reaches 2 pt
// past it (and past the row's top and bottom), not clipped.
import SwiftUI

/// The header's measurements (a separate, non-generic type: `ScreenHeader` is generic).
enum ScreenHeaderSpec {
    /// The row's height; it grows only when a centre title wraps (large text).
    static let height: CGFloat = 40
    /// How far a circle button's 44 pt box reaches past its 40 pt circle on each side: 2.
    static let buttonOverhang: CGFloat = (CircleButton.hitSize - CircleButton.diameter) / 2
    /// The lock-up's mark on Today: 26 pt, the wordmark 15 pt beside it.
    static let lockUpMark: CGFloat = 26
    /// The least space between the slots.
    static let minGap: CGFloat = 8
    /// A leading title's tracking: −1 % of its 26 pt (−0.26).
    static let titleTracking: CGFloat = -0.26
    /// `.wide` from AX1: the title → the control under it.
    static let stackedGap: CGFloat = 12

    /// What the trailing slot of `init(title:trailing:)` holds.
    enum Trailing: Equatable, Sendable {
        /// A `CircleButton` (Strain's plus): laid out as its 40 pt circle, its tap box reaching 2 past the inset.
        case button
        /// A control as wide as its content (Insights' range picker): on the title's line, at the inset; from AX1 under the
        /// title, full width.
        case wide
    }
}

/// A screen's title in the header's leading slot: `.title` (26 Light), tracking −0.26, `textPrimary`, a header for VoiceOver;
/// it wraps rather than truncating at large sizes.
struct ScreenHeaderTitle: View {
    let text: Text

    var body: some View {
        text
            .font(.ryft(.title))
            .tracking(ScreenHeaderSpec.titleTracking)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A header row: `leading`, `center`, `trailing`, vertically centred in 40 pt. The slots are the caller's views; the
/// header adds no element of its own (`children: .contain`), so VoiceOver reads leading, centre, trailing. A slot may be
/// empty (Today without My Day, a mode without night buttons): the row keeps its height and the others their places.
struct ScreenHeader<Leading: View, Center: View, Trailing: View>: View {
    private enum Style: Equatable { case lockUp, threeSlot, title(ScreenHeaderSpec.Trailing) }

    private let style: Style
    private let leading: Leading
    private let center: Center
    private let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Three slots: a `CircleButton` at each edge, the centre between them (it wraps between the buttons at large sizes).
    init(@ViewBuilder leading: () -> Leading, @ViewBuilder center: () -> Center, @ViewBuilder trailing: () -> Trailing) {
        style = .threeSlot
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
        if style == .title(.wide), typeSize.isAccessibilitySize {
            // From AX1 the control has its own line under the title, full width.
            VStack(alignment: .leading, spacing: ScreenHeaderSpec.stackedGap) {
                leading
                    .frame(maxWidth: .infinity, minHeight: ScreenHeaderSpec.height, alignment: .leading)
                trailing
                    .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .contain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 0) {
            switch style {
            case .lockUp:
                leading
                Spacer(minLength: ScreenHeaderSpec.minGap)
                edgeButton(trailing)
            case .threeSlot:
                edgeButton(leading)
                center
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, ScreenHeaderSpec.minGap)
                edgeButton(trailing)
            case .title(let kind):
                leading
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                Spacer(minLength: ScreenHeaderSpec.minGap)
                if kind == .button {
                    edgeButton(trailing)
                } else {
                    trailing.fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: ScreenHeaderSpec.height)
        .accessibilityElement(children: .contain)
    }

    /// A circle button at the row's edge, laid out as its 40 pt circle: the 44 pt box reaches 2 past it on every side, so
    /// the circle's edge is on the inset and the row stays 40 high.
    private func edgeButton(_ button: some View) -> some View {
        button.padding(-ScreenHeaderSpec.buttonOverhang)
    }
}

extension ScreenHeader where Leading == WordmarkLockup, Center == EmptyView {
    /// Today's header: the lock-up (mark 26, wordmark 15) leading, a `CircleButton` trailing. `handOff`: the lock-up is
    /// the launch's hand-off target (`WordmarkLockup(handOff:)`, design.md §P4-7); only Today's header passes `true`.
    init(handOff: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        style = .lockUp
        leading = WordmarkLockup(markSize: ScreenHeaderSpec.lockUpMark, handOff: handOff)
        center = EmptyView()
        self.trailing = trailing()
    }
}

extension ScreenHeader where Leading == ScreenHeaderTitle, Center == EmptyView {
    /// A titled screen's header (Strain, Insights): the title leading, `trailing` at the inset. `trailingLayout` says what the
    /// slot holds: a `CircleButton` (`.button`) or a control as wide as its content (`.wide`: on the title's line, under it
    /// from AX1). An empty trailing slot keeps the row's 40 pt.
    init(title: Text, trailingLayout: ScreenHeaderSpec.Trailing = .button, @ViewBuilder trailing: () -> Trailing) {
        style = .title(trailingLayout)
        leading = ScreenHeaderTitle(text: title)
        center = EmptyView()
        self.trailing = trailing()
    }
}

extension ScreenHeader where Leading == ScreenHeaderTitle, Center == EmptyView, Trailing == EmptyView {
    /// A titled screen's header without a trailing control (Profile).
    init(title: Text) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - previews

/// Sleep's centre as the board has it: the title, and 2 below it the night (the screen builds its own).
private struct ScreenHeaderPreviewTitle: View {
    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: "Sleep")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: "Last night · Sun, Nov 15")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
        }
        .multilineTextAlignment(.center)
    }
}

#Preview("ScreenHeader", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 24) {
            ScreenHeader {
                CircleButton(systemImage: "calendar", iconSize: 16, accessibilityLabel: Text(verbatim: "Calendar")) {}
            }
            .border(Theme.separator)
            // My Day off: the button is gone, the row keeps its 40 pt.
            ScreenHeader { EmptyView() }
                .border(Theme.separator)
            ScreenHeader {
                CircleButton(systemImage: "chevron.left", accessibilityLabel: Text(verbatim: "Previous night")) {}
            } center: {
                ScreenHeaderPreviewTitle()
            } trailing: {
                CircleButton(systemImage: "chevron.right", accessibilityLabel: Text(verbatim: "Next night")) {}
                    .disabled(true)
            }
            .border(Theme.separator)
            ScreenHeaderTitlePreviews()
        }
    }
}

#Preview("ScreenHeader · AX3", traits: .sizeThatFitsLayout) {
    // The lock-up and the buttons keep their size; the centre title wraps between the buttons and the row grows.
    DarkPreview {
        VStack(spacing: 24) {
            ScreenHeader {
                CircleButton(systemImage: "calendar", iconSize: 16, accessibilityLabel: Text(verbatim: "Calendar")) {}
            }
            ScreenHeader {
                CircleButton(systemImage: "chevron.left", accessibilityLabel: Text(verbatim: "Previous night")) {}
            } center: {
                ScreenHeaderPreviewTitle()
            } trailing: {
                CircleButton(systemImage: "chevron.right", accessibilityLabel: Text(verbatim: "Next night")) {}
            }
            ScreenHeaderTitlePreviews()
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

/// The titled headers: Strain's (a circle button), Insights' (the range control), Profile's (no trailing).
private struct ScreenHeaderTitlePreviews: View {
    @State private var range = "30 D"

    var body: some View {
        VStack(spacing: 24) {
            ScreenHeader(title: Text(verbatim: "Strain")) {
                CircleButton(systemImage: "plus", iconSize: 14, accessibilityLabel: Text(verbatim: "Add activity")) {}
            }
            .border(Theme.separator)
            ScreenHeader(title: Text(verbatim: "Insights"), trailingLayout: .wide) {
                SegmentedPicker(selection: $range, options: ["7 D", "30 D", "90 D"], look: .inkFill, width: .content) { $0 }
            }
            .border(Theme.separator)
            ScreenHeader(title: Text(verbatim: "Profile"))
                .border(Theme.separator)
        }
    }
}
