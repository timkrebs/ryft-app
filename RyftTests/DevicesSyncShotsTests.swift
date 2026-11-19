import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes Devices & sync, the tracker detail and picker, Check sync and Sync details (Nocturne PR 6 C2, drafts c-05 … c-09b)
/// as 3x PNGs, whole pages (`PagedWindowShot`), at the default size and at AX3 when `DEVICES_SHOTS_DIR` is set; otherwise does
/// nothing. Run it with `TEST_RUNNER_DEVICES_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/DevicesSyncShotsTests
/// test-without-building`, before and after a change, and compare. Drawn from a real window (`drawHierarchy`); for comparing,
/// not a golden-file test. Synthetic data only (Alex Doe), US English.
@MainActor
@Suite("C2: Devices & sync pages, shots", .serialized)
struct DevicesSyncShotsTests {
    @Test(arguments: Self.names)
    func writeScreen(_ name: String) async throws {
        guard let dir = ProcessInfo.processInfo.environment["DEVICES_SHOTS_DIR"] else { return }
        for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                           ("ax3", .accessibility3, .accessibilityExtraLarge)] {
            let (graph, view) = Self.screen(name)
            try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: typeSize, category: category,
                                       view) { w in
                try await w.settle()
                let image = try await PagedWindowShot.image(w)
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/c2-\(name)-\(size).png"))
            }
            graph.tearDown()
        }
    }

    nonisolated static let names = ["devices", "devices-none", "devices-offline", "tracker-detail", "picker", "check-sync",
                                    "check-sync-running", "check-sync-offline", "sync-details", "sync-details-offline"]

    private static func screen(_ name: String) -> (MockDevicesStates.Graph, AnyView) {
        let english = Locale(identifier: "en_US")
        func page(_ graph: MockDevicesStates.Graph, _ view: some View) -> (MockDevicesStates.Graph, AnyView) {
            (graph, AnyView(view.previewEnvironment(graph.state).environment(\.locale, english)))
        }
        switch name {
        case "devices":
            let g = MockDevicesStates.graph(later: ["oura"])
            return page(g, NavigationStack { DevicesAndSyncView(model: g.devices) })
        case "devices-none":
            let g = MockDevicesStates.graph(trackers: [], checkedAgo: nil)
            return page(g, NavigationStack { DevicesAndSyncView(model: g.devices) })
        case "devices-offline":
            let g = MockDevicesStates.graph(demo: false, online: false, sources: .loaded(ago: 7_200))
            return page(g, NavigationStack { DevicesAndSyncView(model: g.devices) })
        case "tracker-detail":
            let g = MockDevicesStates.graph(trackers: ["garmin"])
            return page(g, NavigationStack { TrackerDetailView(tracker: MockData.tracker("garmin"), model: g.devices) {} })
        case "picker":
            let g = MockDevicesStates.graph()
            return page(g, TrackerPickerSheet(model: g.devices))
        case "check-sync", "check-sync-running":
            let g = MockDevicesStates.graph(trackers: ["garmin"])
            let check = g.check(.garminSleepOff)
            MockDevicesStates.staged(check, name == "check-sync" ? .done : .running, scenario: .garminSleepOff)
            return page(g, NavigationStack { TrackerCheckView(model: check) })
        case "check-sync-offline":
            let g = MockDevicesStates.graph(demo: false, online: false, trackers: ["garmin"])
            let check = g.check(.garmin)
            MockDevicesStates.staged(check, .done, scenario: .garmin)
            return page(g, NavigationStack { TrackerCheckView(model: check) })
        case "sync-details":
            let g = MockDevicesStates.graph(demo: false)
            return page(g, NavigationStack { SyncDetailsView(model: g.details) })
        default:
            let g = MockDevicesStates.graph(demo: false, online: false, lastSync: 3 * 3_600)
            return page(g, NavigationStack { SyncDetailsView(model: g.details) })
        }
    }
}
