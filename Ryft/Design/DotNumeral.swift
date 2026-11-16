// The hero numeral as a 5×7 dot grid (Nocturne, docs/work/2026-11-16-nocturne/design.md §P2-1, §P2-5): one per screen,
// Today's readiness, Sleep's time asleep, Strain's value. Drawn as shapes from a pinned glyph table, not a font. From
// AX1 up, with `style: .light`, or for a character outside the table it falls back to Light digits.
import SwiftUI

/// One glyph of the dot numeral: `rows` holds 7 rows from the top; in each, bit `width - 1 - c` is column `c` (the
/// most significant used bit is the left column).
struct DotGlyph: Equatable {
    let width: Int
    let rows: [UInt8]

    /// Whether the dot in `row` (from the top) and `column` (from the left) is lit.
    func isLit(row: Int, column: Int) -> Bool {
        (rows[row] >> UInt8(width - 1 - column)) & 1 == 1
    }
}

enum DotGlyphs {
    static let rowCount = 7

    /// Digits, the time separator and both decimal separators (design.md §P2-5). `1 2 4 7 8` are the boards' matrices;
    /// `0 3 5 6 9` follow their style; `,` is the full stop with a tail.
    static let table: [Character: DotGlyph] = [
        "0": DotGlyph(width: 5, rows: [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]),
        "1": DotGlyph(width: 5, rows: [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]),
        "2": DotGlyph(width: 5, rows: [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111]),
        "3": DotGlyph(width: 5, rows: [0b01110, 0b10001, 0b00001, 0b00110, 0b00001, 0b10001, 0b01110]),
        "4": DotGlyph(width: 5, rows: [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010]),
        "5": DotGlyph(width: 5, rows: [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110]),
        "6": DotGlyph(width: 5, rows: [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110]),
        "7": DotGlyph(width: 5, rows: [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000]),
        "8": DotGlyph(width: 5, rows: [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110]),
        "9": DotGlyph(width: 5, rows: [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100]),
        ":": DotGlyph(width: 1, rows: [0b0, 0b0, 0b1, 0b0, 0b1, 0b0, 0b0]),     // rows 3 and 5
        ".": DotGlyph(width: 1, rows: [0b0, 0b0, 0b0, 0b0, 0b0, 0b0, 0b1]),     // row 7
        ",": DotGlyph(width: 1, rows: [0b0, 0b0, 0b0, 0b0, 0b0, 0b1, 0b1]),     // rows 6 and 7: the full stop with a tail
    ]

    /// A pending cell: a digit's width, no dot lit.
    static let placeholder = DotGlyph(width: 5, rows: Array(repeating: 0, count: rowCount))

    /// The glyphs of `text`, left to right; `nil` if any character is outside the table. An empty string has nothing to
    /// draw and is `nil` too, so it takes the Light fallback like any other text the grid cannot show.
    static func glyphs(for text: String) -> [DotGlyph]? {
        guard !text.isEmpty else { return nil }
        var glyphs: [DotGlyph] = []
        for character in text {
            guard let glyph = table[character] else { return nil }
            glyphs.append(glyph)
        }
        return glyphs
    }
}

/// A formatted numeral ("84", "7:48", "12.4", "12,4": the caller formats, with the region's separator) as a dot grid,
/// or as Light digits where the grid does not apply. `nil` is pending: blank cells, and the caller's label says "no
/// value yet". One accessibility element with the caller's label in every state.
struct DotNumeral: View {
    enum Style { case dots, light }

    /// Dot diameter and the gap between dots: a 5-column glyph is 33 pt wide, every glyph 47 pt high (7·5 + 6·2).
    nonisolated static let dot: CGFloat = 5, dotGap: CGFloat = 2, height: CGFloat = 47
    /// Gap between glyphs: Today, and the Sleep and Strain detail screens.
    static let glyphGapToday: CGFloat = 8, glyphGapDetail: CGFloat = 7
    /// Unlit dots: `textPrimary` at 10 %, decoration (1.24:1). The Light fallback's size at the default text size.
    static let offOpacity = 0.10, lightSize: CGFloat = 52

    /// Where every dot of a numeral sits, and the grid's size.
    struct Cells: Equatable {
        var size: CGSize
        var lit: [CGPoint]
        var unlit: [CGPoint]
    }

    private let text: String?
    private let style: Style
    private let glyphGap: CGFloat
    private let placeholderGlyphs: Int
    private let accessibilityLabel: Text

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The Light fallback: exactly 52 at the default size, larger from AX1 (about 1.5× at AX3).
    @ScaledMetric(relativeTo: .largeTitle) private var scaledLightSize: CGFloat = DotNumeral.lightSize

    init(_ text: String?, style: Style = .dots, glyphGap: CGFloat = DotNumeral.glyphGapToday,
         placeholderGlyphs: Int = 2, accessibilityLabel: Text) {
        self.text = text
        self.style = style
        self.glyphGap = glyphGap
        self.placeholderGlyphs = placeholderGlyphs
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var content: some View {
        if Self.rendersDots(text, style: style, typeSize: typeSize),
           let cells = Self.cells(text, placeholderGlyphs: placeholderGlyphs, glyphGap: glyphGap) {
            ZStack {
                DotCells(centres: cells.unlit, diameter: Self.dot).fill(Theme.textPrimary.opacity(Self.offOpacity))
                DotCells(centres: cells.lit, diameter: Self.dot).fill(Theme.textPrimary)
            }
            .frame(width: cells.size.width, height: cells.size.height)
        } else {
            lightText
                .font(.ryftNumber(size: scaledLightSize, weight: .light))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    @ViewBuilder private var lightText: some View {
        if let text {
            Text(verbatim: text).foregroundStyle(Theme.textPrimary)
        } else {
            Text(verbatim: String(repeating: "–", count: Self.cellCount(placeholderGlyphs)))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: layout (pure)

    /// The width of one glyph: `w·5 + (w−1)·2`.
    nonisolated static func width(of glyph: DotGlyph) -> CGFloat {
        CGFloat(glyph.width) * dot + CGFloat(max(glyph.width - 1, 0)) * dotGap
    }

    /// The grid's size: glyph widths plus `glyphGap` between glyphs, × 47. `nil` when `text` is outside the table.
    /// A pending numeral (`nil`) has `placeholderGlyphs` blank digit cells (at least one).
    nonisolated static func size(of text: String?, placeholderGlyphs: Int = 2, glyphGap: CGFloat) -> CGSize? {
        cells(text, placeholderGlyphs: placeholderGlyphs, glyphGap: glyphGap)?.size
    }

    /// Dots below AX1 for `style: .dots` and text in the table (or pending); Light digits otherwise.
    nonisolated static func rendersDots(_ text: String?, style: Style, typeSize: DynamicTypeSize) -> Bool {
        guard style == .dots, !typeSize.isAccessibilitySize else { return false }
        guard let text else { return true }
        return DotGlyphs.glyphs(for: text) != nil
    }

    /// Every dot centre: glyph `k` starts at the previous glyph's right edge + `glyphGap`; the dot in column `c`, row
    /// `r` is centred at `(x₀ + c·7 + 2.5, r·7 + 2.5)`.
    nonisolated static func cells(_ text: String?, placeholderGlyphs: Int = 2, glyphGap: CGFloat) -> Cells? {
        let glyphs: [DotGlyph]
        if let text {
            guard let found = DotGlyphs.glyphs(for: text) else { return nil }
            glyphs = found
        } else {
            glyphs = Array(repeating: DotGlyphs.placeholder, count: cellCount(placeholderGlyphs))
        }
        let pitch = dot + dotGap
        var lit: [CGPoint] = [], unlit: [CGPoint] = []
        var x0: CGFloat = 0
        for (index, glyph) in glyphs.enumerated() {
            if index > 0 { x0 += glyphGap }
            for row in 0..<DotGlyphs.rowCount {
                for column in 0..<glyph.width {
                    let centre = CGPoint(x: x0 + CGFloat(column) * pitch + dot / 2, y: CGFloat(row) * pitch + dot / 2)
                    if glyph.isLit(row: row, column: column) { lit.append(centre) } else { unlit.append(centre) }
                }
            }
            x0 += width(of: glyph)
        }
        return Cells(size: CGSize(width: x0, height: height), lit: lit, unlit: unlit)
    }

    /// A pending numeral never draws nothing: at least one cell.
    private nonisolated static func cellCount(_ placeholderGlyphs: Int) -> Int { max(placeholderGlyphs, 1) }
}

/// Circles of the dot diameter at the given centres.
private struct DotCells: Shape {
    let centres: [CGPoint]
    let diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = diameter / 2
        for c in centres {
            path.addEllipse(in: CGRect(x: rect.minX + c.x - r, y: rect.minY + c.y - r, width: 2 * r, height: 2 * r))
        }
        return path
    }
}

#Preview("DotNumeral", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 20) {
            DotNumeral("84", accessibilityLabel: Text("Readiness 84 of 100"))
            DotNumeral("7:48", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("7 hours 48 minutes asleep"))
            DotNumeral("12.4", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("Strain 12.4 of 21"))
            DotNumeral("12,4", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("Strain 12.4 of 21"))
            DotNumeral(nil, accessibilityLabel: Text("Readiness, no value yet"))
            DotNumeral("84", style: .light, accessibilityLabel: Text("Readiness 84 of 100"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("DotNumeral · glyphs", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 20) {
            DotNumeral("01234", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("0 1 2 3 4"))
            DotNumeral("56789", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("5 6 7 8 9"))
            DotNumeral(":.,", accessibilityLabel: Text("Separators"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("DotNumeral · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 20) {
            DotNumeral("84", accessibilityLabel: Text("Readiness 84 of 100"))
            DotNumeral("7:48", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("7 hours 48 minutes asleep"))
            DotNumeral(nil, accessibilityLabel: Text("Readiness, no value yet"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
