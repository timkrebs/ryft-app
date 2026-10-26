import SwiftUI

/// Step 2's counts (ui.md §5): the source, then "1 plan · 2 days · 12 exercises", then "10 workouts · 2 Mar to 27 Apr
/// 2026". Each figure drops out at 0. One VoiceOver element with the whole sentence.
struct ImportSummaryCard: View {
    let summary: ImportSummary
    let zone: TimeZone

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Alpha Progression export", comment: "Training import, step 2: the source, named factually.")
                        .ryftLabelStyle()
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                if let plans = ImportSummaryText.plans(summary) {
                    Text(verbatim: plans)
                        .font(.ryft(.metric))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let workouts = ImportSummaryText.workouts(summary, zone: zone, spoken: false) {
                    Text(verbatim: workouts)
                        .font(.ryft(summary.plans == 0 ? .metric : .callout))
                        .monospacedDigit()
                        .foregroundStyle(summary.plans == 0 ? Theme.textPrimary : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        guard summary.plans > 0 else { return nil }
        var parts = [String(localized: "\(summary.plans) plans", comment: "Training import: a count of plans.")]
        if summary.days > 0 { parts.append(String(localized: "\(summary.days) days", comment: "Training import: a count of plan days.")) }
        if summary.exercises > 0 {
            parts.append(String(localized: "\(summary.exercises) exercises"))
        }
        return parts.joined(separator: " · ")
    }

    static func workouts(_ summary: ImportSummary, zone: TimeZone, spoken: Bool) -> String? {
        guard summary.workouts > 0 else { return nil }
        let count = String(localized: "\(summary.workouts) workouts", comment: "Training import: a count of workouts.")
        guard let first = summary.firstDay, let last = summary.lastDay else { return count }
        let range = ImportText.range(first, last, zone: zone, spoken: spoken)
        return spoken
            ? String(localized: "\(count) from \(range)", comment: "Training import, VoiceOver: 12 workouts from 8 June to 5 July 2026.")
            : "\(count) · \(range)"
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
    SchemePair {
        VStack(spacing: 12) {
            ImportSummaryCard(summary: ImportSummary(ImportMockData.bundle(ImportMockData.plans)
                .merging(ImportMockData.bundle(ImportMockData.workouts, file: 1))), zone: ImportMockData.zone)
            ImportSummaryCard(summary: ImportSummary(ImportMockData.bundle(ImportMockData.plans)), zone: ImportMockData.zone)
            ImportSummaryCard(summary: ImportSummary(ImportMockData.bundle(ImportMockData.workouts)), zone: ImportMockData.zone)
        }
    }
}

#Preview("Summary card · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        ImportSummaryCard(summary: ImportSummary(ImportMockData.bundle(ImportMockData.plans)
            .merging(ImportMockData.bundle(ImportMockData.workouts, file: 1))), zone: ImportMockData.zone)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
