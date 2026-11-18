import SwiftUI

/// "What do you wear?" from Devices & sync: the same tiles; Done saves, Cancel leaves the choice as it was.
struct TrackerPickerSheet: View {
    let model: DevicesViewModel
    @State private var picked: [String]
    @Environment(\.dismiss) private var dismiss

    init(model: DevicesViewModel) {
        self.model = model
        _picked = State(initialValue: model.selection.trackers)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Pick your watch, band or ring. RYFT then shows how to get its data into Apple Health.")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TrackerPickerGrid(catalog: model.catalog, picked: $picked)
                    Text("RYFT only uses this to show you setup steps and to check that your data arrives.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text("What do you wear?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { SheetTitle(text: "What do you wear?") }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.save(picked)
                        dismiss()
                    }
                    .accessibilityIdentifier("wear.done")
                }
            }
        }
    }
}

#Preview("Tracker picker sheet · dark") { devicesScreenPreview(sheet: true) }
