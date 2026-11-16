import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// What VoiceOver is told by the Nocturne components (docs/work/2026-11-16-nocturne/design.md §P2-7, tests 23–26): each is
/// hosted alone in a real window and read through the accessibility tree (`HostedWindow`), the same frames and traits
/// VoiceOver would use. A component is one element, with the caller's label and value; its inner `Text` is not exposed.
/// Taps go through `accessibilityActivate`, the path of VoiceOver's double tap.
///
/// Not covered here (needs a device and VoiceOver): the focus order, the rotor, and how the labels sound.
@MainActor
@Suite("Nocturne components, accessibility", .serialized)
struct NocturneComponentAccessibilityTests {
    private typealias Tokens = NocturneTokenTests

    /// Counts the taps a button's action receives.
    @MainActor
    private final class Taps {
        var count = 0
    }

    /// `view` at the top-leading corner of a 390 × 700 window on the screen colour.
    private func host<V: View>(_ view: V, typeSize: DynamicTypeSize = .large, category: UIContentSizeCategory = .large,
                               _ body: (HostedWindow) async throws -> Void) async throws {
        let content = view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Theme.background)
        try await HostedWindow.run(width: 390, height: 700, typeSize: typeSize, category: category, content, body: body)
    }

    private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.5) -> Bool { abs(a - b) <= tolerance }

    // MARK: 23. DotNumeral

    @Test("Spec 23: a dot numeral is one element — the caller's label, no value, no inner text, the grid's frame")
    func dotNumeralIsOneElement() async throws {
        try await host(DotNumeral("84", accessibilityLabel: Text(verbatim: "Readiness 84 of 100"))) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.count == 1, "elements: \(nodes.map(\.label))")
            let node = try #require(nodes.first)
            #expect(node.label == "Readiness 84 of 100")
            #expect((node.value ?? "").isEmpty, "no value: \(String(describing: node.value))")
            #expect(!node.traits.contains(.button) && !node.traits.contains(.adjustable))
            #expect(near(node.frame.width, 74) && near(node.frame.height, 47), "the grid's size: \(node.frame)")
            #expect(w.node("84", exactly: true) == nil, "the numeral is not read digit by digit")
        }
    }

    @Test("Spec 23: a pending numeral says so through the caller's label")
    func pendingNumeralLabel() async throws {
        try await host(DotNumeral(nil, accessibilityLabel: Text(verbatim: "Readiness, no value yet"))) { w in
            try await w.settle()
            #expect(w.nodes().map(\.label) == ["Readiness, no value yet"])
        }
    }

    /// P2-D10: a pending numeral draws a template now, and the element is still only the caller's words.
    @Test("A pending numeral with a \"0:00\" template is one element: the caller's label, no value, the 125 × 47 grid")
    func pendingTemplateKeepsTheCallersLabel() async throws {
        let label = "Time asleep, no value yet"
        try await host(DotNumeral(nil, glyphGap: DotNumeral.glyphGapDetail, placeholder: "0:00", accessibilityLabel: Text(verbatim: label))) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == [label], "elements: \(nodes.map(\.label))")
            let node = try #require(nodes.first)
            #expect((node.value ?? "").isEmpty, "no value: \(String(describing: node.value))")
            #expect(near(node.frame.width, 125) && near(node.frame.height, 47), "as wide as 7:48: \(node.frame)")
            // Neither the template nor the dashes of the fallback are read out.
            for text in ["0:00", "–:––", "–"] { #expect(w.node(text, exactly: true) == nil, "'\(text)' is not an element") }
        }
    }

    @Test("The same pending numeral in the Light fallback (AX3) keeps the caller's label, not the dashes")
    func pendingTemplateLightKeepsTheCallersLabel() async throws {
        let label = "Time asleep, no value yet"
        let view = DotNumeral(nil, glyphGap: DotNumeral.glyphGapDetail, placeholder: "0:00", accessibilityLabel: Text(verbatim: label))
        try await host(view, typeSize: .accessibility3, category: .accessibilityExtraLarge) { w in
            try await w.settle()
            #expect(w.nodes().map(\.label) == [label], "elements: \(w.nodes().map(\.label))")
            let value = w.nodes().first?.value ?? ""
            #expect(value.isEmpty)
            #expect(w.node("–:––", exactly: true) == nil)
        }
    }

    struct NumeralCase: Sendable, CustomTestStringConvertible {
        let text: String?
        let style: DotNumeral.Style
        let typeSize: DynamicTypeSize
        let category: UIContentSizeCategory
        let label: String
        var testDescription: String { "\(text.map { "\"\($0)\"" } ?? "nil"), \(style), \(typeSize)" }
    }

    /// Spec 23 and 26. Dots, Light digits at AX3, the `.light` style and a string outside the table all give the same
    /// single element with the caller's label; the Light text itself is not a second element.
    @Test("Specs 23, 26: the Light fallback, in all its triggers, is still exactly one element with the caller's label", arguments: [
        NumeralCase(text: "84", style: .dots, typeSize: .accessibility3, category: .accessibilityExtraLarge, label: "Readiness 84 of 100"),
        NumeralCase(text: "7:48", style: .dots, typeSize: .accessibility1, category: .accessibilityMedium, label: "7 hours 48 minutes asleep"),
        NumeralCase(text: nil, style: .dots, typeSize: .accessibility3, category: .accessibilityExtraLarge, label: "Readiness, no value yet"),
        NumeralCase(text: "84", style: .light, typeSize: .large, category: .large, label: "Readiness 84 of 100"),
        NumeralCase(text: "7h", style: .dots, typeSize: .large, category: .large, label: "Seven hours"),
        NumeralCase(text: "", style: .dots, typeSize: .large, category: .large, label: "Empty"),
    ])
    func fallbackIsOneElement(_ c: NumeralCase) async throws {
        let view = DotNumeral(c.text, style: c.style, accessibilityLabel: Text(verbatim: c.label))
        try await host(view, typeSize: c.typeSize, category: c.category) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == [c.label], "elements: \(nodes.map(\.label))")
            let value = nodes.first?.value ?? ""
            #expect(value.isEmpty)
        }
    }

    // MARK: 23. RulerScale

    private func todayRuler(labels: [String] = ["0", "low", "moderate", "high", "100"], value: Double? = 84) -> RulerScale {
        RulerScale(range: 0...100, value: value, zone: 67...100, tickCount: RulerScale.Ticks.today, labels: labels,
                   accessibilityLabel: Text(verbatim: "Readiness scale"),
                   accessibilityValue: Text(verbatim: "84, high, on a scale from 0 to 100"), reduceMotion: true)
    }

    @Test("Spec 23: a ruler is one element — the subject as label, the caller's sentence as value, none for its labels or ticks")
    func rulerIsOneElement() async throws {
        try await host(todayRuler().frame(width: 300)) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.count == 1, "elements: \(nodes.map(\.label))")
            let node = try #require(nodes.first)
            #expect(node.label == "Readiness scale")
            #expect(node.value == "84, high, on a scale from 0 to 100")
            // The element's frame is the union of what is drawn: the 300 pt, and the outer ticks overhang by 0.75 each side.
            #expect(near(node.frame.width, 300 + 1.5, 0.6), "as wide as it is given: \(node.frame)")
            // The 36 pt graphic and a line of labels under it, inside the same element.
            #expect(node.frame.height > 36 && node.frame.height < 60, "graphic and labels: \(node.frame.height)")
            for label in ["low", "moderate", "high", "100"] { #expect(w.node(label, exactly: true) == nil, "'\(label)' is not an element") }
        }
    }

    /// The accessibility frame is the union of the drawn shapes (the needle's top at y 0 to its foot at y 28), not the 36 pt layout
    /// box: VoiceOver's focus rectangle hugs the graphic. Pinned as an upper bound, so a frame that grows past the box fails.
    @Test("Spec 23: a ruler without labels is one element, no taller than its 36 pt box")
    func rulerWithoutLabels() async throws {
        try await host(todayRuler(labels: []).frame(width: 300)) { w in
            try await w.settle()
            let node = try #require(w.nodes().first)
            #expect(w.nodes().count == 1)
            #expect(node.frame.height > 20 && node.frame.height <= 36.5, "\(node.frame)")
        }
    }

    @Test("Spec 23: a ruler with no value keeps its sentence — the caller's text says 'no value yet'")
    func rulerWithoutValue() async throws {
        let ruler = RulerScale(range: 0...100, value: nil, zone: 67...100, tickCount: 61, labels: ["0", "100"],
                               accessibilityLabel: Text(verbatim: "Readiness scale"),
                               accessibilityValue: Text(verbatim: "No value yet, on a scale from 0 to 100"))
        try await host(ruler.frame(width: 300)) { w in
            try await w.settle()
            let node = try #require(w.nodes().first)
            #expect(w.nodes().count == 1)
            #expect(node.value == "No value yet, on a scale from 0 to 100")
        }
    }

    @Test("Spec 26: at AX3 the labels wrap, and the ruler is still one element")
    func rulerAtAX3() async throws {
        try await host(todayRuler().frame(width: 300), typeSize: .accessibility3, category: .accessibilityExtraLarge) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.count == 1, "elements: \(nodes.map(\.label))")
            #expect(nodes.first?.value == "84, high, on a scale from 0 to 100")
            // The graphic stays 36; the labels grow with the text, so the element is taller than at the default size.
            #expect((nodes.first?.frame.height ?? 0) > 36 + 20, "\(String(describing: nodes.first?.frame))")
        }
    }

    // MARK: 22 (hosted). Reduce Motion

    @MainActor
    @Observable final class RulerModel {
        var value: Double? = 20
    }

    struct MovingRuler: View {
        let model: RulerModel
        var body: some View {
            RulerScale(range: 0...100, value: model.value, zone: 67...100, tickCount: RulerScale.Ticks.today,
                       accessibilityLabel: Text(verbatim: "Readiness scale"), accessibilityValue: Text(verbatim: "value"),
                       reduceMotion: true)
                .frame(width: 300)
        }
    }

    /// Spec 22, last clause. With Reduce Motion the needle does not travel: the first frame after a value change already
    /// has it at its final x. (The animated case is deliberately not asserted: a 250 ms ease-out read mid-way is timing.)
    @Test("Spec 22: with Reduce Motion the needle is at its final x in the first frame after a value change")
    func needleJumpsUnderReduceMotion() async throws {
        let model = RulerModel()
        try await host(MovingRuler(model: model)) { w in
            try await w.settle()
            let node = try #require(w.nodes().first)
            let y = node.frame.minY + 20
            let volt = Tokens.resolve(Theme.signal)
            @MainActor func isVolt(_ x: CGFloat) -> Bool {
                guard let p = w.pixel(at: CGPoint(x: x, y: y)) else { return false }
                let t = 4.0 / 255
                return abs(p.r - volt.r) <= t && abs(p.g - volt.g) <= t && abs(p.b - volt.b) <= t
            }
            let (at20, at84) = (CGFloat(60), CGFloat(252))   // the ruler starts at the window's leading edge
            #expect(isVolt(at20) && !isVolt(at84), "the needle starts at 20")
            model.value = 84
            // The next frame, not a settled one.
            #expect(isVolt(at84), "the needle is at 84 in the first frame")
            #expect(!isVolt(at20), "and has left 20")
        }
    }

    // MARK: 23. DotRow

    @Test("Spec 23: a dot row is one element with the caller's summary, not one per dot")
    func dotRowIsOneElement() async throws {
        let summary = "Slept enough on 5 of the last 7 nights; tonight is marked"
        try await host(DotRow([.full, .full, .missed, .full, .full, .missed, .today], accessibilityLabel: Text(verbatim: summary))) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == [summary])
            let node = try #require(nodes.first)
            #expect(near(node.frame.width, 66) && near(node.frame.height, 6), "the row's frame: \(node.frame)")
            #expect((node.value ?? "").isEmpty)
        }
    }

    // MARK: 23. TickRow

    private func tickRow(_ n: Int, minutes: Double?) -> TickRow {
        TickRow(label: Text(verbatim: "Z\(n)"), minutes: minutes, scaleMax: 60, value: Text(verbatim: minutes.map { "\(Int($0))" } ?? "–"),
                accessibilityLabel: Text(verbatim: "Zone \(n), \(minutes.map { "\(Int($0)) minutes" } ?? "no data")"))
    }

    @Test("Spec 23: each tick row is one element with the caller's label; the caller's .contain groups the five")
    func tickRowsAreOneElementEach() async throws {
        let rows = VStack(spacing: TickRow.rowSpacing) {
            tickRow(1, minutes: 40); tickRow(2, minutes: 12); tickRow(3, minutes: 24); tickRow(4, minutes: 5); tickRow(5, minutes: nil)
        }
        .frame(width: 330)
        .accessibilityElement(children: .contain)
        try await host(rows) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == ["Zone 1, 40 minutes", "Zone 2, 12 minutes", "Zone 3, 24 minutes", "Zone 4, 5 minutes", "Zone 5, no data"],
                    "elements: \(nodes.map(\.label))")
            for node in nodes {
                // One line: the 12 pt ticks, and the 12 pt text's line box (15) overhangs them (design.md: "text may overhang").
                #expect(node.frame.height >= 12 - 0.5 && node.frame.height < 20 && node.frame.width >= 315 - 0.5, "one line: \(node.frame)")
            }
            // Five rows 9 pt apart: the 12 pt row plus 9 between each, measured between the rows' tops.
            for (a, b) in zip(nodes, nodes.dropFirst()) { #expect(near(b.frame.minY - a.frame.minY, 21), "rows are 12 + 9 apart") }
            for text in ["Z1", "Z3", "40", "–"] { #expect(w.node(text, exactly: true) == nil, "'\(text)' is not an element") }
        }
    }

    @Test("Spec 23: stacked at AX3, a tick row is still one element")
    func tickRowAtAX3() async throws {
        try await host(tickRow(3, minutes: 24).frame(width: 330), typeSize: .accessibility3, category: .accessibilityExtraLarge) { w in
            try await w.settle()
            #expect(w.nodes().map(\.label) == ["Zone 3, 24 minutes"])
            #expect((w.nodes().first?.frame.height ?? 0) > 12 + 4 + 20, "stacked: \(String(describing: w.nodes().first?.frame))")
        }
    }

    // MARK: 24. CircleButton

    @Test("Spec 24: the circle button is a 44 × 44 button with the caller's label; a tap runs the action once")
    func circleButton() async throws {
        let taps = Taps()
        let button = CircleButton(systemImage: "chevron.left", accessibilityLabel: Text(verbatim: "Previous day")) { taps.count += 1 }
        try await host(button) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == ["Previous day"], "elements: \(nodes.map(\.label))")
            let node = try #require(nodes.first)
            #expect(node.frame.width >= 44 - 0.5 && node.frame.height >= 44 - 0.5, "hit target \(node.frame)")
            #expect(node.traits.contains(.button))
            #expect(node.isEnabled)
            node.activate()
            #expect(taps.count == 1)
        }
    }

    @Test("Spec 24: disabled, the circle button is not enabled and does not run its action")
    func disabledCircleButton() async throws {
        let taps = Taps()
        let button = CircleButton(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add")) { taps.count += 1 }.disabled(true)
        try await host(button) { w in
            try await w.settle()
            let node = try #require(w.node("Add", exactly: true))
            #expect(!node.isEnabled, "traits \(node.traits)")
            #expect(node.traits.contains(.button))
            node.activate()
            #expect(taps.count == 0)
        }
    }

    @Test("Spec 24: at AX3 the circle button does not grow — it is an icon-only graphic")
    func circleButtonAtAX3() async throws {
        let button = CircleButton(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add")) {}
        try await host(button, typeSize: .accessibility3, category: .accessibilityExtraLarge) { w in
            try await w.settle()
            let node = try #require(w.node("Add", exactly: true))
            #expect(near(node.frame.width, 44) && near(node.frame.height, 44), "\(node.frame)")
        }
    }

    // MARK: 25. PillButton

    struct PillCase: Sendable, CustomTestStringConvertible {
        let style: PillButton.Style
        var testDescription: String { "\(style)" }
    }

    @Test("Spec 25: a pill is a button at least 52 high, the width it is given, labelled with its title, with one element",
          arguments: [PillCase(style: .primary), PillCase(style: .secondary)])
    func pillButton(_ c: PillCase) async throws {
        let taps = Taps()
        let pill = PillButton(Text(verbatim: "Continue"), style: c.style) { taps.count += 1 }.padding(.horizontal, 20)
        try await host(pill) { w in
            try await w.settle()
            let nodes = w.nodes()
            // The icon of the primary pill is hidden from VoiceOver: one element, the title.
            #expect(nodes.map(\.label) == ["Continue"], "elements: \(nodes.map(\.label))")
            let node = try #require(nodes.first)
            #expect(node.frame.height >= 52 - 0.5 && node.frame.height < 60, "height \(node.frame.height)")
            #expect(near(node.frame.width, 350), "the width it is given: \(node.frame)")
            #expect(node.traits.contains(.button) && node.isEnabled)
            node.activate()
            #expect(taps.count == 1)
        }
    }

    @Test("Spec 25: disabled, a pill is not enabled and does not run its action", arguments: [PillCase(style: .primary), PillCase(style: .secondary)])
    func disabledPill(_ c: PillCase) async throws {
        let taps = Taps()
        let pill = PillButton(Text(verbatim: "Continue"), style: c.style) { taps.count += 1 }.disabled(true)
        try await host(pill) { w in
            try await w.settle()
            let node = try #require(w.node("Continue", exactly: true))
            #expect(!node.isEnabled, "traits \(node.traits)")
            #expect(node.frame.height >= 52 - 0.5, "a disabled pill keeps its size")
            node.activate()
            #expect(taps.count == 0)
        }
    }

    @Test("Spec 25: at AX3 a 40-character title wraps and the pill grows past 52, still one element",
          arguments: [PillCase(style: .primary), PillCase(style: .secondary)])
    func pillGrowsAtAX3(_ c: PillCase) async throws {
        let title = "Start the guided breathing exercise now!"
        #expect(title.count == 40)
        try await host(PillButton(Text(verbatim: title), style: c.style) {}, typeSize: .accessibility3, category: .accessibilityExtraLarge) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == [title], "elements: \(nodes.map(\.label))")
            let node = try #require(nodes.first)
            // Three or more lines of AX3 text and 12 pt above and below: well over twice the minimum.
            #expect(node.frame.height > 52 * 2, "the pill grew to \(node.frame.height)")
            #expect(near(node.frame.width, 390), "\(node.frame)")
        }
    }

    // MARK: 26. GlowTile

    @Test("Spec 26: a glow tile adds no element of its own — only its content is exposed")
    func glowTileAddsNothing() async throws {
        let tile = GlowTile(Theme.recovery, minHeight: GlowTileSpec.twoUpMinHeight) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Recovery").ryftGlowLabelStyle()
                Text(verbatim: "84").font(.ryft(.metric))
            }
        }
        .frame(width: 169)
        try await host(tile) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == ["Recovery", "84"], "elements: \(nodes.map(\.label))")
            for node in nodes { #expect(node.frame.width < 169 - 20, "inside the padding, not the tile: \(node.frame)") }
        }
    }

    @Test("Spec 26: an empty glow tile exposes nothing, flat or glowing", arguments: [false, true])
    func emptyGlowTile(_ flat: Bool) async throws {
        try await host(GlowTile(Theme.metricSleep, reduceTransparency: flat) { Color.clear }.frame(width: 169, height: 124)) { w in
            try await w.settle()
            #expect(w.nodes().isEmpty, "elements: \(w.nodes().map(\.label))")
        }
    }
}
