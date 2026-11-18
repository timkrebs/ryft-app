// The pill button, the app's one button (Nocturne, docs/work/2026-11-16-nocturne/design.md §P2-4 and §P5-1.2; the compact
// size is design-pr6-b-train.md S1). Brief §2: "Pill-Buttons 52 hoch, primär hell mit dunklem Icon-Kreis, sekundär Outline".
import SwiftUI

/// The app's button. Three styles, two sizes, an optional busy state; the title is the accessibility label.
///
/// - `.primary`: a `textPrimary` fill, the title leading in `background`, and a 40 pt `background` circle with a glyph on the
///   trailing side (`systemImage`, `Icon.forward` when nil; `Icon` is §P5-1.2's table).
/// - `.secondary`: a 1 pt `textPrimary` outline at 20 %, the title centred in `textPrimary`, no icon.
/// - `.destructive`: a 1 pt `alert` outline at 70 % (3.47:1, a boundary's 3:1), the title centred in `alert` (6.09:1), no icon.
///   A destructive action that shares a row with a primary is never the primary.
///
/// `.regular` is at least 52 high and takes the full proposed width; the title scales and wraps, and the pill grows with it.
/// `.compact` (sheet commits, the live workout's Finish) is a 40 pt pill in a 44 pt tap box, as wide as its one-line title
/// plus 18 a side, with no icon circle; it never wraps. A caller that puts it beside other header items caps its type size
/// (`.dynamicTypeSize(...DynamicTypeSize.xxLarge)`) and adds `accessibilityShowsLargeContentViewer()`.
///
/// `busy`: a spinner in place of the primary's glyph, or in place of the other titles; the pill keeps its size and its look,
/// ignores taps, and VoiceOver reads the title with the value "In progress". Disabled (`.disabled(true)` from the caller)
/// dims the whole pill to 35 %.
///
/// The `async` initialisers run the action in a `Task` (`PrimaryButton`'s shape); the pill does not track it, so a caller
/// that must not run twice passes `busy` while it works.
struct PillButton: View {
    enum Style { case primary, secondary, destructive }

    enum Size { case regular, compact }

    /// The primary pill's circle glyph by what the button does (design.md §P5-1.2). Pass one only when it is not `forward`.
    enum Icon {
        /// Log in, Create account, Continue, Use the other account, a plan row's start.
        static let forward = "arrow.right"
        /// Save password, Agree and continue, Review and agree, Done, Save.
        static let confirm = "checkmark"
        /// Send reset link, Send.
        static let send = "arrow.up"
        /// Open Mail, Open Health, any link out of the app.
        static let linkOut = "arrow.up.right"
        /// Export data.
        static let download = "arrow.down"
        /// Start workout.
        static let start = "play.fill"
        /// Check again, Try again.
        static let retry = "arrow.clockwise"
    }

    /// 52: `Theme.Metrics.pillHeight`. The icon circle is a circle button's 40.
    static let minHeight = Theme.Metrics.pillHeight, iconCircle = Theme.Metrics.circleButton
    static let outlineOpacity = 0.20, disabledOpacity = 0.35
    /// Primary: the fill when pressed. Secondary: the fill when pressed.
    static let primaryPressedOpacity = 0.85, secondaryPressedFillOpacity = 0.08
    static let iconSize: CGFloat = 14
    /// Primary 20 leading / 6 trailing (the circle's inset), secondary 22 each side; 12 above and below the title.
    static let primaryLeading: CGFloat = 20, primaryTrailing: CGFloat = 6, secondaryHorizontal: CGFloat = 22
    static let titleVertical: CGFloat = 12

    /// The destructive outline: `alert` at 70 % over `background` is 3.47:1 (3.37 over `surface`), the 3:1 a boundary needs.
    static let destructiveOutlineOpacity = 0.70
    /// The destructive pill's fill when pressed: `alert` at 8 %, as the secondary's is `textPrimary` at 8 %.
    static let destructivePressedFillOpacity = 0.08

    /// `.compact`: a 40 pt visual (a circle button's) in a 44 pt tap box (`minHitTarget`), 18 pt sides.
    static let compactHeight = Theme.Metrics.circleButton, compactHitHeight = Theme.Metrics.minHitTarget
    static let compactHorizontal: CGFloat = 18
    /// Above and below the compact title: the pill stays 40 at the default size and grows once the line is taller than 24.
    static let compactTitleVertical: CGFloat = 8

    private enum Action {
        case sync(() -> Void)
        case async(() async -> Void)
    }

    private let title: Text
    private let style: Style
    private let size: Size
    private let systemImage: String
    private let busy: Bool
    private let action: Action

    /// The caller's `.disabled`, read before the pill disables itself while busy: only the caller's dims it.
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: Text, style: Style = .primary, size: Size = .regular, systemImage: String? = nil, busy: Bool = false,
         action: @escaping () -> Void) {
        self.init(title: title, style: style, size: size, systemImage: systemImage, busy: busy, action: .sync(action))
    }

    /// `action` runs in a `Task` on the main actor.
    init(_ title: Text, style: Style = .primary, size: Size = .regular, systemImage: String? = nil, busy: Bool = false,
         action: @escaping () async -> Void) {
        self.init(title: title, style: style, size: size, systemImage: systemImage, busy: busy, action: .async(action))
    }

    /// A title from outside the app (a tracker's app name from the catalog): shown as it is, never looked up or parsed.
    init(verbatim title: String, style: Style = .primary, size: Size = .regular, systemImage: String? = nil, busy: Bool = false,
         action: @escaping () -> Void) {
        self.init(title: Text(verbatim: title), style: style, size: size, systemImage: systemImage, busy: busy,
                  action: .sync(action))
    }

    /// A title from outside the app; `action` runs in a `Task` on the main actor.
    init(verbatim title: String, style: Style = .primary, size: Size = .regular, systemImage: String? = nil, busy: Bool = false,
         action: @escaping () async -> Void) {
        self.init(title: Text(verbatim: title), style: style, size: size, systemImage: systemImage, busy: busy,
                  action: .async(action))
    }

    private init(title: Text, style: Style, size: Size, systemImage: String?, busy: Bool, action: Action) {
        self.title = title
        self.style = style
        self.size = size
        self.systemImage = Self.glyph(systemImage)
        self.busy = busy
        self.action = action
    }

    /// The primary circle's glyph: the caller's, or `Icon.forward`.
    static func glyph(_ systemImage: String?) -> String { systemImage ?? Icon.forward }

    /// The title's colour, and the spinner's in place of a title.
    static func ink(_ style: Style) -> Color {
        switch style {
        case .primary: return Theme.background
        case .secondary: return Theme.textPrimary
        case .destructive: return Theme.alert
        }
    }

    var body: some View {
        Button(action: run) { label }
            .buttonStyle(PillButtonStyle(style: style, size: size, dimmed: !isEnabled))
            .disabled(busy)
            .accessibilityLabel(title)
            .accessibilityValue(busy ? Text("In progress") : Text(verbatim: ""))
    }

    private func run() {
        guard !busy else { return }
        switch action {
        case .sync(let action): action()
        case .async(let action): Task { await action() }
        }
    }

    @ViewBuilder private var label: some View {
        switch (size, style) {
        case (.regular, .primary): primaryLabel
        case (.regular, _): outlineLabel
        case (.compact, _): compactLabel
        }
    }

    private var primaryLabel: some View {
        HStack(spacing: Theme.Metrics.itemSpacing) {
            styledTitle(Self.ink(.primary))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.textPrimary)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: Self.iconSize, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(width: Self.iconCircle, height: Self.iconCircle)
            .background(Theme.background, in: Circle())
            .accessibilityHidden(true)
        }
        .padding(.leading, Self.primaryLeading)
        .padding(.trailing, Self.primaryTrailing)
    }

    /// Secondary and destructive: busy hides the title (it keeps its lines, so the pill keeps its height) under a spinner.
    private var outlineLabel: some View {
        styledTitle(Self.ink(style))
            .multilineTextAlignment(.center)
            .opacity(busy ? 0 : 1)
            .overlay { spinner(Self.ink(style), controlSize: .regular) }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Self.secondaryHorizontal)
    }

    /// One line, as wide as the title; busy hides the title under a spinner, so the width stays.
    private var compactLabel: some View {
        title
            .font(.ryft(.button))
            .foregroundStyle(Self.ink(style))
            .lineLimit(1)
            .fixedSize()
            .opacity(busy ? 0 : 1)
            .overlay { spinner(Self.ink(style), controlSize: .small) }
            .padding(.horizontal, Self.compactHorizontal)
            .padding(.vertical, Self.compactTitleVertical)
    }

    @ViewBuilder private func spinner(_ tint: Color, controlSize: ControlSize) -> some View {
        if busy {
            ProgressView()
                .controlSize(controlSize)
                .tint(tint)
                .accessibilityHidden(true)
        }
    }

    private func styledTitle(_ color: Color) -> some View {
        title
            .font(.ryft(.button))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Self.titleVertical)
    }
}

private struct PillButtonStyle: ButtonStyle {
    let style: PillButton.Style
    let size: PillButton.Size
    /// The caller disabled the pill (not the pill's own busy state): the whole pill at 35 %.
    let dimmed: Bool

    func makeBody(configuration: Configuration) -> some View {
        switch size {
        case .regular:
            // A capsule at 52 pt (radius 26 = half the height), but the corners stay 26 when the title wraps: a true
            // capsule's radius grows with the height and cuts the outer corners of the first and last lines at AX3.
            let shape = RoundedRectangle(cornerRadius: PillButton.minHeight / 2, style: .circular)
            configuration.label
                .frame(maxWidth: .infinity, minHeight: PillButton.minHeight)
                .background { fill(shape, pressed: configuration.isPressed) }
                .contentShape(shape)
                .opacity(dimmed ? PillButton.disabledOpacity : 1)
        case .compact:
            // The 40 pt pill, centred in a box at least 44 high that is all tappable. Always its own size: a row too narrow
            // for it must not squeeze the sides under the one-line title (the caller caps the type or stacks the row).
            let shape = RoundedRectangle(cornerRadius: PillButton.compactHeight / 2, style: .circular)
            configuration.label
                .frame(minWidth: PillButton.compactHitHeight, minHeight: PillButton.compactHeight)
                .background { fill(shape, pressed: configuration.isPressed) }
                .frame(minHeight: PillButton.compactHitHeight)
                .contentShape(Rectangle())
                .opacity(dimmed ? PillButton.disabledOpacity : 1)
                .fixedSize()
        }
    }

    @ViewBuilder private func fill(_ shape: RoundedRectangle, pressed: Bool) -> some View {
        switch style {
        case .primary:
            shape.fill(Theme.textPrimary.opacity(pressed ? PillButton.primaryPressedOpacity : 1))
        case .secondary:
            shape.fill(Theme.textPrimary.opacity(pressed ? PillButton.secondaryPressedFillOpacity : 0))
                .overlay {
                    shape.strokeBorder(Theme.textPrimary.opacity(PillButton.outlineOpacity), lineWidth: Theme.Metrics.hairline)
                }
        case .destructive:
            shape.fill(Theme.alert.opacity(pressed ? PillButton.destructivePressedFillOpacity : 0))
                .overlay {
                    shape.strokeBorder(Theme.alert.opacity(PillButton.destructiveOutlineOpacity), lineWidth: Theme.Metrics.hairline)
                }
        }
    }
}

// MARK: previews (dark only; the titles are verbatim: the screens own the strings)

/// Every style and state of the regular pill, then the icon table.
private struct PillButtonPreviewBoard: View {
    var body: some View {
        VStack(spacing: 12) {
            PillButton(Text(verbatim: "Continue")) {}
            PillButton(Text(verbatim: "Continue"), busy: true) {}
            PillButton(Text(verbatim: "Continue")) {}
                .disabled(true)
            PillButton(Text(verbatim: "Sync now"), style: .secondary) {}
            PillButton(Text(verbatim: "Sync now"), style: .secondary, busy: true) {}
            PillButton(Text(verbatim: "Sync now"), style: .secondary) {}
                .disabled(true)
            PillButton(Text(verbatim: "Delete account"), style: .destructive) {}
            PillButton(Text(verbatim: "Delete account"), style: .destructive, busy: true) {}
            PillButton(Text(verbatim: "Delete account"), style: .destructive) {}
                .disabled(true)
        }
    }
}

private struct PillButtonIconBoard: View {
    var body: some View {
        VStack(spacing: 12) {
            PillButton(Text(verbatim: "Save"), systemImage: PillButton.Icon.confirm) {}
            PillButton(Text(verbatim: "Send reset link"), systemImage: PillButton.Icon.send) {}
            PillButton(Text(verbatim: "Open Health"), systemImage: PillButton.Icon.linkOut) {}
            PillButton(Text(verbatim: "Export data"), systemImage: PillButton.Icon.download) {}
            PillButton(Text(verbatim: "Start workout"), systemImage: PillButton.Icon.start) {}
            PillButton(Text(verbatim: "Try again"), systemImage: PillButton.Icon.retry) {}
            HStack(spacing: 12) {
                PillButton(Text(verbatim: "Sync now"), style: .secondary) {}
                PillButton(Text(verbatim: "Full re-sync"), style: .destructive) {}
            }
        }
    }
}

/// The compact pill: primary, secondary, destructive, busy and disabled, at their content width; a row that no longer
/// fits stacks (the caller's job: the pill never shrinks).
private struct PillButtonCompactBoard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(busy: false)
            row(busy: true)
            row(busy: false)
                .disabled(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(busy: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { pills(busy: busy) }
            VStack(alignment: .leading, spacing: 8) { pills(busy: busy) }
        }
    }

    @ViewBuilder private func pills(busy: Bool) -> some View {
        PillButton(Text(verbatim: "Save"), size: .compact, busy: busy) {}
        PillButton(Text(verbatim: "Finish"), style: .secondary, size: .compact, busy: busy) {}
        PillButton(Text(verbatim: "Delete"), style: .destructive, size: .compact, busy: busy) {}
    }
}

#Preview("PillButton", traits: .sizeThatFitsLayout) {
    DarkPreview { PillButtonPreviewBoard() }
}

#Preview("PillButton · icons", traits: .sizeThatFitsLayout) {
    DarkPreview { PillButtonIconBoard() }
}

#Preview("PillButton · compact", traits: .sizeThatFitsLayout) {
    DarkPreview { PillButtonCompactBoard() }
}

#Preview("PillButton · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            PillButton(Text(verbatim: "Connect Apple Health to start syncing")) {}
            PillButton(Text(verbatim: "Connect Apple Health to start syncing"), busy: true) {}
            PillButton(Text(verbatim: "Connect Apple Health to start syncing"), style: .secondary) {}
            PillButton(Text(verbatim: "Connect Apple Health to start syncing"), style: .secondary, busy: true) {}
            PillButton(Text(verbatim: "Delete account and every night"), style: .destructive) {}
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("PillButton · compact · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { PillButtonCompactBoard() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
