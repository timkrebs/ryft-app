import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// A view drawn by `ImageRenderer` and read pixel by pixel (8-bit sRGB, un-premultiplied), for the T5.0-A control tests.
@MainActor
struct ControlRender {
    let width: Int, height: Int, scale: CGFloat
    let bytes: [UInt8]

    init?<V: View>(_ view: V, scale: CGFloat = 4) {
        let renderer = ImageRenderer(content: view.environment(\.displayScale, scale))
        renderer.scale = scale
        guard let cg = renderer.uiImage?.cgImage else { return nil }
        let (w, h) = (cg.width, cg.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        (width, height, self.scale, self.bytes) = (w, h, scale, bytes)
    }

    /// The image's size in points.
    var size: CGSize { CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale) }

    func px(_ ix: Int, _ iy: Int) -> NocturneTokenTests.RGBA {
        let i = (iy * width + ix) * 4
        let a = Double(bytes[i + 3]) / 255
        guard a > 0 else { return .init(r: 0, g: 0, b: 0, a: 0) }
        return .init(r: Double(bytes[i]) / 255 / a, g: Double(bytes[i + 1]) / 255 / a, b: Double(bytes[i + 2]) / 255 / a, a: a)
    }

    /// The pixel that covers the point.
    func at(_ x: Double, _ y: Double) -> NocturneTokenTests.RGBA {
        px(min(max(Int((x * Double(scale)).rounded(.down)), 0), width - 1),
           min(max(Int((y * Double(scale)).rounded(.down)), 0), height - 1))
    }

    /// The box (points) around the pixels in `xs` × `ys` (pixel centres) for which `match` holds.
    func bounds(xs: ClosedRange<Double>, ys: ClosedRange<Double>, where match: (NocturneTokenTests.RGBA) -> Bool) -> CGRect? {
        var (minX, minY, maxX, maxY) = (Int.max, Int.max, Int.min, Int.min)
        for iy in 0..<height where ys.contains((Double(iy) + 0.5) / Double(scale)) {
            for ix in 0..<width where xs.contains((Double(ix) + 0.5) / Double(scale)) && match(px(ix, iy)) {
                minX = min(minX, ix); maxX = max(maxX, ix); minY = min(minY, iy); maxY = max(maxY, iy)
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    /// Every pixel of row `y` (points) between `xs`.
    func row(_ y: Double, xs: ClosedRange<Double>) -> [NocturneTokenTests.RGBA] {
        let iy = min(max(Int((y * Double(scale)).rounded(.down)), 0), height - 1)
        return (0..<width).filter { xs.contains((Double($0) + 0.5) / Double(scale)) }.map { px($0, iy) }
    }
}

extension NocturneTokenTests.RGBA {
    /// Every channel within `steps`/255 of `other`; alpha ignored (drawn on an opaque ground).
    func near(_ other: Self, _ steps: Double = 2) -> Bool {
        let t = steps / 255 + 1e-9
        return abs(r - other.r) <= t && abs(g - other.g) <= t && abs(b - other.b) <= t
    }
}

/// The toggle, the links, the icon disc and the `Recovery` colorset (docs/work/2026-11-16-nocturne/design.md §P5-1.4, §P5-12
/// tests 7, 16 and 18; build-plan.md §2 for `Recovery`). Hosted reads go through the accessibility tree (`HostedWindow`).
@MainActor
@Suite("Nocturne controls: toggle, links, icon disc, Recovery", .serialized)
struct NocturneControlsTests {
    private typealias Tokens = NocturneTokenTests
    private typealias RGBA = NocturneTokenTests.RGBA

    @MainActor
    private final class Taps {
        var total = 0
    }

    private func host<V: View>(_ view: V, typeSize: DynamicTypeSize = .large, category: UIContentSizeCategory = .large,
                               _ body: (HostedWindow) async throws -> Void) async throws {
        let content = view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Theme.background)
        try await HostedWindow.run(width: 390, height: 700, typeSize: typeSize, category: category, content, body: body)
    }

    private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.5) -> Bool { abs(a - b) <= tolerance }

    private var ink: RGBA { Tokens.resolve(Theme.textPrimary) }
    private var screen: RGBA { Tokens.resolve(Theme.background) }

    private func over(_ colour: Color, _ alpha: Double = 1) -> RGBA {
        var c = Tokens.resolve(colour)
        c.a *= alpha
        return Tokens.over(c, screen)
    }

    // MARK: the toggle: constants and contrast (7)

    @Test("The toggle's numbers: 51 × 31, knob 25 inset 3, off outline 1.5, disabled 35 %, rows ≥ 44")
    func toggleConstants() {
        #expect(RyftToggleStyle.trackSize == CGSize(width: 51, height: 31))
        #expect(RyftToggleStyle.knobDiameter == 25 && RyftToggleStyle.knobInset == 3)
        #expect(RyftToggleStyle.knobDiameter + 2 * RyftToggleStyle.knobInset == RyftToggleStyle.trackSize.height)
        #expect(RyftToggleStyle.offOutlineWidth == 1.5 && Theme.Metrics.controlOutline == 1.5)
        #expect(RyftToggleStyle.disabledOpacity == 0.35 && RyftToggleStyle.minRowHeight == 44)
    }

    @Test("Spec 7: the knob on the track ≥ 17; the off outline and knob (textTertiary) ≥ 4.5 on surface and background")
    func toggleContrast() {
        let surface = Tokens.resolve(Theme.surface), tertiary = Tokens.resolve(Theme.textTertiary)
        #expect(Tokens.ratio(screen, on: ink) >= 17, "\(Tokens.ratio(screen, on: ink))")
        #expect(Tokens.ratio(tertiary, on: surface) >= 4.5, "\(Tokens.ratio(tertiary, on: surface))")
        #expect(Tokens.ratio(tertiary, on: screen) >= 4.5, "\(Tokens.ratio(tertiary, on: screen))")
    }

    // MARK: the toggle: render

    @Test("On: a textPrimary track and a background knob at the trailing end")
    func trackOn() throws {
        let shot = try #require(ControlRender(RyftToggleTrack(isOn: true).background(Theme.background)))
        #expect(shot.size == CGSize(width: 51, height: 31))
        #expect(shot.at(10, 15.5).near(ink), "track: \(Tokens.describe(shot.at(10, 15.5)))")
        // The knob spans x 23…48: its centre is the screen colour, the track shows 1.5 pt beyond its trailing edge.
        #expect(shot.at(35.5, 15.5).near(screen), "knob: \(Tokens.describe(shot.at(35.5, 15.5)))")
        #expect(shot.at(49.5, 15.5).near(ink), "track right of the knob")
        #expect(shot.at(21.5, 15.5).near(ink), "track left of the knob")
    }

    @Test("Off: a 1.5 pt textTertiary outline, no fill, a textTertiary knob at the leading end")
    func trackOff() throws {
        let shot = try #require(ControlRender(RyftToggleTrack(isOn: false).background(Theme.background)))
        let tertiary = over(Theme.textTertiary)
        #expect(shot.at(25.5, 0.6).near(tertiary, 3), "outline at the top: \(Tokens.describe(shot.at(25.5, 0.6)))")
        #expect(shot.at(25.5, 30.4).near(tertiary, 3), "outline at the bottom")
        #expect(shot.at(38, 15.5).near(screen), "no fill: \(Tokens.describe(shot.at(38, 15.5)))")
        #expect(shot.at(15.5, 15.5).near(tertiary, 3), "knob: \(Tokens.describe(shot.at(15.5, 15.5)))")
        #expect(shot.at(30, 15.5).near(screen), "nothing between the knob and the far end")
    }

    // MARK: the toggle: hosted (16)

    private struct ToggleHost: View {
        @State var isOn: Bool
        var style: Style = .ryft
        let changed: (Bool) -> Void

        enum Style { case ryft, system }

        var body: some View {
            Group {
                switch style {
                case .ryft: toggle.toggleStyle(.ryft)
                case .system: toggle.toggleStyle(.switch)
                }
            }
            .onChange(of: isOn) { _, new in changed(new) }
        }

        private var toggle: Toggle<Text> {
            Toggle(isOn: $isOn) { Text(verbatim: "Wake alarm") }
        }
    }

    @MainActor
    private final class Changes {
        var values: [Bool] = []
    }

    /// What a system switch with the same label and state tells VoiceOver: the reference.
    private func systemSwitch(on: Bool) async throws -> (value: String?, traits: UIAccessibilityTraits) {
        var result: (String?, UIAccessibilityTraits) = (nil, [])
        try await host(ToggleHost(isOn: on, style: .system) { _ in }.padding(.horizontal, 20)) { w in
            try await w.settle()
            let node = try #require(w.node("Wake alarm", exactly: true))
            result = (node.value, node.traits)
        }
        return result
    }

    @Test("Spec 16: still a switch — the system switch's value and traits, on and off; the row ≥ 44 high; a tap toggles",
          arguments: [false, true])
    func toggleIsASwitch(_ initial: Bool) async throws {
        let reference = try await systemSwitch(on: initial), flipped = try await systemSwitch(on: !initial)
        #expect(reference.value != flipped.value, "the system's on and off values differ: \(String(describing: reference.value))")
        let changes = Changes()
        try await host(ToggleHost(isOn: initial) { changes.values.append($0) }.padding(.horizontal, 20)) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == ["Wake alarm"], "one element: \(nodes.map(\.label))")
            let node = try #require(nodes.first)
            #expect(node.value == reference.value, "value \(String(describing: node.value)), system \(String(describing: reference.value))")
            #expect(node.traits == reference.traits, "traits \(node.traits.rawValue), system \(reference.traits.rawValue)")
            #expect(node.traits.contains(.toggleButton) || node.traits.contains(.button), "a control: \(node.traits.rawValue)")
            #expect(node.isEnabled)
            #expect(node.frame.height >= 44 - 0.5 && node.frame.width >= 350 - 0.5, "the row is the target: \(node.frame)")
            node.activate()
            try await w.wait("the toggle to flip") { changes.values == [!initial] }
            try await w.settle()
            let after = try #require(w.node("Wake alarm", exactly: true))
            #expect(after.value == flipped.value, "after the tap: \(String(describing: after.value))")
        }
    }

    @Test("Spec 16: disabled, the toggle is not enabled and a tap changes nothing")
    func disabledToggle() async throws {
        let changes = Changes()
        try await host(ToggleHost(isOn: true) { changes.values.append($0) }.disabled(true).padding(.horizontal, 20)) { w in
            try await w.settle()
            let node = try #require(w.node("Wake alarm", exactly: true))
            #expect(!node.isEnabled, "traits \(node.traits.rawValue)")
            node.activate()
            try await Task.sleep(for: .milliseconds(200))
            #expect(changes.values.isEmpty)
        }
    }

    @Test("At AX3 the label wraps beside the fixed track, and the toggle stays one element")
    func toggleAtAX3() async throws {
        let label = "Remind me at bedtime on every weekday night"
        let toggle = Toggle(isOn: .constant(true)) { Text(verbatim: label).font(.ryft(.body)) }.toggleStyle(.ryft)
        try await host(toggle.padding(.horizontal, 20), typeSize: .accessibility3, category: .accessibilityExtraLarge) { w in
            try await w.settle()
            #expect(w.nodes().map(\.label) == [label], "\(w.nodes().map(\.label))")
            let node = try #require(w.nodes().first)
            #expect(node.frame.height > 88, "the label wrapped: \(node.frame)")
            #expect(node.frame.maxX <= 370 + 0.5, "inside the width: \(node.frame)")
        }
    }

    // MARK: the icon disc (18)

    @Test("Spec 18: the disc's numbers: 36 and 40, a 16 % ring of 1 pt, a 16 pt glyph")
    func discConstants() {
        #expect(IconDisc.Size.regular.diameter == 36 && IconDisc.Size.large.diameter == 40)
        #expect(IconDisc.ringOpacity == 0.16 && IconDisc.ringOpacity == CircleButton.borderOpacity && IconDisc.ringWidth == 1)
        #expect(IconDisc.glyphSize == 16)
    }

    @Test("Spec 18: a 1 pt ring at 16 % and no fill", arguments: [IconDisc.Size.regular, .large])
    func discPixels(_ size: IconDisc.Size) throws {
        let shot = try #require(ControlRender(IconDisc(systemImage: "figure.run", size: size).background(Theme.background)))
        let d = Double(size.diameter)
        #expect(shot.size == CGSize(width: d, height: d))
        let ring = over(Theme.textPrimary, 0.16)
        #expect(shot.at(d / 2, 0.5).near(ring, 3), "ring at the top: \(Tokens.describe(shot.at(d / 2, 0.5)))")
        #expect(shot.at(0.5, d / 2).near(ring, 3), "ring at the left")
        // Inside the ring, clear of the glyph: the ground.
        #expect(shot.at(3, d / 2).near(screen), "no fill: \(Tokens.describe(shot.at(3, d / 2)))")
        #expect(shot.at(d / 2, 3).near(screen), "no fill at the top")
    }

    @Test("Spec 18: unlabelled, the disc is hidden from VoiceOver")
    func discHidden() async throws {
        try await host(HStack { IconDisc(systemImage: "figure.run"); IconDisc(systemImage: "bed.double", size: .large) }) { w in
            try await w.settle()
            #expect(w.nodes().isEmpty, "elements: \(w.nodes().map(\.label))")
        }
    }

    @Test("Spec 18: labelled, the disc is one image element with the caller's label, the disc's size",
          arguments: [IconDisc.Size.regular, .large])
    func discLabelled(_ size: IconDisc.Size) async throws {
        try await host(IconDisc(systemImage: "applewatch", size: size, accessibilityLabel: Text(verbatim: "Apple Watch"))) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == ["Apple Watch"], "\(nodes.map(\.label))")
            let node = try #require(nodes.first)
            #expect(node.traits.contains(.image) && !node.traits.contains(.button))
            #expect(near(node.frame.width, size.diameter) && near(node.frame.height, size.diameter), "\(node.frame)")
        }
    }

    // MARK: the links (18)

    @Test("The link look: textPrimary, underline at 50 %, a 44 pt target")
    func linkConstants() {
        #expect(InlineLink.underlineOpacity == 0.5 && InlineLink.minTarget == 44)
        #expect(InlineLink.ink == Theme.textPrimary)
        #expect(InlineLink.underline == Text.LineStyle(pattern: .solid, color: Theme.textPrimary.opacity(0.5)))
    }

    @Test("Spec 18: ryftLink is a button at least 44 × 44 with its title as label; a tap runs it, disabled does not")
    func standaloneLink() async throws {
        let taps = Taps()
        let links = VStack(alignment: .leading, spacing: 0) {
            Button { taps.total += 1 } label: { Text(verbatim: "Forgot password?") }.ryftLink()
            Button { taps.total += 10 } label: { Text(verbatim: "OK") }.ryftLink()
            Button { taps.total += 100 } label: { Text(verbatim: "Use another email") }.ryftLink().disabled(true)
        }
        try await host(links.padding(.horizontal, 20)) { w in
            try await w.settle()
            #expect(w.nodes().map(\.label) == ["Forgot password?", "OK", "Use another email"], "\(w.nodes().map(\.label))")
            for node in w.nodes() {
                #expect(node.traits.contains(.button), "\(node.label)")
                #expect(node.frame.height >= 44 - 0.5 && node.frame.width >= 44 - 0.5, "\(node.label): \(node.frame)")
            }
            w.node("Forgot password?", exactly: true)?.activate()
            w.node("OK", exactly: true)?.activate()
            w.node("Use another email", exactly: true)?.activate()
            try await w.wait("the two enabled links") { taps.total == 11 }
            #expect(w.node("Use another email", exactly: true)?.isEnabled == false)
        }
    }

    /// The underline is the cue (1.4.1): a row of pixels under the text in ink at 50 % over the ground.
    private func underlineRow(_ shot: ControlRender, xs: ClosedRange<Double>) -> Double? {
        let half = over(Theme.textPrimary, 0.5)
        let span = Double(xs.upperBound - xs.lowerBound) * Double(shot.scale)
        var y = 0.125
        while y < Double(shot.size.height) {
            let hits = shot.row(y, xs: xs).filter { $0.near(half, 14) }.count
            // Descenders cross the line, so most of the row, not all of it.
            if Double(hits) >= 0.7 * span { return y }
            y += 0.25
        }
        return nil
    }

    @Test("Spec 18: ryftLink draws its text in textPrimary over a 50 % underline the width of the text")
    func standaloneLinkPixels() throws {
        let link = Button {} label: { Text(verbatim: "Forgot password?") }.ryftLink().background(Theme.background)
        let shot = try #require(ControlRender(link))
        #expect(shot.size.height == 44, "\(shot.size)")
        let text = try #require(shot.bounds(xs: 0...Double(shot.size.width), ys: 0...44) { $0.near(self.ink, 6) }, "ink glyphs")
        let underline = try #require(underlineRow(shot, xs: (text.minX + 2)...(text.maxX - 2)), "an underline row")
        #expect(underline > text.midY && underline < 44, "under the text: \(underline), text \(text)")
    }

    @Test("Markdown links: the link runs get the ink and the underline; the other runs keep the caller's style")
    func styledRuns() throws {
        let source = try AttributedString(markdown: "Read the [Privacy Policy](https://example.com/privacy) and the [Terms](https://example.com/terms).")
        let styled = InlineLink.styled(source)
        #expect(String(styled.characters) == String(source.characters))
        var links = 0
        for run in styled.runs {
            if run.link != nil {
                links += 1
                #expect(run.swiftUI.foregroundColor == Theme.textPrimary)
                #expect(run.swiftUI.underlineStyle == InlineLink.underline)
            } else {
                #expect(run.swiftUI.foregroundColor == nil && run.swiftUI.underlineStyle == nil)
            }
        }
        #expect(links == 2)
    }

    @Test("InlineLink.styled keeps a sentence with a Markdown link one element; the Links rotor reaches the link")
    func inlineLinkIsReachable() async throws {
        let sentence = try AttributedString(markdown: "Your data is stored on the RYFT platform. [Privacy Policy](https://example.com/privacy)")
        let text = Text(InlineLink.styled(sentence))
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textTertiary)
        try await host(text.padding(.horizontal, 20)) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.count == 1, "\(nodes.map(\.label))")
            let node = try #require(nodes.first)
            #expect(node.label == "Your data is stored on the RYFT platform. Privacy Policy", "no Markdown read out: \(node.label)")
            #expect(node.links.map(\.label) == ["Privacy Policy"], "links: \(node.links.map(\.label))")
        }
    }

    @Test("Inline links draw in textPrimary over the caller's grey, underlined, and never in the system tint")
    func inlineLinkPixels() throws {
        let view = Text(InlineLink.styled(try AttributedString(markdown: "Read the [Privacy Policy](https://example.com/privacy)")))
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize()
            .background(Theme.background)
        let shot = try #require(ControlRender(view))
        let link = try #require(shot.bounds(xs: 0...Double(shot.size.width), ys: 0...Double(shot.size.height)) { $0.near(self.ink, 6) },
                                "the link's ink glyphs")
        // The link is the second half of the line: ink starts well right of the leading "Read the".
        #expect(link.minX > 40, "only the link is ink: \(link)")
        let tinted = shot.bounds(xs: 0...Double(shot.size.width), ys: 0...Double(shot.size.height)) { $0.b - $0.r > 0.15 }
        #expect(tinted == nil, "a tint-coloured pixel at \(String(describing: tinted))")
        #expect(underlineRow(shot, xs: (link.minX + 2)...(link.maxX - 2)) != nil, "the link is underlined")
        let plainInk = shot.bounds(xs: 0...(link.minX - 6), ys: 0...Double(shot.size.height)) { $0.near(self.ink, 6) }
        #expect(plainInk == nil, "the plain words keep the caller's grey: ink at \(String(describing: plainInk))")
    }

    // MARK: Recovery

    @Test("The Recovery colorset resolves to the recovery teal #63D2B4, the colour Accent had; the orbit reads it")
    func recoveryColorset() throws {
        #expect(UIColor(named: "Recovery") != nil, "the colorset is in the app's catalog")
        let teal = Tokens.rgba(0x63D2B4)
        let recovery = Tokens.resolve(Color("Recovery"))
        #expect(Tokens.matches(recovery, teal), "\(Tokens.describe(recovery))")
        #expect(Tokens.matches(recovery, Tokens.resolve(Theme.recovery)), "the same as Theme.recovery")
        #expect(Tokens.matches(Tokens.resolve(OrbitGaugePalette.assets.recovery), teal), "the recovery orbit")
        #expect(Tokens.matches(Tokens.resolve(OrbitGaugePalette.assets.calibration), teal), "the calibration segments")
        #expect(OrbitGaugePalette.assets.recovery == Color("Recovery") && OrbitGaugePalette.assets.calibration == Color("Recovery"),
                "by name, not Accent")
    }
}
