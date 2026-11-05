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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var size: CGSize = .zero
    @State private var sheet: ExerciseSheet?
    @State private var removing: UUID?
    /// One pending focus move: a new one replaces it, so an old one can't land after it or after the screen went.
    @State private var voiceOverMove: Task<Void, Never>?

    private var columns: SetTableColumns { .fitting(width: size.width, typeSize: typeSize) }
    private var hidesStrip: Bool {
        Self.hidesStrip(columns: columns, keypadOpen: controller.focus != nil, height: size.height,
                        pillRow: controller.restPillState == .hidden ? 0 : RestPill.rowHeight(typeSize), typeSize: typeSize)
    }

    /// The page's least room beside the keypad at 320 pt (design.md §5.1): under it the strip gives way until Done. With a
    /// rest running too, the page gets 138 pt even then. That stays: it holds the row being edited, whole, with about 40 pt of
    /// each neighbour, and the rest of the room belongs to the 56 pt keys and the running pill (design.md §2.5, §2.7).
    private static let roomWithKeypad: CGFloat = 220

    /// `height` is this view's, strip and pill row included, so hiding the strip doesn't change the answer.
    static func hidesStrip(columns: SetTableColumns, keypadOpen: Bool, height: CGFloat, pillRow: CGFloat,
                           typeSize: DynamicTypeSize) -> Bool {
        keypadOpen && columns.isCompact && height - ExerciseStrip.height(typeSize) - pillRow < roomWithKeypad
    }

    /// The page's soft top edge, about a line of text, so nothing shows cut in half under the header. `ExercisePage` keeps its
    /// title clear of it.
    static let topFade: CGFloat = 16
    /// Beside the keypad with the strip gone, the page ends right under the header, usually mid-line: solid for what shows of
    /// that line, then a fade that ends above the table's header, where `proxy.scrollTo` leaves it with the row centred.
    static let keypadFade: CGFloat = 28
    private static let keypadFadeSolid = 0.65

    /// Longer than the page's move: a row isn't in the accessibility tree while its page is hidden.
    private static let focusDelay: Duration = .milliseconds(350)

    private func row(_ id: UUID?) -> LocalSessionExercise? {
        controller.exercises.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !controller.sync.isOnline { offlineBanner }
            if !hidesStrip {
                ExerciseStrip(controller: controller, inset: columns.padding, onAdd: actions.addExercise, onReorder: actions.reorder) {
                    voiceOverFocus = $0
                }
                .transition(.opacity)
            }
            if controller.exercises.isEmpty {
                emptyPage
            } else {
                pager
            }
            SessionToastOverlay(controller: controller)
            if controller.restPillState != .hidden { pillRow }
        }
        .animation(Theme.Motion.respecting(reduceMotion), value: controller.restPillState)
        .animation(Theme.Motion.respecting(reduceMotion), value: hidesStrip)
        .environment(\.sessionVoiceOverFocus, $voiceOverFocus)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onAppear { controller.pinPage() }
        // The first exercise of an empty session: nothing to swipe from, and `resolve` chose it.
        .onChange(of: controller.pageExerciseID) { _, _ in controller.pinPage() }
        .onChange(of: controller.advance?.id) { _, _ in perform(controller.advance) }
        .onChange(of: controller.autoFold?.id) { _, _ in focusAfterFold(controller.autoFold) }
        .onChange(of: controller.emptyCheck?.id) { _, _ in announceEmptyCheck() }
        .onDisappear { voiceOverMove?.cancel() }
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

    /// The row didn't change and nothing was logged, so VoiceOver says why (L23). Focus stays on the row. It replaces a
    /// pending move: the user acted since, and its announcement would cut this one off.
    private func announceEmptyCheck() {
        guard voiceOver, controller.emptyCheck != nil else { return }
        moveVoiceOver(to: nil, announcing: String(
            localized: "Nothing logged yet. Enter a value on the keypad.",
            comment: "VoiceOver announcement when a set is checked off with no values: nothing is logged and the keypad opens."))
    }

    /// `to` nil: only the announcement, after the same wait, so the keypad's appearing doesn't cut it off.
    private func moveVoiceOver(to id: UUID?, announcing text: String?) {
        voiceOverMove?.cancel()
        voiceOverMove = Task { @MainActor in
            do { try await Task.sleep(for: Self.focusDelay) } catch { return }
            if let id { voiceOverFocus = id }
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
        // Rows scroll out under the strip through a soft edge rather than a cut. Above any title at rest, so it only shows
        // once the page moved.
        .overlay(alignment: .top) {
            LinearGradient(stops: [.init(color: Theme.background, location: hidesStrip ? Self.keypadFadeSolid : 0),
                                   .init(color: Theme.background.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: hidesStrip ? Self.keypadFade : Self.topFade)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// A stack row, as the toast (architecture.md §8): the page ends above it, so no margin is needed, and `SessionView`'s
    /// keypad sits below it. `session.restBar` marks a rest under way, as on List's bar.
    private var pillRow: some View {
        RestPill(controller: controller) {
            controller.focus = nil
            sheet = controller.pageExerciseID.map(ExerciseSheet.rest)
        }
        .padding(.vertical, RestPill.rowPadding)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(controller.restPillState == .idle ? "" : "session.restBar")
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
        case let .rest(id):
            if let ex = row(id) { RestSheet(controller: controller, exercise: ex) }
        case let .restChoices(id):
            if let ex = row(id) { RestChoicesSheet(controller: controller, exercise: ex) }
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

#Preview("Focused · rest running, dark") {
    session(.restRunning).previewEnvironment()
}

#Preview("Focused · rest running, light") {
    session(.restRunning).previewEnvironment(scheme: .light)
}

#Preview("Focused · rest running, keypad") {
    let c = FocusedPreview.controller(.restRunning)
    if let ex = c.pageExercise { c.edit(ex.orderedSets[0], .kg) }
    return SessionView(controller: c).previewEnvironment()
}

#Preview("Focused · 320 pt", traits: .fixedLayout(width: 320, height: 693)) {
    session(.midSession).previewEnvironment()
}
