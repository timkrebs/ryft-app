import SwiftUI
import Testing
@testable import Ryft

/// The Nocturne components' numbers (docs/work/2026-11-16-nocturne/design.md §P2-7, tests 1–15): the glyph table, every size,
/// pitch and tick position, the gradient stops, the form tokens. Pure: no pixels, no windows. A change to a number here is
/// a design decision (the spec and the boards move with it), not an accident.
@MainActor
@Suite struct NocturneComponentTests {
    private typealias Tokens = NocturneTokenTests

    // MARK: 1–2. The glyph table

    struct GlyphCase: Sendable, CustomTestStringConvertible {
        let character: Character
        let width: Int
        let rows: [UInt8]
        let lit: Int
        var testDescription: String { "'\(character)'" }
    }

    /// §P2-5, written out here and not read from the code: rows top to bottom, the left column is the highest used bit.
    nonisolated static let glyphs: [GlyphCase] = [
        GlyphCase(character: "0", width: 5, rows: [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110], lit: 16),
        GlyphCase(character: "1", width: 5, rows: [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110], lit: 10),
        GlyphCase(character: "2", width: 5, rows: [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111], lit: 14),
        GlyphCase(character: "3", width: 5, rows: [0b01110, 0b10001, 0b00001, 0b00110, 0b00001, 0b10001, 0b01110], lit: 14),
        GlyphCase(character: "4", width: 5, rows: [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010], lit: 14),
        GlyphCase(character: "5", width: 5, rows: [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110], lit: 17),
        GlyphCase(character: "6", width: 5, rows: [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110], lit: 15),
        GlyphCase(character: "7", width: 5, rows: [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000], lit: 11),
        GlyphCase(character: "8", width: 5, rows: [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110], lit: 17),
        GlyphCase(character: "9", width: 5, rows: [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100], lit: 15),
        GlyphCase(character: ":", width: 1, rows: [0b0, 0b0, 0b1, 0b0, 0b1, 0b0, 0b0], lit: 2),
        GlyphCase(character: ".", width: 1, rows: [0b0, 0b0, 0b0, 0b0, 0b0, 0b0, 0b1], lit: 1),
        GlyphCase(character: ",", width: 1, rows: [0b0, 0b0, 0b0, 0b0, 0b0, 0b1, 0b1], lit: 2),
    ]

    @Test("Spec 1: the table has exactly the 13 keys")
    func theTableHasThirteenKeys() {
        #expect(Set(DotGlyphs.table.keys) == Set(Self.glyphs.map(\.character)))
        #expect(DotGlyphs.table.count == 13)
        #expect(DotGlyphs.rowCount == 7)
    }

    @Test("Spec 1: width and all seven rows of each glyph are the pinned ones", arguments: glyphs)
    func glyphIsPinned(_ g: GlyphCase) throws {
        let glyph = try #require(DotGlyphs.table[g.character])
        #expect(glyph.width == g.width)
        #expect(glyph.rows == g.rows)
        #expect(glyph.rows.count == 7)
    }

    @Test("Spec 1: no row has a bit at or above the glyph's width", arguments: glyphs)
    func noRowOverflowsItsWidth(_ g: GlyphCase) throws {
        let glyph = try #require(DotGlyphs.table[g.character])
        for (index, row) in glyph.rows.enumerated() {
            #expect(Int(row) >> glyph.width == 0, "row \(index) of '\(g.character)': \(String(row, radix: 2))")
        }
    }

    @Test("Spec 2: the lit dots of each glyph are the §P2-5 count", arguments: glyphs)
    func litDotCount(_ g: GlyphCase) throws {
        let glyph = try #require(DotGlyphs.table[g.character])
        #expect(glyph.rows.reduce(0) { $0 + $1.nonzeroBitCount } == g.lit)
        // The same count through the public per-dot accessor, the one the drawing uses.
        var viaIsLit = 0
        for row in 0..<7 { for column in 0..<glyph.width where glyph.isLit(row: row, column: column) { viaIsLit += 1 } }
        #expect(viaIsLit == g.lit)
    }

    @Test("The most significant used bit is the left column")
    func theLeftColumnIsTheHighBit() throws {
        // '7': top row all five lit; row 1 only the right column; row 4 (0b01000) column 1.
        let seven = try #require(DotGlyphs.table["7"])
        #expect((0..<5).allSatisfy { seven.isLit(row: 0, column: $0) })
        #expect(seven.isLit(row: 1, column: 4) && !seven.isLit(row: 1, column: 0))
        #expect(seven.isLit(row: 4, column: 1) && !seven.isLit(row: 4, column: 3))
        // ':' lights rows 3 and 5 (indices 2 and 4), '.' row 7, ',' rows 6 and 7.
        let colon = try #require(DotGlyphs.table[":"])
        #expect((0..<7).filter { colon.isLit(row: $0, column: 0) } == [2, 4])
        let stop = try #require(DotGlyphs.table["."])
        #expect((0..<7).filter { stop.isLit(row: $0, column: 0) } == [6])
        let comma = try #require(DotGlyphs.table[","])
        #expect((0..<7).filter { comma.isLit(row: $0, column: 0) } == [5, 6])
    }

    // MARK: 3. glyphs(for:)

    @Test("Spec 3: \"7:48\" is four glyphs of widths 5, 1, 5, 5")
    func glyphsOfATime() throws {
        let glyphs = try #require(DotGlyphs.glyphs(for: "7:48"))
        #expect(glyphs.map(\.width) == [5, 1, 5, 5])
        #expect(glyphs == ["7", ":", "4", "8"].map { DotGlyphs.table[Character($0)]! })
    }

    @Test("Spec 3: a character outside the table makes the whole string nil",
          arguments: ["7h", "7 ", " 7", "-", "84%", "1e3", "٨٤", "８４", "a"])
    func unknownCharactersAreNil(_ text: String) {
        #expect(DotGlyphs.glyphs(for: text) == nil)
    }

    /// Decided by the implementation: there is nothing to draw, so the empty string takes the Light fallback like any
    /// other text the grid cannot show.
    @Test("The empty string has no glyphs (the Light fallback)")
    func emptyStringIsNil() {
        #expect(DotGlyphs.glyphs(for: "") == nil)
    }

    @Test("A region's separator is one narrow glyph: \"12,4\" and \"12.4\" have the same widths")
    func bothDecimalSeparators() throws {
        let comma = try #require(DotGlyphs.glyphs(for: "12,4")), stop = try #require(DotGlyphs.glyphs(for: "12.4"))
        #expect(comma.map(\.width) == [5, 5, 1, 5] && stop.map(\.width) == [5, 5, 1, 5])
    }

    @Test("The pending cell is a digit wide with nothing lit")
    func placeholderCell() {
        #expect(DotGlyphs.placeholder.width == 5)
        #expect(DotGlyphs.placeholder.rows == Array(repeating: 0, count: 7))
    }

    // MARK: 4. Sizes

    struct SizeCase: Sendable, CustomTestStringConvertible {
        let text: String
        let gap: CGFloat
        let width: CGFloat
        var testDescription: String { "\"\(text)\", gap \(Int(gap))" }
    }

    @Test("Spec 4: the layout width is Σ glyph widths + (n−1)·gap, 47 high", arguments: [
        SizeCase(text: "84", gap: 8, width: 74), SizeCase(text: "84", gap: 7, width: 73),
        SizeCase(text: "7:48", gap: 8, width: 128), SizeCase(text: "7:48", gap: 7, width: 125),
        SizeCase(text: "12.4", gap: 8, width: 128), SizeCase(text: "12.4", gap: 7, width: 125),
        SizeCase(text: "12,4", gap: 8, width: 128), SizeCase(text: "12,4", gap: 7, width: 125),
        SizeCase(text: "0", gap: 8, width: 33), SizeCase(text: "0", gap: 7, width: 33),
        SizeCase(text: ":", gap: 8, width: 5), SizeCase(text: ".", gap: 7, width: 5),
        SizeCase(text: "100", gap: 8, width: 115),
    ])
    func layoutSize(_ c: SizeCase) {
        #expect(DotNumeral.size(of: c.text, glyphGap: c.gap) == CGSize(width: c.width, height: 47))
    }

    @Test("Spec 4: a glyph is w·5 + (w−1)·2 wide: 33 for five columns, 5 for one")
    func glyphWidths() throws {
        #expect(DotNumeral.width(of: try #require(DotGlyphs.table["8"])) == 33)
        #expect(DotNumeral.width(of: try #require(DotGlyphs.table[":"])) == 5)
        #expect(DotNumeral.width(of: DotGlyphs.placeholder) == 33)
    }

    @Test("Spec 4: pending with two placeholders is 74×47; the placeholder count scales the width")
    func pendingSize() {
        #expect(DotNumeral.size(of: nil, glyphGap: 8) == CGSize(width: 74, height: 47))
        #expect(DotNumeral.size(of: nil, placeholderGlyphs: 2, glyphGap: 7) == CGSize(width: 73, height: 47))
        #expect(DotNumeral.size(of: nil, placeholderGlyphs: 3, glyphGap: 8) == CGSize(width: 115, height: 47))
        #expect(DotNumeral.size(of: nil, placeholderGlyphs: 1, glyphGap: 8) == CGSize(width: 33, height: 47))
    }

    /// Decided by the implementation: a pending numeral never draws nothing.
    @Test("placeholderGlyphs of zero or less still draws one cell", arguments: [0, -1, -50])
    func placeholderCountIsAtLeastOne(_ count: Int) {
        #expect(DotNumeral.size(of: nil, placeholderGlyphs: count, glyphGap: 8) == CGSize(width: 33, height: 47))
        let cells = DotNumeral.cells(nil, placeholderGlyphs: count, glyphGap: 8)
        #expect(cells?.unlit.count == 35 && cells?.lit.isEmpty == true)
    }

    @Test("Spec 4: a string outside the table has no layout size", arguments: ["7h", "", " ", "84 "])
    func sizeOutsideTheTable(_ text: String) {
        #expect(DotNumeral.size(of: text, glyphGap: 8) == nil)
        #expect(DotNumeral.cells(text, glyphGap: 8) == nil)
    }

    // MARK: Glyph pitch and dot centres

    @Test("The next glyph starts at this one's right edge + the gap, narrow glyphs included")
    func glyphPitch() throws {
        // "7:8" at gap 8: '7' 0…33, ':' at 41…46, '8' at 54…87.
        let cells = try #require(DotNumeral.cells("7:8", glyphGap: 8))
        #expect(cells.size == CGSize(width: 87, height: 47))
        // The colon's lit dots: column 0 of x₀ = 41 → x 43.5, rows 3 and 5 → y 16.5 and 30.5.
        let colon = cells.lit.filter { $0.x > 40 && $0.x < 47 }
        #expect(colon == [CGPoint(x: 43.5, y: 16.5), CGPoint(x: 43.5, y: 30.5)])
        // The 8's top row: columns 1…3 of x₀ = 54 → x 54 + 7 + 2.5 …
        let eightTop = cells.lit.filter { $0.x > 53 && $0.y == 2.5 }.map(\.x)
        #expect(eightTop == [63.5, 70.5, 77.5])
    }

    @Test("A dot's centre is (x₀ + c·7 + 2.5, r·7 + 2.5); lit and unlit tile the glyph")
    func dotCentres() throws {
        let cells = try #require(DotNumeral.cells("84", glyphGap: 8))
        #expect(cells.lit.count + cells.unlit.count == 70)
        #expect(cells.lit.count == 17 + 14)
        #expect(cells.lit.allSatisfy { !cells.unlit.contains($0) })   // not Set: CGPoint is Hashable only from iOS 18
        // The 8's top-left corner is unlit at (2.5, 2.5); its first lit dot is column 1.
        #expect(cells.unlit.contains(CGPoint(x: 2.5, y: 2.5)))
        #expect(cells.lit.contains(CGPoint(x: 9.5, y: 2.5)))
        // The 4 starts at x₀ = 33 + 8 = 41; its top row lights only column 3 → x 41 + 21 + 2.5.
        #expect(cells.lit.filter { $0.x > 40 && $0.y == 2.5 } == [CGPoint(x: 64.5, y: 2.5)])
        // The lowest row's centre is 6·7 + 2.5 = 44.5 (the bottom edge is 47).
        #expect(cells.lit.map(\.y).max() == 44.5)
    }

    @Test("A time lights the sum of its glyphs' dots, and the cells carry the layout size")
    func litTotalOfATime() throws {
        let cells = try #require(DotNumeral.cells("7:48", glyphGap: 7))
        #expect(cells.lit.count == 11 + 2 + 14 + 17)
        #expect(cells.size == DotNumeral.size(of: "7:48", glyphGap: 7))
        #expect(cells.lit.count + cells.unlit.count == 35 * 3 + 7)
    }

    @Test("Pending lights nothing: every cell of every placeholder is unlit")
    func pendingIsAllUnlit() throws {
        let cells = try #require(DotNumeral.cells(nil, glyphGap: 8))
        #expect(cells.lit.isEmpty)
        #expect(cells.unlit.count == 70)
    }

    @Test("The numeral's constants: dot 5, gap 2, height 47, glyph gaps 8 and 7, off 10 %, Light 52")
    func numeralConstants() {
        #expect(DotNumeral.dot == 5 && DotNumeral.dotGap == 2 && DotNumeral.height == 47)
        #expect(DotNumeral.height == 7 * DotNumeral.dot + 6 * DotNumeral.dotGap)
        #expect(DotNumeral.glyphGapToday == 8 && DotNumeral.glyphGapDetail == 7)
        #expect(DotNumeral.offOpacity == 0.10 && DotNumeral.lightSize == 52)
    }

    // MARK: 5. The Light fallback

    struct FallbackCase: Sendable, CustomTestStringConvertible {
        let text: String?
        let style: DotNumeral.Style
        let typeSize: DynamicTypeSize
        let dots: Bool
        var testDescription: String { "\(text.map { "\"\($0)\"" } ?? "nil"), \(style), \(typeSize) -> \(dots ? "dots" : "light")" }
    }

    @Test("Spec 5: dots below AX1, Light from AX1, with .light, and for text outside the table", arguments: [
        FallbackCase(text: "84", style: .dots, typeSize: .xSmall, dots: true),
        FallbackCase(text: "84", style: .dots, typeSize: .large, dots: true),
        FallbackCase(text: "84", style: .dots, typeSize: .xxxLarge, dots: true),
        FallbackCase(text: "84", style: .dots, typeSize: .accessibility1, dots: false),
        FallbackCase(text: "84", style: .dots, typeSize: .accessibility2, dots: false),
        FallbackCase(text: "84", style: .dots, typeSize: .accessibility3, dots: false),
        FallbackCase(text: "84", style: .dots, typeSize: .accessibility5, dots: false),
        FallbackCase(text: "84", style: .light, typeSize: .large, dots: false),
        FallbackCase(text: "7h", style: .dots, typeSize: .large, dots: false),
        FallbackCase(text: "", style: .dots, typeSize: .large, dots: false),
        FallbackCase(text: " ", style: .dots, typeSize: .large, dots: false),
        FallbackCase(text: nil, style: .dots, typeSize: .large, dots: true),
        FallbackCase(text: nil, style: .dots, typeSize: .accessibility1, dots: false),
        FallbackCase(text: nil, style: .light, typeSize: .large, dots: false),
    ])
    func fallback(_ c: FallbackCase) {
        #expect(DotNumeral.rendersDots(c.text, style: c.style, typeSize: c.typeSize) == c.dots)
    }

    @Test("Spec 5: the fallback starts exactly at the first accessibility size")
    func fallbackBoundary() {
        for size in DynamicTypeSize.allCases {
            #expect(DotNumeral.rendersDots("84", style: .dots, typeSize: size) == !size.isAccessibilitySize, "\(size)")
        }
        #expect(DynamicTypeSize.xxxLarge.isAccessibilitySize == false && DynamicTypeSize.accessibility1.isAccessibilitySize)
    }

    // MARK: 6. Tick centres

    @Test("Spec 6: 61 ticks over 300 are 5 apart, from 0 to 300")
    func todayCentres() {
        let c = RulerScale.tickCentres(count: 61, width: 300)
        #expect(c.count == 61 && c.first == 0 && c.last == 300)
        for (i, x) in c.enumerated() { #expect(abs(x - CGFloat(i) * 5) < 1e-9, "tick \(i)") }
    }

    @Test("Spec 6: 64 ticks over 630 are 10 apart")
    func strainCentres() {
        let c = RulerScale.tickCentres(count: 64, width: 630)
        #expect(c.count == 64 && c.first == 0 && c.last == 630)
        for (i, x) in c.enumerated() { #expect(abs(x - CGFloat(i) * 10) < 1e-9, "tick \(i)") }
    }

    @Test("Spec 6: two ticks are the two edges; a count of 1, 0 or less behaves as 2", arguments: [2, 1, 0, -4])
    func twoTickMinimum(_ count: Int) {
        #expect(RulerScale.tickCentres(count: count, width: 200) == [0, 200])
    }

    // MARK: 7. Needle x

    struct NeedleCase: Sendable, CustomTestStringConvertible {
        let value: Double?
        let low: Double, high: Double
        let x: CGFloat?
        var testDescription: String { "\(value.map { "\($0)" } ?? "nil") in \(low)…\(high)" }
    }

    @Test("Spec 7: the needle is at the value's fraction of the width, clamped to the ends", arguments: [
        NeedleCase(value: 84, low: 0, high: 100, x: 252), NeedleCase(value: 0, low: 0, high: 100, x: 0),
        NeedleCase(value: 100, low: 0, high: 100, x: 300), NeedleCase(value: 50, low: 0, high: 100, x: 150),
        NeedleCase(value: 150, low: 0, high: 100, x: 300), NeedleCase(value: -10, low: 0, high: 100, x: 0),
        NeedleCase(value: 1e9, low: 0, high: 100, x: 300), NeedleCase(value: -.infinity, low: 0, high: 100, x: 0),
        NeedleCase(value: .infinity, low: 0, high: 100, x: 300),
        NeedleCase(value: 10.5, low: 0, high: 21, x: 150), NeedleCase(value: 7.5, low: 0, high: 10, x: 225),
        NeedleCase(value: 12.4, low: 0, high: 21, x: 12.4 / 21 * 300),
        NeedleCase(value: 25, low: 20, high: 30, x: 150),
    ])
    func needleX(_ c: NeedleCase) throws {
        let x = try #require(RulerScale.needleX(value: c.value, range: c.low...c.high, width: 300))
        #expect(abs(x - c.x!) < 1e-9, "x \(x)")
    }

    @Test("Spec 7: no value, NaN, and an empty range have no needle")
    func noNeedle() {
        #expect(RulerScale.needleX(value: nil, range: 0...100, width: 300) == nil)
        #expect(RulerScale.needleX(value: .nan, range: 0...100, width: 300) == nil)
        #expect(RulerScale.needleX(value: 5, range: 5...5, width: 300) == nil)
        #expect(RulerScale.needleFraction(value: nil, range: 0...100) == nil)
        #expect(RulerScale.needleFraction(value: .nan, range: 0...1) == nil)
        #expect(RulerScale.needleFraction(value: 3, range: 3...3) == nil)
    }

    @Test("The needle's fraction is clamped to 0…1 and scales with the width")
    func needleFraction() {
        #expect(RulerScale.needleFraction(value: 84, range: 0...100) == 0.84)
        #expect(RulerScale.needleFraction(value: 105, range: 0...100) == 1)
        #expect(RulerScale.needleFraction(value: -1, range: 0...100) == 0)
        let wide = RulerScale.needleX(value: 84, range: 0...100, width: 630) ?? -1
        #expect(abs(wide - 529.2) < 1e-9)
    }

    // MARK: 8. Zone ticks

    @Test("Spec 8: Today, 61 ticks, 'high' from 67: ticks 41…60 (20), and 40 is out")
    func todayZone() {
        let zone = RulerScale.zoneTickIndices(count: RulerScale.Ticks.today, range: 0...100, zone: 67...100)
        #expect(zone == Array(41...60) && zone.count == 20)
        #expect(!zone.contains(40))
    }

    @Test("Spec 8: Sleep, 61 ticks over 0…10 h, need 7.5…8.3: ticks 45…49 (5)")
    func sleepZone() {
        let zone = RulerScale.zoneTickIndices(count: RulerScale.Ticks.sleep, range: 0...10, zone: 7.5...8.3)
        #expect(zone == Array(45...49) && zone.count == 5)
    }

    @Test("Spec 8: Strain, 64 ticks over 0…21, target 10…14: ticks 30…42 (13)")
    func strainZone() {
        let zone = RulerScale.zoneTickIndices(count: RulerScale.Ticks.strain, range: 0...21, zone: 10...14)
        #expect(zone == Array(30...42) && zone.count == 13)
    }

    @Test("Spec 8: compact strain, 43 ticks: ticks 20…28 (9)")
    func compactStrainZone() {
        let zone = RulerScale.zoneTickIndices(count: RulerScale.Ticks.strainCompact, range: 0...21, zone: 10...14)
        #expect(zone == Array(20...28) && zone.count == 9)
    }

    @Test("The tick counts are the boards'")
    func tickCountConstants() {
        #expect(RulerScale.Ticks.today == 61 && RulerScale.Ticks.sleep == 61)
        #expect(RulerScale.Ticks.strain == 64 && RulerScale.Ticks.strainCompact == 43)
    }

    @Test("Spec 8: no zone, no zone ticks")
    func noZone() {
        #expect(RulerScale.zoneTickIndices(count: 61, range: 0...100, zone: nil).isEmpty)
    }

    /// Decided by the implementation: there are no values to place, so there is no zone.
    @Test("An empty range has no zone ticks", arguments: [0.0, 5.0])
    func emptyRangeHasNoZone(_ at: Double) {
        #expect(RulerScale.zoneTickIndices(count: 61, range: at...at, zone: 0...10) == [])
    }

    @Test("A zone that does not touch the range lights nothing; one that overhangs lights up to the end")
    func zoneOutsideAndOverhanging() {
        #expect(RulerScale.zoneTickIndices(count: 61, range: 0...100, zone: 120...130).isEmpty)
        #expect(RulerScale.zoneTickIndices(count: 61, range: 0...100, zone: 90...150) == Array(54...60))
        #expect(RulerScale.zoneTickIndices(count: 61, range: 0...100, zone: -20...0) == [0])
    }

    @Test("A tick count under 2 is 2: the zone is judged on the two ends")
    func zoneWithTooFewTicks() {
        #expect(RulerScale.zoneTickIndices(count: 0, range: 0...100, zone: 50...100) == [1])
        #expect(RulerScale.zoneTickIndices(count: 1, range: 0...100, zone: 0...100) == [0, 1])
    }

    // MARK: 9. Ruler sizes

    @Test("Spec 9: regular is 36 high (8 + 22 + 6), compact 32 (8 + 18 + 6)")
    func rulerHeights() {
        #expect(RulerScale.Size.regular.height == 36 && RulerScale.Size.compact.height == 32)
        #expect(RulerScale.Size.regular.tickRowTop == 8 && RulerScale.Size.compact.tickRowTop == 8)
        #expect(RulerScale.Size.regular.tickRowHeight == 22 && RulerScale.Size.compact.tickRowHeight == 18)
        // The tick row is y 8…30 (regular) and 8…26 (compact); ticks are centred in it.
        #expect(RulerScale.Size.regular.tickRowMidY == 19 && RulerScale.Size.compact.tickRowMidY == 17)
    }

    @Test("Spec 9: tick and needle lengths by size")
    func rulerGeometry() {
        let (r, c) = (RulerScale.Size.regular, RulerScale.Size.compact)
        #expect(r.outsideTick == CGSize(width: 1, height: 8) && c.outsideTick == CGSize(width: 1, height: 7))
        #expect(r.outsideOpacity == 0.22 && c.outsideOpacity == 0.26)
        #expect(r.zoneTick == CGSize(width: 1.5, height: 14) && c.zoneTick == CGSize(width: 1.5, height: 12))
        #expect(r.needleHead == CGSize(width: 12, height: 8) && c.needleHead == CGSize(width: 12, height: 8))
        #expect(r.needleLine == CGSize(width: 1.5, height: 20) && c.needleLine == CGSize(width: 1.5, height: 16))
        // The needle line ends at y 28 (regular) and 24 (compact): inside the ruler.
        #expect(r.tickRowTop + r.needleLine.height == 28 && c.tickRowTop + c.needleLine.height == 24)
    }

    @Test("Spec 9: the default zone opacity is 0.55 regular and 0.60 compact")
    func defaultZoneOpacity() {
        #expect(RulerScale.Size.regular.defaultZoneOpacity == 0.55)
        #expect(RulerScale.Size.compact.defaultZoneOpacity == 0.60)
    }

    @Test("Spec 9: the needle is Volt (Theme.signal)")
    func needleIsSignal() {
        #expect(Tokens.matches(Tokens.resolve(RulerScale.needleColor), Tokens.resolve(Theme.signal)))
        #expect(Tokens.matches(Tokens.resolve(RulerScale.needleColor), Tokens.rgba(0xD8FF4F)))
    }

    // MARK: 10. TickRow lit count

    struct LitCase: Sendable, CustomTestStringConvertible {
        let minutes: Double?
        let scaleMax: Double
        let lit: Int
        var testDescription: String { "\(minutes.map { "\($0)" } ?? "nil") of \(scaleMax)" }
    }

    @Test("Spec 10: lit ticks = clamp(round(minutes·30 / scaleMax), 0…30)", arguments: [
        LitCase(minutes: 0, scaleMax: 60, lit: 0), LitCase(minutes: 1, scaleMax: 60, lit: 1),   // 0.5 rounds up
        LitCase(minutes: 7, scaleMax: 60, lit: 4),                                                // 3.5 rounds up
        LitCase(minutes: 24, scaleMax: 60, lit: 12), LitCase(minutes: 60, scaleMax: 60, lit: 30),
        LitCase(minutes: 90, scaleMax: 60, lit: 30), LitCase(minutes: -5, scaleMax: 60, lit: 0),
        LitCase(minutes: 10, scaleMax: 0, lit: 0), LitCase(minutes: nil, scaleMax: 60, lit: 0),
        LitCase(minutes: 0.9, scaleMax: 60, lit: 0), LitCase(minutes: 29, scaleMax: 58, lit: 15),
        LitCase(minutes: 10, scaleMax: -60, lit: 0),
    ])
    func litCount(_ c: LitCase) {
        #expect(TickRow.litCount(minutes: c.minutes, scaleMax: c.scaleMax) == c.lit)
    }

    /// Decided by the implementation: the value is clamped as a Double before it becomes an Int, so nothing traps, and
    /// anything that is not a number lights nothing. An infinite amount of time is "more than the scale": all 30.
    @Test("Huge, infinite and NaN inputs never trap and clamp before the Int conversion")
    func litCountIsTotal() {
        #expect(TickRow.litCount(minutes: .nan, scaleMax: 60) == 0)
        #expect(TickRow.litCount(minutes: 10, scaleMax: .nan) == 0)
        #expect(TickRow.litCount(minutes: .nan, scaleMax: .nan) == 0)
        #expect(TickRow.litCount(minutes: -.infinity, scaleMax: 60) == 0)
        #expect(TickRow.litCount(minutes: .infinity, scaleMax: .infinity) == 0)   // ∞/∞ is NaN
        #expect(TickRow.litCount(minutes: 10, scaleMax: .infinity) == 0)          // nothing is lit on an endless scale
        #expect(TickRow.litCount(minutes: .infinity, scaleMax: 60) == 30)
        #expect(TickRow.litCount(minutes: 1e300, scaleMax: 1e-300) == 30)         // overflows to ∞ in the product
        #expect(TickRow.litCount(minutes: Double.greatestFiniteMagnitude, scaleMax: 1) == 30)
        #expect(TickRow.litCount(minutes: -Double.greatestFiniteMagnitude, scaleMax: 1) == 0)
        #expect(TickRow.litCount(minutes: 5, scaleMax: .leastNonzeroMagnitude) == 30)
    }

    @Test("The first N ticks light: the count never exceeds the 30 ticks")
    func litCountStaysInRange() {
        for minutes in stride(from: -10.0, through: 200.0, by: 2.5) {
            let n = TickRow.litCount(minutes: minutes, scaleMax: 60)
            #expect((0...TickRow.tickCount).contains(n), "\(minutes) -> \(n)")
        }
    }

    // MARK: 11. DotRow

    @Test("Spec 11: 7 dots are 66×6, one is 6×6, none is .zero")
    func dotRowSizes() {
        #expect(DotRow.size(count: 7) == CGSize(width: 66, height: 6))
        #expect(DotRow.size(count: 1) == CGSize(width: 6, height: 6))
        #expect(DotRow.size(count: 0) == .zero)
        #expect(DotRow.size(count: 30) == CGSize(width: 30 * 6 + 29 * 4, height: 6))
    }

    @Test("A negative count draws nothing either")
    func dotRowNegativeCount() {
        #expect(DotRow.size(count: -3) == .zero)
    }

    // MARK: 12. Form tokens

    @Test("Spec 12: the new Theme.Metrics constants")
    func newMetrics() {
        typealias M = Theme.Metrics
        #expect(M.neutralTileRadius == 22 && M.glowTileRadius == 24 && M.heroTileRadius == 28)
        #expect(M.circleButton == 40 && M.minHitTarget == 44 && M.pillHeight == 52 && M.itemSpacing == 12)
    }

    @Test("Spec 12: the old metrics keep their values until PRs 4–5 move their callers")
    func oldMetricsAreUntouched() {
        typealias M = Theme.Metrics
        #expect(M.cardRadius == 18 && M.tileRadius == 16 && M.screenPadding == 20)
        #expect(M.cardPadding == 18 && M.sectionSpacing == 24 && M.hairline == 1)
    }

    @Test("Spec 12: the glow radii are the tokens")
    func glowRadii() {
        #expect(GlowTileSpec.Radius.tile.points == 24 && GlowTileSpec.Radius.hero.points == 28)
        #expect(GlowTileSpec.Radius.tile.points == Theme.Metrics.glowTileRadius)
        #expect(GlowTileSpec.Radius.hero.points == Theme.Metrics.heroTileRadius)
    }

    // MARK: 13. The gradient

    @Test("Spec 13: the stops are `background` at 0.97 / 0.92 / 0.55 / 0.10, at 0 / 0.34 / 0.68 / 1")
    func gradientStops() throws {
        let stops = GlowTileSpec.stops
        #expect(stops.count == 4)
        let expected: [(location: CGFloat, alpha: Double)] = [(0, 0.97), (0.34, 0.92), (0.68, 0.55), (1, 0.10)]
        for (stop, want) in zip(stops, expected) {
            #expect(abs(stop.location - want.location) < 1e-9, "location \(want.location)")
            let colour = Tokens.resolve(stop.color)
            let bg = Tokens.resolve(Theme.background)
            // Alpha to within the catalog's 0.005; the colour channels are `background`'s.
            #expect(abs(colour.a - want.alpha) <= 0.005, "alpha at \(want.location): \(colour.a)")
            #expect(abs(colour.r - bg.r) <= 1.0 / 255 && abs(colour.g - bg.g) <= 1.0 / 255 && abs(colour.b - bg.b) <= 1.0 / 255)
        }
        #expect(GlowTileSpec.stopOpacities.map(\.location) == [0, 0.34, 0.68, 1])
        #expect(GlowTileSpec.stopOpacities.map(\.opacity) == [0.97, 0.92, 0.55, 0.10])
    }

    struct OverlayCase: Sendable, CustomTestStringConvertible {
        let t: Double
        let opacity: Double
        var testDescription: String { "t \(t)" }
    }

    @Test("Spec 13: the overlay opacity at a radius fraction", arguments: [
        OverlayCase(t: 0, opacity: 0.97), OverlayCase(t: 0.34, opacity: 0.92), OverlayCase(t: 0.5, opacity: 0.7459),
        OverlayCase(t: 0.68, opacity: 0.55), OverlayCase(t: 1, opacity: 0.10), OverlayCase(t: 2, opacity: 0.10),
        OverlayCase(t: -0.5, opacity: 0.97), OverlayCase(t: 0.17, opacity: 0.945), OverlayCase(t: 0.84, opacity: 0.325),
    ])
    func overlayOpacity(_ c: OverlayCase) {
        // ±0.001: the spec rounds 0.745882… to 0.7459; the other points are exact on the stops or on a straight segment.
        #expect(abs(GlowTileSpec.overlayOpacity(atRadiusFraction: c.t) - c.opacity) <= 0.001)
    }

    @Test("The overlay only gets lighter from the core to the edge")
    func overlayIsMonotonic() {
        var last = 1.0
        for t in stride(from: 0.0, through: 1.2, by: 0.01) {
            let o = GlowTileSpec.overlayOpacity(atRadiusFraction: t)
            #expect(o <= last + 1e-12, "t \(t)")
            last = o
        }
    }

    @Test("Spec 13: the ellipse is 90 % × 110 % at 55 % and the padding 14 / 16 / 14 / 16")
    func ellipseAndPadding() {
        #expect(GlowTileSpec.ellipse.rx == 0.90 && GlowTileSpec.ellipse.ry == 1.10 && GlowTileSpec.ellipse.cy == 0.55)
        #expect(GlowTileSpec.padding == EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        #expect(GlowTileSpec.twoUpMinHeight == 124 && GlowTileSpec.heroMinHeight == 172)
        #expect(GlowTileSpec.flatBorder == 2)
    }

    // MARK: 14. Constants

    @Test("Spec 14: circle button and pill constants")
    func buttonConstants() {
        #expect(CircleButton.diameter == 40 && CircleButton.hitSize == 44 && CircleButton.borderOpacity == 0.16)
        #expect(CircleButton.iconSize == 14 && CircleButton.disabledIconOpacity == 0.35)
        #expect(PillButton.minHeight == 52 && PillButton.iconCircle == 40)
        #expect(PillButton.outlineOpacity == 0.20 && PillButton.disabledOpacity == 0.35)
    }

    @Test("Spec 14: the tick row's measurements; the ticks are 177 wide, the row 315")
    func tickRowConstants() {
        #expect(TickRow.tickCount == 30 && TickRow.tick == CGSize(width: 3, height: 12) && TickRow.tickGap == 3)
        #expect(TickRow.rowSpacing == 9 && TickRow.labelWidth == 74 && TickRow.valueWidth == 40)
        #expect(TickRow.unlitOpacity == 0.12)
        #expect(TickRow.ticksWidth == 177)
        #expect(TickRow.labelWidth + TickRow.ticksWidth + TickRow.valueWidth + 2 * Theme.Metrics.itemSpacing == 315)
    }

    @Test("Spec 14: the dot row's dot 6, gap 4, outline 50 %")
    func dotRowConstants() {
        #expect(DotRow.dot == 6 && DotRow.gap == 4 && DotRow.outlineOpacity == 0.5)
    }

    // MARK: 15. Glow label

    @Test("Spec 15: the label constant is 78 %")
    func labelOpacityConstant() {
        #expect(GlowTileSpec.labelOpacity == 0.78)
    }

    @Test("Spec 15: a glow label is 78 % up to xxxLarge and full textPrimary from AX1", arguments: DynamicTypeSize.allCases)
    func labelOpacityBySize(_ size: DynamicTypeSize) {
        let want = size >= .accessibility1 ? 1.0 : 0.78
        #expect(GlowTileSpec.labelOpacity(for: size) == want, "\(size)")
    }
}
