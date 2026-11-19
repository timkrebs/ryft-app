// Sleep → Week, Month and Bedtime's measurements (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-7, §P5-12 test 4): the
// draft renders' gaps and sizes, bottom of one element to the top of the next. The mode picker is `SegmentedPicker`'s ink fill
// (`SegmentedPickerSpec`); Day keeps `SleepLayout`.
import Foundation

enum SleepModesLayout {
    // MARK: the picker (§P5-7.1, `SegmentedPickerSpec.inkFill`)

    /// 40 high: 3 of padding around 34 pt segments, 4 between them; the control's radius 20, a segment's 17.
    nonisolated static let pickerHeight: CGFloat = 40, pickerPadding: CGFloat = 3, pickerGap: CGFloat = 4
    nonisolated static let segmentHeight: CGFloat = 34, segmentRadius: CGFloat = 17, controlRadius: CGFloat = 20
    /// The refresh issue's card, when there is one, under the picker.
    nonisolated static let noticeGap: CGFloat = 12

    // MARK: the head (numeral, caption, delta)

    /// The numeral under the picker (Day's `SleepLayout.numeralGap`), the caption under the numeral, the "vs 7 d" line under
    /// the caption.
    nonisolated static let numeralGap: CGFloat = 22, captionGap: CGFloat = 12, deltaGap: CGFloat = 4
    /// The first glow tile under the caption (Week, Month: no ruler).
    nonisolated static let tileGap: CGFloat = 20
    /// The two neutral tiles under a glow tile, and the cards under them.
    nonisolated static let tilesGap: CGFloat = 12, cardGap: CGFloat = 12

    // MARK: Week and Month (§P5-7.2)

    /// The bed-and-wake glow tile: at least Day's hypnogram height; the strip 8 under its head, the hint 8 under the strip.
    nonisolated static let bedWakeMinHeight: CGFloat = 168, stripGap: CGFloat = 8, hintGap: CGFloat = 8
    /// A night's row in the strip: 14 with its date (Week), 7 without (Month: 30 labels collide).
    nonisolated static let weekRowHeight: CGFloat = 14, monthRowHeight: CGFloat = 7
    /// The stage card: `surface`, radius 22, padding 14 / 16 / 14; the chart 10 under its head, 150 high (its plot 128 and
    /// the date row), the legend 10 under it with 10 pt squares.
    nonisolated static let stageCardRadius: CGFloat = 22
    nonisolated static let stageCardPadding = (top: CGFloat(14), sides: CGFloat(16), bottom: CGFloat(14))
    nonisolated static let stageChartGap: CGFloat = 10, stageChartHeight: CGFloat = 150, stagePlotHeight: CGFloat = 128
    nonisolated static let legendGap: CGFloat = 10, legendSwatch: CGFloat = 10, legendSwatchRadius: CGFloat = 2
    /// 1.5 pt of `surface` between a night's stages, the segments' corners 1.5.
    nonisolated static let stageSegmentGap: CGFloat = 1.5, stageCornerRadius: CGFloat = 1.5
    /// A bar's share of its day: Week 0.55, Month 0.7.
    nonisolated static let weekBarRatio = 0.55, monthBarRatio = 0.7
    /// The hours axis: 0 / 3 / 6 / 9 / 12 h (taller when a night is longer), gridlines ink at 8 %.
    nonisolated static let hourStep = 3.0, minimumHours = 12.0, gridOpacity = 0.08
    /// The nights list: rows 46 high, the consistency 44 wide at the end.
    nonisolated static let nightRowHeight: CGFloat = 46, nightConsistencyWidth: CGFloat = 44

    // MARK: Bedtime (§P5-7.3)

    /// The meridiem 8 after the numeral; the ruler 14 under the caption; the go-to-bed tile 20 under the ruler's box.
    nonisolated static let meridiemGap: CGFloat = 8, rulerGap: CGFloat = 14, goToBedGap: CGFloat = 20
    /// The go-to-bed tile: at least 176; its rows 12 under the head and 10 apart; the marker 6 (a 1 pt ring when not the goal).
    nonisolated static let goToBedMinHeight: CGFloat = 176, optionsGap: CGFloat = 12, optionGap: CGFloat = 10
    nonisolated static let markerSize: CGFloat = 6, markerRing: CGFloat = 1, markerGap: CGFloat = 10
    /// An option's time: 24 pt Light (`ryftNumber`), growing with Dynamic Type.
    nonisolated static let optionTimeSize: CGFloat = 24
    /// The settings card 12 under the tiles; the "As of" footer 12 under it.
    nonisolated static let settingsGap: CGFloat = 12, footerGap: CGFloat = 12

    // MARK: large text

    /// The first, third, fifth … tick: the labelled ones at accessibility sizes, where every tick's label would collide
    /// (the strip's clock, the stage chart's hours; the gridlines stay).
    nonisolated static func everyOther<T>(_ ticks: [T]) -> [T] {
        ticks.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
    }
}

extension Fmt {
    /// A clock time as the Bedtime numeral draws it: the digits ("10:06") and the meridiem ("PM"), split on any whitespace,
    /// including U+202F (the narrow no-break space `Fmt.time` puts before "PM") and U+00A0. A 24-hour time has no meridiem
    /// ("22:06" → ("22:06", nil)); the part with digits is the numeral, the rest the meridiem, before or after it.
    static func clockParts(_ text: String) -> (digits: String, meridiem: String?) {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let index = parts.firstIndex(where: { $0.contains(where: \.isNumber) }) else {
            return (parts.joined(separator: " "), nil)
        }
        var rest = parts
        let digits = rest.remove(at: index)
        return (digits, rest.isEmpty ? nil : rest.joined(separator: " "))
    }

    /// `clockParts` of `Fmt.time(date)`.
    static func clockParts(_ date: Date, locale: Locale = .autoupdatingCurrent) -> (digits: String, meridiem: String?) {
        clockParts(time(date, locale: locale))
    }

    /// A wall-clock time without a day, as `time(_:locale:)` writes one ("6:30 AM", "06:30"): Bedtime & wake's times and
    /// the strip's means. On 1 January 2001, a day without a clock change.
    static func time(hour: Int, minute: Int, locale: Locale = .autoupdatingCurrent, calendar: Calendar = .current) -> String {
        let day = DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)
        return time(calendar.date(from: day), locale: locale)
    }
}
