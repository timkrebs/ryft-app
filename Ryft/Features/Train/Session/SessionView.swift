import SwiftUI

/// The live session, optimised for sweaty thumbs: 56 pt targets, large
/// monospaced numbers, haptics on set check and rest end, the screen stays on.
/// Nothing destructive happens without a confirmation.
struct SessionView: View {
    var controller: SessionController
    @Environment(TrainCoordinator.self) private var coordinator
    @Environment(TrainSyncService.self) private var sync
    @Environment(\.scenePhase) private var scenePhase

    @State private var showsAdd = false
    @State private var showsReorder = false
    @State private var confirmDiscard = false
    @State private var confirmFinish = false
    @State private var plates: PlateRequest?
    @State private var historyFor: ExerciseRef?

    private struct PlateRequest: Identifiable {
        let kg: Double
        let fromKeypad: Bool
        var id: Double { kg }
    }

    private struct ExerciseRef: Identifiable {
        let id: UUID
        let name: String
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                // Backgrounded mid-workout: paused until the app is back.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { controller.pause() } else if phase == .active { controller.resume() }
                }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        RestTimerView(controller: controller)
                            .animation(.snappy, value: controller.rest.phase)
                        if !sync.isOnline {
                            Label("Offline — every set is saved on this phone and syncs later.",
                                  systemImage: "wifi.slash")
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        exerciseList
                        if controller.exercises.isEmpty {
                            InlineMessage(message: String(localized: "An empty session. Add your first exercise."),
                                          systemImage: "dumbbell")
                        }
                        Button {
                            showsAdd = true
                        } label: {
                            Label("Add exercise", systemImage: "plus")
                        }
                        .buttonStyle(TealButtonStyle(prominent: false))
                        if controller.exercises.count > 1 {
                            Button("Reorder exercises") { showsReorder = true }
                                .font(.ryft(.callout))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.never)
                .onChange(of: controller.focus) { _, focus in
                    guard let focus else { return }
                    withAnimation { proxy.scrollTo(focus.setID, anchor: .center) }
                }
                .onAppear {
                    if let focus = controller.focus { proxy.scrollTo(focus.setID, anchor: .center) }
                }
            }
            if controller.focus != nil {
                NumberPad(controller: controller) { kg in plates = PlateRequest(kg: kg, fromKeypad: true) }
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.snappy(duration: 0.25), value: controller.focus == nil)
        .background(Theme.background.ignoresSafeArea())
        .modifier(KeepsScreenAwake())
        .sensoryFeedback(.success, trigger: controller.setsChecked)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: controller.restsEnded)
        .sheet(isPresented: $showsAdd) {
            AddExerciseSheet { controller.add($0) }
        }
        .sheet(item: Bindable(coordinator).summary, onDismiss: { coordinator.summaryDone() }) {
            SessionSummarySheet(summary: $0)
        }
        .sheet(isPresented: $showsReorder) {
            ReorderSheet(controller: controller)
        }
        .sheet(item: $plates) { request in
            PlateCalculatorSheet(target: request.kg,
                                 onUse: request.fromKeypad ? { controller.setWeight($0) } : nil)
        }
        .sheet(item: $historyFor) { ref in
            NavigationStack {
                ExerciseDetailView(exerciseID: ref.id, name: ref.name)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { historyFor = nil } }
                    }
            }
        }
        .confirmationDialog("Finish workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish workout") { Task { await finish() } }
        } message: {
            Text("\(controller.session.completedSetCount) sets checked off. Empty rows are dropped.")
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) { coordinator.discard(controller) }
        } message: {
            Text("All \(controller.session.completedSetCount) logged sets are deleted. This can't be undone.")
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                coordinator.close()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(Theme.surface, in: Circle())
            }
            .accessibilityLabel(Text("Minimise"))
            .accessibilityHint(Text("The workout keeps running"))

            VStack(spacing: 0) {
                Text(controller.session.title)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Fmt.clock(controller.elapsed(at: context.date)))
                        .font(.ryftNumber(size: 30))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(controller.session.title), elapsed time"))

            Menu {
                Button("Reorder exercises", systemImage: "arrow.up.arrow.down") { showsReorder = true }
                Button("Discard workout", systemImage: "trash", role: .destructive) { confirmDiscard = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(Theme.surface, in: Circle())
            }
            .accessibilityLabel(Text("More"))

            Button {
                confirmFinish = true
            } label: {
                Group {
                    if controller.isFinishing { ProgressView().tint(Theme.onAccent) } else { Text("Finish") }
                }
                .font(.ryft(.headline))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
                .background(Theme.accent, in: Capsule())
            }
            .disabled(controller.isFinishing)
            .accessibilityIdentifier("session.finish")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: exercises

    /// Consecutive exercises in one superset group share a bracket.
    private var groups: [[LocalSessionExercise]] {
        var out: [[LocalSessionExercise]] = []
        for ex in controller.exercises {
            if let g = ex.supersetGroup, let last = out.last?.last, last.supersetGroup == g {
                out[out.count - 1].append(ex)
            } else {
                out.append([ex])
            }
        }
        return out
    }

    private var exerciseList: some View {
        ForEach(groups, id: \.first?.id) { group in
            if group.count > 1 {
                SupersetBracket {
                    ForEach(group) { card(for: $0) }
                }
            } else if let ex = group.first {
                card(for: ex)
            }
        }
    }

    private func card(for ex: LocalSessionExercise) -> some View {
        ExerciseCard(controller: controller, exercise: ex,
                     onPlates: {
                         let kg = ex.orderedSets.last { $0.weightKg != nil }?.weightKg ?? ex.targetKg ?? 60
                         plates = PlateRequest(kg: kg, fromKeypad: false)
                     },
                     onHistory: { historyFor = ExerciseRef(id: ex.exerciseId, name: ex.name) })
            .id(ex.id)
    }

    private func finish() async {
        await coordinator.finish(controller)
    }
}

/// Drag to reorder (the list is in edit mode).
struct ReorderSheet: View {
    var controller: SessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(controller.exercises) { ex in
                    HStack {
                        Text(ex.name).font(.ryft(.body))
                        Spacer()
                        if ex.supersetGroup != nil {
                            Image(systemName: "link").foregroundStyle(Theme.accent)
                                .accessibilityLabel(Text("In a superset"))
                        }
                    }
                    .frame(minHeight: 44)
                    .listRowBackground(Theme.surface)
                }
                .onMove { controller.move(from: $0, to: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// After Finish: duration, volume, muscular load, strain, PRs, notes → Done.
struct SessionSummarySheet: View {
    let summary: FinishSummary
    @Environment(TrainSyncService.self) private var sync
    @Environment(TrainLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var notes = ""
    @State private var celebrate = false

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
                            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55).delay(0.15),
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
        .interactiveDismissDisabled()
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

#Preview("Live session · dark") {
    SessionView(controller: TrainPreview.liveController())
        .previewEnvironment()
}

#Preview("Live session · light") {
    SessionView(controller: TrainPreview.liveController())
        .previewEnvironment(scheme: .light)
}

#Preview("Live session · keypad") {
    let c = TrainPreview.liveController()
    c.edit(c.exercises[0].orderedSets[2], .kg)
    return SessionView(controller: c).previewEnvironment()
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
