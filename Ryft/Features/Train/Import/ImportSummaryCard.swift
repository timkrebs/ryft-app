import SwiftUI

/// Step 2's counts (ui.md §5): the source, then "1 plan · 2 days · 12 exercises", then "10 workouts · 2 Mar to 27 Apr
/// 2026" (from AX1 one figure per line, `PartsLine`). Each figure drops out at 0. One VoiceOver element with the whole
/// sentence. Look (PR 6 C §4.14, c-23b): the
/// surface tile, the source 13 pt `textTertiary` with a check, the counts at `.metric`, the workouts 15 pt `textSecondary`.
struct ImportSummaryCard: View {
    let summary: ImportSummary
    let zone: TimeZone

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: ImportLayout.lineGap) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Alpha Progression export", comment: "Training import, step 2: the source, named factually.")
                        .ryftLabelStyle(Theme.textTertiary)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: GroupedListSpec.checkmarkSize, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                if let plans = ImportSummaryText.planParts(summary) {
                    PartsLine(plans, joined: ImportSummaryText.plans(summary))
                        .font(.ryft(.metric))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                if let workouts = ImportSummaryText.workoutParts(summary, zone: zone) {
                    PartsLine(workouts, joined: ImportSummaryText.workouts(summary, zone: zone, spoken: false))
                        .font(.ryft(summary.plans == 0 ? .metric : .callout))
                        .monospacedDigit()
                        .foregroundStyle(summary.plans == 0 ? Theme.textPrimary : Theme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ImportSummaryText.sentence(summary, zone: zone)))
        .accessibilityIdentifier("import.summary")
    }
}

/// The summary's words (ui.md §11): plural counts joined with " · ", never one string with two plurals.
enum ImportSummaryText {
    static func plans(_ summary: ImportSummary) -> String? {
        planParts(summary)?.joined(separator: " · ")
    }

    /// "1 plan", "2 days", "12 exercises": the plans line's figures, the ones above 0.
    static func planParts(_ summary: ImportSummary) -> [String]? {
        guard summary.plans > 0 else { return nil }
        var parts = [String(localized: "\(summary.plans) plans", comment: "Training import: a count of plans.")]
        if summary.days > 0 { parts.append(String(localized: "\(summary.days) days", comment: "Training import: a count of plan days.")) }
        if summary.exercises > 0 {
            parts.append(String(localized: "\(summary.exercises) exercises"))
        }
        return parts
    }

    static func workouts(_ summary: ImportSummary, zone: TimeZone, spoken: Bool) -> String? {
        guard summary.workouts > 0 else { return nil }
        guard spoken else { return workoutParts(summary, zone: zone)?.joined(separator: " · ") }
        let count = String(localized: "\(summary.workouts) workouts", comment: "Training import: a count of workouts.")
        guard let first = summary.firstDay, let last = summary.lastDay else { return count }
        let range = ImportDateText.range(first, last, zone: zone, spoken: true)
        return String(localized: "\(count) from \(range)", comment: "Training import, VoiceOver: 12 workouts from 8 June to 5 July 2026.")
    }

    /// "10 workouts", "2 Mar to 27 Apr 2026": the workouts line as drawn, in parts.
    static func workoutParts(_ summary: ImportSummary, zone: TimeZone) -> [String]? {
        guard summary.workouts > 0 else { return nil }
        let count = String(localized: "\(summary.workouts) workouts", comment: "Training import: a count of workouts.")
        guard let first = summary.firstDay, let last = summary.lastDay else { return [count] }
        return [count, ImportDateText.range(first, last, zone: zone, spoken: false)]
    }

    /// "Alpha Progression export. 1 plan, 2 days, 12 exercises. 10 workouts from 2 March to 27 April 2026."
    static func sentence(_ summary: ImportSummary, zone: TimeZone) -> String {
        let source = String(localized: "Alpha Progression export", comment: "Training import, step 2: the source, named factually.")
        let plans = Self.plans(summary)?.replacingOccurrences(of: " · ", with: ", ")
        let workouts = Self.workouts(summary, zone: zone, spoken: true)
        return ([source] + [plans, workouts].compactMap { $0 }).joined(separator: ". ") + "."
    }
}

#Preview("Summary card", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            ImportSummaryCard(summary: ImportSummary(ImportMockData.bundle(ImportMockData.plans)
                .merging(ImportMockData.bundle(ImportMockData.workouts, file: 1))), zone: ImportMockData.zone)
            ImportSummaryCard(summary: ImportSummary(ImportMockData.bundle(ImportMockData.plans)), zone: ImportMockData.zone)
            ImportSummaryCard(summary: ImportSummary(ImportMockData.bundle(ImportMockData.workouts)), zone: ImportMockData.zone)
        }
    }
}

#Preview("Summary card · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        ImportSummaryCard(summary: ImportSummary(ImportMockData.bundle(ImportMockData.plans)
            .merging(ImportMockData.bundle(ImportMockData.workouts, file: 1))), zone: ImportMockData.zone)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
