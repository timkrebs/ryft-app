import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// OrbitGauge PR 4: today's strain band, the pure decisions (geometry, tone, size rule), the colours' contrast, the
/// spoken sentence and the widget's contract. The pixels are in `OrbitGaugeBandRenderTests`. Synthetic values only:
/// 71 / 71 % / 88 % / 9.6 with the band 8 to 13.
@Suite("OrbitGauge band: decisions")
struct OrbitGaugeBandTests {
    typealias G = OrbitGaugeGeometry

    private static let band: ClosedRange<Double> = 8...13
    // A NaN bound cannot be built: `ClosedRange` traps on it even through `uncheckedBounds` in a debug build. The
    // non-finite bounds that can reach the gauge are the infinities.

    // MARK: 1. geometry

    @Test func theRailsEndsAreWhereAnArcOfThoseStrainsEnds() throws {
        let rail = try #require(G.bandRail(for: Self.band))
        #expect(abs(rail.start - G.Orbit.strain.headDegrees(for: 8.0 / 21)) < 1e-9)
        #expect(abs(rail.end - G.Orbit.strain.headDegrees(for: 13.0 / 21)) < 1e-9)
        // The numbers the design note gives: 8 -> 137.14, 13 -> 222.86 degrees clockwise from the top.
        #expect(abs(rail.start - 137.14) < 0.01)
        #expect(abs(rail.end - 222.86) < 0.01)
        #expect(abs(rail.sweep - (rail.end - rail.start)) < 1e-9 && rail.sweep > 0)
        // And an arc whose strain is the band's upper end ends exactly there.
        let values = OrbitGaugeValues(strain: 13)
        #expect(abs(G.Orbit.strain.headDegrees(for: try #require(values.strainFraction)) - rail.end) < 1e-9)
    }

    @Test func theRailClampsToTheScale() throws {
        let low = try #require(G.bandRail(for: -4...6))
        #expect(low.start == 0)
        #expect(abs(low.end - G.Orbit.strain.headDegrees(for: 6.0 / 21)) < 1e-9)
        let high = try #require(G.bandRail(for: 15...40))
        #expect(abs(high.start - G.Orbit.strain.headDegrees(for: 15.0 / 21)) < 1e-9)
        #expect(abs(high.end - G.Orbit.strain.headDegrees(for: 1)) < 1e-9)
        #expect(G.clampedBand(-4...6) == 0...6)
        #expect(G.clampedBand(15...40) == 15...21)
        #expect(G.clampedBand(-5...50) == 0...21)
        #expect(G.clampedBand(Self.band) == Self.band)
    }

    @Test(arguments: [
        ("nil", nil as ClosedRange<Double>?),
        ("wholly above the scale", 22...30),
        ("wholly below the scale", -9 ... -1),
        ("touching 21 from above", 21...30),
        ("touching 0 from below", -3...0),
        ("a one-point band", 10...10),
        ("a one-point band at 21", 21...21),
        ("infinite lower", -Double.infinity...5),
        ("infinite upper", 8...Double.infinity),
        ("infinite both", -Double.infinity...Double.infinity),
    ])
    func anUnusableBandGivesNoRailAndNoSpeech(_ name: String, _ band: ClosedRange<Double>?) {
        #expect(G.clampedBand(band) == nil, "\(name)")
        #expect(G.bandRail(for: band) == nil, "\(name)")
        #expect(G.strainPastBandDegrees(strain: 15, band: band) == nil, "\(name)")
        for dial in [72, 112, 160, 400] as [CGFloat] {
            #expect(!G.drawsBandRail(band, dial: dial), "\(name) at \(dial)")
        }
    }

    /// Between the outer ring's inner edge and the inner dots' outer edge, clear of both, at every size that draws it.
    @Test(arguments: [90, 100, 112, 124, 160, 172, 220, 300] as [CGFloat])
    func theRailSitsInTheAirBetweenTheOuterRingAndTheInnerDots(_ dial: CGFloat) {
        #expect(G.drawsBandRail(Self.band, dial: dial))
        let m = G.metrics(forDial: dial)
        let ringInner = m.outerRadius - m.outerStroke / 2
        let dotsOuter = m.innerRadius + m.dotRadius
        let railOuter = m.bandRadius + m.bandStroke / 2
        let railInner = m.bandRadius - m.bandStroke / 2
        #expect(railOuter < ringInner, "air to the outer ring at \(dial): \(ringInner - railOuter)")
        #expect(railInner > dotsOuter, "air to the inner dots at \(dial): \(railInner - dotsOuter)")
        #expect(ringInner - railOuter > 0.5 && railInner - dotsOuter > 0.5, "visible air at \(dial)")
        #expect(m.bandStroke >= G.minStroke / 2 && m.bandStroke < m.outerStroke, "thinner than the ring at \(dial)")
        // 69.5 on the 160 dial, scaled.
        #expect(abs(m.bandRadius - 69.5 * dial / G.referenceDial) < 1e-9)
    }

    // MARK: 2. tone

    private func values(strain: Double?, band: ClosedRange<Double>? = Self.band) -> OrbitGaugeValues {
        OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: strain, strainBand: band)
    }

    @Test(arguments: [
        ("below the band", 4.0, true), ("at its lower end", 8.0, true), ("inside", 9.6, true),
        ("exactly at its upper end", 13.0, true), ("zero", 0.0, true),
        ("just above", 13.01, false), ("well above", 16.5, false), ("the top of the scale", 21.0, false),
        ("beyond the scale", 25.0, false),
    ] as [(String, Double, Bool)])
    func theToneShiftsOnlyAboveTheUpperEnd(_ name: String, _ strain: Double, _ plain: Bool) {
        let v = values(strain: strain)
        #expect(G.strainTone(v) == (plain ? .plain : .pastBand), "\(name)")
        // The arc's turn point agrees with the tone: the band's end when past, nothing otherwise.
        let degrees = G.strainPastBandDegrees(strain: strain, band: Self.band)
        #expect((degrees == nil) == plain, "\(name)")
        if let degrees { #expect(abs(degrees - 222.86) < 0.01, "\(name)") }
    }

    @Test func theToneIsPlainWithoutStrainOrWithoutABand() {
        #expect(G.strainTone(values(strain: nil)) == .plain)
        #expect(G.strainTone(values(strain: 20, band: nil)) == .plain)
        #expect(G.strainTone(values(strain: 20, band: 30...40)) == .plain)
        #expect(G.strainTone(values(strain: .nan)) == .plain)
        #expect(G.strainTone(values(strain: .infinity)) == .plain)
        #expect(G.strainPastBandDegrees(strain: nil, band: Self.band) == nil)
    }

    @Test func theToneFollowsTheClampedUpperEnd() {
        // 15...40 is 15...21 on the scale: nothing is above it.
        #expect(G.strainTone(values(strain: 21, band: 15...40)) == .plain)
        #expect(G.strainTone(values(strain: 14.9, band: 15...40)) == .plain)
        #expect(G.strainTone(values(strain: 21, band: 0...20)) == .pastBand)
    }

    // MARK: the split line

    @Test func theSplitIsTheBandsUpperEndWhateverTheStrain() throws {
        let split = try #require(G.strainSplitDegrees(band: Self.band))
        #expect(abs(split - 222.86) < 0.01)
        #expect(split == G.bandRail(for: Self.band)?.end)
        // It does not take the strain: the drawing is one structure whether the arc is past it or not.
        for strain in [4.0, 13.0, 16.5] as [Double] {
            #expect(G.strainPastBandDegrees(strain: strain, band: Self.band) == (strain > 13 ? split : nil))
        }
        #expect(abs(try #require(G.strainSplitDegrees(band: 18...40)) - G.Orbit.strain.headDegrees(for: 1)) < 1e-9)
        for band in [nil, 22...30, 10...10, -9 ... -1, -Double.infinity...Double.infinity] as [ClosedRange<Double>?] {
            #expect(G.strainSplitDegrees(band: band) == nil)
        }
    }

    // MARK: the wedge

    @Test func aWedgeThatDoesNotPassItsStartIsEmpty() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(OrbitWedge(from: 10, to: 10).path(in: rect).isEmpty)
        #expect(OrbitWedge(from: 200, to: 100).path(in: rect).isEmpty, "no wrap the long way round")
        #expect(OrbitWedge(from: 0, to: -8).path(in: rect).isEmpty)
        let wedge = OrbitWedge(from: 90, to: 180).path(in: rect)
        #expect(!wedge.isEmpty)
        // 3 to 6 o'clock from the centre: the lower right quadrant, never the left half.
        #expect(wedge.boundingRect.minX >= 49 && wedge.boundingRect.minY >= 49)
    }

    // MARK: 3. size rule

    @Test func noRailBelowNinetyPointsButOnMediumAndLarge() {
        #expect(G.minDialForBandRail == 90)
        #expect(!G.drawsBandRail(Self.band, dial: OrbitGauge.Size.small.dial))
        #expect(!G.drawsBandRail(Self.band, dial: 89.99))
        #expect(G.drawsBandRail(Self.band, dial: 90))
        #expect(G.drawsBandRail(Self.band, dial: OrbitGauge.Size.medium.dial))
        #expect(G.drawsBandRail(Self.band, dial: OrbitGauge.Size.large.dial))
        #expect(!G.drawsBandRail(Self.band, dial: 44))
    }

    @Test func theToneStillShiftsAtSmall() {
        // The decision has no dial in it, so the shift is the same at every size.
        #expect(!G.drawsBandRail(Self.band, dial: OrbitGauge.Size.small.dial))
        #expect(G.strainTone(values(strain: 16.5)) == .pastBand)
        #expect(G.strainPastBandDegrees(strain: 16.5, band: Self.band) != nil)
    }

    // MARK: 6. contrast

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

    private static let styles: [(String, UIUserInterfaceStyle)] = [("dark", .dark), ("light", .light)]

    @MainActor
    @Test func theColourPastTheBandIsAlertAndReachesThreeToOneOnTheTrack() {
        let palette = OrbitGaugePalette.assets
        for (name, style) in Self.styles {
            let past = resolve(palette.strainPastBand, style)
            #expect(ratio(past, resolve(Theme.alert, style)) < 1.001, "\(name): it is alert itself")
            #expect(ratio(past, resolve(Theme.surfaceRaised, style)) >= 3, "\(name) on the track")
            #expect(ratio(past, resolve(Theme.background, style)) >= 3, "\(name) on the background")
            // And it differs from the in-band strain colour, or the shift would say nothing.
            let plain = resolve(palette.strain, style)
            let apart = abs(past.r - plain.r) + abs(past.g - plain.g) + abs(past.b - plain.b)
            #expect(apart > 0.5, "\(name) alert against strain: \(apart)")
        }
    }

    @MainActor
    @Test func theRailsOpacityIsPinnedAndItsRatioStaysAboveTwo() {
        #expect(G.bandRailOpacity == 0.5)
        for (name, style) in Self.styles {
            var rail = resolve(OrbitGaugePalette.assets.strain, style)
            rail.a = G.bandRailOpacity
            let background = resolve(Theme.background, style)
            let onBackground = ratio(over(rail, background), background)
            // Below 3:1 on purpose (design.md §11: the scale of the target, the arc carries the value); a floor
            // of 2.0 makes thinning it out a decision, not an accident.
            #expect(onBackground >= 2.0, "\(name) rail on the background: \(onBackground)")
            #expect(onBackground < 3, "\(name): documented as sub-3:1, so a change to this needs a design decision")
        }
    }

    // MARK: 7. VoiceOver

    /// "9.6" or "9,6": the simulator's region decides, as the existing sentence test notes.
    private func one(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) }
    private func upToOne(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }

    @Test func withABandTheStrainSentenceNamesTheRange() {
        let expected = "Strain \(one(9.6)) of 21, today's recommended range \(upToOne(8)) to \(upToOne(13))"
        #expect(OrbitGauge.spokenStrain(9.6, band: Self.band) == expected)
        #expect(expected.hasPrefix("Strain 9") && expected.hasSuffix("range 8 to 13"), "whole ends without a decimal: \(expected)")
        #expect(OrbitGauge.spokenValue(.previewBanded(strain: 9.6)).hasSuffix(expected))
        #expect(OrbitGauge.spokenValue(.previewBanded(strain: 9.6)).hasPrefix("71, High. Recovery 71 percent, Sleep 88 percent, "))
    }

    @Test func aboveTheBandTheSentenceSaysAbove() {
        let above = "Strain \(one(16.5)) of 21, above today's recommended range \(upToOne(8)) to \(upToOne(13))"
        #expect(OrbitGauge.spokenStrain(16.5, band: Self.band) == above)
        #expect(above.hasSuffix("above today's recommended range 8 to 13"))
        #expect(OrbitGauge.spokenValue(.previewBanded(strain: 16.5)).hasSuffix(above))
        #expect(OrbitGauge.spokenStrain(21, band: Self.band).contains("above today's"))
        // Exactly at the upper end, and below or inside it: the plain range sentence.
        for strain in [4.0, 9.6, 13.0] as [Double] {
            let spoken = OrbitGauge.spokenStrain(strain, band: Self.band)
            #expect(spoken == "Strain \(one(strain)) of 21, today's recommended range 8 to 13", "strain \(strain)")
            #expect(!spoken.contains("above"))
        }
        // The clamped band decides: nothing is above 15...21.
        #expect(!OrbitGauge.spokenStrain(21, band: 15...40).contains("above"))
    }

    @Test func theEndsShowAtMostOneDecimalAndFollowTheClamp() {
        #expect(OrbitGauge.spokenStrain(9.6, band: 8.5...12.25).hasSuffix("range \(upToOne(8.5)) to \(upToOne(12.25))"))
        #expect(OrbitGauge.spokenStrain(9.6, band: 8.5...12.25).contains("12") && !OrbitGauge.spokenStrain(9.6, band: 8.5...12.25).contains("12.25"))
        // As drawn: clamped to the scale.
        #expect(OrbitGauge.spokenStrain(9.6, band: -3...30).hasSuffix("range 0 to 21"))
    }

    @Test func withoutAUsableBandTheSentenceIsTheOldOne() {
        let old = "Strain \(one(9.6)) of 21"
        #expect(OrbitGauge.spokenStrain(9.6, band: nil) == old)
        let unusable: [ClosedRange<Double>] = [30...40, 10...10, -5 ... -1]
        for (i, band) in unusable.enumerated() {
            #expect(OrbitGauge.spokenStrain(9.6, band: band) == old, "unusable band #\(i)")
        }
        // The whole value too: identical with and without the field when there is no band.
        #expect(OrbitGauge.spokenValue(.previewScored) == OrbitGauge.spokenValue(
            OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6, strainBand: nil)))
        #expect(OrbitGauge.spokenValue(.previewScored).hasSuffix(old))
        #expect(!OrbitGauge.spokenValue(.previewScored).contains("range"))
    }

    @Test func aMissingStrainStillSaysNotScoredWhateverTheBand() {
        let withBand = OrbitGauge.spokenValue(.previewBanded(strain: nil))
        let without = OrbitGauge.spokenValue(OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88))
        #expect(withBand == without)
        #expect(withBand.hasSuffix("Strain, not scored"))
    }

    /// The German template resolves in the app's `de.lproj`, with the locale's decimal comma for the number.
    @Test func germanResolvesToBelastungMitHeutigemBereich() throws {
        let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"), "the app has a German localization")
        let german = try #require(Bundle(path: path))
        let key = "Strain %@ of 21, today's recommended range %@ to %@"
        let template = german.localizedString(forKey: key, value: "MISSING", table: nil)
        #expect(template == "Belastung %1$@ von 21, heutiger empfohlener Bereich %2$@ bis %3$@")
        let de = Locale(identifier: "de_DE")
        let strain = 9.6.formatted(.number.precision(.fractionLength(1)).locale(de))
        let lo = 8.0.formatted(.number.precision(.fractionLength(0...1)).locale(de))
        let hi = 13.0.formatted(.number.precision(.fractionLength(0...1)).locale(de))
        #expect(strain == "9,6" && lo == "8" && hi == "13")
        #expect(String(format: template, locale: de, strain as NSString, lo as NSString, hi as NSString)
                == "Belastung 9,6 von 21, heutiger empfohlener Bereich 8 bis 13")
        let above = german.localizedString(forKey: "Strain %@ of 21, above today's recommended range %@ to %@",
                                           value: "MISSING", table: nil)
        #expect(above == "Belastung %1$@ von 21, über dem heutigen empfohlenen Bereich %2$@ bis %3$@")
        let high = 16.5.formatted(.number.precision(.fractionLength(1)).locale(de))
        #expect(String(format: above, locale: de, high as NSString, lo as NSString, hi as NSString)
                == "Belastung 16,5 von 21, über dem heutigen empfohlenen Bereich 8 bis 13")
        // 0 to 1 fraction digits: a half shows, a whole number never gets ",0".
        #expect(8.5.formatted(.number.precision(.fractionLength(0...1)).locale(de)) == "8,5")
        #expect(!lo.contains(",0") && !hi.contains(",0"))
    }

    // MARK: 8. the widget

    /// The snapshot has no band field and the widget draws nil; Today's side (`strainBand` nil in the mode it decides)
    /// is already pinned by `OrbitGaugeTodayTests`, which compares whole values with `==`.
    @Test func theSnapshotShapeIsUnchangedAndItsGaugeCarriesNoBand() throws {
        let json = #"{"day":"2026-10-22","kind":"score","readiness":71,"updatedAt":"2026-10-22T07:30:00Z","#
            + #""orbit":{"recovery":71,"sleepPerformance":88,"strain":9.6}}"#
        let snapshot = try ReadinessSnapshot.decoder.decode(ReadinessSnapshot.self, from: Data(json.utf8))
        let written = try #require(JSONSerialization.jsonObject(with: ReadinessSnapshot.encoder.encode(snapshot)) as? [String: Any])
        let orbit = try #require(written["orbit"] as? [String: Any])
        #expect(Set(orbit.keys) == ["recovery", "sleepPerformance", "strain"])
        let encoded = try ReadinessSnapshot.encoder.encode(snapshot)
        #expect(!(String(data: encoded, encoding: .utf8) ?? "band").lowercased().contains("band"))
        let expected = OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)
        #expect(snapshot.gauge?.scoredValues == expected)
        #expect(snapshot.gauge?.scoredValues?.strainBand == nil)

        let pendingJSON = #"{"day":"2026-10-22","kind":"pending","previousReadiness":71,"updatedAt":"2026-10-22T07:30:00Z","#
            + #""orbit":{"recovery":71,"sleepPerformance":88,"strain":9.6}}"#
        let pending = try ReadinessSnapshot.decoder.decode(ReadinessSnapshot.self, from: Data(pendingJSON.utf8))
        #expect(pending.gauge == .pending(previous: expected))
    }
}
