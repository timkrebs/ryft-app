import SwiftUI

// A card whose last time has more sets than the line lists: the first five, then "+2 more" (beta feedback 2, §4).
// In its own file and store so the live session previews keep theirs.

#Preview("Exercise card · last time over five sets", traits: .sizeThatFitsLayout) {
    let store = TrainStore(inMemory: true)
    let session = SessionFactory.empty(in: store)
    let card = SessionFactory.add(MockTrain.lateral, to: session, sets: 3, in: store)
    card.lastTime = (0..<7).map { i in SessionSet(setIndex: i, reps: 15 - i, weightKg: i < 4 ? 10 : 8) }
    let controller = SessionController(session: session, sync: TrainPreview.sync, liveActivity: nil)
    return SchemePair {
        ExerciseCard(controller: controller, exercise: card, onPlates: {}, onHistory: {})
    }
}
