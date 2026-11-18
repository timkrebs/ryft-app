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
    /// Recovery, the middle orbit counter-clockwise (`Theme.recovery`, teal; the `Recovery` colorset).
    var recovery: Color
    /// Sleep, the middle orbit clockwise (`Theme.metricSleep`).
    var sleep: Color
    /// Strain, the outer orbit (`Theme.metricStrain`).
    var strain: Color
    /// The strain arc, dot and halo past the band's upper end (`Theme.alert`). The v3 gauge draws no readiness band
    /// colour: the lit ticks are `ink`, and the band is a word under the gauge and in the sentence.
    var alert: Color
    /// The filled calibration segments (the recovery teal of the baselines; the `Recovery` colorset).
    var calibration: Color
    /// One colour for every track in place of `ink` at its three strengths; nil (the app, the widget in full colour)
    /// keeps the strengths. The widget's tinted, clear and lock-screen renderings set it (`WidgetOrbitGauge`): the
    /// system turns every colour into one ink there, and the 7 % middle ring would vanish.
    var flatTrack: Color?

    /// The asset catalog's colours: the app's and, copied under the same names, the widget's. Recovery and calibration read
    /// `Recovery`, not `Accent`: the app's interactive accent goes neutral in Nocturne PR 5 and the orbit's teal must not
    /// follow it (design-pr6-c-settings.md, the `OrbitGaugePalette` note).
    static let assets = OrbitGaugePalette(
        ink: Color("TextPrimary"), signal: Color("Signal"), recovery: Color("Recovery"), sleep: Color("MetricSleep"),
        strain: Color("MetricStrain"), alert: Color("Alert"), calibration: Color("Recovery"))

    /// The tracks (design.md §P3-1): the outer ticks and the calibrating segments, the middle ring, the inner ticks.
    static let outerTrackOpacity = 0.16, middleTrackOpacity = 0.07, innerTrackOpacity = 0.13
    /// A dot's halo: its colour at this opacity.
    static let haloOpacity = 0.16

    var outerTrack: Color { flatTrack ?? ink.opacity(Self.outerTrackOpacity) }
    var middleTrack: Color { flatTrack ?? ink.opacity(Self.middleTrackOpacity) }
    var innerTrack: Color { flatTrack ?? ink.opacity(Self.innerTrackOpacity) }

    /// The readiness bands' lower bounds, as `Theme.band(forScore:)` and `MetricSpec.scoreBand` draw them: the widget's
    /// band word (`ReadinessWidget`).
    static let highFrom = 67
    static let moderateFrom = 34

    /// The strain arc, dot and halo past the band's upper end: `alert` itself (design.md §11 on why not a mix).
    var strainPastBand: Color { alert }

    func colour(of orbit: OrbitGaugeGeometry.Orbit) -> Color {
        switch orbit {
        case .recovery: return recovery
        case .sleep: return sleep
        case .strain: return strain
        }
    }
}
