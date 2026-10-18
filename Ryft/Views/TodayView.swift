import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var settings: Settings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if !settings.isConfigured {
                        ContentUnavailableView("Not connected",
                                               systemImage: "server.rack",
                                               description: Text("Add your server URL and API key in Settings."))
                    } else {
                        rings
                        if let s = state.today, s.calibrating {
                            Label("Calibrating — baselines need about 7 nights of data.", systemImage: "waveform.path.ecg")
                                .font(.footnote).foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }
                        metrics
                        workouts
                    }
                    if sync.isSyncing {
                        HStack { ProgressView(); Text(sync.progress).font(.footnote).foregroundStyle(.secondary) }
                    }
                    if let e = state.error ?? sync.lastError {
                        Text(e).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).day().month()))
            .refreshable {
                await sync.syncNow()
                await state.refresh()
            }
        }
    }

    private var rings: some View {
        let s = state.today
        return HStack(spacing: 16) {
            ScoreRing(value: s?.recovery.map { Double($0) / 100 },
                      label: "Recovery",
                      display: s?.recovery.map { "\($0)%" } ?? "–",
                      color: Bands.recovery(s?.recovery), size: 110)
            ScoreRing(value: s?.strain.map { $0 / 21 },
                      label: "Strain",
                      display: s?.strain.map { String(format: "%.1f", $0) } ?? "–",
                      color: Bands.strain(s?.strain), size: 110)
            ScoreRing(value: s?.sleepPerformance.map { Double($0) / 100 },
                      label: "Sleep",
                      display: s?.sleepPerformance.map { "\($0)%" } ?? "–",
                      color: Bands.sleep(s?.sleepPerformance), size: 110)
        }
        .padding(.horizontal)
    }

    private var metrics: some View {
        let s = state.today
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Metric(title: "HRV", value: s?.hrvMs.map { String(format: "%.0f ms", $0) })
            Metric(title: "Resting HR", value: s?.rhr.map { String(format: "%.0f bpm", $0) })
            Metric(title: "Respiratory rate", value: s?.respRate.map { String(format: "%.1f /min", $0) })
            Metric(title: "SpO₂", value: s?.spo2.map { String(format: "%.0f%%", $0) })
            Metric(title: "Sleep", value: s?.sleepActualMin.map(\.asHoursMinutes))
            Metric(title: "Sleep need", value: s?.sleepNeedMin.map(\.asHoursMinutes),
                   footnote: s?.sleepDebtMin.map { $0 > 0 ? "debt \($0.asHoursMinutes)" : nil } ?? nil)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var workouts: some View {
        if !state.todayWorkouts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Activities").font(.headline).padding(.horizontal)
                ForEach(state.todayWorkouts) { w in
                    HStack {
                        Image(systemName: "figure.run")
                        VStack(alignment: .leading) {
                            Text(w.activity.replacingOccurrences(of: "_", with: " ").capitalized)
                            Text("\(Int(w.duration / 60)) min" + (w.avgHr.map { String(format: " · %.0f bpm avg", $0) } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let st = w.strain {
                            Text(String(format: "%.1f", st))
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(Bands.strain(st))
                        }
                    }
                    .padding()
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }
        }
    }
}

private struct Metric: View {
    let title: String
    let value: String?
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "–").font(.title3.weight(.semibold).monospacedDigit())
            if let footnote { Text(footnote).font(.caption2).foregroundStyle(.orange) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
