import SwiftUI

/// The lock-screen mock's numbers (docs/work/2026-11-23-first-run/ui.md §4).
enum LockScreenMockSpec {
    /// The phone's top corners, and the inset between its edge and the notification.
    static let frameRadius: CGFloat = 36, sideInset: CGFloat = 12
    /// The clock block above the notification: the date, the time at `clockSize` (Light), and the gaps around them.
    static let clockSize: CGFloat = 56, clockTop: CGFloat = 26, clockBottom: CGFloat = 18, clockGap: CGFloat = 2
    /// The notification: `surfaceRaised`, the one card radius, 14 inside; the app tile 38 (scaled), 12 from the text.
    static let cardRadius = Theme.Metrics.neutralTileRadius, cardPadding: CGFloat = 14
    static let tileSide: CGFloat = 38, tileGap: CGFloat = 12, markSide: CGFloat = 22, tileRadius: CGFloat = 10
    /// The stacked notifications under it, hinting at a full lock screen: two bars, fading.
    static let ghostHeight: CGFloat = 12, ghostGap: CGFloat = 6
    static let ghostOpacities: [Double] = [0.55, 0.3]
    /// The phone is cut off at the bottom: its last `fadeShare` of height fades to the screen colour.
    static let fadeShare: Double = 0.28, bottomRoom: CGFloat = 36
    /// From this size the clock and the stacked bars go, and the notification stands alone: the text is the example.
    static let compactFrom = DynamicTypeSize.accessibility3

    /// Whether the clock, the stacked bars and the phone's frame are drawn at `size`.
    static func showsPhone(at size: DynamicTypeSize) -> Bool { size < compactFrom }
}

/// A lock screen with one RYFT notification on it, for the notification primer (first run) and wherever a page explains
/// what it would send. Decoration around one fact: the notification's words. Nocturne, dark only: a `surface` phone with a
/// 16 % ink outline, cut off at the bottom; the notification a `surfaceRaised` card with the mark in a tile, the title in
/// ink, the message and the time label in `textSecondary` (`textTertiary` fails on `surfaceRaised`). Nothing is teal or Volt.
///
/// The caller passes finished strings, localised, so this file owns no copy: the notification's `title` and `message`
/// (no health value in either: the lock-screen rule of docs/work/2026-11-22-notifications/ui.md §5), `timeLabel` ("now"),
/// `clock` (any `Date`; the lock screen's time and date are formatted for the locale) and `accessibilityLabel`, the one
/// sentence VoiceOver reads for the whole mock ("Example notification from RYFT. …"): the clock and the bars are hidden.
///
/// `.phone` draws the frame, the clock and the stacked bars; `.card` the notification alone (a page that has no room for the
/// phone). From `compactFrom` (AX3) `.phone` draws the card alone as well. No motion in it; the screen that holds it fades.
struct LockScreenMock: View {
    enum Style { case phone, card }

    var style: Style = .phone
    let clock: Date
    let title: String
    let message: String
    let timeLabel: String
    let accessibilityLabel: String

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The tile scales with the text up to 1.5 times its size: above that it would be the biggest thing in the card.
    @ScaledMetric(relativeTo: .callout) private var scaledTile = LockScreenMockSpec.tileSide
    private var tile: CGFloat { min(scaledTile, LockScreenMockSpec.tileSide * 1.5) }
    private var mark: CGFloat { tile * LockScreenMockSpec.markSide / LockScreenMockSpec.tileSide }

    var body: some View {
        Group {
            if style == .phone, LockScreenMockSpec.showsPhone(at: typeSize) {
                phone
            } else {
                notification
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    // MARK: the phone

    private var phone: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: LockScreenMockSpec.frameRadius, bottomLeadingRadius: 0,
                                           bottomTrailingRadius: 0, topTrailingRadius: LockScreenMockSpec.frameRadius,
                                           style: .continuous)
        return VStack(spacing: 0) {
            VStack(spacing: LockScreenMockSpec.clockGap) {
                Text(clock, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                Text(clock, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.ryftNumber(size: LockScreenMockSpec.clockSize, weight: .light))
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .padding(.top, LockScreenMockSpec.clockTop)
            .padding(.bottom, LockScreenMockSpec.clockBottom)
            notification
                .padding(.horizontal, LockScreenMockSpec.sideInset)
            VStack(spacing: LockScreenMockSpec.ghostGap) {
                ForEach(Array(LockScreenMockSpec.ghostOpacities.enumerated()), id: \.offset) { index, opacity in
                    RoundedRectangle(cornerRadius: LockScreenMockSpec.cardRadius / 2, style: .continuous)
                        .fill(Theme.surfaceRaised.opacity(opacity))
                        .frame(height: LockScreenMockSpec.ghostHeight)
                        .padding(.horizontal, LockScreenMockSpec.sideInset + CGFloat(index + 1) * 10)
                }
            }
            .padding(.top, LockScreenMockSpec.ghostGap)
            .padding(.bottom, LockScreenMockSpec.bottomRoom)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: shape)
        .overlay { shape.strokeBorder(Theme.textPrimary.opacity(CircleButton.borderOpacity), lineWidth: Theme.Metrics.hairline) }
        .mask {
            // Opaque down to `1 - fadeShare`, then to nothing at the bottom edge.
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: 1 - LockScreenMockSpec.fadeShare),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: the notification

    private var notification: some View {
        let shape = RoundedRectangle(cornerRadius: LockScreenMockSpec.cardRadius, style: .continuous)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        // At accessibility sizes the tile goes above the text, so the words keep the card's whole width.
        let outer = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: LockScreenMockSpec.tileGap))
        return outer {
            appTile
            VStack(alignment: .leading, spacing: 2) {
                layout {
                    Text(verbatim: title)
                        .font(.ryft(.button))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Text(verbatim: timeLabel)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(verbatim: message)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(LockScreenMockSpec.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: shape)
    }

    /// RYFT's mark in a rounded tile: `background` with the 16 % outline, as the circle button's border is.
    private var appTile: some View {
        let shape = RoundedRectangle(cornerRadius: LockScreenMockSpec.tileRadius * tile / LockScreenMockSpec.tileSide,
                                     style: .continuous)
        return RyftMark()
            .frame(width: mark, height: mark)
            .foregroundStyle(Theme.textPrimary)
            .frame(width: tile, height: tile)
            .background(Theme.background, in: shape)
            .overlay { shape.strokeBorder(Theme.textPrimary.opacity(CircleButton.borderOpacity), lineWidth: Theme.Metrics.hairline) }
    }
}

// MARK: - previews (dark only: ADR 0016, every colour is a one-value asset, so a light preview would be the same pixels)

private enum MockSample {
    /// 07:30 on a Monday, so the shots hold still.
    static let clock = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 7, minute: 30)) ?? .now
    static let title = "Your morning score is ready"
    static let message = "Open RYFT to see how you recovered overnight."
    static let label = "Example notification from RYFT. Your morning score is ready. Open RYFT to see how you recovered overnight."
    static func mock(_ style: LockScreenMock.Style = .phone, title: String = title, message: String = message) -> LockScreenMock {
        LockScreenMock(style: style, clock: clock, title: title, message: message, timeLabel: "now", accessibilityLabel: label)
    }
}

#Preview("LockScreenMock · phone", traits: .sizeThatFitsLayout) {
    DarkPreview { MockSample.mock() }
}

#Preview("LockScreenMock · journal and sync examples", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 20) {
            MockSample.mock(title: "How was yesterday?", message: "A few taps, and RYFT shows how your habits change the morning after.")
            MockSample.mock(title: "Your data hasn't synced", message: "Open RYFT to bring it up to date.")
        }
    }
}

#Preview("LockScreenMock · card", traits: .sizeThatFitsLayout) {
    DarkPreview { MockSample.mock(.card) }
}

#Preview("LockScreenMock · AX3 (card alone)", traits: .sizeThatFitsLayout) {
    DarkPreview { MockSample.mock() }
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("LockScreenMock · AX5", traits: .sizeThatFitsLayout) {
    DarkPreview { MockSample.mock() }
        .environment(\.dynamicTypeSize, .accessibility5)
}
