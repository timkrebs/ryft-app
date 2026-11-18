import SwiftUI

/// The night's sleep need, term by term (`base + strain + debt − nap credit`), and the
/// baseline (the part that's yours to set) one tap away.
struct SleepNeedSheet: View {
    /// `nil` for nights scored before the breakdown existed.
    let need: SleepNeed?
    let total: String
    let editor: BodySettingsEditor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let need {
                        Card { SleepNeedBar(need: need) }
                    } else {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                StatRow(title: "Sleep need", value: total)
                                Text("This night was scored before RYFT broke the need down.")
                                    .font(.ryft(.caption))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    Text("Your baseline is yours to set. The top-ups follow yesterday's strain and your sleep debt; a nap lowers the next night's need.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Card {
                        NavigationLink {
                            BaselineSleepNeedForm(editor: editor)
                        } label: {
                            SettingRowLabel(title: "Change baseline", value: editor.sleepBaseText,
                                            detail: editor.sleepBaseSourceText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sleepNeed.changeBaseline")
                    }
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text("Sleep need"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}
