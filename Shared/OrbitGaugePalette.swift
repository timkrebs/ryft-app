// The orbit's colours, by asset name, for the app and the widget (ADR 0010). This is the one documented place
// outside `Theme.swift` that names colours: the widget has no `Theme`, so both catalogs carry these colorsets
// under the same names (`scripts/check-shared-types.py` compares their Contents.json).
import SwiftUI

struct OrbitGaugePalette {
    /// The ink (`Theme.textPrimary`): the lit readiness ticks, and every track at its strength (`outerTrackOpacity`,
    /// `middleTrackOpacity`, `innerTrackOpacity`). 16 % of it over `background` is the pixel `SurfaceRaised` is.
    var ink: Color
    /// The readiness marker on the inner ring, and nothing else in the gauge (`Theme.signal`, Volt; ADR 0016, 2.2).
    var signal: Color
    /// Recovery, the middle orbit counter-clockwise (`Theme.recovery`, teal).
    var recovery: Color
    /// Sleep, the middle orbit clockwise (`Theme.metricSleep`).
    var sleep: Color
    /// Strain, the outer orbit (`Theme.metricStrain`).
    var strain: Color
    /// The readiness bands: high, moderate, low (`Theme.band(forScore:)`). The v3 gauge draws no band colour (the lit
    /// ticks are `ink`; the band is a word under the gauge and in the sentence); `low` is still the strain past its band.
    var high: Color
    var moderate: Color
    var low: Color
    /// The filled calibration segments (`Theme.accent`, the teal of the baselines).
    var calibration: Color
    /// `band(forReadiness: nil)` (`Theme.textTertiary`).
    var noReadiness: Color
    /// One colour for every track in place of `ink` at its three strengths; nil (the app, the widget in full colour)
    /// keeps the strengths. The widget's tinted, clear and lock-screen renderings set it (`WidgetOrbitGauge`): the
    /// system turns every colour into one ink there, and the 7 % middle ring would vanish.
    var flatTrack: Color?

    /// The asset catalog's colours: the app's and, copied under the same names, the widget's.
    static let assets = OrbitGaugePalette(
        ink: Color("TextPrimary"), signal: Color("Signal"), recovery: Color("Accent"), sleep: Color("MetricSleep"),
        strain: Color("MetricStrain"), high: Color("Accent"), moderate: Color("Warning"), low: Color("Alert"),
        calibration: Color("Accent"), noReadiness: Color("TextTertiary"))

    /// The tracks (design.md §P3-1): the outer ticks and the calibrating segments, the middle ring, the inner ticks.
    static let outerTrackOpacity = 0.16, middleTrackOpacity = 0.07, innerTrackOpacity = 0.13
    /// A dot's halo: its colour at this opacity.
    static let haloOpacity = 0.16

    var outerTrack: Color { flatTrack ?? ink.opacity(Self.outerTrackOpacity) }
    var middleTrack: Color { flatTrack ?? ink.opacity(Self.middleTrackOpacity) }
    var innerTrack: Color { flatTrack ?? ink.opacity(Self.innerTrackOpacity) }

    /// The readiness bands' lower bounds, as `Theme.band(forScore:)` and `MetricSpec.scoreBand` draw them.
    static let highFrom = 67
    static let moderateFrom = 34

    /// The band of a readiness, `noReadiness` without one.
    func band(forReadiness readiness: Int?) -> Color {
        guard let readiness else { return noReadiness }
        switch readiness {
        case Self.highFrom...: return high
        case Self.moderateFrom...: return moderate
        default: return low
        }
    }

    /// The strain arc, dot and halo past the band's upper end: `alert` itself (design.md §11 on why not a mix).
    var strainPastBand: Color { low }

    func colour(of orbit: OrbitGaugeGeometry.Orbit) -> Color {
        switch orbit {
        case .recovery: return recovery
        case .sleep: return sleep
        case .strain: return strain
        }
    }
}
