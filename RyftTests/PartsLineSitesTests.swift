import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// R3: the other "a · b" lines that dangled at the accessibility sizes stand their parts one per line from AX1 (`PartsLine`):
/// the exercise page's, My Day's and the activity detail's subtitles, About you's and the Sleep need sheet's source rows, the
/// body-setting editors' source line, Profile's Bedtime & wake row and the start sheet's option details. Below AX1 each draws
/// what it drew before: its parts joined give that line.
@MainActor
@Suite("R3: more lines stand their parts from AX1")
struct PartsLineSitesTests {
    private let english = Locale(identifier: "en_US")

    /// Friday, November 13 2026, 17:30 here.
    private var friday: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 17, minute: 30)) ?? .now
    }

    @Test("The exercise page: \"Barbell · Quads · Glutes\", the kind and the primary muscles")
    func exerciseSubtitle() {
        let model = ExerciseDetailViewModel(exerciseID: MockTrain.squat.id, history: nil,
                                            library: TrainHistoryFixtures.library(), clock: TestClock(now: friday))
        let squat = MockTrain.squat
        #expect(model.subtitleParts == [squat.kind.title] + squat.primaryMuscles.map(\.title))
        #expect(model.subtitleParts?.count == 3)
        // As the page drew it: the kind and the muscles joined with " · ".
        #expect(model.subtitle == ([squat.kind.title] + squat.primaryMuscles.map(\.title)).joined(separator: " · "))
        #expect(model.subtitle == "Barbell · Quads · Glutes")
    }

    @Test("My Day's header: \"Today · Fri, Nov 13\", \"Yesterday · …\", the date alone")
    func myDaySubtitle() {
        let cases: [(today: Bool, yesterday: Bool, line: String, parts: [String])] = [
            (true, false, "Today · Fri, Nov 13", ["Today", "Fri, Nov 13"]),
            (false, true, "Yesterday · Fri, Nov 13", ["Yesterday", "Fri, Nov 13"]),
            (false, false, "Fri, Nov 13", ["Fri, Nov 13"]),
        ]
        for c in cases {
            let line = MyDayPage.subtitle(friday, isToday: c.today, isYesterday: c.yesterday, locale: english)
            let parts = MyDayPage.subtitleParts(friday, isToday: c.today, isYesterday: c.yesterday, locale: english)
            #expect(line == c.line)
            #expect(parts == c.parts)
            #expect(parts.joined(separator: " · ") == line, "the parts joined are the line below AX1")
        }
    }

    @Test("The activity detail: \"Fri, Nov 13 · 5:00 – 5:40 PM\", the day and the times as one interval")
    func activitySubtitle() throws {
        let clock = TestClock(now: friday)
        let env = AppEnvironment.test(api: MockPlatformAPI(), clock: clock, flags: [.activitiesManual: true])
        let state = AppState(env: env)
        let start = friday.addingTimeInterval(-30 * 60), end = friday.addingTimeInterval(10 * 60)
        let saved = try #require(env.activities.save(manual: ActivityDraft(sport: .running, start: start, end: end)))
        let detail = ActivityDetailViewModel(route: ActivityRoute(id: saved.id, day: start), state: state)
        try #require(detail.activity != nil)

        let parts = detail.subtitleParts(locale: english)
        // What the header drew before R3: the day, " · ", the interval.
        let day = start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(english))
        let times = (start..<end).formatted(Date.IntervalFormatStyle(date: .omitted, time: .shortened, locale: english))
        #expect(parts == [day, times])
        #expect(detail.subtitle(locale: english) == "\(day) · \(times)")
        #expect(day == "Fri, Nov 13")
    }

    @Test("About you's and Profile's source rows: the parts joined are the row's detail, for every source")
    func sourceRows() {
        let cases: [(MaxHRSource, Int?, [String])] = [
            (.estimated, 1990, ["Estimated from your age (born 1990)"]),
            (.manual, 1990, ["Set by you"]),
            (.default, nil, ["Default", "add your birth year for an estimate"]),
        ]
        for (source, year, parts) in cases {
            let editor = editor(MockSleepNeedStates.user(maxHrSource: source, birthYear: year))
            #expect(editor.rowDetailParts(.maxHR) == parts)
            #expect(editor.rowDetailParts(.maxHR)?.joined(separator: " · ") == editor.rowDetail(.maxHR))
        }
        let withDefault = editor(MockSleepNeedStates.user(maxHrSource: .default, birthYear: nil))
        #expect(withDefault.rowDetail(.maxHR) == "Default · add your birth year for an estimate", "the line as before")
        for source in [SleepBaseSource.learned, .manual, .default] {
            let editor = editor(MockSleepNeedStates.user(sleepBaseSource: source))
            #expect(editor.rowDetailParts(.sleepBase)?.joined(separator: " · ") == editor.rowDetail(.sleepBase), "\(source)")
        }
    }

    @Test("The editors' source line: the parts, with \"saved …\" after them while the value isn't saved")
    func editorSourceLine() {
        let editor = editor(MockSleepNeedStates.user(maxHr: 190, maxHrSource: .default, birthYear: nil))
        let unchanged = BodySettingContent(.maxHR, editor: editor, draft: 190)
        #expect(unchanged.sourceParts == ["Default", "add your birth year for an estimate"])
        #expect(unchanged.source == "Default · add your birth year for an estimate")
        #expect(unchanged.spokenSource == unchanged.source)
        let changed = BodySettingContent(.maxHR, editor: editor, draft: 191)
        #expect(changed.sourceParts == ["Default", "add your birth year for an estimate", "saved 190 bpm"])
        #expect(changed.source == "Default · add your birth year for an estimate · saved 190 bpm")
        #expect(changed.spokenSource == "Default · add your birth year for an estimate, saved 190 beats per minute")

        let manual = self.editor(MockSleepNeedStates.user(sleepBaseMin: 450, sleepBaseSource: .manual))
        let base = BodySettingContent(.sleepBase, editor: manual, draft: 465)
        #expect(base.sourceParts == ["Set by you", "saved 7:30"])
        #expect(base.source == "Set by you · saved 7:30")
        #expect(base.spokenSource == "Set by you, saved 7 hours 30 minutes")
    }

    @Test("Sleep need's baseline row and Profile's Bedtime & wake row: their parts joined are the detail")
    func sleepRows() throws {
        let editor = editor(MockSleepNeedStates.user(sleepBaseSource: .learned))
        let learned = SleepNeedSheetContent.BaselineRow(editor: editor)
        let parts = try #require(learned.detailParts)
        #expect(parts.first == "Learned")
        // As the row drew it: the editor's source line.
        #expect(learned.detail == editor.sleepBaseSourceText)
        #expect(parts.joined(separator: " · ") == editor.sleepBaseSourceText)
        let manual = SleepNeedSheetContent.BaselineRow(editor: self.editor(MockSleepNeedStates.user(sleepBaseSource: .manual)))
        #expect(manual.detailParts == ["Set by you"] && manual.detail == "Set by you")

        var schedule = SleepSchedule.default
        #expect(BedtimePlanner.summaryDetailParts(schedule) == [SleepSchedule.Goal.peak.title])
        schedule.reminderOn = true
        schedule.alarmOn = true
        let all = try #require(BedtimePlanner.summaryDetailParts(schedule))
        #expect(all.count == 3)
        #expect(all.joined(separator: " · ") == "\(SleepSchedule.Goal.peak.title) · reminder · alarm")
        #expect(BedtimePlanner.summaryDetailParts(nil) == nil)
    }

    @Test("The start sheet's details: \"Upper A · 5 exercises · ~55 min\", the last session, the plan's days")
    func startOptions() throws {
        let today = try #require(TrainPreview.library.today)
        let parts = StartOptionText.todayParts(today)
        #expect(parts.count == 3 && parts[0] == today.day.name)
        // As the sheet drew it: the day's name, then the exercises and the minutes.
        #expect(StartOptionText.line(parts) == "\(today.day.name) · \(TodayPlanText.detail(today))")
        #expect(TodayPlanText.detail(today)
            == "\(today.day.exercises.count) exercises · ~\(SessionEstimate.minutes(for: today.day.exercises)) min")

        let last = TrainSession(title: "Upper A", startedAt: friday.addingTimeInterval(-86_400), endedAt: friday,
                                status: .completed, exercises: [])
        #expect(StartOptionText.line(StartOptionText.lastParts(last, now: friday)) == "Upper A · Yesterday")
        let plan = MockTrain.upperLower
        #expect(StartOptionText.line(StartOptionText.planParts(plan)) == plan.days.map(\.name).joined(separator: " · "))
        #expect(StartOptionText.planParts(plan).count == plan.days.count)
    }

    private func editor(_ user: User) -> BodySettingsEditor {
        let state = AppState(env: .test(api: MockPlatformAPI(), online: true))
        state.user = user
        return BodySettingsEditor(state: state)
    }
}

/// R3: one site in a window at AX3: the exercise page's subtitle stands one part per line under the title, from the leading
/// inset, while VoiceOver still hears the line as the page wrote it.
@MainActor
@Suite("R3: the exercise page's subtitle at AX3", .serialized)
struct PartsLineSitesHostedTests {
    /// The size `text` takes on one line at AX3 in `font`.
    private func lineSize(_ text: String, _ font: Font) -> CGSize {
        let view = Text(verbatim: text).font(font).monospacedDigit().fixedSize()
            .environment(\.dynamicTypeSize, .accessibility3)
        return UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 10_000, height: 10_000))
    }

    @Test("At AX3 \"Barbell\", \"Quads\", \"Glutes\" one per line under \"Back squat\"; VoiceOver hears \"Barbell · Quads · Glutes\"")
    func exerciseSubtitleAtAX3() async throws {
        let view = NavigationStack { ExerciseDetailView(exerciseID: MockTrain.squat.id) }
            .environment(TrainHistoryFixtures.library())
        try await HostedWindow.run(width: 390, height: 1_400, bottomInset: 0, typeSize: .accessibility3,
                                   category: .accessibilityExtraLarge, view) { w in
            try await w.wait("the header") { w.nodes().contains { $0.identifier == "exerciseDetail.header" } }
            try await w.settle()
            let header = try #require(w.nodes().first { $0.identifier == "exerciseDetail.header" })
            #expect(header.label == MockTrain.squat.name)
            #expect(header.value == "Barbell · Quads · Glutes", "VoiceOver as before: \(header.value ?? "nil")")

            let parts = ["Barbell", "Quads", "Glutes"]
            let title = lineSize(MockTrain.squat.name, .ryft(.callout))
            let widest = parts.map { lineSize($0, .ryft(.caption)).width }.max() ?? 0
            let line = lineSize(parts[0], .ryft(.caption)).height
            #expect(header.frame.minX < 40, "stacked, from the leading inset: \(header.frame)")
            // Under the title: the subtitle's ink, from the window's edge to the other.
            let below = CGRect(x: 0, y: header.frame.minY + title.height + 1, width: 390,
                               height: header.frame.maxY - header.frame.minY - title.height - 1)
            let pixels = try WindowPixels(w, scale: 2)
            let paper = pixels.at(2, below.midY)
            let ink = try #require(pixels.box(in: below) { abs($0.r - paper.r) + abs($0.g - paper.g) + abs($0.b - paper.b) > 0.3 },
                                   "the subtitle under \(header.frame)")
            #expect(ink.width <= widest + 2, "one part per line: ink \(ink.width) wide, the widest part \(widest)")
            #expect(ink.height >= 2.4 * line, "three lines: ink \(ink.height) tall, a line \(line)")
            #expect(ink.minX >= header.frame.minX - 1, "from the header's leading edge: \(ink) in \(header.frame)")
        }
    }
}
