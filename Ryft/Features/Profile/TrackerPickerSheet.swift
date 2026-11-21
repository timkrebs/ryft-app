import SwiftUI

/// "What do you wear?" from Devices & sync (Nocturne PR 6 C2, §4.4, draft c-07): a sheet's page with Close, the same tiles as
/// onboarding, and Done pinned under them. Done saves; Close leaves the choice as it was.
struct TrackerPickerSheet: View {
    let model: DevicesViewModel
    @State private var picked: [String]
    @Environment(\.dismiss) private var dismiss

    init(model: DevicesViewModel) {
        self.model = model
        _picked = State(initialValue: model.selection.trackers)
    }

    var body: some View {
        SubpageScaffold(Text("What do you wear?"), navigation: .close(), isSheet: true) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                Text("Pick your watch, tracker or ring. RYFT then shows how to get its data into Apple Health.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                TrackerPickerGrid(catalog: model.catalog, picked: $picked)
                GroupFooter(Text("RYFT only uses this to show you setup steps and to check that your data arrives."))
            }
        }
        .pinnedBar {
            PillButton(Text("Done"), systemImage: PillButton.Icon.confirm) {
                model.save(picked)
                dismiss()
            }
            .accessibilityIdentifier("wear.done")
        }
    }
}

// Previews only: `MockDevicesStates` is a debug type, and a Release build has no previews.
#if DEBUG
#Preview("Tracker picker") {
    let g = MockDevicesStates.graph(trackers: ["garmin", "oura"])
    TrackerPickerSheet(model: g.devices)
        .previewEnvironment(g.state)
}

#Preview("Tracker picker · AX3") {
    let g = MockDevicesStates.graph(trackers: ["garmin"])
    TrackerPickerSheet(model: g.devices)
        .previewEnvironment(g.state)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
