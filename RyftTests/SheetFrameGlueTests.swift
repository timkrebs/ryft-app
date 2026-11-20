import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The shared sheet frame and header after PR 6 B's tickets met (the integration round): `SheetHeader`'s close circle hidden,
/// disabled or renamed (additive; the default unchanged), `SheetFrame`'s body, the rest sheets on it, Focused's empty page and
/// the exercise page opened from the live workout. In a real window (`HostedWindow`), read through the accessibility tree and
/// sampled pixels. Synthetic values only.
@MainActor
@Suite("Sheet frame, sheet header and the live workout's glue", .serialized)
struct SheetFrameGlueTests {
    /// Pixels brighter than mid-grey along `frame`'s middle line: the words of a message on a dark card.
    private static func inkPixels(across frame: CGRect, in w: HostedWindow) -> Int {
        var ink = 0
        for x in stride(from: frame.minX + 4, through: frame.maxX - 4, by: 2) {
            if let p = w.pixel(at: CGPoint(x: x, y: frame.midY)), p.r > 0.5 { ink += 1 }
        }
        return ink
    }

    // MARK: SheetHeader

    @Test("By default the close circle is \"Close\", sheet.close, enabled, and runs onClose")
    func theDefaultClose() async throws {
        var closed = 0
        let header = SheetHeader(Text(verbatim: "Add activity"), onClose: { closed += 1 }) {
            PillButton(Text(verbatim: "Save"), size: .compact) {}
        }
        try await HostedWindow.run(width: 390, height: 200, header.padding(.horizontal, SheetHeaderSpec.sidePadding)) { w in
            try await w.settle()
            let close = try #require(w.node("Close", exactly: true))
            #expect(close.identifier == "sheet.close")
            #expect(close.isEnabled)
            #expect(close.activate())
            #expect(closed == 1)
        }
    }

    @Test("closeHidden(): no close circle, and the title stays centred")
    func aHiddenClose() async throws {
        let header = SheetHeader(Text(verbatim: "Reorder")) {
            PillButton(Text(verbatim: "Done"), size: .compact) {}
        }
        .closeHidden()
        try await HostedWindow.run(width: 390, height: 200, header.padding(.horizontal, SheetHeaderSpec.sidePadding)) { w in
            try await w.settle()
            #expect(w.node("Close", exactly: true) == nil)
            #expect(!w.nodes().contains { $0.identifier == "sheet.close" })
            #expect(w.node("Done", exactly: true) != nil)
            let title = try #require(w.node("Reorder", exactly: true))
            #expect(title.traits.contains(.header))
            #expect(abs(title.frame.midX - 195) < 1, "\(title.frame)")
        }
    }

    @Test("closeDisabled(true): the circle is there, not enabled, and a tap does nothing; false is the default")
    func aDisabledClose() async throws {
        var closed = 0
        let header = SheetHeader(Text(verbatim: "New plan"), closeLabel: Text(verbatim: "Cancel"), onClose: { closed += 1 }) {
            PillButton(Text(verbatim: "Save"), size: .compact, busy: true) {}
        }
        try await HostedWindow.run(width: 390, height: 200,
                                   header.closeDisabled(true).padding(.horizontal, SheetHeaderSpec.sidePadding)) { w in
            try await w.settle()
            let cancel = try #require(w.node("Cancel", exactly: true))
            #expect(cancel.identifier == "sheet.close")
            #expect(!cancel.isEnabled)
            _ = cancel.activate()
            #expect(closed == 0)
        }
        try await HostedWindow.run(width: 390, height: 200,
                                   header.closeDisabled(false).padding(.horizontal, SheetHeaderSpec.sidePadding)) { w in
            try await w.settle()
            #expect(w.node("Cancel", exactly: true)?.isEnabled == true)
        }
    }

    @Test("closeIdentifier(_:) renames the circle for tests; its label and action stay")
    func aRenamedClose() async throws {
        let header = SheetHeader(Text(verbatim: "Rest"), closeLabel: Text(verbatim: "Done")).closeIdentifier("restSheet.done")
        try await HostedWindow.run(width: 390, height: 200, header.padding(.horizontal, SheetHeaderSpec.sidePadding)) { w in
            try await w.settle()
            #expect(w.node("Done", exactly: true)?.identifier == "restSheet.done")
        }
    }

    // MARK: SheetFrame

    @Test("SheetFrame: the body 20 from the sides and 12 under the header row; insets of its own too")
    func theFramesBody() async throws {
        let frame = SheetFrame(Text(verbatim: "Notes")) {
            Text(verbatim: "Body line").font(.ryft(.callout)).foregroundStyle(Theme.textPrimary)
        }
        try await HostedWindow.run(width: 390, height: 600, bottomInset: 0, frame) { w in
            try await w.settle()
            // From the title's middle (the window has a top safe area): half the 40 pt row, then the 12 pt gap.
            let title = try #require(w.node("Notes", exactly: true)).frame
            let body = try #require(w.node("Body line", exactly: true)).frame
            #expect(abs(body.minX - SheetHeaderSpec.sidePadding) < 1, "\(body)")
            #expect(abs((body.minY - title.midY) - (SheetHeaderSpec.height / 2 + SheetFrameSpec.bodyGap)) < 1.5, "\(title) \(body)")
        }
        try await HostedWindow.run(width: 390, height: 600, bottomInset: 0, frame.bodyInsets(EdgeInsets())) { w in
            try await w.settle()
            #expect(abs(try #require(w.node("Body line", exactly: true)).frame.minX) < 1, "a body that pads itself")
        }
    }

    @Test("The rest choices sheet on SheetFrame: \"Done\" as restSheet.done, the title a heading, a row per preset")
    func theRestChoicesSheet() async throws {
        let c = FocusedPreview.controller(.midSession)
        defer { c.stop() }
        let ex = try #require(c.pageExercise)
        try await HostedWindow.run(width: 390, height: 844, RestChoicesSheet(controller: c, exercise: ex)) { w in
            try await w.settle()
            #expect(w.node("Done", exactly: true)?.identifier == "restSheet.done")
            #expect(w.node("Rest for this exercise", exactly: true)?.traits.contains(.header) == true)
            #expect(w.nodes().filter { $0.identifier?.hasPrefix("restChoice.") == true }.count == RestChoices.presets.count)
            // The rows pad themselves: 20 from the side, as before the shared frame.
            let first = try #require(w.nodes().first { $0.identifier == "restChoice.\(RestChoices.presets[0])" }).frame
            #expect(abs(first.minX - Theme.Metrics.screenPadding) < 1, "\(first)")
        }
    }

    // MARK: the live workout

    /// The bug the integration found: `PlaceholderOutline` as an overlay filled `surface` over the message.
    @Test("Focused's empty page shows its message: the outline is a stroke over the card, not a filled placeholder")
    func focusedsEmptyPage() async throws {
        let c = FocusedPreview.controller(.empty)
        defer { c.stop() }
        #expect(c.layout == .focused)
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c)) { w in
            try await w.settle()
            let message = try #require(w.node("An empty session. Add your first exercise.")).frame
            let ink = Self.inkPixels(across: message, in: w)
            #expect(ink > 4, "the message is drawn: \(ink) ink pixels")
        }
    }

    @Test("The exercise page from the live workout: a sheet with the sheet header's close circle, which closes it")
    func theExercisePageSheet() async throws {
        let c = FocusedPreview.controller(.midSession)
        defer { c.stop() }
        let page = try #require(c.pageExercise)
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c)) { w in
            try await w.settle()
            #expect(w.host.presentedViewController == nil, "no sheet yet")
            #expect(try #require(w.node("\(page.name), history", exactly: true)).activate())
            // A presented sheet's elements live beside the host's: `presentedNodes()`.
            @MainActor func sheetNode(_ label: String) -> HostedWindow.Node? { w.presentedNodes()?.first { $0.label == label } }
            try await w.wait("the exercise page's sheet") { sheetNode("Close")?.identifier == "sheet.close" }
            #expect(w.presentedNodes()?.contains { $0.label == page.name && $0.traits.contains(.header) } == true,
                    "the page's title in its header")
            #expect(try #require(sheetNode("Close")).activate())
            try await w.wait("the sheet closes") { w.host.presentedViewController == nil }
        }
    }
}
