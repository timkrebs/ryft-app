// The activity row of the Strain board (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-3.6; build plan §2: T5.2 builds
// the board row, PR 6 B extends it as `ActivityRow` S6 with source badges, a state mark, a dashed variant and a card style).
// One row for a workout, a logged session, a My Day item and Train's link rows (B §3.1, `b-23`).
import SwiftUI

/// The row's numbers (§P5-12 test 1; B §1.3).
enum ActivityListRowSpec {
    /// 60 high at least (it grows with its text), radius 20, 16 at the sides, 12 between the disc, the text and the value.
    nonisolated static let minHeight: CGFloat = 60, radius: CGFloat = 20, sidePadding: CGFloat = 16, spacing: CGFloat = 12
    /// Above and below the text when the row grows past 60 (large text, a wrapped title).
    nonisolated static let verticalPadding: CGFloat = 10
    /// The leading disc (`IconDisc` `.regular`).
    nonisolated static let disc: CGFloat = 36
    /// The title → the meta line, and (from AX1) the meta → the value under it.
    nonisolated static let metaGap: CGFloat = 2, stackedValueGap: CGFloat = 4
    /// The value: 20 Light at the default size, growing with Dynamic Type like `.title3`.
    nonisolated static let valueSize: CGFloat = 20
    /// The chevron of a row that is a link with a chevron (Train's rows, a session): 12 pt, `textTertiary`.
    nonisolated static let chevronSize: CGFloat = 12
    /// The value's caption ("load", B §7.1): under the value, flush with its trailing edge; from AX1 beside it, this far.
    nonisolated static let captionGap: CGFloat = 0, stackedCaptionGap: CGFloat = 4
}

/// `[disc 36] 12 [title / meta] 12 [value] (12 [chevron])` on `surface`, radius 20: the title `callout` (15) in
/// `textPrimary`, 2 under it the meta `caption` (12) in `textTertiary` ("07:10 · 42 min · 7.8 km"), the value 20 Light in
/// `textPrimary` at the right ("–" in `textSecondary` without one). From AX1 the value goes under the meta and the title wraps.
/// Layout only: the caller makes it a link (`NavigationLink(value:)`), says what it opens (a hint) and names it (an identifier).
/// One VoiceOver element whose label is `content.spoken`.
///
/// PR 6 B's options (T6B.0): `filledDisc` fills the disc in ink (`IconDisc.Style.filled`: Plans' enrolled plan, §6.1), and
/// `valueCaption` puts a word under the value in `axis` (11) `textTertiary` (History's "load", §7.1). Both are drawing only:
/// `spoken` still says everything. My Day's (source badges, the state mark, the dashed missing night, the card style) are
/// T6B.6's.
struct ActivityListRow: View {
    /// What a row says. A value type, so the screens build it in their models and tests read it.
    struct Content: Equatable {
        var systemImage: String
        var title: String
        /// The facts under the title; nil leaves the title alone.
        var meta: String?
        /// The number at the right (strain "9.8"); nil shows "–".
        var value: String?
        /// The row's VoiceOver label: one sentence in the order it is drawn.
        var spoken: String
        /// A column for the value at all: activity rows have one, Train's link rows do not.
        var showsValue = true
        /// The disc filled in ink with a `background` glyph: the row that is "this one" (Plans' enrolled plan, with
        /// `checkmark`). `spoken` says so ("active").
        var filledDisc = false
        /// A word under the value ("load"); nil draws the value alone. In `spoken` as the caller words it.
        var valueCaption: String?
    }

    enum Accessory: Equatable {
        case none
        /// A `chevron.right`: Train's rows and a linked session (the board's activity rows have none, D5-22).
        case chevron
    }

    let content: Content
    var accessory: Accessory = .none

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var valueSize: CGFloat = ActivityListRowSpec.valueSize

    var body: some View {
        HStack(alignment: .center, spacing: ActivityListRowSpec.spacing) {
            IconDisc(systemImage: content.systemImage, style: content.filledDisc ? .filled : .outline)
            VStack(alignment: .leading, spacing: ActivityListRowSpec.metaGap) {
                Text(verbatim: content.title)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta = content.meta {
                    Text(verbatim: meta)
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if content.showsValue, typeSize.isAccessibilitySize {
                    value.padding(.top, ActivityListRowSpec.stackedValueGap - ActivityListRowSpec.metaGap)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if content.showsValue, !typeSize.isAccessibilitySize {
                value
            }
            if accessory == .chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: ActivityListRowSpec.chevronSize, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, ActivityListRowSpec.sidePadding)
        .padding(.vertical, ActivityListRowSpec.verticalPadding)
        .frame(maxWidth: .infinity, minHeight: ActivityListRowSpec.minHeight, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: ActivityListRowSpec.radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: ActivityListRowSpec.radius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: content.spoken))
    }

    /// The number, and its caption under it (beside it from AX1, where the value is under the meta).
    @ViewBuilder private var value: some View {
        if let caption = content.valueCaption {
            if typeSize.isAccessibilitySize {
                HStack(alignment: .firstTextBaseline, spacing: ActivityListRowSpec.stackedCaptionGap) {
                    number
                    captionText(caption)
                }
            } else {
                VStack(alignment: .trailing, spacing: ActivityListRowSpec.captionGap) {
                    number
                    captionText(caption)
                }
            }
        } else {
            number
        }
    }

    private var number: some View {
        Text(verbatim: content.value ?? Fmt.placeholder)
            .font(.ryftNumber(size: valueSize, weight: .light))
            .foregroundStyle(content.value == nil ? Theme.textSecondary : Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }

    private func captionText(_ caption: String) -> some View {
        Text(verbatim: caption)
            .font(.ryft(.axis))
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
            .fixedSize()
    }
}

/// A row while its list loads: the outline at the row's height and radius (`PlaceholderRow`), nothing inside.
struct ActivityListRowPlaceholder: View {
    var body: some View {
        PlaceholderRow(height: ActivityListRowSpec.minHeight, radius: ActivityListRowSpec.radius)
    }
}

// MARK: - previews (dark only; verbatim: the screens own the strings)

private enum ActivityListRowPreview {
    static let rows: [(ActivityListRow.Content, ActivityListRow.Accessory)] = [
        (.init(systemImage: "figure.run", title: "Run", meta: "07:10 · 42 min · 7.8 km", value: "9.8",
               spoken: "Run, 7:10 AM, 42 minutes, 7.8 kilometres, Strain 9.8"), .none),
        (.init(systemImage: "dumbbell", title: "Upper A", meta: "17:30 · 55 min · Load 84.6", value: "6.1",
               spoken: "Upper A, 5:30 PM, 55 minutes, Strain 6.1, Muscular load 84.6"), .none),
        (.init(systemImage: "figure.walk", title: "Walk", meta: "12:05 · 24 min · 104 bpm", value: nil,
               spoken: "Walk, 12:05 PM, 24 minutes, No strain"), .none),
        (.init(systemImage: "list.bullet.rectangle", title: "My plans", meta: "Upper/Lower 4× · week 6", value: nil,
               spoken: "My plans, Upper/Lower 4× · week 6", showsValue: false), .chevron),
        // PR 6 B: the enrolled plan's filled disc (Plans) and a value with its caption (History).
        (.init(systemImage: "checkmark", title: "Upper/Lower 4×", meta: "Hypertrophy · 4 days/week · repeating", value: nil,
               spoken: "Upper/Lower 4×, active, Hypertrophy, 4 days a week, repeating", showsValue: false,
               filledDisc: true), .chevron),
        (.init(systemImage: "dumbbell.fill", title: "Upper A", meta: "Fri, Nov 13 · 55m · 7,500 kg", value: "85.0",
               spoken: "Upper A, Friday 13 November, 55 minutes, 7,500 kilograms, muscular load 85",
               valueCaption: "load"), .chevron),
    ]
}

private struct ActivityListRowPreviewList: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(ActivityListRowPreview.rows.indices, id: \.self) { i in
                ActivityListRow(content: ActivityListRowPreview.rows[i].0, accessory: ActivityListRowPreview.rows[i].1)
            }
            ActivityListRowPlaceholder()
        }
    }
}

#Preview("ActivityListRow", traits: .sizeThatFitsLayout) {
    DarkPreview { ActivityListRowPreviewList() }
}

#Preview("ActivityListRow · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { ActivityListRowPreviewList() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
