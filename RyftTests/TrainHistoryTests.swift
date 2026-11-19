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

    /// The text with its no-break spaces as plain ones.
    private func plain(_ s: String?) -> String? { s?.replacingOccurrences(of: "\u{00A0}", with: " ") }

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
        #expect(plain(week.summary) == "2 sessions · 12.2 t · load 126")
        #expect(week.spokenSummary(locale: english) == "2 sessions, 12,200 kilograms, Muscular load 126")
        #expect(week.title(locale: english) == "Week of Nov 13")
        let unscored = TrainHistoryViewModel.Week(start: friday, sessions: [SessionSummary(session(load: nil))])
        #expect(plain(unscored.summary)?.hasSuffix("load –") == true)
    }

    @Test func historyLoadsWithOutlinesThenSaysWhereSessionsComeFrom() async {
        let library = TrainLibrary(store: TrainStore(inMemory: true), remote: { MockTrainSource(start: .empty) }, restore: false)
        let vm = TrainHistoryViewModel(library: library)
        #expect(vm.isLoading && vm.subtitle == nil, "outline rows, no subtitle while loading")
        await vm.load()
        #expect(!vm.isLoading && vm.isEmpty && vm.subtitle == nil)

        let demo = TrainHistoryViewModel(library: TrainHistoryFixtures.library())
        await demo.load()
        #expect(demo.subtitle == "\(demo.sessions.count) workouts")
    }

    // MARK: session detail

    @Test func aScoredSessionLightsTheNumeralAndListsItsSets() throws {
        let s = session()
        let content = SessionDetailContent(summary: SessionSummary(s), session: s, loaded: true, locale: english) { _ in "Bench press" }
        #expect(content.state == .loaded && content.title == "Upper A")
        #expect(plain(content.subtitle) == "Fri, Nov 13 · 55 min · 2 sets", "working sets only")
        #expect(content.spokenSubtitle == "Friday, November 13, 55 minutes, 2 sets")
        #expect(content.hero.strain == 10.4 && content.hero.numeral != nil)
        #expect(content.tiles.map(\.id) == ["volume", "load"], "strain is the hero, not a tile")
        #expect(content.tiles[0].value == "7,500" && content.tiles[0].unit == "kg" && content.tiles[1].value == "85.0")
        let lines = try #require(content.exercises.first?.sets)
        #expect(content.exercises.first?.name == "Bench press")
        #expect(lines.map(\.position) == ["W", "2", "3"], "the warm-up drawn W, the position counting it")
        #expect(lines[0].spokenPosition == "Set 1 of 3, warm-up" && lines[1].spokenPosition == "Set 2 of 3")
        #expect(lines[1].text == "80 kg × 5" && lines[1].rpe == "RPE 8.5" && lines[2].rpe == nil)
        #expect(lines[1].spokenValue == "5 reps at 80 kilograms, RPE 8.5")
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
        #expect(failed.state == .failed && failed.subtitle == nil && failed.title == String(localized: "Workout"))
        #expect(failed.hero.caption.isEmpty, "the failure's message speaks, not the caption")
    }

    @Test func timedAndDistanceSetsShowTheirTimeAndDistance() {
        #expect(SessionDetailContent.text(set(0, seconds: 45)) == "0:45")
        // A distance in the locale's road unit, as the app's other distances ("5.0 km", "3.1 mi").
        let distance = SessionDetailContent.text(set(0, meters: 5_000))
        #expect(plain(distance) == plain(Fmt.distance(meters: 5_000)) && distance != Fmt.placeholder)
        #expect(plain(SessionDetailContent.text(set(0, seconds: 1_500, meters: 5_000))) == plain("\(distance) · 25:00"))
        #expect(SessionDetailContent.text(set(0, reps: 8)) == "× 8")
    }

    // MARK: exercise page

    @Test func theChangeIsBlueOnlyWhenItRises() {
        #expect(plain(E1RMChange.text(11.6)) == "▲ 11.6 kg" && E1RMChange.color(11.6) == Theme.metricStrain)
        #expect(plain(E1RMChange.text(-1.5)) == "▼ 1.5 kg" && E1RMChange.color(-1.5) == Theme.textSecondary, "no red")
        #expect(E1RMChange.text(0.04) == String(localized: "Steady") && E1RMChange.color(0.04) == Theme.textSecondary)
        #expect(E1RMChange.spoken(11.6) == "Up 11.6 kg" && E1RMChange.spoken(-1.5) == "Down 1.5 kg")
        #expect(plain(E1RMChange.overWindow(E1RMChange.text(11.6))) == "▲ 11.6 kg in 90 days")
    }

    @Test func e1rmIsATrainingMetricInStrainBlue() {
        #expect(MetricSpec.e1rm.color == Theme.metricStrain)
    }

    @Test func theHeroIsTheNewestEstimate() {
        let history = MockTrain.exerciseHistory(for: MockTrain.bench.id, sessions: MockTrain.history)
        let vm = ExerciseDetailViewModel(exerciseID: MockTrain.bench.id, history: history,
                                         library: TrainHistoryFixtures.library(), clock: TestClock(now: .now))
        #expect(!vm.isLoading && vm.hasTrend)
        let points = vm.points
        #expect(vm.latest == points.last?.value)
        if let first = points.first?.value, let last = points.last?.value {
            #expect(vm.change == last - first)
            #expect(vm.lastChange == last - points[points.count - 2].value)
        }
        let once = ExerciseDetailViewModel(exerciseID: MockTrain.bench.id,
                                           history: MockTrain.firstTimeHistory(for: MockTrain.bench.id),
                                           library: TrainHistoryFixtures.library(), clock: TestClock(now: .now))
        #expect(!once.hasTrend && once.change == nil && once.lastChange == nil)
        #expect(once.emptyChartText == String(localized: "Log this exercise twice to see a trend."))
    }

    // MARK: in a window

    private func ids(_ w: HostedWindow) -> [String] { w.nodes().compactMap(\.identifier) }

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
            #expect(!weeks.isEmpty && weeks.allSatisfy { $0.traits.contains(.header) && ($0.value ?? "").contains("sessions") })
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
        let library = TrainLibrary(store: TrainStore(inMemory: true), remote: { MockTrainSource(start: .empty) }, restore: false)
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
            #expect((hero.value ?? "").contains("kilograms") && (hero.value ?? "").contains("in 90 days"), "\(hero.value ?? "")")
            #expect(hero.frame.minY - header.frame.maxY >= ExerciseDetailLayout.heroGap - 1)
            let chart = try #require(nodes.first { $0.identifier == "exerciseDetail.chart" })
            #expect(chart.label == "Estimated one-rep max, last 90 days")
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
