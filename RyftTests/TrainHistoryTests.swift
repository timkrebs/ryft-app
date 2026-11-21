import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// T6B.5 (PR 6 B §7, §14.2): History, the session detail and the exercise page, as values and in a real window.
@MainActor
@Suite("T6B.5: History, session detail, exercise page", .serialized)
struct TrainHistoryTests {
    private let english = Locale(identifier: "en_US")
    private static let width: CGFloat = 390

    /// The text with its no-break spaces (and the narrow one before "PM") as plain ones.
    private func plain(_ s: String?) -> String? {
        s?.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// `day` (YYYY-MM-DD) at noon here.
    private func noon(_ day: String) -> Date {
        (DayFormat.date(from: day) ?? .now).addingTimeInterval(12 * 3600)
    }

    private func point(_ day: String, _ kg: Double) -> E1RMPoint { E1RMPoint(day: day, value: kg) }

    /// A finished Upper A `days` before `now`, as History's list carries it.
    private func summary(daysAgo days: Int, now: Date = .now) -> SessionSummary {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        return SessionSummary(TrainSession(title: "Upper A", startedAt: start, endedAt: start.addingTimeInterval(55 * 60),
                                           status: .completed, muscularTrimp: 85, strain: 10.4, volumeKg: 7_500, exercises: []))
    }

    /// Friday, November 13 2026, 17:30 here.
    private var friday: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 17, minute: 30)) ?? .now
    }

    private func set(_ index: Int, reps: Int? = nil, kg: Double? = nil, rpe: Double? = nil, seconds: Int? = nil,
                     meters: Double? = nil, warmup: Bool = false) -> SessionSet {
        SessionSet(setIndex: index, reps: reps, weightKg: kg, rpe: rpe, durationSec: seconds, distanceM: meters,
                   isWarmup: warmup, completedAt: friday)
    }

    private func session(load: Double? = 85, strain: Double? = 10.4, volume: Double? = 7_500) -> TrainSession {
        TrainSession(title: "Upper A", startedAt: friday, endedAt: friday.addingTimeInterval(55 * 60), status: .completed,
                     muscularTrimp: load, strain: strain, volumeKg: volume,
                     exercises: [SessionExercise(exerciseId: MockTrain.bench.id, position: 0,
                                                 sets: [set(0, reps: 5, kg: 60, warmup: true), set(1, reps: 5, kg: 80, rpe: 8.5),
                                                        set(2, reps: 5, kg: 80)])])
    }

    // MARK: History

    @Test func aRowIsTheActivityRowWithItsLoad() {
        let row = TrainHistoryRows.row(SessionSummary(session()), locale: english)
        #expect(row.systemImage == "dumbbell.fill" && row.title == "Upper A")
        #expect(plain(row.meta) == "Fri, Nov 13 · 55m · 7,500 kg")
        #expect(row.value == "85.0" && row.valueCaption == "load", "the load with \"load\" under it, no chip")
        #expect(row.spoken == "Upper A, Friday, November 13, 55 minutes, 7,500 kilograms, Muscular load 85")
    }

    @Test func aRowWithoutLoadShowsTheDash() {
        var s = session(load: nil)
        s.title = ""
        let row = TrainHistoryRows.row(SessionSummary(s), locale: english)
        #expect(row.title == String(localized: "Workout"))
        #expect(row.value == nil && row.valueCaption == "load", "the row draws \"–\" for a missing value")
        #expect(row.spoken.hasSuffix("No muscular load"))
    }

    @Test func aWeekSumsItsSessions() {
        let a = SessionSummary(session(load: 85.4, volume: 7_500)), b = SessionSummary(session(load: 40.2, volume: 4_700))
        let week = TrainHistoryViewModel.Week(start: friday, sessions: [a, b])
        #expect(plain(week.summary(locale: english)) == "2 sessions · 12.2 t · load 126")
        #expect(week.spokenSummary(locale: english) == "2 sessions, 12,200 kilograms, Muscular load 126")
        #expect(week.title(locale: english) == "Week of Nov 13")
        let unscored = TrainHistoryViewModel.Week(start: friday, sessions: [SessionSummary(session(load: nil))])
        #expect(plain(unscored.summary(locale: english))?.hasSuffix("load –") == true)
    }

    @Test func historyLoadsWithOutlinesThenSaysWhereSessionsComeFrom() async {
        let library = TrainLibrary.testing(store: TrainStore(inMemory: true), remote: { MockTrainSource(start: .empty) }, restore: false)
        let vm = TrainHistoryViewModel(library: library)
        #expect(vm.state == .loading && vm.subtitle == nil, "outline rows, no subtitle while loading")
        await vm.load()
        #expect(vm.state == .empty && vm.isEmpty && !vm.failed && vm.subtitle == nil, "the platform said: none")
    }

    @Test func theSubtitleCountsTheLast90Days() {
        let library = TrainHistoryFixtures.library()
        let many = TrainHistoryViewModel(library: library, sessions: (0..<25).map { summary(daysAgo: $0) }, fresh: true)
        #expect(plain(many.subtitle) == "25 workouts · last 90 days")
        let one = TrainHistoryViewModel(library: library, sessions: [summary(daysAgo: 3)], fresh: true)
        #expect(plain(one.subtitle) == "1 workout · last 90 days")
        #expect(TrainHistoryViewModel(library: library, sessions: [], fresh: true).subtitle == nil)
    }

    @Test func aFailedReadWithNothingCachedIsAFailureNotEmpty() async {
        let rig = TrainHistoryFixtures.rig(cached: false, fails: true)
        let vm = TrainHistoryViewModel(library: rig.library)
        await vm.load()
        #expect(vm.state == .failed && vm.failed && !vm.isEmpty && !vm.isLoading && !vm.isOffline)
        #expect(vm.subtitle == nil && vm.weeks.isEmpty)
        // Try again, online.
        rig.source.fails = false
        await vm.refresh()
        #expect(vm.state == .list && vm.fresh && !vm.isOffline && !vm.sessions.isEmpty)
    }

    @Test func onlyTheEmptyListThePlatformSentIsEmpty() async {
        let rig = TrainHistoryFixtures.rig(cached: false, list: [])
        let vm = TrainHistoryViewModel(library: rig.library)
        await vm.load()
        #expect(vm.state == .empty && !vm.isOffline)
        // Offline later: the platform's empty list, as of when it came, said to be the copy.
        rig.source.fails = true
        await vm.refresh()
        #expect(vm.state == .empty && vm.isOffline && vm.fetchedAt != nil)
    }

    @Test func historysFirstPaintAndItsOfflineCopyKeepToTheLast90Days() async {
        let recent = summary(daysAgo: 10), old = summary(daysAgo: 100)
        let rig = TrainHistoryFixtures.rig(cached: false, fails: true)
        let fetched = Date.now.addingTimeInterval(-3_600)
        rig.store.saveDocument([recent, old], key: "train.sessions", at: fetched)
        #expect(rig.library.cachedSessions().map(\.id) == [recent.id, old.id], "the cache keeps both")
        #expect(rig.library.cachedSessions(now: .now).map(\.id) == [recent.id], "the first paint: nothing the read would drop")
        let vm = TrainHistoryViewModel(library: rig.library)
        await vm.load()
        #expect(vm.sessions.map(\.id) == [recent.id])
        #expect(vm.state == .list && vm.isOffline && !vm.fresh)
        #expect(abs((vm.fetchedAt ?? .distantPast).timeIntervalSince(fetched)) < 0.01)
        #expect(plain(vm.subtitle) == "1 workout · last 90 days")
    }

    @Test func theOfflineLineSaysWhenTheCopyWasFetched() {
        let fetched = noon("2026-11-13").addingTimeInterval(2 * 3600 + 5 * 60) // 14:05
        #expect(plain(TrainOfflineNote.text(fetchedAt: fetched, now: friday)) == "Offline · as of 2:05 PM")
        #expect(plain(TrainOfflineNote.text(fetchedAt: fetched.addingTimeInterval(-86_400), now: friday))
                == "Offline · as of Yesterday 2:05 PM")
        #expect(TrainOfflineNote.text(fetchedAt: nil, now: friday) == "Offline", "only this phone's sessions: no time to give")
    }

    // MARK: session detail

    @Test func aScoredSessionLightsTheNumeralAndListsItsSets() throws {
        let s = session()
        let content = SessionDetailContent(summary: SessionSummary(s), session: s, loaded: true, locale: english) { _ in "Bench press" }
        #expect(content.state == .loaded && content.title == "Upper A")
        #expect(plain(content.subtitle) == "Fri, Nov 13 · 55 min · 2 sets", "working sets only")
        #expect(content.spokenSubtitle == "Friday, November 13, 55 minutes, 2\u{00A0}sets")
        #expect(content.hero.strain == 10.4 && content.hero.numeral != nil)
        #expect(content.tiles.map(\.id) == ["volume", "load"], "strain is the hero, not a tile")
        #expect(content.tiles[0].value == "7,500" && content.tiles[0].unit == "kg" && content.tiles[1].value == "85.0")
        let lines = try #require(content.exercises.first?.sets)
        #expect(content.exercises.first?.name == "Bench press")
        #expect(lines.map(\.position) == ["W", "2", "3"], "the warm-up drawn W, the position counting it")
        #expect(lines[0].spokenPosition == "Set 1 of 3, warm-up" && lines[1].spokenPosition == "Set 2 of 3")
        #expect(lines[1].text == "80\u{00A0}kg × 5" && lines[1].rpe == "RPE 8.5" && lines[2].rpe == nil)
        #expect(lines[1].spokenValue == "5\u{00A0}reps at 80\u{00A0}kilograms, RPE 8.5")
    }

    @Test func anUnscoredSessionLeavesTheNumeralUnlit() {
        // The list's summary still carries a strain the loaded session no longer has: the session's absence wins.
        let content = SessionDetailContent(summary: SessionSummary(MockTrain.completed), session: MockTrain.completedUnscored,
                                           loaded: true, locale: english)
        #expect(content.hero.strain == nil && content.hero.numeral == nil)
        #expect(content.hero.caption == SessionDetailContent.noStrainCaption)
        #expect(content.tiles[1].value == Fmt.placeholder)
    }

    @Test func theSummaryPaintsUntilTheSessionArrives() {
        let summary = SessionSummary(MockTrain.completed)
        let loading = SessionDetailContent(summary: summary, session: nil, loaded: false, locale: english)
        #expect(loading.state == .loading && loading.title == MockTrain.completed.title)
        #expect(loading.hero.strain == MockTrain.completed.strain && loading.exercises.isEmpty)
        let failed = SessionDetailContent(summary: nil, session: nil, loaded: true, locale: english)
        #expect(failed.state == .failed && failed.subtitle == nil && failed.title == "Workout")
        #expect(failed.hero.caption.isEmpty, "the failure's message speaks, not the caption")
        let unknown = SessionDetailContent(summary: nil, session: nil, loaded: false, locale: english)
        #expect(unknown.state == .loading && unknown.title == nil, "nothing known yet: the title is an outline, not \"Workout\"")
    }

    @Test func timedAndDistanceSetsShowTheirTimeAndDistance() {
        #expect(SessionDetailContent.text(set(0, seconds: 45), locale: english) == "0:45")
        // A distance in the locale's road unit, as the app's other distances ("5.0 km", "3.1 mi").
        let distance = SessionDetailContent.text(set(0, meters: 5_000), locale: english)
        #expect(plain(distance) == "3.1 mi" && plain(distance) == plain(Fmt.distance(meters: 5_000, locale: english)))
        #expect(plain(SessionDetailContent.text(set(0, seconds: 1_500, meters: 5_000), locale: english)) == plain("\(distance) · 25:00"))
        #expect(SessionDetailContent.text(set(0, reps: 8), locale: english) == "× 8")
    }

    @Test func timedAndDistanceSetsAreSpokenInWords() {
        #expect(SessionDetailContent.spoken(set(0, seconds: 45), locale: english) == "45 seconds")
        #expect(SessionDetailContent.spoken(set(0, seconds: 90), locale: english) == "1 minute, 30 seconds")
        #expect(SessionDetailContent.spoken(set(0, seconds: 120), locale: english) == "2 minutes")
        #expect(SessionDetailContent.spoken(set(0, seconds: 1_500, meters: 5_000), locale: english) == "3.1 miles, 25 minutes")
        let line = SessionDetailContent.lines([set(0, seconds: 45, warmup: false)], locale: english)
        #expect(line.first?.spokenValue == "45 seconds")
    }

    @Test func aFailedReadAgainKeepsTheSession() async {
        let rig = TrainHistoryFixtures.rig(session: MockTrain.completed)
        let vm = SessionDetailViewModel(sessionID: MockTrain.completed.id, library: rig.library)
        await vm.load()
        #expect(vm.content(locale: english).state == .loaded)
        // Back from the exercise page, offline: the read again fails; the session stays, no outlines meanwhile.
        rig.source.fails = true
        await vm.load()
        #expect(vm.session?.id == MockTrain.completed.id && vm.loaded)
        #expect(vm.content(locale: english).state == .loaded && !vm.content(locale: english).exercises.isEmpty)
    }

    // MARK: exercise page

    @Test func theChangeIsBlueOnlyWhenItRises() {
        #expect(plain(E1RMChange.text(11.6, locale: english)) == "▲ 11.6 kg" && E1RMChange.color(11.6) == Theme.metricStrain)
        #expect(plain(E1RMChange.text(-1.5, locale: english)) == "▼ 1.5 kg" && E1RMChange.color(-1.5) == Theme.textSecondary, "no red")
        #expect(E1RMChange.text(0.04, locale: english) == String(localized: "Steady") && E1RMChange.color(0.04) == Theme.textSecondary)
        #expect(E1RMChange.spoken(11.6, locale: english) == "Up 11.6\u{00A0}kg" && E1RMChange.spoken(-1.5, locale: english) == "Down 1.5\u{00A0}kg")
        #expect(plain(E1RMChange.overWindow(E1RMChange.text(11.6, locale: english))) == "▲ 11.6 kg in 90 days")
    }

    @Test func e1rmIsATrainingMetricInStrainBlue() {
        #expect(MetricSpec.e1rm.color == Theme.metricStrain)
    }

    private func benchPage(_ e1rm: [E1RMPoint], now: String = "2026-11-13", exercise: UUID = MockTrain.bench.id,
                           library: TrainLibrary? = nil) -> ExerciseDetailViewModel {
        ExerciseDetailViewModel(exerciseID: exercise, history: ExerciseHistory(exerciseId: exercise, prs: [], sessions: [], e1rm: e1rm),
                                library: library ?? TrainHistoryFixtures.library(), clock: TestClock(now: noon(now)))
    }

    @Test func theHeroIsTheNewestEstimateAndTheChangeSpansTheWindow() throws {
        let vm = benchPage([point("2026-09-01", 81.5), point("2026-10-20", 90.4), point("2026-11-12", 93.3)])
        #expect(!vm.isLoading && vm.hasTrend && vm.lead == .estimate)
        #expect(vm.latest == 93.3 && vm.heroDate(locale: english) == nil)
        #expect(E1RMChange.rounded(try #require(vm.change)) == 11.8, "93.3 − 81.5")
        #expect(E1RMChange.rounded(try #require(vm.lastChange)) == 2.9, "93.3 − 90.4")
        let once = benchPage([point("2026-11-12", 93.3)])
        #expect(!once.hasTrend && once.latest == 93.3 && once.change == nil && once.lastChange == nil)
        #expect(once.emptyChartText == "Log this exercise a few more times to see a trend.")
    }

    @Test func anEstimateOlderThanTheWindowStillLeadsWithItsDate() {
        // The last session 120 days ago: the newest estimate overall, dated, rather than an unlit hero.
        let vm = benchPage([point("2026-06-01", 85.0), point("2026-07-16", 88.5)])
        #expect(vm.points.isEmpty && !vm.hasTrend && vm.change == nil)
        #expect(vm.latest == 88.5)
        #expect(vm.heroDate(locale: english) == "As of Jul 16")
        let lastYear = benchPage([point("2025-12-20", 88.5)], now: "2026-11-13")
        #expect(lastYear.heroDate(locale: english) == "As of Dec 20, 2025")
    }

    @Test func exercisesWithoutAn1RMLeadWithWhatTheyHave() {
        let library = TrainHistoryFixtures.library()
        #expect(benchPage([], exercise: MockTrain.plank.id, library: library).lead == .sets, "a timed exercise has no 1RM")
        let pullUps = benchPage([], exercise: MockTrain.pullUp.id, library: library)
        #expect(pullUps.lead == .noAddedWeight && pullUps.latest == nil)
        #expect(pullUps.noAddedWeightText == "An estimated 1RM needs sets with added weight.")
        #expect(benchPage([point("2026-11-12", 95)], exercise: MockTrain.pullUp.id, library: library).lead == .estimate,
                "weighted pull-ups have their estimate")
        #expect(benchPage([], library: library).lead == .estimate, "a barbell lift without sets yet: the unlit hero")
    }

    @Test func aRecentSessionsBestIsToTheTenth() {
        let row = ExerciseDetailViewModel.RecentRow(id: 0, date: "Nov 13", sets: "", spokenSets: "", best: 93.33, locale: english)
        #expect(row.bestText == "93.3", "as the hero and the chart, not to the half kilogram (93.5)")
        #expect(plain(row.bestSpoken) == "e1RM 93.3 kg")
        #expect(ExerciseDetailViewModel.RecentRow(id: 1, date: "", sets: "", spokenSets: "", best: 99.96, locale: english).bestText == "100")
    }

    /// The locale handed in, not the phone's: a German one writes German numbers on any simulator (the app passes its own).
    @Test func theNumbersFollowTheLocaleTheyAreGiven() throws {
        let german = Locale(identifier: "de_DE")
        let row = TrainHistoryRows.row(SessionSummary(session()), locale: german)
        #expect(plain(row.meta)?.hasSuffix(" · 7.500 kg") == true && row.value == "85,0", "\(row.meta) · \(row.value ?? "")")
        let a = SessionSummary(session(load: 85.4, volume: 7_500)), b = SessionSummary(session(load: 40.2, volume: 4_700))
        let week = TrainHistoryViewModel.Week(start: friday, sessions: [a, b])
        #expect(plain(week.summary(locale: german)) == "2 sessions · 12,2 t · load 126")
        let s = session()
        let content = SessionDetailContent(summary: SessionSummary(s), session: s, loaded: true, locale: german) { _ in "Bench press" }
        #expect(content.tiles[0].value == "7.500" && content.tiles[1].value == "85,0")
        let lines = try #require(content.exercises.first?.sets)
        #expect(lines[1].rpe == "RPE 8,5" && lines[1].spokenValue == "5\u{00A0}reps at 80\u{00A0}kilograms, RPE 8,5")
        #expect(plain(E1RMChange.text(11.6, locale: german)) == "▲ 11,6 kg" && E1RMChange.spoken(-1.5, locale: german) == "Down 1,5\u{00A0}kg")
        let recent = ExerciseDetailViewModel.RecentRow(id: 0, date: "", sets: "", spokenSets: "", best: 93.33, locale: german)
        #expect(recent.bestText == "93,3" && plain(recent.bestSpoken) == "e1RM 93,3 kg")
    }

    @Test func aFailedExerciseReadWithNothingCachedIsAFailure() async {
        let rig = TrainHistoryFixtures.rig(cached: false, fails: true)
        let vm = ExerciseDetailViewModel(exerciseID: MockTrain.bench.id, library: rig.library, clock: TestClock(now: .now))
        await vm.load()
        #expect(vm.failed && !vm.isLoading && !vm.isOffline && vm.history == nil)
        rig.source.fails = false
        await vm.load()
        #expect(!vm.failed && vm.fresh && vm.history != nil)
    }

    @Test func aFailedExerciseReadShowsTheCopyOffline() async {
        let rig = TrainHistoryFixtures.rig()
        let online = ExerciseDetailViewModel(exerciseID: MockTrain.bench.id, library: rig.library, clock: TestClock(now: .now))
        await online.load()
        #expect(online.fresh && !online.isOffline)
        // Relaunched, offline: the store's copy, said to be one.
        rig.source.fails = true
        let relaunched = TrainLibrary.testing(store: rig.store, remote: { rig.source }, restore: true)
        let offline = ExerciseDetailViewModel(exerciseID: MockTrain.bench.id, library: relaunched, clock: TestClock(now: .now))
        await offline.load()
        #expect(offline.isOffline && !offline.failed && offline.history?.e1rm == online.history?.e1rm)
        #expect(offline.fetchedAt != nil)
    }

    // MARK: in a window

    private func ids(_ w: HostedWindow) -> [String] { w.nodes().compactMap(\.identifier) }

    /// The "Recent sets" group's title (the group itself, a container without a label, isn't one of VoiceOver's nodes).
    private func hasRecentSets(_ w: HostedWindow) -> Bool {
        w.nodes().contains { $0.label == String(localized: "Recent sets") && $0.traits.contains(.header) }
    }

    @Test func historyDrawsWeeksOfActivityRows() async throws {
        let view = NavigationStack { TrainHistoryView().trainDestinations() }.environment(TrainHistoryFixtures.library())
        try await HostedWindow.run(width: Self.width, height: 2_400, bottomInset: 0, view) { w in
            try await w.wait("rows") { ids(w).contains { $0.hasPrefix("history.row.") } }
            try await w.settle()
            let nodes = w.nodes()
            let header = try #require(nodes.first { $0.label == String(localized: "History") && $0.traits.contains(.header) })
            #expect(header.frame.minY < 120)
            let rows = nodes.filter { $0.identifier?.hasPrefix("history.row.") == true }
            #expect(!rows.isEmpty)
            for row in rows {
                #expect(row.frame.height >= ActivityListRowSpec.minHeight - 0.5, "\(row.frame)")
                #expect(row.traits.contains(.button) && row.label.contains("Muscular load"), "\(row.label)")
            }
            #expect(zip(rows, rows.dropFirst()).allSatisfy { $1.frame.minY - $0.frame.maxY >= TrainHistoryLayout.rowSpacing - 0.5 })
            let weeks = nodes.filter { $0.label.hasPrefix("Week of") }
            // "1 session" or "3 sessions" (the catalog's plural).
            #expect(!weeks.isEmpty && weeks.allSatisfy { $0.traits.contains(.header) && ($0.value ?? "").contains("session") },
                    "\(weeks.map { $0.value ?? "nil" })")
            #expect(!ids(w).contains("history.loading") && !ids(w).contains("history.empty"))
        }
    }

    @Test func historyLoadingIsThreeOutlineRows() async throws {
        let view = NavigationStack { TrainHistoryView() }.environment(TrainHistoryFixtures.library(hangs: true, cached: false))
        try await HostedWindow.run(width: Self.width, height: 844, view) { w in
            try await w.wait("outlines") { ids(w).contains("history.loading") }
            let outlines = try #require(w.nodes().first { $0.identifier == "history.loading" })
            #expect(outlines.label == "Loading workouts")
            let rows = CGFloat(TrainHistoryLayout.placeholderRows)
            let expected = rows * ActivityListRowSpec.minHeight + (rows - 1) * TrainHistoryLayout.rowSpacing
            #expect(abs(outlines.frame.height - expected) < 1, "\(outlines.frame)")
            #expect(!ids(w).contains("history.empty"))
        }
    }

    @Test func historyEmptyIsAnOutlinedCard() async throws {
        let library = TrainLibrary.testing(store: TrainStore(inMemory: true), remote: { MockTrainSource(start: .empty) }, restore: false)
        let view = NavigationStack { TrainHistoryView() }.environment(library)
        try await HostedWindow.run(width: Self.width, height: 844, view) { w in
            try await w.wait("empty") { ids(w).contains("history.empty") }
            let empty = try #require(w.nodes().first { $0.identifier == "history.empty" })
            #expect(empty.label.hasPrefix("No workouts logged yet."))
            #expect(empty.frame.height >= ActivityListRowSpec.minHeight - 0.5)
            #expect(empty.frame.width <= Self.width - 2 * Theme.Metrics.screenPadding + 0.5)
        }
    }

    @Test func aSessionDetailLeadsWithTheStrainAndOpensItsExercises() async throws {
        let view = NavigationStack { SessionDetailView(sessionID: MockTrain.completed.id).trainDestinations() }
            .environment(TrainHistoryFixtures.library(session: MockTrain.completed))
        try await HostedWindow.run(width: Self.width, height: 2_400, bottomInset: 0, view) { w in
            try await w.wait("exercises") { ids(w).contains { $0.hasPrefix("sessionDetail.exercise.") } }
            try await w.settle()
            let nodes = w.nodes()
            let header = try #require(nodes.first { $0.label == MockTrain.completed.title && $0.traits.contains(.header) })
            let numeral = try #require(nodes.first { $0.identifier == "sessionDetail.numeral" })
            #expect(numeral.frame.minY - header.frame.maxY >= SessionDetailLayout.heroGap - 1, "22 under the header")
            let volume = try #require(nodes.first { $0.identifier == "sessionDetail.stat.volume" })
            let load = try #require(nodes.first { $0.identifier == "sessionDetail.stat.load" })
            #expect(abs(volume.frame.minY - load.frame.minY) < 0.5 && abs(volume.frame.height - load.frame.height) < 0.5)
            #expect(load.frame.minX - volume.frame.maxX >= SessionDetailLayout.spacing - 0.5)
            #expect(nodes.contains { $0.identifier == "sessionDetail.notes" })
            // One container per exercise: the name a button with its hint, each set its own element.
            let heads = nodes.filter { $0.hint == String(localized: "Opens the exercise's history") }
            #expect(heads.count == MockTrain.completed.exercises.count)
            #expect(heads.allSatisfy { $0.traits.contains(.button) })
            let sets = nodes.filter { $0.label.hasPrefix("Set ") }
            #expect(sets.count == MockTrain.completed.exercises.flatMap(\.sets).count)
            // A set's row is 34 high: its text's frame is VoiceOver's, so the rows' pitch shows it.
            let pitches = zip(sets, sets.dropFirst()).map { $1.frame.minY - $0.frame.minY }
            let inCard = pitches.filter { abs($0 - SessionDetailLayout.setRowHeight) < 0.5 }
            #expect(inCard.count == sets.count - MockTrain.completed.exercises.count, "\(pitches)")
            #expect(pitches.allSatisfy { $0 > SessionDetailLayout.setRowHeight - 0.5 }, "\(pitches)")
            // The name opens the exercise's page.
            let first = try #require(heads.first)
            first.activate()
            try await w.wait("the exercise page") { ids(w).contains("exerciseDetail.numeral") }
        }
    }

    @Test func aSessionDetailThatCannotLoadSaysSo() async throws {
        let view = NavigationStack { SessionDetailView(sessionID: UUID()) }.environment(TrainHistoryFixtures.library(cached: false))
        try await HostedWindow.run(width: Self.width, height: 844, view) { w in
            try await w.wait("the failure") { w.node("This workout couldn't be loaded.") != nil }
            #expect(ids(w).contains("sessionDetail.failure.retry"))
            #expect(!ids(w).contains("sessionDetail.loading"))
        }
    }

    /// R3: a session opened before anything of it is known (a link from outside History). At AX3 the header stacks, and the
    /// title's outline goes where the title will be, from the leading inset under Back: it was centred over the whole stacked
    /// header, between Back's line and the title's.
    @Test func theLoadingTitlesOutlineSitsUnderBackAtAX3() async throws {
        let view = NavigationStack { SessionDetailPage(content: SessionDetailContent(summary: nil, session: nil, loaded: false)) }
        try await HostedWindow.run(width: Self.width, height: 1_400, bottomInset: 0, typeSize: .accessibility3,
                                   category: .accessibilityExtraLarge, view) { w in
            try await w.wait("the header") { ids(w).contains("sessionDetail.header") }
            try await w.settle()
            let nodes = w.nodes()
            let header = try #require(nodes.first { $0.identifier == "sessionDetail.header" })
            let back = try #require(nodes.first { $0.identifier == "sessionDetail.back" })
            #expect(header.label == String(localized: "Loading the workout") && header.traits.contains(.header))
            #expect(header.frame.minY >= back.frame.maxY - 1, "stacked: the title's line under Back's \(back.frame), \(header.frame)")
            // The outline (`surface` and a hairline on `background`): the only thing drawn between Back and the hero.
            let region = CGRect(x: 0, y: back.frame.maxY + 1, width: Self.width, height: header.frame.maxY + 4 - back.frame.maxY - 1)
            let pixels = try WindowPixels(w, scale: 2)
            let paper = pixels.at(2, region.midY)
            let outline = try #require(pixels.box(in: region) { abs($0.r - paper.r) + abs($0.g - paper.g) + abs($0.b - paper.b) > 0.05 },
                                       "the outline under \(back.frame)")
            #expect(abs(outline.minX - header.frame.minX) <= 2, "from the leading inset: \(outline), the header \(header.frame)")
            #expect(abs(outline.width - SessionDetailLayout.titlePlaceholderWidth) <= 3, "\(outline)")
            #expect(outline.midY >= header.frame.minY && outline.midY <= header.frame.maxY, "on the title's line: \(outline) in \(header.frame)")
        }
    }

    @Test func theExercisePageLeadsWithItsEstimate() async throws {
        let view = NavigationStack { ExerciseDetailView(exerciseID: MockTrain.bench.id).trainDestinations() }
            .environment(TrainHistoryFixtures.library())
        try await HostedWindow.run(width: Self.width, height: 2_000, bottomInset: 0, view) { w in
            try await w.wait("the chart") { ids(w).contains("exerciseDetail.chart") }
            try await w.settle()
            let nodes = w.nodes()
            let header = try #require(nodes.first { $0.label == MockTrain.bench.name && $0.traits.contains(.header) })
            let hero = try #require(nodes.first { $0.identifier == "exerciseDetail.numeral" })
            #expect(hero.label == String(localized: "Estimated 1RM"))
            #expect((hero.value ?? "").contains("kilograms") && (hero.value ?? "").contains("in 90\u{00A0}days"), "\(hero.value ?? "")")
            #expect(hero.frame.minY - header.frame.maxY >= ExerciseDetailLayout.heroGap - 1)
            let chart = try #require(nodes.first { $0.identifier == "exerciseDetail.chart" })
            #expect(chart.label == "Estimated one-rep max, last 90\u{00A0}days")
            #expect(abs(chart.frame.height - ExerciseDetailLayout.chartHeight) < 1, "\(chart.frame)")
            #expect(nodes.contains { $0.label == String(localized: "Personal records") && $0.traits.contains(.header) })
            #expect(nodes.contains { $0.label == String(localized: "Recent sets") && $0.traits.contains(.header) })
            #expect(!ids(w).contains("exerciseDetail.loading"))
        }
    }

    @Test func aFirstTimeExerciseHasNoTrendAndNoChange() async throws {
        let view = NavigationStack { ExerciseDetailView(exerciseID: MockTrain.bench.id) }
            .environment(TrainHistoryFixtures.library(history: MockTrain.firstTimeHistory(for: MockTrain.bench.id)))
        try await HostedWindow.run(width: Self.width, height: 1_400, bottomInset: 0, view) { w in
            try await w.wait("no trend") { ids(w).contains("exerciseDetail.noTrend") }
            #expect(!ids(w).contains("exerciseDetail.chart"))
            let hero = try #require(w.nodes().first { $0.identifier == "exerciseDetail.numeral" })
            #expect(!(hero.value ?? "").contains("90 days"), "one point: no change to show")
        }
    }

    @Test func historyThatCannotLoadSaysSoAndTriesAgain() async throws {
        let rig = TrainHistoryFixtures.rig(cached: false, fails: true)
        let view = NavigationStack { TrainHistoryView() }.environment(rig.library)
        try await HostedWindow.run(width: Self.width, height: 844, view) { w in
            try await w.wait("the failure") { ids(w).contains("history.failure.retry") }
            #expect(w.node("Your workouts couldn't be loaded.") != nil)
            #expect(!ids(w).contains("history.empty") && !ids(w).contains("history.loading"), "never \"No workouts logged yet\"")
            rig.source.fails = false
            try #require(w.nodes().first { $0.identifier == "history.failure.retry" }).activate()
            try await w.wait("rows") { ids(w).contains { $0.hasPrefix("history.row.") } }
            #expect(!ids(w).contains("history.failure.retry") && !ids(w).contains("history.offline"))
        }
    }

    @Test func historyOfflineShowsTheCopyAndWhenItCame() async throws {
        let rig = TrainHistoryFixtures.rig()
        _ = await rig.library.sessionsRead()
        rig.source.fails = true
        let view = NavigationStack { TrainHistoryView() }.environment(rig.library)
        try await HostedWindow.run(width: Self.width, height: 1_400, bottomInset: 0, view) { w in
            try await w.wait("the offline line") { ids(w).contains("history.offline") }
            let line = try #require(w.nodes().first { $0.identifier == "history.offline" })
            #expect(line.label.hasPrefix("Offline · as of "), "\(line.label)")
            #expect(ids(w).contains { $0.hasPrefix("history.row.") })
            #expect(!ids(w).contains("history.failure.retry"))
        }
    }

    @Test func theSessionDetailKeepsItsSessionWhenAReadFailsOnReturn() async throws {
        let rig = TrainHistoryFixtures.rig(session: MockTrain.completed)
        let view = NavigationStack { SessionDetailView(sessionID: MockTrain.completed.id).trainDestinations() }
            .environment(rig.library)
        try await HostedWindow.run(width: Self.width, height: 2_400, bottomInset: 0, view) { w in
            try await w.wait("exercises") { ids(w).contains { $0.hasPrefix("sessionDetail.exercise.") } }
            let reads = rig.source.sessionReads
            let head = try #require(w.nodes().first { $0.hint == String(localized: "Opens the exercise's history") })
            head.activate()
            try await w.wait("the exercise page") { ids(w).contains("exerciseDetail.numeral") }
            // Offline now; back on the session, it reads again and fails.
            rig.source.fails = true
            try #require(w.nodes().first { $0.identifier == "exerciseDetail.back" }).activate()
            try await w.wait("the session again") { !ids(w).contains("exerciseDetail.numeral") && ids(w).contains("sessionDetail.numeral") }
            try await w.settle()
            // The hosted window doesn't appear the page again (no second read): the failing read again is
            // `aFailedReadAgainKeepsTheSession`'s.
            #expect(rig.source.sessionReads >= reads)
            let shown = ids(w)
            #expect(shown.filter { $0.hasPrefix("sessionDetail.exercise.") && $0.hasSuffix(".open") }.count
                    == MockTrain.completed.exercises.count, "the cards stay")
            #expect(!shown.contains("sessionDetail.failure.retry") && !shown.contains("sessionDetail.loading"))
        }
    }

    @Test func anExercisePageThatCannotLoadSaysSoAndNothingElse() async throws {
        let rig = TrainHistoryFixtures.rig(cached: false, fails: true)
        let view = NavigationStack { ExerciseDetailView(exerciseID: MockTrain.bench.id, name: "Bench press") }.environment(rig.library)
        try await HostedWindow.run(width: Self.width, height: 1_400, bottomInset: 0, view) { w in
            try await w.wait("the failure") { ids(w).contains("exerciseDetail.failure.retry") }
            #expect(w.node("This exercise's history couldn't be loaded.") != nil)
            let shown = ids(w)
            for absent in ["exerciseDetail.numeral", "exerciseDetail.loading", "exerciseDetail.noTrend", "exerciseDetail.chartHead"] {
                #expect(!shown.contains(absent), "\(absent): no unlit hero, no chart card")
            }
            #expect(w.node("No sets logged") == nil && !hasRecentSets(w), "no \"No sets logged\", no Recent sets")
            rig.source.fails = false
            try #require(w.nodes().first { $0.identifier == "exerciseDetail.failure.retry" }).activate()
            try await w.wait("the estimate") { ids(w).contains("exerciseDetail.numeral") }
            #expect(!ids(w).contains("exerciseDetail.failure.retry"))
        }
    }

    @Test func anExercisePageOfflineShowsTheCopyAndWhenItCame() async throws {
        let rig = TrainHistoryFixtures.rig()
        _ = await rig.library.historyRead(for: MockTrain.bench.id)
        rig.source.fails = true
        let relaunched = TrainLibrary.testing(store: rig.store, remote: { rig.source }, restore: true)
        let view = NavigationStack { ExerciseDetailView(exerciseID: MockTrain.bench.id) }.environment(relaunched)
        try await HostedWindow.run(width: Self.width, height: 2_000, bottomInset: 0, view) { w in
            try await w.wait("the offline line") { ids(w).contains("exerciseDetail.offline") }
            let line = try #require(w.nodes().first { $0.identifier == "exerciseDetail.offline" })
            #expect(line.label.hasPrefix("Offline · as of "), "\(line.label)")
            #expect(ids(w).contains("exerciseDetail.numeral") && hasRecentSets(w))
            #expect(!ids(w).contains("exerciseDetail.failure.retry"))
        }
    }

    @Test func aTimedExerciseLeadsWithItsRecentSets() async throws {
        let holds = (0..<3).map { SessionSet(setIndex: $0, durationSec: 45) }
        let history = ExerciseDetailPreview.withoutEstimates(MockTrain.plank, sets: holds)
        let view = NavigationStack { ExerciseDetailView(exerciseID: MockTrain.plank.id) }
            .environment(TrainHistoryFixtures.library(history: history))
        try await HostedWindow.run(width: Self.width, height: 1_400, bottomInset: 0, view) { w in
            try await w.wait("the sets") { hasRecentSets(w) }
            try await w.settle()
            let shown = ids(w)
            #expect(!shown.contains("exerciseDetail.numeral") && !shown.contains("exerciseDetail.chartHead")
                    && !shown.contains("exerciseDetail.noTrend"), "no 1RM for a hold")
            let nodes = w.nodes()
            let header = try #require(nodes.first { $0.label == MockTrain.plank.name && $0.traits.contains(.header) })
            let title = try #require(nodes.first { $0.label == String(localized: "Recent sets") && $0.traits.contains(.header) })
            #expect(title.frame.minY - header.frame.maxY >= ExerciseDetailLayout.heroGap - 1, "Recent sets first, 22 under the header")
            #expect(nodes.contains { $0.label.contains("45 seconds, 45 seconds, 45 seconds") }, "\(nodes.map(\.label))")
        }
    }

    @Test func aBodyweightExerciseWithoutAddedWeightSaysWhyThereIsNo1RM() async throws {
        let reps = (0..<3).map { SessionSet(setIndex: $0, reps: 8) }
        let history = ExerciseDetailPreview.withoutEstimates(MockTrain.pullUp, sets: reps)
        let view = NavigationStack { ExerciseDetailView(exerciseID: MockTrain.pullUp.id) }
            .environment(TrainHistoryFixtures.library(history: history))
        try await HostedWindow.run(width: Self.width, height: 1_400, bottomInset: 0, view) { w in
            try await w.wait("the hero") { ids(w).contains("exerciseDetail.numeral") }
            try await w.settle()
            let hero = try #require(w.nodes().first { $0.identifier == "exerciseDetail.numeral" })
            #expect(hero.value == "An estimated 1RM needs sets with added weight.")
            #expect(w.node("An estimated 1RM needs sets with added weight.") == nil, "one element: the hero says it")
            let shown = ids(w)
            #expect(!shown.contains("exerciseDetail.chartHead") && !shown.contains("exerciseDetail.noTrend"))
            #expect(hasRecentSets(w) && w.node("No sets logged") == nil)
        }
    }

    @Test func inASheetTheExercisePageCloses() async throws {
        var closed = false
        let view = ExerciseDetailView(exerciseID: MockTrain.bench.id, onClose: { closed = true })
            .environment(TrainHistoryFixtures.library())
        try await HostedWindow.run(width: Self.width, height: 1_400, bottomInset: 0, view) { w in
            try await w.wait("the close circle") { ids(w).contains("sheet.close") }
            #expect(!ids(w).contains("exerciseDetail.back"))
            let close = try #require(w.nodes().first { $0.identifier == "sheet.close" })
            close.activate()
            #expect(closed)
        }
    }
}
