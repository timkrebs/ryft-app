import Foundation
import Testing
@testable import Ryft

@MainActor
struct StrainBreakdownTests {
    private func model(score strain: Double, trimp: Int, muscular: Int?) -> StrainViewModel {
        let state = AppState(env: .test())
        let day = DayFormat.string(from: state.env.clock.now())
        state.repository.store(detail: DayDetail(score: DailyScore(day: day, strain: strain), sleep: nil,
                                                 strain: DayStrain(trimp: trimp, hrMin: 600, zoneMin: [0, 0, 0, 0, 0],
                                                                   muscularTrimp: muscular),
                                                 workouts: []))
        return StrainViewModel(state: state, store: TrainStore(inMemory: true))
    }

    @Test func theDaysStrainSplitsByLoad() throws {
        let vm = model(score: 13.3, trimp: 99, muscular: 44)
        let split = try #require(vm.strainSplit)
        #expect(split.strength == 4.1 && split.cardio == 9.2)
        #expect(vm.strainSplitText == String(localized: "Cardio \(Fmt.strain(9.2)) · Strength \(Fmt.strain(4.1))"))
    }

    @Test func noSessionNoSplit() {
        #expect(model(score: 12.4, trimp: 99, muscular: 0).strainSplit == nil)
        #expect(model(score: 12.4, trimp: 99, muscular: nil).strainSplit == nil)
    }
}

struct RecordWordingTests {
    /// The same words as the PR_BODY_* push keys.
    @Test func recordsReadLikeTheirPush() {
        #expect(PRKind.e1rm.sentence(102.5).hasPrefix("Estimated one-rep max"))
        #expect(PRKind.maxWeight.sentence(100).contains("heaviest set yet"))
        #expect(PRKind.maxReps.sentence(12) == "12 reps in one set, your most yet.")
        #expect(PRKind.maxVolume.sentence(1250).contains("reps × kg"))
    }
}
