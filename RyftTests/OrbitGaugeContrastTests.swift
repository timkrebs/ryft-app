import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// WCAG 2.x contrast of the gauge's graphics (1.4.11 asks 3:1), resolved from the asset catalog (dark, the only appearance).
/// Gauge v3 (docs/work/2026-11-16-nocturne/design.md §P3-3): the tracks are `ink` at 7, 13 and 16 % over `background`, and
/// every composite is taken as the 8-bit pixel it lands as (`#1A1C1B`, `#282A28`, `#2F312F`), which is how the design
/// note's numbers were measured.
@MainActor
@Suite struct OrbitGaugeContrastTests {
    private struct RGBA { var r, g, b, a: CGFloat }

    private func resolve(_ colour: Color, _ style: UIUserInterfaceStyle) -> RGBA {
        let ui = UIColor(colour).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var c = RGBA(r: 0, g: 0, b: 0, a: 0)
        ui.getRed(&c.r, green: &c.g, blue: &c.b, alpha: &c.a)
        return c
    }

    /// `top` at `alpha` over an opaque `bottom`, as the 8-bit pixel it lands as.
    private func over(_ top: RGBA, _ alpha: CGFloat, _ bottom: RGBA) -> RGBA {
        func mix(_ t: CGFloat, _ b: CGFloat) -> CGFloat { ((t * alpha + b * (1 - alpha)) * 255).rounded() / 255 }
        return RGBA(r: mix(top.r, bottom.r), g: mix(top.g, bottom.g), b: mix(top.b, bottom.b), a: 1)
    }

    private func luminance(_ c: RGBA) -> Double {
        func lin(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    private func ratio(_ a: RGBA, _ b: RGBA) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func two(_ v: Double) -> String { String(format: "%.2f", v) }

    /// The design note prints two decimals.
    private func printed(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.006 }

    private struct Tracks { var middle, inner, outer: RGBA }

    private func tracks(_ style: UIUserInterfaceStyle) -> Tracks {
        let ink = resolve(OrbitGaugePalette.assets.ink, style), background = resolve(Theme.background, style)
        return Tracks(middle: over(ink, OrbitGaugePalette.middleTrackOpacity, background),
                      inner: over(ink, OrbitGaugePalette.innerTrackOpacity, background),
                      outer: over(ink, OrbitGaugePalette.outerTrackOpacity, background))
    }

    @Test func theTracksAreTheDesignNotesPixels() {
        let t = tracks(.dark)
        func hex(_ c: RGBA) -> String {
            String(format: "%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
        }
        #expect(hex(t.middle) == "1A1C1B")
        #expect(hex(t.inner) == "282A28")
        #expect(hex(t.outer) == "2F312F")
        // 16 % of the ink is the pixel `SurfaceRaised` is.
        #expect(hex(t.outer) == hex(resolve(Theme.surfaceRaised, .dark)))
    }

    @Test func arcsAndDotsReachThreeToOneOnTheirTrack() {
        var lines: [String] = []
        for (name, style) in [("dark", UIUserInterfaceStyle.dark)] {
            let background = resolve(Theme.background, style)
            let t = tracks(style)
            let palette = OrbitGaugePalette.assets
            // Each graphic: on the background and over the track it is drawn on, with the design note's numbers.
            let graphics: [(String, Color, RGBA, String, Double, Double)] = [
                ("Recovery", palette.recovery, t.middle, "7 % ring", 10.66, 9.31),
                ("Sleep", palette.sleep, t.middle, "7 % ring", 6.81, 5.94),
                ("Strain", palette.strain, t.outer, "16 % ticks", 5.94, 3.97),
                ("Strain past its band (alert)", palette.strainPastBand, t.outer, "16 % ticks", 6.09, 4.07),
                ("Volt", palette.signal, t.inner, "13 % ticks", 17.13, 12.63),
            ]
            for (title, colour, track, trackName, onBackgroundExpected, onTrackExpected) in graphics {
                let c = resolve(colour, style)
                let onTrack = ratio(c, track), onBackground = ratio(c, background)
                lines.append("\(name) \(title): on background \(two(onBackground)), over the \(trackName) \(two(onTrack))")
                #expect(onTrack >= 3, "\(name) \(title) over its track")
                #expect(onBackground >= 3, "\(name) \(title) on background")
                #expect(printed(onBackground, onBackgroundExpected), "\(name) \(title) on background: \(two(onBackground))")
                #expect(printed(onTrack, onTrackExpected), "\(name) \(title) over its track: \(two(onTrack))")
            }
            // The lit readiness ticks against the unlit ones: the readiness is told by them.
            let ink = resolve(palette.ink, style)
            let lit = ratio(ink, t.inner)
            #expect(lit >= 3 && printed(lit, 12.79), "\(name) lit vs unlit tick: \(two(lit))")
            #expect(printed(ratio(ink, background), 17.35), "\(name) ink on background")
            lines.append("\(name) lit tick vs unlit tick \(two(lit)); ink on background \(two(ratio(ink, background)))")
            // A dot over its own halo (the colour at 16 % over the background).
            for (title, colour, expected) in [("Recovery", palette.recovery, 7.99), ("Sleep", palette.sleep, 5.55),
                                              ("Strain", palette.strain, 4.95)] as [(String, Color, Double)] {
                let c = resolve(colour, style)
                let halo = over(c, OrbitGaugePalette.haloOpacity, background)
                #expect(ratio(c, halo) >= 3 && printed(ratio(c, halo), expected), "\(name) \(title) dot over its halo")
                lines.append("\(name) \(title) dot over its halo \(two(ratio(c, halo)))")
            }
            for (title, track) in [("7 %", t.middle), ("13 %", t.inner), ("16 %", t.outer)] {
                lines.append("\(name) track \(title) on background \(two(ratio(track, background)))")
            }
        }
        print("ORBIT-CONTRAST\n" + lines.joined(separator: "\n"))
        if let dir = ProcessInfo.processInfo.environment["ORBIT_SHOTS_DIR"] {
            try? lines.joined(separator: "\n").write(toFile: dir + "/contrast.txt", atomically: true, encoding: .utf8)
        }
    }

    /// The calibration's filled segments are `Theme.recovery` on their track (`ink` at 16 %) and on the background.
    @Test func filledCalibrationSegmentsReachThreeToOneOnTrackAndBackground() {
        for (name, style) in [("dark", UIUserInterfaceStyle.dark)] {
            let accent = resolve(OrbitGaugePalette.assets.calibration, style)
            #expect(ratio(accent, tracks(style).outer) >= 3, "\(name) filled segment on its track")
            #expect(ratio(accent, resolve(Theme.background, style)) >= 3, "\(name) filled segment on the background")
            // The palette's calibration colour is the recovery teal the other tests measure.
            #expect(ratio(accent, resolve(Theme.recovery, style)) < 1.001)
        }
    }

    /// Pending draws the previous day at `pendingOpacity` on purpose below 3:1 in places (design.md, PR 2: "yesterday,
    /// not today"; the number carries the value and VoiceOver says it). Pinning the constant makes raising or lowering it
    /// a decision, not an accident; this is not an assertion that 0.6 reaches 3:1. Each mark is measured over the track it
    /// is drawn on: Recovery and Sleep on the 7 % middle ring, Strain on the 16 % outer ticks (never on the 7 % ring, a pairing
    /// the gauge does not draw). On gauge v3, in dark: Strain on the background (2.80) and over its ticks (2.34), and Sleep
    /// over its ring (2.98), are under 3:1 at 0.6; Sleep on the background (3.11) and Recovery (4.38, 4.16) stay over it.
    /// While it breathes the marks dip to 0.75 of that (0.45): Strain over its ticks is then 1.90. That is the documented
    /// dimming, asserted below.
    @Test func pendingOpacityIsPinnedAndIntentionallyBelowThreeToOne() {
        #expect(OrbitGaugeMarks.pendingOpacity == 0.6)
        var lines: [String] = []
        for (name, style) in [("dark", UIUserInterfaceStyle.dark)] {
            let background = resolve(Theme.background, style)
            let t = tracks(style)
            // title, colour, on the background, over its track, the track and its name.
            let cases: [(String, Color, Double, Double, RGBA, String)] = [
                ("recovery", Theme.recovery, 4.38, 4.16, t.middle, "7 % ring"),
                ("sleep", Theme.metricSleep, 3.11, 2.98, t.middle, "7 % ring"),
                ("strain", Theme.metricStrain, 2.80, 2.34, t.outer, "16 % ticks"),
            ]
            for (title, colour, onBackgroundExpected, onTrackExpected, track, trackName) in cases {
                let c = resolve(colour, style)
                let onBackground = ratio(over(c, OrbitGaugeMarks.pendingOpacity, background), background)
                let onTrack = ratio(over(c, OrbitGaugeMarks.pendingOpacity, track), track)
                #expect(printed(onBackground, onBackgroundExpected), "\(name) pending \(title) on background: \(two(onBackground))")
                #expect(printed(onTrack, onTrackExpected), "\(name) pending \(title) over the \(trackName): \(two(onTrack))")
                switch title {
                case "strain":
                    #expect(onBackground < 3, "\(name) pending strain on the background")
                    #expect(onTrack < 3, "\(name) pending strain over the \(trackName)")
                case "sleep":
                    #expect(onTrack < 3, "\(name) pending sleep over the \(trackName)")
                    #expect(onBackground >= 3, "\(name) pending sleep on the background")
                default:
                    #expect(onBackground >= 3 && onTrack >= 3, "\(name) pending recovery")
                }
                lines.append("\(name) pending \(title): background \(two(onBackground)), over the \(trackName) \(two(onTrack))")
            }
            // The breathing low (`phaseAnimator`'s 0.75 of the dimmed marks): the strain is lower still, over the ticks it is on.
            let breathingLow = OrbitGaugeMarks.pendingOpacity * 0.75
            let strain = resolve(Theme.metricStrain, style)
            let low = ratio(over(strain, breathingLow, t.outer), t.outer)
            #expect(abs(breathingLow - 0.45) < 1e-12)
            #expect(printed(low, 1.90) && low < 3, "\(name) breathing strain over the 16 % ticks: \(two(low))")
            lines.append("\(name) pending strain at the breathing low (0.45): over the 16 % ticks \(two(low))")
            // The previous day's number is text in textTertiary: that one must read.
            let tertiary = resolve(Theme.textTertiary, style)
            #expect(ratio(over(tertiary, tertiary.a, background), background) >= 4.5, "\(name) pending number")
        }
        print("ORBIT-PENDING-CONTRAST\n" + lines.joined(separator: "\n"))
    }
}
