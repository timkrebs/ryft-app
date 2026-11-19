import SwiftUI

/// One imported workout's exercises and sets, read-only (ui.md §8.1): "1  60 kg × 10". Skipped sets aren't sent, so
/// they're counted at the end; a clock change is named in words, never with file text. Look (PR 6 C §4.14): a sheet's own
/// page (`SubpageScaffold`, `isSheet`) with Close; the counts, then a grouped card per exercise with a row per set.
struct ImportSessionDetailSheet: View {
    let preview: ImportSessionPreview
    /// Exercise names by id: the library's and the new custom ones.
    let names: [UUID: String]
    let zone: TimeZone

    var body: some View {
        NavigationStack {
            SubpageScaffold(Text(verbatim: ImportPreviewText.dayAndTitle(preview, zone: zone)), navigation: .close(), isSheet: true) {
                VStack(alignment: .leading, spacing: ImportLayout.blockSpacing) {
                    VStack(alignment: .leading, spacing: ImportLayout.lineGap) {
                        Text(verbatim: ImportPreviewText.counts(preview))
                            .font(.ryft(.callout))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                        if let note = preview.clockChange {
                            ImportNoteLine(systemImage: "clock.badge.exclamationmark", text: String(localized: note.message))
                        }
                    }
                    ForEach(preview.session?.exercises ?? []) { exercise in
                        GroupedCard(Text(verbatim: names[exercise.exerciseId] ?? "")) {
                            ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                                GroupedRow.value(Text(verbatim: "\(index + 1)"), value: Text(verbatim: SetText.short(set)))
                            }
                        }
                    }
                    if preview.skippedSetCount > 0 {
                        VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                            Text("\(preview.skippedSetCount) sets skipped",
                                 comment: "Training import, step 5: sets with no weight or reps.")
                                .font(.ryft(.callout))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                            Text("Skipped · no weight or reps", comment: "Training import, step 5: why a set is skipped.")
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

#Preview("Session detail") {
    let build = ImportMockData.build()
    let names = Dictionary(MockTrain.exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    return Theme.background.ignoresSafeArea().sheet(isPresented: .constant(true)) {
        ImportSessionDetailSheet(preview: build.sessions[1], names: names, zone: ImportMockData.zone)
            .presentedRoot()
    }
    .preferredColorScheme(.dark)
}
