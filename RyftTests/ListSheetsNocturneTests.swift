import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The live workout's List layout and the sheets it opens, in Nocturne (PR 6 B §4.3, §4.7, §4.8, §14.2; T6B.2): the numbers
/// and inks as maths, then the views in a real window (`HostedWindow`), read through the accessibility tree and sampled pixels.
/// Synthetic values only (the plan's Upper A).
@MainActor
@Suite("List layout and session sheets in Nocturne", .serialized)
struct ListSheetsNocturneTests {
    // MARK: numbers and inks

    @Test("List's current-set bar: Focused's 2 pt Volt bar, 10 outside the 56 pt row, 40 high, in the card's padding")
    func theBarsNumbers() {
        #expect(CurrentSetHighlight.barOutset == 10)
        #expect(LiveSessionSpec.activeBarHeight(rowHeight: CurrentSetHighlight.rowHeight) == 40)
        #expect(LiveSessionSpec.activeBarWidth == 2)
        // In the card's 14 pt padding, 4 from its edge.
        #expect(ExerciseCard.padding - CurrentSetHighlight.barOutset == 4)
        #expect(FocusedRowInk.mark == Theme.signal)
    }

    @Test("The rest bar: radius 22, an edge of ink at 20 % (the running pill's), a 36 pt ring of Volt on ink at 16 %")
    func theRestBarsNumbers() {
        #expect(RestBar.radius == 22)
        #expect(RestBar.edge == RestPill.runningEdge)
        #expect(RestBar.ring == 36 && RestBar.ringLine == 4 && RestBar.compactRing == 28)
        #expect(RestBar.ringTrack == RestPill.ringTrack)
        #expect(RestBar.ringInk == Theme.signal)
        #expect(RestBar.lessTitle == "\u{2212}15 s" && RestBar.moreTitle == "+15 s")
    }

    @Test("A folded exercise is an outlined grey check on a radius-22 row, not a filled teal one")
    func theCollapsedRow() {
        #expect(CollapsedExerciseRow.checkSymbol == "checkmark.circle")
        #expect(CollapsedExerciseRow.checkInk == Theme.textSecondary)
        #expect(CollapsedExerciseRow.checkSize == 20)
        #expect(CollapsedExerciseRow.radius == 22)
    }

    @Test("A filter chip: a 34 pt capsule in a 44 pt box; the chosen one ink-filled, the others an ink outline at 16 %")
    func theFilterChip() {
        #expect(FilterChip.height == 34)
        #expect(FilterChip.hitOverhang * 2 + FilterChip.height == Theme.Metrics.minHitTarget)
        #expect(FilterChip.edge == 0.16)
    }

    @Test("An exercise row's detail: the kind, then the main muscles as a list (b-24), Custom first for the user's own")
    func theRowsDetail() {
        let bench = MockTrain.bench
        #expect(AddExerciseSheet.detail(of: bench) == "Barbell · Chest")
        var two = bench
        two.primaryMuscles = [.quads, .glutes]
        #expect(AddExerciseSheet.detail(of: two) == "Barbell · Quads, glutes")
        var own = bench
        own.isCustom = true
        #expect(AddExerciseSheet.detail(of: own).hasPrefix("Custom · "))
    }

    @Test("Edit targets: the sets stepper says why it stops at its floor; elsewhere its value is RyftStepper's")
    func theFloorNote() {
        let floor = RyftStepperValue(text: "2", canDecrement: false, canIncrement: true) { _ in }
        #expect(EditTargetsSheet.spokenValue(floor, floorNote: "2 sets are done and stay.") == "2, minimum. 2 sets are done and stay.")
        #expect(EditTargetsSheet.spokenValue(floor, floorNote: nil) == "2, minimum")
        let open = RyftStepperValue(text: "3", canDecrement: true, canIncrement: true) { _ in }
        #expect(EditTargetsSheet.spokenValue(open, floorNote: "2 sets are done and stay.") == "3")
    }

    // MARK: hosted: the List page

    private typealias RGB = FocusedPolishHostedTests.RGB

    private static func isClose(_ p: RGB, _ color: Color, tolerance: Double = 0.06) -> Bool {
        FocusedPolishHostedTests.isClose(p, to: FocusedPolishHostedTests.rgb(color), tolerance: tolerance)
    }

    /// Whether anything in the window carries `identifier`: a text field is a UIKit view, not one of `nodes()`' SwiftUI nodes.
    private static func hasIdentifier(_ identifier: String, in w: HostedWindow) -> Bool {
        var seen = Set<ObjectIdentifier>()
        func walk(_ object: NSObject, depth: Int) -> Bool {
            guard depth < 80, seen.insert(ObjectIdentifier(object)).inserted else { return false }
            if (object.value(forKey: "accessibilityIdentifier") as? String) == identifier { return true }
            if let elements = object.accessibilityElements {
                for case let child as NSObject in elements where walk(child, depth: depth + 1) { return true }
            }
            if let view = object as? UIView {
                for sub in view.subviews where walk(sub, depth: depth + 1) { return true }
            }
            return false
        }
        return walk(w.window, depth: 0)
    }

    /// `b-02`: set 2 of Bench press is the current set. The bar sits 10 pt outside its row in the card's padding; the done row
    /// above has none.
    @Test("List's current set: the Volt bar 10 pt outside the row, in the card; none beside a done row")
    func theCurrentSetsBar() async throws {
        let c = SessionSheetsPreview.listDraft()
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 1400, SessionView(controller: c)) { w in
            try await w.settle()
            let current = try #require(w.node("Set 2 of"))
            #expect(current.value == "Next set.")
            let done = try #require(w.node("Set 1 of")).frame
            // From the screen's edge: the row's element takes in the (hidden) bar, so its frame starts at the bar. The row
            // starts at the page's side plus the card's padding.
            let rowX = LiveSessionSpec.sidePadding + ExerciseCard.padding
            let barX = rowX - CurrentSetHighlight.barOutset + LiveSessionSpec.activeBarWidth / 2
            let mid = LiveSessionSpec.activeBarInset + LiveSessionSpec.activeBarHeight(rowHeight: CurrentSetHighlight.rowHeight) / 2
            let bar = try #require(w.pixel(at: CGPoint(x: barX, y: current.frame.minY + mid)))
            #expect(Self.isClose(bar, Theme.signal, tolerance: 0.1), "\(bar)")
            // Above the bar's end, still in the row: the card.
            let above = try #require(w.pixel(at: CGPoint(x: barX, y: current.frame.minY + 2)))
            #expect(Self.isClose(above, Theme.surface), "\(above)")
            let none = try #require(w.pixel(at: CGPoint(x: barX, y: done.minY + mid)))
            #expect(Self.isClose(none, Theme.surface), "\(none)")
            // The bar is inside the card: 4 pt further out is the screen.
            let outside = try #require(w.pixel(at: CGPoint(x: LiveSessionSpec.sidePadding - 2, y: current.frame.midY)))
            #expect(Self.isClose(outside, Theme.background), "\(outside)")
        }
    }

    @Test("Under the cards: \"Add exercise\" an outline pill (52 high), \"Reorder exercises\" a 44 pt text button")
    func underTheCards() async throws {
        let c = SessionSheetsPreview.listDraft()
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 3000, SessionView(controller: c)) { w in
            try await w.settle()
            let add = try #require(w.node("Add exercise", exactly: true))
            #expect(add.frame.height >= PillButton.minHeight - 0.5, "\(add.frame)")
            #expect(add.traits.contains(.button))
            let inside = try #require(w.pixel(at: CGPoint(x: add.frame.minX + 30, y: add.frame.midY)))
            #expect(Self.isClose(inside, Theme.background), "an outline, not a fill: \(inside)")
            let reorder = try #require(w.node("Reorder exercises", exactly: true))
            #expect(reorder.frame.height >= Theme.Metrics.minHitTarget - 0.5, "\(reorder.frame)")
        }
    }

    @Test("An empty List session says so, visibly, in an outlined card and offers Add exercise")
    func anEmptySession() async throws {
        let c = FocusedPreview.controller(.empty)
        defer { c.stop() }
        // The same store as the session: `c.sync`.
        let list = SessionController(session: c.session, sync: c.sync, liveActivity: nil, layout: .list)
        defer { list.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: list)) { w in
            try await w.settle()
            let message = try #require(w.node("An empty session. Add your first exercise.")).frame
            // The outline is a stroke over the message, not a filled placeholder: the words stay visible.
            var ink = 0
            for x in stride(from: message.minX + 4, through: message.maxX - 4, by: 2) {
                if let p = w.pixel(at: CGPoint(x: x, y: message.midY)), p.r > 0.5 { ink += 1 }
            }
            #expect(ink > 4, "the message is drawn: \(ink) ink pixels")
            #expect(w.node("Add exercise", exactly: true) != nil)
            #expect(w.node("Reorder exercises") == nil)
        }
    }

    // MARK: hosted: the rest bar

    @Test("The rest bar running: −15 s and +15 s leading, Skip trailing on one line, each a 44 pt target, Voice Control names kept")
    func theRunningRestBar() async throws {
        let c = SessionSheetsPreview.listDraft()
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c)) { w in
            try await w.settle()
            #expect(w.node("Rest timer")?.isAdjustable == true)
            let less = try #require(w.node("Fifteen seconds less", exactly: true))
            let more = try #require(w.node("Fifteen seconds more", exactly: true))
            let skip = try #require(w.node("Skip rest", exactly: true))
            for node in [less, more, skip] {
                #expect(node.frame.height >= Theme.Metrics.minHitTarget - 0.5, "\(node.label) \(node.frame)")
            }
            #expect(abs(less.frame.midY - skip.frame.midY) < 1 && abs(more.frame.midY - skip.frame.midY) < 1)
            #expect(less.frame.maxX < more.frame.minX && more.frame.maxX < skip.frame.minX)
            // Skip ends at the card's content edge: 16 pt page side, 14 pt in the card.
            #expect(abs(skip.frame.maxX - (390 - LiveSessionSpec.sidePadding - RestBar.horizontalPadding)) < 1, "\(skip.frame)")
            #expect(less.inputLabels == ["Minus 15", "Fifteen seconds less"])
            #expect(skip.inputLabels == ["Skip", "Skip rest"])

            let before = c.rest.remaining(at: .now)
            #expect(more.activate())
            #expect(c.rest.remaining(at: .now) > before + 10)
            #expect(skip.activate())
            try await w.wait("the rest ends") { !c.rest.isRunning }
        }
    }

    @Test("At AX3 the rest bar's three buttons go one per line")
    func theRestBarAtAX3() async throws {
        let c = SessionSheetsPreview.listDraft()
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 1400, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                   SessionView(controller: c)) { w in
            try await w.settle()
            let frames = try ["Fifteen seconds less", "Fifteen seconds more", "Skip rest"].map {
                try #require(w.node($0, exactly: true)).frame
            }
            #expect(frames[0].maxY <= frames[1].minY + 0.5 && frames[1].maxY <= frames[2].minY + 0.5, "\(frames)")
        }
    }

    @Test("Rest over: the words and the next set as one element, and a Dismiss pill that ends it")
    func restOver() async throws {
        let c = SessionSheetsPreview.listFolded()
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c)) { w in
            try await w.wait("the banner") { w.node("Rest over") != nil }
            let banner = try #require(w.node("Rest over"))
            #expect(banner.label.hasPrefix("Rest over. Next: "), "\(banner.label)")
            let dismiss = try #require(w.node("Dismiss", exactly: true))
            #expect(dismiss.hint == "Dismisses the banner")
            #expect(dismiss.frame.height >= Theme.Metrics.minHitTarget - 0.5)
            #expect(dismiss.activate())
            try await w.wait("the banner goes") { w.node("Rest over") == nil }
        }
    }

    @Test("A folded exercise: one button that says what was done, at least 56 high, its identifier and hint kept")
    func theFoldedRow() async throws {
        let c = SessionSheetsPreview.listFolded()
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 1400, SessionView(controller: c)) { w in
            try await w.settle()
            let row = try #require(w.node("Bench press, completed."))
            #expect(row.identifier == "collapsed.0")
            #expect(row.hint == "Expands the sets")
            #expect(row.frame.height >= 56 - 0.5)
            #expect(row.traits.contains(.button))
        }
    }

    // MARK: hosted: the sheets

    @Test("Add exercise: the header, the search field, the chosen chip, rows named by the exercise with their identifiers")
    func addExercise() async throws {
        var picked: Exercise?
        try await HostedWindow.run(width: 390, height: 844, AddExerciseSheet { picked = $0 }) { w in
            try await w.settle()
            let title = try #require(w.node("Add exercise", exactly: true))
            #expect(title.traits.contains(.header))
            #expect(w.node("Close", exactly: true)?.identifier == "sheet.close")
            #expect(Self.hasIdentifier("exercise.search", in: w))
            let all = try #require(w.node("All muscles", exactly: true))
            #expect(all.isSelected)
            #expect(all.frame.height >= Theme.Metrics.minHitTarget - 0.5, "\(all.frame)")
            #expect(w.node("All exercises", exactly: true)?.traits.contains(.header) == true)
            let bench = try #require(w.node(MockTrain.bench.name, exactly: true))
            #expect(bench.identifier == "exercise.pick.\(MockTrain.bench.slug)")
            #expect(bench.value == AddExerciseSheet.detail(of: MockTrain.bench))
            #expect(bench.frame.height >= Theme.Metrics.listRowHeight - 0.5)
            #expect(w.node("Custom exercise", exactly: true)?.identifier == "exercise.custom")

            // A muscle chip takes the selection, and the list follows it.
            let muscle = try #require(MockTrain.bench.primaryMuscles.first)
            #expect(try #require(w.node(muscle.title, exactly: true)).activate())
            try await w.wait("the chip is chosen") { w.node(muscle.title, exactly: true)?.isSelected == true }
            #expect(w.node("All muscles", exactly: true)?.isSelected == false)

            #expect(try #require(w.node(MockTrain.bench.name, exactly: true)).activate())
            #expect(picked?.id == MockTrain.bench.id)
        }
    }

    @Test("Replace: Similar before All exercises, the split note read as one, and the plan toggle pinned and passed on")
    func replace() async throws {
        var result: (Exercise, Bool)?
        let context = SessionSheetsPreview.replaceContext()
        try await HostedWindow.run(width: 390, height: 844, AddExerciseSheet(replacing: context) { result = ($0, $1) }) { w in
            try await w.settle()
            #expect(w.node("Replace \(MockTrain.bench.name)", exactly: true)?.traits.contains(.header) == true)
            let similar = try #require(w.node("Similar", exactly: true)).frame
            #expect(w.node("Your done set stays with \(MockTrain.bench.name).") != nil)
            let toggle = try #require(w.node("Also change the plan"))
            #expect(toggle.identifier == "replace.alsoChangePlan")
            // Pinned under the list: in the window's lower part, whatever the list's scroll.
            #expect(toggle.frame.minY > 844 / 2, "\(toggle.frame)")
            #expect(toggle.activate())
            let first = try #require(w.nodes().first {
                $0.identifier?.hasPrefix("exercise.pick.") == true && $0.frame.minY > similar.maxY
            })
            #expect(first.activate())
            #expect(result?.1 == true, "the toggle's value goes with the pick")
        }
    }

    @Test("Replace at AX3: the plan toggle scrolls with the list, above Similar")
    func replaceAtAX3() async throws {
        let context = SessionSheetsPreview.replaceContext()
        try await HostedWindow.run(width: 390, height: 844, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                   AddExerciseSheet(replacing: context) { _, _ in }) { w in
            try await w.settle()
            let toggle = try #require(w.node("Also change the plan"))
            if let similar = w.node("Similar", exactly: true) {
                #expect(toggle.frame.maxY <= similar.frame.minY + 0.5, "\(toggle.frame) \(similar.frame)")
            }
        }
    }

    @Test("The custom exercise form: Add disabled until it has a name, the three menu rows and the toggle")
    func customExercise() async throws {
        try await HostedWindow.run(width: 390, height: 844, CustomExerciseForm(name: "") { _ in }) { w in
            try await w.settle()
            #expect(w.node("Custom exercise", exactly: true)?.traits.contains(.header) == true)
            #expect(w.node("Cancel", exactly: true)?.identifier == "sheet.close")
            let add = try #require(w.node("Add", exactly: true))
            #expect(add.identifier == "customExercise.add")
            #expect(!add.isEnabled, "no name yet")
            #expect(Self.hasIdentifier("customExercise.name", in: w))
            #expect(w.node("Kind", exactly: true) != nil)
            #expect(w.node("Main muscle", exactly: true)?.identifier == "customExercise.muscle")
            #expect(w.node("Logged as", exactly: true) != nil)
            #expect(w.node("One side at a time") != nil)
        }
        try await HostedWindow.run(width: 390, height: 844, CustomExerciseForm(name: "Landmine press") { _ in }) { w in
            try await w.settle()
            #expect(w.node("Add", exactly: true)?.isEnabled == true)
        }
    }

    @Test("Edit targets: adjustable stepper rows, the floor's reason said, Done writes and keeps its identifier, Cancel doesn't")
    func editTargets() async throws {
        let c = SessionSheetsPreview.listDraft()
        defer { c.stop() }
        let bench = c.exercises[0]
        let before = c.targets(of: bench)
        try await HostedWindow.run(width: 390, height: 1000, EditTargetsSheet(controller: c, exercise: bench)) { w in
            try await w.settle()
            #expect(w.node("Edit targets", exactly: true)?.traits.contains(.header) == true)
            #expect(w.node("Cancel", exactly: true)?.identifier == "sheet.close")
            let sets = try #require(w.node("Sets", exactly: true))
            #expect(sets.isAdjustable)
            #expect(sets.value == "\(before.sets)")
            for _ in 0..<20 { sets.decrement() }
            try await w.wait("the floor") { w.node("Sets", exactly: true)?.value?.contains("minimum. ") == true }
            #expect(w.node("Sets", exactly: true)?.value == "1, minimum. 1 set is done and stays.")
            #expect(w.node("Rest", exactly: true)?.value == RestSpeech.duration(bench.restSec))
            #expect(w.node("Reps from", exactly: true)?.isAdjustable == true)

            // Cancel leaves the session alone.
            #expect(try #require(w.node("Cancel", exactly: true)).activate())
            #expect(c.targets(of: bench) == before)
        }
        try await HostedWindow.run(width: 390, height: 1000, EditTargetsSheet(controller: c, exercise: bench)) { w in
            try await w.settle()
            try #require(w.node("Sets", exactly: true)).increment()
            try await w.wait("one more set") { w.node("Sets", exactly: true)?.value == "\(before.sets + 1)" }
            let done = try #require(w.node("Done", exactly: true))
            #expect(done.identifier == "editTargets.done")
            #expect(done.activate())
            #expect(c.targets(of: bench).sets == before.sets + 1)
        }
    }

    @Test("Edit targets: \"Clear target weight\" under the weight while there is one")
    func clearTheWeight() async throws {
        let c = SessionSheetsPreview.listDraft()
        defer { c.stop() }
        let bench = c.exercises[0]
        try await HostedWindow.run(width: 390, height: 1000, EditTargetsSheet(controller: c, exercise: bench)) { w in
            try await w.settle()
            if w.node("Clear target weight", exactly: true) == nil {
                try #require(w.node("Target weight (kg)", exactly: true)).increment()
            }
            try await w.wait("Clear shows") { w.node("Clear target weight", exactly: true) != nil }
            try await w.settle()
            let weight = try #require(w.node("Target weight (kg)", exactly: true))
            let clear = try #require(w.node("Clear target weight", exactly: true))
            #expect(clear.frame.minY >= weight.frame.maxY - 0.5, "under the weight")
            #expect(clear.activate())
            try await w.wait("Clear goes with the weight") { w.node("Clear target weight", exactly: true) == nil }
            #expect(w.node("Target weight (kg)", exactly: true)?.value?.hasPrefix(Fmt.placeholder) == true)
        }
    }

    @Test("Notes: the header with Save, the field named Notes, the close circle Cancel")
    func notes() async throws {
        let c = SessionSheetsPreview.listDraft()
        defer { c.stop() }
        let bench = c.exercises[0]
        bench.notes = "Pause on the chest"
        try await HostedWindow.run(width: 390, height: 844, ExerciseNotesSheet(controller: c, exercise: bench)) { w in
            try await w.settle()
            #expect(w.node("Notes", exactly: true)?.traits.contains(.header) == true)
            #expect(w.node("Save", exactly: true)?.identifier == "notes.save")
            #expect(Self.hasIdentifier("notes.field", in: w))
            #expect(w.node("Cancel", exactly: true)?.identifier == "sheet.close")
            #expect(try #require(w.node("Save", exactly: true)).activate())
            #expect(bench.notes == "Pause on the chest")
        }
    }

    @Test("Reorder: the header with Done (its own identifier), a 56 pt row per exercise, a superset named")
    func reorder() async throws {
        let c = SessionSheetsPreview.listDraft()
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 844, ReorderSheet(controller: c)) { w in
            try await w.settle()
            #expect(w.node("Reorder", exactly: true)?.traits.contains(.header) == true)
            #expect(w.node("Done", exactly: true)?.identifier == "reorder.done")
            for ex in c.exercises.prefix(3) {
                #expect(w.node(ex.name) != nil, "\(ex.name)")
            }
            // 56 a row (B §1.3), not 56 plus the list's insets: the names are a row's height apart.
            let first = try #require(w.node(c.exercises[0].name, exactly: true)).frame
            let second = try #require(w.node(c.exercises[1].name, exactly: true)).frame
            #expect(abs((second.midY - first.midY) - ReorderSheet.rowHeight) < 1.5, "\(first) \(second)")
            if c.exercises.contains(where: { $0.supersetGroup != nil }) {
                #expect(w.node("In a superset") != nil)
            }
        }
    }
}
