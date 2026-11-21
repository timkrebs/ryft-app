import Foundation
import Testing
@testable import Ryft

/// PR 6's R4 re-checks, follow-up F1 item 2: My Day's `forget()` (the switch's account-state forgetter) ends the loads
/// still out. A's late day failure would otherwise put A's day and request ID back after the forget, and B's first Today
/// frame would show the card failed with A's Details. Synthetic data only.
@MainActor
@Suite("F1 item 2: My Day's forget ends the loads still out", .serialized)
struct MyDayForgetGenerationTests {
    @Test func aLateFailureAfterTheForgetWritesNothing() async {
        let api = MockPlatformAPI()
        // The day's detail fails with A's request ID; the activities answer.
        api.faults["day"] = FaultInjection.Rule(.status(400, retryAfter: nil))
        let env = AppEnvironment.test(api: api, clock: TestClock(now: .now), flags: [.todayMyDay: true])
        defer { withExtendedLifetime(env) {} }
        let vm = MyDayViewModel(state: AppState(env: env), store: TrainStore(inMemory: true))
        let key = DayFormat.string(from: vm.today)
        let details = "HTTP 400 · Request ID fault-day"

        // With no switch, the failure is the day's, with its Details.
        await vm.load(vm.today)
        #expect(vm.failed == [key] && vm.failedDetails == [key: details])
        vm.forget()
        #expect(vm.failed.isEmpty && vm.failedDetails.isEmpty)

        // A's load again, its activities held: the switch forgets My Day, then the activities answer.
        let hold = Gate()
        api.activitySource.beforeList = { await hold.wait() }
        let late = Task { await vm.load(vm.today, force: true) }
        #expect(await eventually { api.count("day") == 2 && api.count("activities") == 2 }, "A's day is out, its activities held")
        vm.forget()
        await hold.open()
        await late.value
        #expect(vm.failed.isEmpty, "\(vm.failed)")
        #expect(vm.failedDetails.isEmpty, "\(vm.failedDetails)")
        #expect(vm.card.phase != .failed && vm.card.failedDetails == nil)
    }
}
