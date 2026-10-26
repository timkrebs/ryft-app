import SwiftUI

/// One imported workout's exercises and sets, read-only (ui.md §8.1): "1  60 kg × 10". Skipped sets aren't sent, so
/// they're counted at the end; a clock change is named in words, never with file text.
struct ImportSessionDetailSheet: View {
    let preview: ImportSessionPreview
    /// Exercise names by id: the library's and the new custom ones.
    let names: [UUID: String]
    let zone: TimeZone

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                    Text(verbatim: ImportPreviewText.counts(preview))
                        .font(.ryft(.callout))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    if let note = preview.clockChange {
                        ImportNoteLine(systemImage: "clock.badge.exclamationmark", text: String(localized: note.message))
                    }
                    ForEach(preview.session?.exercises ?? []) { exercise in
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(verbatim: names[exercise.exerciseId] ?? "")
                                    .font(.ryft(.headline))
                                    .foregroundStyle(Theme.textPrimary)
                                ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                                    HStack(spacing: 14) {
                                        Text(verbatim: "\(index + 1)")
                                            .foregroundStyle(Theme.textTertiary)
                                            .frame(minWidth: 20, alignment: .leading)
                                        Text(verbatim: SetText.short(set))
                                            .foregroundStyle(Theme.textPrimary)
                                    }
                                    .font(.ryft(.body))
                                    .monospacedDigit()
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                    if preview.skippedSetCount > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(preview.skippedSetCount) sets skipped",
                                 comment: "Training import, step 5: sets with no weight or reps.")
                                .font(.ryft(.callout))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                            Text("Skipped · no weight or reps", comment: "Training import, step 5: why a set is skipped.")
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(ImportPreviewText.dayAndTitle(preview, zone: zone))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }
}

#Preview("Session detail · dark") {
    let build = ImportMockData.build()
    let names = Dictionary(MockTrain.exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    return ImportSessionDetailSheet(preview: build.sessions[1], names: names, zone: ImportMockData.zone)
        .preferredColorScheme(.dark)
}

#Preview("Session detail · light") {
    let build = ImportMockData.build()
    let names = Dictionary(MockTrain.exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    return ImportSessionDetailSheet(preview: build.sessions[5], names: names, zone: ImportMockData.zone)
        .preferredColorScheme(.light)
}
