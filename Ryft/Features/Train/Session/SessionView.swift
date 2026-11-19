import SwiftUI

/// What `SessionView` hosts for the Focused layout: its sheets stay above both layouts.
struct SessionActions {
    var addExercise: () -> Void
    var reorder: () -> Void
    var plates: (LocalSessionExercise) -> Void
    var history: (LocalSessionExercise) -> Void
    /// A finger on the pages: no jump for the next 3 s.
    var userScrolled: () -> Void
    /// The same confirmation as the header's Finish.
    var finish: () -> Void
}

/// Finish beside the circles and the title (PR 6 B §4.1): the compact pill keeps its one line, so in a full row its type stops
/// growing (`.xxLarge`, `.large` at 320) and a long press shows it large. List's stacked header at the accessibility sizes gives
/// it a row of its own, where it grows.
private struct FinishCap: ViewModifier {
    let isOn: Bool
    let cap: DynamicTypeSize

    func body(content: Content) -> some View {
        if isOn {
            content
                .dynamicTypeSize(...cap)
                .accessibilityShowsLargeContentViewer()
        } else {
            content
        }
    }
}

/// Text that stops growing at 320 pt. The keypad, in Focused: every point it takes is the page's, and at AX3 with a rest the
/// row being edited wouldn't fit. The session's title, beside the buttons: at AX3 it was cut to "Upp…". Wider screens keep their
/// sizes.
private struct CompactTextCap: ViewModifier {
    let isOn: Bool
    let cap: DynamicTypeSize

    func body(content: Content) -> some View {
        if isOn { content.dynamicTypeSize(...cap) } else { content }
    }
}

/// The session's title: one line beside the buttons; on its own full-width line (List at the accessibility sizes) it wraps
/// whole instead of being cut.
private struct SessionTitleLines: ViewModifier {
    let wraps: Bool

    func body(content: Content) -> some View {
        if wraps {
            content
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            content.lineLimit(1)
        }
    }
}

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
    @State private var width: CGFloat = 0

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
            if restBarState != 0 {
                RestBar(controller: controller, pill: restBarIsPill, onExpand: { restBarPeek = true })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
            if controller.layout == .focused {
                FocusedSessionView(controller: controller, actions: actions)
            } else {
                listContent
            }
            // A session reopened with its keypad up: laid out before there's a width, it squeezes a 320 pt page to nothing and
            // the pager gives up its page, and with it the keypad.
            if controller.focus != nil, controller.layout == .list || width > 0 {
                NumberPad(controller: controller) { kg in plates = PlateRequest(kg: kg, fromKeypad: true) }
                    .modifier(CompactTextCap(isOn: controller.layout == .focused && isCompactHeader, cap: .xxLarge))
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Theme.background.ignoresSafeArea())
        .modifier(KeepsScreenAwake())
        .sensoryFeedback(.success, trigger: controller.setsChecked)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: controller.restsEnded)
        .sheet(isPresented: $showsAdd) {
            AddExerciseSheet { picked in
                let row = controller.add(picked)
                // Focused: the new exercise's page. The list stays where it is.
                if controller.layout == .focused {
                    withAnimation(Theme.Motion.respecting(reduceMotion)) { controller.jump(to: row.id) }
                }
            }
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

    /// 320 pt, in both layouts (design.md §2.1, PR 6 B §4.1): 12 pt sides, 6 pt gaps and the 26 pt clock on one line, since an
    /// hour clock doesn't fit the middle at 30 pt. Finish and the title stop growing sooner.
    private var isCompactHeader: Bool { SetTableColumns.fitting(width: width).isCompact }
    private var headerGap: CGFloat { isCompactHeader ? LiveSessionSpec.compactHeaderGap : LiveSessionSpec.headerGap }

    /// List at the accessibility sizes: the buttons get a row of their own and the title and clock the full width under it.
    /// Side by side, Finish broke into "Finis/h" and at the largest sizes the title was cut. Focused keeps its one row (§5.1).
    private var stacksHeader: Bool { controller.layout == .list && typeSize.isAccessibilitySize }

    /// PR 6 B §4.1: the minimise circle, the title over the clock, the More circle and Finish, 8 apart (6 at 320) from circle
    /// edge to circle edge; each circle's edge, not its 44 pt box, on the page's 16 pt side (12 at 320). 6 above and below.
    private var header: some View {
        Group {
            if stacksHeader {
                // VoiceOver keeps the one-row order (Minimise, the title and clock, More, Finish), not the drawn one.
                VStack(spacing: headerGap) {
                    HStack(spacing: headerGap) {
                        minimiseButton.accessibilitySortPriority(4)
                        Spacer(minLength: headerGap)
                        moreMenu.accessibilitySortPriority(2)
                        finishButton.accessibilitySortPriority(1)
                    }
                    titleAndClock.accessibilitySortPriority(3)
                }
                .accessibilityElement(children: .contain)
            } else {
                HStack(spacing: headerGap) {
                    minimiseButton
                    titleAndClock
                    moreMenu
                    finishButton
                }
                .frame(minHeight: LiveSessionSpec.headerRow)
            }
        }
        .padding(.horizontal, isCompactHeader ? LiveSessionSpec.compactSidePadding : LiveSessionSpec.sidePadding)
        .padding(.vertical, LiveSessionSpec.headerVerticalPadding)
    }

    private var minimiseButton: some View {
        CircleButton(systemImage: "chevron.down", iconSize: LiveSessionSpec.headerIcon, accessibilityLabel: Text("Minimise")) {
            coordinator.close()
        }
        .headerEdgeButton()
        .accessibilityHint(Text("The workout keeps running"))
    }

    private var titleAndClock: some View {
        VStack(spacing: 0) {
            Text(controller.session.title)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .modifier(SessionTitleLines(wraps: stacksHeader))
                // Beside the buttons only: List's stacked title has the full width.
                .modifier(CompactTextCap(isOn: isCompactHeader && !stacksHeader, cap: LiveSessionSpec.compactTitleCap))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Fmt.clock(controller.elapsed(at: context.date)))
                    .font(.ryftNumber(size: isCompactHeader ? LiveSessionSpec.compactClock : LiveSessionSpec.clock))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(isCompactHeader ? 1 : nil)
                    .minimumScaleFactor(isCompactHeader ? LiveSessionSpec.compactClockScale : 1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(controller.session.title), elapsed time"))
    }

    /// A menu, so a `CircleButton` (a button) can't be it: the label draws the circle button's look from its numbers. Its type
    /// doesn't grow, so a long press shows it large, as the circle buttons do.
    private var moreMenu: some View {
        Menu {
            Button("Reorder exercises", systemImage: "arrow.up.arrow.down") { showsReorder = true }
            Button("Discard workout", systemImage: "trash", role: .destructive) { confirmDiscard = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: LiveSessionSpec.headerIcon, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: CircleButton.diameter, height: CircleButton.diameter)
                .overlay {
                    Circle().strokeBorder(Theme.textPrimary.opacity(CircleButton.borderOpacity), lineWidth: Theme.Metrics.hairline)
                }
                .frame(width: CircleButton.hitSize, height: CircleButton.hitSize)
                .contentShape(Rectangle())
        }
        .headerEdgeButton()
        .accessibilityLabel(Text("More"))
        .accessibilityShowsLargeContentViewer {
            Label { Text("More") } icon: { Image(systemName: "ellipsis") }
        }
    }

    /// An outline until every set is done, then filled (F14, D6B-5): one primary at a time, and at all-done the card's
    /// "Finish workout" and this one. While it finishes, the pill's spinner (the title and width stay) and no second tap.
    private var finishButton: some View {
        PillButton(Text("Finish"), style: controller.finishIsFilled ? .primary : .secondary, size: .compact,
                   busy: controller.isFinishing) {
            confirmFinish = true
        }
        .modifier(FinishCap(isOn: !stacksHeader,
                            cap: isCompactHeader ? LiveSessionSpec.compactFinishCap : LiveSessionSpec.finishCap))
        .accessibilityIdentifier("session.finish")
    }

    // MARK: exercises

    /// The list layout (PR 6 B §4.7, `b-02`): every exercise on one screen, 16 pt sides. Under the cards "Add exercise" as an
    /// outline pill (the header's Finish is the one primary, and only once every set is done) and "Reorder exercises" as a quiet
    /// text button. Offline is one grey line; an empty session an outlined card, as in Focused (§4.9).
    private var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    if !sync.isOnline {
                        Label("Offline — every set is saved on this phone and syncs later.",
                              systemImage: "wifi.slash")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    }
                    exerciseList
                    if controller.exercises.isEmpty {
                        InlineMessage(message: String(localized: "An empty session. Add your first exercise."),
                                      systemImage: "dumbbell")
                            // Focused's empty page: the message's 1 pt `separator` edge over its `surface`.
                            .overlay {
                                RoundedRectangle(cornerRadius: InlineMessageSpec.radius, style: .continuous)
                                    .strokeBorder(Theme.separator, lineWidth: PlaceholderRowSpec.lineWidth)
                                    .accessibilityHidden(true)
                            }
                    }
                    if controller.isAllDone {
                        AllSetsDoneCard(exercises: controller.exercises.count,
                                        sets: controller.session.completedSetCount) { confirmFinish = true }
                    }
                    PillButton(Text("Add exercise"), style: .secondary) { showsAdd = true }
                    if controller.exercises.count > 1 {
                        Button {
                            showsReorder = true
                        } label: {
                            Text("Reorder exercises")
                                .font(.ryft(.callout))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minHitTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Color.clear.frame(height: 1).id(Self.endAnchor)
                }
                .padding(.horizontal, LiveSessionSpec.sidePadding)
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
        // An inset, not an overlay: while the toast shows, the last set row scrolls clear of it.
        .safeAreaInset(edge: .bottom, spacing: 0) { SessionToastOverlay(controller: controller) }
    }

    /// What both layouts share and only this view can open.
    private var actions: SessionActions {
        SessionActions(addExercise: { showsAdd = true }, reorder: { showsReorder = true }, plates: showPlates,
                       history: showHistory, userScrolled: userScrolled, finish: { confirmFinish = true })
    }

    private func showPlates(for ex: LocalSessionExercise) {
        let kg = ex.orderedSets.last { $0.weightKg != nil }?.weightKg ?? ex.targetKg ?? 60
        plates = PlateRequest(kg: kg, fromKeypad: false)
    }

    private func showHistory(of ex: LocalSessionExercise) {
        historyFor = ExerciseRef(id: ex.exerciseId, name: ex.name)
    }

    /// Consecutive exercises in one superset group share a bracket.
    private var groups: [[LocalSessionExercise]] { controller.exerciseGroups }

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
                             onPlates: { showPlates(for: ex) }, onHistory: { showHistory(of: ex) })
            }
        }
        .transition(.opacity)
        .id(ex.id)
    }

    // MARK: jump to next

    private static let endAnchor = "session.end"

    /// Hidden, running or over: the bar appears, changes or goes (not every ±15 s). Once every set is done a running
    /// rest is hidden (nothing comes next; the all-done card does); "Rest over" still shows until dismissed (ui.md §7).
    /// Always hidden in Focused: `RestPill` is its timer.
    private var restBarState: Int {
        guard controller.layout == .list else { return 0 }
        return switch controller.rest.phase {
        case .idle: 0
        case .running: controller.isAllDone ? 0 : 1
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
private struct ManualScrollReporter: ViewModifier {
    var onScroll: () -> Void

    func body(content: Content) -> some View {
        content.onScrollPhaseChange { old, new in
            // The finger on the list, and again when it lets go or the list coasts to a stop.
            if new == .interacting || new == .decelerating || old == .interacting || old == .decelerating {
                onScroll()
            }
        }
    }
}

#Preview("Live session · List") {
    SessionView(controller: TrainPreview.liveController())
        .previewEnvironment()
}

/// `b-02`: List's first exercise under way, a rest running.
#Preview("Live session · List draft") {
    SessionView(controller: FocusedPreview.controller(.draftList))
        .previewEnvironment()
}

/// The buttons on a row of their own, the title under them; the table's column titles on one line.
#Preview("Live session · List, AX3") {
    SessionView(controller: TrainPreview.liveController())
        .previewEnvironment()
        .dynamicTypeSize(.accessibility3)
}

#Preview("Live session · List, keypad") {
    let c = TrainPreview.liveController()
    c.edit(c.exercises[0].orderedSets[2], .kg)
    return SessionView(controller: c).previewEnvironment()
}
