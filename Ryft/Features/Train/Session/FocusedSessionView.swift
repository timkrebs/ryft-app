import SwiftUI

/// The Focused layout: one exercise per page under a strip of tiles (design.md, architecture.md §8). `SessionView` stays
/// the host and keeps what both layouts share; this replaces only the list. The toast is a stack row here, never on a
/// page: its `onDisappear` commits the replace, and a swipe mustn't do that.
struct FocusedSessionView: View {
    var controller: SessionController
    let actions: SessionActions

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Moves it: a strip double tap (the title), an advance and an auto-fold (the active row). Titles and rows bind to it
    /// (`sessionVoiceOverFocus`).
    @AccessibilityFocusState private var voiceOverFocus: UUID?
    @State private var width: CGFloat = 0
    @State private var sheet: ExerciseSheet?
    @State private var removing: UUID?

    private var columns: SetTableColumns { .fitting(width: width) }

    /// Longer than the page's move: a row isn't in the accessibility tree while its page is hidden.
    private static let focusDelay: Duration = .milliseconds(350)

    private func row(_ id: UUID?) -> LocalSessionExercise? {
        controller.exercises.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !controller.sync.isOnline { offlineBanner }
            ExerciseStrip(controller: controller, inset: columns.padding, onAdd: actions.addExercise, onReorder: actions.reorder) {
                voiceOverFocus = $0
            }
            if controller.exercises.isEmpty {
                emptyPage
            } else {
                pager
            }
            SessionToastOverlay(controller: controller)
        }
        .environment(\.sessionVoiceOverFocus, $voiceOverFocus)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear { controller.pinPage() }
        // The first exercise of an empty session: nothing to swipe from, and `resolve` chose it.
        .onChange(of: controller.pageExerciseID) { _, _ in controller.pinPage() }
        .onChange(of: controller.advance?.id) { _, _ in perform(controller.advance) }
        .onChange(of: controller.autoFold?.id) { _, _ in focusAfterFold(controller.autoFold) }
        .sheet(item: $sheet) { content(for: $0) }
        .confirmationDialog(Text("Remove \(row(removing)?.name ?? "")?"),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove exercise", role: .destructive) {
                if let ex = row(removing) { controller.remove(ex) }
            }
        } message: {
            Text("Its sets in this workout are deleted.")
        }
    }

    /// The planner decided (L1). `.advance` is a page change and its `collapse` is ignored: no Focused view reads it. The
    /// page stays on `.allDone`, and shows its footer (`ExercisePage`).
    private func perform(_ request: AdvanceRequest?) {
        guard let request else { return }
        switch request.step {
        case .stay:
            return
        case let .advance(_, to):
            withAnimation(Theme.Motion.respecting(reduceMotion)) { controller.follow(request) }
            guard voiceOver, let ex = row(to.exerciseID), let set = controller.activeSet(in: ex) else { return }
            moveVoiceOver(to: set.id, announcing: controller.pageAnnouncement(of: ex))
        case .allDone:
            guard voiceOver else { return }
            AccessibilityNotification.Announcement(String(
                localized: "All sets done. Finish workout available at the bottom.",
                comment: "VoiceOver announcement when the last set of a workout is checked off.")).post()
        }
    }

    /// The row VoiceOver was on just left the table (review S4): the active row, else the title.
    private func focusAfterFold(_ fold: AutoFold?) {
        guard voiceOver, let ex = row(fold?.exerciseID) else { return }
        moveVoiceOver(to: controller.activeSet(in: ex)?.id ?? ex.id, announcing: nil)
    }

    private func moveVoiceOver(to id: UUID, announcing text: String?) {
        Task { @MainActor in
            try? await Task.sleep(for: Self.focusDelay)
            voiceOverFocus = id
            if let text { AccessibilityNotification.Announcement(text).post() }
        }
    }

    private var offlineBanner: some View {
        Label("Offline — every set is saved on this phone and syncs later.", systemImage: "wifi.slash")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, columns.padding)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private var pager: some View {
        SessionPager(pages: controller.exercises.map(\.id),
                     selection: Binding(get: { controller.pageExerciseID }, set: { if let id = $0 { controller.jump(to: id) } }),
                     onDrag: actions.userScrolled) { id in
            if let ex = row(id) {
                ExercisePage(controller: controller, exercise: ex, columns: columns,
                             onSheet: { sheet = $0 }, onRemove: { removing = ex.id },
                             onPlates: { actions.plates(ex) }, onHistory: { actions.history(ex) }, onFinish: actions.finish)
            }
        }
    }

    /// No pager with no pages: the + tile above is the way in.
    private var emptyPage: some View {
        VStack {
            InlineMessage(message: String(localized: "An empty session. Add your first exercise."), systemImage: "dumbbell")
            Spacer()
        }
        .padding(.horizontal, columns.padding)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func content(for sheet: ExerciseSheet) -> some View {
        switch sheet {
        case let .replace(id):
            if let ex = row(id) {
                AddExerciseSheet(replacing: controller.replaceContext(for: ex)) { picked, alsoChangePlan in
                    let window = SessionController.undoWindow(voiceOver: voiceOver, switchControl: switchControl)
                    Task { await controller.replace(ex, with: picked, alsoChangePlan: alsoChangePlan, window: window) }
                }
                .presentationDetents([.large])
            }
        case let .targets(id):
            if let ex = row(id) { EditTargetsSheet(controller: controller, exercise: ex) }
        case let .notes(id):
            if let ex = row(id) { ExerciseNotesSheet(controller: controller, exercise: ex) }
        }
    }
}

@MainActor
private func session(_ scenario: FocusedPreview.Scenario) -> some View {
    SessionView(controller: FocusedPreview.controller(scenario))
}

#Preview("Focused · dark") {
    session(.midSession).previewEnvironment()
}

#Preview("Focused · light") {
    session(.midSession).previewEnvironment(scheme: .light)
}

#Preview("Focused · keypad") {
    let c = FocusedPreview.controller(.midSession)
    if let ex = c.pageExercise { c.edit(ex.orderedSets[0], .kg) }
    return SessionView(controller: c).previewEnvironment()
}

#Preview("Focused · superset, dark") {
    session(.superset).previewEnvironment()
}

#Preview("Focused · superset, light") {
    session(.superset).previewEnvironment(scheme: .light)
}

#Preview("Focused · offline, dark") {
    session(.offline).previewEnvironment()
}

#Preview("Focused · offline, light") {
    session(.offline).previewEnvironment(scheme: .light)
}

#Preview("Focused · empty, dark") {
    session(.empty).previewEnvironment()
}

#Preview("Focused · empty, light") {
    session(.empty).previewEnvironment(scheme: .light)
}

#Preview("Focused · all done, dark") {
    session(.allDone).previewEnvironment()
}

#Preview("Focused · all done, light") {
    session(.allDone).previewEnvironment(scheme: .light)
}

#Preview("Focused · 320 pt", traits: .fixedLayout(width: 320, height: 693)) {
    session(.midSession).previewEnvironment()
}
