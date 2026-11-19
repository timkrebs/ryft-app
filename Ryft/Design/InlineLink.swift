// Links (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-1.4): ink, underlined at 50 %. The ink is the body text's, so
// colour alone would not mark a link (17.35 against `textSecondary`'s 6.95 is 2.5:1, under WCAG 1.4.1's 3:1): the underline
// does. One look for a link on its own line (`ryftLink()`) and a link inside a sentence (`InlineLink.styled`).
import SwiftUI

enum InlineLink {
    /// The underline: `textPrimary` at 50 %.
    static let underlineOpacity = 0.5
    /// A link on its own line is at least 44 × 44 (`Theme.Metrics.minHitTarget`).
    static let minTarget = Theme.Metrics.minHitTarget
    /// A standalone link while pressed, and disabled (the whole control, as the pills).
    static let pressedOpacity = 0.6, disabledOpacity = 0.35

    static var ink: Color { Theme.textPrimary }
    static var underline: Text.LineStyle { Text.LineStyle(pattern: .solid, color: Theme.textPrimary.opacity(underlineOpacity)) }

    /// `text` with every link run (`[words](url)`) in the link ink and underlined; the rest keeps the caller's style. As
    /// `Text(InlineLink.styled(…))` a tap goes through the environment's `openURL` (so `safariSheet` keeps it in the app),
    /// and VoiceOver's Links rotor reaches each link.
    static func styled(_ text: AttributedString) -> AttributedString {
        var styled = text
        for range in text.runs.filter({ $0.link != nil }).map(\.range) {
            styled[range].swiftUI.foregroundColor = ink
            styled[range].swiftUI.underlineStyle = underline
        }
        return styled
    }
}

extension View {
    /// A text control on its own line: apply to a `Button` or a `Link`. Callout, `textPrimary`, underlined at 50 %, at least
    /// 44 × 44 and all of it tappable; pressed 60 %, disabled 35 %.
    func ryftLink() -> some View {
        buttonStyle(RyftLinkButtonStyle())
    }
}

private struct RyftLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RyftLinkLabel(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct RyftLinkLabel<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .font(.ryft(.callout))
            .foregroundStyle(InlineLink.ink)
            .underline(true, pattern: .solid, color: InlineLink.ink.opacity(InlineLink.underlineOpacity))
            .frame(minWidth: InlineLink.minTarget, minHeight: InlineLink.minTarget)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (isPressed ? InlineLink.pressedOpacity : 1) : InlineLink.disabledOpacity)
    }
}

// MARK: previews (dark only; verbatim: the screens own the strings)

private struct InlineLinkPreviewBoard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {} label: { Text(verbatim: "Forgot password?") }
                .ryftLink()
            Button {} label: { Text(verbatim: "Use another email") }
                .ryftLink()
                .disabled(true)
            Text(InlineLink.styled(Self.sentence))
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
            Text(InlineLink.styled(Self.sentence))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.neutralTileRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Markdown without the catalog (the preview's words are not the app's).
    static let sentence = (try? AttributedString(markdown: "By creating an account you agree to the [Terms](https://example.com/terms) "
                                                     + "and the [Privacy Policy](https://example.com/privacy).")) ?? AttributedString()
}

#Preview("InlineLink", traits: .sizeThatFitsLayout) {
    DarkPreview { InlineLinkPreviewBoard() }
}

#Preview("InlineLink · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { InlineLinkPreviewBoard() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
