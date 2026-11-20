import Charts
import SwiftUI

/// Bed and wake times per night on a shared clock axis (20:00 → 10:00, widened when a night falls outside), with the mean
/// bedtime and wake time as dashed rules. The consistency visual of Sleep → Week / Month (Nocturne,
/// docs/work/2026-11-16-nocturne/design.md §P5-7.2): a row per night, oldest on top, the bars `metricSleep`. Week draws 14 pt rows
/// with their dates, growing with the date text; Month 7 pt rows and no dates (30 collide), the clock axis kept. The rows are
/// numbered, so a date sits on its own bar and every bar has one. At accessibility sizes the clock labels every other tick.
/// Inside a glow tile its labels take the tile's label ink.
struct BedtimeStrip: View {
    let bedtimes: [SleepBedtime]
    var rowHeight: CGFloat = SleepModesLayout.weekRowHeight
    /// The dates beside the rows: Week only.
    var showsRowLabels = true

    /// A bar's share of its row, and its corner.
    nonisolated static let barShare: CGFloat = 0.7, barRadius: CGFloat = 2
    /// The gridlines' ink.
    nonisolated static let gridOpacity = 0.08

    @Environment(\.glowLabelOpacity) private var glowLabelOpacity
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The dates' growth: a row with a date is never lower than its text.
    @ScaledMetric(relativeTo: .caption2) private var labelScale: CGFloat = 1
    /// The clock row under the rows, growing with the axis text.
    @ScaledMetric(relativeTo: .caption2) private var axisRowHeight: CGFloat = 18

    private var labelInk: Color { glowLabelOpacity.map { Theme.textPrimary.opacity($0) } ?? Theme.textTertiary }

    var body: some View {
        let l = BedtimeLayout(bedtimes)
        let count = l.nights.count
        let rowHeight = showsRowLabels ? self.rowHeight * max(labelScale, 1) : self.rowHeight
        let barHeight = rowHeight * Self.barShare
        let ticks = typeSize.isAccessibilitySize ? SleepModesLayout.everyOther(l.ticks) : l.ticks
        Chart {
            ForEach(Array(l.nights.enumerated()), id: \.element.id) { index, n in
                BarMark(xStart: .value("Bedtime", n.bed), xEnd: .value("Wake", n.wake),
                        y: .value("Night", BedtimeLayout.rowCentre(index, count: count)), height: .fixed(barHeight))
                    .foregroundStyle(Theme.metricSleep)
                    .cornerRadius(min(Self.barRadius, barHeight / 2))
            }
            if let bed = l.meanBed {
                RuleMark(x: .value("Mean bedtime", bed))
                    .lineStyle(ChartStyle.baseline)
                    .foregroundStyle(ChartStyle.reference)
            }
            if let wake = l.meanWake {
                RuleMark(x: .value("Mean wake time", wake))
                    .lineStyle(ChartStyle.baseline)
                    .foregroundStyle(ChartStyle.reference)
            }
        }
        .chartXScale(domain: l.domain)
        .chartYScale(domain: 0...Double(max(count, 1)))
        .chartXAxis {
            AxisMarks(values: ticks) { v in
                AxisGridLine(stroke: ChartStyle.grid).foregroundStyle(Theme.textPrimary.opacity(Self.gridOpacity))
                AxisValueLabel {
                    if let m = v.as(Double.self) {
                        Text(BedtimeLayout.clock(m)).font(ChartStyle.axisFont).foregroundStyle(labelInk)
                    }
                }
            }
        }
        .chartYAxis {
            // Month: no marks at all, so the plot takes the whole width.
            AxisMarks(position: .leading,
                      values: showsRowLabels ? (0..<count).map { BedtimeLayout.rowCentre($0, count: count) } : []) { v in
                AxisValueLabel {
                    if let y = v.as(Double.self), let index = BedtimeLayout.row(at: y, count: count) {
                        Text(l.nights[index].label).font(ChartStyle.axisFont).foregroundStyle(labelInk)
                    }
                }
            }
        }
        // The rows are exactly `rowHeight`: the plot is as high as the nights, the clock row under it.
        .chartPlotStyle { plot in plot.frame(height: CGFloat(max(count, 1)) * rowHeight) }
        .frame(height: CGFloat(max(count, 1)) * rowHeight + axisRowHeight)
        .chartAppear()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bedtimes and wake times"))
        .accessibilityValue(Text(l.spoken))
    }
}

/// The strip's numbers: each night in minutes from 20:00 the evening before its
/// wake day, so nights across midnight line up.
struct BedtimeLayout: Equatable {
    struct Night: Identifiable, Equatable {
        let day: String
        let label: String
        let bed: Double
        let wake: Double
        var id: String { day }
    }

    let nights: [Night]
    let meanBed: Double?
    let meanWake: Double?
    let domain: ClosedRange<Double>
    let ticks: [Double]

    /// 20:00 → 10:00.
    static let defaultDomain: ClosedRange<Double> = 0...840

    init(_ bedtimes: [SleepBedtime], calendar: Calendar = .current) {
        nights = bedtimes.map { b in
            let wakeDay = calendar.startOfDay(for: b.wake)
            let origin = wakeDay.addingTimeInterval(-4 * 3600)   // 20:00 the evening before
            let label = (DayFormat.date(from: b.day) ?? b.wake).formatted(.dateTime.weekday(.abbreviated).day())
            return Night(day: b.day, label: label, bed: b.bed.timeIntervalSince(origin) / 60,
                         wake: b.wake.timeIntervalSince(origin) / 60)
        }
        func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
        meanBed = mean(nights.map(\.bed))
        meanWake = mean(nights.map(\.wake))
        // Whole hours, never narrower than 20:00 → 10:00.
        let lo = min(Self.defaultDomain.lowerBound, ((nights.map(\.bed).min() ?? 0) / 60).rounded(.down) * 60)
        let hi = max(Self.defaultDomain.upperBound, ((nights.map(\.wake).max() ?? 0) / 60).rounded(.up) * 60)
        domain = lo...hi
        ticks = stride(from: lo, through: hi, by: (hi - lo) > 900 ? 240 : 120).map { $0 }
    }

    /// The y value of row `index` (0 the oldest, at the top) of `count`: rows are 1 apart, the first at the top.
    nonisolated static func rowCentre(_ index: Int, count: Int) -> Double {
        Double(count - index) - 0.5
    }

    /// The row whose centre is `y`, the inverse of `rowCentre`; `nil` off the rows.
    nonisolated static func row(at y: Double, count: Int) -> Int? {
        let index = Int((Double(count) - 0.5 - y).rounded())
        return (0..<count).contains(index) ? index : nil
    }

    /// Minutes from 20:00 → "22", "00", "06" (24-hour clock in every locale).
    static func clock(_ minutes: Double) -> String {
        let hour = (20 + Int((minutes / 60).rounded(.down))) % 24
        return String(format: "%02d", (hour + 24) % 24)
    }

    /// "Mean bedtime 10:48 PM, mean wake time 6:41 AM" ("22:48", "06:41" on a 24-hour clock).
    var spoken: String { spoken(locale: .autoupdatingCurrent) }

    func spoken(locale: Locale, calendar: Calendar = .current) -> String {
        func time(_ m: Double?) -> String {
            guard let m else { return Fmt.placeholder }
            let total = ((20 * 60 + Int(m.rounded())) % (24 * 60) + 24 * 60) % (24 * 60)
            return Fmt.time(hour: total / 60, minute: total % 60, locale: locale, calendar: calendar)
        }
        return String(localized: "Mean bedtime \(time(meanBed)), mean wake time \(time(meanWake))")
    }
}

#Preview("Bedtime strip", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 24) {
            BedtimeStrip(bedtimes: MockData.sleepRange(.week).bedtimes)
            BedtimeStrip(bedtimes: MockData.sleepRange(.month).bedtimes, rowHeight: SleepModesLayout.monthRowHeight,
                         showsRowLabels: false)
        }
    }
}

#Preview("Bedtime strip · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        BedtimeStrip(bedtimes: MockData.sleepRange(.week).bedtimes)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
