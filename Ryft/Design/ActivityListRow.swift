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

    // MARK: S6, My Day's extensions (T6B.6; B §9, `b-17`, `b-18`, `b-26`)

    /// A row with source badges hangs from its top: 12 above and below, the value 6 and the chevron 12 under the row's top
    /// inset, so both sit on the disc's middle.
    nonisolated static let badgedVerticalPadding: CGFloat = 12, valueTopInset: CGFloat = 6, chevronTopInset: CGFloat = 12
    /// The meta line → the badges' line.
    nonisolated static let badgesGap: CGFloat = 4
    /// `style: .card`: no surface and no sides of its own (the card's 16 are the inset), 12 above and below.
    nonisolated static let cardVerticalPadding: CGFloat = 12
    /// `style: .dashed`: a 1 pt outline at ink 12 % in 4-on-4 dashes; its disc's ring (`IconDisc`'s 16 %) in 3-on-3.
    nonisolated static let dashedOutlineOpacity = 0.12, outlineDash: CGFloat = 4, discDash: CGFloat = 3
    /// The value's unit ("h" after the night's "7:48"): `caption` in `textTertiary`, 3 after the number, on its baseline.
    nonisolated static let unitGap: CGFloat = 3
}

/// `[disc 36] 12 [title / meta] 12 [value] (12 [chevron])` on `surface`, radius 20: the title `callout` (15) in
/// `textPrimary`, 2 under it the meta `caption` (12) in `textTertiary` ("07:10 · 42 min · 7.8 km"), the value 20 Light in
/// `textPrimary` at the right ("–" in `textSecondary` without one). From AX1 the value goes under the meta and the title wraps.
/// Layout only: the caller makes it a link (`NavigationLink(value:)`), says what it opens (a hint) and names it (an identifier).
/// One VoiceOver element whose label is `content.spoken`.
///
/// PR 6 B's options (T6B.0): `filledDisc` fills the disc in ink (`IconDisc.Style.filled`: Plans' enrolled plan, §6.1), and
/// `valueCaption` puts a word under the value in `axis` (11) `textTertiary` (History's "load", §7.1). Both are drawing only:
/// `spoken` still says everything.
///
/// My Day's (S6, T6B.6; B §9):
/// - `badges`: a second meta line of `SourceBadge`s, 4 under the meta. Such a row hangs from its top (12 above and below), so
///   the disc, the title and the value line up however many lines the text takes.
/// - `mark`: an `ActivityStateMark` in the value's place (the scored strain, or a state's word); under the value when the row
///   has both (a night that uploads). `retry` is its R4 Retry, also a VoiceOver action on the row.
/// - `glyphInk`: the disc's glyph in `metricSleep` for the night (B §1.1); `valueUnit` after the value ("7:48" "h").
/// - `style`: `.tile` (its own `surface`), `.card` (inside a card: no surface, no sides, 12 above and below; the card draws the
///   hairlines between), `.dashed` (what is missing, the night without sleep: no fill, a dashed outline and disc, the glyph in
///   `textTertiary`, the title in `textSecondary`).
/// - `action`: a text action at the trailing edge ("Add sleep", `ryftLink`, 44 high), under the title from AX1, never broken.
///   The row is then a VoiceOver container: its sentence, then the action's button.
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
        /// Where the row came from, as outline capsules on a second meta line ("Garmin Connect", "RYFT"); empty draws none.
        /// In `spoken` as the caller words it ("Sources: Garmin Connect and RYFT, merged").
        var badges: [String] = []
        /// The state mark in the value's place (My Day); nil draws `value`. With a `value` too, the mark's word goes under it.
        var mark: ActivityStateMark.State?
        /// The disc's glyph: ink, or the night's `metricSleep`.
        var glyphInk: GlyphInk = .primary
        /// A unit after the value, in `caption` `textTertiary` ("h").
        var valueUnit: String?
    }

    /// The disc's glyph ink (B §1.1: sleep is violet, everything else ink).
    enum GlyphInk: Equatable, Sendable {
        case primary, sleep

        var color: Color {
            switch self {
            case .primary: return Theme.textPrimary
            case .sleep: return Theme.metricSleep
            }
        }
    }

    enum Accessory: Equatable {
        case none
        /// A `chevron.right`: Train's rows and a linked session (the board's activity rows have none, D5-22).
        case chevron
    }

    /// Where the row sits (S6).
    enum Style: Equatable, Sendable {
        /// On its own `surface`, radius 20: Strain, Train, History, My Day's screen.
        case tile
        /// Inside a card (My Day on Today): no surface (the card doesn't nest surfaces), no sides, 12 above and below.
        case card
        /// What is missing (the night without sleep): no fill, a dashed 1 pt outline at ink 12 %, a dashed disc.
        case dashed
    }

    /// A text action at the row's trailing edge ("Add sleep").
    struct Action {
        let title: Text
        let identifier: String
        let perform: () -> Void
    }

    let content: Content
    var accessory: Accessory
    var style: Style
    /// The state mark's Retry (R4); nil offers none.
    var retry: (() -> Void)?
    var action: Action?

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var valueSize: CGFloat = ActivityListRowSpec.valueSize

    init(content: Content, accessory: Accessory = .none, style: Style = .tile, retry: (() -> Void)? = nil,
         action: Action? = nil) {
        self.content = content
        self.accessory = accessory
        self.style = style
        self.retry = retry
        self.action = action
    }

    /// From AX1 the value, the mark and the action go under the text.
    private var stacks: Bool { typeSize.isAccessibilitySize }
    /// A row with badges hangs from its top.
    private var hangs: Bool { !content.badges.isEmpty }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: ActivityListRowSpec.radius, style: .continuous) }

    var body: some View {
        HStack(alignment: hangs ? .top : .center, spacing: ActivityListRowSpec.spacing) {
            disc
            text
                .frame(maxWidth: .infinity, alignment: .leading)
            if !stacks {
                if content.showsValue {
                    valueSlot.padding(.top, hangs ? ActivityListRowSpec.valueTopInset : 0)
                }
                if let action { actionButton(action) }
            }
            if accessory == .chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: ActivityListRowSpec.chevronSize, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, hangs ? ActivityListRowSpec.chevronTopInset : 0)
            }
        }
        .padding(.horizontal, style == .card ? 0 : ActivityListRowSpec.sidePadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, minHeight: ActivityListRowSpec.minHeight, alignment: .leading)
        .background { surface }
        .contentShape(style == .card ? AnyShape(Rectangle()) : AnyShape(shape))
        .modifier(ActivityListRowAccessibility(spoken: content.spoken, isContainer: action != nil, retry: retry))
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .card: return ActivityListRowSpec.cardVerticalPadding
        case .tile, .dashed: return hangs ? ActivityListRowSpec.badgedVerticalPadding : ActivityListRowSpec.verticalPadding
        }
    }

    @ViewBuilder private var surface: some View {
        switch style {
        case .tile:
            shape.fill(Theme.surface)
        case .card:
            Color.clear
        case .dashed:
            shape.strokeBorder(Theme.textPrimary.opacity(ActivityListRowSpec.dashedOutlineOpacity),
                               style: StrokeStyle(lineWidth: Theme.Metrics.hairline,
                                                  dash: [ActivityListRowSpec.outlineDash, ActivityListRowSpec.outlineDash]))
        }
    }

    // MARK: the parts

    /// `IconDisc`, or, where it has no style for it yet (a tinted glyph, a dashed ring), the same disc from its numbers.
    @ViewBuilder private var disc: some View {
        if style == .dashed {
            RowDisc(systemImage: content.systemImage, ink: Theme.textTertiary, dashed: true)
        } else if content.glyphInk != .primary, !content.filledDisc {
            RowDisc(systemImage: content.systemImage, ink: content.glyphInk.color, dashed: false)
        } else {
            IconDisc(systemImage: content.systemImage, style: content.filledDisc ? .filled : .outline)
        }
    }

    /// The title, the meta, the badges; from AX1 the value (or mark) and the action under them.
    private var text: some View {
        VStack(alignment: .leading, spacing: ActivityListRowSpec.metaGap) {
            Text(verbatim: content.title)
                .font(.ryft(.callout))
                .foregroundStyle(style == .dashed ? Theme.textSecondary : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let meta = content.meta {
                Text(verbatim: meta)
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if hangs {
                SourceBadgeRow(titles: content.badges)
                    .padding(.top, ActivityListRowSpec.badgesGap - ActivityListRowSpec.metaGap)
            }
            if stacks {
                if content.showsValue {
                    valueSlot.padding(.top, ActivityListRowSpec.stackedValueGap - ActivityListRowSpec.metaGap)
                }
                if let action { actionButton(action) }
            }
        }
    }

    /// The value (with its unit or caption), the state mark, or both: the value, then the mark's word under it.
    @ViewBuilder private var valueSlot: some View {
        if let mark = content.mark {
            VStack(alignment: stacks ? .leading : .trailing, spacing: ActivityStateMarkSpec.wordGap) {
                if content.value != nil { value }
                ActivityStateMark(state: mark, retry: retry, alignment: stacks ? .leading : .trailing,
                                  showsNumber: content.value == nil)
            }
        } else {
            value
        }
    }

    /// The number, and its caption under it (beside it from AX1, where the value is under the meta).
    @ViewBuilder private var value: some View {
        if let caption = content.valueCaption {
            if stacks {
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
        } else if let unit = content.valueUnit {
            HStack(alignment: .firstTextBaseline, spacing: ActivityListRowSpec.unitGap) {
                number
                Text(verbatim: unit)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize()
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

    /// "Add sleep": `ryftLink` (callout, ink, underlined, 44 × 44), one line however large the text.
    private func actionButton(_ action: Action) -> some View {
        Button(action: action.perform) { action.title.fixedSize() }
            .ryftLink()
            .accessibilityIdentifier(action.identifier)
    }
}

/// The disc where `IconDisc` has no style for it: the glyph in `ink` (the night's `metricSleep`, the missing night's
/// `textTertiary`), the ring dashed for what is missing. `IconDisc`'s numbers: 36, a 1 pt ring at ink 16 %, a 16 pt Light glyph.
private struct RowDisc: View {
    let systemImage: String
    let ink: Color
    let dashed: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: IconDisc.glyphSize, weight: .light))
            .foregroundStyle(ink)
            .frame(width: IconDisc.regularDiameter, height: IconDisc.regularDiameter)
            .overlay {
                Circle().strokeBorder(Theme.textPrimary.opacity(IconDisc.ringOpacity),
                                      style: StrokeStyle(lineWidth: IconDisc.ringWidth,
                                                         dash: dashed ? [ActivityListRowSpec.discDash, ActivityListRowSpec.discDash] : []))
            }
            .accessibilityHidden(true)
    }
}

/// One element with the row's sentence (and Retry as its action); with a trailing action a container: the drawn words, then
/// the action's button.
private struct ActivityListRowAccessibility: ViewModifier {
    let spoken: String
    let isContainer: Bool
    let retry: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if isContainer {
            // Its children speak: the words, then the action's button.
            content.accessibilityElement(children: .contain)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: spoken))
                .accessibilityActions {
                    if let retry {
                        Button(String(localized: "Retry", comment: "My Day: send a failed upload again."), action: retry)
                    }
                }
        }
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

    /// My Day's (T6B.6): the night with its badge, a merged run with its strain, a state mark, an upload under a value.
    static let myDay: [ActivityListRow.Content] = [
        .init(systemImage: "bed.double.fill", title: "Sleep", meta: "10:50 PM–7:00 AM · 7h 48m", value: "7:48",
              spoken: "Sleep, 10:50 PM to 7:00 AM, 7 hours, 48 minutes, Source: Apple Health", badges: ["Apple Health"],
              glyphInk: .sleep, valueUnit: "h"),
        .init(systemImage: "figure.run", title: "Running", meta: "6:40 AM–7:32 AM · 48m · 5.2 mi", value: nil,
              spoken: "Running, 6:40 AM to 7:32 AM, 48 minutes, 5.2 miles, Strain 10.6, Sources: Garmin Connect and RYFT, merged",
              badges: ["Garmin Connect", "RYFT"], mark: .scored(10.6)),
        .init(systemImage: "figure.walk", title: "Walk", meta: "12:15 PM–12:50 PM · 35m · 2.9 km", value: nil,
              spoken: "Walk, 12:15 PM to 12:50 PM, 35 minutes, 2.9 kilometres, Strain pending, Source: Apple Health",
              badges: ["Apple Health"], mark: .strainPending),
        .init(systemImage: "bed.double.fill", title: "Sleep", meta: "11:00 PM–7:00 AM · 8h 00m", value: "8:00",
              spoken: "Sleep, 11:00 PM to 7:00 AM, 8 hours, Uploading, Source: Added by you", badges: ["Added by you"],
              mark: .uploading(lastStrain: nil), glyphInk: .sleep, valueUnit: "h"),
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

/// S6: tiles with badges and marks, the same in a card, and the dashed missing night with its action.
private struct ActivityListRowMyDayPreviewList: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(ActivityListRowPreview.myDay.indices, id: \.self) { i in
                ActivityListRow(content: ActivityListRowPreview.myDay[i], accessory: .chevron)
            }
            ActivityListRow(content: .init(systemImage: "bed.double.fill", title: "No sleep recorded", meta: nil, value: nil,
                                           spoken: "No sleep recorded", showsValue: false),
                            style: .dashed, action: .init(title: Text(verbatim: "Add sleep"), identifier: "preview.addSleep") {})
            Card {
                VStack(spacing: 0) {
                    ForEach(ActivityListRowPreview.myDay.prefix(2).indices, id: \.self) { i in
                        if i > 0 { Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline) }
                        ActivityListRow(content: ActivityListRowPreview.myDay[i], style: .card)
                    }
                }
            }
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

#Preview("ActivityListRow · My Day", traits: .sizeThatFitsLayout) {
    DarkPreview { ActivityListRowMyDayPreviewList() }
}

#Preview("ActivityListRow · My Day · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { ActivityListRowMyDayPreviewList() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
