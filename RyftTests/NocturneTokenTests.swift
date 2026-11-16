import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The Nocturne tokens (docs/work/2026-11-16-nocturne/design.md, ADR 0016): every §2 value pinned as the asset catalog
/// resolves it (±1/255), the one documented deviation (textTertiary 48 %, not 45 %), appearance independence, and the
/// contrast the style promises. A change to any number here is a design decision, not an accident.
@MainActor
@Suite struct NocturneTokenTests {
    struct RGBA {
        var r, g, b, a: Double
    }

    /// The colour as the asset catalog resolves it in `style`.
    static func resolve(_ colour: Color, _ style: UIUserInterfaceStyle = .dark) -> RGBA {
        let ui = UIColor(colour).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }

    static func rgba(_ hex: UInt32, _ alpha: Double = 1) -> RGBA {
        RGBA(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255, a: alpha)
    }

    /// `top` over an opaque `bottom`, in sRGB (how the screen composites it).
    static func over(_ top: RGBA, _ bottom: RGBA) -> RGBA {
        RGBA(r: top.r * top.a + bottom.r * (1 - top.a), g: top.g * top.a + bottom.g * (1 - top.a),
             b: top.b * top.a + bottom.b * (1 - top.a), a: 1)
    }

    static func luminance(_ c: RGBA) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// WCAG 2.x contrast of `foreground` (any alpha) on an opaque `ground`.
    static func ratio(_ foreground: RGBA, on ground: RGBA) -> Double {
        let (a, b) = (luminance(over(foreground, ground)), luminance(ground))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func matches(_ actual: RGBA, _ expected: RGBA) -> Bool {
        let step = 1.0 / 255
        return abs(actual.r - expected.r) <= step && abs(actual.g - expected.g) <= step
            && abs(actual.b - expected.b) <= step && abs(actual.a - expected.a) <= 0.005
    }

    static func describe(_ c: RGBA) -> String {
        String(format: "#%02X%02X%02X @ %.3f", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()),
               Int((c.b * 255).rounded()), c.a)
    }

    // MARK: §2 tokens

    private static let ink: UInt32 = 0xF2F1EC
    /// The screen colour, one constant for the `background` row and the `surfaceRaised` derivation: move one and the other has to move.
    private static let screen: UInt32 = 0x0A0C0B

    /// Every colour of the style, with its value. `textTertiary` is the deviation: the style says 45 %.
    private static var tokens: [(String, Color, RGBA)] {
        [
            ("background", Theme.background, rgba(screen)),
            ("surface", Theme.surface, rgba(0x121514)),
            ("textPrimary", Theme.textPrimary, rgba(ink)),
            ("textSecondary", Theme.textSecondary, rgba(ink, 0.62)),
            ("textTertiary (ADR: 48 %, the style's 45 % is 4.1:1)", Theme.textTertiary, rgba(ink, 0.48)),
            ("separator", Theme.separator, rgba(ink, 0.08)),
            ("surfaceRaised (the 16 % track flattened over background)", Theme.surfaceRaised, over(rgba(ink, 0.16), rgba(screen))),
            ("recovery", Theme.recovery, rgba(0x63D2B4)),
            ("accent", Theme.accent, rgba(0x63D2B4)),
            ("sleep", Theme.metricSleep, rgba(0x9B8AF0)),
            ("strain", Theme.metricStrain, rgba(0x5E8BEA)),
            ("signal", Theme.signal, rgba(0xD8FF4F)),
            ("onSignal", Theme.onSignal, rgba(0x0A0C0B)),
            ("onAccent", Theme.onAccent, rgba(0x0A0C0B)),
            // The legacy names carry the Nocturne values, not their old ones.
            ("graphite", Theme.graphite, rgba(0x0A0C0B)),
            ("slate", Theme.slate, rgba(0x121514)),
            ("mist", Theme.mist, rgba(ink)),
            ("teal", Theme.teal, rgba(0x63D2B4)),
            ("sage", Theme.sage, rgba(0x6EA89A)),
            ("accentSecondary", Theme.accentSecondary, rgba(0x6EA89A)),
            ("warning", Theme.warning, rgba(0xE3C25B)),
            ("alert", Theme.alert, rgba(0xE36B5B)),
            ("stageDeep", Theme.stageDeep, rgba(0x2F55D4)),
            ("stageLight", Theme.stageLight, rgba(0x4F7BE8)),
            ("stageREM", Theme.stageREM, rgba(0x8FB3FF)),
            ("stageAwake", Theme.stageAwake, rgba(0xB8C4D6)),
        ]
    }

    @Test func everyTokenResolvesToItsNocturneValue() {
        for (name, colour, expected) in Self.tokens {
            let actual = Self.resolve(colour)
            #expect(Self.matches(actual, expected), "\(name): \(Self.describe(actual)), expected \(Self.describe(expected))")
        }
    }

    /// The app is dark-only: a colour is one value, the same in a light trait collection.
    @Test func noTokenDependsOnTheAppearance() {
        for (name, colour, _) in Self.tokens {
            let dark = Self.resolve(colour, .dark), light = Self.resolve(colour, .light)
            #expect(Self.matches(light, dark), "\(name): light \(Self.describe(light)) differs from dark \(Self.describe(dark))")
        }
    }

    /// The legend: the orbit's three colours are the ones the rings, tiles and trends use, and `recovery` is `accent`.
    @Test func theLegendIsThreeDistinctColours() {
        let legend = [Theme.recovery, Theme.metricSleep, Theme.metricStrain].map { Self.resolve($0) }
        for i in legend.indices {
            for j in legend.indices where j > i {
                #expect(!Self.matches(legend[i], legend[j]), "legend colours \(i) and \(j) are the same")
            }
        }
        #expect(Self.matches(Self.resolve(Theme.recovery), Self.resolve(Theme.accent)))
    }

    // MARK: contrast

    private static var grounds: [(String, RGBA)] {
        [("background", Self.resolve(Theme.background)), ("surface", Self.resolve(Theme.surface))]
    }

    /// Text reaches 4.5:1 on the screen and on the neutral tile.
    @Test func textReachesFourPointFiveToOne() {
        let text = [("textPrimary", Theme.textPrimary), ("textSecondary", Theme.textSecondary),
                    ("textTertiary", Theme.textTertiary)]
        for (name, colour) in text {
            let c = Self.resolve(colour)
            for (groundName, ground) in Self.grounds {
                let r = Self.ratio(c, on: ground)
                #expect(r >= 4.5, "\(name) on \(groundName): \(String(format: "%.2f", r))")
            }
        }
        #expect(Self.ratio(Self.resolve(Theme.onAccent), on: Self.resolve(Theme.accent)) >= 4.5)
        #expect(Self.ratio(Self.resolve(Theme.onSignal), on: Self.resolve(Theme.signal)) >= 4.5)
    }

    /// A raised fill (`surfaceRaised`, opaque `#2F312F`) carries `textPrimary` and `textSecondary`, never `textTertiary`
    /// (ADR 0016 §2.5): the tertiary ratio is below 4.5 on it, so no text may sit there in that colour.
    @Test func raisedFillsCarryPrimaryAndSecondaryText() {
        let raised = Self.resolve(Theme.surfaceRaised)
        #expect(raised.a == 1, "surfaceRaised is opaque")
        #expect(Self.ratio(Self.resolve(Theme.textPrimary), on: raised) >= 4.5)
        #expect(Self.ratio(Self.resolve(Theme.textSecondary), on: raised) >= 4.5)
        #expect(Self.ratio(Self.resolve(Theme.textTertiary), on: raised) < 4.5, "the rule's reason: tertiary is under 4.5")
        // Graphics (glyphs, outlines) need 3:1.
        #expect(Self.ratio(Self.resolve(Theme.textTertiary), on: raised) >= 3)
    }

    /// The metric and signal colours are graphics (WCAG 1.4.11, 3:1) on both grounds; so are the band colours.
    @Test func metricAndSignalColoursReachThreeToOne() {
        let graphics = [("recovery", Theme.recovery), ("sleep", Theme.metricSleep), ("strain", Theme.metricStrain),
                        ("signal", Theme.signal), ("warning", Theme.warning), ("alert", Theme.alert),
                        ("accentSecondary", Theme.accentSecondary)]
        for (name, colour) in graphics {
            let c = Self.resolve(colour)
            for (groundName, ground) in Self.grounds {
                let r = Self.ratio(c, on: ground)
                #expect(r >= 3, "\(name) on \(groundName): \(String(format: "%.2f", r))")
            }
        }
    }

    /// ADR 0016: the style's 45 % for `textTertiary` is 4.1:1 on both grounds; 48 % is the lowest whole percent that
    /// reaches 4.5:1 on both, and the catalog carries it.
    @Test func tertiaryIsTheLowestWholePercentThatPasses() {
        func passes(_ percent: Int) -> Bool {
            let c = Self.rgba(Self.ink, Double(percent) / 100)
            return Self.grounds.allSatisfy { Self.ratio(c, on: $0.1) >= 4.5 }
        }
        #expect(!passes(45), "the style's 45 % would pass: the deviation is not needed")
        #expect(!passes(47))
        #expect(passes(48))
        #expect(Self.resolve(Theme.textTertiary).a >= 0.48 - 0.005)
    }

    /// The neutral tile is a step above the screen, not a second background.
    @Test func surfaceSitsJustAboveTheBackground() {
        let r = Self.ratio(Self.resolve(Theme.surface), on: Self.resolve(Theme.background))
        #expect(r > 1.05 && r < 1.2, "surface on background \(r)")
    }

    // MARK: type

    /// The §2 scale as the roles carry it: titles and numbers Light, text Regular, buttons Medium.
    @Test func theTypeScaleIsTheStyles() {
        let scale: [(RyftTextStyle, CGFloat, Font.Weight)] = [
            (.display, 52, .light), (.numberLarge, 34, .light), (.title, 26, .light), (.metric, 26, .light),
            (.headline, 17, .medium), (.body, 16, .regular), (.callout, 15, .regular), (.button, 16, .medium),
            (.label, 13, .regular), (.caption, 12, .regular), (.axis, 11, .regular), (.tab, 11, .regular),
            (.wordmark, 15, .light),
        ]
        for (style, size, weight) in scale {
            #expect(style.size == size, "\(style) size")
            #expect(style.weight == weight, "\(style) weight")
        }
    }

    @Test func lightWeightsUseSatoshiLight() {
        for weight in [Font.Weight.light, .thin, .ultraLight] {
            #expect(RyftFonts.postScriptName(for: weight) == "Satoshi-Light")
        }
        #expect(RyftFonts.postScriptName(for: .regular) == "Satoshi-Regular")
        #expect(RyftFonts.postScriptName(for: .medium) == "Satoshi-Medium")
        #expect(RyftFonts.postScriptName(for: .bold) == "Satoshi-Bold")
    }

    /// A number is Light from 20 pt; below that Regular, which stays legible on a dark screen.
    @Test func numbersAreLightFromTwentyPoints() {
        #expect(RyftFonts.numberWeight(forSize: 52) == .light)
        #expect(RyftFonts.numberWeight(forSize: 20) == .light)
        #expect(RyftFonts.numberWeight(forSize: 19) == .regular)
        #expect(RyftFonts.numberWeight(forSize: 11) == .regular)
    }

    /// Satoshi Light is registered with the app; the file itself is git-ignored (`make fonts`), so only the
    /// Info.plist entry is checked, not whether the face loads.
    @Test func satoshiLightIsRegisteredInInfoPlist() {
        let fonts = Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String] ?? []
        #expect(fonts.contains("Satoshi-Light.otf"), "UIAppFonts: \(fonts)")
        for weight in ["Regular", "Medium", "Bold"] { #expect(fonts.contains("Satoshi-\(weight).otf")) }
    }
}
