import SwiftUI
import Testing
@testable import Ryft

/// The live workout's shell in Nocturne (PR 6 B §4.1–§4.5, §14.2): its numbers and the row inks, by maths. Dark, the app's one
/// appearance. The hosted half is `LiveSessionShellHostedTests`. On the main actor: the views' numbers are theirs.
@MainActor
@Suite("Live workout shell")
struct LiveSessionShellTests {
    // MARK: the numbers (§4)

    /// Its height is pinned in a window: `LiveSessionShellHostedTests.headerGeometry`.
    @Test("The header: 16 pt sides (12 at 320), 44 pt buttons, 6 above and below, 8 apart (6 at 320)")
    func header() {
        #expect(LiveSessionSpec.sidePadding == 16 && LiveSessionSpec.compactSidePadding == 12)
        #expect(LiveSessionSpec.headerRow == 44 && LiveSessionSpec.headerVerticalPadding == 6)
        #expect(LiveSessionSpec.headerGap == 8 && LiveSessionSpec.compactHeaderGap == 6)
        #expect(LiveSessionSpec.clock == 30 && LiveSessionSpec.compactClock == 26 && LiveSessionSpec.compactClockScale == 0.8)
        #expect(LiveSessionSpec.finishCap == .xxLarge && LiveSessionSpec.compactFinishCap == .large)
        #expect(LiveSessionSpec.compactTitleCap == .accessibility1)
    }

    /// D6B-3: the circles are `CircleButton`'s 40 in 44, the pill the compact one.
    @Test("The header's buttons are a circle button's 40 pt in a 44 pt box, and Finish is the compact pill in the same box")
    func headerButtons() {
        #expect(CircleButton.diameter == 40 && CircleButton.hitSize == LiveSessionSpec.headerRow)
        #expect(PillButton.compactHeight == 40 && PillButton.compactHitHeight == LiveSessionSpec.headerRow)
    }

    /// The geometry the Focused tests pinned before: Nocturne changes inks, not these.
    @Test("The strip, its tiles and the page's fade keep their sizes")
    func focusedGeometry() {
        #expect(ExerciseStrip.height == 76 && LiveSessionSpec.strip == 76 && LiveSessionSpec.stripTop == 8)
        #expect(ExerciseTile.size == 56 && ExerciseTile.largeSize == 64)
        #expect(FocusedSessionView.topFade == 16)
        #expect(SetTableColumns.fitting(width: 390).padding == LiveSessionSpec.sidePadding)
        #expect(SetTableColumns.fitting(width: 320).padding == LiveSessionSpec.compactSidePadding)
    }

    @Test("The active row's bar: 2 pt, 10 outside the row at 390 and 6 at 320, so 6 from the screen's edge at either; row − 16 high",
          arguments: [(16 as CGFloat, 10 as CGFloat), (12, 6)])
    func theBar(_ c: (padding: CGFloat, outset: CGFloat)) {
        #expect(LiveSessionSpec.activeBarWidth == 2)
        #expect(LiveSessionSpec.activeBarOutset(padding: c.padding) == c.outset)
        #expect(c.padding - LiveSessionSpec.activeBarOutset(padding: c.padding) == LiveSessionSpec.activeBarFromEdge)
        #expect(LiveSessionSpec.activeBarHeight(rowHeight: 56) == 40)
        #expect(LiveSessionSpec.activeBarHeight(rowHeight: 64) == 48)
    }

    @Test("The rest pill: an outline idle and running, ink 12 % and 20 %; a 24 pt ring on an ink track at 16 %")
    func restPill() {
        #expect(RestPill.idleEdge == 0.12 && RestPill.runningEdge == 0.20 && RestPill.overFill == 0.12)
        #expect(RestPill.idleEdge == LiveSessionSpec.restingEdge && RestPill.runningEdge == OutlinedKey.edge)
        #expect(RestPill.ring == 24 && RestPill.ringLine == 3 && RestPill.ringTrack == 0.16)
        #expect(RestPill.idleMinWidth == 112 && RestPill.runningMinWidth == 144)
    }

    /// §4.5, §4.6: the rest sheet's ±15 s, the keypad's steps and the plate calculator's are one key, the secondary pill's edge
    /// at the row's radius. The chips and the idle pill share the resting 12 %.
    @Test("One outlined key: the secondary pill's 20 % edge (10 % off) at radius 14; the chips' edge the resting 12 %")
    func outlinedKey() {
        #expect(OutlinedKey.edge == PillButton.outlineOpacity && OutlinedKey.edge == 0.20 && OutlinedKey.disabledEdge == 0.10)
        #expect(OutlinedKey.radius == LiveSessionSpec.rowRadius && NumberPad.keyRadius == LiveSessionSpec.rowRadius)
        #expect(LiveSessionSpec.restingEdge == 0.12 && SessionChip.edge == Theme.textPrimary.opacity(LiveSessionSpec.restingEdge))
    }

    // MARK: the row inks (§4.3)

    private typealias RGBA = (r: Double, g: Double, b: Double, a: Double)

    private func parts(_ color: Color) -> RGBA {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let c = color.resolve(in: environment)
        return (Double(c.red), Double(c.green), Double(c.blue), Double(c.opacity))
    }

    private func over(_ top: RGBA, _ bottom: RGBA) -> RGBA {
        func mix(_ t: Double, _ b: Double) -> Double { t * top.a + b * (1 - top.a) }
        return (mix(top.r, bottom.r), mix(top.g, bottom.g), mix(top.b, bottom.b), 1)
    }

    private func luminance(_ c: RGBA) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private func contrast(_ ink: Color, on ground: RGBA) -> Double {
        let a = luminance(over(parts(ink), ground)), b = luminance(ground)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @Test("The active ✓ is the one filled ink square, its glyph the screen's colour at 17:1; the others have no fill")
    func theCheck() {
        #expect(FocusedRowInk.checkFill(.active) == Theme.textPrimary)
        #expect(FocusedRowInk.checkGlyph(.active) == Theme.background)
        #expect(contrast(FocusedRowInk.checkGlyph(.active), on: parts(Theme.textPrimary)) >= 17)
        #expect(FocusedRowInk.checkFill(.done) == .clear && FocusedRowInk.checkFill(.upcoming) == .clear)
        #expect(FocusedRowInk.checkGlyph(.done) == Theme.textSecondary)
        #expect(FocusedRowInk.checkGlyph(.upcoming) == Theme.textTertiary)
    }

    @Test("The active row's tint is ink at 5 %; its marks are Volt; the keypad's ring is ink")
    func theActiveRow() {
        #expect(FocusedRowInk.activeTint == 0.05)
        #expect(abs(parts(FocusedRowInk.activeRowFill(true)).a - 0.05) < 0.001)
        #expect(parts(FocusedRowInk.activeRowFill(false)).a < 0.001)
        #expect(FocusedRowInk.mark == Theme.signal)
        #expect(FocusedRowInk.focusRing == Theme.textPrimary)
    }

    /// List raises its upcoming fields at 55 %: an empty one there is grey, as on the active row (`textTertiary` on the raised
    /// fill is under 4.5:1).
    @Test("An empty field on a raised fill is grey and holds 4.5:1 on it")
    func anEmptyRaisedField() {
        let ink = FocusedRowInk.value(.upcoming, hasValue: false, hasGhost: false, onRaisedField: true)
        #expect(ink == Theme.textSecondary)
        #expect(contrast(ink, on: parts(Theme.surfaceRaised)) >= 4.5)
        #expect(FocusedRowInk.value(.upcoming, hasValue: false, hasGhost: false) == Theme.textTertiary)
        // A done row's field the keypad types into is raised too.
        let done = FocusedRowInk.value(.done, hasValue: false, hasGhost: false, onRaisedField: true)
        #expect(done == Theme.textSecondary)
        #expect(contrast(done, on: parts(Theme.surfaceRaised)) >= 4.5)
        #expect(FocusedRowInk.value(.done, hasValue: false, hasGhost: false) == Theme.textTertiary)
    }
}

/// The shell in real windows (PR 6 B §14.2): the header's geometry and VoiceOver order, the active row's marks, the running
/// pill, and List's row inks, read through the accessibility tree and the window's pixels. Synthetic values only.
@MainActor
@Suite("Live workout shell, hosted", .serialized)
struct LiveSessionShellHostedTests {
    struct WidthCase: Sendable, CustomTestStringConvertible {
        let width: CGFloat, height: CGFloat
        var side: CGFloat { width < 360 ? LiveSessionSpec.compactSidePadding : LiveSessionSpec.sidePadding }
        var gap: CGFloat { width < 360 ? LiveSessionSpec.compactHeaderGap : LiveSessionSpec.headerGap }
        var testDescription: String { "\(Int(width)) pt" }
    }

    nonisolated static let widths = [WidthCase(width: 390, height: 844), WidthCase(width: 320, height: 693)]

    /// The circle's edge, not its 44 pt box, is on the page's side: the box overhangs it by 2.
    private static let overhang = (CircleButton.hitSize - CircleButton.diameter) / 2

    @Test("Focused's header: the circles' edges on the sides, 44 pt boxes, Finish 8 from More (6 at 320)", arguments: widths)
    func headerGeometry(_ s: WidthCase) async throws {
        let c = FocusedPreview.controller(.draft)
        defer { c.stop() }
        try await HostedWindow.run(width: s.width, height: s.height, SessionView(controller: c)) { w in
            try await w.settle()
            let minimise = try #require(w.node("Minimise", exactly: true)).frame
            let more = try #require(w.node("More", exactly: true)).frame
            let finish = try #require(w.node("Finish", exactly: true)).frame
            #expect(abs(minimise.width - 44) < 0.5 && abs(minimise.height - 44) < 0.5, "\(minimise)")
            #expect(abs(more.width - 44) < 0.5 && abs(more.height - 44) < 0.5, "\(more)")
            #expect(abs(minimise.minX + Self.overhang - s.side) < 0.5, "\(minimise)")
            #expect(abs(finish.maxX - (s.width - s.side)) < 0.5, "\(finish)")
            #expect(abs(finish.minX - (more.maxX - Self.overhang) - s.gap) < 0.5, "More \(more), Finish \(finish)")
            #expect(abs(finish.height - PillButton.compactHitHeight) < 0.5, "\(finish)")
            #expect(abs(finish.midY - more.midY) < 0.5 && abs(more.midY - minimise.midY) < 0.5, "one row")
            // Its height, from the window's top to the strip (its first tile less the strip's top): 6 + the taller of the
            // buttons and the title over the clock + 6. The strip's own element isn't in the tree the window walks.
            let titleAndClock = try #require(w.node("\(c.session.title), elapsed time", exactly: true)).frame
            let tile = try #require(w.nodes().first { $0.identifier?.hasPrefix("session.strip.") == true }).frame
            let height = tile.minY - LiveSessionSpec.stripTop - w.host.view.safeAreaInsets.top
            let expected = 2 * LiveSessionSpec.headerVerticalPadding + max(LiveSessionSpec.headerRow, titleAndClock.height)
            #expect(abs(height - expected) < 0.5, "header \(height), title and clock \(titleAndClock), tile \(tile)")
        }
    }

    /// §4.1 at 320 in List too: 12 pt sides, 6 pt gaps, and an hour clock on one line at 26 pt. A clock under a minute is the
    /// reference: one line in any header, so the same height means "1:23:45" didn't break.
    @Test("List's header at 320: the circles on 12 pt sides, 6 apart, \"1:23:45\" on one line")
    func listsCompactHeader() async throws {
        var heights: [CGFloat] = []
        for elapsed in [5025.0, 42] {
            let c = FocusedPreview.controller(.draftList)
            defer { c.stop() }
            #expect(c.layout == .list)
            c.session.startedAt = Date().addingTimeInterval(-elapsed)
            try await HostedWindow.run(width: 320, height: 693, SessionView(controller: c)) { w in
                try await w.settle()
                let minimise = try #require(w.node("Minimise", exactly: true)).frame
                let more = try #require(w.node("More", exactly: true)).frame
                let finish = try #require(w.node("Finish", exactly: true)).frame
                let clock = try #require(w.node("\(c.session.title), elapsed time", exactly: true))
                #expect(abs(minimise.minX + Self.overhang - LiveSessionSpec.compactSidePadding) < 0.5, "\(minimise)")
                #expect(abs(finish.maxX - (320 - LiveSessionSpec.compactSidePadding)) < 0.5, "\(finish)")
                #expect(abs(finish.minX - (more.maxX - Self.overhang) - LiveSessionSpec.compactHeaderGap) < 0.5, "\(more) \(finish)")
                #expect(abs(c.elapsed(at: .now) - elapsed) < 60, "\(c.elapsed(at: .now))")
                heights.append(clock.frame.height)
            }
        }
        #expect(heights.count == 2 && abs(heights[0] - heights[1]) < 0.5, "1:23:45 \(heights.first ?? 0), 0:42 \(heights.last ?? 0)")
    }

    @Test("VoiceOver reads Focused's header as one row: Minimise, the title and clock, More, Finish")
    func headerOrder() async throws {
        let c = FocusedPreview.controller(.draft)
        defer { c.stop() }
        let title = c.session.title
        try await HostedWindow.run(width: 390, height: 844, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                   SessionView(controller: c)) { w in
            try await w.settle()
            let labels = w.nodes().map(\.label)
            let order = ["Minimise", "\(title), elapsed time", "More", "Finish"].map { wanted in labels.firstIndex(of: wanted) }
            let found = order.compactMap { $0 }
            #expect(found.count == 4 && found == found.sorted(), "order \(order): \(labels.prefix(8))")
            #expect(w.node("Minimise", exactly: true)?.hint == "The workout keeps running")
            #expect(w.node("Finish", exactly: true)?.identifier == "session.finish")
        }
    }

    private typealias RGB = FocusedPolishHostedTests.RGB

    private static func rgb(_ color: Color) -> RGB { FocusedPolishHostedTests.rgb(color) }

    /// For a flat colour, where the render is exact: a 6 % tint or a 4-point change of an outline's opacity stays outside it.
    private static let exact = FocusedPolishHostedTests.exact

    private static func isClose(_ p: RGB, _ color: Color, tolerance: Double = 0.06) -> Bool {
        FocusedPolishHostedTests.isClose(p, to: rgb(color), tolerance: tolerance)
    }

    /// `b-04`: set 2 of Barbell row is active. The bar is 6 pt from the screen's edge; the ✓'s fill is ink, sampled above its
    /// glyph; an upcoming row has neither.
    @Test("The active row: a Volt bar at its leading edge and the ✓ filled ink; an upcoming row neither", arguments: widths)
    func theActiveRowsMarks(_ s: WidthCase) async throws {
        let c = FocusedPreview.controller(.draft)
        defer { c.stop() }
        try await HostedWindow.run(width: s.width, height: s.height, SessionView(controller: c)) { w in
            try await w.settle()
            let active = try #require(w.node("Set 2 of")).frame
            let upcoming = try #require(w.node("Set 3 of")).frame
            #expect(w.node("Set 2 of")?.value == "Next set.")
            let barX = LiveSessionSpec.activeBarFromEdge + LiveSessionSpec.activeBarWidth / 2
            let rowMid = LiveSessionSpec.activeBarInset + LiveSessionSpec.activeBarHeight(rowHeight: 56) / 2
            let bar = try #require(w.pixel(at: CGPoint(x: barX, y: active.minY + rowMid)))
            #expect(Self.isClose(bar, Theme.signal, tolerance: 0.1), "\(bar)")
            let noBar = try #require(w.pixel(at: CGPoint(x: barX, y: upcoming.minY + rowMid)))
            #expect(Self.isClose(noBar, Theme.background), "\(noBar)")

            let checkX = active.maxX - 28
            let fill = try #require(w.pixel(at: CGPoint(x: checkX, y: active.minY + 6)))
            #expect(Self.isClose(fill, Theme.textPrimary), "\(fill)")
            let open = try #require(w.pixel(at: CGPoint(x: checkX, y: upcoming.minY + 6)))
            #expect(Self.isClose(open, Theme.background), "\(open)")
        }
    }

    /// `b-04`: 1:54 left. The ring's progress starts at 12 o'clock; inside the capsule it is the `surface` outline, not a fill.
    @Test("The running pill is an outline on surface with a Volt ring")
    func theRunningPill() async throws {
        let c = FocusedPreview.controller(.draft)
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c)) { w in
            try await w.settle()
            let pill = try #require(w.node("Rest", exactly: true)).frame
            #expect(c.rest.isRunning)
            let inside = try #require(w.pixel(at: CGPoint(x: pill.maxX - 12, y: pill.minY + 6)))
            #expect(Self.isClose(inside, Theme.surface, tolerance: Self.exact), "\(inside)")
            // The ring's top, where its progress starts: the pill centres its content in its 144 pt, so walk the leading half
            // of that line. Nothing else in the pill is Volt.
            let top = pill.midY - RestPill.ring / 2
            var ring: [(r: Double, g: Double, b: Double)] = []
            for x in stride(from: pill.minX + 8, through: pill.midX, by: 1) {
                if let p = w.pixel(at: CGPoint(x: x, y: top)) { ring.append(p) }
            }
            #expect(ring.contains { Self.isClose($0, Theme.signal, tolerance: 0.12) }, "\(ring.prefix(6))")
        }
    }

    /// `b-02`, §4.7: Bench press, set 1 done, set 2 the current set, set 3 upcoming. No done-row tint, no filled done ✓.
    @Test("List's rows: the current set's ✓ filled ink; a done row and an upcoming one have none, on the card's surface")
    func listInks() async throws {
        let c = FocusedPreview.controller(.draftList)
        defer { c.stop() }
        #expect(c.layout == .list)
        try await HostedWindow.run(width: 390, height: 1400, SessionView(controller: c)) { w in
            try await w.settle()
            let done = try #require(w.node("Set 1 of")).frame
            let active = try #require(w.node("Set 2 of")).frame
            let upcoming = try #require(w.node("Set 3 of")).frame
            let fill = try #require(w.pixel(at: CGPoint(x: active.maxX - 28, y: active.minY + 6)))
            #expect(Self.isClose(fill, Theme.textPrimary), "\(fill)")
            for (name, row) in [("done", done), ("upcoming", upcoming)] {
                let check = try #require(w.pixel(at: CGPoint(x: row.maxX - 28, y: row.minY + 6)))
                #expect(Self.isClose(check, Theme.surface), "\(name) ✓ \(check)")
            }
            // The row's own ground: its top middle, above the fields' 4 pt inset. Not its leading edge: the element starts about
            // 7 pt left of the row's background, so a tint there went unseen.
            let doneGround = try #require(w.pixel(at: CGPoint(x: done.midX, y: done.minY + 2)))
            #expect(Self.isClose(doneGround, Theme.surface, tolerance: Self.exact), "a done row has no tint: \(doneGround)")
        }
    }

    @Test("The rest sheet's header: \"Rest\" a heading, the close circle \"Done\" with its old identifier")
    func restSheetHeader() async throws {
        let c = FocusedPreview.controller(.draft)
        defer { c.stop() }
        let ex = try #require(c.pageExercise)
        try await HostedWindow.run(width: 390, height: 844, RestSheet(controller: c, exercise: ex)) { w in
            try await w.settle()
            let title = try #require(w.node("Rest", exactly: true))
            #expect(title.traits.contains(.header))
            let done = try #require(w.node("Done", exactly: true))
            #expect(done.identifier == "restSheet.done")
            #expect(abs(done.frame.width - 44) < 0.5, "\(done.frame)")
            #expect(w.nodes().first { $0.identifier == "restSheet.value" }?.label == "Rest", "the clock keeps its label")
        }
    }
}
