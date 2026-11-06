// The orbit's colours, by asset name, for the app and the widget (ADR 0010). This is the one documented place
// outside `Theme.swift` that names colours: the widget has no `Theme`, so both catalogs carry these colorsets
// under the same names (`scripts/check-shared-types.py` compares their Contents.json).
import SwiftUI

struct OrbitGaugePalette {
    /// The empty scale under every arc (`Theme.surfaceRaised`).
    var track: Color
    /// Recovery, the inner orbit counter-clockwise (`Theme.accent`, teal).
    var recovery: Color
    /// Sleep, the inner orbit clockwise (`Theme.metricSleep`).
    var sleep: Color
    /// Strain, the outer orbit (`Theme.metricStrain`).
    var strain: Color
    /// The centre ring by readiness band: high, moderate, low (`Theme.band(forScore:)`).
    var high: Color
    var moderate: Color
    var low: Color
    /// The filled calibration segments (`Theme.accent`, the teal of the baselines).
    var calibration: Color
    /// The centre ring without a readiness (`Theme.textTertiary`).
    var noReadiness: Color

    /// The asset catalog's colours: the app's and, copied under the same names, the widget's.
    static let assets = OrbitGaugePalette(
        track: Color("SurfaceRaised"), recovery: Color("Accent"), sleep: Color("MetricSleep"),
        strain: Color("MetricStrain"), high: Color("Accent"), moderate: Color("Warning"), low: Color("Alert"), calibration: Color("Accent"),
        noReadiness: Color("TextTertiary"))

    /// The readiness bands' lower bounds, as `Theme.band(forScore:)` and `MetricSpec.scoreBand` draw them.
    static let highFrom = 67
    static let moderateFrom = 34

    /// The centre ring's colour: the band of the readiness, `noReadiness` without one.
    func band(forReadiness readiness: Int?) -> Color {
        switch BandStyle(score: readiness) {
        case .solid: return high
        case .half: return moderate
        case .outlined: return low
        case .none: return noReadiness
        }
    }

    /// The ink of the strain arc and dot past the band's upper end: `alert` itself. One ink with `strain` in light, so
    /// the texture says it (`OrbitGaugeGeometry.PastTexture`), not this colour.
    var strainPastBand: Color { low }

    func colour(of orbit: OrbitGaugeGeometry.Orbit) -> Color {
        switch orbit {
        case .recovery: return recovery
        case .sleep: return sleep
        case .strain: return strain
        }
    }
}
