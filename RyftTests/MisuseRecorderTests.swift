import Foundation
import Testing
@testable import Ryft

@Suite("Read-model misuse in the tests' host")
@MainActor
struct MisuseRecorderTests {
    /// The app's default finds the tests' recorder (`Misuse.report`): a misuse fails its test instead of the host.
    @Test func theAppsDefaultFindsTheRecorder() {
        #expect(NSClassFromString(Misuse.recorderClassName) is MisuseRecording.Type)
    }

    /// A seed while a write is pending, through a Repository's default `onMisuse`: this test records the issue (as a
    /// known one here), and the host and the other tests go on.
    @Test func aSeedWhileAWriteIsPendingFailsItsTestNotTheHost() async {
        let (repository, hold) = await repositoryWithAHeldWrite()
        withKnownIssue("Repository.seed while read-model writes are pending") {
            repository.seed(.detail(DayDetail(score: DailyScore(day: "2026-10-21", strain: 1), sleep: nil, workouts: [])))
        }
        hold.open()
        await repository.settled()
    }
}
