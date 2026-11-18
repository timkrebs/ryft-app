import SwiftUI

/// After Finish: duration, volume, muscular load, strain, PRs, notes → Done.
struct SessionSummarySheet: View {
    let summary: FinishSummary
    @Environment(TrainSyncService.self) private var sync
    @Environment(TrainLibrary.self) private var library
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var notes = ""
    @State private var celebrate = false
    /// Where the strain's heart rate came from (the platform's workout for the session).
    @State private var heartRate: String?
    @State private var savingToHealth = false
    private var export: WorkoutHealthExport { .shared }

    private var session: LocalSession? { sync.store.session(id: summary.sessionID) }

    /// The server's answer: at finish, or later from the queue.
    private var completed: TrainSession? {
        summary.completed ?? sync.lastCompletion.flatMap { $0.id == summary.sessionID ? $0 : nil }
    }

    var body: some View {
        let doc = completed ?? session?.wire
        let prs = completed?.prs ?? session?.prs ?? []
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Image(systemName: prs.isEmpty ? "checkmark.seal.fill" : "trophy.fill")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(prs.isEmpty ? Theme.accent : Theme.warning)
                            .symbolEffect(.bounce, value: celebrate)
                            .scaleEffect(celebrate || reduceMotion ? 1 : 0.6)
                            .animation(reduceMotion ? nil : Theme.Motion.standard.delay(0.15),
                                       value: celebrate)
                        Text(prs.isEmpty ? String(localized: "Workout done")
                                         : String(localized: "\(prs.count) new PRs"))
                            .font(.ryft(.title))
                            .foregroundStyle(Theme.textPrimary)
                        Text(doc?.title ?? "")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)

                    HStack(spacing: 10) {
                        MetricTile(title: "Duration", value: duration(doc), systemImage: "clock")
                        MetricTile(title: "Volume", value: Fmt.volume(doc?.volumeKg ?? session?.liveVolumeKg),
                                   systemImage: "scalemass")
                    }
                    HStack(spacing: 10) {
                        MetricTile(title: "Muscular load", value: Fmt.load(doc?.muscularTrimp),
                                   systemImage: "dumbbell.fill", tint: Theme.accentSecondary)
                        MetricTile(title: "Strain", value: Fmt.strain(doc?.strain), systemImage: "bolt.fill")
                    }
                    if completed == nil && session?.pendingCompletion == true {
                        WillSyncNote().frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let heartRate {
                        Label(heartRate, systemImage: "heart")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("summary.heartRate")
                    }
                    if export.shouldAsk { saveToHealth }
                    if !prs.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                CardHeader(title: "Personal records")
                                ForEach(prs, id: \.self) { pr in
                                    PRBadge(record: pr, exerciseName: library.exercise(id: pr.exerciseId)?.name)
                                }
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            CardHeader(title: "Notes")
                            TextField("How did it feel?", text: $notes, axis: .vertical)
                                .font(.ryft(.body))
                                .lineLimit(3...6)
                        }
                    }
                    Button("Done") { done() }
                        .buttonStyle(TealButtonStyle())
                        .accessibilityIdentifier("summary.done")
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sensoryFeedback(.success, trigger: celebrate)
        .onAppear {
            notes = session?.notes ?? ""
            celebrate = true
        }
        .task(id: completed?.workoutId) { await loadHeartRate() }
        .interactiveDismissDisabled()
    }

    /// Once, after the first completed workout: RYFT writes nothing to Apple Health unless asked.
    private var saveToHealth: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Save workouts to Apple Health?", systemImage: "heart.text.square")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your strength workouts then appear in Fitness and Health. RYFT writes only the workout, no heart rate. You can change this in Profile.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button {
                        savingToHealth = true
                        Task {
                            defer { savingToHealth = false }
                            guard await export.turnOn(), let s = session, let end = s.endedAt else { return }
                            await export.save(sessionID: s.id, start: s.startedAt, end: end)
                        }
                    } label: {
                        Text("Save")
                    }
                    .buttonStyle(TealButtonStyle(prominent: true))
                    .disabled(savingToHealth)
                    Button { export.turnOff() } label: { Text("Not now") }
                        .buttonStyle(TealButtonStyle(prominent: false))
                        .disabled(savingToHealth)
                }
                if export.needsAccess { HealthWriteAccessHint() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("summary.saveToHealth")
    }

    /// "Heart rate from Garmin Connect" when the platform matched a watch's workout; otherwise
    /// how to get heart-rate strain next time.
    private func loadHeartRate() async {
        guard let id = completed?.workoutId else { return }
        guard let detail = try? await state.source.workout(id: id) else { return }
        heartRate = Self.heartRateLine(detail.workout)
    }

    static func heartRateLine(_ workout: Workout) -> String {
        if workout.avgHr != nil, workout.source != "ryft-session" {
            return String(localized: "Heart rate from \(workout.source)")
        }
        // A watch workout may still be on its way (it's matched once it syncs).
        return String(localized: "No heart rate yet. With a strength workout on your watch too, it arrives once the watch syncs.")
    }

    private func duration(_ doc: TrainSession?) -> String {
        guard let doc, let end = doc.endedAt else { return Fmt.placeholder }
        return Fmt.duration(seconds: end.timeIntervalSince(doc.startedAt))
    }

    private func done() {
        if let s = session, s.notes != notes {
            s.notes = notes
            sync.sessionChanged(s)
        }
        dismiss()
    }
}

#Preview("Summary · dark") {
    let s = MockTrain.liveSession(in: TrainPreview.store)
    s.status = .completed
    s.endedAt = .now
    return SessionSummarySheet(summary: FinishSummary(sessionID: s.id, completed: MockTrain.completed))
        .previewEnvironment()
}

#Preview("Summary · light, will sync") {
    let s = MockTrain.liveSession(in: TrainPreview.store)
    s.status = .completed
    s.endedAt = .now
    s.pendingCompletion = true
    return SessionSummarySheet(summary: FinishSummary(sessionID: s.id, completed: nil))
        .previewEnvironment(scheme: .light)
}
