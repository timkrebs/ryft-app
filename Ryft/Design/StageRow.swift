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
///
/// From AX1 the row stacks: the swatch and the name on one line, the duration and the share on the next, under the name (the
/// part 2 validation found "20%" broken into "20" / "%", "Awake" into "Awak" / "e" and "1h 35m" wrapped at AX5). A name, a
/// duration or a share never breaks or shrinks; if the duration and the share don't fit side by side, the share goes under
/// the duration.
struct StageRow: View {
    let share: StageShare

    nonisolated static let swatch: CGFloat = 10, swatchRadius: CGFloat = 2
    /// The swatch to the name, and so the stacked row's indent under the name.
    nonisolated static let swatchGap: CGFloat = 12
    /// The share bar: 4 high, 8 under the line, its track ink at 6 %.
    nonisolated static let barHeight: CGFloat = 4, barGap: CGFloat = 8, trackOpacity = 0.06
    /// The stacked row: the name's line to the duration's.
    nonisolated static let stackedLineGap: CGFloat = 4

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Self.barGap) {
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                HStack(spacing: Self.swatchGap) {
                    swatch
                    name
                    Spacer(minLength: 8)
                    duration
                    percent
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
            ShareBar(fraction: Self.fraction(share.pct), tint: SleepStageTint.color(share.stage))
        }
        .accessibilityElement(children: .combine)
    }

    /// From AX1: the name on its own line; the duration and the share under it, side by side while they fit.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: Self.stackedLineGap) {
            HStack(spacing: Self.swatchGap) {
                swatch
                name
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    duration
                    Spacer(minLength: 8)
                    percent
                }
                VStack(alignment: .leading, spacing: Self.stackedLineGap) {
                    duration
                    percent
                }
            }
            .padding(.leading, Self.swatch + Self.swatchGap)
        }
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: Self.swatchRadius, style: .continuous)
            .fill(SleepStageTint.color(share.stage))
            .frame(width: Self.swatch, height: Self.swatch)
    }

    private var name: some View {
        Text(share.stage.title)
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }

    private var duration: some View {
        Text(Fmt.duration(minutes: share.min))
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }

    private var percent: some View {
        Text(Fmt.percent(share.pct))
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .fixedSize()
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

/// The stage card at AX5 as Sleep draws it (`DarkPreview` is the screen's padding): each row stacked, nothing broken.
#Preview("StageRow · AX5") {
    DarkPreview {
        Card {
            VStack(spacing: 14) {
                ForEach(MockData.todayDetail.sleep?.displayStages ?? []) { StageRow(share: $0) }
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
