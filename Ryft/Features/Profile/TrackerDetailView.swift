import SwiftUI

/// One tracker's card as a page (Nocturne PR 6 C2, §4.4, draft c-06), pushed from Devices & sync or the root of Today's
/// calibration sheet: the subpage header with the card's title, then the catalog's card (`TrackerSetupCard`, restyled in T6.0).
struct TrackerDetailView: View {
    let tracker: Tracker
    let model: DevicesViewModel
    var placement: DevicesPagePlacement = .pushed
    /// Just my iPhone: "Add a tracker" opens the picker.
    let addTracker: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(tracker: Tracker, model: DevicesViewModel, placement: DevicesPagePlacement = .pushed,
         addTracker: @escaping () -> Void) {
        self.tracker = tracker
        self.model = model
        self.placement = placement
        self.addTracker = addTracker
    }

    var body: some View {
        SubpageScaffold(Text(verbatim: tracker.cardTitle), navigation: placement.navigation, isSheet: placement.isSheet) {
            TrackerSetupCard(tracker: tracker,
                             later: TrackerSelectionStore.needsSetup(tracker) ? { model.selection.markLater(tracker.id) } : nil,
                             addTracker: tracker.isJustIPhone ? {
                                 dismiss()
                                 addTracker()
                             } : nil)
        }
        .devicesPagePlacement(placement)
    }
}

// Previews only: `MockDevicesStates` is a debug type, and a Release build has no previews.
#if DEBUG
#Preview("Tracker detail · Garmin") {
    let g = MockDevicesStates.graph(trackers: ["garmin", "oura"])
    NavigationStack { TrackerDetailView(tracker: MockData.tracker("garmin"), model: g.devices) {} }
        .previewEnvironment(g.state)
}

#Preview("Tracker detail · Just my iPhone") {
    let g = MockDevicesStates.graph(trackers: ["iphone"])
    NavigationStack { TrackerDetailView(tracker: MockData.tracker("iphone"), model: g.devices) {} }
        .previewEnvironment(g.state)
}

#Preview("Tracker detail · AX3") {
    let g = MockDevicesStates.graph(trackers: ["garmin"])
    NavigationStack { TrackerDetailView(tracker: MockData.tracker("garmin"), model: g.devices) {} }
        .previewEnvironment(g.state)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
