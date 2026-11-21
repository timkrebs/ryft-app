import SwiftUI
import Testing
import UIKit
@testable import Ryft

// Activities in Nocturne (docs/work/2026-11-16-nocturne/design-pr6-b-train.md §10, §14.2's Activities rows): the effort scale
// (the selection in ink, its spoken value, three columns from AX1, circles that keep a gap on 320 pt), Save off until the form
// is valid and once it saved, a save that can't write, the Strength suggestion, the footer per sport, the chip rows and the
// Duration row at large text, Add sleep, the detail's sync line and strain states (offline included) and its reading order,
// tied fastest splits. Layout checks run in a window.

// MARK: - rules (no window)

@MainActor
@Suite("Activities in Nocturne: rules")
struct ActivitiesNocturneRuleTests {
    @Test func theSelectedEffortIsInkNeverAnAccent() {
        #expect(EffortScaleSpec.fill(selected: true) == Theme.textPrimary)
        #expect(EffortScaleSpec.ink(selected: true) == Theme.background)
        #expect(EffortScaleSpec.fill(selected: false) == .clear)
        #expect(EffortScaleSpec.ink(selected: false) == Theme.textPrimary)
        #expect(EffortScaleSpec.weight(selected: true) == .bold && EffortScaleSpec.weight(selected: false) == .regular)
        // L27: teal is recovery's, Volt is "now"; neither marks a choice.
        #expect(EffortScaleSpec.fill(selected: true) != Theme.recovery)
        #expect(EffortScaleSpec.fill(selected: true) != Theme.accentSecondary)
    }

    @Test func theEffortSpeaksItsNumberAndWord() {
        #expect(EffortScale.spokenValue(7) == "7 of 10, Hard")
        #expect(EffortScale.spokenValue(1) == "1 of 10, Very easy")
        #expect(EffortScale.spokenValue(10) == "10 of 10, Maximal")
        #expect(EffortScale.spokenValue(nil) == "Not set")
        #expect(EffortScale.caption(7) == "7 · Hard")
    }

    @Test func fiveColumnsUntilAX1ThenThree() {
        for size in [DynamicTypeSize.xSmall, .large, .xxxLarge] { #expect(EffortScaleSpec.columns(for: size) == 5, "\(size)") }
        for size in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            #expect(EffortScaleSpec.columns(for: size) == 3, "\(size)")
        }
    }

    /// At 10:00 by the env's clock: the default hour and the half hour after its start are behind it. On the wall clock in
    /// the half hour after midnight the default starts at midnight, and its start plus 30 minutes ends in the future.
    @Test func saveStaysOffUntilTheFormIsValid() {
        let ten = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now
        let env = AppEnvironment.test(clock: TestClock(now: ten), flags: [.todayMyDay: true, .activitiesManual: true])
        let model = AddActivityModel(env: env, day: ten)
        #expect(model.start == ten.addingTimeInterval(-3_600) && model.end == ten, "09:00 to 10:00")
        #expect(model.canSave, "the default hour is valid")
        model.end = model.start.addingTimeInterval(-60)
        #expect(!model.canSave && model.issues.contains(.endBeforeStart))
        model.end = model.start.addingTimeInterval(1_800)
        model.sport = .running
        model.distanceText = "0"
        #expect(!model.canSave && model.issues == [.distanceInvalid])
        model.distanceText = "5.2"
        #expect(model.canSave)
    }

    @Test func strengthSuggestsTrainUntilAddHereAnyway() throws {
        let state = ActivitiesShotFixtures.state()
        let model = AddActivityModel(env: state.env, day: .now)
        model.sport = .strength
        #expect(model.suggestsTrain && !model.showsDistance)
        model.addsStrengthHere = true
        #expect(!model.suggestsTrain)
        // Editing a strength activity never suggests it.
        let saved = try #require(state.env.activities.save(manual: ActivityDraft(
            sport: .strength, start: .now.addingTimeInterval(-3_600), end: .now.addingTimeInterval(-1_800))))
        let edit = AddActivityModel(env: state.env, editing: saved.activity, merged: false)
        #expect(!edit.suggestsTrain)
    }

    @Test func theTileSplitsItsNumberFromItsUnit() {
        #expect(ActivityDetailViewModel.splitUnit("8.4 km") == ("8.4", "km"))
        #expect(ActivityDetailViewModel.splitUnit("5:34\u{00A0}/km") == ("5:34", "/km"))
        #expect(ActivityDetailViewModel.splitUnit("42") == ("42", nil))
    }

    @Test func theCircleNeverOutgrowsItsColumn() {
        // Not measured yet: the size's cap.
        #expect(EffortScaleSpec.diameter(scaled: 62, typeSize: .xxxLarge, width: 0) == EffortScaleSpec.maxDiameter)
        // 390 pt: 318 inside the card (390 − 2 × 20 − 2 × 16), 46 at the default size, 54 at xxxLarge.
        #expect(EffortScaleSpec.diameter(scaled: 46, typeSize: .large, width: 318) == 46)
        #expect(EffortScaleSpec.diameter(scaled: 62, typeSize: .xxxLarge, width: 318) == EffortScaleSpec.maxDiameter)
        // 320 pt: 248 inside, five columns of 49.6, each circle 4 short of it.
        #expect(abs(EffortScaleSpec.diameter(scaled: 62, typeSize: .xxxLarge, width: 248) - 45.6) < 0.01)
        // From AX1 three columns: 248 / 3 − 4, under the 84 cap.
        #expect(abs(EffortScaleSpec.diameter(scaled: 120, typeSize: .accessibility3, width: 248) - (248.0 / 3 - 4)) < 0.01)
    }

    @Test func theFooterSaysEffortMakesStrainOnlyWhereItDoes() {
        #expect(!AddActivityModel.effortMakesStrain(for: .mobility), "the detail says mobility has no strain without heart rate")
        for sport in [Sport.running, .padel, .hiit, .yoga, .climbing, .other] {
            #expect(AddActivityModel.effortMakesStrain(for: sport), "\(sport)")
        }
    }

    @Test func saveRunsOnceThenStaysOff() throws {
        let state = ActivitiesShotFixtures.state()
        let model = AddActivityModel(env: state.env, day: .now)
        let day = DayFormat.string(from: model.start)
        let before = state.env.activities.snapshots(onDay: day).count
        #expect(model.save())
        #expect(model.didSave && !model.canSave)
        #expect(!model.save(), "a second tap writes nothing")
        #expect(state.env.activities.snapshots(onDay: day).count == before + 1)

        // Two days back: the default night (23:00 to 07:00) is whole whatever the time now.
        let sleep = AddSleepModel(env: state.env, day: DayFormat.shift(.now, days: -2))
        #expect(sleep.save())
        #expect(sleep.didSave && !sleep.canSave && !sleep.save())
    }

    @Test func addSleepOpensLargeFromXLarge() {
        #expect(AddSleepSheet.detents(for: .large) == [.medium, .large])
        #expect(AddSleepSheet.detents(for: .xLarge) == [.large])
        #expect(AddSleepSheet.detents(for: .accessibility3) == [.large])
    }

    @Test func theDistanceUnitIsSaidByName() {
        #expect(AddActivitySheet.unitName(Locale(identifier: "en_US")) == "miles")
        #expect(AddActivitySheet.unitName(Locale(identifier: "en_DE")) == "kilometres")
    }

    @Test func tiedFastestSplitsAreMarkedAsTheyRead() {
        func split(_ index: Int, _ seconds: Double, _ metres: Double = 1_000) -> ActivitySplit {
            ActivitySplit(index: index, distanceM: metres, durationSec: seconds, ascentM: nil)
        }
        // 5:34.4 and 5:33.6 both read 5:34 /km: a tie on screen is a tie in the table.
        #expect(SplitsTable.fastest([split(1, 340), split(2, 334.4), split(3, 333.6)], paceStyle: .pace) == [2, 3])
        #expect(SplitsTable.fastest([split(1, 340), split(2, 333)], paceStyle: .pace) == [2])
        // The partial last split counts per kilometre: 0.5 km in 2:40 is 5:20 /km.
        #expect(SplitsTable.fastest([split(1, 340), split(2, 160, 500)], paceStyle: .pace) == [2])
        // One split, or all reading the same: none is fastest.
        #expect(SplitsTable.fastest([split(1, 340)], paceStyle: .pace).isEmpty)
        #expect(SplitsTable.fastest([split(1, 340), split(2, 340.2)], paceStyle: .pace).isEmpty)
        // Speed in tenths of km/h: 1 km in 150 s and in 150.2 s both read 24.0 km/h.
        #expect(SplitsTable.fastest([split(1, 150), split(2, 150.2), split(3, 160)], paceStyle: .speed) == [1, 2])
    }
}

// MARK: - the detail's sync line (offline-first)

@MainActor
@Suite("Activities in Nocturne: the detail's sync line")
struct ActivityDetailSyncLineTests {
    @MainActor
    private struct Graph {
        let clock: TestClock
        let api: MockPlatformAPI
        let env: AppEnvironment
        let state: AppState

        init(online: Bool) {
            let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
            clock = TestClock(now: noon)
            api = MockPlatformAPI(activities: MockActivitiesSource(now: { [clock] in clock.now() }))
            env = .test(api: api, clock: clock, flags: [.todayMyDay: true, .activitiesManual: true], online: online)
            state = AppState(env: env)
        }

        /// A HIIT session rated 8, saved on this iPhone today; its id.
        func saveHIIT() throws -> UUID {
            let model = AddActivityModel(env: env, day: clock.now())
            model.sport = .hiit
            model.effort = 8
            try #require(model.save())
            return try #require(env.activities.snapshots(onDay: DayFormat.string(from: clock.now())).first?.id)
        }

        /// The platform's activities as this iPhone cached them.
        func seedServer() -> [SportActivity] {
            let all = MockActivitiesSource.demo(on: clock.now())
            for day in Set(all.map { DayFormat.string(from: $0.start) }) {
                state.repository.seed(.activities(all.filter { DayFormat.string(from: $0.start) == day }, day: day))
            }
            return all
        }

        func detail(_ id: UUID, on day: Date) -> ActivityDetailViewModel {
            ActivityDetailViewModel(route: ActivityRoute(id: id, day: day), state: state)
        }
    }

    @Test func aCachedActivityOpenedOfflineSaysItIsWhatThisIPhoneHas() throws {
        let g = Graph(online: false)
        let run = try #require(g.seedServer().first { $0.mergedWith != nil })
        let detail = g.detail(run.id, on: run.start)
        #expect(detail.activity != nil, "drawn from the cache, no spinner")
        #expect(detail.syncLine == .offlineCache)
        #expect(detail.strainLine == .heartRate(run.strain ?? 0, source: run.hrSource), "the platform's score, cached")
    }

    @Test func onlineAndAtRYFTThereIsNoLine() throws {
        let g = Graph(online: true)
        let run = try #require(g.seedServer().first { $0.mergedWith != nil })
        #expect(g.detail(run.id, on: run.start).syncLine == nil)
    }

    @Test func savedOfflineShowsItsUploadAndNeverAScore() async throws {
        let g = Graph(online: false)
        // The account is ready (the test env holds uploads at consent until told otherwise): only the network waits.
        g.env.uploader.gate = { _ in nil }
        let id = try g.saveHIIT()
        await g.env.uploader.flush(userInitiated: true)

        let detail = g.detail(id, on: g.clock.now())
        // The upload's line wins over the offline one: one line at a time.
        #expect(detail.syncLine == .upload(.offline))
        #expect(detail.strainLine == .notAtRYFT, "no score, and no word of heart rate, until RYFT has it")
    }

    /// Where RYFT doesn't have the activity yet, each way it can be held.
    enum Unsent: String, CaseIterable, Sendable {
        case uploading, offline, retrying, refused, gated, notAvailableYet
    }

    /// The upload note's case, without its attempt.
    private static func name(_ note: ActivityDetailViewModel.UploadNote?) -> String {
        switch note {
        case .uploading?: return "uploading"
        case .offline?: return "offline"
        case .notAvailableYet?: return "notAvailableYet"
        case .gated?: return "gated"
        case .accountDeleting?: return "accountDeleting"
        case .retrying?: return "retrying"
        case .refused?: return "refused"
        case .failed?: return "failed"
        case nil: return "none"
        }
    }

    @Test("Strain arrives once RYFT has the activity, not \"Waiting for heart rate\", while it isn't there",
          arguments: Unsent.allCases)
    func strainWaitsForRYFTWhileUnsent(_ unsent: Unsent) async throws {
        let g = Graph(online: unsent != .offline)
        g.env.uploader.gate = unsent == .gated ? { _ in .gate(.consentRequired) } : { _ in nil }
        switch unsent {
        case .retrying: g.api.failNext = APIError.transport(URLError(.timedOut))
        case .refused: g.api.failNext = APIError.http(422, "end in the future", requestID: "req-422")
        case .notAvailableYet: g.api.failNext = APIError.http(404, "not found")
        case .uploading, .offline, .gated: break
        }
        let id = try g.saveHIIT()
        // Uploading: queued, not sent yet.
        if unsent != .uploading { await g.env.uploader.flush(userInitiated: true) }

        let detail = g.detail(id, on: g.clock.now())
        #expect(Self.name(detail.uploadNote) == unsent.rawValue)
        #expect(detail.serverCopy == nil)
        #expect(detail.strainLine == .notAtRYFT)
    }

    @Test func heldWhileTheAccountIsDeletedStrainWaitsForRYFT() async throws {
        let hold = RequestHold()
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let auth = AuthService(client: MockAuthClient(session: .preview(id: UUID())), settings: Settings(defaults: defaults),
                               defaults: defaults, wipeLocalData: { _ in true },
                               deleteRemoteAccount: {
                                   await hold.wait()
                                   throw APIError.http(503, "")
                               },
                               postAppleAuthorization: { _ in })
        let clock = TestClock()
        let env = AppEnvironment.test(api: MockPlatformAPI(), clock: clock, auth: auth, flags: [.activitiesManual: true])
        env.uploader.gate = { _ in nil }
        let state = AppState(env: env)
        state.bindAccountHooks(auth, apiStatus: APIStatus())
        let end = clock.now().addingTimeInterval(-3_600)
        let saved = env.activities.save(manual: ActivityDraft(sport: .running, start: end.addingTimeInterval(-1_800), end: end))
        let id = try #require(saved?.id)
        let detail = ActivityDetailViewModel(route: ActivityRoute(id: id, day: end), state: state)

        let deleting = Task { await auth.deleteAccount() }
        #expect(await eventually { auth.isDeletingAccount })
        #expect(detail.uploadNote == .accountDeleting)
        #expect(detail.strainLine == .notAtRYFT)
        hold.release()
        _ = await deleting.value
    }

    @Test func waitingForHeartRateOnlyOnceRYFTHasIt() throws {
        let g = Graph(online: true)
        // The demo's yoga: at the platform, not scored yet.
        let yoga = try #require(g.seedServer().first { $0.sport == .yoga })
        let detail = g.detail(yoga.id, on: yoga.start)
        #expect(detail.serverCopy != nil && yoga.strain == nil)
        #expect(detail.strainLine == .waiting)
    }

    @Test func gatedSaysItUploadsOnceTheAccountIsReady() async throws {
        let g = Graph(online: true)
        g.env.uploader.gate = { _ in .gate(.consentRequired) }
        let id = try g.saveHIIT()
        await g.env.uploader.flush(userInitiated: true)
        #expect(g.detail(id, on: g.clock.now()).syncLine == .upload(.gated))
    }
}

// MARK: - in a window

@MainActor
@Suite("Activities in Nocturne: in a window", .serialized)
struct ActivitiesNocturneHostedTests {
    private func run(_ content: some View, width: CGFloat = 390, height: CGFloat = 1_600, typeSize: DynamicTypeSize = .large,
                     category: UIContentSizeCategory = .large, waitFor identifier: String,
                     body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: width, height: height, bottomInset: 0, typeSize: typeSize, category: category,
                                   content) { w in
            try await w.wait(identifier) { w.nodes().contains { $0.identifier == identifier } }
            try await w.settle()
            try await body(w)
        }
    }

    private func node(_ w: HostedWindow, _ identifier: String) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == identifier }, "\(identifier) on screen")
    }

    // MARK: the effort scale

    /// One scale, 350 wide on `surface`, its value bound to `value`.
    private struct ScaleHost: View {
        @State var value: Int?
        var body: some View {
            EffortScale(value: $value)
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.surface)
        }
    }

    @Test func theSelectedCircleIsFilledInInkAndReadsAsOneAdjustableElement() async throws {
        try await run(ScaleHost(value: 7), height: 400, waitFor: "effortScale") { w in
            let scale = try node(w, "effortScale")
            #expect(scale.label == "Perceived effort")
            #expect(scale.value == "7 of 10, Hard")
            #expect(scale.isAdjustable)
            #expect(scale.actionNames.contains("Clear"))
            #expect(w.nodes().filter { $0.identifier?.hasPrefix("effortScale") == true }.count == 1, "one element for VoiceOver")

            // 7 is the second circle of the second row; 6 the first. Sampled under the number, inside the circle.
            let d = EffortScaleSpec.diameter, column = scale.frame.width / CGFloat(EffortScaleSpec.columns)
            let y = scale.frame.minY + d + EffortScaleSpec.rowSpacing + d / 2 + d * 0.36
            let seven = try #require(w.pixel(at: CGPoint(x: scale.frame.minX + column * 1.5, y: y)))
            let six = try #require(w.pixel(at: CGPoint(x: scale.frame.minX + column * 0.5, y: y)))
            #expect(seven.r > 0.85 && seven.g > 0.85 && seven.b > 0.8, "ink fill \(seven)")
            #expect(abs(seven.r - seven.g) < 0.06 && abs(seven.g - seven.b) < 0.08, "neutral, no teal or Volt \(seven)")
            #expect(six.r < 0.25 && six.g < 0.25 && six.b < 0.25, "the others are open \(six)")
        }
    }

    @Test func theScaleAdjustsAndClears() async throws {
        try await run(ScaleHost(value: nil), height: 400, waitFor: "effortScale") { w in
            #expect(try node(w, "effortScale").value == "Not set")
            try node(w, "effortScale").increment()
            try await w.wait("1") { (try? node(w, "effortScale").value) == "1 of 10, Very easy" }
            let scale = try node(w, "effortScale")
            #expect(scale.perform(action: "Clear"))
            try await w.wait("cleared") { (try? node(w, "effortScale").value) == "Not set" }
        }
    }

    @Test func threeColumnsFromAX1() async throws {
        // No value: no line under the grid, so the element is only its rows.
        try await run(ScaleHost(value: nil), height: 900, typeSize: .accessibility1, category: .accessibilityMedium,
                      waitFor: "effortScale") { w in
            let height = try node(w, "effortScale").frame.height
            // Four rows of three (the circle between 46 and the large-text cap); two rows of five would need a circle
            // past the cap.
            let fourRows = (height - 3 * EffortScaleSpec.rowSpacing) / 4
            #expect(fourRows >= EffortScaleSpec.diameter && fourRows <= EffortScaleSpec.maxLargeTextDiameter + 0.5,
                    "height \(height), circle \(fourRows)")
        }
        try await run(ScaleHost(value: nil), height: 600, typeSize: .xxxLarge, category: .extraExtraExtraLarge,
                      waitFor: "effortScale") { w in
            let height = try node(w, "effortScale").frame.height
            let twoRows = (height - EffortScaleSpec.rowSpacing) / 2
            #expect(twoRows >= EffortScaleSpec.diameter && twoRows <= EffortScaleSpec.maxDiameter + 0.5,
                    "height \(height), circle \(twoRows)")
        }
    }

    // MARK: Add activity

    @Test func saveIsOffWithTheFirstReasonAsItsHint() async throws {
        let invalid = ActivitiesShotFixtures.add { $0.end = $0.start.addingTimeInterval(-600) }
        try await run(invalid, waitFor: "addActivity.save") { w in
            let save = try node(w, "addActivity.save")
            #expect(!save.isEnabled)
            #expect(save.hint == AddActivityModel.message(.endBeforeStart))
            #expect(w.nodes().contains { $0.identifier == "addActivity.issue.endBeforeStart" })
            #expect(w.nodes().contains { $0.identifier == "sheet.close" && $0.label == "Cancel" })
        }
        try await run(ActivitiesShotFixtures.add(ActivitiesShotFixtures.fill), waitFor: "addActivity.save") { w in
            let save = try node(w, "addActivity.save")
            #expect(save.isEnabled)
            // The system's controls (the chips' compact pickers, the distance and notes fields) keep their identifiers in
            // UIKit, out of this walk: `AddActivityUITests` drives `addActivity.start(.time)`, `.end(.time)` and `.notes`.
            for id in ["sheet.close", "addActivity.sport", "addActivity.duration", "effortScale", "addActivity.footer"] {
                #expect(w.nodes().contains { $0.identifier == id }, "\(id) in \(w.nodes().compactMap(\.identifier).sorted())")
            }
        }
    }

    @Test func strengthShowsTheSuggestionThenItsOneLine() async throws {
        let state = ActivitiesShotFixtures.state()
        let model = AddActivityModel(env: state.env, day: .now)
        model.sport = .strength
        try await run(AddActivitySheet(model: model).previewEnvironment(state), waitFor: "addActivity.logInTrain") { w in
            let ids = Set(w.nodes().compactMap(\.identifier))
            #expect(ids.contains("addActivity.logInTrain") && ids.contains("addActivity.addAnyway"))
            #expect(!ids.contains("addActivity.footer"), "strength has no strain footnote")
            #expect(!ids.contains("addActivity.distance"))
            let addAnyway = try node(w, "addActivity.addAnyway")
            #expect(addAnyway.activate())
            try await w.wait("the one line") {
                w.nodes().contains { $0.identifier == "addActivity.strengthNote.logInTrain" }
            }
            #expect(!w.nodes().contains { $0.identifier == "addActivity.logInTrain" })
            #expect(model.addsStrengthHere)
        }
    }

    // MARK: saving

    /// Presents `sheet` over the window's page as a sheet is presented (its own hosting controller, modally), and waits for its
    /// Save. Whether it is still up is UIKit's `presentedViewController`; SwiftUI's `dismiss` dismisses it.
    private func present(_ sheet: some View, over w: HostedWindow) async throws {
        w.host.present(UIHostingController(rootView: AnyView(sheet)), animated: false)
        try await w.wait("the sheet's Save", timeout: .seconds(20)) { sheetElement(w, "addActivity.save") != nil }
    }

    /// The presented sheet's elements (`HostedWindow.nodes()` walks the page only), in tree order.
    private func sheetElements(_ w: HostedWindow) -> [NSObject] {
        guard let root = w.host.presentedViewController?.view else { return [] }
        var found: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ object: NSObject, depth: Int) {
            guard depth < 40, seen.insert(ObjectIdentifier(object)).inserted else { return }
            if String(describing: type(of: object)) == "AccessibilityNode" { found.append(object) }
            if let elements = object.accessibilityElements {
                for case let child as NSObject in elements { walk(child, depth: depth + 1) }
            } else {
                let count = object.accessibilityElementCount()
                if count != NSNotFound, count > 0 {
                    for i in 0..<count { if let child = object.accessibilityElement(at: i) as? NSObject { walk(child, depth: depth + 1) } }
                }
            }
            if let view = object as? UIView { for sub in view.subviews { walk(sub, depth: depth + 1) } }
        }
        walk(root, depth: 0)
        return found
    }

    private func sheetElement(_ w: HostedWindow, _ identifier: String) -> NSObject? {
        sheetElements(w).first { ($0.value(forKey: "accessibilityIdentifier") as? String) == identifier }
    }

    /// Whether the sheet is still up, and not on its way down, for all of `duration`: time for a dismissal to start, were
    /// there one (SwiftUI's `dismiss` animates, so `presentedViewController` alone would clear only after it).
    private func sheetStaysUp(_ w: HostedWindow, for duration: Duration = .seconds(2)) async throws -> Bool {
        let end = ContinuousClock.now + duration
        while ContinuousClock.now < end {
            guard let sheet = w.host.presentedViewController, !sheet.isBeingDismissed else { return false }
            try await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    /// The window's page, under the sheet.
    private var page: some View {
        Text(verbatim: "page").accessibilityIdentifier("page").frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @Test func aSaveThatCannotWriteKeepsTheSheetAndOffersTryAgain() async throws {
        // Signed out meanwhile: nothing can be written on this iPhone (a real failure, not the preview flag).
        let env = AppEnvironment.test(auth: .preview(signedIn: false), flags: [.todayMyDay: true, .activitiesManual: true])
        let state = AppState(env: env)
        let model = AddActivityModel(env: env, day: env.clock.now())
        try #require(model.canSave, "a valid form: only the write fails")
        model.notes = "Kept as typed"
        var saved = 0
        let sheet = AddActivitySheet(model: model, onSaved: { saved += 1 }).previewEnvironment(state)
        try await run(page, waitFor: "page") { w in
            try await present(sheet, over: w)
            defer { w.host.dismiss(animated: false) }
            let save = try #require(sheetElement(w, "addActivity.save"))
            #expect(save.accessibilityActivate())
            try await w.wait("Try again") { sheetElement(w, "addActivity.saveError.retry") != nil }
            #expect(sheetElements(w).contains { $0.accessibilityLabel == "Couldn't save on this iPhone." })
            let stays = try await sheetStaysUp(w)
            #expect(stays, "the sheet stays")
            #expect(saved == 0, "nothing was saved")
            #expect(model.notes == "Kept as typed" && !model.didSave)
            let again = try #require(sheetElement(w, "addActivity.save"))
            #expect(!again.accessibilityTraits.contains(.notEnabled), "ready to try again")

            // Try again fails the same way and keeps the sheet too.
            let retry = try #require(sheetElement(w, "addActivity.saveError.retry"))
            #expect(retry.accessibilityActivate())
            let staysAgain = try await sheetStaysUp(w)
            #expect(staysAgain, "the sheet stays")
            #expect(saved == 0)
            #expect(sheetElement(w, "addActivity.saveError.retry") != nil)
        }
    }

    @Test func aSaveClosesTheSheetAndASecondTapWritesNothing() async throws {
        let state = ActivitiesShotFixtures.state()
        let model = AddActivityModel(env: state.env, day: .now)
        let day = DayFormat.string(from: model.start)
        let before = state.env.activities.snapshots(onDay: day).count
        var saved = 0
        let sheet = AddActivitySheet(model: model, onSaved: { saved += 1 }).previewEnvironment(state)
        try await run(page, waitFor: "page") { w in
            try await present(sheet, over: w)
            defer { if w.host.presentedViewController != nil { w.host.dismiss(animated: false) } }
            let save = try #require(sheetElement(w, "addActivity.save"))
            #expect(save.accessibilityActivate())
            _ = save.accessibilityActivate() // while the sheet closes
            try await w.wait("the sheet closes", timeout: .seconds(20)) { w.host.presentedViewController == nil }
            #expect(saved == 1)
            #expect(state.env.activities.snapshots(onDay: day).count == before + 1, "one activity, not two")
        }
    }

    // MARK: Add sleep

    /// The system date pickers behind the chips (UIKit's, outside SwiftUI's nodes), top to bottom, then left to right.
    private func datePickers(_ w: HostedWindow) -> [UIDatePicker] {
        func walk(_ view: UIView) -> [UIDatePicker] {
            if let picker = view as? UIDatePicker { return [picker] }
            return view.subviews.flatMap(walk)
        }
        // By the centre: a time picker is taller than a date picker over chips of one height.
        return walk(w.window).sorted { a, b in
            let fa = a.convert(a.bounds, to: w.window), fb = b.convert(b.bounds, to: w.window)
            if abs(fa.midY - fb.midY) > 2 { return fa.midY < fb.midY }
            return fa.minX < fb.minX
        }
    }

    private func frames(_ pickers: [UIDatePicker], in w: HostedWindow) -> [CGRect] {
        pickers.map { $0.convert($0.bounds, to: w.window) }
    }

    @Test func addSleepSaveIsOffWithItsReasonAndItsChipsHoldTheNight() async throws {
        let state = ActivitiesShotFixtures.state()
        let model = AddSleepModel(env: state.env, day: DayFormat.shift(.now, days: -2))
        model.wake = model.bed.addingTimeInterval(1_800)
        let sheet = AddSleepSheet(model: model).previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US"))
        try await run(sheet, waitFor: "addSleep.save") { w in
            let save = try node(w, "addSleep.save")
            let issue = try #require(model.issues.first)
            #expect(!save.isEnabled)
            #expect(save.hint == AddSleepModel.message(issue))
            #expect(w.nodes().contains { $0.identifier == "addSleep.issue.\(issue)" })
            #expect(try node(w, "sheet.close").label == "Cancel", "a form to discard")
            // Two chips a row, the date and the time, holding the night as the model has it.
            let pickers = datePickers(w)
            try #require(pickers.count == 4, "two rows of two chips")
            #expect(pickers.map(\.datePickerMode) == [.date, .time, .date, .time])
            #expect(pickers[0].date == model.bed && pickers[1].date == model.bed)
            #expect(pickers[2].date == model.wake && pickers[3].date == model.wake)
            for label in ["Went to bed", "Woke up"] {
                #expect(w.nodes().contains { $0.label == label }, "\(label) names its row")
            }
            // Each chip has its own name: VoiceOver doesn't read "Went to bed" twice.
            #expect(pickers.map { $0.accessibilityLabel ?? "" }
                == ["Date you went to bed", "Time you went to bed", "Date you woke up", "Time you woke up"])
        }
        // Where the tracker has the night there is no form: nothing to discard, so "Close", and no Save.
        let recorded = AddSleepModel(env: state.env, day: .now, night: { _ in .recorded })
        try await run(AddSleepSheet(model: recorded).previewEnvironment(state), waitFor: "sheet.close") { w in
            let close = try node(w, "sheet.close")
            #expect(close.label == "Close")
            #expect(!w.nodes().contains { $0.identifier == "addSleep.save" })
        }
    }

    // MARK: large text

    /// One line of each word in the row's font, out of the way: what a label needs to stay on one line.
    private func probes(_ words: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(words, id: \.self) { word in
                Text(verbatim: word)
                    .font(.ryft(.callout))
                    .fixedSize()
                    .accessibilityLabel(Text(verbatim: "probe \(word)"))
            }
        }
    }

    @Test("At xxLarge a chip row's label keeps its line, beside its chips or above them", arguments: ["activity", "sleep"])
    func chipRowLabelsStayWholeAtXXLarge(_ sheet: String) async throws {
        let state = ActivitiesShotFixtures.state()
        let labels = sheet == "activity" ? ["Start", "End"] : ["Went to bed", "Woke up"]
        let content = sheet == "activity"
            ? AnyView(AddActivitySheet(model: AddActivityModel(env: state.env, day: .now)))
            : AnyView(AddSleepSheet(model: AddSleepModel(env: state.env, day: DayFormat.shift(.now, days: -2))))
        let view = content.previewEnvironment(state)
            .environment(\.locale, Locale(identifier: "en_US"))
            .overlay(alignment: .bottomLeading) { probes(labels) }
        try await run(view, typeSize: .xxLarge, category: .extraExtraLarge, waitFor: "sheet.close") { w in
            let pickers = frames(datePickers(w), in: w)
            try #require(pickers.count == 4)
            for (row, label) in labels.enumerated() {
                let text = try #require(w.nodes().first { $0.label == label }, "\(label)")
                let probe = try #require(w.nodes().first { $0.label == "probe \(label)" })
                #expect(text.frame.height <= probe.frame.height + 1, "\(label) on one line: \(text.frame), one line is \(probe.frame)")
                #expect(text.frame.width >= probe.frame.width - 1, "\(label) not squeezed: \(text.frame)")
                let date = pickers[row * 2], time = pickers[row * 2 + 1]
                let beside = abs(date.midY - text.frame.midY) < 2 && date.minX >= text.frame.maxX
                let under = date.minY >= text.frame.maxY - 1
                #expect(beside || under, "\(label)'s chips beside or under it: \(text.frame) \(date)")
                #expect(time.maxX <= 390 - Theme.Metrics.screenPadding + 0.5, "inside the card: \(time)")
            }
        }
    }

    /// The window drawn once (1x), read at many points (`HostedWindow.pixel` draws it for every point).
    @MainActor
    private struct Snapshot {
        let width: Int, height: Int
        private let bytes: [UInt8]

        init(_ w: HostedWindow) throws {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let bounds = w.window.bounds
            let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
                _ = w.window.drawHierarchy(in: bounds, afterScreenUpdates: true)
            }
            let cg = try #require(image.cgImage)
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let width = cg.width, height = cg.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            try #require(drew)
            self.width = width
            self.height = height
            bytes = buffer
        }

        /// Text or a glyph: brighter than the page, the cards, the hairlines and the 16 % outlines.
        func isInk(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            let i = (y * width + x) * 4
            return max(bytes[i], bytes[i + 1], bytes[i + 2]) > 90
        }

        /// Where ink is, left to right, in the rect; nil without any.
        func extent(x: Range<Int>, y: Range<Int>) -> ClosedRange<Int>? {
            var low: Int?, high: Int?
            for yy in y { for xx in x where isInk(xx, yy) { low = min(low ?? xx, xx); high = max(high ?? xx, xx) } }
            guard let low, let high else { return nil }
            return low...high
        }

        /// The lines of text in the rect: runs of rows with ink.
        func lines(x: Range<Int>, y: Range<Int>) -> [Range<Int>] {
            var out: [Range<Int>] = []
            var start: Int?
            for yy in y {
                let inked = x.contains { isInk($0, yy) }
                if inked, start == nil { start = yy }
                if !inked, let s = start { out.append(s..<yy); start = nil }
            }
            if let s = start { out.append(s..<y.upperBound) }
            return out
        }
    }

    @Test("Across midnight at large text the Duration row keeps its words whole and inside the card",
          arguments: ["390 AX3", "320 xxxLarge"])
    func durationAcrossMidnightAtLargeText(_ size: String) async throws {
        let ax3 = size == "390 AX3"
        let width: CGFloat = ax3 ? 390 : 320
        let night = ActivitiesShotFixtures.add { model in
            let evening = Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: DayFormat.shift(.now, days: -2)) ?? .now
            model.start = evening
            model.end = evening.addingTimeInterval(3_600)
        }
        .environment(\.locale, Locale(identifier: "en_US"))
        .overlay(alignment: .bottomLeading) { probes(["Duration"]) }
        try await run(night, width: width, typeSize: ax3 ? .accessibility3 : .xxxLarge,
                      category: ax3 ? .accessibilityExtraLarge : .extraExtraExtraLarge, waitFor: "addActivity.duration") { w in
            let row = try node(w, "addActivity.duration")
            #expect(row.label == "Duration, 1 hour, ends the next day", "the next day said, not only shown")
            let probe = try #require(w.nodes().first { $0.label == "probe Duration" })
            let shot = try Snapshot(w)
            let card = (left: Int(Theme.Metrics.screenPadding), right: Int(width - Theme.Metrics.screenPadding))
            let ys = Int(row.frame.minY.rounded(.up)) + 1 ..< Int(row.frame.maxY) - 2
            #expect(shot.extent(x: card.right + 1 ..< Int(width), y: ys) == nil, "nothing past the card's edge")
            let lines = shot.lines(x: card.left + 1 ..< card.right - 1, y: ys)
            let first = try #require(lines.first.flatMap { shot.extent(x: card.left + 1 ..< card.right - 1, y: $0) })
            let labelEnd = card.left + Int(GroupedListSpec.rowInset + probe.frame.width)
            #expect(first.upperBound >= labelEnd - 3, "\"Duration\" whole on its line: \(first), to \(labelEnd)")
            if ax3 || lines.count > 1 {
                // Stacked: the label alone on its line, the value and "(next day)" under it.
                #expect(lines.count >= 2, "\(lines)")
                #expect(first.upperBound <= labelEnd + 4, "nothing beside the label: \(first), the label to \(labelEnd)")
            }
        }
    }

    @Test("On a 320 pt screen the effort circles keep a gap from xLarge", arguments: ["xLarge", "xxxLarge"])
    func effortCirclesFitTheirColumnsAt320(_ size: String) async throws {
        let xl = size == "xLarge"
        try await run(ActivitiesShotFixtures.add { _ in }, width: 320, typeSize: xl ? .xLarge : .xxxLarge,
                      category: xl ? .extraLarge : .extraExtraExtraLarge, waitFor: "effortScale") { w in
            let scale = try node(w, "effortScale")
            // No value: two rows of circles and nothing under them.
            let diameter = (scale.frame.height - EffortScaleSpec.rowSpacing) / 2
            let column = scale.frame.width / CGFloat(EffortScaleSpec.columns)
            #expect(diameter <= column - EffortScaleSpec.minGap + 0.5, "circle \(diameter) in a column of \(column)")
            #expect(diameter >= Theme.Metrics.minHitTarget, "still a target: \(diameter)")
            #expect(scale.frame.maxX <= 320 - Theme.Metrics.screenPadding - CardSpec.padding + 0.5, "inside the card: \(scale.frame)")
        }
    }

    // MARK: words

    @Test func theDistanceUnitIsSaid() async throws {
        let running = ActivitiesShotFixtures.add { $0.sport = .running }.environment(\.locale, Locale(identifier: "en_US"))
        try await run(running, waitFor: "addActivity.distanceUnit") { w in
            let unit = try node(w, "addActivity.distanceUnit")
            #expect(unit.label == "miles")
        }
    }

    @Test func theFooterPromisesEffortStrainOnlyWhereTheDetailKeepsIt() async throws {
        try await run(ActivitiesShotFixtures.add { $0.sport = .mobility }, waitFor: "addActivity.footer") { w in
            let footer = try node(w, "addActivity.footer")
            #expect(footer.label == "Without heart rate there is no strain for this activity.")
        }
        try await run(ActivitiesShotFixtures.add { $0.sport = .padel }, waitFor: "addActivity.footer") { w in
            let footer = try node(w, "addActivity.footer")
            #expect(footer.label.hasSuffix("Without it, your effort rating is used."))
        }
    }

    // MARK: the detail

    @Test func theDetailReadsHeaderNumeralTilesStrainThenActions() async throws {
        let mobility = ActivitiesShotFixtures.detail { $0.sport == .mobility }
        try await run(mobility, height: 1_200, waitFor: "activityDetail.numeral") { w in
            let ids = w.nodes().compactMap(\.identifier)
            let order = ["activityDetail.back", "activityDetail.header", "activityDetail.menu", "activityDetail.numeral",
                         "activityDetail.stat.duration", "activityDetail.stat.effort", "activityDetail.strain",
                         "activityDetail.addNote", "activityDetail.edit", "activityDetail.delete"]
            let positions = order.map { id in ids.firstIndex(of: id) }
            #expect(!positions.contains(nil), "missing: \(zip(order, positions).filter { $0.1 == nil }.map(\.0)); found \(ids)")
            let found = positions.compactMap { $0 }
            #expect(found == found.sorted(), "reading order \(ids)")

            let numeral = try node(w, "activityDetail.numeral")
            #expect(numeral.label == "Duration" && numeral.value == "20 minutes")
            #expect(try node(w, "activityDetail.header").label == "Mobility")
            #expect(try node(w, "activityDetail.stat.effort").value == "3 of 10, Easy")
            #expect(try node(w, "activityDetail.delete").label == "Delete activity")
            #expect(try node(w, "activityDetail.strain").label.contains("No heart rate for this time."))
            #expect(w.node("Saved on this iPhone") == nil && w.node("Showing what's saved") == nil, "at RYFT, online: no sync line")
        }
    }

    @Test func aScoredRunSaysItsStrainInOneSentence() async throws {
        let run = ActivitiesShotFixtures.detail { $0.mergedWith != nil }
        try await self.run(run, height: 2_000, waitFor: "activityDetail.strain") { w in
            let strain = try node(w, "activityDetail.strain")
            #expect(strain.label == "Strain")
            let value = try #require(strain.value)
            #expect(value.contains(" of 21, ") && value.contains("Merged from two sources"), "\(value)")
            let ids = w.nodes().compactMap(\.identifier)
            let strainAt = try #require(ids.firstIndex(of: "activityDetail.strain"))
            let heartRate = try #require(ids.firstIndex(of: "activityDetail.mergedWorkout"))
            #expect(strainAt < heartRate)
            #expect(w.nodes().contains { $0.label == "Splits" })
        }
    }

    @Test func savedOfflineTheDetailShowsItsUploadLineAndNoScore() async throws {
        try await run(ActivitiesShotFixtures.offlineDetail(), waitFor: "activityDetail.numeral") { w in
            // `InlineMessage`'s identifier names its buttons only: the line is found by its sentence, read as one.
            try await w.wait("the upload line") { w.node("Saved on this iPhone. It will upload when you're online.") != nil }
            let nodes = w.nodes()
            let lineAt = try #require(nodes.firstIndex { $0.label.hasPrefix("Saved on this iPhone.") })
            let numeralAt = try #require(nodes.firstIndex { $0.identifier == "activityDetail.numeral" })
            #expect(lineAt < numeralAt, "the line comes before the numeral")
            let strain = try node(w, "activityDetail.strain")
            #expect(strain.label.contains("Strain arrives once RYFT has this activity."), "\(strain.label)")
            #expect(!strain.label.contains("heart rate"), "nothing about heart rate before RYFT has it: \(strain.label)")
            #expect(!(strain.value ?? "").contains("of 21"))
        }
    }

    @Test func aMergedActivitySaysWhatEachSideGaveWhileItWaitsToo() async throws {
        let state = ActivitiesShotFixtures.state()
        var all = MockActivitiesSource.demo()
        let i = try #require(all.firstIndex { $0.mergedWith != nil })
        // At RYFT, merged, not scored yet.
        all[i].strain = nil
        all[i].strainSource = nil
        for day in Set(all.map { DayFormat.string(from: $0.start) }) {
            state.repository.seed(.activities(all.filter { DayFormat.string(from: $0.start) == day }, day: day))
        }
        let run = all[i]
        let detail = NavigationStack { ActivityDetailView(route: ActivityRoute(id: run.id, day: run.start)) }.previewEnvironment(state)
        try await self.run(detail, height: 2_000, waitFor: "activityDetail.strain") { w in
            let strain = try node(w, "activityDetail.strain")
            #expect(strain.label.contains("Waiting for heart rate") && strain.label.contains("Merged from two sources"),
                    "\(strain.label)")
        }
    }
}
