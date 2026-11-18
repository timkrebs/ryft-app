import SwiftUI

/// One tracker's card, pushed from Devices & sync.
struct TrackerDetailView: View {
    let tracker: Tracker
    let model: DevicesViewModel
    /// Just my iPhone: "Add a tracker" opens the picker.
    let addTracker: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            TrackerSetupCard(tracker: tracker,
                             later: TrackerSelectionStore.needsSetup(tracker) ? { model.selection.markLater(tracker.id) } : nil,
                             addTracker: tracker.isJustIPhone ? {
                                 dismiss()
                                 addTracker()
                             } : nil)
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: tracker.cardTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A tracker's card or the picker sheet from Devices & sync, on mock data.
@MainActor
func devicesScreenPreview(sheet: Bool = false) -> some View {
    let state = AppState.preview(flags: [.devicesSetup: true])
    let model = DevicesViewModel(state: state, selection: TrackerSelectionStore(env: state.env))
    model.selection.stage(["garmin", "oura"])
    return Group {
        if sheet {
            TrackerPickerSheet(model: model)
        } else {
            NavigationStack { TrackerDetailView(tracker: MockData.tracker("garmin"), model: model) {} }
        }
    }
    .previewEnvironment(state)
}

#Preview("Tracker detail · dark") { devicesScreenPreview() }
