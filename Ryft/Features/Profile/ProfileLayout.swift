// Profile's main list in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-6.1; the lead's board measurements): every gap
// is from the bottom of one element to the top of the next, so the page is one `VStack(spacing: 0)` with these between its
// rows. Plain values, so the layout tests assert numbers, not pixels.
import CoreGraphics
import Foundation

enum ProfileLayout {
    // MARK: the page, top to bottom (§P5-6.1)

    /// Row 1: the header, "Profile" with no trailing control (`ScreenHeaderSpec.height`).
    nonisolated static let header: CGFloat = 40
    /// The header to the identity row.
    nonisolated static let headerToIdentity: CGFloat = 18
    /// The identity row to the first group's title.
    nonisolated static let identityToFirstGroup: CGFloat = 24
    /// Between two groups (the last line of one, its footer included, to the next title): the board's 18
    /// (`GroupedListSpec.groupSpacing`).
    nonisolated static let groupGap: CGFloat = 18
    /// A group's title to its card (`GroupedListSpec.titleGap`).
    nonisolated static let titleToCard: CGFloat = 8
    /// The card (`GroupedCard`): radius 22, rows at least 46 high.
    nonisolated static let cardRadius: CGFloat = 22, rowMinHeight: CGFloat = 46
    /// The last group to the buttons row, and the buttons row (or its message) to the Developer group (Debug builds).
    nonisolated static let buttonsTop: CGFloat = 18, buttonsToDeveloper: CGFloat = 18
    /// The buttons row: two pills 52 high (`PillButton.minHeight`), 12 apart; Log out is as wide as its title plus 22 a
    /// side (about 108 at the default size), Export takes the rest.
    nonisolated static let buttonsHeight: CGFloat = 52, buttonsGap: CGFloat = 12, logOutPadding: CGFloat = 22
    /// The buttons row to an export error under it.
    nonisolated static let buttonsToMessage: CGFloat = 8
    /// The brand lock-up above the About group: 18 above it (a group's gap), 18 under it to the group's title.
    nonisolated static let lockUpToGroup: CGFloat = 18

    // MARK: the identity row (§P5-6.1 row 2)

    /// The avatar to the name and status, side by side; from AX1 the avatar sits over them, this far above.
    nonisolated static let identitySpacing: CGFloat = 16, identityStackedSpacing: CGFloat = 12
    /// The name to the status row.
    nonisolated static let nameToStatus: CGFloat = 6
    /// The name: 20 pt Light, growing with Dynamic Type (relative to `.title3`).
    nonisolated static let nameSize: CGFloat = 20
    /// The status row: a 6 pt dot, 6 to the line (12 pt `.caption`, `textSecondary`).
    nonisolated static let statusDot: CGFloat = 6, statusDotGap: CGFloat = 6
    /// A hollow (updating) dot's ring.
    nonisolated static let hollowDotLine: CGFloat = 1

    // MARK: the avatar (§P5-6.1 "The avatar")

    /// A 72 pt frame, fixed at every text size.
    nonisolated static let avatar: CGFloat = 72
    /// The strain ring: radius 34 (its centre line), stroke 1.6, round caps; the track `textPrimary` at 10 %.
    nonisolated static let ringRadius: CGFloat = 34, ringStroke: CGFloat = 1.6, trackOpacity = 0.10
    /// The arc's end: a dot of radius 3.4 in `metricStrain` with a 1.6 `background` ring around it (the gauge's end dots).
    nonisolated static let endDotRadius: CGFloat = 3.4, endDotRing: CGFloat = 1.6
    /// The inner disc (`surface`) at inset 8: 56 across.
    nonisolated static let discInset: CGFloat = 8
    nonisolated static var discDiameter: CGFloat { avatar - 2 * discInset }
    /// The initials: 20 pt Light, tracking 0.04 em (0.8 pt); without initials the `person` glyph at 20 pt Light.
    nonisolated static let initialsSize: CGFloat = 20, initialsTrackingEm: CGFloat = 0.04
    nonisolated static var initialsTracking: CGFloat { initialsSize * initialsTrackingEm }

    /// The strain scale the ring is a share of (`MetricSpec.strain`'s 0…21).
    nonisolated static let strainMax: Double = 21

    /// The ring's share, 0…1, for today's strain; nil without one (the track only).
    nonisolated static func strainShare(_ strain: Double?) -> Double? {
        guard let strain, strain.isFinite else { return nil }
        return min(max(strain / strainMax, 0), 1)
    }

    /// Where the arc ends, in degrees clockwise from 12 o'clock (12.4 → 212.6°); nil without strain today.
    nonisolated static func arcEndDegrees(_ strain: Double?) -> Double? {
        strainShare(strain).map { $0 * 360 }
    }

    /// The end dot's centre in the avatar's 72 pt frame: on the ring's centre line at `degrees` from 12 o'clock.
    nonisolated static func endPoint(degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        let centre = avatar / 2
        return CGPoint(x: centre + ringRadius * CGFloat(sin(radians)), y: centre - ringRadius * CGFloat(cos(radians)))
    }
}
