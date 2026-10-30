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
                ("band high (accent)", Theme.accent), ("band moderate (warning)", Theme.warning), ("band low (alert)", Theme.alert),
            ]
            for (title, colour) in graphics {
                let c = resolve(colour, style)
                let onTrack = ratio(c, track), onBackground = ratio(c, background)
                lines.append("\(name) \(title): on track \(String(format: "%.2f", onTrack)), on background \(String(format: "%.2f", onBackground))")
                #expect(onTrack >= 3, "\(name) \(title) on track")
                #expect(onBackground >= 3, "\(name) \(title) on background")
            }
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
}
