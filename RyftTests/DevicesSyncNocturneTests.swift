import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Devices & sync, the tracker picker, Check sync and Sync details in Nocturne (PR 6 C2, design-pr6-c-settings.md §6 tests 6–8,
/// 15, 17): the pages' decisions as values, the offline-first rule (2026-11-19: nothing claims a freshness it doesn't have),
/// and the hosted pages at 390 pt, default and AX3. Synthetic data (`MockDevicesStates`), US English.
@MainActor
@Suite("C2: Devices & sync pages", .serialized)
struct DevicesSyncNocturneTests {
    // MARK: decisions

    @Test("Seen in Apple Health: fresh, loading, not loaded, or an earlier load's with its time")
    func sourcesFreshness() {
        typealias F = SourcesFreshness
        let at = Date(timeIntervalSince1970: 1_792_400_000)
        #expect(F.decide(hasList: true, isDemo: false, isOnline: true, fetchedAt: at, failures: 0) == .fresh)
        #expect(F.decide(hasList: true, isDemo: false, isOnline: false, fetchedAt: at, failures: 0) == .stale(at), "offline")
        #expect(F.decide(hasList: true, isDemo: false, isOnline: true, fetchedAt: at, failures: 2) == .stale(at), "loads fail")
        #expect(F.decide(hasList: true, isDemo: false, isOnline: false, fetchedAt: nil, failures: 0) == .stale(nil))
        #expect(F.decide(hasList: false, isDemo: false, isOnline: true, fetchedAt: nil, failures: 0) == .loading)
        #expect(F.decide(hasList: false, isDemo: false, isOnline: false, fetchedAt: nil, failures: 0) == .notLoaded)
        #expect(F.decide(hasList: false, isDemo: false, isOnline: true, fetchedAt: nil, failures: 3) == .notLoaded)
        #expect(F.decide(hasList: true, isDemo: true, isOnline: false, fetchedAt: nil, failures: 5) == .fresh, "demo data")
    }

    @Test("Check sync's one primary: Allow access while not asked, busy while running, disabled without Apple Health")
    func checkSyncPrimary() {
        #expect(CheckSyncPrimary.decide(.notAsked) == .allowAccess)
        #expect(CheckSyncPrimary.decide(.running) == .checkAgain(busy: true, enabled: true))
        #expect(CheckSyncPrimary.decide(.unavailable) == .checkAgain(busy: false, enabled: false))
        for phase: TrackerCheckModel.Phase in [.idle, .done, .locked, .failed] {
            #expect(CheckSyncPrimary.decide(phase) == .checkAgain(busy: false, enabled: true), "\(phase)")
        }
    }

    @Test("Check rows: each kind its own symbol; ok in ink, a fix amber, none teal")
    func checkRowKinds() {
        let kinds: [CheckRow.Kind] = [.waiting, .checking, .ok, .expected, .neutral, .late, .fix]
        #expect(Set(kinds.map(\.symbol)).count == kinds.count)
        #expect(CheckRow.Kind.ok.color == Theme.textPrimary)
        #expect(CheckRow.Kind.fix.color == Theme.warning)
        #expect(!kinds.contains { $0.color == Theme.accent || $0.color == Theme.recovery })
    }

    @Test("Spec 15: the pages' sources name no teal (L27: teal is recovery only)")
    func noTealInTheSources() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let files = ["DevicesAndSyncView", "TrackerDetailView", "TrackerPickerSheet", "TrackerCheckView", "SyncDetailsView",
                     "DevicesSyncPresentation"]
        for file in files {
            let source = try String(contentsOf: root.appendingPathComponent("Ryft/Features/Profile/\(file).swift"), encoding: .utf8)
            for teal in ["Theme.accent", "Theme.onAccent", "Theme.recovery", "TealButtonStyle", "PrimaryButton("] {
                #expect(!source.contains(teal), "\(file) names \(teal)")
            }
        }
    }

    // MARK: honest freshness (the offline-first rule)

    @Test("Sync details' State: up to date only with an upload on record and a connection; the last sync's real age")
    func syncDetailsState() {
        let clock = TestClock()
        let online = MockDevicesStates.graph(demo: false, clock: clock)
        defer { online.tearDown() }
        #expect(online.details.phaseText == String(localized: "Up to date") && !online.details.isOffline)
        #expect(online.details.lastSyncText(now: clock.now()) != String(localized: "Never"))
        #expect(online.details.lastSyncText(now: clock.now()).contains("5"), "five minutes ago")

        let offline = MockDevicesStates.graph(demo: false, online: false, clock: clock)
        defer { offline.tearDown() }
        #expect(offline.details.isOffline)
        #expect(offline.details.phaseText == String(localized: "Offline"), "offline nothing is up to date")

        let never = MockDevicesStates.graph(demo: false, lastSync: nil, clock: clock)
        defer { never.tearDown() }
        #expect(never.details.phaseText == String(localized: "Idle"), "no upload on record: never up to date")
        #expect(never.details.lastSyncText(now: clock.now()) == String(localized: "Never"))

        let demo = MockDevicesStates.graph(online: false, lastSync: nil, clock: clock)
        defer { demo.tearDown() }
        #expect(!demo.details.isOffline, "demo data sends nothing, so it is never offline")
    }

    @Test("Devices & sync's list: an earlier load says when; nothing loaded says so; loading while it can load")
    func devicesFreshness() {
        let clock = TestClock()
        let stale = MockDevicesStates.graph(demo: false, online: false, sources: .loaded(ago: 7_200), clock: clock)
        defer { stale.tearDown() }
        let loaded = clock.now().addingTimeInterval(-7_200)
        #expect(stale.devices.sourcesFreshness == .stale(loaded))
        let footer = stale.devices.lastLoadedText(loaded)
        #expect(footer.hasPrefix("Showing what RYFT last loaded, ") && footer.contains(SyncLine.dataTime(loaded, now: clock.now())))

        let failing = MockDevicesStates.graph(demo: false, sources: .failing(ago: 600), clock: clock)
        defer { failing.tearDown() }
        #expect(failing.devices.sourcesFreshness == .stale(clock.now().addingTimeInterval(-600)))

        let loading = MockDevicesStates.graph(demo: false, sources: .never, clock: clock)
        defer { loading.tearDown() }
        #expect(loading.devices.sourcesFreshness == .loading)

        let notLoaded = MockDevicesStates.graph(demo: false, online: false, sources: .never, clock: clock)
        defer { notLoaded.tearDown() }
        #expect(notLoaded.devices.sourcesFreshness == .notLoaded)
    }

    @Test("Check sync offline: the model knows; demo data never is")
    func checkSyncOffline() {
        let offline = MockDevicesStates.graph(demo: false, online: false, trackers: ["garmin"])
        defer { offline.tearDown() }
        #expect(offline.check(.garmin).isOffline)
        let demo = MockDevicesStates.graph(online: false, trackers: ["garmin"])
        defer { demo.tearDown() }
        #expect(!demo.check(.garmin).isOffline)
    }

    // MARK: Sync details' actions

    @Test("Spec 8: Copy diagnostics says Copied for 2 s on the clock, then its title again")
    func copiedForTwoSeconds() async throws {
        let clock = TestClock()
        let g = MockDevicesStates.graph(demo: false, clock: clock)
        defer { g.tearDown() }
        let copy = Task { await g.details.copyAndConfirm() }
        try await HostedSettling.until("Copied, waiting", polls: 1_000, condition: { g.details.copied && clock.pendingSleeps > 0 },
                                       pause: { await Task.yield() })
        clock.advance(by: .milliseconds(1_900))
        await Task.yield()
        #expect(g.details.copied, "still Copied at 1.9 s")
        clock.advance(by: .milliseconds(100))
        await copy.value
        #expect(!g.details.copied, "the title again at 2 s")
    }

    @Test("Spec 8, hosted: Copied replaces the title; the syncing actions are disabled while a sync can't run (demo)")
    func syncDetailsActions() async throws {
        let clock = TestClock()
        let g = MockDevicesStates.graph(demo: true, clock: clock)
        try await host(g, NavigationStack { SyncDetailsView(model: g.details) }) { w in
            #expect(!g.details.canSync, "demo data uploads nothing")
            let resend = try #require(w.nodes().first { $0.identifier == "syncDetails.resendRecent" })
            let resync = try #require(w.nodes().first { $0.identifier == "syncDetails.fullResync" })
            #expect(!resend.isEnabled && !resync.isEnabled)
            let copy = try #require(w.nodes().first { $0.identifier == "syncDetails.copy" })
            #expect(copy.isEnabled && copy.label == "Copy diagnostics")
            copy.activate()
            try await w.wait("Copied") { w.nodes().first { $0.identifier == "syncDetails.copy" }?.label == "Copied" }
            clock.advance(by: .seconds(2))
            try await w.wait("the title again") {
                w.nodes().first { $0.identifier == "syncDetails.copy" }?.label == "Copy diagnostics"
            }
        }
    }

    @Test("Spec 8, AX3: the request lines wrap inside the page; values go under their names")
    func syncDetailsAtAX3() async throws {
        let g = MockDevicesStates.graph(demo: false)
        try await host(g, typeSize: .accessibility3, category: .accessibilityExtraLarge, height: 9_000,
                       NavigationStack { SyncDetailsView(model: g.details) }) { w in
            let nodes = w.nodes()
            let request = try #require(nodes.first { $0.label.contains("/v1/ingest/samples") })
            #expect(request.frame.minX >= 0 && request.frame.maxX <= 390, "\(request.frame)")
            #expect(request.label.contains("01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c"), "the whole request ID")
            for node in nodes where node.frame.width > 0 {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= 390.5, "\(node.label) \(node.frame)")
            }
        }
    }

    // MARK: Devices & sync, hosted

    @Test("Spec 6: with trackers the primary is Check sync and Edit shows; the rows say their status in words")
    func devicesWithTrackers() async throws {
        let g = MockDevicesStates.graph(later: ["oura"])
        try await host(g, NavigationStack { DevicesAndSyncView(model: g.devices) }) { w in
            let nodes = w.nodes()
            #expect(nodes.contains { $0.identifier == "devices.checkSync" && $0.label == "Check sync" })
            #expect(!nodes.contains { $0.identifier == "devices.choose" })
            let edit = try #require(nodes.first { $0.identifier == "devices.edit" })
            #expect(edit.label == "Edit trackers")
            let oura = try #require(nodes.first { $0.identifier == "devices.row.oura" })
            #expect(oura.label == "Oura" && oura.value == "Set up later" && oura.hint == "Opens setup and details")
            let title = try #require(nodes.first { $0.label == "Devices & sync" })
            #expect(title.traits.contains(.header))
            #expect(nodes.contains { $0.label == "Your trackers" && $0.traits.contains(.header) })
        }
    }

    @Test("Spec 6: without a tracker the primary is Choose; no Edit, no Check sync")
    func devicesWithoutTrackers() async throws {
        let g = MockDevicesStates.graph(trackers: [], checkedAgo: nil)
        try await host(g, NavigationStack { DevicesAndSyncView(model: g.devices) }) { w in
            let nodes = w.nodes()
            #expect(nodes.contains { $0.identifier == "devices.choose" && $0.label == "Choose" })
            #expect(!nodes.contains { $0.identifier == "devices.checkSync" })
            #expect(!nodes.contains { $0.identifier == "devices.edit" })
        }
    }

    @Test("Spec 6, offline: the cached list stays and its footer says when it was loaded")
    func devicesOfflineFooter() async throws {
        let clock = TestClock()
        let g = MockDevicesStates.graph(demo: false, online: false, sources: .loaded(ago: 7_200), clock: clock)
        let time = SyncLine.dataTime(clock.now().addingTimeInterval(-7_200), now: clock.now())
        try await host(g, NavigationStack { DevicesAndSyncView(model: g.devices) }) { w in
            let nodes = w.nodes()
            #expect(nodes.contains { $0.label.contains("Showing what RYFT last loaded, \(time).") })
            #expect(nodes.filter { $0.identifier == "devices.source" }.count == 3, "the cached sources stay")
        }
    }

    @Test("Devices & sync at AX3: Edit on its own line under the title; nothing leaves the 390 pt page")
    func devicesAtAX3() async throws {
        let g = MockDevicesStates.graph(trackers: ["garmin", "oura"])
        try await host(g, typeSize: .accessibility3, category: .accessibilityExtraLarge, height: 7_000,
                       NavigationStack { DevicesAndSyncView(model: g.devices) }) { w in
            let nodes = w.nodes()
            let title = try #require(nodes.first { $0.label == "Your trackers" })
            let edit = try #require(nodes.first { $0.identifier == "devices.edit" })
            #expect(edit.frame.minY >= title.frame.maxY - 1, "Edit under the title: \(edit.frame) \(title.frame)")
            #expect(edit.frame.height >= 44 && edit.frame.width >= 44)
            for node in nodes where node.frame.width > 0 {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= 390.5, "\(node.label) \(node.frame)")
            }
        }
    }

    // MARK: the picker, hosted

    @Test("The picker: the choice shows selected, the tiles' rule, and Done saves (Close keeps it as it was)")
    func pickerSelection() async throws {
        // The tiles' rule (`TrackerPickerGrid`): several at once; Just my iPhone alone, and it clears the others.
        #expect(TrackerSelectionStore.toggled("oura", in: ["garmin"]).picked == ["garmin", "oura"])
        #expect(TrackerSelectionStore.toggled("garmin", in: ["garmin", "oura"]).picked == ["oura"])
        let iPhone = TrackerSelectionStore.toggled(TrackerSelectionStore.iPhone, in: ["garmin", "oura"])
        #expect(iPhone.picked == [TrackerSelectionStore.iPhone] && iPhone.cleared)

        let clock = TestClock()
        let g = MockDevicesStates.graph(demo: false, trackers: ["garmin", "oura"], checkedAgo: nil, clock: clock)
        let before = try #require(g.devices.selection.selection?.updatedAt)
        clock.advance(by: .seconds(60))
        try await host(g, TrackerPickerSheet(model: g.devices)) { w in
            let nodes = w.nodes()
            #expect(nodes.first { $0.identifier == "wear.tile.garmin" }?.isSelected == true)
            #expect(nodes.first { $0.identifier == "wear.tile.oura" }?.isSelected == true)
            #expect(nodes.first { $0.identifier == "wear.tile.apple_watch" }?.isSelected == false)
            #expect(nodes.contains { $0.identifier == "subpage.close" && $0.label == "Close" }, "Close leaves the choice as it was")
            #expect(g.devices.selection.selection?.updatedAt == before, "nothing saved before Done")
            let done = try #require(nodes.first { $0.identifier == "wear.done" })
            #expect(done.label == "Done")
            done.activate()
            try await w.wait("saved") { g.devices.selection.selection?.updatedAt == clock.now() }
            #expect(g.devices.selection.trackers == ["garmin", "oura"])
        }
    }

    // MARK: Check sync, hosted

    @Test("Spec 7: running is busy Checking…; done shows the rows, the fix and Check again")
    func checkSyncRunningAndDone() async throws {
        let running = MockDevicesStates.graph(trackers: ["garmin"])
        let runningCheck = running.check(.garminSleepOff)
        MockDevicesStates.staged(runningCheck, .running, scenario: .garminSleepOff)
        try await host(running, NavigationStack { TrackerCheckView(model: runningCheck) }) { w in
            let run = try #require(w.nodes().first { $0.identifier == "check.run" })
            #expect(run.label == "Checking…" && run.value == "In progress")
            #expect(!w.nodes().contains { $0.identifier == "check.allow" })
        }

        let done = MockDevicesStates.graph(trackers: ["garmin"])
        let doneCheck = done.check(.garminSleepOff)
        MockDevicesStates.staged(doneCheck, .done, scenario: .garminSleepOff)
        try await host(done, NavigationStack { TrackerCheckView(model: doneCheck) }) { w in
            let nodes = w.nodes()
            let run = try #require(nodes.first { $0.identifier == "check.run" })
            #expect(run.label == "Check again" && run.isEnabled)
            #expect(nodes.first { $0.identifier == "check.row.sleep" }?.value == "Should arrive, nothing yet. Fix available")
            #expect(nodes.contains { $0.identifier == "check.openApp" && $0.traits.contains(.link) }, "the store, a link-out row")
            #expect(!nodes.contains { $0.identifier == "check.offline" })
        }
    }

    @Test("Spec 7: not asked pins Allow access; a failed read says so and keeps Check again")
    func checkSyncNotAskedAndFailed() async throws {
        let notAsked = MockDevicesStates.graph(trackers: ["garmin"])
        let notAskedCheck = notAsked.check(.garmin)
        MockDevicesStates.staged(notAskedCheck, .notAsked, scenario: .garmin)
        try await host(notAsked, NavigationStack { TrackerCheckView(model: notAskedCheck) }) { w in
            let nodes = w.nodes()
            #expect(nodes.contains { $0.identifier == "check.allow" && $0.label == "Allow access" })
            #expect(!nodes.contains { $0.identifier == "check.run" })
            #expect(nodes.contains { $0.label.contains("RYFT hasn't asked for Health access yet.") })
        }

        let failed = MockDevicesStates.graph(trackers: ["garmin"])
        let failedCheck = failed.check(.garmin)
        MockDevicesStates.staged(failedCheck, .failed, scenario: .garmin)
        try await host(failed, NavigationStack { TrackerCheckView(model: failedCheck) }) { w in
            let nodes = w.nodes()
            #expect(nodes.contains { $0.identifier == "check.note" && $0.label.contains("couldn't be read") })
            #expect(nodes.first { $0.identifier == "check.run" }?.isEnabled == true)
        }
    }

    @Test("Spec 7, offline: Check sync says RYFT can't be reached, and the check still shows its results")
    func checkSyncOfflineHosted() async throws {
        let g = MockDevicesStates.graph(demo: false, online: false, trackers: ["garmin"])
        let check = g.check(.garmin)
        MockDevicesStates.staged(check, .done, scenario: .garmin)
        try await host(g, NavigationStack { TrackerCheckView(model: check) }) { w in
            let nodes = w.nodes()
            let notice = try #require(nodes.first { $0.identifier == "check.offline" })
            #expect(notice.label.contains("RYFT can't be reached"))
            #expect(nodes.contains { $0.identifier == "check.row.heart_rate" })
            #expect(nodes.first { $0.identifier == "check.run" }?.value != "In progress", "nothing spins")
        }
    }

    @Test("Check sync at AX3: results under names, nothing leaves the page")
    func checkSyncAtAX3() async throws {
        let g = MockDevicesStates.graph(trackers: ["garmin"])
        let check = g.check(.garminSleepOff)
        MockDevicesStates.staged(check, .done, scenario: .garminSleepOff)
        try await host(g, typeSize: .accessibility3, category: .accessibilityExtraLarge, height: 9_000,
                       NavigationStack { TrackerCheckView(model: check) }) { w in
            for node in w.nodes() where node.frame.width > 0 {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= 390.5, "\(node.label) \(node.frame)")
            }
        }
    }

    // MARK: hosting

    /// The page in a 390 pt window, settled, in US English; the graph's defaults go afterwards.
    private func host(_ graph: MockDevicesStates.Graph, typeSize: DynamicTypeSize = .large,
                      category: UIContentSizeCategory = .large, height: CGFloat = 2_600, _ view: some View,
                      _ body: (HostedWindow) async throws -> Void) async throws {
        defer { graph.tearDown() }
        let page = view.previewEnvironment(graph.state).environment(\.locale, Locale(identifier: "en_US"))
        try await HostedWindow.run(width: 390, height: height, typeSize: typeSize, category: category, page) { w in
            try await w.settle()
            try await body(w)
        }
    }
}
