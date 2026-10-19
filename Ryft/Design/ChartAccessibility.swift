import Accessibility
import SwiftUI

/// Audio Graphs for a date/value series (VoiceOver → rotor → Audio Graph), so
/// charts are explorable without sight, not just summarised.
struct SeriesChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    /// Unit or series name for the y axis, e.g. "bpm".
    let valueName: String
    let points: [(date: Date, value: Double)]
    var valueText: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = points.map(\.date)
        let values = points.map(\.value)
        let start = dates.min() ?? .now, end = max(dates.max() ?? .now, start.addingTimeInterval(1))
        let lo = values.min() ?? 0, hi = max(values.max() ?? 1, lo + 1)
        let span = end.timeIntervalSince(start)
        // Times shorter than two days are read as clock times, longer ones as days.
        let dateText: (Date) -> String = span < 2 * 86_400
            ? { $0.formatted(date: .omitted, time: .shortened) }
            : { $0.formatted(.dateTime.day().month(.abbreviated)) }

        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Date"),
            range: start.timeIntervalSince1970...end.timeIntervalSince1970,
            gridlinePositions: []) { dateText(Date(timeIntervalSince1970: $0)) }
        let y = AXNumericDataAxisDescriptor(title: valueName, range: lo...hi, gridlinePositions: []) { valueText($0) }
        let series = AXDataSeriesDescriptor(
            name: title, isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.value) })
        return AXChartDescriptor(title: title, summary: nil, xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}
