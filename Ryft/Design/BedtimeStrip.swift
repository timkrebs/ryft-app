import Charts
import SwiftUI

/// Bed and wake times per night on a shared clock axis (20:00 → 10:00, widened
/// when a night falls outside), with the mean bedtime and wake time as thin
/// markers. The consistency visual of Sleep → Week / Month.
struct BedtimeStrip: View {
    let bedtimes: [SleepBedtime]
    var rowHeight: CGFloat = 10

    private var layout: BedtimeLayout { BedtimeLayout(bedtimes) }

    var body: some View {
        let l = layout
        Chart {
            ForEach(l.nights) { n in
                BarMark(xStart: .value("Bedtime", n.bed), xEnd: .value("Wake", n.wake),
                        y: .value("Night", n.label), height: .fixed(rowHeight * 0.7))
                    .foregroundStyle(Theme.metricSleep)
                    .cornerRadius(2)
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
        .chartXAxis {
            AxisMarks(values: l.ticks) { v in
                AxisGridLine(stroke: ChartStyle.grid).foregroundStyle(Theme.separator)
                AxisValueLabel {
                    if let m = v.as(Double.self) { Text(BedtimeLayout.clock(m)).font(ChartStyle.axisFont) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel().font(ChartStyle.axisFont)
            }
        }
        .frame(height: max(80, CGFloat(l.nights.count) * rowHeight + 28))
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

    /// Minutes from 20:00 → "22", "00", "06" (24-hour clock in every locale).
    static func clock(_ minutes: Double) -> String {
        let hour = (20 + Int((minutes / 60).rounded(.down))) % 24
        return String(format: "%02d", (hour + 24) % 24)
    }

    /// "Mean bedtime 22:48, mean wake time 06:41".
    var spoken: String {
        func hhmm(_ m: Double?) -> String {
            guard let m else { return Fmt.placeholder }
            let total = (20 * 60 + Int(m.rounded())) % (24 * 60)
            return String(format: "%02d:%02d", total / 60, total % 60)
        }
        return String(localized: "Mean bedtime \(hhmm(meanBed)), mean wake time \(hhmm(meanWake))")
    }
}

#Preview("Bedtime strip", traits: .sizeThatFitsLayout) {
    SchemePair {
        BedtimeStrip(bedtimes: MockData.sleepRange(.week).bedtimes)
    }
}
