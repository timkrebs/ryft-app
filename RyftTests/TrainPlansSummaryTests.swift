import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// T6B.3/T6B.4 (PR 6 B §14.2): the workout summary's states, the resume banner, the records, Plans' tile and rows, a plan's
/// spoken lines and the builder's rules, as values.
@MainActor
@Suite("T6B.3/T6B.4: summary, banner, Plans")
struct TrainPlansSummaryTests {
    private let english = Locale(identifier: "en_US")

    // MARK: banner

    @Test func theBannersNumbers() {
        #expect(WorkoutBannerSpec.minHeight == 68 && WorkoutBannerSpec.radius == 22)
        #expect(WorkoutBannerSpec.borderOpacity == 0.20 && WorkoutBannerSpec.dot == 8)
        #expect(WorkoutBannerSpec.pulseOpacity == 0.35 && WorkoutBannerSpec.pulseDuration == 1)
    }

    @Test func theBannerSaysWhatIsRunning() {
        #expect(WorkoutInProgressBanner.meta(title: "Upper A", minutes: 23, sets: 6) == "Upper A · 23\u{00A0}min · 6 sets done")
        #expect(WorkoutInProgressBanner.spoken(title: "Upper A", minutes: 23, sets: 6) == "Upper A, 23 minutes, 6 sets done")
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(WorkoutInProgressBanner.minutes(since: start, now: start.addingTimeInterval(23 * 60 + 59)) == 23)
        #expect(WorkoutInProgressBanner.minutes(since: start, now: start.addingTimeInterval(-120)) == 0, "a clock moved back")
    }

    // MARK: records

    @Test func aRecordNamesItsExerciseAndKind() {
        let pr = PersonalRecord(exerciseId: MockTrain.bench.id, kind: .e1rm, value: 93.5, sessionId: UUID(), achievedAt: .now)
        #expect(PRBadge.title(pr, exerciseName: "Bench press") == "Bench press")
        #expect(PRBadge.detail(pr, exerciseName: "Bench press", showsDate: false) == PRKind.e1rm.title)
        #expect(PRBadge.spokenLabel(pr, exerciseName: "Bench press") == "Bench press")
        #expect(PRBadge.spokenValue(pr, exerciseName: "Bench press", showsDate: false) == PRKind.e1rm.sentence(93.5))
        // On the exercise's own page: the kind over its date, the sentence first for VoiceOver.
        #expect(PRBadge.title(pr, exerciseName: nil) == PRKind.e1rm.title)
        #expect(PRBadge.detail(pr, exerciseName: nil, showsDate: false) == nil)
        #expect(PRBadge.detail(pr, exerciseName: nil, showsDate: true) != nil)
        #expect(PRBadge.spokenLabel(pr, exerciseName: nil) == PRKind.e1rm.sentence(93.5))
    }

    @Test func aRecordFromAnotherYearCarriesItsYear() throws {
        let cal = Calendar(identifier: .gregorian)
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 18)))
        let old = try #require(cal.date(from: DateComponents(year: 2025, month: 11, day: 13)))
        #expect(PRBadge.date(old, now: now, calendar: cal).contains("2025"))
        #expect(!PRBadge.date(now, now: now, calendar: cal).contains("2026"))
    }

    // MARK: summary

    @Test func aScoredSummaryLightsTheNumeral() {
        let s = MockTrain.completed
        let content = SessionSummaryContent(session: s, answered: true, pendingCompletion: false, locale: english)
        #expect(content.strainState == .scored)
        #expect(content.hero.strain == s.strain && content.hero.numeral != nil)
        #expect(content.hero.caption.hasPrefix(StrainHero.named("")), "\(content.hero.caption)")
        #expect(content.tiles.map(\.id) == ["duration", "volume", "load", "sets"], "strain is the hero, not a tile")
        #expect(content.tiles[2].value == Fmt.load(s.muscularTrimp, locale: english))
        let sets = s.exercises.flatMap(\.sets).filter { $0.completedAt != nil }.count
        #expect(content.tiles[3].value == "\(sets)")
        #expect(content.tiles[0].spoken?.contains("minute") == true, "\(content.tiles[0].spoken ?? "")")
        #expect(!content.showsWillSync)
        #expect(content.title == s.title)
        #expect(content.subtitle.hasPrefix("Workout done · "), "\(content.subtitle)")
    }

    @Test func theSubtitleNamesTheDay() throws {
        var s = MockTrain.completed
        let cal = Calendar(identifier: .gregorian)
        let end = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 19)))
        s.endedAt = end
        let content = SessionSummaryContent(session: s, answered: true, pendingCompletion: false, locale: english)
        #expect(content.subtitle == "Workout done · Wed, Nov 18")
        #expect(content.spokenSubtitle == "Workout done, Wednesday, November 18")
    }

    /// Offline: no platform answer, the numeral unlit (no needle), the will-sync note, the load "–", the rest from the phone.
    @Test func aPendingSummaryIsHonest() {
        var local = MockTrain.completed
        local.strain = nil
        local.muscularTrimp = nil
        let content = SessionSummaryContent(session: local, answered: false, pendingCompletion: true, locale: english)
        #expect(content.strainState == .pending)
        #expect(content.hero.strain == nil && content.hero.numeral == nil)
        #expect(content.hero.caption == "Strain · arrives once your workout is scored")
        #expect(content.showsWillSync)
        #expect(content.tiles[2].value == Fmt.placeholder)
        #expect(content.tiles[1].value != Fmt.placeholder, "the volume is the logged sets'")
    }

    /// `…/complete` always brings a strain (the muscular load on the strain scale), so an answer without one is a session
    /// the platform hasn't scored yet: pending, never a "no heart rate" state of its own.
    @Test func anUnscoredAnswerIsPending() {
        let unscored = SessionSummaryContent(session: MockTrain.completedUnscored, answered: true, pendingCompletion: false)
        #expect(unscored.strainState == .pending)
        #expect(unscored.hero.caption == "Strain · arrives once your workout is scored")
        #expect(!unscored.showsWillSync, "answered: nothing waits")
    }

    @Test func theVolumeTileSplitsItsUnitAndSaysItInWords() {
        let none = SessionSummaryContent.volumeParts(nil, locale: english)
        #expect(none.value == Fmt.placeholder && none.unit == nil && none.spoken == nil)
        let kg = SessionSummaryContent.volumeParts(7_500, locale: english)
        #expect(kg.unit == "kg" && kg.value == "7,500")
        #expect(kg.spoken == "7,500 kilograms", "\(kg.spoken ?? "")")
        let tonnes = SessionSummaryContent.volumeParts(12_400, locale: english)
        #expect(tonnes.unit == "t" && tonnes.value == "12.4")
        #expect(tonnes.spoken == "12.4 tonnes")
        let tile = SessionSummaryContent.tiles(MockTrain.completed, locale: english)[1]
        #expect(tile.id == "volume" && tile.spoken != nil, "the tile says its unit in words")
    }

    @Test func theSummarysNumbers() {
        #expect(SessionSummaryLayout.heroGap == 22)
        #expect(SessionSummaryLayout.tilesGap + StrainLayout.rulerFollowingGap == 26, "the tiles 26 under the ruler")
        #expect(SessionSummaryLayout.spacing == 12)
    }

    // MARK: Plans

    @Test func theActiveTileIsAGlowTile() {
        let tile = PlanTileContent(planID: MockTrain.upperLower.id, paused: false, name: "Upper/Lower 4×", week: 6,
                                   nextDay: "Upper A")
        #expect(tile.state == .active)
        #expect(tile.stateText == "Active" && tile.weekText == "Week 6" && tile.nextText == "Next: Upper A")
        #expect(tile.spoken == "Upper/Lower 4×, Active, Week 6, Next: Upper A")
    }

    /// `GET /v1/plans` reports no paused enrolment: the tile shows no week and no next day, whatever it is handed.
    @Test func aPausedTileInventsNothing() {
        let tile = PlanTileContent(planID: MockTrain.upperLower.id, paused: true, name: "Upper/Lower 4×", week: 6,
                                   nextDay: "Upper A")
        #expect(tile.state == .paused && tile.stateText == "Paused")
        #expect(tile.weekText == nil, "no week, and no paused date: the head's right stays empty")
        #expect(tile.nextText == "Resume continues where you stopped.")
        #expect(tile.spoken == "Upper/Lower 4×, Paused, Resume continues where you stopped.")
    }

    @Test func theNextDayComesFromTheEnrolment() {
        var e = MockTrain.enrollment
        #expect(PlanTileContent.nextDayName(plan: MockTrain.upperLower, enrollment: e) == "Upper A")
        e.currentDayIndex = 1
        #expect(PlanTileContent.nextDayName(plan: MockTrain.upperLower, enrollment: e) == "Lower A")
        #expect(PlanTileContent.nextDayName(plan: nil, enrollment: e) == nil)
        #expect(PlanTileContent.nextDayName(plan: MockTrain.upperLower, enrollment: nil) == nil)
        // A plan with weeks: the day of the enrolment's week.
        let week2 = Enrollment(id: UUID(), planId: MockTrain.weightlifting.id, startedAt: .now, currentWeek: 2,
                               currentDayIndex: 1, status: .active)
        let day = MockTrain.weightlifting.days.first { $0.week == 2 && $0.dayIndex == 1 }
        #expect(PlanTileContent.nextDayName(plan: MockTrain.weightlifting, enrollment: week2) == day?.name)
    }

    @Test func onlyTheActivePlansRowIsFilled() {
        let summary = PlanSummary(MockTrain.upperLower)
        let active = PlanRowContent(summary, status: .active)
        #expect(active.row.filledDisc && active.row.systemImage == "checkmark" && !active.row.showsValue)
        #expect(active.row.spoken.hasPrefix("Upper/Lower 4×, Active, Hypertrophy, 4 days a week"), "\(active.row.spoken)")
        let paused = PlanRowContent(summary, status: .paused)
        #expect(!paused.row.filledDisc && paused.row.spoken.contains("Paused"))
        let other = PlanRowContent(PlanSummary(MockTrain.fullBody), status: nil)
        #expect(!other.row.filledDisc && other.row.systemImage == "list.bullet.rectangle")
        #expect(other.row.spoken == "Full Body 3×, Strength, 3 days a week, 12 weeks")
        #expect(other.row.meta == MockTrain.fullBody.summaryText)
    }

    /// PR 6 combine: Train's meta lines join as My Day's and Strain's (`MyDayText.join`), so T5.8's rule holds there too: a part
    /// never breaks inside, the "·" ends its line, and from AX1 an activity row (a plan row) or the done card stands the parts
    /// one per line, without the "·".
    @Test("Plans' summary and Today's done line join as My Day's: one part per line from AX1")
    func metaLinesJoinAsMyDays() {
        let summary = MockTrain.fullBody.summaryText
        #expect(!summary.contains(" · ") && summary.contains(ActivityListRowSpec.metaSeparator), "\(summary.debugDescription)")
        #expect(ActivityListRow.metaLines(summary, stacked: true) == ["Strength", "3\u{00A0}days/week", "12\u{00A0}weeks"])
        #expect(ActivityListRow.metaLines(summary, stacked: false) == [summary])
        let session = LocalSession(title: "Upper A")
        session.strain = 11.2
        let done = TrainTodayViewModel.doneText(session)
        #expect(!done.contains(" · ") && done.hasPrefix("Done\u{00A0}· "), "\(done.debugDescription)")
        let lines = ActivityListRow.metaLines(done, stacked: true)
        #expect(lines.count == 2 && lines.first == "Done" && lines.last?.hasPrefix("load\u{00A0}") == true, "\(lines)")
    }

    @Test func theViewModelBuildsTheTileFromTheLibrary() {
        let active = PlansViewModel(library: TrainShotFixtures.library(MockTrain.catalog()))
        #expect(active.tile?.state == .active)
        #expect(active.tile?.nextText == "Next: Upper A" && active.tile?.weekText == "Week 6")
        #expect(active.builtinRows.first { $0.id == MockTrain.upperLower.id }?.row.filledDisc == true)
        #expect(active.hasCatalog && !active.isLoading && !active.isOffline)

        let none = PlansViewModel(library: TrainShotFixtures.library(MockTrain.catalog(enrolled: false, mine: false)))
        #expect(none.tile == nil && none.mineRows.isEmpty)
    }

    /// The real paused path: no enrolment in the catalog, the plan remembered on this iPhone. "Paused", the name, "Resume
    /// continues where you stopped." and nothing else.
    @Test func thePausedPlanAsThePlatformReportsIt() {
        let library = TrainShotFixtures.library(MockTrain.catalog(enrolled: false), paused: MockTrain.upperLower.id)
        let model = PlansViewModel(library: library)
        let tile = model.tile
        #expect(tile?.state == .paused && tile?.name == MockTrain.upperLower.name)
        #expect(tile?.weekText == nil && tile?.nextText == "Resume continues where you stopped.")
        let row = model.builtinRows.first { $0.id == MockTrain.upperLower.id }
        #expect(row?.row.filledDisc == false && row?.row.spoken.contains("Paused") == true)
    }

    /// Each test's library remembers its own paused plan (F1 round 2): one test's paused plan isn't another's, whichever
    /// runs alongside it, so none of them saves and restores `UserDefaults.standard`.
    @Test func aPausedPlanIsTheLibrarysOwn() {
        let paused = TrainShotFixtures.library(MockTrain.catalog(enrolled: false), paused: MockTrain.upperLower.id)
        let other = TrainShotFixtures.library(MockTrain.catalog(enrolled: false))
        #expect(paused.pausedPlanID == MockTrain.upperLower.id)
        #expect(other.pausedPlanID == nil && PlansViewModel(library: other).tile == nil, "no Resume of another test's plan")
        let built = TrainLibrary.testing(store: TrainStore(inMemory: true), remote: { MockTrainSource.shared }, restore: false)
        #expect(built.pausedPlanID == nil)
    }

    /// Nothing cached: outlines only while a load runs (or before the first); offline (the reads send nothing) a line, not
    /// outlines that never fill, and no "Plans you make or copy appear here." before the plans are known.
    @Test func plansWithoutACatalogNeverLoadForever() async {
        let env = AppEnvironment.test(online: false)
        let library = TrainLibrary.testing(store: TrainStore(inMemory: true), remote: { MockTrainSource.shared }, restore: true)
        library.reads = env.reads
        let model = PlansViewModel(library: library)
        #expect(model.isLoading && !model.isOffline, "before the first load: the outlines")
        await model.loadIfNeeded()
        #expect(!model.hasCatalog && model.error == nil, "offline: nothing sent, nothing failed")
        #expect(!model.isLoading && model.isOffline)
        withExtendedLifetime(env) {}
    }

    @Test func aPlanThatCannotLoadSaysSo() async {
        let library = TrainLibrary.testing(store: TrainStore(inMemory: true), remote: { OfflineTrainSource() }, restore: true)
        let model = PlanDetailViewModel(planID: MockTrain.fullBody.id, library: library)
        #expect(model.failure == nil, "loading: the outlines")
        await model.load()
        let offline = URLError(.notConnectedToInternet)
        #expect(model.plan == nil && model.failure == offline.localizedDescription, "\(model.failure ?? "nil")")
        #expect(model.failureDetails == offline.diagnosticDetails)
        // The page's own failure (F1 item 1): not the Plans page's message.
        #expect(library.error == nil && library.errorDetails == nil)
    }

    @Test func anExercisesNotesAreRead() throws {
        var plank = try #require(MockTrain.fullBody.days.first?.exercises.first)
        plank.notes = "45 s holds"
        #expect(PlanSpeech.exercise(plank, locale: english).hasSuffix(", 45 s holds"))
        plank.notes = "  "
        #expect(!PlanSpeech.exercise(plank, locale: english).hasSuffix(", "), "blank notes add nothing")
    }

    @Test func aPlansSpokenLines() throws {
        let squat = try #require(MockTrain.fullBody.days.first?.exercises.first)
        let spoken = PlanSpeech.exercise(squat, locale: english)
        #expect(spoken.hasPrefix("\(squat.exercise.name), \(squat.sets) sets of "), "\(spoken)")
        #expect(spoken.contains("rest "), "\(spoken)")
        #expect(PlanSpeech.restDuration(180, locale: english) == "3 minutes")
        #expect(PlanSpeech.restDuration(90, locale: english).contains("30 seconds"))
        #expect(PlanSpeech.day("Day A", minutes: 55) == "Day A, about 55 minutes")
        #expect(PlanSpeech.summary(goal: .strength, daysPerWeek: 3, weeks: 12) == "Strength, 3 days a week, 12 weeks")
        var kg = squat
        kg.targetKind = .kg
        kg.targetValue = 100
        #expect(PlanSpeech.target(kg, locale: english) == "at 100 kilograms")
        kg.repsMin = 10
        kg.repsMax = 12
        #expect(PlanSpeech.exercise(kg, locale: english).contains("sets of 10 to 12 at 100 kilograms"))
    }

    // MARK: builder

    @Test func theBuildersRules() {
        let missing: [PlanIssue] = [.missingName]
        #expect(PlanBuilderRules.shownIssues(missing, attempted: false, hasChanges: false).isEmpty, "a fresh form")
        #expect(PlanBuilderRules.shownIssues(missing, attempted: false, hasChanges: true) == missing)
        #expect(PlanBuilderRules.shownIssues(missing, attempted: true, hasChanges: false) == missing)
        #expect(!PlanBuilderRules.canSave(issues: missing))
        #expect(PlanBuilderRules.canSave(issues: []))
    }

    /// Everything the old stepper reached stays choosable: the presets, none to 45 s, 6 to 15 minutes, and the exercise's own.
    @Test func theRestChoicesLoseNothing() {
        let choices = PlanBuilderRules.restChoices(current: 180)
        #expect(choices == choices.sorted() && Set(choices).count == choices.count)
        #expect(Set(RestChoices.presets).isSubset(of: choices))
        #expect([0, 30, 45, 360, 480, 600, 900].allSatisfy(choices.contains))
        #expect(choices.last == PlanValidation.maxRestSec)
        #expect(PlanBuilderRules.restChoices(current: 75).contains(75))
    }

    /// Issues without a field (no day, a superset of one, sets or rest out of range) are lines of their own, one per sentence.
    @Test func issuesWithoutAFieldStillShow() {
        let a = UUID(), b = UUID()
        let shown: [PlanIssue] = [.missingName, .noDays, .sets(exerciseID: a), .sets(exerciseID: b), .rest(exerciseID: a),
                                  .lonelySuperset(dayID: a, group: 1), .reps(exerciseID: a), .emptyDay(dayID: a)]
        #expect(PlanBuilderRules.formIssues(shown) == [.noDays, .sets(exerciseID: a), .rest(exerciseID: a),
                                                       .lonelySuperset(dayID: a, group: 1)])
    }

    /// Unlinking the first of three leaves the third alone in its group: that is no superset, so nothing is left lonely.
    @Test func unlinkingASupersetOfThreeLeavesNoneLonely() throws {
        let library = TrainShotFixtures.library(MockTrain.catalog())
        let model = PlanBuilderViewModel(plan: .blank(), library: library)
        let day = try #require(model.plan.days.first?.id)
        for e in MockTrain.exercises.prefix(3) { model.add(e, toDay: day) }
        model.link(dayID: day, 0, true)
        model.link(dayID: day, 1, true)
        #expect(model.isLinked(dayID: day, 0) && model.isLinked(dayID: day, 1))
        model.link(dayID: day, 0, false)
        #expect(!model.issues.contains { if case .lonelySuperset = $0 { true } else { false } }, "\(model.issues)")
        #expect(model.plan.days[0].exercises.allSatisfy { $0.supersetGroup == nil })
        // Unlinking the last pair of three keeps the first two together.
        model.link(dayID: day, 0, true)
        model.link(dayID: day, 1, true)
        model.link(dayID: day, 1, false)
        #expect(model.isLinked(dayID: day, 0) && !model.isLinked(dayID: day, 1))
        #expect(!model.issues.contains { if case .lonelySuperset = $0 { true } else { false } })
    }
}

/// The summary, the banner, Plans and the builder drawn in a window (PR 6 B §14.2): what VoiceOver hears and the identifiers
/// the UI tests use.
@MainActor
@Suite("T6B.3/T6B.4: hosted", .serialized)
struct TrainPlansSummaryHostedTests {
    private static let width: CGFloat = 390

    private func ids(_ w: HostedWindow) -> Set<String> { Set(w.nodes().compactMap(\.identifier)) }

    @Test func theBannerIsOneButton() async throws {
        try await HostedWindow.run(width: Self.width, height: 400, TrainShotFixtures.banner()) { w in
            try await w.settle()
            let banner = try #require(w.nodes().first { $0.identifier == "train.resume" })
            #expect(banner.label == "Workout in progress")
            #expect(banner.value == "Upper A, 23 minutes, 6 sets done" || banner.value == "Upper A, 24 minutes, 6 sets done",
                    "\(banner.value ?? "")")
            #expect(banner.hint == "Opens the workout")
            #expect(banner.traits.contains(.button))
            #expect(banner.frame.height >= WorkoutBannerSpec.minHeight - 0.5, "\(banner.frame)")
            #expect(w.node("Resume", exactly: true) == nil, "the pill is the banner's look, not a second button")
        }
    }

    @Test func theBannerStacksFromAX1() async throws {
        try await HostedWindow.run(width: Self.width, height: 600, typeSize: .accessibility3,
                                   category: .accessibilityExtraLarge, TrainShotFixtures.banner()) { w in
            try await w.settle()
            let banner = try #require(w.nodes().first { $0.identifier == "train.resume" })
            #expect(banner.frame.height > WorkoutBannerSpec.minHeight, "the pill under the text: \(banner.frame)")
            #expect(banner.frame.width <= Self.width - 40 + 0.5)
        }
    }

    @Test func aScoredSummary() async throws {
        let view = TrainShotFixtures.summary(completed: MockTrain.completed)
        try await HostedWindow.run(width: Self.width, height: 1_400, bottomInset: 0, view) { w in
            try await w.settle()
            let nodes = w.nodes()
            let found = Set(nodes.compactMap(\.identifier))
            for id in ["summary.header", "summary.numeral", "summary.ruler", "summary.stat.duration", "summary.stat.volume",
                       "summary.stat.load", "summary.stat.sets", "summary.done"] {
                #expect(found.contains(id), "\(id) in \(found.sorted())")
            }
            let header = try #require(nodes.first { $0.identifier == "summary.header" })
            #expect(header.label == MockTrain.completed.title && header.traits.contains(.header))
            #expect(header.value?.hasPrefix("Workout done, ") == true, "\(header.value ?? "")")
            let numeral = try #require(nodes.first { $0.identifier == "summary.numeral" })
            #expect(numeral.label.hasPrefix("Strain ") && numeral.label.hasSuffix(" of 21"), "\(numeral.label)")
            #expect(!nodes.contains { $0.identifier == "summary.stat.strain" }, "strain is the hero")
            #expect(nodes.contains { $0.label == "Personal records" && $0.traits.contains(.header) }, "the records card")
            #expect(nodes.contains { $0.label == "Bench press" && $0.value == PRKind.e1rm.sentence(93.5) })
            #expect(!nodes.contains { $0.label.contains("new PRs") }, "no celebration title")
            // VoiceOver order: the header, the numeral, the ruler, the tiles, the records, Done.
            let order = nodes.compactMap(\.identifier)
            let sequence = ["summary.header", "summary.numeral", "summary.ruler", "summary.stat.duration", "summary.done"]
            let positions = sequence.compactMap { order.firstIndex(of: $0) }
            #expect(positions == positions.sorted() && positions.count == sequence.count, "\(order)")
            let done = try #require(nodes.first { $0.identifier == "summary.done" })
            #expect(done.label == "Done")
        }
    }

    @Test func aPendingSummaryHasNoNeedle() async throws {
        try await HostedWindow.run(width: Self.width, height: 1_400, bottomInset: 0, TrainShotFixtures.pendingSummary()) { w in
            try await w.settle()
            let nodes = w.nodes()
            let numeral = try #require(nodes.first { $0.identifier == "summary.numeral" })
            #expect(numeral.label == "Strain · arrives once your workout is scored", "\(numeral.label)")
            let ruler = try #require(nodes.first { $0.identifier == "summary.ruler" })
            #expect(ruler.value == String(localized: "No data"), "no needle: \(ruler.value ?? "")")
            #expect(w.node("Saved on this phone. Will sync") != nil, "the will-sync note")
            let load = try #require(nodes.first { $0.identifier == "summary.stat.load" })
            #expect(load.value?.contains(Fmt.placeholder) == true || load.label.contains(Fmt.placeholder), "\(load)")
            #expect(w.node("Personal records", exactly: true) == nil, "no records card")
        }
    }

    @Test func aSummaryWithoutRecordsHasNoCard() async throws {
        let view = TrainShotFixtures.summary(completed: MockTrain.completedWithoutRecords)
        try await HostedWindow.run(width: Self.width, height: 1_400, bottomInset: 0, view) { w in
            try await w.settle()
            #expect(w.node("Personal records", exactly: true) == nil)
            #expect(ids(w).contains("summary.done"))
        }
    }

    @Test func aPausedPlanIsAnOutlineWithResume() async throws {
        try await HostedWindow.run(width: Self.width, height: 900, bottomInset: 0,
                                   TrainShotFixtures.plans(MockTrain.catalog(enrolled: false), paused: MockTrain.upperLower.id)) { w in
            try await w.settle()
            let found = ids(w)
            #expect(found.contains("plans.resume") && !found.contains("plans.pause"), "\(found.sorted())")
            let tile = try #require(w.nodes().first { $0.identifier == "plans.current" })
            #expect(tile.label == "Upper/Lower 4×, Paused, Resume continues where you stopped.", "\(tile.label)")
            #expect(tile.hint == "Opens the plan")
            let resume = try #require(w.nodes().first { $0.identifier == "plans.resume" })
            #expect(resume.label == "Resume")
            // No glow: the tile's padding is the page's background, not strain blue.
            let pixel = try #require(w.pixel(at: CGPoint(x: tile.frame.minX - 8, y: tile.frame.midY)))
            #expect(abs(pixel.b - pixel.r) < 0.05 && pixel.b < 0.2, "\(pixel)")
        }
    }

    @Test func theActivePlanGlows() async throws {
        try await HostedWindow.run(width: Self.width, height: 900, bottomInset: 0,
                                   TrainShotFixtures.plans(MockTrain.catalog())) { w in
            try await w.settle()
            let found = ids(w)
            #expect(found.contains("plans.pause") && !found.contains("plans.resume"), "\(found.sorted())")
            #expect(found.contains("plans.header") && found.contains("plans.back") && found.contains("plans.newPlan"))
            let tile = try #require(w.nodes().first { $0.identifier == "plans.current" })
            #expect(tile.label == "Upper/Lower 4×, Active, Week 6, Next: Upper A")
            let pixel = try #require(w.pixel(at: CGPoint(x: tile.frame.minX - 8, y: tile.frame.midY)))
            #expect(pixel.b - pixel.r > 0.08, "strain blue at the tile's edge: \(pixel)")
            #expect(w.node("Full Body 3×, Strength, 3 days a week, 12 weeks", exactly: true) != nil)
        }
    }

    @Test func withoutPlansOfYourOwnTheSentenceShows() async throws {
        try await HostedWindow.run(width: Self.width, height: 900, bottomInset: 0,
                                   TrainShotFixtures.plans(MockTrain.catalog(enrolled: false, mine: false))) { w in
            try await w.settle()
            #expect(w.node("Plans you make or copy appear here.", exactly: true) != nil)
            #expect(w.node("My plans", exactly: true) == nil, "no empty section")
            #expect(!ids(w).contains("plans.current"))
        }
    }

    /// Offline with nothing cached: the calm line with Try again, no outlines, and no sentence about plans of your own.
    @Test func offlineWithoutPlansSaysSo() async throws {
        try await HostedWindow.run(width: Self.width, height: 900, bottomInset: 0, TrainShotFixtures.offlinePlans()) { w in
            try await w.wait("the offline line") { w.node("Plans appear once you're online.", exactly: true) != nil }
            let found = ids(w)
            #expect(!found.contains("plans.loading"), "no outlines that never fill: \(found.sorted())")
            #expect(found.contains("plans.offline.retry") && found.contains("plans.newPlan"), "\(found.sorted())")
            #expect(w.node("Plans you make or copy appear here.", exactly: true) == nil, "the plans aren't known yet")
        }
    }

    /// A plan neither cached nor loadable: the failure with Try again instead of outlines.
    @Test func aPlanThatCannotLoadShowsTheFailure() async throws {
        try await HostedWindow.run(width: Self.width, height: 900, bottomInset: 0,
                                   TrainShotFixtures.unloadablePlan(MockTrain.fullBody.id)) { w in
            try await w.wait("the failure") { w.nodes().contains { $0.identifier == "plan.loadError.retry" } }
            #expect(!ids(w).contains("plan.loading"), "\(ids(w).sorted())")
        }
    }

    @Test func aPlansDayIsOneContainer() async throws {
        try await HostedWindow.run(width: Self.width, height: 1_600, bottomInset: 0,
                                   TrainShotFixtures.planDetail(MockTrain.fullBody.id)) { w in
            try await w.wait("the plan") { w.nodes().contains { $0.identifier == "plan.enroll" } }
            try await w.settle()
            let header = try #require(w.nodes().first { $0.identifier == "plan.header" })
            #expect(header.label == MockTrain.fullBody.name)
            #expect(header.value == "Strength, 3 days a week, 12 weeks", "\(header.value ?? "")")
            let squat = try #require(MockTrain.fullBody.days.first?.exercises.first)
            #expect(w.node(PlanSpeech.exercise(squat), exactly: true) != nil, "one element per exercise")
            #expect(ids(w).contains("plan.copy") && !ids(w).contains("plan.delete"), "built-in: Copy and edit, no Delete")
            let starts = ids(w).filter { $0.hasPrefix("plan.startDay.") }
            #expect(starts == Set(MockTrain.fullBody.days.map { "plan.startDay.\($0.dayIndex)" }), "one per day: \(starts)")
        }
    }

    @Test func saveWaitsForAValidPlan() async throws {
        try await HostedWindow.run(width: Self.width, height: 900, bottomInset: 0, PlanBuilderView(plan: .blank())) { w in
            try await w.settle()
            let save = try #require(w.nodes().first { $0.identifier == "planBuilder.save" })
            #expect(save.label == "Save" && !save.isEnabled)
            #expect(save.hint == PlanIssue.missingName.message)
            #expect(w.node("New plan", exactly: true) != nil)
            #expect(w.node(PlanIssue.missingName.message, exactly: true) == nil, "nothing is wrong on a fresh form")
        }
        try await HostedWindow.run(width: Self.width, height: 900, bottomInset: 0,
                                   PlanBuilderView(plan: MockTrain.upperLower.copy())) { w in
            try await w.settle()
            let save = try #require(w.nodes().first { $0.identifier == "planBuilder.save" })
            #expect(save.isEnabled)
            #expect(w.node("Edit plan", exactly: true) != nil)
        }
    }

    /// Without a day there is no field to sit under: the sentence is a line above Add day, so the off Save says why.
    @Test func removingTheLastDaySaysWhy() async throws {
        try await HostedWindow.run(width: Self.width, height: 900, bottomInset: 0, PlanBuilderView(plan: .blank())) { w in
            try await w.settle()
            let remove = try #require(w.node("Remove Day A", exactly: true))
            #expect(remove.activate())
            try await w.wait("the no-days line") { w.node(PlanIssue.noDays.message, exactly: true) != nil }
            let save = try #require(w.nodes().first { $0.identifier == "planBuilder.save" })
            #expect(!save.isEnabled)
        }
    }

    @Test func cancelAsksOnceSomethingChanged() async throws {
        try await HostedWindow.run(width: Self.width, height: 900, bottomInset: 0,
                                   PlanBuilderView(plan: MockTrain.upperLower.copy())) { w in
            try await w.settle()
            let days = try #require(w.node("Days per week", exactly: true))
            #expect(days.isAdjustable)
            days.increment()
            try await w.wait("the change") { w.node("Days per week", exactly: true)?.value?.hasPrefix("5") == true }
            let cancel = try #require(w.nodes().first { $0.identifier == "sheet.close" })
            #expect(cancel.label == "Cancel")
            #expect(cancel.activate())
            try await w.wait("the discard dialog") { w.menuItem("Discard changes") != nil }
        }
    }
}
