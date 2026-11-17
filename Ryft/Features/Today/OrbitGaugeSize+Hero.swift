// Today's hero gauge (Nocturne PR 4, L14; docs/work/2026-11-16-nocturne/design.md §P4-1 row 6): the 260 pt frame PR 3
// previewed as `.custom(dial: 248)`. One size in every hero state (scored, pending, calibrating, empty), so nothing jumps
// when the state changes. The app's only; the widget keeps its own sizes.
import CoreGraphics

extension OrbitGaugeSize {
    /// Dial 248, frame 260. The halo reaches 3 pt past the frame (133 from the centre against the frame's 130), so the
    /// gauge's container never clips it.
    static let hero = OrbitGaugeSize.custom(dial: TodayLayout.heroDial)
}
