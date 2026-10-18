import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    chart("Recovery", unit: "%", color: .green) { $0.recovery.map(Double.init) }
                    chart("Strain", unit: "", color: .blue) { $0.strain }
                    chart("Sleep performance", unit: "%", color: .indigo) { $0.sleepPerformance.map(Double.init) }
                    chart("HRV", unit: "ms", color: .teal) { $0.hrvMs }
                    chart("Resting HR", unit: "bpm", color: .red) { $0.rhr }
                }
                .padding()
            }
            .navigationTitle("Last 30 days")
            .refreshable { await state.refresh() }
        }
    }

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private func chart(_ title: String, unit: String, color: Color, _ pick: @escaping (DailyScore) -> Double?) -> some View {
        let points = state.history.compactMap { d in pick(d).map { Point(date: d.date, value: $0) } }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let last = points.last {
                    Text(String(format: "%.0f %@", last.value, unit)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if points.isEmpty {
                Text("No data yet").font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart(points) { p in
                    LineMark(x: .value("Day", p.date), y: .value(title, p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(color)
                    AreaMark(x: .value("Day", p.date), y: .value(title, p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(color.opacity(0.12))
                    PointMark(x: .value("Day", p.date), y: .value(title, p.value))
                        .symbolSize(18)
                        .foregroundStyle(color)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 150)
            }
        }
    }
}
