// A summary or subtitle line made of parts (R2 V1 S6; PR 6 B §12, C §2.9): History's week totals, the pushed headers'
// subtitles, My Day's summary, Profile's "where it comes from" details, the training import's counts. At the accessibility
// sizes a joined line wraps and leaves its "·" dangling at the end of a line ("25 workouts ·" / "last 90 days"); an activity
// row's meta already stacks its parts there (`ActivityListRow.metaLines`), and these lines now do the same.
import SwiftUI

/// "1 session · 7,500 kg · load 85" at the default sizes; from AX1 "1 session", "7,500 kg", "load 85", one per line.
///
/// - Below AX1 the parts share one line, `joined`: as My Day's and Strain's meta join them (`MyDayText.join`: a part never
///   breaks inside, the "·" ends its line) unless the caller passes the line it already draws (the import's counts, a
///   sentence from the strings catalog).
/// - From AX1 each part has its own line, without separators: nothing dangles, and a long part wraps inside its own line.
/// - Without parts (a sentence instead of counts, the import's "All 12 matched…") `joined` is drawn at every size.
/// - VoiceOver hears one element at every size: the joined line, the parts in order, or the caller's `spoken` words (the
///   import's count line says its total first). Inside a container that speaks for its children it is read as before.
///
/// The font, ink, digits and alignment are the caller's: `PartsLine(parts).font(.ryft(.caption)).monospacedDigit()`.
struct PartsLine: View {
    private let parts: [String]
    private let joined: String
    private let spoken: String

    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - joined: the one-line form as drawn at the default sizes; nil: `MyDayText.join(parts)`.
    ///   - spoken: what VoiceOver hears; nil: the one-line form.
    init(_ parts: [String], joined: String? = nil, spoken: String? = nil) {
        self.parts = parts
        self.joined = joined ?? MyDayText.join(parts)
        self.spoken = spoken ?? self.joined
    }

    var body: some View {
        Text(verbatim: Self.text(parts, joined: joined, stacked: typeSize.isAccessibilitySize))
            .accessibilityLabel(Text(verbatim: spoken))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// What is drawn: the one-line form (`joined`, or `MyDayText.join(parts)`), or, `stacked`, the parts one per line with
    /// no separator, empty ones left out (without any, the one-line form).
    static func text(_ parts: [String], joined: String? = nil, stacked: Bool) -> String {
        let shown = parts.filter { !$0.isEmpty }
        guard stacked, !shown.isEmpty else { return joined ?? MyDayText.join(parts) }
        return shown.joined(separator: "\n")
    }
}

// MARK: - previews (dark only; verbatim: the screens own the strings)

private struct PartsLinePreviewList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PartsLine(["1 session", "7,500 kg", "load 85"])
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
            PartsLine(["4 activities", "2h 13m", "6.8 mi"])
                .font(.ryft(.label))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
            PartsLine(["Default", "add your birth year for an estimate"],
                      joined: "Default · add your birth year for an estimate")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(width: 350, alignment: .leading)
        .padding(20)
    }
}

#Preview("PartsLine", traits: .sizeThatFitsLayout) {
    DarkPreview { PartsLinePreviewList() }
}

#Preview("PartsLine · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { PartsLinePreviewList() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
