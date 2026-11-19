import SwiftUI

/// Why a night's need is what it is, as numbers (`DayDetail.sleep.need`): `base + strain + debt − nap credit = total`.
/// Computed once, so the tile, the card's footer, the sentence and VoiceOver say the same thing. Durations are clocks
/// ("7:30", "+0:20", "−0:25"), as Nocturne's numerals and totals are (design.md §P4-4); VoiceOver hears them in words.
struct SleepNeedBreakdown: Equatable {
    struct Term: Identifiable, Equatable {
        enum Kind: String { case base, strain, debt, nap }
        let kind: Kind
        let minutes: Int
        var id: Kind { kind }

        var title: String {
            switch kind {
            case .base: return String(localized: "Baseline")
            case .strain: return String(localized: "Strain")
            case .debt: return String(localized: "Sleep debt")
            case .nap: return String(localized: "Nap credit")
            }
        }

        /// "7:30", "+0:20", "−0:25" (a real minus).
        var signed: String {
            switch kind {
            case .base: return Fmt.clock(minutes: minutes)
            case .strain, .debt: return "+" + Fmt.clock(minutes: minutes)
            case .nap: return Fmt.clock(minutes: -minutes)
            }
        }

        /// The term as VoiceOver reads it, one element: "Baseline, 7 hours 30 minutes", "Strain, plus 20 minutes",
        /// "Nap credit, minus 25 minutes".
        var spoken: String {
            let amount = Fmt.spokenDuration(minutes: minutes)
            switch kind {
            case .base: return "\(title), \(amount)"
            case .strain, .debt:
                return String(localized: "\(title), plus \(amount)",
                              comment: "VoiceOver: a top-up of the night's sleep need, e.g. \"Strain, plus 20 minutes\". 1: the term, 2: the time.")
            case .nap:
                return String(localized: "\(title), minus \(amount)",
                              comment: "VoiceOver: the nap credit taken off the night's sleep need, \"Nap credit, minus 25 minutes\". 1: the term, 2: the time.")
            }
        }
    }

    let total: Int
    /// Base first, then the top-ups and the credit that aren't zero.
    let terms: [Term]

    init(_ need: SleepNeed) {
        total = need.total
        terms = [Term(kind: .base, minutes: need.base)]
            + [Term(kind: .strain, minutes: need.strain), Term(kind: .debt, minutes: need.debt),
               Term(kind: .nap, minutes: need.napCredit)].filter { $0.minutes > 0 }
    }

    func minutes(_ kind: Term.Kind) -> Int { terms.first { $0.kind == kind }?.minutes ?? 0 }

    /// "You needed 8:18: 7:30 baseline, +0:20 for yesterday's strain, +0:28 of debt."
    var sentence: String { sentence(Fmt.clock(minutes:)) }

    /// The sentence as VoiceOver reads it: "You needed 8 hours 18 minutes: 7 hours 30 minutes baseline, +20 minutes for
    /// yesterday's strain, …" (a clock would be read as a time of day).
    var spokenSentence: String { sentence { Fmt.spokenDuration(minutes: $0 ?? 0) } }

    private func sentence(_ duration: (Int?) -> String) -> String {
        var parts = [String(localized: "\(duration(minutes(.base))) baseline")]
        if minutes(.strain) > 0 {
            parts.append(String(localized: "+\(duration(minutes(.strain))) for yesterday's strain"))
        }
        if minutes(.debt) > 0 { parts.append(String(localized: "+\(duration(minutes(.debt))) of debt")) }
        if minutes(.nap) > 0 { parts.append(String(localized: "−\(duration(minutes(.nap))) for your nap")) }
        let list = parts.formatted(.list(type: .and, width: .narrow))
        return String(localized: "You needed \(duration(total)): \(list).")
    }
}

/// The sleep need sheet's tile (Nocturne, PR 6 C §4.12, D6C-13): one sleep glow tile (`hypnogram` kind: 168 high at least,
/// radius 28), "How it adds up" and the total on its head row, 14 below it one tick row per term, 9 apart, all on one scale
/// (the total lights 30 ticks), in ink: one tile, one colour, the legend in words. The rows keep one tick column, or all
/// stack (PR 5's one-column rule, `ZoneBlock`). VoiceOver: the tile is a container; the head row is one element, and each
/// term's ticks are one value ("Strain, plus 20 minutes").
struct SleepNeedBar: View {
    let need: SleepNeed
    /// Previews and tests; `nil` follows the system.
    var reduceTransparency: Bool?

    /// The head row → the first tick row.
    nonisolated static let headGap: CGFloat = 14

    private var breakdown: SleepNeedBreakdown { SleepNeedBreakdown(need) }

    var body: some View {
        let b = breakdown
        GlowTile(Theme.metricSleep, kind: .hypnogram, reduceTransparency: reduceTransparency) {
            VStack(alignment: .leading, spacing: Self.headGap) {
                head(b)
                ZoneBlock(zones: b.terms.map { term in
                              ZoneBlock.Zone(label: Text(verbatim: term.title), minutes: Double(term.minutes),
                                             value: Text(verbatim: term.signed), accessibilityLabel: Text(verbatim: term.spoken))
                          },
                          scaleMax: Double(max(b.total, 1)),
                          accessibilityLabel: Self.title)
            }
        }
        .accessibilityIdentifier("sleepNeed.tile")
    }

    private func head(_ b: SleepNeedBreakdown) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Metrics.itemSpacing) {
            Self.title.ryftGlowLabelStyle()
            Spacer(minLength: 0)
            Text(verbatim: Fmt.clock(minutes: b.total))
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.title)
        .accessibilityValue(Text(verbatim: Fmt.spokenDuration(minutes: b.total)))
        .accessibilityAddTraits(.isHeader)
    }

    static var title: Text { Text("How it adds up", comment: "Sleep need sheet: the head of the tile that lists the need's terms.") }
}

// MARK: - previews (dark only)

#Preview("Sleep need tile", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 24) {
            SleepNeedBar(need: MockSleepNeedStates.need)
            SleepNeedBar(need: MockSleepNeedStates.needWithNap)
        }
    }
}

#Preview("Sleep need tile · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        SleepNeedBar(need: MockSleepNeedStates.needWithNap)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
