// The grouped list (Nocturne, docs/work/2026-11-16-nocturne/build-plan.md §2; design.md §P5-6.1–6.2; PR 6 B §1.3 S4, C §2.2,
// A's `ListGroup`): a group title, a `surface` card of rows with a hairline between them, and an optional footer. One row type
// with seven kinds, so Profile's list, its subpages and every form in PR 6 read as the same list. It replaces `ProfileSection`,
// `SettingRow`, `SettingRowLabel` and `LinkRow` (their callers move in the screen tickets).
import SwiftUI

/// The grouped list's numbers (a separate, non-generic type: `GroupedCard` is generic).
enum GroupedListSpec {
    /// The card: `surface`, radius 22 (`Theme.Metrics.neutralTileRadius`), no border, no shadow.
    static let cardRadius = Theme.Metrics.neutralTileRadius
    /// A row: at least 46 high (`Theme.Metrics.listRowHeight`), 16 at the sides, 12 between its parts.
    static let rowMinHeight = Theme.Metrics.listRowHeight
    static let rowInset: CGFloat = 16
    static let rowSpacing = Theme.Metrics.itemSpacing
    /// Above and below the row's text and its icon disc: a one-line row stays 46, a row with a detail line is about 58, a row
    /// with an icon disc 56 (the Train section's rows, §P5-3.5).
    static let textPadding: CGFloat = 10
    /// The detail line, 2 under the title.
    static let detailGap: CGFloat = 2
    /// Group title → card, card → footer (8 each), and one group's last line → the next title (18, the caller's spacing).
    static let titleGap: CGFloat = 8, footerGap: CGFloat = 8, groupSpacing: CGFloat = 18
    /// The chevron and the ↗ are decoration (the title and the row's role say what it is): ink at 35 %, about 3:1. An action
    /// row's glyph is ink at 55 %.
    static let accessoryOpacity = 0.35, actionGlyphOpacity = 0.55
    /// Point sizes: the chevron and the ↗ 12 semibold, the checkmark 14 medium, an action's glyph 15.
    static let chevronSize: CGFloat = 12, checkmarkSize: CGFloat = 14, glyphSize: CGFloat = 15
    /// A pressed row fills at the circle button's 8 %; a disabled one is at 35 % as every control.
    static let pressedFillOpacity = CircleButton.pressedFillOpacity, disabledOpacity = 0.35
}

extension EnvironmentValues {
    /// Set by `GroupedCard` for its content: a row draws the hairline above itself.
    @Entry var isInGroupedCard = false
}

extension View {
    /// The hairline above a row in a `GroupedCard`: 1 pt `separator`, inset 16 at both ends, drawn just outside the row's top
    /// edge, so the card's clip hides the first row's and the others sit between two rows. `GroupedRow` has it; a row the
    /// caller builds itself (a stepper, two chips) adds it. Outside a card it draws nothing.
    func groupedRowHairline() -> some View {
        modifier(GroupedRowHairline())
    }
}

private struct GroupedRowHairline: ViewModifier {
    @Environment(\.isInGroupedCard) private var isInGroupedCard

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isInGroupedCard {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: Theme.Metrics.hairline)
                    .padding(.horizontal, GroupedListSpec.rowInset)
                    .offset(y: -Theme.Metrics.hairline)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - group

/// A group's title: 13 pt (`.label`) in `textTertiary`, flush with the card, a header for VoiceOver's rotor; capped at AX3.
/// An optional text action sits at the end of its line ("Edit"), as `ryftLink()`, its 44 pt target reaching past the line
/// without moving the card.
struct GroupTitle: View {
    struct Action {
        let title: Text
        let perform: () -> Void

        init(_ title: Text, perform: @escaping () -> Void) {
            self.title = title
            self.perform = perform
        }
    }

    private let title: Text
    private let action: Action?

    init(_ title: Text, action: Action? = nil) {
        self.title = title
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GroupedListSpec.rowSpacing) {
            title
                .font(.ryft(.label))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let action {
                Button(action: action.perform) { action.title }
                    .ryftLink()
                    // The link is 44 high; the line keeps the title's height.
                    .padding(.vertical, -GroupedListSpec.titleActionOverhang)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

extension GroupedListSpec {
    /// How far a title action's 44 pt box reaches above and below the title's line.
    static let titleActionOverhang: CGFloat = 12
}

/// A footer under a card: 12 pt (`.caption`) in `textTertiary`, flush left, any number of lines.
struct GroupFooter: View {
    private let text: Text

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        text
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A group: the title, 8 below it the card (`surface`, radius 22) with the rows, 8 below that the footer. The rows are the
/// caller's (`GroupedRow`, or its own with `groupedRowHairline()`); the card draws the hairlines between them. Groups stack
/// `GroupedListSpec.groupSpacing` (18) apart, which is the caller's `VStack` spacing.
struct GroupedCard<Content: View, Footer: View>: View {
    private let title: GroupTitle?
    private let content: Content
    private let footer: Footer?

    /// Any footer: an `InlineMessage` under the card, a status line, a footer with a link.
    init(_ title: GroupTitle?, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                title.padding(.bottom, GroupedListSpec.titleGap)
            }
            let shape = RoundedRectangle(cornerRadius: GroupedListSpec.cardRadius, style: .continuous)
            VStack(alignment: .leading, spacing: 0) { content }
                .environment(\.isInGroupedCard, true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: shape)
                .clipShape(shape)
            if let footer {
                footer.padding(.top, GroupedListSpec.footerGap)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension GroupedCard where Footer == GroupFooter {
    /// A group with a plain title and an optional one-sentence footer.
    init(_ title: Text? = nil, footer: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title.map { GroupTitle($0) }
        self.content = content()
        self.footer = footer.map(GroupFooter.init)
    }

    /// A group whose title carries an action ("Edit").
    init(title: GroupTitle, footer: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self.footer = footer.map(GroupFooter.init)
    }
}

// MARK: - row

/// One row of a grouped card. Every kind has the same height (≥ 46), padding (0 / 16) and title (15 pt `textPrimary`, never
/// truncated: it wraps and the row grows); an optional leading `IconDisc` (36) and a detail line (12 pt `textTertiary`, 2 below
/// the title). From AX1 a value goes under the title. The kinds:
///
/// | Kind | Trailing | VoiceOver |
/// |---|---|---|
/// | `value` | the value, 15 pt `textTertiary` | one element: the title, the value (and the detail) as its value |
/// | `push` | an optional value, a chevron | a button; the caller's hint |
/// | `linkOut` | ↗ | a link, hint "Opens outside the app" unless the caller says where |
/// | `action` | an optional glyph at 55 %, a spinner while busy | a button; "In progress" while busy, and taps do nothing |
/// | `select` | a checkmark on the chosen row | a button, `isSelected` on the chosen row |
/// | `toggle` | the `Toggle` (`.ryft` from the root) | the switch: label, on / off |
/// | `menu` | the current value, `chevron.up.chevron.down`; the row opens a `Menu` | a button: the title, the value |
/// | `destructive` | the title in `alert`, an optional glyph | a button; the dialog that follows says the rest |
/// | `custom` | the caller's view (a stepper, chips) | the title, then the caller's control |
struct GroupedRow: View {
    enum Kind: Equatable, Sendable {
        case value, push, linkOut, action, select, toggle, menu, destructive, custom
    }

    private enum Behaviour {
        case none
        case button(() -> Void)
        case navigation(AnyView)
        case url(URL)
        case toggle(Binding<Bool>)
        case menu(AnyView)
        case custom(AnyView)
    }

    let kind: Kind
    private let title: Text
    private let detail: Text?
    private let valueText: Text?
    private let icon: String?
    private let accessory: GroupedRowLabel.Accessory
    private let hint: Text?
    private let busy: Bool
    private let isSelected: Bool
    private let behaviour: Behaviour

    @Environment(\.openURL) private var openURL

    private init(kind: Kind, title: Text, detail: Text?, value: Text?, icon: String?, accessory: GroupedRowLabel.Accessory,
                 hint: Text?, busy: Bool = false, isSelected: Bool = false, behaviour: Behaviour) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.valueText = value
        self.icon = icon
        self.accessory = accessory
        self.hint = hint
        self.busy = busy
        self.isSelected = isSelected
        self.behaviour = behaviour
    }

    // One factory per kind (the kinds' closures would make initialisers ambiguous with a trailing closure).

    /// value: the title and a value, read as one element.
    static func value(_ title: Text, value: Text, detail: Text? = nil, icon: String? = nil) -> GroupedRow {
        GroupedRow(kind: .value, title: title, detail: detail, value: value, icon: icon, accessory: .none, hint: nil,
                   behaviour: .none)
    }

    /// push: a button that opens something (a sheet, a page the caller presents); an optional value before the chevron.
    static func push(_ title: Text, value: Text? = nil, detail: Text? = nil, icon: String? = nil, hint: Text? = nil,
                     action: @escaping () -> Void) -> GroupedRow {
        GroupedRow(kind: .push, title: title, detail: detail, value: value, icon: icon, accessory: .chevron, hint: hint,
                   behaviour: .button(action))
    }

    /// push: a `NavigationLink(value:)` to `route` (the stack's `navigationDestination(for:)` builds the page).
    static func push<Route: Hashable>(_ title: Text, value: Text? = nil, detail: Text? = nil, icon: String? = nil,
                                      hint: Text? = nil, route: Route) -> GroupedRow {
        let label = GroupedRowLabel(title, value: value, detail: detail, icon: icon, accessory: .chevron)
        return GroupedRow(kind: .push, title: title, detail: detail, value: value, icon: icon, accessory: .chevron, hint: hint,
                          behaviour: .navigation(AnyView(NavigationLink(value: route) { label })))
    }

    /// link-out: opens `url` through the environment's `openURL` (so an in-app Safari handler still catches it). `hint` says
    /// where it opens ("Opens Health"); without one, "Opens outside the app".
    static func linkOut(_ title: Text, detail: Text? = nil, icon: String? = nil, hint: Text? = nil, url: URL) -> GroupedRow {
        GroupedRow(kind: .linkOut, title: title, detail: detail, value: nil, icon: icon, accessory: .linkOut, hint: hint,
                   behaviour: .url(url))
    }

    /// action: a button that does something here ("Sync now", "Copy diagnostics"); `systemImage` its trailing glyph. While
    /// `busy` a spinner takes the glyph's place, taps do nothing and VoiceOver says "In progress".
    static func action(_ title: Text, detail: Text? = nil, icon: String? = nil, systemImage: String? = nil, busy: Bool = false,
                       action: @escaping () -> Void) -> GroupedRow {
        GroupedRow(kind: .action, title: title, detail: detail, value: nil, icon: icon,
                   accessory: busy ? .spinner : systemImage.map { .glyph($0) } ?? .none, hint: nil, busy: busy,
                   behaviour: .button(action))
    }

    /// select: one of a set; the chosen row has the checkmark and the selected trait.
    static func select(_ title: Text, detail: Text? = nil, icon: String? = nil, isSelected: Bool,
                       action: @escaping () -> Void) -> GroupedRow {
        GroupedRow(kind: .select, title: title, detail: detail, value: nil, icon: icon, accessory: .checkmark(isSelected),
                   hint: nil, isSelected: isSelected, behaviour: .button(action))
    }

    /// toggle: a `Toggle` with the title (and the detail) as its label. It takes the toggle style of its environment: the app
    /// root's `.ryft` (T5.1).
    static func toggle(_ title: Text, detail: Text? = nil, icon: String? = nil, isOn: Binding<Bool>) -> GroupedRow {
        GroupedRow(kind: .toggle, title: title, detail: detail, value: nil, icon: icon, accessory: .none, hint: nil,
                   behaviour: .toggle(isOn))
    }

    /// menu: the title, the current value and `chevron.up.chevron.down`; the whole row opens a `Menu` of the caller's items
    /// (buttons, or a `Picker` for a checkmark on the current one). §P5-6.2: birth year, session layout, hero numbers.
    static func menu<Items: View>(_ title: Text, value: Text, detail: Text? = nil, icon: String? = nil,
                                  @ViewBuilder items: () -> Items) -> GroupedRow {
        let entries = items()
        let label = GroupedRowLabel(title, value: value, detail: detail, icon: icon, accessory: .menu)
        return GroupedRow(kind: .menu, title: title, detail: detail, value: value, icon: icon, accessory: .menu, hint: nil,
                          behaviour: .menu(AnyView(Menu { entries } label: { label })))
    }

    /// destructive: the title in `alert` ("Delete account"), at the end of its group; the caller confirms with the system
    /// dialog. `systemImage`, when the spec gives the row a glyph, is drawn in `alert` too. Busy as `action`.
    static func destructive(_ title: Text, detail: Text? = nil, systemImage: String? = nil, busy: Bool = false,
                            action: @escaping () -> Void) -> GroupedRow {
        GroupedRow(kind: .destructive, title: title, detail: detail, value: nil, icon: nil,
                   accessory: busy ? .spinner : systemImage.map { .destructiveGlyph($0) } ?? .none, hint: nil, busy: busy,
                   behaviour: .button(action))
    }

    /// custom: the caller's trailing control (a `Menu`, a stepper, a date chip). The title stays a plain text before it; the
    /// control carries its own accessibility.
    static func custom<Trailing: View>(_ title: Text, detail: Text? = nil, icon: String? = nil,
                                       @ViewBuilder trailing: () -> Trailing) -> GroupedRow {
        GroupedRow(kind: .custom, title: title, detail: detail, value: nil, icon: icon, accessory: .none, hint: nil,
                   behaviour: .custom(AnyView(trailing())))
    }

    /// "Opens outside the app": a link-out row's hint when the caller gives none.
    static let linkOutHint = Text("Opens outside the app", comment: "VoiceOver hint of a row that opens a web page or another app.")
    /// A busy row's VoiceOver value (the pill's).
    static let busyValue = Text("In progress")

    var body: some View {
        content
            .groupedRowHairline()
    }

    @ViewBuilder private var content: some View {
        switch behaviour {
        case .none:
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(spokenValue)
        case .button(let action):
            Button {
                if !busy { action() }
            } label: {
                label
            }
            .buttonStyle(GroupedRowButtonStyle())
            .allowsHitTesting(!busy)
            .accessibilityLabel(title)
            .accessibilityValue(busy ? Self.busyValue : spokenValue)
            .accessibilityHint(hint ?? Text(verbatim: ""))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        case .navigation(let link):
            link
                .buttonStyle(GroupedRowButtonStyle())
                .accessibilityLabel(title)
                .accessibilityValue(spokenValue)
                .accessibilityHint(hint ?? Text(verbatim: ""))
        case .url(let url):
            Button {
                openURL(url)
            } label: {
                label
            }
            .buttonStyle(GroupedRowButtonStyle())
            .accessibilityLabel(title)
            .accessibilityValue(spokenValue)
            .accessibilityHint(hint ?? Self.linkOutHint)
            .accessibilityRemoveTraits(.isButton)
            .accessibilityAddTraits(.isLink)
        case .toggle(let isOn):
            Toggle(isOn: isOn) {
                GroupedRowText(title: title, detail: detail, value: nil, icon: icon, titleColor: Theme.textPrimary)
            }
            .padding(.horizontal, GroupedListSpec.rowInset)
            .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
        case .menu(let menu):
            menu
                .menuStyle(.button)
                .buttonStyle(GroupedRowButtonStyle())
                .accessibilityLabel(title)
                .accessibilityValue(spokenValue)
        case .custom(let trailing):
            GroupedRowLabel(title, detail: detail, icon: icon, trailing: trailing)
                .accessibilityElement(children: .contain)
        }
    }

    private var label: GroupedRowLabel {
        GroupedRowLabel(title, value: valueText, detail: detail, icon: icon, accessory: accessory,
                        titleColor: kind == .destructive ? Theme.alert : Theme.textPrimary)
    }

    /// The value and the detail, in that order, as VoiceOver reads them after the title.
    private var spokenValue: Text {
        switch (valueText, detail) {
        case let (value?, detail?): return value + Text(verbatim: ", ") + detail
        case let (value?, nil): return value
        case let (nil, detail?): return detail
        case (nil, nil): return Text(verbatim: "")
        }
    }
}

/// The row's press and disabled looks: the row fills at 8 % while pressed, the whole row is at 35 % when disabled.
private struct GroupedRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GroupedRowButtonBody(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct GroupedRowButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .background(Theme.textPrimary.opacity(isPressed ? GroupedListSpec.pressedFillOpacity : 0))
            .opacity(isEnabled ? 1 : GroupedListSpec.disabledOpacity)
    }
}

/// A row's look without its behaviour: the label of a `NavigationLink(destination:)`, a `Menu` or anything else the caller
/// wraps (`GroupedRow` uses it for its own kinds). It adds no accessibility of its own beyond its texts; the wrapper decides.
struct GroupedRowLabel: View {
    enum Accessory: Equatable {
        case none
        /// `chevron.right`, 12 pt semibold (it grows with the title's text size), ink 35 %.
        case chevron
        /// `arrow.up.right`, the same size and ink.
        case linkOut
        /// `chevron.up.chevron.down` (a menu row), the same size and ink.
        case menu
        /// `checkmark` 14 pt medium in `textPrimary` when `true`; the same space, empty, when `false`.
        case checkmark(Bool)
        /// An action's glyph, 15 pt, ink 55 %.
        case glyph(String)
        /// A destructive row's glyph, 15 pt, `alert`.
        case destructiveGlyph(String)
        /// A small spinner in `textSecondary` (busy).
        case spinner
    }

    private let title: Text
    private let value: Text?
    private let detail: Text?
    private let icon: String?
    private let accessory: Accessory
    private let titleColor: Color
    private let trailing: AnyView?

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The accessories grow with the title (`.callout`), as `Card`'s glyphs do: 12 pt at the default size.
    @ScaledMetric(relativeTo: .callout) private var glyphScale: CGFloat = 1

    init(_ title: Text, value: Text? = nil, detail: Text? = nil, icon: String? = nil, accessory: Accessory = .none,
         titleColor: Color = Theme.textPrimary) {
        self.title = title
        self.value = value
        self.detail = detail
        self.icon = icon
        self.accessory = accessory
        self.titleColor = titleColor
        self.trailing = nil
    }

    fileprivate init(_ title: Text, detail: Text?, icon: String?, trailing: AnyView) {
        self.title = title
        self.value = nil
        self.detail = detail
        self.icon = icon
        self.accessory = .none
        self.titleColor = Theme.textPrimary
        self.trailing = trailing
    }

    /// From AX1 the value goes under the title, where it has the whole line.
    private var stacksValue: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        HStack(alignment: .center, spacing: GroupedListSpec.rowSpacing) {
            GroupedRowText(title: title, detail: detail, value: stacksValue ? value : nil, icon: icon, titleColor: titleColor)
            if !stacksValue, let value {
                GroupedRowValue(text: value)
            }
            if let trailing {
                trailing
            }
            accessoryView
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var accessoryView: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            decoration("chevron.right", size: GroupedListSpec.chevronSize, weight: .semibold,
                       color: Theme.textPrimary.opacity(GroupedListSpec.accessoryOpacity))
        case .linkOut:
            decoration("arrow.up.right", size: GroupedListSpec.chevronSize, weight: .semibold,
                       color: Theme.textPrimary.opacity(GroupedListSpec.accessoryOpacity))
        case .menu:
            decoration("chevron.up.chevron.down", size: GroupedListSpec.chevronSize, weight: .semibold,
                       color: Theme.textPrimary.opacity(GroupedListSpec.accessoryOpacity))
        case .checkmark(let on):
            decoration("checkmark", size: GroupedListSpec.checkmarkSize, weight: .medium, color: Theme.textPrimary)
                .opacity(on ? 1 : 0)
        case .glyph(let name):
            decoration(name, size: GroupedListSpec.glyphSize, weight: .regular,
                       color: Theme.textPrimary.opacity(GroupedListSpec.actionGlyphOpacity))
        case .destructiveGlyph(let name):
            decoration(name, size: GroupedListSpec.glyphSize, weight: .regular, color: Theme.alert)
        case .spinner:
            ProgressView()
                .controlSize(.small)
                .tint(Theme.textSecondary)
                .accessibilityHidden(true)
        }
    }

    private func decoration(_ name: String, size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size * glyphScale, weight: weight))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// The leading part of a row: the icon disc, the title, the detail line and (from AX1) the value, 10 above and below.
private struct GroupedRowText: View {
    let title: Text
    let detail: Text?
    let value: Text?
    let icon: String?
    let titleColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: GroupedListSpec.rowSpacing) {
            if let icon {
                IconDisc(systemImage: icon)
            }
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                title
                    .font(.ryft(.callout))
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    detail
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let value {
                    GroupedRowValue(text: value)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, GroupedListSpec.textPadding)
    }
}

/// A row's value: 15 pt in `textTertiary` (4.54:1 on `surface`), tabular digits. A caller's `Text.foregroundStyle` wins (a
/// value that needs attention is `warning` with its words, §P5-6.3).
private struct GroupedRowValue: View {
    let text: Text

    var body: some View {
        text
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}
