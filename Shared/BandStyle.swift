// A score's level as a way of drawing it, not a colour (ADR 0015 §4). Pure, for the app and the widget (ADR 0010):
// the thresholds are `OrbitGaugePalette`'s, the same in both appearances.

/// High, moderate and low read by fill: `solid`, `half`, `outlined`. `none` has no score, so nothing stands in for a level.
enum BandStyle: Hashable, Sendable {
    case solid, half, outlined, none

    init(score: Int?) {
        guard let score else {
            self = .none
            return
        }
        switch score {
        case OrbitGaugePalette.highFrom...: self = .solid
        case OrbitGaugePalette.moderateFrom...: self = .half
        default: self = .outlined
        }
    }
}
