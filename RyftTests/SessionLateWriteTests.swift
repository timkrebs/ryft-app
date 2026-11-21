import Foundation
import SwiftData
import Testing
@testable import Ryft

/// A pick or a replace that arrives once the workout is over (a slow custom save that comes back after Finish, Discard or an
/// account change) changes nothing: `SessionController.add` and `replace` act only while the session is underway.
@MainActor
struct SessionLateWriteTests {
    @Test("While the workout is underway an add adds a row")
    func anAddWhileUnderway() throws {
        let rig = ReplaceRig()
        let count = rig.controller.exercises.count
        let row = try #require(rig.controller.add(MockTrain.plank))
        #expect(rig.controller.exercises.count == count + 1)
        #expect(rig.controller.exercises.last?.id == row.id)
    }

    @Test("A late add after Finish changes nothing")
    func aLateAddAfterFinish() async {
        let rig = ReplaceRig()
        let c = rig.controller
        let before = c.exercises.map(\.id)
        _ = await c.finish()
        let stamp = rig.session.updatedAt
        let ops = rig.store.pendingOps().count

        #expect(c.add(MockTrain.plank) == nil)
        #expect(c.exercises.map(\.id) == before)
        #expect(rig.session.updatedAt == stamp, "the finished session isn't written again")
        #expect(rig.store.pendingOps().count == ops, "nothing queued")
    }

    /// Discard deletes the session and, by cascade, its rows; what the deleted session's relationship still holds after that is
    /// in no fixed order (any part of the rows, or none), so the store is what's checked: no row for the late pick, nothing left.
    @Test("A late add after Discard changes nothing")
    func aLateAddAfterDiscard() throws {
        let rig = ReplaceRig()
        let c = rig.controller
        let sessionID = rig.session.id
        c.discard()
        #expect(c.add(MockTrain.plank) == nil)
        let rows = try rig.store.context.fetch(FetchDescriptor<LocalSessionExercise>())
        #expect(!rows.contains { $0.exerciseId == MockTrain.plank.id }, "no row for the late pick")
        #expect(rows.isEmpty, "the discarded session's rows went with it: \(rows.map(\.name))")
        #expect(try rig.store.context.fetch(FetchDescriptor<LocalSession>()).allSatisfy { $0.id != sessionID })
        #expect(rig.store.pendingOps().allSatisfy { $0.sessionId != sessionID }, "nothing queued for it")
    }

    @Test("A late add after the controller stopped (an account change) changes nothing")
    func aLateAddAfterStop() {
        let rig = ReplaceRig()
        let c = rig.controller
        let before = c.exercises.map(\.id)
        c.stop()
        #expect(!c.isUnderway)
        #expect(c.add(MockTrain.plank) == nil)
        #expect(c.exercises.map(\.id) == before)
    }

    @Test("A late replace after Finish changes nothing")
    func aLateReplaceAfterFinish() async {
        let rig = ReplaceRig()
        let c = rig.controller
        let x = rig.x
        let exerciseID = x.exerciseId, name = x.name
        let rows = c.exercises.map(\.id)
        _ = await c.finish()
        let stamp = rig.session.updatedAt

        await c.replaceExercise(x, with: rig.incline)
        #expect(x.exerciseId == exerciseID && x.name == name)
        #expect(c.exercises.map(\.id) == rows)
        #expect(c.undo == nil, "no toast offers an undo")
        #expect(rig.session.updatedAt == stamp)
    }
}
