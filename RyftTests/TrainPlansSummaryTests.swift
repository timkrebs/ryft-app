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
        #expect(WorkoutInProgressBanner.meta(title: "Upper A", minutes: 23, sets: 6) == "Upper A · 23 min · 6 sets done")
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
        let content = SessionSummaryContent(session: s, answered: true, pendingCompletion: false, hasHeartRate: true,
                                            locale: english)
        #expect(content.strainState == .scored)
        #expect(content.hero.strain == s.strain && content.hero.numeral != nil)
        #expect(content.hero.caption.hasPrefix(StrainHero.named("")), "\(content.hero.caption)")
        #expect(content.tiles.map(\.id) == ["duration", "volume", "load", "sets"], "strain is the hero, not a tile")
        #expect(content.tiles[2].value == Fmt.load(s.muscularTrimp))
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
        let content = SessionSummaryContent(session: s, answered: true, pendingCompletion: false, hasHeartRate: nil,
                                            locale: english)
        #expect(content.subtitle == "Workout done · Wed, Nov 18")
        #expect(content.spokenSubtitle == "Workout done, Wednesday, November 18")
    }

    /// Offline: no platform answer, the numeral unlit (no needle), the will-sync note, the load "–", the rest from the phone.
    @Test func aPendingSummaryIsHonest() {
        var local = MockTrain.completed
        local.strain = nil
        local.muscularTrimp = nil
        let content = SessionSummaryContent(session: local, answered: false, pendingCompletion: true, hasHeartRate: nil,
                                            locale: english)
        #expect(content.strainState == .pending)
        #expect(content.hero.strain == nil && content.hero.numeral == nil)
        #expect(content.hero.caption == "Strain · arrives once your workout is scored")
        #expect(content.showsWillSync)
        #expect(content.tiles[2].value == Fmt.placeholder)
        #expect(content.tiles[1].value != Fmt.placeholder, "the volume is the logged sets'")
    }

    @Test func scoredWithoutHeartRateSaysWhy() {
        let unscored = MockTrain.completedUnscored
        let none = SessionSummaryContent(session: unscored, answered: true, pendingCompletion: false, hasHeartRate: false)
        #expect(none.strainState == .noHeartRate)
        #expect(none.hero.caption == "Strain · no heart rate for this workout")
        // While the heart rate is still being looked up, or with it: not scored yet.
        #expect(SessionSummaryContent(session: unscored, answered: true, pendingCompletion: false, hasHeartRate: nil)
            .strainState == .pending)
        #expect(SessionSummaryContent(session: unscored, answered: true, pendingCompletion: false, hasHeartRate: true)
            .strainState == .pending)
        #expect(!none.showsWillSync, "answered: nothing waits")
    }

    @Test func theVolumeTileSplitsItsUnit() {
        let none = SessionSummaryContent.volumeParts(nil)
        #expect(none.value == Fmt.placeholder && none.unit == nil)
        let kg = SessionSummaryContent.volumeParts(7_500)
        #expect(kg.unit == "kg" && kg.value.filter(\.isNumber) == "7500")
        let tonnes = SessionSummaryContent.volumeParts(12_400)
        #expect(tonnes.unit == "t" && tonnes.value.filter(\.isNumber) == "124")
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

    @Test func thePausedTileSaysWhatWaits() {
        let tile = PlanTileContent(planID: MockTrain.upperLower.id, paused: true, name: "Upper/Lower 4×", week: 6,
                                   nextDay: "Upper A")
        #expect(tile.state == .paused && tile.stateText == "Paused")
        #expect(tile.weekText == nil, "no paused date in the API: the head's right stays empty")
        #expect(tile.nextText == "Next: Upper A · week 6 waits")
        #expect(tile.spoken == "Upper/Lower 4×, Paused, Next: Upper A, week 6 waits")
        // A pause the app only remembers: no enrolment, so no week and no day.
        let remembered = PlanTileContent(planID: MockTrain.upperLower.id, paused: true, name: "Upper/Lower 4×", week: nil,
                                         nextDay: nil)
        #expect(remembered.nextText == "Resume continues where you stopped.")
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

    @Test func theViewModelBuildsTheTileFromTheLibrary() {
        UserDefaults.standard.removeObject(forKey: "train.pausedPlanID")
        let active = PlansViewModel(library: TrainShotFixtures.library(MockTrain.catalog()))
        #expect(active.tile?.state == .active)
        #expect(active.tile?.nextText == "Next: Upper A" && active.tile?.weekText == "Week 6")
        #expect(active.builtinRows.first { $0.id == MockTrain.upperLower.id }?.row.filledDisc == true)
        #expect(!active.isLoading)

        let paused = PlansViewModel(library: TrainShotFixtures.library(MockTrain.catalog(paused: true)))
        #expect(paused.tile?.state == .paused)
        #expect(paused.tile?.nextText == "Next: Upper A · week 6 waits")

        let none = PlansViewModel(library: TrainShotFixtures.library(MockTrain.catalog(enrolled: false, mine: false)))
        #expect(none.tile == nil && none.mineRows.isEmpty)
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
        #expect(!PlanBuilderRules.canSave(issues: missing, saving: false))
        #expect(PlanBuilderRules.canSave(issues: [], saving: false))
        #expect(!PlanBuilderRules.canSave(issues: [], saving: true))
        #expect(PlanBuilderRules.restChoices(current: 180) == RestChoices.presets)
        #expect(PlanBuilderRules.restChoices(current: 75).first == 60 && PlanBuilderRules.restChoices(current: 75).contains(75))
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
        UserDefaults.standard.removeObject(forKey: "train.pausedPlanID")
        try await HostedWindow.run(width: Self.width, height: 900, bottomInset: 0,
                                   TrainShotFixtures.plans(MockTrain.catalog(paused: true))) { w in
            try await w.settle()
            let found = ids(w)
            #expect(found.contains("plans.resume") && !found.contains("plans.pause"), "\(found.sorted())")
            let tile = try #require(w.nodes().first { $0.identifier == "plans.current" })
            #expect(tile.label.hasPrefix("Upper/Lower 4×, Paused"), "\(tile.label)")
            #expect(tile.hint == "Opens the plan")
            let resume = try #require(w.nodes().first { $0.identifier == "plans.resume" })
            #expect(resume.label == "Resume")
            // No glow: the tile's padding is the page's background, not strain blue.
            let pixel = try #require(w.pixel(at: CGPoint(x: tile.frame.minX - 8, y: tile.frame.midY)))
            #expect(abs(pixel.b - pixel.r) < 0.05 && pixel.b < 0.2, "\(pixel)")
        }
    }

    @Test func theActivePlanGlows() async throws {
        UserDefaults.standard.removeObject(forKey: "train.pausedPlanID")
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
        UserDefaults.standard.removeObject(forKey: "train.pausedPlanID")
        try await HostedWindow.run(width: Self.width, height: 900, bottomInset: 0,
                                   TrainShotFixtures.plans(MockTrain.catalog(enrolled: false, mine: false))) { w in
            try await w.settle()
            #expect(w.node("Plans you make or copy appear here.", exactly: true) != nil)
            #expect(w.node("My plans", exactly: true) == nil, "no empty section")
            #expect(!ids(w).contains("plans.current"))
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
