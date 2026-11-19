import SwiftUI
import Testing
import UIKit
@testable import Ryft

// Activities in Nocturne (docs/work/2026-11-16-nocturne/design-pr6-b-train.md §10, §14.2's Activities rows): the effort scale
// (the selection in ink, its spoken value, three columns from AX1), Save off until the form is valid, the Strength
// suggestion, the detail's sync line (offline included) and its reading order. Layout checks run in a window.

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
        #expect(EffortScaleSpec.fill(selected: true) != Theme.accent)
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

    @Test func saveStaysOffUntilTheFormIsValid() {
        let state = ActivitiesShotFixtures.state()
        let model = AddActivityModel(env: state.env, day: .now)
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
}

// MARK: - the detail's sync line (offline-first)

@MainActor
@Suite("Activities in Nocturne: the detail's sync line")
struct ActivityDetailSyncLineTests {
    @MainActor
    private struct Graph {
        let clock: TestClock
        let env: AppEnvironment
        let state: AppState

        init(online: Bool) {
            let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
            clock = TestClock(now: noon)
            let api = MockPlatformAPI(activities: MockActivitiesSource(now: { [clock] in clock.now() }))
            env = .test(api: api, clock: clock, flags: [.todayMyDay: true, .activitiesManual: true], online: online)
            state = AppState(env: env)
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
        let model = AddActivityModel(env: g.env, day: g.clock.now())
        model.sport = .hiit
        model.effort = 8
        #expect(model.save())
        let id = try #require(g.env.activities.snapshots(onDay: DayFormat.string(from: g.clock.now())).first?.id)
        await g.env.uploader.flush(userInitiated: true)

        let detail = g.detail(id, on: g.clock.now())
        // The upload's line wins over the offline one: one line at a time.
        #expect(detail.syncLine == .upload(.offline))
        #expect(detail.strainLine == .waiting, "no score until RYFT has it")
        #expect(!detail.stats(locale: Locale(identifier: "en_US")).contains { $0.title == "Strain" })
    }

    @Test func gatedSaysItUploadsOnceTheAccountIsReady() async throws {
        let g = Graph(online: true)
        g.env.uploader.gate = { _ in .gate(.consentRequired) }
        let model = AddActivityModel(env: g.env, day: g.clock.now())
        #expect(model.save())
        let id = try #require(g.env.activities.snapshots(onDay: DayFormat.string(from: g.clock.now())).first?.id)
        await g.env.uploader.flush(userInitiated: true)
        #expect(g.detail(id, on: g.clock.now()).syncLine == .upload(.gated))
    }
}

// MARK: - in a window

@MainActor
@Suite("Activities in Nocturne: in a window", .serialized)
struct ActivitiesNocturneHostedTests {
    nonisolated private static let width: CGFloat = 390

    private func run(_ content: some View, height: CGFloat = 1_600, typeSize: DynamicTypeSize = .large,
                     category: UIContentSizeCategory = .large, waitFor identifier: String,
                     body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: Self.width, height: height, bottomInset: 0, typeSize: typeSize, category: category,
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
            #expect(strain.label.contains("Waiting for heart rate"), "\(strain.label)")
            #expect(!(strain.value ?? "").contains("of 21"))
        }
    }
}
