import SwiftUI

/// The live session, optimised for sweaty thumbs: 56 pt targets, large
/// monospaced numbers, haptics on set check and rest end, the screen stays on.
/// Nothing destructive happens without a confirmation.
struct SessionView: View {
    var controller: SessionController
    @Environment(TrainCoordinator.self) private var coordinator
    @Environment(TrainSyncService.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// AX sizes: the rest bar shrinks to a pill once the list is scrolled during a rest…
    @State private var restBarScrolledAway = false
    /// …and a tap on the pill shows it whole for a moment.
    @State private var restBarPeek = false
    /// VoiceOver: after a jump, focus goes to the target set row (rows bind to it via `sessionVoiceOverFocus`).
    @AccessibilityFocusState private var voiceOverFocus: UUID?

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
            // Pinned outside the list, so a jump never scrolls the timer away (ui.md §6).
            if controller.rest.phase != .idle {
                RestBar(controller: controller, pill: restBarIsPill, onExpand: { restBarPeek = true })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
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
                        if controller.isAllDone {
                            AllSetsDoneCard(exercises: controller.exercises.count,
                                            sets: controller.session.completedSetCount) { confirmFinish = true }
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
                        Color.clear.frame(height: 1).id(Self.endAnchor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .animation(Theme.Motion.respecting(reduceMotion), value: controller.collapsed)
                    .environment(\.sessionVoiceOverFocus, $voiceOverFocus)
                }
                .scrollDismissesKeyboard(.never)
                .modifier(ManualScrollReporter { userScrolled() })
                .onChange(of: controller.focus) { _, focus in
                    guard let focus else { return }
                    withAnimation { proxy.scrollTo(focus.setID, anchor: .center) }
                }
                .onChange(of: controller.advance?.id) { _, _ in jump(to: controller.advance, with: proxy) }
                .onAppear {
                    if let focus = controller.focus { proxy.scrollTo(focus.setID, anchor: .center) }
                }
            }
            if controller.focus != nil {
                NumberPad(controller: controller) { kg in plates = PlateRequest(kg: kg, fromKeypad: true) }
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(Theme.Motion.quick, value: controller.focus == nil)
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.standard), value: restBarState)
        .onChange(of: controller.rest.isRunning) { _, _ in restBarScrolledAway = false }
        .task(id: restBarPeek) {
            // A tap on the pill shows the whole bar for 4 s.
            guard restBarPeek else { return }
            try? await Task.sleep(for: .seconds(4))
            restBarPeek = false
        }
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

    /// A finished exercise folds into one row after its last set (jump to next); a tap opens it again.
    @ViewBuilder
    private func card(for ex: LocalSessionExercise) -> some View {
        Group {
            if controller.isCollapsed(ex) {
                CollapsedExerciseRow(exercise: ex) { controller.expand(ex) }
            } else {
                ExerciseCard(controller: controller, exercise: ex,
                             onPlates: {
                                 let kg = ex.orderedSets.last { $0.weightKg != nil }?.weightKg ?? ex.targetKg ?? 60
                                 plates = PlateRequest(kg: kg, fromKeypad: false)
                             },
                             onHistory: { historyFor = ExerciseRef(id: ex.exerciseId, name: ex.name) })
            }
        }
        .transition(.opacity)
        .id(ex.id)
    }

    // MARK: jump to next

    private static let endAnchor = "session.end"

    /// Idle, running or over: the bar appears, changes or goes (not every ±15 s).
    private var restBarState: Int {
        switch controller.rest.phase {
        case .idle: 0
        case .running: 1
        case .finished: 2
        }
    }

    private var restBarIsPill: Bool {
        typeSize.isAccessibilitySize && (restBarScrolledAway || controller.focus != nil) && !restBarPeek
    }

    private func userScrolled() {
        controller.userScrolled()
        if typeSize.isAccessibilitySize, controller.rest.isRunning, !restBarScrolledAway { restBarScrolledAway = true }
    }

    /// The controller decided: the next set goes to the top under the rest bar, or the list to its end.
    private func jump(to request: AdvanceRequest?, with proxy: ScrollViewProxy) {
        guard let request else { return }
        let animation = Theme.Motion.respecting(reduceMotion, Theme.Motion.standard)
        switch request.step {
        case .stay:
            return
        case let .advance(_, to):
            // A first set: the whole card, so its name and last time show above it.
            let first = controller.exercises.first { $0.id == to.exerciseID }?.orderedSets.first?.id == to.setID
            let target: UUID = first ? to.exerciseID : to.setID
            withAnimation(animation) { proxy.scrollTo(target, anchor: .top) }
            if UIAccessibility.isVoiceOverRunning { voiceOverFocus = to.setID }
        case .allDone:
            withAnimation(animation) { proxy.scrollTo(Self.endAnchor, anchor: .bottom) }
            if UIAccessibility.isVoiceOverRunning {
                AccessibilityNotification.Announcement(String(
                    localized: "All sets done. Finish workout available at the bottom.",
                    comment: "VoiceOver announcement when the last set of a workout is checked off.")).post()
            }
        }
    }

    private func finish() async {
        await coordinator.finish(controller)
    }
}

/// Tells the controller when the user (not `scrollTo`) moves the list: a jump waits 3 s after that.
/// iOS 18 reports the scroll phase; iOS 17 sees the drag (a simultaneous gesture, so scrolling still wins).
private struct ManualScrollReporter: ViewModifier {
    var onScroll: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollPhaseChange { old, new in
                // The finger on the list, and again when it lets go or the list coasts to a stop.
                if new == .interacting || new == .decelerating || old == .interacting || old == .decelerating {
                    onScroll()
                }
            }
        } else {
            content.simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in onScroll() })
        }
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
