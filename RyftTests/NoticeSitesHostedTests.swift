import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Every warning and error line of `design.md` 4.7, in its real view and in the state that shows it, read from the window's
/// pixels on the background it really has: the crop's commonest colour is the ground, its strongest colour the ink. None of
/// these states is reachable in demo mode. Each site also pins its ink to the token it is meant to draw, so a system red that
/// beats a `foregroundStyle` fails here. Synthetic values only.
///
/// With `ORBIT_SHOTS_DIR` set (`TEST_RUNNER_ORBIT_SHOTS_DIR` on the command line), every reading goes to `notice-contrast.txt`
/// and every crop to a PNG beside it.
@MainActor
@Suite("Notice sites, hosted", .serialized)
struct NoticeSitesHostedTests {
    private static let shotsDir = ProcessInfo.processInfo.environment["ORBIT_SHOTS_DIR"]

    // MARK: reading

    private struct RGB: CustomStringConvertible {
        let r, g, b: Double
        var luminance: Double {
            func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        func contrast(_ other: RGB) -> Double {
            let (a, b) = (luminance, other.luminance)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        func distance(_ o: RGB) -> Double { ((r - o.r) * (r - o.r) + (g - o.g) * (g - o.g) + (b - o.b) * (b - o.b)).squareRoot() }
        var description: String { String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255)) }
    }

    /// The window at 3x in sRGB.
    @MainActor
    private struct Shot {
        let width, height: Int
        let bytes: [UInt8]
        let image: UIImage

        init?(_ w: HostedWindow) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            format.opaque = true
            format.preferredRange = .standard
            let window = w.window
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            guard let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let drew = bytes.withUnsafeMutableBytes { raw in
                let context = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                        bytesPerRow: cg.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                context?.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                return context != nil
            }
            guard drew else { return nil }
            (width, height, self.bytes, self.image) = (cg.width, cg.height, bytes, image)
        }

        /// The ground is the crop's commonest colour. The ink is the colour furthest from it that fills at least 9 pixels, one
        /// square point: enough to skip stray antialiasing, and a stem's core at 3x is that much.
        func read(_ rect: CGRect) -> (ground: RGB, ink: RGB)? {
            let x0 = max(0, Int(rect.minX * 3)), x1 = min(width, Int(rect.maxX * 3))
            let y0 = max(0, Int(rect.minY * 3)), y1 = min(height, Int(rect.maxY * 3))
            guard x0 < x1, y0 < y1 else { return nil }
            var counts: [UInt32: Int] = [:]
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let i = (y * width + x) * 4
                    counts[UInt32(bytes[i]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]), default: 0] += 1
                }
            }
            func rgb(_ key: UInt32) -> RGB {
                RGB(r: Double(key >> 16 & 255) / 255, g: Double(key >> 8 & 255) / 255, b: Double(key & 255) / 255)
            }
            guard let groundKey = counts.max(by: { $0.value < $1.value })?.key else { return nil }
            let ground = rgb(groundKey)
            let ink = counts.filter { $0.value >= 9 }.keys.map(rgb).max { $0.contrast(ground) < $1.contrast(ground) }
            return ink.map { (ground, $0) }
        }
    }

    /// The token as drawn on `ground`: the text tokens carry an alpha in light.
    private func resolved(_ colour: Color, on ground: RGB, dark: Bool) -> RGB {
        let ui = UIColor(colour).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let c = ui.cgColor.converted(to: space, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 1]
        let a = Double(c[3])
        return RGB(r: Double(c[0]) * a + ground.r * (1 - a), g: Double(c[1]) * a + ground.g * (1 - a), b: Double(c[2]) * a + ground.b * (1 - a))
    }

    /// Waits for the element and scrolls the page until it is well inside the viewport.
    private func reveal(_ what: String, in w: HostedWindow, _ match: (HostedWindow.Node) -> Bool) async throws -> HostedWindow.Node {
        func find() -> HostedWindow.Node? { w.nodes().first(where: match) }
        do {
            try await w.wait(what, timeout: .seconds(8)) { find() != nil }
        } catch {
            Issue.record("\(what) isn't on screen: \(w.nodes().map(\.label).prefix(60))")
            throw error
        }
        try await w.settle()
        var node = try #require(find())
        if let scroll = w.pageScrollView(), let viewport = w.pageViewport(), !viewport.insetBy(dx: 0, dy: 24).contains(node.frame) {
            let top = -scroll.adjustedContentInset.top
            let bottom = max(top, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
            let y = scroll.contentOffset.y + node.frame.midY - viewport.midY
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(max(y, top), bottom)), animated: false)
            try await w.settle()
            node = try #require(find())
        }
        return node
    }

    /// The reading at `rect`: at least 4.5:1, and the ink is `token`.
    private func measure(_ site: String, _ rect: CGRect, in w: HostedWindow, dark: Bool, ink token: Color = Theme.textPrimary) throws {
        let shot = try #require(Shot(w), "\(site): no shot")
        let reading = try #require(shot.read(rect), "\(site): nothing at \(rect)")
        let ratio = reading.ink.contrast(reading.ground)
        let expected = resolved(token, on: reading.ground, dark: dark)
        let scheme = dark ? "dark" : "light"
        #expect(ratio >= 4.5, "\(site), \(scheme): \(reading.ink) on \(reading.ground) is \(ratio)")
        #expect(reading.ink.distance(expected) < 0.08, "\(site), \(scheme): drew \(reading.ink), not \(expected)")
        save(site, rect, shot, line: String(format: "%.2f %@ %@ on %@ %@", ratio, scheme, reading.ink.description,
                                            reading.ground.description, site))
    }

    private func save(_ site: String, _ rect: CGRect, _ shot: Shot, line: String) {
        guard let dir = Self.shotsDir else { return }
        let log = URL(fileURLWithPath: dir).appendingPathComponent("notice-contrast.txt")
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        try? (text + line + "\n").write(to: log, atomically: true, encoding: .utf8)
        let box = rect.insetBy(dx: -8, dy: -8)
        let scale = CGAffineTransform(scaleX: 3, y: 3)
        guard let crop = shot.image.cgImage?.cropping(to: box.applying(scale)),
              let png = UIImage(cgImage: crop).pngData() else { return }
        let name = line.split(separator: " ").dropFirst(1).first.map(String.init) ?? "shot"
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(site.replacingOccurrences(of: " ", with: "-"))-\(name).png"))
    }

    private func saveWindow(_ name: String, _ w: HostedWindow) {
        guard let dir = Self.shotsDir, let shot = Shot(w), let png = shot.image.pngData() else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func onPage<V: View>(_ view: V) -> some View {
        ScrollView { view.padding(Theme.Metrics.screenPadding) }.background(Theme.background.ignoresSafeArea())
    }

    private func scheme(_ dark: Bool) -> ColorScheme { dark ? .dark : .light }

    /// A row's value, at the trailing end of a `StatRow`: the row is one element, and its title is in another ink.
    private func value(of row: CGRect) -> CGRect {
        CGRect(x: row.maxX - row.width / 3, y: row.minY, width: row.width / 3, height: row.height)
    }

    // MARK: Bedtime & wake

    private func planner(_ state: AppState, alarms: MockWakeAlarms, schedule: SleepSchedule) async -> BedtimePlanner {
        let planner = BedtimePlanner(state: state, alarms: alarms)
        await planner.update(schedule)
        return planner
    }

    private func bedtime(_ alarms: MockWakeAlarms? = nil, alarmOn: Bool = false, dark: Bool,
                         flags: [FeatureFlag: Bool] = [.sleepPlanner: true]) async -> some View {
        let state = AppState.preview(flags: flags)
        var schedule = SleepSchedule.default
        schedule.alarmOn = alarmOn
        let planner = await planner(state, alarms: alarms ?? MockWakeAlarms(), schedule: schedule)
        return NavigationStack { SleepScheduleView(planner: planner) }.previewEnvironment(state, scheme: scheme(dark))
    }

    @Test("Turn off Bedtime & wake", arguments: [false, true])
    func turnOff(dark: Bool) async throws {
        let view = await bedtime(dark: dark)
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let node = try await reveal("Turn off", in: w) { $0.label == "Turn off Bedtime & wake" }
            try measure("turn off", node.frame, in: w, dark: dark)
        }
    }

    @Test("The alarm iOS no longer allows", arguments: [false, true])
    func alarmProblem(dark: Bool) async throws {
        let alarms = MockWakeAlarms()
        alarms.allowed = false
        let view = await bedtime(alarms, alarmOn: true, dark: dark)
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let node = try await reveal("the alarm problem", in: w) { $0.label.hasPrefix("The wake-up alarm is off") }
            try measure("alarm problem", node.frame, in: w, dark: dark)
        }
    }

    @Test("The alarm iOS refuses when asked", arguments: [false, true])
    func alarmRefused(dark: Bool) async throws {
        let alarms = MockWakeAlarms()
        alarms.allows = false
        let view = await bedtime(alarms, dark: dark)
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let toggle = try await reveal("the alarm switch", in: w) { $0.label.hasPrefix("Wake me at my wake time") }
            toggle.activate()
            let node = try await reveal("the refusal", in: w) { $0.label == "Not allowed in iOS Settings." }
            try measure("alarm refused", node.frame, in: w, dark: dark)
        }
    }

    // MARK: Sleep

    @Test("High sleep debt", arguments: [false, true])
    func sleepDebt(dark: Bool) async throws {
        var day = MockData.todayDetail
        day.score.sleepDebtMin = 95
        let sleep = try #require(day.sleep)
        let view = onPage(SleepDaySection(sleep: sleep, score: day.score)).previewEnvironment(scheme: scheme(dark))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let node = try await reveal("the debt row", in: w) { $0.label.hasPrefix("Sleep debt") }
            try measure("sleep debt", value(of: node.frame), in: w, dark: dark)
        }
    }

    // MARK: Profile

    @Test("Consent out of date and Apple Health not asked", arguments: [false, true])
    func profileRows(dark: Bool) async throws {
        let state = AppState.preview()
        var user = MockData.user
        user.consent = nil
        state.user = user
        (state.env.health as? MockHealthStore)?.access = .notAsked
        try await HostedWindow.run(width: 390, height: 844, dark: dark, ProfileView().previewEnvironment(state, scheme: scheme(dark))) { w in
            let consent = try await reveal("the consent row", in: w) { $0.label.hasPrefix("Health-data consent") }
            try measure("consent", value(of: consent.frame), in: w, dark: dark)
            let health = try await reveal("the Apple Health row", in: w) { $0.label.hasPrefix("Apple Health") && $0.label.contains("Not requested") }
            try measure("apple health", value(of: health.frame), in: w, dark: dark)
        }
    }

    @Test("Sync details: the last error, a failed request, a resource that keeps failing", arguments: [false, true])
    func syncDetails(dark: Bool) async throws {
        let state = AppState.preview()
        let auth = state.env.auth
        let account = try #require(auth.accountID, "the preview is signed in")
        var engine = SyncEngineState()
        engine.lastError = "The upload was refused"
        engine.lastRequestID = "req-sample"
        engine.save(account: account, defaults: state.env.defaults)
        defer { SyncEngineState().save(account: account, defaults: state.env.defaults) }
        let at = state.env.clock.now()
        state.env.reads.seed([
            .me: ResourceState(fetchedAt: at, lastError: ResourceError(kind: .transient, status: 503, code: nil, requestID: "req-sample",
                                                                       transport: nil, attempts: 3, at: at),
                               consecutiveFailures: RefreshPolicy.failuresBeforeIssue),
        ])
        let api = APIStatus()
        api.record(APIStatus.RequestFailure(date: at, method: "GET", path: "/v1/me", status: 503, requestID: "req-sample"))
        let sync = SyncService(env: state.env)
        let model = SyncDetailsModel(state: state, sync: sync,
                                     coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: state.env.clock),
                                     apiStatus: api)
        let view = NavigationStack { SyncDetailsView(model: model) }.previewEnvironment(state, scheme: scheme(dark))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let error = try await reveal("the last error", in: w) { $0.label.hasPrefix("The upload was refused") }
            try measure("sync last error", error.frame, in: w, dark: dark)
            let row = try await reveal("the failing resource", in: w) { $0.label.contains("failed in a row") }
            try measure("sync loaded row", row.frame.divided(atDistance: 20, from: .maxYEdge).slice, in: w, dark: dark)
            let request = try await reveal("the failed request", in: w) { $0.label.hasPrefix("503 GET") }
            try measure("sync request", request.frame, in: w, dark: dark)
        }
    }

    @Test("A report that's too long", arguments: [false, true])
    func reportTooLong(dark: Bool) async throws {
        let state = AppState.preview()
        let model = ReportProblemModel(env: state.env, apiStatus: APIStatus()) { FeedbackSync() }
        model.stage(message: String(repeating: "a", count: 4_100))
        #expect(model.isTooLong)
        let view = NavigationStack { ReportProblemView(model: model) }.previewEnvironment(state, scheme: scheme(dark))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let node = try await reveal("the count", in: w) { $0.label.hasSuffix("/ 4000") }
            try measure("report too long", node.frame, in: w, dark: dark)
        }
    }

    // MARK: Train

    @Test("A paused plan", arguments: [false, true])
    func pausedPlan(dark: Bool) async throws {
        // The enrolment as the app last stored it. `setPaused` would write `UserDefaults.standard`, and the demo's source is shared.
        var catalog = MockTrain.catalog()
        catalog.active?.status = .paused
        let store = TrainStore(inMemory: true)
        store.cache(exercises: MockTrain.exercises)
        store.cache(plans: MockTrain.plans)
        store.saveDocument(catalog, key: "train.plans")
        let library = TrainLibrary(store: store, remote: { MockTrainSource() }, restore: true)
        #expect(library.isPaused)
        let view = NavigationStack { PlansView().trainDestinations() }.environment(library).previewEnvironment(scheme: scheme(dark))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let node = try await reveal("Paused", in: w) { $0.label.caseInsensitiveCompare("Paused") == .orderedSame }
            try measure("plan paused", node.frame, in: w, dark: dark, ink: Theme.textSecondary)
        }
    }

    @Test("Delete on your own plan", arguments: [false, true])
    func deletePlan(dark: Bool) async throws {
        let view = NavigationStack { PlanDetailView(planID: MockTrain.homeDumbbells.id) }.previewEnvironment(scheme: scheme(dark))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let node = try await reveal("Delete", in: w) { $0.label == "Delete" }
            try measure("plan delete", node.frame, in: w, dark: dark)
        }
    }

    @Test("The plate calculator's closest load", arguments: [false, true])
    func plates(dark: Bool) async throws {
        let view = PlateCalculatorSheet(target: 101.3).previewEnvironment(scheme: scheme(dark))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let node = try await reveal("Loaded", in: w) { $0.label.hasPrefix("Loaded") }
            try measure("plates loaded", value(of: node.frame), in: w, dark: dark, ink: Theme.textSecondary)
        }
    }

    @Test("The warm-up W in a past session", arguments: [false, true])
    func warmUpInHistory(dark: Bool) async throws {
        let id = try #require(MockTrain.history.last?.id)
        let view = NavigationStack { SessionDetailView(sessionID: id).trainDestinations() }.previewEnvironment(scheme: scheme(dark))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let card = try await reveal("the exercise with a warm-up", in: w) { $0.label.contains(", W, ") }
            // The set number's column on the first row: the title is above it and the numbers below draw another ink.
            let mark = CGRect(x: card.frame.minX + 16, y: card.frame.minY + 48, width: 28, height: 26)
            try measure("history warm-up", mark, in: w, dark: dark, ink: FocusedRowInk.warmUpMark)
        }
    }

    @Test("The warm-up W on the Focused page", arguments: [false, true])
    func warmUpInSession(dark: Bool) async throws {
        let controller = FocusedPreview.controller(.warmupsOpen)
        defer { controller.stop() }
        try await HostedWindow.run(width: 390, height: 844, dark: dark, SessionView(controller: controller)) { w in
            // The number's column, inside the active row's pill and clear of its unsaved dot, then on a plain row.
            func mark(_ row: CGRect) -> CGRect { CGRect(x: row.minX + 16, y: row.midY - 9, width: 20, height: 18) }
            let active = try await reveal("the active warm-up", in: w) { $0.label.hasPrefix("Set 1 of 2, warm-up") }
            try measure("session warm-up active", mark(active.frame), in: w, dark: dark, ink: FocusedRowInk.warmUpMark)
            let upcoming = try await reveal("the next warm-up", in: w) { $0.label.hasPrefix("Set 2 of 2, warm-up") }
            try measure("session warm-up", mark(upcoming.frame), in: w, dark: dark, ink: FocusedRowInk.warmUpMark)
        }
    }

    @Test("Every error in the Plan builder, and its panel", arguments: [false, true])
    func planBuilder(dark: Bool) async throws {
        var plan = MockTrain.homeDumbbells
        plan.name = ""
        plan.days[0].exercises[0].repsMin = 20
        plan.days[0].exercises[0].repsMax = 5
        plan.days.append(PlanDay(dayIndex: plan.days.count, name: "Day C", exercises: []))
        let view = PlanBuilderView(plan: plan).previewEnvironment(scheme: scheme(dark))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let save = try await reveal("Save", in: w) { $0.label == "Save" }
            save.activate()
            let panel = try await reveal("the panel", in: w) { $0.label.contains("Give the plan a name.") }
            try measure("builder panel", panel.frame.insetBy(dx: 6, dy: 6), in: w, dark: dark)
            let exercise = try await reveal("the exercise's issue", in: w) { $0.label.hasPrefix("Reps must be 1 to 100") }
            try measure("builder exercise", exercise.frame, in: w, dark: dark)
            let day = try await reveal("the day's issue", in: w) { $0.label == "Every day needs at least one exercise." }
            try measure("builder day", day.frame, in: w, dark: dark)
        }
    }

    @Test("Discard a saved import", arguments: [false, true])
    func discardImport(dark: Bool) async throws {
        let model = ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.savedOnPhone))
        let view = NavigationStack { ImportResultView(model: model) }.previewEnvironment(scheme: scheme(dark))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let node = try await reveal("Discard import", in: w) { $0.label == "Discard import" }
            try measure("import discard", node.frame, in: w, dark: dark)
        }
    }

    // MARK: Activities

    private func manualActivity(dark: Bool) throws -> some View {
        let state = AppState.preview(flags: [.todayMyDay: true, .activitiesManual: true])
        let saved = try #require(state.env.activities.save(manual: ActivityDraft(
            sport: .hiit, start: .now.addingTimeInterval(-3_600), end: .now.addingTimeInterval(-1_800), perceivedEffort: 8)))
        return NavigationStack { ActivityDetailView(route: ActivityRoute(id: saved.id, day: saved.start)) }
            .previewEnvironment(state, scheme: scheme(dark))
    }

    @Test("Delete an activity", arguments: [false, true])
    func deleteActivity(dark: Bool) async throws {
        try await HostedWindow.run(width: 390, height: 844, dark: dark, manualActivity(dark: dark)) { w in
            let node = try await reveal("Delete", in: w) { $0.label == "Delete" }
            try measure("activity delete", node.frame, in: w, dark: dark)
        }
    }

    private func editedSleep(dark: Bool) -> some View {
        let state = AppState.preview(flags: [.todayMyDay: true, .activitiesManual: true])
        let wake = state.env.clock.now().addingTimeInterval(-3_600)
        let night = ManualSleepSnapshot(day: DayFormat.string(from: wake), bed: wake.addingTimeInterval(-28_800), wake: wake,
                                        localRevision: 1, confirmedRevision: 1, deletedAt: nil, lastAttempt: nil)
        return AddSleepSheet(model: AddSleepModel(env: state.env, editing: night)).previewEnvironment(state, scheme: scheme(dark))
    }

    @Test("Delete a sleep entry", arguments: [false, true])
    func deleteSleep(dark: Bool) async throws {
        try await HostedWindow.run(width: 390, height: 844, dark: dark, editedSleep(dark: dark)) { w in
            let node = try await reveal("Delete this entry", in: w) { $0.label == "Delete this entry" }
            try measure("sleep delete", node.frame, in: w, dark: dark)
        }
    }

    // MARK: Journal

    private static let offline = "You're offline. Save again when you're back online."

    @Test("A journal setting that couldn't be saved", arguments: [false, true])
    func journalSettings(dark: Bool) async throws {
        let state = AppState.preview(online: false)
        let store = journalPreviewStore(state)
        let name = try #require(store.behaviors.first?.name)
        let view = NavigationStack { JournalSettingsView(store: store) }.previewEnvironment(state, scheme: scheme(dark))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let toggle = try await reveal(name, in: w) { $0.label.hasPrefix(name) }
            toggle.activate()
            let node = try await reveal("the error", in: w) { $0.label == Self.offline }
            try measure("journal settings", node.frame, in: w, dark: dark)
        }
    }

    private func textField(in view: UIView) -> UITextField? {
        if let text = view as? UITextField { return text }
        for sub in view.subviews { if let text = textField(in: sub) { return text } }
        return nil
    }

    @Test("A behavior that couldn't be added", arguments: [false, true])
    func journalAdd(dark: Bool) async throws {
        let state = AppState.preview(online: false)
        let view = AddBehaviorSheet(store: journalPreviewStore(state)).previewEnvironment(state, scheme: scheme(dark))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            try await w.settle()
            let name = try #require(textField(in: w.host.view))
            name.text = "Sample"
            name.sendActions(for: .editingChanged)
            try await w.wait("Add to enable") { w.node("Add", exactly: true)?.isEnabled == true }
            try #require(w.node("Add", exactly: true)).activate()
            let node = try await reveal("the error", in: w) { $0.label == Self.offline }
            try measure("journal add", node.frame, in: w, dark: dark)
        }
    }

    // MARK: the destructive labels at their tightest

    enum Destructive: String, CaseIterable, CustomTestStringConvertible {
        case turnOff = "Turn off Bedtime & wake", plan = "Delete", importJob = "Discard import", activity = "Delete an activity"
        case sleep = "Delete this entry"
        var testDescription: String { rawValue }
        var title: String { self == .activity ? "Delete" : rawValue }
    }

    private func view(_ label: Destructive) async throws -> AnyView {
        switch label {
        case .turnOff: return await AnyView(bedtime(dark: false))
        case .plan: return AnyView(NavigationStack { PlanDetailView(planID: MockTrain.homeDumbbells.id) }.previewEnvironment(scheme: .light))
        case .importJob:
            let model = ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.savedOnPhone))
            return AnyView(NavigationStack { ImportResultView(model: model) }.previewEnvironment(scheme: .light))
        case .activity: return try AnyView(manualActivity(dark: false))
        case .sleep: return AnyView(editedSleep(dark: false))
        }
    }

    /// English; the crops go to `ORBIT_SHOTS_DIR`, for the eye: a frame can't tell a good wrap from a bad one.
    @Test("Each destructive label fits at 320 pt, by default and at AX3", arguments: Destructive.allCases, [false, true])
    func destructiveLabels(_ label: Destructive, ax3: Bool) async throws {
        let view = try await view(label)
        try await HostedWindow.run(width: 320, height: 693, dark: false, typeSize: ax3 ? .accessibility3 : .large,
                                   category: ax3 ? .accessibilityExtraLarge : .large, view) { w in
            let node = try await reveal(label.title, in: w) { $0.label == label.title }
            #expect(node.frame.minX >= 0 && node.frame.maxX <= 320, "\(node.frame)")
            #expect(node.frame.height > 43.9, "\(node.frame)")
            saveWindow("label-\(label.rawValue.replacingOccurrences(of: " ", with: "-"))-\(ax3 ? "ax3" : "default")", w)
        }
    }

    // MARK: alone in their views

    @Test("Saving workouts not allowed", arguments: [false, true])
    func healthHint(dark: Bool) async throws {
        try await HostedWindow.run(width: 390, height: 844, dark: dark, onPage(HealthWriteAccessHint())) { w in
            let node = try await reveal("the hint", in: w) { $0.label.hasPrefix("Allow it in Health") }
            try measure("health hint", node.frame, in: w, dark: dark)
        }
    }

    @Test("A signal that needs fixing", arguments: [false, true])
    func checkRow(dark: Bool) async throws {
        let view = onPage(CheckRow(name: "Heart rate", result: "Not arriving", kind: .fix))
        try await HostedWindow.run(width: 390, height: 844, dark: dark, view) { w in
            let node = try await reveal("the row", in: w) { $0.label.hasPrefix("Heart rate") }
            try measure("check row glyph", node.frame.divided(atDistance: 26, from: .minXEdge).slice, in: w, dark: dark)
        }
    }
}
