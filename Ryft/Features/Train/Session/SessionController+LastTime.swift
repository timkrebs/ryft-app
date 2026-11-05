import Foundation

/// `LocalSessionExercise.lastTime` decodes JSON on every read, and a row reads it about seven times through `ghost`.
extension SessionController {
    /// `ex.lastTime`, decoded once per stored value. Checked against `lastTimeData` on every read, so a replace or an undo
    /// can't serve the old sets. The copy lives here and not on the model: nothing changes the store's schema.
    func lastTime(of ex: LocalSessionExercise) -> [SessionSet] {
        let data = ex.lastTimeData
        if let hit = lastTimeCache[ex.id], hit.data == data { return hit.sets }
        let sets = ex.lastTime
        lastTimeCache[ex.id] = (data, sets)
        return sets
    }
}

extension LocalSessionExercise {
    /// `ghost(forSetAt:)` with the sets already decoded.
    func ghost(forSetAt index: Int, lastTime: [SessionSet]) -> (reps: Int?, kg: Double?) {
        let last = lastTime.filter { !$0.isWarmup }
        if index < last.count { return (last[index].reps, last[index].weightKg) }
        return (targetRepsMin, targetKg ?? last.last?.weightKg)
    }
}
