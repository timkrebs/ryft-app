import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes Bedtime & wake and Tonight (Nocturne PR 6 C §4.13, drafts c-21 … c-22c) as 3x PNGs, whole pages
/// (`PagedWindowShot`), at the default size and at AX3, when `BEDTIME_SHOTS_DIR` is set; otherwise does nothing. Run it with
/// `TEST_RUNNER_BEDTIME_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/BedtimeShotsTests test-without-building`, before
/// and after a change, and compare. Drawn from a real window; for comparing, not a golden-file test. Synthetic data only,
/// US English, on the test clock at 5:42 PM.
@MainActor
@Suite("C4: Bedtime & wake and Tonight, shots", .serialized)
struct BedtimeShotsTests {
    @Test(arguments: Self.names)
    func writeScreen(_ name: String) async throws {
        guard let dir = ProcessInfo.processInfo.environment["BEDTIME_SHOTS_DIR"] else { return }
        for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                           ("ax3", .accessibility3, .accessibilityExtraLarge)] {
            let screen = await BedtimeShotScreen.screen(name)
            try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: typeSize, category: category,
                                       screen.view) { w in
                try await w.settle()
                if let interact = screen.interact {
                    try await interact(w)
                    try await w.settle()
                }
                let image = try await PagedWindowShot.image(w)
                try #require(image.pngData()).write(to: URL(fileURLWithPath: "\(dir)/c4-\(name)-\(size).png"))
            }
        }
    }

    nonisolated static let names = [
        "tonight", "tonight-not-set-up", "tonight-loading", "tonight-offline-cached", "tonight-offline", "tonight-failed",
        "bedtime-wake", "bedtime-wake-days", "bedtime-wake-refused", "bedtime-wake-alarm-problem",
    ]
}

/// Tonight and Bedtime & wake in one state each, on a test environment of their own (a fresh schedule store, the test
/// clock at 5:42 PM, the mock platform), as Today and Profile show them.
@MainActor
enum BedtimeShotScreen {
    struct Screen {
        let view: AnyView
        /// What a person does before the shot (a switch iOS refuses).
        var interact: ((HostedWindow) async throws -> Void)?
    }

    /// A test environment with Bedtime & wake's flag on, the clock at 5:42 PM local on its day.
    static func state(online: Bool = true, signedIn: Bool = true, api: MockPlatformAPI = MockPlatformAPI())
        -> (AppState, TestClock) {
        let clock = TestClock()
        clock.set(Calendar.current.date(bySettingHour: 17, minute: 42, second: 0, of: clock.now()) ?? clock.now())
        let auth: AuthService? = signedIn ? nil : .preview(signedIn: false)
        let state = AppState(env: .test(api: api, clock: clock, auth: auth, flags: [.sleepPlanner: true], online: online))
        state.user = MockData.user
        return (state, clock)
    }

    static func screen(_ name: String) async -> Screen {
        switch name {
        case "tonight":
            let (state, _) = state()
            let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
            await planner.update(.default)
            return Screen(view: tonight(state, planner))
        case "tonight-not-set-up":
            let (state, _) = state()
            return Screen(view: tonight(state, BedtimePlanner(state: state, alarms: MockWakeAlarms())))
        case "tonight-loading":
            // Nothing to plan with (signed out): the schedule is there, no plan and no failure yet.
            let (state, _) = state(signedIn: false)
            SleepSchedule.default.save(account: state.env.auth.accountID, defaults: state.env.defaults)
            return Screen(view: tonight(state, BedtimePlanner(state: state, alarms: MockWakeAlarms())))
        case "tonight-offline-cached":
            let (state, clock) = state()
            await BedtimePlanner(state: state, alarms: MockWakeAlarms()).update(.default)
            clock.advance(by: .seconds(3_600))
            (state.env.connectivity as? ConnectivityMonitor)?.update(false)
            let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
            await planner.refresh()
            return Screen(view: tonight(state, planner))
        case "tonight-offline":
            let (state, _) = state(online: false)
            let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
            await planner.update(.default)
            return Screen(view: tonight(state, planner))
        case "tonight-failed":
            let api = MockPlatformAPI()
            api.failure = APIError.http(503, "", requestID: "01JD8K2V9Q7M3X")
            let (state, _) = state(api: api)
            let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
            await planner.update(.default)
            return Screen(view: tonight(state, planner))
        case "bedtime-wake-days":
            let (state, _) = state()
            var schedule = SleepSchedule.default
            schedule.sameOnWeekdays = false
            schedule.wake[4] = "07:15"
            let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
            await planner.update(schedule)
            return Screen(view: SubpageShotScreen.pushed(state) { SleepScheduleView(planner: planner) })
        case "bedtime-wake-refused":
            let (state, _) = state()
            let alarms = MockWakeAlarms()
            alarms.allows = false
            let planner = BedtimePlanner(state: state, alarms: alarms)
            var schedule = SleepSchedule.default
            schedule.reminderOn = true
            await planner.update(schedule)
            return Screen(view: SubpageShotScreen.pushed(state) { SleepScheduleView(planner: planner) }) { w in
                try await w.wait("the alarm switch") { w.node("Wake me at my wake time") != nil }
                _ = w.node("Wake me at my wake time")?.activate()
                try await w.wait("the refusal") { w.node("Not allowed in iOS Settings.") != nil }
            }
        case "bedtime-wake-alarm-problem":
            let (state, _) = state()
            var schedule = SleepSchedule.default
            schedule.alarmOn = true
            schedule.save(account: state.env.auth.accountID, defaults: state.env.defaults)
            let alarms = MockWakeAlarms()
            alarms.allowed = false
            let planner = BedtimePlanner(state: state, alarms: alarms)
            await planner.refresh()
            return Screen(view: SubpageShotScreen.pushed(state) { SleepScheduleView(planner: planner) })
        default:
            let (state, _) = state()
            let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
            var schedule = SleepSchedule.default
            schedule.reminderOn = true
            await planner.update(schedule)
            return Screen(view: SubpageShotScreen.pushed(state) { SleepScheduleView(planner: planner) })
        }
    }

    /// Tonight as Today shows it: a card in the scrolling page, 20 from the sides.
    static func tonight(_ state: AppState, _ planner: BedtimePlanner) -> AnyView {
        AnyView(NavigationStack {
            ScrollView {
                TonightCard(planner: planner)
                    .padding(.horizontal, Theme.Metrics.screenPadding)
                    .padding(.vertical, 16)
            }
            .background(Theme.background.ignoresSafeArea())
        }
        .previewEnvironment(state)
        .toggleStyle(.ryft)
        .environment(\.locale, Locale(identifier: "en_US")))
    }
}
