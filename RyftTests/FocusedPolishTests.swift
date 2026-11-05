import SwiftUI
import Testing
@testable import Ryft

/// T5's decisions as plain values: the table at a text size (design.md §5.1), the RPE line, Finish's fill (L21), the light
/// tokens by maths rather than pixels, and "Next" when there is no check to follow. Synthetic values only.
@MainActor
@Suite("Focused polish")
struct FocusedPolishTests {
    // MARK: the table at a text size

    struct TableCase: Sendable, CustomTestStringConvertible {
        let width: CGFloat
        let size: DynamicTypeSize
        let numeral: CGFloat, fourth: Bool, row: CGFloat, lastTime: CGFloat
        var testDescription: String { "\(Int(width)) pt, \(size)" }
    }

    nonisolated static let tables = [
        TableCase(width: 390, size: .large, numeral: 22, fourth: true, row: 56, lastTime: 36),
        TableCase(width: 320, size: .large, numeral: 20, fourth: true, row: 56, lastTime: 36),
        TableCase(width: 390, size: .xxxLarge, numeral: 22, fourth: true, row: 56, lastTime: 36),
        TableCase(width: 320, size: .xxxLarge, numeral: 20, fourth: true, row: 56, lastTime: 36),
        TableCase(width: 390, size: .accessibility1, numeral: 26, fourth: true, row: 56, lastTime: 44),
        TableCase(width: 390, size: .accessibility2, numeral: 26, fourth: true, row: 56, lastTime: 44),
        TableCase(width: 320, size: .accessibility1, numeral: 26, fourth: false, row: 56, lastTime: 44),
        TableCase(width: 320, size: .accessibility2, numeral: 26, fourth: false, row: 56, lastTime: 44),
        TableCase(width: 390, size: .accessibility3, numeral: 30, fourth: false, row: 64, lastTime: 44),
        TableCase(width: 320, size: .accessibility3, numeral: 30, fourth: false, row: 64, lastTime: 44),
        TableCase(width: 390, size: .accessibility5, numeral: 30, fourth: false, row: 64, lastTime: 44),
    ]

    @Test("The table follows design.md §5.1", arguments: tables)
    func table(_ t: TableCase) {
        let c = SetTableColumns.fitting(width: t.width, typeSize: t.size)
        #expect(c.numeral == t.numeral)
        #expect(c.hasFourth == t.fourth)
        #expect(c.rowHeight == t.row)
        #expect(c.lastTimeRow == t.lastTime)
        #expect(c.isCompact == (t.width < 360))
        #expect(c.numberHitArea.height == t.row, "the number's hit area is a row high")
    }

    @Test("A text size never changes the width class, which the header and the strip's rule read")
    func widthClassHoldsAtEverySize() {
        for size in DynamicTypeSize.allCases {
            #expect(SetTableColumns.fitting(width: 320, typeSize: size).isCompact)
            #expect(!SetTableColumns.fitting(width: 390, typeSize: size).isCompact)
        }
        #expect(!SetTableColumns.fitting(width: 0).isCompact, "no size yet is the regular table, as before")
    }

    @Test("Tiles and the strip grow at AX3, and the strip's height keeps its slots")
    func stripAtAX3() {
        #expect(ExerciseStrip.tileSize(.accessibility2) == 56)
        #expect(ExerciseStrip.height(.accessibility2) == 76)
        #expect(ExerciseStrip.tileSize(.accessibility3) == 64)
        #expect(ExerciseStrip.height(.accessibility3) == 84)
    }

    @Test("−15 and +15 grow with their 64 pt key at AX3")
    func restKeys() {
        #expect(RestSheet.keyNumeral(.accessibility2) == 17)
        #expect(RestSheet.keyNumeral(.accessibility3) == 26)
    }

    @Test("At 320 pt the taller strip counts for the room beside the keypad")
    func stripHeightCounts() {
        let compact = SetTableColumns.fitting(width: 320, typeSize: .accessibility3)
        #expect(FocusedSessionView.hidesStrip(columns: compact, keypadOpen: true, height: 300, pillRow: 0, typeSize: .accessibility3))
        #expect(!FocusedSessionView.hidesStrip(columns: compact, keypadOpen: true, height: 300, pillRow: 0, typeSize: .accessibility2))
    }

    // MARK: the RPE line

    private func rig(_ layout: SessionLayout = .focused) -> ReplaceRig {
        let r = ReplaceRig(sessionLayout: layout)
        r.controller.settings.setColumn = nil
        return r
    }

    private let large = SetTableColumns.fitting(width: 390, typeSize: .accessibility3)

    @Test("With a fourth column there is no RPE line")
    func noLineWithAColumn() {
        let r = rig()
        let set = r.row.orderedSets[0]
        set.rpe = 8
        #expect(!r.controller.showsRPELine(of: set, in: r.row, columns: .regular))
    }

    @Test("Without one, a row with an RPE keeps its line, in any column")
    func aLoggedRPEHasItsLine() {
        let r = rig()
        r.controller.settings.setColumn = .e1rm
        let sets = r.row.orderedSets
        sets[2].rpe = 8.5
        #expect(r.controller.showsRPELine(of: sets[2], in: r.row, columns: large))
        #expect(!r.controller.showsRPELine(of: sets[1], in: r.row, columns: large), "not on the others")
    }

    @Test("In RPE mode the active row is the way in, and the other rows stay one line")
    func theActiveRowIsTheWayIn() {
        let r = rig()
        r.controller.settings.setColumn = .rpe
        let sets = r.row.orderedSets
        #expect(r.controller.showsRPELine(of: sets[0], in: r.row, columns: large))
        #expect(!r.controller.showsRPELine(of: sets[1], in: r.row, columns: large))
    }

    @Test("An estimate column has no empty line on the active row")
    func noLineInAnEstimateMode() {
        let r = rig()
        r.controller.settings.setColumn = .tenRM
        #expect(!r.controller.showsRPELine(of: r.row.orderedSets[0], in: r.row, columns: large))
    }

    @Test("Edit RPE from an estimate column shows the line it types into, on that row")
    func theKeypadBringsItsLine() {
        let r = rig()
        r.controller.settings.setColumn = .e1rm
        let sets = r.row.orderedSets
        r.controller.edit(sets[1], .rpe)
        #expect(r.controller.showsRPELine(of: sets[1], in: r.row, columns: large))
    }

    @Test("A done row without an RPE gets the line only while the keypad is on it")
    func theKeypadOnADoneRow() {
        let r = rig()
        let set = r.row.orderedSets[0]
        set.reps = 5
        set.completedAt = .now
        #expect(!r.controller.showsRPELine(of: set, in: r.row, columns: large))
        r.controller.edit(set, .rpe)
        #expect(r.controller.showsRPELine(of: set, in: r.row, columns: large))
        r.controller.focus = nil
        #expect(!r.controller.showsRPELine(of: set, in: r.row, columns: large))
    }

    // MARK: Finish (L21)

    private func checkAll(_ r: ReplaceRig) {
        for ex in r.controller.exercises {
            for set in ex.orderedSets {
                set.reps = 5
                set.completedAt = .now
            }
        }
    }

    @Test("In Focused Finish fills only when every set is done, and an uncheck takes the fill away")
    func finishFillsAtTheEnd() {
        let r = rig()
        #expect(!r.controller.finishIsFilled)
        checkAll(r)
        #expect(r.controller.finishIsFilled)
        r.row.orderedSets[0].completedAt = nil
        #expect(!r.controller.finishIsFilled)
    }

    @Test("List's Finish is filled from the start")
    func listKeepsItsFinish() {
        #expect(rig(.list).controller.finishIsFilled)
    }

    // MARK: the light tokens, by maths

    private func parts(_ color: Color, _ scheme: ColorScheme) -> (r: Double, g: Double, b: Double, a: Double) {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let c = color.resolve(in: environment)
        return (Double(c.red), Double(c.green), Double(c.blue), Double(c.opacity))
    }

    /// `top` over `bottom` in gamma sRGB, as the screen composes it.
    private func over(_ top: (r: Double, g: Double, b: Double, a: Double), _ bottom: (r: Double, g: Double, b: Double, a: Double))
        -> (r: Double, g: Double, b: Double, a: Double) {
        func mix(_ t: Double, _ b: Double) -> Double { t * top.a + b * (1 - top.a) }
        return (mix(top.r, bottom.r), mix(top.g, bottom.g), mix(top.b, bottom.b), 1)
    }

    private func luminance(_ c: (r: Double, g: Double, b: Double, a: Double)) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private func contrast(_ ink: Color, on ground: (r: Double, g: Double, b: Double, a: Double), _ scheme: ColorScheme) -> Double {
        let a = luminance(over(parts(ink, scheme), ground)), b = luminance(ground)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func background(_ s: ColorScheme) -> (r: Double, g: Double, b: Double, a: Double) { parts(Theme.background, s) }
    private func tint(_ s: ColorScheme) -> (r: Double, g: Double, b: Double, a: Double) {
        var accent = parts(Theme.accent, s)
        accent.a = FocusedRowInk.activeTint
        return over(accent, background(s))
    }

    @Test("Light: text on the active row's tint holds 4.5:1", arguments: [false, true])
    func theEstimateOnTheActiveRow(isDash: Bool) {
        let ink = FocusedRowInk.estimate(active: true, isDash: isDash, .light)
        #expect(ink == Theme.textPrimary, "grey clears 4.5:1 here by 0.01, which is no margin")
        #expect(contrast(ink, on: tint(.light), .light) >= 4.5)
    }

    @Test("Light: an estimate on a plain row keeps its grey, which holds 4.5:1 there", arguments: [false, true])
    func theEstimateOnAPlainRow(isDash: Bool) {
        let ink = FocusedRowInk.estimate(active: false, isDash: isDash, .light)
        #expect(ink == (isDash ? Theme.textTertiary : Theme.textSecondary))
        #expect(contrast(ink, on: background(.light), .light) >= 4.5)
    }

    @Test("Light: the upcoming ✓'s outline holds 3:1 on the background")
    func theOutline() {
        #expect(contrast(FocusedRowInk.upcomingOutline(.light), on: background(.light), .light) >= 3)
    }

    @Test("Dark keeps the design's tokens")
    func darkIsUnchanged() {
        #expect(FocusedRowInk.upcomingOutline(.dark) == Theme.surfaceRaised)
        #expect(FocusedRowInk.estimate(active: true, isDash: false, .dark) == Theme.textSecondary)
        #expect(FocusedRowInk.estimate(active: true, isDash: true, .dark) == Theme.textTertiary)
    }

    /// `warning` needs no change: on the active row the W sits on its raised pill, never on the tint.
    @Test("The warm-up W holds 4.5:1 on a plain row and on the active row's pill, in both schemes",
          arguments: [ColorScheme.light, .dark])
    func theWarmUpMark(scheme: ColorScheme) {
        #expect(contrast(Theme.warning, on: background(scheme), scheme) >= 4.5)
        let pill = scheme == .light ? Theme.surface : Theme.surfaceRaised
        #expect(contrast(Theme.warning, on: over(parts(pill, scheme), tint(scheme)), scheme) >= 4.5)
    }

    @Test("An unfilled Finish reads 4.5:1 on its capsule", arguments: [ColorScheme.light, .dark])
    func finishText(scheme: ColorScheme) {
        #expect(contrast(Theme.accent, on: parts(Theme.surface, scheme), scheme) >= 4.5)
    }

    // MARK: "Next" with no check to follow

    @Test("A removed exercise that was the last checked: Next names the page's row, not that row's partner")
    func nextAfterARemoveNamesThePage() {
        let r = rig()
        let c = r.controller
        c.toggleCheck(r.curl.orderedSets[0], in: r.curl)
        c.jump(to: r.x.id)
        c.remove(r.curl)
        #expect(c.nextLabel().hasPrefix(r.x.name), "\(c.nextLabel())")
        #expect(c.nextUp(after: nil)?.exercise.id == r.x.id)
    }

    @Test("Removing the checked member of a superset of three: Next names its partner, the page's row")
    func nextAfterARemoveNamesThePartner() {
        let r = rig()
        let c = r.controller
        r.row.supersetGroup = 1
        c.jump(to: r.row.id)
        c.toggleCheck(r.row.orderedSets[0], in: r.row)
        #expect(c.nextLabel().hasPrefix(r.x.name), "the partner, before the remove")
        c.remove(r.row)
        #expect(c.pageExercise?.id == r.x.id)
        #expect(c.nextLabel().hasPrefix(r.x.name), "\(c.nextLabel())")
    }

    @Test("With a check to follow, a superset's partner still comes first")
    func aCheckStillFlipsToThePartner() {
        let r = rig()
        let c = r.controller
        c.jump(to: r.x.id)
        c.toggleCheck(r.x.orderedSets[0], in: r.x)
        #expect(c.nextLabel().hasPrefix(r.lateral.name), "\(c.nextLabel())")
    }

    @Test("A page with nothing open: Next goes on from it")
    func aFinishedPageGoesOn() {
        let r = rig()
        let c = r.controller
        for set in r.row.orderedSets {
            set.reps = 5
            set.completedAt = .now
        }
        c.jump(to: r.row.id)
        #expect(c.nextUp(after: nil)?.exercise.id == r.x.id)
    }

    @Test("List reads from the top, as before")
    func listIsUnchanged() {
        let r = rig(.list)
        #expect(r.controller.nextUp(after: nil)?.exercise.id == r.row.id)
    }
}

/// `HostedWindow` leaves the simulator's automation setting on: a UI run on that simulator comes next.
@MainActor
@Suite("Hosted window", .serialized)
struct HostedWindowTests {
    @Test("Automation is on during a window and stays on after it", arguments: [false, true])
    func automationStaysOn(before: Bool) async throws {
        let setting = try await HostedWindow.automationAroundAWindow(before: before)
        #expect(setting.during)
        #expect(setting.after)
    }
}
