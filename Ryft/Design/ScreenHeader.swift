// The header row of Nocturne's screens (docs/work/2026-11-16-nocturne/design.md §P4-1 row 1, §P4-2 row 1): 40 pt high,
// the content's first row (with `ScreenScaffold(showsHeader: false)`). Today: the lock-up leading and one circle button
// trailing. Sleep (and Strain, PR 5): a circle button each side and the title between them, centred. A circle button at
// either edge puts its 40 pt circle's edge on the content inset; its 44 pt tap box reaches 2 pt past it (and past the
// row's top and bottom), not clipped.
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
}

/// A header row: `leading`, `center`, `trailing`, vertically centred in 40 pt. The slots are the caller's views; the
/// header adds no element of its own (`children: .contain`), so VoiceOver reads leading, centre, trailing. A slot may be
/// empty (Today without My Day, a mode without night buttons): the row keeps its height and the others their places.
struct ScreenHeader<Leading: View, Center: View, Trailing: View>: View {
    private enum Style { case lockUp, threeSlot }

    private let style: Style
    private let leading: Leading
    private let center: Center
    private let trailing: Trailing

    /// Three slots: a `CircleButton` at each edge, the centre between them (it wraps between the buttons at large sizes).
    init(@ViewBuilder leading: () -> Leading, @ViewBuilder center: () -> Center, @ViewBuilder trailing: () -> Trailing) {
        style = .threeSlot
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
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
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
