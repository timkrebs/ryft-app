import SwiftUI

/// The per-exercise sheets of the Focused layout. `FocusedSessionView` holds them above the pages, by row id: pages lose
/// their state on a round trip, and a page can move under an opening sheet (architecture.md §8).
enum ExerciseSheet: Identifiable {
    case replace(UUID), targets(UUID), notes(UUID)

    var id: String {
        switch self {
        case let .replace(id): return "replace.\(id)"
        case let .targets(id): return "targets.\(id)"
        case let .notes(id): return "notes.\(id)"
        }
    }
}

/// One exercise on the Focused layout's page: title, chips, notes, warm-ups, the set table, Add set, "All sets done", last
/// time (design.md §2.3 to §2.6). Holds no sheets; what it opens goes through its closures.
struct ExercisePage: View {
    var controller: SessionController
    let exercise: LocalSessionExercise
    let columns: SetTableColumns
    var onSheet: (ExerciseSheet) -> Void
    var onRemove: () -> Void
    var onPlates: () -> Void
    var onHistory: () -> Void
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.sessionVoiceOverFocus) private var voiceOverFocus

    /// The footer's scroll anchor.
    private static let allDoneAnchor = "session.page.allDone"

    private var motion: Animation? { Theme.Motion.respecting(reduceMotion) }
    private var warmups: [LocalSet] { exercise.orderedSets.filter(\.isWarmup) }
    private var working: [LocalSet] { exercise.orderedSets.filter { !$0.isWarmup } }
    private var isExpanded: Bool { !controller.isFolded(exercise) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleRow
                    supersetLine
                    chips
                    notesLine
                    if !warmups.isEmpty {
                        warmupPill
                            .padding(.top, 2)
                            .padding(.bottom, 8)
                    }
                    if !exercise.sets.isEmpty { table }
                    addSet
                    // On every page: the user can be on any of them when the last set is checked (L1: stay).
                    if controller.isAllDone {
                        AllSetsDoneCard(exercises: controller.exercises.count, sets: controller.session.completedSetCount,
                                        onFinish: onFinish)
                            .padding(.top, 8)
                            .id(Self.allDoneAnchor)
                    }
                    if exercise.lastTime.contains(where: { !$0.isWarmup }) {
                        LastTimeCard(sets: exercise.lastTime, loadType: exercise.loadType, columns: columns,
                                     column: controller.column(for: exercise), onTap: onHistory)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, columns.padding)
                .padding(.bottom, 24)
                .animation(motion, value: isExpanded)
            }
            .scrollDismissesKeyboard(.never)
            .onChange(of: controller.focus) { _, focus in
                guard let focus, exercise.sets.contains(where: { $0.id == focus.setID }) else { return }
                withAnimation(motion) { proxy.scrollTo(focus.setID, anchor: .center) }
            }
            .onChange(of: controller.advance?.id) { _, _ in
                guard case .allDone = controller.advance?.step, exercise.id == controller.pageExerciseID else { return }
                withAnimation(motion) { proxy.scrollTo(Self.allDoneAnchor, anchor: .bottom) }
            }
            .onAppear {
                if let focus = controller.focus, exercise.sets.contains(where: { $0.id == focus.setID }) {
                    proxy.scrollTo(focus.setID, anchor: .center)
                }
            }
        }
    }

    // MARK: title, chips, notes

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onHistory) {
                HStack(spacing: 6) {
                    Text(exercise.name)
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { menuItems }
            .accessibilityLabel(Text(
                "\(exercise.name), history",
                comment: "VoiceOver: the exercise's title on its page in a workout, which opens its history."
            ))
            .accessibilityAddTraits(.isHeader)
            // The toast's Undo, reachable from the page too while it lasts (ui.md §4).
            .accessibilityActions {
                if let undo = controller.undo, undo.touches(exercise.id) {
                    Button(String(localized: "Undo", comment: "Toast button that takes back the last change, e.g. a replaced exercise.")) {
                        SessionToastOverlay.undo(undo, in: controller)
                    }
                }
            }
            .modifier(PageTitleFocus(exerciseID: exercise.id, focus: voiceOverFocus))
            .accessibilityIdentifier("session.page.title")
            Spacer(minLength: 4)
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Options for \(exercise.name)"))
        }
    }

    private var menuItems: some View {
        ExerciseMenuItems(controller: controller, exercise: exercise,
                          onReplace: { onSheet(.replace(exercise.id)) }, onTargets: { onSheet(.targets(exercise.id)) },
                          onNotes: { onSheet(.notes(exercise.id)) }, onPlates: onPlates, onHistory: onHistory, onRemove: onRemove,
                          onAddWarmup: warmups.isEmpty ? { controller.addWarmup(to: exercise) } : nil)
    }

    @ViewBuilder
    private var supersetLine: some View {
        let partners = controller.supersetPartners(of: exercise).map(\.name)
        if !partners.isEmpty {
            Label("Superset with \(partners.formatted())", systemImage: "link")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 20)
        }
    }

    /// In a row that scrolls sideways when it doesn't fit; stacked at accessibility sizes (design.md §5.1).
    @ViewBuilder
    private var chips: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) { chipItems }
                .padding(.bottom, 8)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { chipItems }
                    .padding(.leading, columns.padding)
                    // Past the fade, so the last chip ends clear of it.
                    .padding(.trailing, columns.padding + 16)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .mask {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                }
            }
            .padding(.horizontal, -columns.padding)
        }
    }

    @ViewBuilder
    private var chipItems: some View {
        Button {
            controller.beginReplace()
            onSheet(.replace(exercise.id))
        } label: {
            SessionChip(text: exercise.kind.title, leading: "arrow.triangle.2.circlepath",
                        isEnabled: controller.canReplace(exercise))
        }
        .buttonStyle(.plain)
        .disabled(!controller.canReplace(exercise))
        .accessibilityLabel(Text("Replace exercise, \(exercise.kind.title)", comment: "VoiceOver: the equipment chip on an exercise's page. 1: the equipment."))
        .accessibilityHint(Self.sheetHint)
        .accessibilityIdentifier("session.chip.replace")

        Button {
            controller.focus = nil
            onSheet(.targets(exercise.id))
        } label: {
            SessionChip(text: exercise.targetText ?? String(localized: "Set target", comment: "The target chip of an exercise without a target, in a workout."),
                        trailing: "pencil")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Edit targets, \(exercise.targetText ?? String(localized: "Set target"))",
                                 comment: "VoiceOver: the target chip on an exercise's page. 1: the target, e.g. 3 × 8–10 @ 30 kg."))
        .accessibilityHint(Self.sheetHint)
        .accessibilityIdentifier("session.chip.targets")

        Menu {
            RestChoices(controller: controller, exercise: exercise)
        } label: {
            SessionChip(text: String(localized: "Rest \(Fmt.clock(TimeInterval(exercise.restSec)))"), leading: "timer", trailing: "pencil")
        }
        .accessibilityLabel(Text(
            "Rest, \(Self.spokenDuration(exercise.restSec))",
            comment: "VoiceOver: the rest chip on an exercise's page. 1: e.g. 1 minute, 15 seconds."
        ))
        .accessibilityIdentifier("session.chip.rest")
    }

    private static let sheetHint = Text("Opens a sheet", comment: "VoiceOver hint on the chips of an exercise's page in a workout.")

    private static func spokenDuration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }

    @ViewBuilder
    private var notesLine: some View {
        if !exercise.notes.isEmpty {
            Button {
                controller.focus = nil
                onSheet(.notes(exercise.id))
            } label: {
                Label(exercise.notes, systemImage: "note.text")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Notes: \(exercise.notes)", comment: "VoiceOver: an exercise's notes in a workout. 1: the notes."))
            .accessibilityHint(Text("Edits the notes", comment: "VoiceOver hint on an exercise's notes in a workout."))
        }
    }

    // MARK: warm-ups

    private var warmupPill: some View {
        Button {
            withAnimation(motion) { controller.setWarmups(expanded: !isExpanded, for: exercise) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "flame")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.warning)
                warmupTitle
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(warmupsDone
            ? Text("\(warmupTitleText), done", comment: "VoiceOver: the warm-up pill once every warm-up is checked. 1: e.g. 2 warm-up sets.")
            : Text(warmupTitleText))
        .accessibilityValue(isExpanded ? Text("expanded", comment: "VoiceOver: the warm-up group is open.")
                                       : Text("collapsed", comment: "VoiceOver: the warm-up group is folded."))
        .accessibilityHint(Text("Shows or hides the warm-up sets", comment: "VoiceOver hint on the warm-up pill."))
        .accessibilityIdentifier("session.warmups")
    }

    private var warmupsDone: Bool { warmups.allSatisfy(\.isCompleted) }

    private var warmupTitleText: String {
        warmups.count == 1
            ? String(localized: "1 warm-up set", comment: "The warm-up pill on an exercise's page, one set.")
            : String(localized: "\(warmups.count) warm-up sets", comment: "The warm-up pill on an exercise's page.")
    }

    private var warmupTitle: Text { Text(verbatim: warmupTitleText) }

    private var addWarmup: some View {
        Button {
            controller.addWarmup(to: exercise)
        } label: {
            Label(String(localized: "Add warm-up set", comment: "Exercise menu in a workout: adds a warm-up set to this exercise."),
                  systemImage: "plus")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: the table

    private var table: some View {
        VStack(alignment: .leading, spacing: 4) {
            SetTableHeader(loadType: exercise.loadType, columns: columns, column: controller.column(for: exercise),
                           onCycle: controller.cyclesColumn(of: exercise) ? { controller.cycleColumn(of: exercise) } : nil)
            let active = controller.activeSet(in: exercise)?.id
            if isExpanded, !warmups.isEmpty {
                let warmups = warmups
                ForEach(Array(warmups.enumerated()), id: \.element.id) { i, set in
                    row(set, number: i + 1, count: warmups.count, active: active)
                }
                addWarmup
            }
            let working = working
            ForEach(Array(working.enumerated()), id: \.element.id) { i, set in
                row(set, number: i + 1, count: working.count, active: active)
            }
        }
    }

    private func row(_ set: LocalSet, number: Int, count: Int, active: UUID?) -> some View {
        SetRow(controller: controller, set: set, exercise: exercise, number: number, count: count,
               swipeToDelete: false, columns: columns,
               rowState: FocusedRowState(isCompleted: set.isCompleted, isActive: set.id == active))
            .id(set.id) // scroll anchor for the keypad
            .currentSetHighlight(set.id == active, setID: set.id)
    }

    private var addSet: some View {
        Button {
            controller.addSet(to: exercise)
        } label: {
            Label("Add set", systemImage: "plus")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The set table's column titles. Labels stop growing at XXXL: a row is read by VoiceOver as one element, so they are
/// hidden from it, and they share the rows' fixed columns. With `onCycle` the fourth one is a button, 44 pt high, so the
/// row grows upward and the labels stay on the table.
struct SetTableHeader: View {
    let loadType: LoadType
    let columns: SetTableColumns
    let column: SetColumn
    /// The header's tap. `nil`: plain text, as in the last-time card and for time and distance.
    var onCycle: (() -> Void)?

    private var usesWeight: Bool { loadType == .weight || loadType == .bodyweight }

    var body: some View {
        HStack(alignment: .bottom, spacing: columns.gap) {
            Group {
                Text(verbatim: "#").frame(width: columns.number, height: 24)
                if usesWeight {
                    Group {
                        if loadType == .bodyweight {
                            Text("+kg", comment: "Set table's column in a workout: load added to bodyweight. Shown uppercase.")
                        } else {
                            Text("kg")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
                }
                Text("Reps").frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
            }
            .accessibilityHidden(true)
            fourth
            Color.clear.frame(width: columns.check, height: 1).accessibilityHidden(true)
        }
        .font(.ryft(.label))
        .textCase(.uppercase)
        .tracking(columns.headerTracking)
        .foregroundStyle(Theme.textTertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private var fourth: some View {
        if let onCycle {
            Button(action: onCycle) {
                Text(verbatim: column.title)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: columns.fourth, height: 24)
                    .frame(height: 44, alignment: .bottom)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Table column",
                                     comment: "VoiceOver: the set table's fourth column header in a workout, a button. Its value says what the column shows."))
            .accessibilityValue(Text(verbatim: column.spokenTitle))
            // Voice Control goes by what's on screen, and the label doesn't say it: "Tap E1RM".
            .accessibilityInputLabels([Text(verbatim: column.title), Text(verbatim: column.spokenTitle), Text("Table column")])
            .accessibilityHint(Text("Switches between estimated 1RM, estimated 10RM and RPE",
                                    comment: "VoiceOver hint on the set table's fourth column header in a workout."))
            .accessibilityIdentifier("session.column")
        } else {
            Text(verbatim: column.title)
                .frame(width: columns.fourth, height: 24)
                .accessibilityHidden(true)
        }
    }
}

/// What the last session did, as a table on the set table's columns (design.md §2.6, L7): the heading has the date only,
/// since the session's title isn't on the wire. Hidden by its caller without a working set; the whole card opens history.
struct LastTimeCard: View {
    /// `exercise.lastTime`, warm-ups included: they aren't listed.
    let sets: [SessionSet]
    let loadType: LoadType
    let columns: SetTableColumns
    /// The table's choice, so the card reads straight down from it.
    let column: SetColumn
    var onTap: () -> Void

    private static let shown = 6
    private var working: [SessionSet] { sets.filter { !$0.isWarmup } }
    private var listed: [SessionSet] { Array(working.prefix(Self.shown)) }
    /// The fourth column, top to bottom: what last time logged, there is no ghost here.
    var fourth: [String] { listed.map { column.text(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe) } }
    private var usesWeight: Bool { loadType == .weight || loadType == .bodyweight }
    private var date: Date? { working.compactMap(\.completedAt).max() }

    var body: some View {
        Button(action: onTap) {
            // The rows stay on the table's grid, so the card has no side padding of its own: the number column is its margin.
            VStack(alignment: .leading, spacing: 0) {
                heading
                    .font(.ryft(.label))
                    .textCase(.uppercase)
                    .tracking(columns.headerTracking)
                    .foregroundStyle(Theme.textTertiary)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                SetTableHeader(loadType: loadType, columns: columns, column: column)
                let fourth = fourth
                ForEach(Array(listed.enumerated()), id: \.element.id) { i, set in
                    row(set, number: i + 1, fourth: fourth[i])
                }
                if working.count > Self.shown {
                    Text(moreText)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 28)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(spoken))
        .accessibilityHint(Text("Opens history", comment: "VoiceOver hint on the last-time card of an exercise's page."))
        .accessibilityIdentifier("session.lastTime")
    }

    @ViewBuilder
    private var heading: some View {
        if let date {
            Text("Last time · \(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))",
                 comment: "Heading of the last-time card in a workout. 1: the date, e.g. Tue 3 Nov. Shown uppercase.")
        } else {
            Text("Last time", comment: "Heading of the last-time card in a workout, without a date. Shown uppercase.")
        }
    }

    private func row(_ set: SessionSet, number: Int, fourth: String) -> some View {
        let stored = SetStoredValue(reps: set.reps, durationSec: set.durationSec, distanceM: set.distanceM)
        return HStack(spacing: columns.gap) {
            Text(verbatim: "\(number)").frame(width: columns.number)
            if usesWeight { Text(set.weightKg.map(Fmt.kgNumber) ?? Fmt.placeholder).frame(maxWidth: .infinity) }
            Text(stored?.text ?? set.reps.map(String.init) ?? Fmt.placeholder).frame(maxWidth: .infinity)
            Text(verbatim: fourth).frame(width: columns.fourth)
            Color.clear.frame(width: columns.check, height: 1)
        }
        .font(.ryftNumber(size: 17))
        .monospacedDigit()
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(height: 36)
    }

    private var moreText: String {
        String(localized: "+\(working.count - Self.shown) more",
               comment: "Train session, an exercise's Last time line: sets not listed after the first five.")
    }

    /// "Last time, Tue 3 November: set 1, 10 reps at 75 kilograms, estimated one-rep max 100 kilograms; set 2, …".
    var spoken: String {
        let rows = listed.enumerated().map { i, set in
            String(
                localized: "set \(i + 1), \(spoken(set))",
                comment: "VoiceOver: one row of the last-time card. 1: its number, 2: e.g. 10 reps at 75 kilograms."
            )
        }
        var list = rows.joined(separator: "; ")
        if working.count > Self.shown { list += "; " + moreText }
        guard let date else { return String(localized: "Last time: \(list)") }
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
        return String(localized: "Last time, \(day): \(list)", comment: "VoiceOver: the last-time card. 1: the date, 2: its sets.")
    }

    /// The row's values, then what its fourth column shows.
    private func spoken(_ set: SessionSet) -> String {
        let values = Self.spokenValues(set)
        guard let fourth = column.spoken(weightKg: set.weightKg, reps: set.reps, rpe: set.rpe) else { return values }
        return "\(values), \(fourth)"
    }

    private static func spokenValues(_ set: SessionSet) -> String {
        if let stored = SetStoredValue(reps: set.reps, durationSec: set.durationSec, distanceM: set.distanceM) { return stored.spoken }
        switch (set.reps, set.weightKg) {
        case let (r?, k?): return String(localized: "\(r) reps at \(Fmt.kgNumber(k)) kilograms")
        case let (r?, nil): return String(localized: "\(r) reps")
        case let (nil, k?): return String(localized: "\(Fmt.kgNumber(k)) kilograms")
        default: return Fmt.placeholder
        }
    }
}

/// A chip of the page's chip row: 32 pt high, 44 pt to touch. Never accent: three of them would outweigh the check.
struct SessionChip: View {
    let text: String
    var leading: String?
    var trailing: String?
    var isEnabled = true

    var body: some View {
        HStack(spacing: 6) {
            if let leading { glyph(leading) }
            Text(text)
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let trailing { glyph(trailing) }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
    }
}

/// The strip's double tap lands here.
private struct PageTitleFocus: ViewModifier {
    let exerciseID: UUID
    let focus: AccessibilityFocusState<UUID?>.Binding?

    func body(content: Content) -> some View {
        // The environment is the same for every page, so this never switches a title's identity.
        if let focus {
            content.accessibilityFocused(focus, equals: exerciseID)
        } else {
            content
        }
    }
}

@MainActor
private func page(_ scenario: FocusedPreview.Scenario) -> some View {
    let c = FocusedPreview.controller(scenario)
    return ExercisePage(controller: c, exercise: c.pageExercise ?? c.exercises[0], columns: .regular, onSheet: { _ in }, onRemove: {},
                        onPlates: {}, onHistory: {}, onFinish: {})
        .background(Theme.background)
}

#Preview("Page · dark") {
    page(.midSession).previewEnvironment()
}

#Preview("Page · light") {
    page(.midSession).previewEnvironment(scheme: .light)
}

#Preview("Page · a tapped row, dark") {
    page(.tappedRow).previewEnvironment()
}

#Preview("Page · a tapped row, light") {
    page(.tappedRow).previewEnvironment(scheme: .light)
}

#Preview("Page · no history, dark") {
    page(.oneExercise).previewEnvironment()
}

#Preview("Page · no history, light") {
    page(.oneExercise).previewEnvironment(scheme: .light)
}

#Preview("Page · all done") {
    page(.allDone).previewEnvironment()
}

#Preview("Page · warm-ups folded") {
    page(.warmups).previewEnvironment()
}

#Preview("Page · warm-ups open, light") {
    page(.warmupsOpen).previewEnvironment(scheme: .light)
}

#Preview("Page · bodyweight, dark") {
    page(.bodyweight).previewEnvironment()
}

#Preview("Page · bodyweight, light") {
    page(.bodyweight).previewEnvironment(scheme: .light)
}

#Preview("Page · time and distance, dark") {
    page(.timeAndDistance).previewEnvironment()
}

#Preview("Page · time and distance, light") {
    page(.timeAndDistance).previewEnvironment(scheme: .light)
}

#Preview("Page · AX3") {
    page(.midSession).previewEnvironment().dynamicTypeSize(.accessibility3)
}

#Preview("Last time · dark and light", traits: .sizeThatFitsLayout) {
    SchemePair {
        LastTimeCard(sets: FocusedPreview.lastTime, loadType: .weight, columns: .regular, column: .rpe, onTap: {})
    }
}

#Preview("Last time · over six sets, no date", traits: .sizeThatFitsLayout) {
    SchemePair {
        LastTimeCard(sets: (0..<8).map { SessionSet(setIndex: $0, reps: 12 - $0, weightKg: 75) }, loadType: .weight, columns: .compact,
                     column: .e1rm, onTap: {})
    }
}
