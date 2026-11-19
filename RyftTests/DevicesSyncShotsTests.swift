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
            let (graph, view) = await Self.screen(name)
            try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: typeSize, category: category,
                                       view) { w in
                try await w.settle()
                // In a sheet: the screen as it is (the paged shot scrolls the page under the sheet).
                let image = name.hasPrefix("in-sheet") ? Self.window(w) : try await PagedWindowShot.image(w)
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/c2-\(name)-\(size).png"))
            }
            graph.tearDown()
        }
    }

    nonisolated static let names = ["devices", "devices-none", "devices-offline", "tracker-detail", "picker", "check-sync",
                                    "check-sync-running", "check-sync-offline", "sync-details", "sync-details-offline",
                                    "sync-details-waiting", "in-sheet-root", "in-sheet-pushed", "in-sheet-pushed-without-inset"]

    private static func window(_ w: HostedWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
            w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
        }
    }

    private static func screen(_ name: String) async -> (MockDevicesStates.Graph, AnyView) {
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
        case "sync-details-waiting":
            // An activity saved, a workout held at the consent gate (a put and a complete), a report kept for later.
            let g = MockDevicesStates.graph(demo: false, reportsWaiting: 1)
            let end = g.env.clock.now()
            _ = g.env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900), end: end))
            g.train.gate = { write in write == .erasure ? nil : .gate(.consentRequired) }
            _ = await g.train.finish(SessionFactory.empty(in: g.store))
            return page(g, NavigationStack { SyncDetailsView(model: g.details) })
        case "in-sheet-root":
            // The sheet's root for reference: where a sheet's page starts.
            let g = MockDevicesStates.graph(trackers: ["garmin"])
            return page(g, Theme.background.ignoresSafeArea().sheet(isPresented: .constant(true)) {
                NavigationStack { DevicesAndSyncView(model: g.devices, placement: .sheet) }
            })
        case "in-sheet-pushed", "in-sheet-pushed-without-inset":
            // Today's calibration sheet: Devices & sync as the sheet's root, a tracker's card pushed from it. The second is
            // how a pushed page sat before `pushedInSheet` (for the comparison only).
            let g = MockDevicesStates.graph(trackers: ["garmin"])
            let pushed: DevicesPagePlacement = name == "in-sheet-pushed" ? DevicesPagePlacement.sheet.pushed : .pushed
            return page(g, Theme.background.ignoresSafeArea().sheet(isPresented: .constant(true)) {
                NavigationStack {
                    DevicesAndSyncView(model: g.devices, placement: .sheet)
                        .navigationDestination(isPresented: .constant(true)) {
                            TrackerDetailView(tracker: MockData.tracker("garmin"), model: g.devices, placement: pushed) {}
                        }
                }
            })
        default:
            let g = MockDevicesStates.graph(demo: false, online: false, lastSync: 3 * 3_600)
            return page(g, NavigationStack { SyncDetailsView(model: g.details) })
        }
    }
}
