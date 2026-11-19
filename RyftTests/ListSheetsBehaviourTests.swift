import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// What the live workout's rest bar and sheets do, in a real window (`HostedWindow`): the rest bar's buttons stay inside the
/// card at every size, "Rest over" keeps its words whole at AX sizes, a custom exercise reaches the pick and a slow one after
/// Cancel reaches nothing, a drag in Reorder moves the workout's exercise, and VoiceOver meets Replace's pinned plan toggle
/// before the list. Synthetic values only (the plan's Upper A).
@MainActor
@Suite("List and session sheets: behaviour", .serialized)
struct ListSheetsBehaviourTests {
    // MARK: the rest bar

    struct Fit: Sendable, CustomTestStringConvertible {
        let width: CGFloat
        let ax2: Bool

        var typeSize: DynamicTypeSize { ax2 ? .accessibility2 : .xxLarge }
        var category: UIContentSizeCategory { ax2 ? .accessibilityLarge : .extraExtraLarge }
        var testDescription: String { "\(Int(width)) pt, \(ax2 ? "AX2" : "XXL")" }
    }

    @Test("The running rest bar's buttons stay inside the card: one line while they fit, else one per line",
          arguments: [Fit(width: 390, ax2: true), Fit(width: 320, ax2: false)])
    func theRestBarFits(_ fit: Fit) async throws {
        let c = SessionSheetsPreview.listDraft()
        defer { c.stop() }
        try await HostedWindow.run(width: fit.width, height: 1_200, typeSize: fit.typeSize, category: fit.category,
                                   SessionView(controller: c)) { w in
            try await w.settle()
            let less = try #require(w.node("Fifteen seconds less", exactly: true)).frame
            let more = try #require(w.node("Fifteen seconds more", exactly: true)).frame
            let skip = try #require(w.node("Skip rest", exactly: true)).frame
            // The card's content: 16 pt page side, 14 pt in the card.
            let leading = LiveSessionSpec.sidePadding + RestBar.horizontalPadding
            let trailing = fit.width - leading
            for frame in [less, more, skip] {
                #expect(frame.minX >= leading - 0.5 && frame.maxX <= trailing + 0.5, "\(frame) in \(leading)...\(trailing)")
            }
            // Either the one line (Skip after +15 s) or one per line, leading.
            let oneLine = abs(less.midY - skip.midY) < 1
            if oneLine {
                #expect(more.maxX < skip.minX)
            } else {
                #expect(less.maxY <= more.minY + 0.5 && more.maxY <= skip.minY + 0.5, "\(less) \(more) \(skip)")
                #expect(abs(skip.minX - less.minX) < 1, "leading")
            }
        }
    }

    @Test("Rest over at AX3: the words take the card's width and Dismiss sits under them, leading")
    func restOverAtAX3() async throws {
        let c = SessionSheetsPreview.listFolded()
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 1_400, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                   SessionView(controller: c)) { w in
            try await w.wait("the banner") { w.node("Rest over") != nil }
            try await w.settle()
            let words = try #require(w.node("Rest over")).frame
            let dismiss = try #require(w.node("Dismiss", exactly: true)).frame
            let leading = LiveSessionSpec.sidePadding + RestBar.horizontalPadding
            #expect(dismiss.minY >= words.maxY - 0.5, "under the words: \(words) \(dismiss)")
            #expect(abs(dismiss.minX - leading) < 2, "leading: \(dismiss)")
            // Beside the bell only: from after the bell to the card's content edge.
            #expect(words.maxX <= 390 - leading + 0.5 && words.width > 390 - 2 * leading - 60, "\(words)")
        }
    }

    // MARK: the custom exercise

    @Test("Add exercise → Custom exercise → Add: the saved exercise is the pick")
    func aCustomExerciseIsPicked() async throws {
        let library = TrainLibrary(store: TrainStore(inMemory: true), remote: { MockTrainSource() }, restore: false)
        var picked: Exercise?
        let sheet = AddExerciseSheet(initialQuery: "Landmine press") { picked = $0 }.environment(library)
        try await HostedWindow.run(width: 390, height: 844, sheet) { w in
            try await w.settle()
            #expect(try #require(w.node("Custom exercise", exactly: true)).activate())
            // The form is a sheet over the list: its elements live beside the host's.
            @MainActor func formNode(_ label: String) -> HostedWindow.Node? { w.presentedNodes()?.first { $0.label == label } }
            try await w.wait("the form") { formNode("Add")?.identifier == "customExercise.add" }
            #expect(formNode("Add")?.isEnabled == true, "named from the search")
            #expect(try #require(formNode("Add")).activate())
            try await w.wait("the pick") { picked != nil }
            #expect(picked?.name == "Landmine press")
            #expect(picked?.isCustom == true)
            #expect(library.exercises.contains { $0.id == picked?.id }, "saved in the library")
        }
    }

    @Test("The custom form: a save still under way when Cancel is tapped hands nothing back")
    func aSlowCustomSaveAfterCancel() async throws {
        let source = GatedCreateSource()
        let library = TrainLibrary(store: TrainStore(inMemory: true), remote: { source }, restore: false)
        var saved: Exercise?
        let form = CustomExerciseForm(name: "Landmine press") { saved = $0 }.environment(library)
        try await HostedWindow.run(width: 390, height: 844, form) { w in
            try await w.settle()
            #expect(try #require(w.node("Add", exactly: true)).activate())
            try await w.wait("the save is under way") { source.creates == 1 }
            #expect(try #require(w.node("Cancel", exactly: true)).activate())
            source.open()
            try await w.wait("the save comes back") { source.answered == 1 }
            try await w.settle()
            #expect(saved == nil, "nothing reaches the workout after Cancel")
            #expect(library.exercises.contains { $0.name == "Landmine press" }, "the library keeps it")
        }
    }

    @Test("The custom form: a slow save without Cancel still hands the exercise back")
    func aSlowCustomSave() async throws {
        let source = GatedCreateSource()
        let library = TrainLibrary(store: TrainStore(inMemory: true), remote: { source }, restore: false)
        var saved: Exercise?
        let form = CustomExerciseForm(name: "Landmine press") { saved = $0 }.environment(library)
        try await HostedWindow.run(width: 390, height: 844, form) { w in
            try await w.settle()
            #expect(try #require(w.node("Add", exactly: true)).activate())
            try await w.wait("the save is under way") { source.creates == 1 }
            source.open()
            try await w.wait("the exercise comes back") { saved != nil }
            #expect(saved?.name == "Landmine press")
        }
    }

    // MARK: Reorder

    @Test("Reorder: a drag moves the workout's exercise to where it's dropped")
    func reorderMoves() async throws {
        let c = SessionSheetsPreview.listDraft()
        defer { c.stop() }
        let names = c.exercises.map(\.name)
        try #require(names.count >= 3)
        // The first exercise dropped on the third row: it ends third.
        var expected = names
        expected.move(fromOffsets: [0], toOffset: 3)
        try await HostedWindow.run(width: 390, height: 844, ReorderSheet(controller: c)) { w in
            try await w.settle()
            let list = try #require(Self.collectionView(in: w.window), "the List's collection view")
            let target = try #require(list.cellForItem(at: IndexPath(item: 2, section: 0)), "the third row")
            // UIKit's own interactive move, as the row's handle drives it: pick up, follow the finger, drop.
            #expect(list.beginInteractiveMovementForItem(at: IndexPath(item: 0, section: 0)), "the row can move")
            list.updateInteractiveMovementTargetPosition(CGPoint(x: target.center.x, y: target.center.y + 4))
            list.endInteractiveMovement()
            try await w.wait("the workout's order follows") { c.exercises.map(\.name) == expected }
            #expect(c.exercises.map(\.position) == Array(0..<names.count), "positions renumbered")
            try await w.settle()
            let first = try #require(w.node(expected[0], exactly: true)).frame
            let third = try #require(w.node(expected[2], exactly: true)).frame
            #expect(first.midY < third.midY, "the rows show the new order: \(first) \(third)")
        }
    }

    private static func collectionView(in view: UIView) -> UICollectionView? {
        if let list = view as? UICollectionView { return list }
        for sub in view.subviews { if let hit = collectionView(in: sub) { return hit } }
        return nil
    }

    // MARK: VoiceOver's order

    @Test("Replace: VoiceOver meets the pinned plan toggle after the header and before the list")
    func replaceReadingOrder() async throws {
        let context = SessionSheetsPreview.replaceContext()
        try await HostedWindow.run(width: 390, height: 844, AddExerciseSheet(replacing: context) { _, _ in }) { w in
            try await w.settle()
            // `nodes()` walks each group's children as SwiftUI hands them to VoiceOver: sorted by their sort priority. Drawn
            // under the list, the bar would come last without it (as it did with the priority one group too deep).
            let labels = w.nodes().map(\.label)
            let title = try #require(labels.firstIndex(of: "Replace \(MockTrain.bench.name)"))
            let toggle = try #require(labels.firstIndex { $0.hasPrefix("Also change the plan") })
            let similar = try #require(labels.firstIndex(of: "Similar"))
            let firstRow = try #require(labels.firstIndex(of: "Incline dumbbell press"), "Similar's first row")
            #expect(title < toggle, "\(labels)")
            #expect(toggle < similar && toggle < firstRow, "\(labels)")
        }
    }
}

/// Demo data's platform whose exercise create waits for `open()`: a slow save. Counts the creates asked for and answered.
final class GatedCreateSource: TrainDataSource, @unchecked Sendable {
    private let base = MockTrainSource()
    private let gate = AsyncStream<Void>.makeStream()
    private let lock = NSLock()
    private var asked = 0, done = 0

    var creates: Int { lock.withLock { asked } }
    var answered: Int { lock.withLock { done } }

    func open() {
        gate.continuation.yield()
        gate.continuation.finish()
    }

    func createExercise(_ e: Exercise) async throws -> Exercise {
        lock.withLock { asked += 1 }
        for await _ in gate.stream { break }
        let saved = try await base.createExercise(e)
        lock.withLock { done += 1 }
        return saved
    }

    func exercises() async throws -> [Exercise] { try await base.exercises() }
    func exerciseHistory(id: UUID) async throws -> ExerciseHistory { try await base.exerciseHistory(id: id) }
    func plans() async throws -> PlansOverview { try await base.plans() }
    func plan(id: UUID) async throws -> Plan { try await base.plan(id: id) }
    func savePlan(_ p: Plan) async throws -> Plan { try await base.savePlan(p) }
    func deletePlan(id: UUID) async throws { try await base.deletePlan(id: id) }
    func enroll(planID: UUID) async throws -> Enrollment { try await base.enroll(planID: planID) }
    func pauseEnrollment() async throws { try await base.pauseEnrollment() }
    func planToday() async throws -> PlanToday? { try await base.planToday() }
    func sessions(from: Date, to: Date) async throws -> [SessionSummary] { try await base.sessions(from: from, to: to) }
    func session(id: UUID) async throws -> TrainSession { try await base.session(id: id) }
    func putSession(_ s: TrainSession) async throws -> SessionPutResult { try await base.putSession(s) }
    func completeSession(id: UUID, _ body: SessionComplete) async throws -> TrainSession {
        try await base.completeSession(id: id, body)
    }
    func deleteSession(id: UUID) async throws { try await base.deleteSession(id: id) }
}
