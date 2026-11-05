import Foundation
import Testing
@testable import Ryft

/// The Focused table's fourth column on its own: the cycle, the default rule, the cell and what VoiceOver says. Synthetic
/// values only (75 × 10, 80 × 6).
@Suite("Fourth column")
struct SetColumnTests {
    // MARK: the cycle

    @Test func theCycleIsE1RMTenRMRPEAndAround() {
        #expect(SetColumn.e1rm.next == .tenRM)
        #expect(SetColumn.tenRM.next == .rpe)
        #expect(SetColumn.rpe.next == .e1rm)
    }

    @Test func theHeadersReadE1RMTenRMAndRPE() {
        #expect(SetColumn.e1rm.title == "E1RM")
        #expect(SetColumn.tenRM.title == "10RM")
        #expect(SetColumn.rpe.title == "RPE")
    }

    @Test func theStoredValuesStay() {
        // Written to UserDefaults: renaming a case would lose every user's choice.
        #expect(SetColumn.allCases.map(\.rawValue) == ["e1rm", "10rm", "rpe"])
    }

    // MARK: the default

    @Test func theDefaultIsE1RM() {
        #expect(SetColumn.shown(chosen: nil, loadType: .weight, targetKind: .kg, sessionHasRPE: false) == .e1rm)
        #expect(SetColumn.shown(chosen: nil, loadType: .weight, targetKind: nil, sessionHasRPE: false) == .e1rm)
    }

    @Test func anRPETargetShowsRPE() {
        #expect(SetColumn.shown(chosen: nil, loadType: .weight, targetKind: .rpe, sessionHasRPE: false) == .rpe)
    }

    @Test func anRPEInTheSessionShowsRPE() {
        #expect(SetColumn.shown(chosen: nil, loadType: .weight, targetKind: .kg, sessionHasRPE: true) == .rpe)
    }

    @Test("A choice stands over the default rule", arguments: SetColumn.allCases)
    func aChoiceStands(_ chosen: SetColumn) {
        #expect(SetColumn.shown(chosen: chosen, loadType: .weight, targetKind: .rpe, sessionHasRPE: true) == chosen)
    }

    @Test("Every load type's column", arguments: [
        (loadType: LoadType.weight, offered: true), (.bodyweight, true), (.time, false), (.distance, false),
    ])
    func loadTypes(_ type: (loadType: LoadType, offered: Bool)) {
        #expect(SetColumn.offersEstimates(for: type.loadType) == type.offered)
        for chosen in [SetColumn?.none] + SetColumn.allCases.map(Optional.some) {
            let shown = SetColumn.shown(chosen: chosen, loadType: type.loadType, targetKind: .kg, sessionHasRPE: false)
            #expect(shown == (type.offered ? chosen ?? .e1rm : .rpe), "\(type.loadType) with \(String(describing: chosen))")
        }
    }

    // MARK: the cell

    @Test("The pinned sets on screen", arguments: [
        (kg: 80.0, reps: 6, e1rm: "96", tenRM: "72"), (75.0, 10, "100", "75"),
    ])
    func pinnedSets(_ pin: (kg: Double, reps: Int, e1rm: String, tenRM: String)) {
        #expect(SetColumn.e1rm.text(weightKg: pin.kg, reps: pin.reps, rpe: nil) == pin.e1rm)
        #expect(SetColumn.tenRM.text(weightKg: pin.kg, reps: pin.reps, rpe: nil) == pin.tenRM)
    }

    @Test func fifteenRepsReadAsTwelve() {
        #expect(SetColumn.e1rm.text(weightKg: 60, reps: 15, rpe: nil) == "84")
        #expect(SetColumn.tenRM.text(weightKg: 60, reps: 15, rpe: nil) == "63")
    }

    @Test func theCellRoundsToHalfAKilo() {
        // 100 × 5 = 116.67 → 116.5. 77.5 × 3 = 85.25 → 85.5 on the half-up tie; its 10RM 63.94 → 64.
        #expect(SetColumn.e1rm.text(weightKg: 100, reps: 5, rpe: nil) == Fmt.kgNumber(116.5))
        #expect(SetColumn.e1rm.text(weightKg: 77.5, reps: 3, rpe: nil) == Fmt.kgNumber(85.5))
        #expect(SetColumn.tenRM.text(weightKg: 77.5, reps: 3, rpe: nil) == "64")
    }

    @Test func theTenRMIsRoundedOnceFromTheExactEstimate() {
        // 50.2 × 10: the exact e1RM 66.93 gives 50.2, shown as 50. From the e1RM on screen, 67, it would be 50.25 → 50.5.
        #expect(SetColumn.tenRM.text(weightKg: 50.2, reps: 10, rpe: nil) == "50")
    }

    @Test("No estimate is a dash", arguments: [
        (kg: Double?.none, reps: Int?.some(8)), // bodyweight, or an assisted set: its load isn't in weightKg
        (0, 8), // the wire's other "no added load"
        (nil, nil),
        (80, nil),
        (80, 0),
        (-20, 8),
    ])
    func noEstimate(_ set: (kg: Double?, reps: Int?)) {
        #expect(SetColumn.e1rm.text(weightKg: set.kg, reps: set.reps, rpe: nil) == Fmt.placeholder)
        #expect(SetColumn.tenRM.text(weightKg: set.kg, reps: set.reps, rpe: nil) == Fmt.placeholder)
        #expect(SetColumn.e1rm.spoken(weightKg: set.kg, reps: set.reps, rpe: nil) == nil)
        #expect(SetColumn.tenRM.spoken(weightKg: set.kg, reps: set.reps, rpe: nil) == nil)
    }

    @Test func addedLoadIsAllABodyweightEstimateCounts() {
        // +10 × 6: 12, the load in the +KG column, not body weight and belt.
        #expect(SetColumn.e1rm.text(weightKg: 10, reps: 6, rpe: nil) == "12")
        #expect(SetColumn.tenRM.text(weightKg: 10, reps: 6, rpe: nil) == "9")
    }

    @Test func rpeModeShowsTheRPEAndNoEstimate() {
        #expect(SetColumn.rpe.text(weightKg: 80, reps: 6, rpe: 8.5) == Fmt.kgNumber(8.5))
        #expect(SetColumn.rpe.text(weightKg: 80, reps: 6, rpe: nil).isEmpty, "empty stays empty, the table stays quiet")
        #expect(SetColumn.rpe.estimate(weightKg: 80, reps: 6) == nil)
    }

    // MARK: VoiceOver

    @Test func theEstimatesAreSpokenWithTheirKind() {
        #expect(SetColumn.e1rm.spoken(weightKg: 75, reps: 10, rpe: nil) == "estimated one-rep max 100 kilograms")
        #expect(SetColumn.tenRM.spoken(weightKg: 75, reps: 10, rpe: nil) == "estimated ten-rep max 75 kilograms")
        #expect(SetColumn.rpe.spoken(weightKg: 75, reps: 10, rpe: 8) == "RPE 8")
        #expect(SetColumn.rpe.spoken(weightKg: 75, reps: 10, rpe: nil) == nil)
    }

    @Test func theHeaderSaysWhatItShows() {
        #expect(SetColumn.e1rm.spokenTitle == "Estimated 1RM")
        #expect(SetColumn.tenRM.spokenTitle == "Estimated 10RM")
        #expect(SetColumn.rpe.spokenTitle == "RPE")
    }
}

/// The choice on disk (design.md §7, brief: per user).
@Suite("Fourth column's choice")
struct SetColumnSettingTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard }

    @Test func nothingChosenIsNil() {
        #expect(Settings(defaults: defaults()).setColumn == nil)
    }

    @Test("A choice survives a relaunch", arguments: SetColumn.allCases)
    func aChoiceSurvives(_ column: SetColumn) {
        let d = defaults()
        Settings(defaults: d).setColumn = column
        #expect(Settings(defaults: d).setColumn == column)
    }

    @Test func anUnknownValueIsNoChoice() {
        let d = defaults()
        d.set("15rm", forKey: "train.setColumn")
        #expect(Settings(defaults: d).setColumn == nil)
    }

    @Test func logOutClearsIt() {
        let d = defaults()
        let settings = Settings(defaults: d)
        settings.setColumn = .tenRM
        settings.sessionLayout = .list
        settings.clearPerUserState()
        #expect(settings.setColumn == nil)
        #expect(settings.sessionLayout == .list, "a choice about the device's screen, not the account")
        #expect(Settings(defaults: d).setColumn == nil, "gone from disk too: the next account starts on the default")
    }
}

/// The controller side and the last-time card. The rig is `ReplaceRig`: `Row` (0, 3 sets, no target) · `Bench` (1, 4 sets:
/// 5 × 80 typed on the first two, last time 5 × 77.5, target 5 reps at 80) · `Lateral` (2) · `Curl` (3).
@MainActor
struct SessionColumnTests {
    private func rig(_ layout: SessionLayout = .focused) -> ReplaceRig { ReplaceRig(sessionLayout: layout) }

    /// What a choice must leave alone.
    private struct Written: Equatable {
        let updatedAt: Date
        let ops: Int

        @MainActor
        init(_ r: ReplaceRig) {
            updatedAt = r.session.updatedAt
            ops = r.store.pendingOps().count
        }
    }

    private func add(_ exercise: Exercise, to r: ReplaceRig) -> LocalSessionExercise {
        SessionFactory.add(exercise, to: r.session, sets: 3, in: r.store)
    }

    // MARK: which column

    @Test func theRigOpensOnE1RM() {
        let r = rig()
        #expect(r.controller.column(for: r.row) == .e1rm)
        #expect(r.controller.column(for: r.x) == .e1rm)
    }

    @Test func anRPETargetShowsRPEOnThatExerciseOnly() {
        let r = rig()
        r.row.targetKindRaw = TargetKind.rpe.rawValue
        #expect(r.controller.column(for: r.row) == .rpe)
        #expect(r.controller.column(for: r.x) == .e1rm)
    }

    @Test func anRPEAnywhereInTheSessionShowsRPEEverywhere() {
        let r = rig()
        r.curl.orderedSets[2].rpe = 8
        #expect(r.controller.column(for: r.row) == .rpe)
        #expect(r.controller.column(for: r.curl) == .rpe)
    }

    @Test func aWarmUpsRPECounts() {
        let r = rig()
        let set = r.row.orderedSets[0]
        set.isWarmup = true
        set.rpe = 6
        #expect(r.controller.column(for: r.x) == .rpe)
    }

    @Test func lastTimesRPEIsNotThisSessions() {
        let r = rig()
        r.row.lastTime = [SessionSet(setIndex: 0, reps: 8, weightKg: 60, rpe: 9)]
        #expect(r.controller.column(for: r.row) == .e1rm)
    }

    @Test func aChoiceStandsOverAnRPETargetAndALoggedRPE() {
        let r = rig()
        r.settings.setColumn = .tenRM
        r.row.targetKindRaw = TargetKind.rpe.rawValue
        r.curl.orderedSets[0].rpe = 8
        #expect(r.controller.column(for: r.row) == .tenRM)
        #expect(r.controller.column(for: r.curl) == .tenRM)
    }

    // MARK: flag off

    @Test("List stays on RPE, whatever was chosen", arguments: [SetColumn?.none] + SetColumn.allCases.map(Optional.some))
    func listIsRPE(_ chosen: SetColumn?) {
        let r = rig(.list)
        r.settings.setColumn = chosen
        #expect(r.controller.column(for: r.row) == .rpe)
        #expect(!r.controller.cyclesColumn(of: r.row))
    }

    @Test func listCantWriteTheChoice() {
        let r = rig(.list)
        r.controller.cycleColumn(of: r.row)
        #expect(r.settings.setColumn == nil)
    }

    @Test func listSaysNoEstimate() {
        let r = rig(.list)
        r.settings.setColumn = .e1rm
        #expect(r.controller.columnSpoken(of: r.x.orderedSets[0], in: r.x) == nil)
    }

    // MARK: cycling and persistence

    @Test func theHeaderCyclesAndWritesTheChoice() {
        let r = rig()
        let c = r.controller
        for expected in [SetColumn.tenRM, .rpe, .e1rm, .tenRM] {
            c.cycleColumn(of: r.row)
            #expect(r.settings.setColumn == expected)
            #expect(c.column(for: r.row) == expected)
        }
    }

    @Test func theCycleGoesOnFromWhatShows() {
        let r = rig()
        r.row.targetKindRaw = TargetKind.rpe.rawValue
        r.controller.cycleColumn(of: r.row)
        #expect(r.settings.setColumn == .e1rm, "RPE was on screen: E1RM follows, not 10RM")
    }

    @Test func aChoiceReachesEveryExercise() {
        let r = rig()
        r.controller.cycleColumn(of: r.row)
        #expect(r.controller.column(for: r.curl) == .tenRM)
    }

    @Test func aChoiceOutlivesTheController() {
        let r = rig()
        r.controller.cycleColumn(of: r.row)
        let next = SessionController(session: r.session, sync: r.sync, liveActivity: nil, clock: r.clock, library: r.library,
                                     layout: .focused, settings: r.settings)
        defer { next.stop() }
        #expect(next.column(for: r.row) == .tenRM)
    }

    @Test func aChoiceIsNoEdit() {
        let r = rig()
        r.store.save()
        let before = Written(r)
        let sets = r.x.orderedSets.map { ($0.reps, $0.weightKg, $0.rpe) }
        r.controller.cycleColumn(of: r.row)
        r.controller.cycleColumn(of: r.row)
        #expect(Written(r) == before, "no updatedAt and no upload")
        #expect(r.x.orderedSets.map(\.reps) == sets.map(\.0) && r.x.orderedSets.map(\.rpe) == sets.map(\.2))
    }

    @Test("Time and distance have no estimates and no choice to make", arguments: [true, false])
    func timeAndDistance(_ time: Bool) {
        let r = rig()
        let ex = add(time ? MockTrain.plank : MockTrain.erg, to: r)
        #expect(!r.controller.cyclesColumn(of: ex))
        #expect(r.controller.column(for: ex) == .rpe)
        r.settings.setColumn = .e1rm
        #expect(r.controller.column(for: ex) == .rpe, "the stored choice doesn't apply")
        r.controller.cycleColumn(of: ex)
        #expect(r.settings.setColumn == .e1rm, "and a tap can't reach it")
        #expect(r.controller.column(for: r.row) == .e1rm, "the other exercises keep theirs")
    }

    // MARK: RPE stays reachable

    @Test func editingRPEShowsItsFieldOverAnyChoice() {
        let r = rig()
        r.settings.setColumn = .e1rm
        let set = r.x.orderedSets[0]
        r.controller.edit(set, .rpe)
        #expect(r.controller.column(for: r.x) == .rpe, "the digits have a field")
        #expect(r.controller.column(for: r.row) == .e1rm, "another exercise doesn't follow")
        #expect(r.settings.setColumn == .e1rm, "and the choice is untouched")
        r.controller.focus = nil
        #expect(r.controller.column(for: r.x) == .e1rm, "back with the keypad")
    }

    @Test func editingKgOrRepsLeavesTheColumn() {
        let r = rig()
        r.settings.setColumn = .tenRM
        r.controller.edit(r.x.orderedSets[0], .kg)
        #expect(r.controller.column(for: r.x) == .tenRM)
        r.controller.edit(r.x.orderedSets[0], .reps)
        #expect(r.controller.column(for: r.x) == .tenRM)
    }

    @Test func aTypedRPESettlesTheDefaultForTheSession() {
        let r = rig()
        r.controller.edit(r.row.orderedSets[0], .rpe)
        r.controller.type("8")
        r.controller.focus = nil
        #expect(r.controller.column(for: r.row) == .rpe)
        #expect(r.controller.column(for: r.x) == .rpe)
    }

    @Test func aChoiceHoldsAfterATypedRPE() {
        let r = rig()
        r.settings.setColumn = .e1rm
        let set = r.row.orderedSets[0]
        r.controller.edit(set, .rpe)
        r.controller.type("8")
        r.controller.focus = nil
        #expect(r.controller.column(for: r.row) == .e1rm)
        #expect(set.rpe == 8, "stored, and VoiceOver and the context menu reach it")
    }

    @Test func theHeaderClosesAnRPEKeypadAndGoesOnFromIt() {
        let r = rig()
        r.settings.setColumn = .e1rm
        let set = r.x.orderedSets[0]
        r.controller.edit(set, .rpe)
        r.controller.type("9")
        r.controller.cycleColumn(of: r.x)
        #expect(r.controller.focus == nil)
        #expect(set.rpe == 9, "what was typed stays")
        #expect(r.settings.setColumn == .e1rm, "RPE was on screen")
        #expect(r.controller.column(for: r.x) == .e1rm)
    }

    @Test func theHeaderLeavesAKgKeypadOpen() {
        let r = rig()
        r.controller.edit(r.x.orderedSets[0], .kg)
        r.controller.cycleColumn(of: r.x)
        #expect(r.controller.focus?.field == .kg)
    }

    // MARK: the numbers a row reads

    @Test func aDoneSetReadsWhatItLogged() {
        let r = rig()
        r.settings.setColumn = .e1rm
        let set = r.x.orderedSets[0]
        set.weightKg = 75
        set.reps = 10
        set.completedAt = r.clock.now()
        #expect(r.controller.columnText(of: set, in: r.x) == "100")
        r.settings.setColumn = .tenRM
        #expect(r.controller.columnText(of: set, in: r.x) == "75")
    }

    @Test func aDoneSetWithoutLoadHasNoEstimateEvenWithAGhost() {
        let r = rig()
        r.settings.setColumn = .e1rm
        let set = r.x.orderedSets[2] // empty, with a ghost of 80
        set.reps = 5
        set.completedAt = r.clock.now()
        #expect(r.controller.columnText(of: set, in: r.x) == Fmt.placeholder, "a number nobody logged isn't an estimate of it")
    }

    @Test func anOpenSetReadsItsGhost() {
        let r = rig()
        r.settings.setColumn = .e1rm
        // The third row is empty; the ghost is the target, 5 × 80 (last time has one set).
        #expect(r.controller.columnText(of: r.x.orderedSets[2], in: r.x) == Fmt.kgNumber(93.5))
    }

    @Test func aTypedValueBeatsTheGhostPerField() {
        let r = rig()
        r.settings.setColumn = .e1rm
        let set = r.x.orderedSets[2]
        set.reps = 10
        #expect(r.controller.columnText(of: set, in: r.x) == Fmt.kgNumber(106.5), "typed 10 reps at the ghost's 80 kg")
    }

    @Test func anEmptySetIsADash() {
        let r = rig()
        r.settings.setColumn = .e1rm
        #expect(r.controller.columnText(of: r.row.orderedSets[0], in: r.row) == Fmt.placeholder)
    }

    @Test func aStoredTimeHasNoRepsToRead() {
        let r = rig()
        r.settings.setColumn = .e1rm
        let set = r.x.orderedSets[2] // has a ghost of 5 × 80, shown as its time instead
        set.durationSec = 45
        #expect(r.controller.columnText(of: set, in: r.x) == Fmt.placeholder)
    }

    @Test func aBodyweightSetCountsAddedLoadOnly() {
        let r = rig()
        r.settings.setColumn = .e1rm
        let ex = add(MockTrain.pullUp, to: r)
        let sets = ex.orderedSets
        sets[0].reps = 8
        sets[0].completedAt = r.clock.now()
        sets[1].reps = 6
        sets[1].weightKg = 10
        sets[1].completedAt = r.clock.now()
        #expect(r.controller.columnText(of: sets[0], in: ex) == Fmt.placeholder)
        #expect(r.controller.columnText(of: sets[1], in: ex) == "12")
    }

    @Test func aBodyweightGhostFromAnAssistedSetIsADash() {
        let r = rig()
        r.settings.setColumn = .e1rm
        let ex = add(MockTrain.pullUp, to: r)
        ex.lastTime = [SessionSet(setIndex: 0, reps: 8, assistKg: 20)]
        #expect(r.controller.columnText(of: ex.orderedSets[0], in: ex) == Fmt.placeholder)
    }

    @Test func rpeModeShowsTheSetsRPE() {
        let r = rig()
        r.settings.setColumn = .rpe
        let set = r.x.orderedSets[0]
        set.rpe = 8.5
        #expect(r.controller.columnText(of: set, in: r.x) == Fmt.kgNumber(8.5))
    }

    // MARK: VoiceOver on a row

    @Test func aRowSpeaksItsEstimateInTheEstimateColumns() {
        let r = rig()
        let set = r.x.orderedSets[0] // 5 × 80, typed
        r.settings.setColumn = .e1rm
        #expect(r.controller.columnSpoken(of: set, in: r.x) == "estimated one-rep max \(Fmt.kgNumber(93.5)) kilograms")
        r.settings.setColumn = .tenRM
        #expect(r.controller.columnSpoken(of: set, in: r.x) == "estimated ten-rep max 70 kilograms")
    }

    @Test func aRowHasNothingToAddInRPE() {
        let r = rig()
        r.settings.setColumn = .rpe
        let set = r.x.orderedSets[0]
        set.rpe = 8
        #expect(r.controller.columnSpoken(of: set, in: r.x) == nil, "the row says its RPE itself, in every column")
    }

    // MARK: the last-time card

    private func card(_ sets: [SessionSet], _ column: SetColumn, loadType: LoadType = .weight) -> LastTimeCard {
        LastTimeCard(sets: sets, loadType: loadType, columns: .regular, column: column, onTap: {})
    }

    private let lastTime = [SessionSet(setIndex: 0, reps: 10, weightKg: 75, rpe: 8), SessionSet(setIndex: 1, reps: 6, weightKg: 80)]

    @Test func theCardFollowsTheColumn() {
        #expect(card(lastTime, .e1rm).fourth == ["100", "96"])
        #expect(card(lastTime, .tenRM).fourth == ["75", "72"])
        #expect(card(lastTime, .rpe).fourth == ["8", ""])
    }

    @Test func theCardKeepsTheCapAndTheDash() {
        let sets = [SessionSet(setIndex: 0, reps: 15, weightKg: 60), SessionSet(setIndex: 1, reps: 8),
                    SessionSet(setIndex: 2, reps: 6, assistKg: 20), SessionSet(setIndex: 3, durationSec: 45)]
        #expect(card(sets, .tenRM, loadType: .bodyweight).fourth == ["63", Fmt.placeholder, Fmt.placeholder, Fmt.placeholder])
    }

    @Test func theCardListsWorkingSetsUpToSix() {
        var sets = [SessionSet(setIndex: 0, reps: 10, weightKg: 40, isWarmup: true)]
        sets += (1...8).map { SessionSet(setIndex: $0, reps: 10, weightKg: 75) }
        #expect(card(sets, .e1rm).fourth == Array(repeating: "100", count: 6), "no warm-up, and six rows")
    }

    @Test func theCardSpeaksTheColumn() {
        let e1rm = card(lastTime, .e1rm).spoken
        #expect(e1rm.contains("10 reps at 75 kilograms, estimated one-rep max 100 kilograms"))
        #expect(e1rm.contains("6 reps at 80 kilograms, estimated one-rep max 96 kilograms"))
        #expect(card(lastTime, .tenRM).spoken.contains("estimated ten-rep max 72 kilograms"))
        let rpe = card(lastTime, .rpe).spoken
        #expect(rpe.contains("10 reps at 75 kilograms, RPE 8") && !rpe.contains("estimated"))
    }

    @Test func theCardFollowsTheExercisesColumnOnThePage() {
        let r = rig()
        r.settings.setColumn = .tenRM
        r.x.lastTime = lastTime
        #expect(card(r.x.lastTime, r.controller.column(for: r.x)).fourth == ["75", "72"])
    }
}
