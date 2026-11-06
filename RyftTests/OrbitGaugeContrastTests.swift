import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// WCAG 2.x contrast of the gauge's graphics (1.4.11 asks 3:1), resolved from the asset catalog in both appearances.
@MainActor
@Suite struct OrbitGaugeContrastTests {
    private struct RGBA { var r, g, b, a: CGFloat }

    private func resolve(_ colour: Color, _ style: UIUserInterfaceStyle) -> RGBA {
        let ui = UIColor(colour).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var c = RGBA(r: 0, g: 0, b: 0, a: 0)
        ui.getRed(&c.r, green: &c.g, blue: &c.b, alpha: &c.a)
        return c
    }

    private func over(_ top: RGBA, _ bottom: RGBA) -> RGBA {
        RGBA(r: top.r * top.a + bottom.r * (1 - top.a), g: top.g * top.a + bottom.g * (1 - top.a),
             b: top.b * top.a + bottom.b * (1 - top.a), a: 1)
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

    @Test func arcsAndDotsReachThreeToOneOnTheirTrack() {
        var lines: [String] = []
        for (name, style) in [("dark", UIUserInterfaceStyle.dark), ("light", .light)] {
            let background = resolve(Theme.background, style)
            let track = resolve(Theme.surfaceRaised, style)
            let graphics: [(String, Color)] = [
                ("Recovery (accent)", Theme.accent), ("Sleep", Theme.metricSleep), ("Strain", Theme.metricStrain),
                ("band high (accent)", Theme.accent), ("band low (alert)", Theme.alert),
            ]
            for (title, colour) in graphics {
                let c = resolve(colour, style)
                let onTrack = ratio(c, track), onBackground = ratio(c, background)
                lines.append("\(name) \(title): on track \(String(format: "%.2f", onTrack)), on background \(String(format: "%.2f", onBackground))")
                #expect(onTrack >= 3, "\(name) \(title) on track")
                #expect(onBackground >= 3, "\(name) \(title) on background")
            }
            // Moderate on the background only: a scored ring has no track under it, and light's `Warning` is 2.90:1 on the
            // track. `BandStyleTests.theRingIsDrawnByItsLevel` pins the gap between its dashes as the background.
            let moderate = ratio(resolve(Theme.warning, style), background)
            lines.append("\(name) band moderate (warning): on background \(String(format: "%.2f", moderate))")
            #expect(moderate >= 3, "\(name) band moderate on background")
            let primary = over(resolve(Theme.textTertiary, style), background)
            #expect(ratio(primary, background) >= 3, "\(name) centre ring without readiness")
            lines.append("\(name) centre ring without readiness (textTertiary): on background \(String(format: "%.2f", ratio(primary, background)))")
            lines.append("\(name) track on background \(String(format: "%.2f", ratio(track, background)))")
        }
        print("ORBIT-CONTRAST\n" + lines.joined(separator: "\n"))
        if let dir = ProcessInfo.processInfo.environment["ORBIT_SHOTS_DIR"] {
            try? lines.joined(separator: "\n").write(toFile: dir + "/contrast.txt", atomically: true, encoding: .utf8)
        }
    }

    /// The calibration's filled segments are `Theme.accent` on the track and on the background (design.md, PR 2).
    @Test func filledCalibrationSegmentsReachThreeToOneOnTrackAndBackground() {
        for (name, style) in [("dark", UIUserInterfaceStyle.dark), ("light", .light)] {
            let accent = resolve(OrbitGaugePalette.assets.calibration, style)
            #expect(ratio(accent, resolve(Theme.surfaceRaised, style)) >= 3, "\(name) filled segment on its track")
            #expect(ratio(accent, resolve(Theme.background, style)) >= 3, "\(name) filled segment on the background")
            // The palette's calibration colour is the accent the other tests measure.
            #expect(ratio(accent, resolve(Theme.accent, style)) < 1.001)
        }
    }

    /// Pending draws the previous day at `pendingOpacity`, secondary on purpose: the number carries the state at >= 4.5:1 and
    /// VoiceOver says it. The arcs have a floor, so thinning them is a decision, and a ceiling against their full colour, so
    /// pending stays dimmer than a scored day. The floor holds at rest; the breath's trough goes under it until PR 3 deletes
    /// this opacity for the dashed drawing.
    @Test func pendingOpacityIsPinnedAndTheNumberCarriesTheState() {
        #expect(OrbitGaugeMarks.pendingOpacity == 0.6)
        var lines: [String] = []
        for (name, style) in [("dark", UIUserInterfaceStyle.dark), ("light", .light)] {
            let background = resolve(Theme.background, style)
            let track = resolve(Theme.surfaceRaised, style)
            for (title, colour) in [("accent", Theme.accent), ("sleep", Theme.metricSleep), ("strain", Theme.metricStrain)] {
                var c = resolve(colour, style)
                let full = ratio(c, track)
                c.a = OrbitGaugeMarks.pendingOpacity
                let onTrack = ratio(over(c, track), track)
                lines.append("\(name) pending \(title): over track \(String(format: "%.2f", onTrack)), \(String(format: "%.2f", onTrack / full)) of full")
                #expect(onTrack >= 2.0, "\(name) \(title) over the track: \(onTrack)")
                #expect(onTrack < 0.7 * full, "\(name) \(title) stays dimmer than full: \(onTrack) of \(full)")
            }
            // The previous day's number is text in textTertiary: that one must read.
            #expect(ratio(over(resolve(Theme.textTertiary, style), background), background) >= 4.5, "\(name) pending number")
        }
        print("ORBIT-PENDING-CONTRAST\n" + lines.joined(separator: "\n"))
    }
}
