import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The pill as the one button (docs/work/2026-11-16-nocturne/design.md §P5-1.2, §P5-12 tests 6 and 17; the compact size is
/// design-pr6-b-train.md S1): the destructive style and its contrast, busy (no taps, the label kept, "In progress", the same
/// size), the `async` action, the icon table, the compact size, and growth at AX3. PR 2's tests (spec 14, 25) still pin the
/// regular primary and secondary pills unchanged.
@MainActor
@Suite("PillButton, Nocturne PR 5", .serialized)
struct PillButtonNocturneTests {
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

    // MARK: constants and the icon table

    @Test("The new constants: destructive outline 70 %, pressed 8 %; compact 40 in 44, 18 a side")
    func constants() {
        #expect(PillButton.destructiveOutlineOpacity == 0.70 && PillButton.destructivePressedFillOpacity == 0.08)
        #expect(PillButton.compactHeight == 40 && PillButton.compactHitHeight == 44 && PillButton.compactHorizontal == 18)
        #expect(PillButton.compactHeight == Theme.Metrics.circleButton && PillButton.compactHitHeight == Theme.Metrics.minHitTarget)
        // PR 2's numbers stay.
        #expect(PillButton.minHeight == 52 && PillButton.disabledOpacity == 0.35 && PillButton.outlineOpacity == 0.20)
    }

    @Test("Spec 17: the icon table of §P5-1.2, and systemImage nil takes the default arrow")
    func iconTable() {
        #expect(PillButton.Icon.forward == "arrow.right")
        #expect(PillButton.Icon.confirm == "checkmark")
        #expect(PillButton.Icon.send == "arrow.up")
        #expect(PillButton.Icon.linkOut == "arrow.up.right")
        #expect(PillButton.Icon.download == "arrow.down")
        #expect(PillButton.Icon.start == "play.fill")
        #expect(PillButton.Icon.retry == "arrow.clockwise")
        #expect(PillButton.glyph(nil) == "arrow.right")
        #expect(PillButton.glyph("play.fill") == "play.fill")
        for symbol in [PillButton.Icon.forward, PillButton.Icon.confirm, PillButton.Icon.send, PillButton.Icon.linkOut,
                       PillButton.Icon.download, PillButton.Icon.start, PillButton.Icon.retry] {
            #expect(UIImage(systemName: symbol) != nil, "\(symbol) is an SF Symbol")
        }
    }

    @Test("The title ink per style: background on the fill, textPrimary on the outline, alert on the destructive outline")
    func inkPerStyle() {
        #expect(PillButton.ink(.primary) == Theme.background)
        #expect(PillButton.ink(.secondary) == Theme.textPrimary)
        #expect(PillButton.ink(.destructive) == Theme.alert)
    }

    // MARK: 6. Contrast

    @Test("Spec 6: background on the primary fill ≥ 17, pressed (85 %) ≥ 12; alert ≥ 6.0 / 5.6; the 70 % outline ≥ 3.3 on both")
    func contrast() {
        let ink = Tokens.resolve(Theme.textPrimary), screen = Tokens.resolve(Theme.background), surface = Tokens.resolve(Theme.surface)
        let alert = Tokens.resolve(Theme.alert)
        #expect(Tokens.ratio(screen, on: ink) >= 17, "\(Tokens.ratio(screen, on: ink))")
        var pressed = ink
        pressed.a = PillButton.primaryPressedOpacity
        let pressedFill = Tokens.over(pressed, screen)
        #expect(Tokens.ratio(screen, on: pressedFill) >= 12, "\(Tokens.ratio(screen, on: pressedFill))")
        #expect(Tokens.ratio(alert, on: screen) >= 6.0, "\(Tokens.ratio(alert, on: screen))")
        #expect(Tokens.ratio(alert, on: surface) >= 5.6, "\(Tokens.ratio(alert, on: surface))")
        var outline = alert
        outline.a = PillButton.destructiveOutlineOpacity
        #expect(Tokens.ratio(outline, on: screen) >= 3.3, "\(Tokens.ratio(outline, on: screen))")
        #expect(Tokens.ratio(outline, on: surface) >= 3.3, "\(Tokens.ratio(outline, on: surface))")
        // Area B's 40 % (S2) would not be a boundary: the reason for 70.
        outline.a = 0.40
        #expect(Tokens.ratio(outline, on: surface) < 3, "\(Tokens.ratio(outline, on: surface))")
    }

    // MARK: 17. Hosted

    struct Case: Sendable, CustomTestStringConvertible {
        let style: PillButton.Style
        let size: PillButton.Size
        var testDescription: String { "\(style) \(size)" }
    }

    nonisolated static let everyCase = [Case(style: .primary, size: .regular), Case(style: .secondary, size: .regular),
                            Case(style: .destructive, size: .regular), Case(style: .primary, size: .compact),
                            Case(style: .secondary, size: .compact), Case(style: .destructive, size: .compact)]

    @Test("Spec 17: idle, every style and size is one button element: the title, no value, enabled, one tap runs once",
          arguments: everyCase)
    func idle(_ c: Case) async throws {
        let taps = Taps()
        try await host(PillButton(Text(verbatim: "Delete"), style: c.style, size: c.size) { taps.total += 1 }.padding(.horizontal, 20)) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == ["Delete"], "elements: \(nodes.map(\.label))")
            let node = try #require(nodes.first)
            #expect((node.value ?? "").isEmpty, "no value when idle: \(String(describing: node.value))")
            #expect(node.traits.contains(.button) && node.isEnabled)
            switch c.size {
            case .regular:
                #expect(node.frame.height >= 52 - 0.5 && near(node.frame.width, 350), "\(node.frame)")
            case .compact:
                // The 44 pt box, as wide as the title and 18 a side (≥ 44).
                #expect(near(node.frame.height, 44), "\(node.frame)")
                #expect(node.frame.width >= 44 && node.frame.width < 120, "content width: \(node.frame)")
            }
            node.activate()
            #expect(taps.total == 1)
        }
    }

    /// Busy and idle hosted one after the other, the same title: busy keeps the frame, the label, adds the value, takes no tap.
    @Test("Spec 17: busy keeps the label and the frame, adds \"In progress\", and takes no tap", arguments: everyCase)
    func busy(_ c: Case) async throws {
        let title = "Save password"
        var idleFrame = CGRect.zero
        try await host(PillButton(Text(verbatim: title), style: c.style, size: c.size) {}.padding(.horizontal, 20)) { w in
            try await w.settle()
            idleFrame = try #require(w.node(title, exactly: true)).frame
        }
        let taps = Taps()
        let busy = PillButton(Text(verbatim: title), style: c.style, size: c.size, busy: true) { taps.total += 1 }
        try await host(busy.padding(.horizontal, 20)) { w in
            try await w.settle()
            let nodes = w.nodes()
            // The spinner adds no element of its own.
            #expect(nodes.map(\.label) == [title], "elements: \(nodes.map(\.label))")
            let node = try #require(nodes.first)
            #expect(node.value == String(localized: "In progress"), "value \(String(describing: node.value))")
            #expect(node.traits.contains(.button))
            #expect(!node.isEnabled, "busy takes no tap")
            #expect(near(node.frame.width, idleFrame.width) && near(node.frame.height, idleFrame.height),
                    "busy \(node.frame), idle \(idleFrame)")
            node.activate()
            #expect(taps.total == 0)
        }
    }

    @Test("Spec 17: the async initialiser runs its action once per tap", arguments: [PillButton.Style.primary, .destructive])
    func asyncActionRunsOnce(_ style: PillButton.Style) async throws {
        let taps = Taps()
        let pill = PillButton(Text(verbatim: "Send"), style: style) {
            try? await Task.sleep(for: .milliseconds(20))
            taps.total += 1
        }
        try await host(pill.padding(.horizontal, 20)) { w in
            try await w.settle()
            let node = try #require(w.node("Send", exactly: true))
            node.activate()
            try await w.wait("the action to run") { taps.total == 1 }
            try await Task.sleep(for: .milliseconds(200))
            #expect(taps.total == 1, "once, not again")
        }
    }

    @Test("The verbatim initialisers show outside text as it is, sync and async")
    func verbatim() async throws {
        let taps = Taps()
        let title = "Open **Connect** [IQ]"
        let pills = VStack(spacing: 12) {
            PillButton(verbatim: title, style: .secondary) { taps.total += 1 }
            PillButton(verbatim: title + " app", size: .compact) { taps.total += 10 }
        }
        try await host(pills.padding(.horizontal, 20)) { w in
            try await w.settle()
            #expect(w.nodes().map(\.label) == [title, title + " app"], "\(w.nodes().map(\.label))")
            w.node(title, exactly: true)?.activate()
            w.node(title + " app", exactly: true)?.activate()
            try await w.wait("both actions") { taps.total == 11 }
        }
    }

    @Test("Spec 17: disabled by the caller, a destructive or compact pill is not enabled and runs nothing",
          arguments: [Case(style: .destructive, size: .regular), Case(style: .primary, size: .compact)])
    func disabled(_ c: Case) async throws {
        let taps = Taps()
        try await host(PillButton(Text(verbatim: "Delete"), style: c.style, size: c.size) { taps.total += 1 }.disabled(true)) { w in
            try await w.settle()
            let node = try #require(w.node("Delete", exactly: true))
            #expect(!node.isEnabled)
            #expect((node.value ?? "").isEmpty, "disabled is not busy")
            node.activate()
            #expect(taps.total == 0)
        }
    }

    @Test("Spec 17: at AX3 the destructive pill wraps and grows past 104; the compact pill stays one line and grows past 44")
    func accessibilitySizes() async throws {
        let title = "Delete account and every night recorded"
        try await host(PillButton(Text(verbatim: title), style: .destructive) {}, typeSize: .accessibility3,
                       category: .accessibilityExtraLarge) { w in
            try await w.settle()
            let node = try #require(w.node(title, exactly: true))
            #expect(node.frame.height > 52 * 2, "grew to \(node.frame.height)")
            #expect(near(node.frame.width, 390), "\(node.frame)")
        }
        var defaultWidth: CGFloat = 0
        try await host(PillButton(Text(verbatim: "Save"), size: .compact) {}) { w in
            try await w.settle()
            defaultWidth = try #require(w.node("Save", exactly: true)).frame.width
        }
        try await host(PillButton(Text(verbatim: "Save"), size: .compact) {}, typeSize: .accessibility3,
                       category: .accessibilityExtraLarge) { w in
            try await w.settle()
            let node = try #require(w.node("Save", exactly: true))
            #expect(node.frame.height > 44 && node.frame.height < 90, "one line, taller: \(node.frame)")
            #expect(node.frame.width > defaultWidth * 1.5, "wider with the type: \(node.frame.width) vs \(defaultWidth)")
        }
    }

    @Test("A compact pill is never squeezed: offered 40 pt, it keeps the width it has with room")
    func compactKeepsItsWidth() async throws {
        var natural: CGFloat = 0
        try await host(PillButton(Text(verbatim: "Delete"), style: .destructive, size: .compact) {}) { w in
            try await w.settle()
            natural = try #require(w.node("Delete", exactly: true)).frame.width
        }
        try await host(PillButton(Text(verbatim: "Delete"), style: .destructive, size: .compact) {}.frame(width: 40)) { w in
            try await w.settle()
            let node = try #require(w.node("Delete", exactly: true))
            #expect(near(node.frame.width, natural), "squeezed to \(node.frame.width), natural \(natural)")
        }
    }

    // MARK: render

    private var ink: RGBA { Tokens.resolve(Theme.textPrimary) }
    private var screen: RGBA { Tokens.resolve(Theme.background) }

    private func over(_ colour: Color, _ alpha: Double) -> RGBA {
        var c = Tokens.resolve(colour)
        c.a = alpha
        return Tokens.over(c, screen)
    }

    private func pill(_ style: PillButton.Style, size: PillButton.Size = .regular, title: String = "Delete",
                      systemImage: String? = nil, busy: Bool = false, width: CGFloat? = 300) -> some View {
        PillButton(Text(verbatim: title), style: style, size: size, systemImage: systemImage, busy: busy) {}
            .frame(width: width)
            .background(Theme.background)
    }

    @Test("Spec 17: the destructive pill is a 70 % alert outline, no fill, the title in alert, centred")
    func destructivePixels() throws {
        let shot = try #require(ControlRender(pill(.destructive)))
        #expect(shot.size == CGSize(width: 300, height: 52))
        #expect(shot.at(150, 0.5).near(over(Theme.alert, 0.70), 3), "outline: \(Tokens.describe(shot.at(150, 0.5)))")
        #expect(shot.at(150, 51.5).near(over(Theme.alert, 0.70), 3))
        #expect(shot.at(150, 3).near(screen), "no fill: \(Tokens.describe(shot.at(150, 3)))")
        let alert = Tokens.resolve(Theme.alert)
        let title = try #require(shot.bounds(xs: 10...290, ys: 8...44) { $0.near(alert, 30) }, "the title's alert ink")
        #expect(abs(title.midX - 150) <= 2, "centred: \(title)")
    }

    @Test("Spec 17: systemImage nil draws the same pill as arrow.right; another glyph draws a different one")
    func defaultGlyphPixels() throws {
        let none = try #require(ControlRender(pill(.primary, title: "Continue")))
        let arrow = try #require(ControlRender(pill(.primary, title: "Continue", systemImage: "arrow.right")))
        let check = try #require(ControlRender(pill(.primary, title: "Continue", systemImage: PillButton.Icon.confirm)))
        #expect(none.bytes == arrow.bytes)
        #expect(none.bytes != check.bytes)
    }

    @Test("Busy keeps the look: the primary fill stays full ink (not the disabled 35 %), the outline stays 70 %")
    func busyLooksEnabled() throws {
        let primary = try #require(ControlRender(pill(.primary, busy: true)))
        #expect(primary.at(150, 2).near(ink), "fill: \(Tokens.describe(primary.at(150, 2)))")
        let destructive = try #require(ControlRender(pill(.destructive, busy: true)))
        #expect(destructive.at(150, 0.5).near(over(Theme.alert, 0.70), 3))
    }

    @Test("Compact: a 40 pt pill centred in the 44 pt box — clear 2 pt above and below, the fill inside, 18 pt sides")
    func compactPixels() throws {
        let shot = try #require(ControlRender(pill(.primary, size: .compact, title: "Save", width: nil)))
        #expect(shot.size.height == 44, "\(shot.size)")
        let mid = shot.size.width / 2
        #expect(shot.at(mid, 1).near(screen), "above the pill: \(Tokens.describe(shot.at(mid, 1)))")
        #expect(shot.at(mid, 43).near(screen), "below the pill")
        #expect(shot.at(mid, 3).near(ink), "the fill: \(Tokens.describe(shot.at(mid, 3)))")
        // The title is `background` on the fill, 18 pt in from each end. Only the middle rows: higher up, the round ends'
        // corners are the screen colour too.
        let title = try #require(shot.bounds(xs: 3...(shot.size.width - 3), ys: 17...27) { $0.near(self.screen, 40) })
        #expect(title.minX >= 17.5 && title.minX < 22, "title starts at \(title.minX)")
        #expect(shot.size.width - title.maxX >= 17.5 && shot.size.width - title.maxX < 22, "ends \(shot.size.width - title.maxX) before")
        let outline = try #require(ControlRender(pill(.secondary, size: .compact, title: "Save", width: nil)))
        #expect(outline.at(outline.size.width / 2, 2.5).near(over(Theme.textPrimary, 0.20), 3), "the 20 % outline at y 2")
        #expect(outline.at(outline.size.width / 2, 5).near(screen), "no fill")
    }
}
