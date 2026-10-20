import SwiftUI

/// Why a night's need is what it is, as numbers (`DayDetail.sleep.need`):
/// `base + strain + debt − nap credit = total`. Computed once, so the bar,
/// the sentence and VoiceOver say the same thing.
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
            case .debt: return String(localized: "Debt")
            case .nap: return String(localized: "Nap credit")
            }
        }

        /// "7h 40m", "+37m", "−25m".
        var signed: String {
            switch kind {
            case .base: return Fmt.duration(minutes: minutes)
            case .strain, .debt: return "+" + Fmt.duration(minutes: minutes)
            case .nap: return Fmt.duration(minutes: -minutes)
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

    /// "You needed 8h 58m: 7h 40m baseline, +37m for yesterday's strain, +41m of debt."
    var sentence: String {
        var parts = [String(localized: "\(Fmt.duration(minutes: minutes(.base))) baseline")]
        if minutes(.strain) > 0 {
            parts.append(String(localized: "+\(Fmt.duration(minutes: minutes(.strain))) for yesterday's strain"))
        }
        if minutes(.debt) > 0 { parts.append(String(localized: "+\(Fmt.duration(minutes: minutes(.debt))) of debt")) }
        if minutes(.nap) > 0 { parts.append(String(localized: "−\(Fmt.duration(minutes: minutes(.nap))) for your nap")) }
        let list = parts.formatted(.list(type: .and, width: .narrow))
        return String(localized: "You needed \(Fmt.duration(minutes: total)): \(list).")
    }
}

/// The need as one segmented bar: baseline, strain and debt top-ups side by
/// side, the nap credit as a dashed segment taken off the end; the four
/// numbers labelled underneath, the sentence below them.
struct SleepNeedBar: View {
    let need: SleepNeed
    @Environment(\.dynamicTypeSize) private var typeSize

    private var breakdown: SleepNeedBreakdown { SleepNeedBreakdown(need) }

    private func color(_ kind: SleepNeedBreakdown.Term.Kind) -> Color {
        switch kind {
        case .base: return Theme.metricSleep
        case .strain: return Theme.metricStrain
        case .debt: return Theme.warning
        case .nap: return Theme.textTertiary
        }
    }

    var body: some View {
        let b = breakdown
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sleep need").ryftLabelStyle()
                Spacer()
                Text(Fmt.duration(minutes: b.total))
                    .font(.ryft(.headline))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            bar(b)
            legend(b)
            Text(b.sentence)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep need"))
        .accessibilityValue(Text(b.sentence))
    }

    /// Widths are minutes over the gross need (before the credit), so the
    /// dashed nap segment sits inside the bar where it's taken off.
    private func bar(_ b: SleepNeedBreakdown) -> some View {
        let gross = Double(max(1, b.minutes(.base) + b.minutes(.strain) + b.minutes(.debt)))
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(b.terms.filter { $0.kind != .nap }) { t in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(t.kind))
                            .frame(width: max(2, w * Double(t.minutes) / gross - 2))
                    }
                }
                if b.minutes(.nap) > 0 {
                    let napWidth = w * Double(b.minutes(.nap)) / gross
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.surface.opacity(0.7))
                        .overlay(RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Theme.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .frame(width: napWidth)
                        .offset(x: w - napWidth)
                }
            }
        }
        .frame(height: 12)
    }

    private func legend(_ b: SleepNeedBreakdown) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        return layout {
            ForEach(b.terms) { t in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle().fill(color(t.kind)).frame(width: 6, height: 6)
                        Text(t.title).font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
                    }
                    Text(t.signed)
                        .font(.ryft(.callout))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }
}

#Preview("Sleep need", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 24) {
            SleepNeedBar(need: SleepNeed(base: 460, strain: 37, debt: 41, napCredit: 0, total: 538))
            SleepNeedBar(need: SleepNeed(base: 460, strain: 24, debt: 12, napCredit: 35, total: 461))
        }
    }
}
