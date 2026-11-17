// Sleep's previews (Nocturne, docs/work/2026-11-16-nocturne/design.md §P4-10): dark only, each state at the default size
// and at AX3. The nights are the board's night from `MockData` (T4.0) and the variants the states need, built here so
// `MockData` stays as Today needs it. The shots and hosted tests use the same scenes.
import SwiftUI

/// One state of Sleep → Day as values: the header, the board and the night under it.
struct SleepPreviewScene {
    enum Night: String, CaseIterable {
        case latest, thin, oldest, older, loading, failed, noSleep, pending, noStages, noTimeline, noNeed, reduceTransparency
        /// Pending with `sleep: null` (the API's placeholder day): Apple Health's raw night; and without one either.
        case pendingRaw, pendingEmpty
    }

    /// Apple Health's night for `pendingRaw`: 7:17 asleep, woken at 06:52 (Today's pending scenario's night).
    static func rawNight(today: Date) -> RawNight {
        let wake = today.addingTimeInterval(6 * 3_600 + 52 * 60)
        return RawNight(asleepMin: 437, bedtime: wake.addingTimeInterval(-8 * 3_600 + 25 * 60), wake: wake,
                        source: "Garmin Connect")
    }

    let night: Night
    let date: Date
    let header: SleepHeaderContent
    let board: SleepBoard
    let sleep: SleepDetail?
    let score: DailyScore?

    /// Days back: an older night with a need, and `MockData.BoardWeek`'s night scored without one (its `nil` share, week
    /// index 2 of offsets 6 … 0).
    static let olderNight = 2, noNeedNight = 4

    var numeralStyle: DotNumeral.Style { night == .thin ? .light : .dots }
    var reduceTransparency: Bool? { night == .reduceTransparency ? true : nil }

    init(_ night: Night) {
        let today = Calendar.current.startOfDay(for: .now)
        var date = today
        var detail: DayDetail? = MockData.todayDetail
        var isLoading = false, error: String?
        var rawNight: RawNight?
        switch night {
        case .latest, .thin, .reduceTransparency:
            break
        case .older:
            date = DayFormat.shift(today, days: -Self.olderNight)
            detail = MockData.detail(for: date)
        case .oldest:
            date = DayFormat.shift(today, days: -(MockData.historyDays - 1))
            detail = MockData.detail(for: date)
        case .noNeed:
            // MockData's night without a need (BoardWeek): no zone, no middle label, "Asleep" alone.
            date = DayFormat.shift(today, days: -Self.noNeedNight)
            detail = MockData.detail(for: date)
        case .loading:
            detail = nil
            isLoading = true
        case .failed:
            detail = nil
            // What `SleepViewModel.load()` keeps when the request fails offline and nothing is cached.
            error = APIError.transport(URLError(.notConnectedToInternet)).localizedDescription
        case .noSleep:
            detail?.sleep = nil
        case .pending:
            // The raw night is in, the score isn't.
            detail?.score = DailyScore(day: DayFormat.string(from: today), sleepActualMin: 468, scoringState: .pending)
        case .pendingRaw, .pendingEmpty:
            // What `GET /v1/days/{day}` answers while the night is scored: the placeholder score, `sleep: null`.
            detail = DayDetail(score: DailyScore(day: DayFormat.string(from: today), scoringState: .pending), sleep: nil,
                               workouts: [])
            rawNight = night == .pendingRaw ? Self.rawNight(today: today) : nil
        case .noStages:
            detail?.sleep?.stages = []
            detail?.sleep?.hasStages = false
            detail?.sleep?.segments = []
        case .noTimeline:
            detail?.sleep?.segments = []
        }
        let score = detail?.score
        let marker = DayMarker.kind(for: score)
        let week = (0..<SleepBoard.weekNights).reversed().map { back in
            Self.score(DayFormat.shift(date, days: -back))?.sleepConsistency
        }
        self.night = night
        self.date = date
        header = SleepHeaderContent(mode: .day, night: date, today: today, marker: marker,
                                    canStepBack: night != .oldest, canStepForward: date < today)
        board = SleepBoard(sleep: detail?.sleep, score: score,
                           previousDebt: Self.score(DayFormat.shift(date, days: -1))?.sleepDebtMin,
                           weekConsistency: week, isPending: marker == .pending, isLoading: isLoading, error: error,
                           rawNight: rawNight)
        sleep = detail?.sleep
        self.score = score
    }

    private static func score(_ date: Date) -> DailyScore? {
        let day = DayFormat.string(from: date)
        return MockData.history.first { $0.day == day }
    }
}

/// Sleep → Day for a scene, as `SleepView` lays it out.
struct SleepPreviewPage: View {
    let scene: SleepPreviewScene

    init(_ night: SleepPreviewScene.Night) {
        scene = SleepPreviewScene(night)
    }

    var body: some View {
        NavigationStack {
            SleepPage(header: scene.header, mode: .constant(.day), modes: SleepMode.allCases, step: { _ in }) {
                SleepDay(board: scene.board, sleep: scene.sleep, score: scene.score, night: scene.date,
                         numeralStyle: scene.numeralStyle, reduceTransparency: scene.reduceTransparency,
                         retry: scene.night == .failed ? {} : nil)
            }
        }
    }
}

/// The real screen in another mode (Week, Month, Bedtime keep their content under the header and the picker).
private struct SleepModePreview: View {
    let mode: SleepMode
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        SleepView().onAppear { screens.sleep.mode = mode }
    }
}

private extension View {
    func ax3() -> some View { environment(\.dynamicTypeSize, .accessibility3) }
}

#Preview("Sleep · scored") { SleepView().previewEnvironment() }
#Preview("Sleep · scored · AX3") { SleepView().previewEnvironment().ax3() }
#Preview("Sleep · thin digits") { SleepPreviewPage(.thin).previewEnvironment() }
#Preview("Sleep · thin digits · AX3") { SleepPreviewPage(.thin).previewEnvironment().ax3() }
#Preview("Sleep · latest night") { SleepPreviewPage(.latest).previewEnvironment() }
#Preview("Sleep · latest night · AX3") { SleepPreviewPage(.latest).previewEnvironment().ax3() }
#Preview("Sleep · oldest night") { SleepPreviewPage(.oldest).previewEnvironment() }
#Preview("Sleep · oldest night · AX3") { SleepPreviewPage(.oldest).previewEnvironment().ax3() }
#Preview("Sleep · an older night") { SleepPreviewPage(.older).previewEnvironment() }
#Preview("Sleep · an older night · AX3") { SleepPreviewPage(.older).previewEnvironment().ax3() }
#Preview("Sleep · loading") { SleepPreviewPage(.loading).previewEnvironment() }
#Preview("Sleep · loading · AX3") { SleepPreviewPage(.loading).previewEnvironment().ax3() }
#Preview("Sleep · load error") { SleepPreviewPage(.failed).previewEnvironment() }
#Preview("Sleep · load error · AX3") { SleepPreviewPage(.failed).previewEnvironment().ax3() }
#Preview("Sleep · no sleep") { SleepPreviewPage(.noSleep).previewEnvironment() }
#Preview("Sleep · no sleep · AX3") { SleepPreviewPage(.noSleep).previewEnvironment().ax3() }
#Preview("Sleep · pending score") { SleepPreviewPage(.pending).previewEnvironment() }
#Preview("Sleep · pending score · AX3") { SleepPreviewPage(.pending).previewEnvironment().ax3() }
#Preview("Sleep · pending, Apple Health's night") { SleepPreviewPage(.pendingRaw).previewEnvironment() }
#Preview("Sleep · pending, Apple Health's night · AX3") { SleepPreviewPage(.pendingRaw).previewEnvironment().ax3() }
#Preview("Sleep · pending, no night yet") { SleepPreviewPage(.pendingEmpty).previewEnvironment() }
#Preview("Sleep · pending, no night yet · AX3") { SleepPreviewPage(.pendingEmpty).previewEnvironment().ax3() }
#Preview("Sleep · no stages") { SleepPreviewPage(.noStages).previewEnvironment() }
#Preview("Sleep · no stages · AX3") { SleepPreviewPage(.noStages).previewEnvironment().ax3() }
#Preview("Sleep · no timeline") { SleepPreviewPage(.noTimeline).previewEnvironment() }
#Preview("Sleep · no timeline · AX3") { SleepPreviewPage(.noTimeline).previewEnvironment().ax3() }
#Preview("Sleep · no need") { SleepPreviewPage(.noNeed).previewEnvironment() }
#Preview("Sleep · no need · AX3") { SleepPreviewPage(.noNeed).previewEnvironment().ax3() }
#Preview("Sleep · Reduce Transparency") { SleepPreviewPage(.reduceTransparency).previewEnvironment() }
#Preview("Sleep · Reduce Transparency · AX3") { SleepPreviewPage(.reduceTransparency).previewEnvironment().ax3() }

#Preview("Sleep · with a nap") {
    // The board's night had a nap: the chip and its line open the details card.
    ScrollView {
        SleepNightCards(sleep: MockData.todayDetail.sleep ?? SleepDetail(), score: MockData.todayScore)
            .padding(20)
    }
    .background(Theme.background)
    .previewEnvironment()
}

#Preview("Sleep · with a nap · AX3") {
    ScrollView {
        SleepNightCards(sleep: MockData.todayDetail.sleep ?? SleepDetail(), score: MockData.todayScore)
            .padding(20)
    }
    .background(Theme.background)
    .previewEnvironment()
    .ax3()
}

#Preview("Sleep · Week") { SleepModePreview(mode: .week).previewEnvironment() }
#Preview("Sleep · Week · AX3") { SleepModePreview(mode: .week).previewEnvironment().ax3() }
#Preview("Sleep · Month") { SleepModePreview(mode: .month).previewEnvironment() }
#Preview("Sleep · Month · AX3") { SleepModePreview(mode: .month).previewEnvironment().ax3() }
#Preview("Sleep · Bedtime") { SleepModePreview(mode: .plan).previewEnvironment() }
#Preview("Sleep · Bedtime · AX3") { SleepModePreview(mode: .plan).previewEnvironment().ax3() }

#Preview("Sleep need") {
    let state = AppState.preview()
    SleepNeedSheet(need: MockData.todayDetail.sleep?.need, total: "8h 18m", editor: BodySettingsEditor(state: state))
        .previewEnvironment(state)
}

#Preview("Sleep need · no breakdown · AX3") {
    let state = AppState.preview()
    SleepNeedSheet(need: nil, total: "8h 10m", editor: BodySettingsEditor(state: state))
        .previewEnvironment(state)
        .ax3()
}
