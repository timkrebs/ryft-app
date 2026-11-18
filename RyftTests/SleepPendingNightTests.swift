import Foundation
import Testing
@testable import Ryft

// CR1: Sleep → Day on a night that is being scored. `GET /v1/days/{day}` answers 200 with the placeholder score
// (`scoring_state: "pending"`) and `sleep: null`; Sleep showed "No sleep recorded for this night." Per design.md §P4-5
// "Pending score" it shows the numeral and the ruler from Apple Health's raw night (the one Today shows), labelled
// unscored, with the outline hypnogram and tiles, and never claims there was no sleep.

private let enUS = Locale(identifier: "en_US")

@MainActor
struct SleepPendingNightTests {
    private let now = Date(timeIntervalSince1970: 1_794_906_000) // 2026-11-17 10:00 in Berlin; any morning does
    private var today: Date { Calendar.current.startOfDay(for: now) }

    /// The API's placeholder day as it comes over the wire (API.md, `GET /v1/days/{day}`), decoded as the client does.
    private func placeholderDay() throws -> DayDetail {
        let day = DayFormat.string(from: today)
        let json = #"{"score":{"day":"\#(day)","state":"calibrating","baseline_days":0,"calibrating":false,"#
            + #""computed_at":"0001-01-01T00:00:00Z","scoring_state":"pending","coverage":null},"#
            + #""sleep":null,"strain":null,"workouts":[]}"#
        return try APIClient.jsonDecoder.decode(DayDetail.self, from: Data(json.utf8))
    }

    /// Last night in Apple Health: 7:17 asleep, woken at 06:52 this morning.
    private func rawNight(wakeDaysBack: Int = 0) -> RawNight {
        let wake = DayFormat.shift(today, days: -wakeDaysBack).addingTimeInterval(6 * 3_600 + 52 * 60)
        return RawNight(asleepMin: 437, bedtime: wake.addingTimeInterval(-8 * 3_600 + 25 * 60), wake: wake, source: "Connect")
    }

    private func model(raw: RawNight?) throws -> SleepViewModel {
        let state = AppState(env: .test(clock: TestClock(now: now)))
        state.today = try placeholderDay()
        state.lastNight = raw
        let vm = SleepViewModel(state: state)
        vm.mode = .day
        return vm
    }

    // MARK: the board

    @Test func thePlaceholderDayWithAppleHealthsNightShowsItUnscored() throws {
        let detail = try placeholderDay()
        #expect(detail.sleep == nil && DayMarker.kind(for: detail.score) == .pending, "the API's placeholder")
        let board = SleepBoard(sleep: nil, score: detail.score, scoring: .scoring, rawNight: rawNight(), locale: enUS)
        #expect(board.look == .pending && board.isOutline)
        #expect(board.clock == "7:17")
        #expect(board.numeralLabel == "\(Fmt.spokenDuration(minutes: 437, locale: enUS)) asleep")
        #expect(board.caption == "From Apple Health · not scored yet")
        #expect(board.spokenCaption == "Last night, from Apple Health, not scored yet")
        #expect(board.ruler.value == 437.0 / 60 && board.ruler.zone == nil, "the needle at the raw total, no need yet")
        #expect(board.hypnogram == nil && board.tiles.map(\.value) == ["–", "–", "–", "–"])
    }

    @Test func withoutAppleHealthsNightItSaysTheNightIsBeingScored() throws {
        let board = SleepBoard(sleep: nil, score: try placeholderDay().score, scoring: .scoring, locale: enUS)
        #expect(board.look == .pending && board.isOutline)
        #expect(board.clock == nil && board.numeralLabel == nil && board.ruler.value == nil)
        #expect(board.caption == "Your night is being scored." && board.spokenCaption == board.caption)
    }

    /// A day with a score and no night still says so; loading and a failed load come before pending.
    @Test func noSleepLoadingAndFailedAreUnchanged() {
        #expect(SleepBoard(sleep: nil, score: DailyScore(day: "2026-11-16"), rawNight: rawNight(), locale: enUS).look == .noSleep)
        #expect(SleepBoard(sleep: nil, score: nil, scoring: .scoring, isLoading: true, rawNight: rawNight(), locale: enUS).look == .loading)
        #expect(SleepBoard(sleep: nil, score: nil, scoring: .scoring, error: "x", rawNight: rawNight(), locale: enUS).look == .failed("x"))
    }

    // MARK: the model

    @Test func sleepShowsTheNightTodayShows() throws {
        let vm = try model(raw: rawNight())
        #expect(vm.marker == .pending)
        let board = vm.board
        #expect(board.look == .pending && board.clock == "7:17")
        #expect(!board.caption.contains("No sleep") && board.caption.contains("not scored yet"))
        // The step announcement follows: the night, unscored, then its time asleep.
        #expect(vm.stepAnnouncement == "\(vm.header.spokenSubtitle), not scored yet. \(board.numeralLabel ?? "")",
                "\(vm.stepAnnouncement)")
        #expect(!vm.stepAnnouncement.contains("No sleep"))
    }

    @Test func withoutARawNightTheModelSaysItIsBeingScored() throws {
        let vm = try model(raw: nil)
        #expect(vm.board.look == .pending && vm.board.clock == nil)
        #expect(vm.stepAnnouncement.hasSuffix(", not scored yet. Your night is being scored."), "\(vm.stepAnnouncement)")
    }

    /// Apple Health's night is last night's: an older one (woken yesterday) isn't shown as this night's.
    @Test func aRawNightFromAnotherMorningIsNotThisNights() throws {
        let vm = try model(raw: rawNight(wakeDaysBack: 1))
        #expect(vm.rawNight == nil && vm.board.clock == nil && vm.board.look == .pending)
    }
}

/// The same in a window: the preview scenes the shots use (`SleepPreviewScene.Night.pendingRaw`, `.pendingEmpty`).
@MainActor
@Suite(.serialized) struct SleepPendingNightHostedTests {
    @Test func thePageNeverSaysThereWasNoSleep() async throws {
        for night in [SleepPreviewScene.Night.pendingRaw, .pendingEmpty] {
            try await HostedWindow.run(width: 390, height: 1400, bottomInset: 0, SleepPreviewPage(night)) { w in
                try await w.wait("Sleep's tiles") { w.nodes().contains { $0.identifier == "sleep.tile.restorative" } }
                try await w.settle()
                let nodes = w.nodes()
                #expect(!nodes.contains { $0.label.contains("No sleep recorded") }, "\(night)")
                #expect(!nodes.contains { $0.identifier == "sleep.hypnogram" }, "the outline, not a night's hypnogram")
                let header = try #require(nodes.first { $0.label == "Sleep" && $0.traits.contains(.header) })
                #expect(header.value?.hasSuffix("not scored yet") == true, "\(header.value ?? "")")
                if night == .pendingRaw {
                    let numeral = try #require(nodes.first { $0.identifier == "sleep.numeral" })
                    #expect(numeral.label == "\(Fmt.spokenDuration(minutes: 437)) asleep")
                    #expect(nodes.contains { $0.label == "Last night, from Apple Health, not scored yet" })
                } else {
                    #expect(nodes.contains { $0.label == "Your night is being scored." })
                }
            }
        }
    }
}
