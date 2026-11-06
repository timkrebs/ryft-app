import SwiftUI

/// What a warning or an error line carries where hue no longer can (ADR 0015): a glyph before the text. Decorative for
/// VoiceOver, because the text says it. Put it right after the `Text`, so the `.font` and `.foregroundStyle` that follow
/// reach the glyph too.
enum NoticeGlyph: String {
    case warning = "exclamationmark.triangle"
    case error = "exclamationmark.circle"
}

extension View {
    /// With the warning glyph when `isOn`. The structure stays, so a line that starts or stops warning doesn't lose its state.
    func warningLine(_ isOn: Bool = true) -> some View { noticeLine(isOn ? .warning : nil) }

    func errorLine() -> some View { noticeLine(.error) }

    private func noticeLine(_ glyph: NoticeGlyph?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let glyph {
                Image(systemName: glyph.rawValue).accessibilityHidden(true)
            }
            self
        }
    }
}

#Preview("Notice lines", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "A warning that wraps onto a second line at a large text size, with its glyph on the first.")
                .warningLine()
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textPrimary)
            Text(verbatim: "A quiet line, no glyph").warningLine(false).font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
            Text(verbatim: "An error").errorLine().font(.ryft(.callout)).foregroundStyle(Theme.textPrimary)
            StatRow(title: "Sleep debt", value: "1h 05m", warns: true)
        }
    }
}

#Preview("Notice lines · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "A warning at a large text size").warningLine().font(.ryft(.caption)).foregroundStyle(Theme.textPrimary)
            StatRow(title: "Sleep debt", value: "1h 05m", warns: true)
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
