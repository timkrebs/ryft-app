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
        #expect(!kinds.contains { $0.color == Theme.recovery })
    }

    @Test("Spec 15: the pages' sources name no teal (L27: teal is recovery only)")
    func noTealInTheSources() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let files = ["DevicesAndSyncView", "TrackerDetailView", "TrackerPickerSheet", "TrackerCheckView", "SyncDetailsView",
                     "DevicesSyncPresentation"]
        let teal = try Regex(#"Theme\.(teal|accent\w*|onAccent|recovery)|Color\("(Accent|Teal|Recovery)|TealButtonStyle|PrimaryButton\("#)
        for file in files {
            let source = try String(contentsOf: root.appendingPathComponent("Ryft/Features/Profile/\(file).swift"), encoding: .utf8)
            let found = source.matches(of: teal).map { String(source[$0.range]) }
            #expect(found.isEmpty, "\(file) names \(found)")
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
            let request = try #require(nodes.first { $0.label.contains("POST /v1/sync") })
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
            // Half a point of slack: under the pushed header's AX3 title the link sits on a fractional origin (213.67), where
            // its 44 pt box measures 43.99999999999997.
            #expect(edit.frame.height >= 44 - 0.5 && edit.frame.width >= 44 - 0.5, "\(edit.frame)")
            for node in nodes where node.frame.width > 0 {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= 390.5, "\(node.label) \(node.frame)")
            }
        }
    }

    // MARK: the picker, hosted

    @Test("The picker shows the saved choice selected; Done saves the shown choice and closes; Close closes without saving")
    func pickerShowsSavesAndCloses() async throws {
        // The tiles' rule (`TrackerPickerGrid`): several at once; Just my iPhone alone, and it clears the others.
        #expect(TrackerSelectionStore.toggled("oura", in: ["garmin"]).picked == ["garmin", "oura"])
        #expect(TrackerSelectionStore.toggled("garmin", in: ["garmin", "oura"]).picked == ["oura"])
        let iPhone = TrackerSelectionStore.toggled(TrackerSelectionStore.iPhone, in: ["garmin", "oura"])
        #expect(iPhone.picked == [TrackerSelectionStore.iPhone] && iPhone.cleared)

        for closes in [true, false] {
            let clock = TestClock()
            let g = MockDevicesStates.graph(demo: false, trackers: ["garmin", "oura"], checkedAgo: nil, clock: clock)
            let before = try #require(g.devices.selection.selection?.updatedAt)
            clock.advance(by: .seconds(60))
            try await host(g, SheetHost { TrackerPickerSheet(model: g.devices) }) { w in
                try await w.wait("the sheet") { sheetNodes(w).contains { $0.identifier == "wear.done" } }
                try await w.settle()
                let nodes = sheetNodes(w)
                #expect(nodes.first { $0.identifier == "wear.tile.garmin" }?.isSelected == true)
                #expect(nodes.first { $0.identifier == "wear.tile.oura" }?.isSelected == true)
                #expect(nodes.first { $0.identifier == "wear.tile.apple_watch" }?.isSelected == false)
                #expect(!nodes.contains { $0.label == "Cancel" }, "Close is the way out")
                let button = try #require(nodes.first { $0.identifier == (closes ? "subpage.close" : "wear.done") })
                #expect(button.label == (closes ? "Close" : "Done"))
                button.activate()
                try await w.wait("the sheet closed") { w.nodes().contains { $0.identifier == SheetHost<EmptyView>.closed } }
                if closes {
                    #expect(g.devices.selection.selection?.updatedAt == before, "Close saves nothing")
                } else {
                    #expect(g.devices.selection.selection?.updatedAt == clock.now(), "Done saves")
                }
                #expect(g.devices.selection.trackers == ["garmin", "oura"])
            }
        }
    }

    // MARK: Check sync, hosted

    @Test("Spec 7: running is busy and keeps Check again (the busy rule); done shows the rows, the fix and Check again")
    func checkSyncRunningAndDone() async throws {
        let running = MockDevicesStates.graph(trackers: ["garmin"])
        let runningCheck = running.check(.garminSleepOff)
        MockDevicesStates.staged(runningCheck, .running, scenario: .garminSleepOff)
        try await host(running, NavigationStack { TrackerCheckView(model: runningCheck) }) { w in
            let run = try #require(w.nodes().first { $0.identifier == "check.run" })
            #expect(run.label == "Check again" && run.value == "In progress" && !run.isEnabled, "\(run.label) · \(run.value ?? "")")
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

    /// R2 V1 S5: from AX1 the result goes under the name, and nothing pushes a row out to the card's edge any more; the
    /// hairline above a short row stopped at its words, and the two lines touched the hairlines.
    @Test("Check sync at AX3: every row is the card's width, its hairline inset to inset, with 10 above and below")
    func checkSyncRowsAtAX3() async throws {
        let g = MockDevicesStates.graph(trackers: SyncCheckScenario.appleWatch.trackers)
        let check = g.check(.appleWatch)
        MockDevicesStates.staged(check, .done, scenario: .appleWatch)
        try await host(g, typeSize: .accessibility3, category: .accessibilityExtraLarge, height: 2_400,
                       NavigationStack { TrackerCheckView(model: check) }) { w in
            let rows = w.nodes().filter { $0.identifier?.hasPrefix("check.row.") == true }
            #expect(rows.count >= 5, "\(rows.map(\.label))")
            // The hairline as drawn: `separator` over the card's `surface`.
            let line = NocturneTokenTests.resolve(Theme.separator), card = NocturneTokenTests.resolve(Theme.surface)
            let ink = (r: card.r + (line.r - card.r) * line.a, g: card.g + (line.g - card.g) * line.a,
                       b: card.b + (line.b - card.b) * line.a)
            let pixels = try WindowPixels(w, scale: 2)
            let padding = CheckSyncSpec.stackedRowPadding
            // The page's column is 350 at 20 from the sides; a row's hairline is 16 in from the card's edges.
            let inset = SubpageSpec.sidePadding + GroupedListSpec.rowInset
            for (above, row) in zip(rows, rows.dropFirst()) {
                #expect(row.frame.minY - above.frame.maxY >= 2 * padding - 0.5,
                        "10 under \(above.label), 10 above \(row.label): \(above.frame) \(row.frame)")
                let band = CGRect(x: 0, y: row.frame.minY - padding - 3, width: 390, height: 5)
                let hairline = pixels.box(in: band) {
                    abs($0.r - ink.r) < 0.03 && abs($0.g - ink.g) < 0.03 && abs($0.b - ink.b) < 0.03
                }
                #expect(hairline.map { abs($0.minX - inset) < 1.5 && abs($0.maxX - (390 - inset)) < 1.5 } == true,
                        "above \(row.label): \(hairline.map { "\($0)" } ?? "none")")
            }
        }
    }

    // MARK: review round: Sync details' State after a held, failed or stopped run (B1)

    /// One branch of `SyncIdleState.decide` each: what it's given, what it says.
    struct IdleCase: Sendable, CustomTestStringConvertible {
        let name: String
        var pausedFor: UploadGate?
        var offline = false
        var failed = false
        var backfillDone = true
        var backlog = false
        var uploaded = true
        let expected: SyncIdleState
        var testDescription: String { name }
    }

    nonisolated static let idleCases: [IdleCase] = [
        IdleCase(name: "consent gate", pausedFor: .gate(.consentRequired), offline: true, failed: true,
                 expected: .actionNeeded(.consent)),
        IdleCase(name: "invite gate", pausedFor: .gate(.inviteRequired), expected: .actionNeeded(.invite)),
        IdleCase(name: "policy not known", pausedFor: .policyUnknown, failed: true, expected: .paused),
        IdleCase(name: "offline", offline: true, failed: true, expected: .offline),
        IdleCase(name: "last run failed", failed: true, backlog: true, expected: .failed),
        IdleCase(name: "import not finished", backfillDone: false, backlog: true, expected: .importNotFinished),
        IdleCase(name: "stopped early", backlog: true, expected: .moreToSend),
        IdleCase(name: "demo's hold is silent", pausedFor: .demo, expected: .upToDate),
        IdleCase(name: "an upload on record", expected: .upToDate),
        IdleCase(name: "never sent", uploaded: false, expected: .idle),
    ]

    @Test("B1: State between runs, each branch; Up to date only after everything else", arguments: Self.idleCases)
    func idleStateBranch(_ c: IdleCase) {
        let state = SyncIdleState.decide(pausedFor: c.pausedFor, offline: c.offline, failed: c.failed,
                                         backfillDone: c.backfillDone, backlog: c.backlog, uploaded: c.uploaded)
        #expect(state == c.expected)
    }

    @Test("B1: the words are Today's for a hold, and only a hold or a failure asks for attention")
    func idleStateWords() {
        #expect(SyncIdleState.actionNeeded(.consent).text == String(localized: "Action needed: agree to the privacy policy"))
        #expect(SyncIdleState.actionNeeded(.invite).text == String(localized: "Action needed: enter your invite code"))
        #expect(SyncIdleState.paused.text == String(localized: "Health sync paused"))
        #expect(SyncIdleState.failed.text == String(localized: "Last sync failed"))
        #expect(SyncIdleState.moreToSend.text == String(localized: "More to send"))
        let attention: [SyncIdleState] = [.actionNeeded(.consent), .paused, .failed]
        let calm: [SyncIdleState] = [.offline, .importNotFinished, .moreToSend, .upToDate, .idle]
        #expect(attention.allSatisfy(\.needsAttention) && !calm.contains(where: \.needsAttention))
    }

    /// An account that finished its import and uploaded an hour ago; the next run reads one heart-rate page.
    private func liveDetails(api: MockPlatformAPI = MockPlatformAPI(), gate: UploadGate? = nil)
        throws -> (SyncDetailsModel, SyncService) {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [
            HealthDelta(samples: [Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "x")])
        ]])
        let clock = TestClock()
        let env = AppEnvironment.test(api: api, health: health, clock: clock)
        let account = try #require(env.auth.accountID)
        MockDevicesStates.engine(now: clock.now()).save(account: account, defaults: env.defaults)
        env.settings.lastSync = clock.now().addingTimeInterval(-3_600)
        let state = AppState(env: env)
        let sync = SyncService(env: env)
        sync.gate = { gate }
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock)
        return (SyncDetailsModel(state: state, sync: sync, coordinator: coordinator, apiStatus: APIStatus()), sync)
    }

    @Test("B1, live: a failed run says Last sync failed, in warning, though an earlier upload is on record")
    func failedRunIsNotUpToDate() async throws {
        let api = MockPlatformAPI()
        api.failNext = APIError.http(500, "")
        let (model, sync) = try liveDetails(api: api)
        #expect(model.phaseText == String(localized: "Up to date") && !model.stateNeedsAttention, "before: an upload on record")
        await sync.syncNow()
        #expect(sync.engineState.phase == .idle && sync.engineState.lastError != nil)
        #expect(model.phaseText == String(localized: "Last sync failed"))
        #expect(model.stateNeedsAttention)
    }

    @Test("B1, live: a run held at a gate says Today's words", arguments: [
        UploadGate.gate(.consentRequired), .gate(.inviteRequired), .policyUnknown,
    ])
    func heldRunIsNotUpToDate(_ gate: UploadGate) async throws {
        let (model, sync) = try liveDetails(gate: gate)
        await sync.syncNow()
        #expect(sync.pausedFor == gate)
        let expected: String = switch gate {
        case .gate(.inviteRequired): String(localized: "Action needed: enter your invite code")
        case .gate: String(localized: "Action needed: agree to the privacy policy")
        default: String(localized: "Health sync paused")
        }
        #expect(model.phaseText == expected)
        #expect(model.stateNeedsAttention)
    }

    // MARK: review round: Seen in Apple Health and gate refusals (S1)

    @Test("S1: a refusal at a gate newer than the load is unreachable; an older one isn't")
    func sourcesFreshnessAtTheGate() {
        let at = Date(timeIntervalSince1970: 1_792_400_000)
        func gate(_ offset: TimeInterval) -> ResourceError {
            ResourceError(kind: .gate, status: 403, code: "consent_required", requestID: nil, transport: nil, attempts: 1,
                          at: at.addingTimeInterval(offset))
        }
        typealias F = SourcesFreshness
        #expect(F.decide(hasList: true, isDemo: false, isOnline: true, fetchedAt: at, failures: 0, lastError: gate(60))
            == .stale(at), "refused after the load: the list is the earlier load's")
        #expect(F.decide(hasList: true, isDemo: false, isOnline: true, fetchedAt: at, failures: 0, lastError: gate(-60))
            == .fresh, "refused before the load that worked")
        #expect(F.decide(hasList: false, isDemo: false, isOnline: true, fetchedAt: nil, failures: 0, lastError: gate(0))
            == .notLoaded, "nothing cached and refused: never Loading… forever")
        #expect(F.decide(hasList: true, isDemo: false, isOnline: true, fetchedAt: nil, failures: 0, lastError: gate(0))
            == .stale(nil))
    }

    @Test("S1: a cached list behind a refusal says it's an earlier load, without Offline while online")
    func refusedListsFooter() async throws {
        let cached = MockDevicesStates.graph(demo: false, sources: .refused(cached: true))
        #expect(cached.devices.sourcesFreshness == .stale(nil))
        #expect(cached.devices.lastLoadedText(nil) == "Showing your last loaded data.")
        try await host(cached, NavigationStack { DevicesAndSyncView(model: cached.devices) }) { w in
            let nodes = w.nodes()
            #expect(nodes.contains { $0.label.contains("Showing your last loaded data.") })
            #expect(!nodes.contains { $0.label.contains("Offline") })
            #expect(!nodes.contains { $0.label == "Loading…" })
        }

        let empty = MockDevicesStates.graph(demo: false, sources: .refused(cached: false))
        #expect(empty.devices.sourcesFreshness == .notLoaded)
        try await host(empty, NavigationStack { DevicesAndSyncView(model: empty.devices) }) { w in
            #expect(w.nodes().contains { $0.label == "Not loaded yet" })
            #expect(!w.nodes().contains { $0.label == "Loading…" })
        }

        let offline = MockDevicesStates.graph(demo: false, online: false, sources: .refused(cached: true))
        defer { offline.tearDown() }
        #expect(offline.devices.lastLoadedText(nil) == "Offline. Showing your last loaded data.")
    }

    @Test("Offline data: no source's Last data is newer than the load that brought the list")
    func sourcesAreNotNewerThanTheirLoad() throws {
        let clock = TestClock()
        let g = MockDevicesStates.graph(demo: false, online: false, sources: .loaded(ago: 7_200), clock: clock)
        defer { g.tearDown() }
        let loaded = try #require(g.state.resourceStates[.me]?.fetchedAt)
        #expect(g.devices.sources.allSatisfy { $0.lastSeen <= loaded })
    }

    // MARK: review round: what waits to be sent (S2)

    @Test("S2: activities and nights count saved ones; a recording in progress isn't waiting to send")
    func unsentActivitiesLeaveOutARecording() throws {
        let clock = TestClock()
        let g = MockDevicesStates.graph(demo: false, clock: clock)
        defer { g.tearDown() }
        let account = try #require(g.env.auth.accountID)
        let end = clock.now()
        #expect(g.env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900), end: end)) != nil)
        g.store.context.insert(LocalActivity(account: account, sport: .running, origin: .recorded, phase: "recording",
                                             start: end.addingTimeInterval(-600), end: nil, movingSec: 540,
                                             localRevision: 0, createdAt: end.addingTimeInterval(-600)))
        g.store.save()
        #expect(g.env.activities.unconfirmedCount(ofAccount: account) == 2, "the store counts the recording")
        #expect(g.details.unsentActivities == 1, "Sync details doesn't")
    }

    @Test("S2: workouts waiting in Train's outbox, and the gate that holds them in Today's words")
    func unsentWorkoutsAndTheirGate() async throws {
        let g = MockDevicesStates.graph(demo: false)
        defer { g.tearDown() }
        #expect(g.details.unsentWorkouts == 0 && g.details.workoutsHeldText == nil)
        g.train.gate = { write in write == .erasure ? nil : .gate(.consentRequired) }
        _ = await g.train.finish(SessionFactory.empty(in: g.store)) // a put and a complete
        #expect(g.train.pendingCount == 2 && g.train.heldAt == .gate(.consentRequired))
        #expect(g.details.unsentWorkouts == 2)
        #expect(g.details.workoutsHeldText == String(localized: "Action needed: agree to the privacy policy"))
        #expect(SyncDetailsModel.waitingText(2) == 2.formatted() && SyncDetailsModel.waitingText(0) == "None")
    }

    @Test("S2: Profile connects Train's outbox and the reports kept for later to Sync details")
    func profileConnectsWhatWaits() async throws {
        let g = MockDevicesStates.graph(demo: false)
        defer { g.tearDown() }
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: g.state, sync: g.sync), clock: g.env.clock)
        let train = TrainCoordinator(sync: g.train, library: TrainLibrary.preview(store: g.store, outbox: g.train),
                                     liveActivities: false)
        let profile = ProfileViewModel(state: g.state, sync: g.sync, coordinator: coordinator, apiStatus: APIStatus(),
                                       train: train)
        #expect(profile.syncDetails.trainOutbox === g.train)
        #expect(profile.syncDetails.unsentReports == 0)
        profile.report.stage(waiting: 2)
        #expect(profile.syncDetails.unsentReports == 2)
    }

    @Test("S2, hosted: Waiting to send lists activities and nights, workouts with their hold, and reports")
    func waitingGroupHosted() async throws {
        let clock = TestClock()
        let g = MockDevicesStates.graph(demo: false, reportsWaiting: 1, clock: clock)
        let end = clock.now()
        _ = g.env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900), end: end))
        g.train.gate = { write in write == .erasure ? nil : .gate(.consentRequired) }
        _ = await g.train.finish(SessionFactory.empty(in: g.store))
        try await host(g, NavigationStack { SyncDetailsView(model: g.details) }) { w in
            let nodes = w.nodes()
            #expect(nodes.contains { $0.label == "Waiting to send" && $0.traits.contains(.header) })
            #expect(nodes.first { $0.identifier == "syncDetails.unsent" }?.value == "1")
            let workouts = try #require(nodes.first { $0.identifier == "syncDetails.unsentWorkouts" })
            #expect(workouts.value?.contains("2") == true, "\(workouts.value ?? "-")")
            #expect(workouts.value?.contains("Action needed: agree to the privacy policy") == true)
            #expect(nodes.first { $0.identifier == "syncDetails.unsentReports" }?.value == "1")
        }
    }

    // MARK: review round: Sync details' nits

    @Test("Offline: Sync last 3 days again and Full resync can't run, and the footer says why")
    func offlineDisablesTheUploads() async throws {
        let online = AppEnvironment.test(online: true)
        let offline = AppEnvironment.test(online: false)
        for env in [online, offline] {
            let state = AppState(env: env)
            let sync = SyncService.ungated(env: env)
            let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock)
            let model = SyncDetailsModel(state: state, sync: sync, coordinator: coordinator, apiStatus: APIStatus())
            #expect(model.canSync, "signed in, configured, not demo")
            #expect(model.canSyncAgain == env.connectivity.isOnline)
        }
        let g = MockDevicesStates.graph(demo: false, online: false)
        try await host(g, NavigationStack { SyncDetailsView(model: g.details) }) { w in
            let nodes = w.nodes()
            #expect(nodes.first { $0.identifier == "syncDetails.resendRecent" }?.isEnabled == false)
            #expect(nodes.first { $0.identifier == "syncDetails.fullResync" }?.isEnabled == false)
            #expect(nodes.contains { $0.label.contains("You're offline. Syncing again works when you're back online.") })
        }
        let here = MockDevicesStates.graph(demo: false)
        try await host(here, NavigationStack { SyncDetailsView(model: here.details) }) { w in
            #expect(!w.nodes().contains { $0.label.contains("Syncing again works") })
        }
    }

    @Test("Streams say their newest reading as the status line does; Last sync is Profile's words")
    func streamsAndLastSyncWords() throws {
        let clock = TestClock()
        let g = MockDevicesStates.graph(demo: false, clock: clock)
        defer { g.tearDown() }
        let heartRate = try #require(g.details.streams.first { $0.id == HealthStream.quantity(.heartRate).anchorID })
        let newest = try #require(heartRate.progress?.newest)
        #expect(heartRate.newestLine(now: clock.now()) == "Newest \(SyncLine.dataTime(newest, now: clock.now()))")
        #expect(SyncDetailsModel.StreamRow(id: "x", name: "x", progress: nil).newestLine(now: clock.now()) == "Nothing sent yet")
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: g.state, sync: g.sync), clock: g.env.clock)
        let profile = ProfileViewModel(state: g.state, sync: g.sync, coordinator: coordinator, apiStatus: APIStatus())
        #expect(profile.lastSyncText == g.details.lastSyncText(now: clock.now()))
        #expect(profile.lastSyncText == "5 minutes ago")
        #expect(SyncDetailsModel.lastSyncWords(nil, now: clock.now()) == "Never")
    }

    @Test("Apple Health access: only Not requested asks for attention; Not available is a fact, never amber")
    func healthAttentionRule() {
        #expect(HealthAccess.notAsked.needsAttention)
        #expect(!HealthAccess.unavailable.needsAttention && !HealthAccess.asked.needsAttention
            && !HealthAccess.unknown.needsAttention)
    }

    // MARK: review round: placement (S4, nit 1)

    @Test("Placement: what a sheet's page pushes keeps the sheet's inset; Back on pushed pages, Close at the root")
    func placementInASheet() {
        #expect(DevicesPagePlacement.sheet.pushed == .pushedInSheet)
        #expect(DevicesPagePlacement.pushedInSheet.pushed == .pushedInSheet)
        #expect(DevicesPagePlacement.pushed.pushed == .pushed && DevicesPagePlacement.root.pushed == .pushed)
        #expect(DevicesPagePlacement.sheet.isSheet && !DevicesPagePlacement.pushedInSheet.isSheet, "the sheet's look: its root only")
        #expect(!DevicesPagePlacement.pushed.isSheet && !DevicesPagePlacement.root.isSheet)
        #expect(DevicesPagePlacement.pushedInSheet.topInset == SubpageSpec.sheetTopInset)
        #expect([DevicesPagePlacement.sheet, .pushed, .root].allSatisfy { $0.topInset == 0 }, "the root's inset is its own")
        if case .back = DevicesPagePlacement.pushedInSheet.navigation {} else { Issue.record("pushed in a sheet: Back") }
        if case .close = DevicesPagePlacement.sheet.navigation {} else { Issue.record("a sheet's root: Close") }
        if case .none = DevicesPagePlacement.root.navigation {} else { Issue.record("a Debug host's root: neither") }
    }

    @Test("SyncDetailsSheet (Today's status line): Close, no Back, and Close dismisses the sheet")
    func syncDetailsSheetCloses() async throws {
        let g = MockDevicesStates.graph(demo: false)
        try await host(g, SheetHost { SyncDetailsSheet(model: g.details) }) { w in
            try await w.wait("the sheet") { sheetNodes(w).contains { $0.identifier == "subpage.close" } }
            try await w.settle()
            let nodes = sheetNodes(w)
            #expect(!nodes.contains { $0.identifier == "subpage.back" })
            #expect(nodes.contains { $0.label == "Sync details" && $0.traits.contains(.header) })
            let close = try #require(nodes.first { $0.identifier == "subpage.close" })
            #expect(close.label == "Close")
            close.activate()
            try await w.wait("dismissed") { w.nodes().contains { $0.identifier == SheetHost<EmptyView>.closed } }
            try await w.wait("the sheet gone") { w.host.presentedViewController == nil }
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

/// A sheet over an empty page, presented at once; its marker shows when the sheet was dismissed (by Close or Done).
struct SheetHost<Content: View>: View {
    static var closed: String { "sheetHost.closed" }
    @ViewBuilder let content: () -> Content
    @State private var presented = true

    var body: some View {
        Theme.background
            .ignoresSafeArea()
            .overlay {
                if !presented {
                    Text(verbatim: "Closed").accessibilityIdentifier(Self.closed)
                }
            }
            .sheet(isPresented: $presented) { content() }
    }
}

/// One element of a presented sheet (`HostedWindow.Node` is made only by the host's own walk).
struct SheetNode {
    let label: String
    let traits: UIAccessibilityTraits
    let object: NSObject
    var identifier: String? { object.value(forKey: "accessibilityIdentifier") as? String }
    var isSelected: Bool { traits.contains(.selected) }
    /// A tap as VoiceOver's double tap does it.
    @discardableResult
    func activate() -> Bool { object.accessibilityActivate() }
}

/// The presented sheet's elements, walked as `HostedWindow.nodes()` walks the host's own view (a sheet is presented above
/// it, outside that view).
@MainActor
func sheetNodes(_ w: HostedWindow) -> [SheetNode] {
    guard let root = w.host.presentedViewController?.view else { return [] }
    var found: [SheetNode] = []
    var seen = Set<ObjectIdentifier>()
    func walk(_ object: NSObject, depth: Int) {
        guard depth < 40, seen.insert(ObjectIdentifier(object)).inserted else { return }
        if String(describing: type(of: object)) == "AccessibilityNode", let label = object.accessibilityLabel, !label.isEmpty {
            found.append(SheetNode(label: label, traits: object.accessibilityTraits, object: object))
        }
        if let elements = object.accessibilityElements {
            for case let child as NSObject in elements { walk(child, depth: depth + 1) }
        } else {
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for i in 0..<count {
                    if let child = object.accessibilityElement(at: i) as? NSObject { walk(child, depth: depth + 1) }
                }
            }
        }
        if let view = object as? UIView { for sub in view.subviews { walk(sub, depth: depth + 1) } }
    }
    walk(root, depth: 0)
    return found
}
