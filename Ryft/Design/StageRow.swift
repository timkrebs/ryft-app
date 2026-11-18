import SwiftUI

/// The sleep stages' tints in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-7.2, §P5-7.4): the sleep violet at 100 %
/// (Deep), 80 % (REM) and 62 % (Light, and a night without stages, "Asleep"); Awake is `textTertiary`. No blue. Over `surface`
/// they are 6.38 / 4.50 / 3.19:1 (graphics need 3), but neighbours are only 1.4 apart, so a stage is never told by its tint
/// alone: the order (Deep at the bottom, then Light, REM on top), the legend and the names carry it.
enum SleepStageTint {
    nonisolated static let deep = 1.0, rem = 0.80, light = 0.62, asleep = 0.62

    /// The violet's opacity for `stage`; `nil` for Awake (not violet).
    nonisolated static func opacity(_ stage: SleepStageKind) -> Double? {
        switch stage {
        case .deep: return deep
        case .rem: return rem
        case .light: return light
        case .awake: return nil
        }
    }

    /// `stage`'s colour; `nil` is a night without stages ("Asleep").
    static func color(_ stage: SleepStageKind?) -> Color {
        guard let stage else { return Theme.metricSleep.opacity(asleep) }
        return opacity(stage).map { Theme.metricSleep.opacity($0) } ?? Theme.textTertiary
    }
}

/// One stage of a night (Sleep → Day's stage card): a 10 pt swatch in the stage's tint, the stage's name, its duration and
/// share; under them the share as a bar in the same tint over a 6 % ink track. The name and the order say the stage, the tint
/// only repeats it. One VoiceOver element.
struct StageRow: View {
    let share: StageShare

    nonisolated static let swatch: CGFloat = 10, swatchRadius: CGFloat = 2
    /// The share bar: 4 high, 8 under the line, its track ink at 6 %.
    nonisolated static let barHeight: CGFloat = 4, barGap: CGFloat = 8, trackOpacity = 0.06

    var body: some View {
        VStack(alignment: .leading, spacing: Self.barGap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: Self.swatchRadius, style: .continuous)
                    .fill(SleepStageTint.color(share.stage))
                    .frame(width: Self.swatch, height: Self.swatch)
                Text(share.stage.title)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text(Fmt.duration(minutes: share.min))
                    .font(.ryft(.callout))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(Fmt.percent(share.pct))
                    .font(.ryft(.callout))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            ShareBar(fraction: Self.fraction(share.pct), tint: SleepStageTint.color(share.stage))
        }
        .accessibilityElement(children: .combine)
    }

    /// The share as 0…1 from the platform's percentage (0–100); 0 without one.
    nonisolated static func fraction(_ pct: Double?) -> Double {
        min(max((pct ?? 0) / 100, 0), 1)
    }

    private struct ShareBar: View {
        let fraction: Double
        let tint: Color

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.textPrimary.opacity(StageRow.trackOpacity))
                    Capsule().fill(tint).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: StageRow.barHeight)
            .accessibilityHidden(true)
        }
    }
}

#Preview("StageRow", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 14) {
            ForEach(MockData.todayDetail.sleep?.displayStages ?? []) { StageRow(share: $0) }
        }
    }
}

#Preview("StageRow · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 14) {
            ForEach(MockData.todayDetail.sleep?.displayStages ?? []) { StageRow(share: $0) }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
