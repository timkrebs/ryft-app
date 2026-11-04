import SwiftUI

/// The Focused set table's columns at a width (design.md §2.5): the row, its header and the last-time card share them,
/// so a column reads straight down the page. The two fields take what's left, equally.
struct SetTableColumns: Equatable {
    let number: CGFloat
    let fourth: CGFloat
    let check: CGFloat
    let gap: CGFloat
    /// The kg and reps numerals.
    let numeral: CGFloat
    /// Page padding, into which the number's 44 pt hit area reaches.
    let padding: CGFloat
    let headerTracking: CGFloat

    /// 390 pt class.
    static let regular = SetTableColumns(number: 36, fourth: 56, check: 56, gap: 6, numeral: 22, padding: 16, headerTracking: 2)
    /// 320 pt (Display Zoom).
    static let compact = SetTableColumns(number: 28, fourth: 48, check: 56, gap: 4, numeral: 20, padding: 12, headerTracking: 1)

    static func fitting(width: CGFloat) -> SetTableColumns {
        width > 0 && width < 360 ? .compact : .regular
    }

    /// The number's hit area, 44 x 56, in its own coordinates: left into the page padding, then right into the gap.
    var numberHitArea: CGRect {
        let left = min(padding, 44 - number)
        return CGRect(x: -left, y: 0, width: 44, height: 56)
    }
}

/// A Focused row's look (design.md §3.1). Derived from the set and the page's active row, never stored.
enum FocusedRowState: Equatable {
    case active, done, upcoming

    init(isCompleted: Bool, isActive: Bool) {
        self = isCompleted ? .done : isActive ? .active : .upcoming
    }
}

/// One set: number (tap: warm-up), kg, reps, RPE, check. 56 pt tall, large
/// monospaced numbers; empty fields show last time / the target ghosted.
struct SetRow: View {
    var controller: SessionController
    let set: LocalSet
    let exercise: LocalSessionExercise
    let number: Int
    let count: Int
    /// Off in Focused: inside the pager the row's gesture gets no drag, and one that wins kills page swipes (L16). The
    /// context menu and the VoiceOver action stay.
    var swipeToDelete = true
    /// Focused's table; nil: the list's card.
    var columns: SetTableColumns?
    /// Focused's row states; nil: the list's card.
    var rowState: FocusedRowState?

    @State private var confirmDelete = false
    /// How far the row is swiped open (0 or less); "Delete" shows in the space it leaves.
    @State private var swipe: CGFloat = 0
    @State private var swipeAxis: Axis?
    @State private var swipeStart: CGFloat = 0
    /// When a sideways drag last ended: the tap a button sees at its end isn't one.
    @State private var swipeEndedAt: Date = .distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private static let revealWidth: CGFloat = 88

    private var ghost: (reps: Int?, kg: Double?) { controller.ghost(for: set, in: exercise) }
    private var usesWeight: Bool { exercise.loadType == .weight || exercise.loadType == .bodyweight }

    var body: some View {
        row
            .offset(x: swipe)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if swipe < 0 { deleteButton.frame(width: -swipe) }
            }
            .clipped()
            // Unchecked rows only; a vertical drag stays the list's scroll.
            .simultaneousGesture(swipeGesture, including: swipeToDelete && !set.isCompleted ? .all : .subviews)
            .onChange(of: set.isCompleted) { _, done in if done { swipe = 0 } }
            .contextMenu {
                // Focused's column can be an estimate, so RPE needs a way in from any of them (design.md §7).
                if columns != nil {
                    Button("Edit RPE", systemImage: "pencil") { controller.edit(set, .rpe) }
                }
                Button(set.isWarmup ? "Mark as working set" : "Mark as warm-up", systemImage: "flame") {
                    controller.toggleWarmup(set)
                }
                Button("Delete set", systemImage: "trash", role: .destructive) { requestDelete() }
            }
            .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete set", role: .destructive) { controller.delete(set, from: exercise) }
            }
            // VoiceOver: one element per set with actions.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityAddTraits(set.isCompleted ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { check() }
            .accessibilityAction(named: Text(set.isCompleted ? "Mark not done" : "Check off")) { check() }
            .accessibilityAction(named: Text("Edit weight")) { controller.edit(set, .kg) }
            .modifier(EditRepsAction(offered: storedValue == nil) { controller.edit(set, .reps) })
            .accessibilityAction(named: Text("Edit RPE")) { controller.edit(set, .rpe) }
            .accessibilityAction(named: Text(set.isWarmup ? "Mark as working set" : "Mark as warm-up")) {
                controller.toggleWarmup(set)
            }
            .accessibilityAction(named: Text("Delete set")) { requestDelete() }
            .accessibilityIdentifier("\(isFocusedWarmup ? "warmup" : "set").\(exercise.position).\(number)")
    }

    private var row: some View {
        HStack(spacing: columns?.gap ?? 6) {
            Button {
                tap { controller.toggleWarmup(set) }
            } label: {
                Text(set.isWarmup ? "W" : "\(number)")
                    .font(.ryftNumber(size: 17))
                    .foregroundStyle(numberColor)
                    .frame(width: columns?.number ?? 40, height: 56)
                    .background { if rowState == .active { activePill } }
                    .contentShape(columns.map { Path($0.numberHitArea) } ?? Path(CGRect(x: 0, y: 0, width: 40, height: 56)))
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            if usesWeight {
                field(.kg, value: set.weightKg.map(Fmt.kgNumber), ghost: ghost.kg.map(Fmt.kgNumber))
            }
            if let stored = storedValue {
                readOnlyField(stored)
            } else {
                field(.reps, value: set.reps.map(String.init), ghost: ghost.reps.map(String.init))
            }
            if controller.column(for: exercise) == .rpe {
                field(.rpe, value: set.rpe.map(Fmt.kgNumber), ghost: nil)
                    .frame(minWidth: columns?.fourth, maxWidth: columns?.fourth ?? 64)
            } else {
                estimateCell
            }

            Button {
                tap { check() }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(checkGlyph)
                    .frame(width: 56, height: 56)
                    .background(checkFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        if rowState == .upcoming {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.surfaceRaised, lineWidth: 1)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityHidden(true)
        }
        .frame(minHeight: 56)
        .background(rowState == nil && set.isCompleted ? Theme.accent.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Focused's states (design.md §2.5, §2.8)

    private var numberColor: Color {
        if set.isWarmup { return Theme.warning }
        return rowState == .active ? Theme.textPrimary : Theme.textSecondary
    }

    /// The active row's fields and `#`. In light, `surfaceRaised` sits at 1.01:1 on the row's tint and `surface` at 1.28:1,
    /// about dark's step, and it keeps the ghost above 4.5:1. List has no row state and stays as it is.
    private var raisedFill: Color {
        rowState == .active && colorScheme == .light ? Theme.surface : Theme.surfaceRaised
    }

    /// The raised `#` of the active row, with its dot.
    private var activePill: some View {
        Capsule()
            .fill(raisedFill)
            .frame(width: min(columns?.number ?? 32, 32), height: min(columns?.number ?? 32, 32))
            .overlay(alignment: .topTrailing) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
            }
    }

    private var checkGlyph: Color {
        switch rowState {
        case .active: Theme.onAccent
        case .done: Theme.textSecondary
        case .upcoming: Theme.textTertiary
        case nil: set.isCompleted ? Theme.onAccent : Theme.textTertiary
        }
    }

    private var checkFill: Color {
        switch rowState {
        case .active: Theme.accent
        case .done, .upcoming: .clear
        case nil: set.isCompleted ? Theme.accent : Theme.surfaceRaised
        }
    }

    /// Only the active row's fields are raised, and RPE stays quieter: it is optional.
    private func fieldOpacity(_ f: SetFocus.Field, focused: Bool) -> Double {
        guard !focused else { return 1 }
        switch rowState {
        case .active: return f == .rpe ? 0.55 : 1
        case .done, .upcoming: return 0
        case nil: return 0.55
        }
    }

    /// A ghost reads as what you'll do, in a colour that holds 4.5:1; only an empty field is quieter than that. A done
    /// value is grey, told apart from a ghost by the check column.
    private func valueColor(hasValue: Bool, hasGhost: Bool) -> Color {
        switch rowState {
        case nil: hasValue ? Theme.textPrimary : Theme.textTertiary.opacity(0.7)
        case .done: hasValue ? Theme.textSecondary : Theme.textTertiary
        case .active, .upcoming: hasValue ? Theme.textPrimary : hasGhost ? Theme.textSecondary : Theme.textTertiary
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            requestDelete()
        } label: {
            Label("Delete", systemImage: "trash")
                .labelStyle(.iconOnly)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.alert, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.leading, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("set.delete")
    }

    /// Starts only once the drag is clearly sideways (1.5 : 1), so the list's vertical scroll wins otherwise.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let dx = value.translation.width, dy = value.translation.height
                if swipeAxis == nil {
                    swipeAxis = abs(dx) > abs(dy) * 1.5 ? .horizontal : .vertical
                    swipeStart = swipe
                }
                guard swipeAxis == .horizontal else { return }
                swipe = min(0, max(-Self.revealWidth * 1.3, swipeStart + dx))
            }
            .onEnded { _ in
                defer { swipeAxis = nil }
                if swipeAxis == .horizontal { swipeEndedAt = .now }
                guard swipeAxis == .horizontal else { return }
                withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                    swipe = swipe < -Self.revealWidth / 2 ? -Self.revealWidth : 0
                }
            }
    }

    /// The ✓ and VoiceOver's check, one rule: a Focused row follows L17 (L23, L24), List toggles.
    private func check() {
        if rowState != nil {
            controller.checkRow(set, in: exercise)
        } else {
            controller.toggleCheck(set, in: exercise)
        }
    }

    /// A row button's action, unless the touch was a swipe; on an open row a tap only closes it.
    private func tap(_ action: () -> Void) {
        guard swipeAxis != .horizontal, Date.now.timeIntervalSince(swipeEndedAt) > 0.35 else { return }
        if swipe < 0 {
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) { swipe = 0 }
            return
        }
        action()
    }

    /// Focused numbers warm-ups on their own: "1" is a warm-up and a working set, so they need telling apart.
    private var isFocusedWarmup: Bool { columns != nil && set.isWarmup }

    private var deleteTitle: Text {
        isFocusedWarmup ? Text("Delete \(String(localized: "warm-up"))?") : Text("Delete set \(number)?")
    }

    /// A set with values (or checked) asks first; an empty one goes at once.
    private func requestDelete() {
        withAnimation(reduceMotion ? nil : Theme.Motion.quick) { swipe = 0 }
        if set.hasValues || set.isCompleted {
            confirmDelete = true
        } else {
            controller.delete(set, from: exercise)
        }
    }

    /// "Set 2 of 5, 8 reps at 80 kilograms, completed".
    private var accessibilityText: String {
        var parts = [String(localized: "Set \(number) of \(count)")]
        if set.isWarmup { parts.append(String(localized: "warm-up")) }
        let reps = Self.spokenReps(set.reps, ghost: ghost.reps, stored: storedValue), kg = set.weightKg ?? ghost.kg
        var values: String?
        switch (reps, kg) {
        case let (r?, k?): values = String(localized: "\(r) reps at \(Fmt.kgNumber(k)) kilograms")
        case let (r?, nil): values = String(localized: "\(r) reps")
        case let (nil, k?): values = String(localized: "\(Fmt.kgNumber(k)) kilograms")
        default: break
        }
        // Focused's ghost looks real, so it says what it is.
        let planned = rowState != nil && !set.isCompleted && set.reps == nil && set.weightKg == nil
        if let text = values {
            parts.append(planned
                ? String(localized: "planned \(text)",
                         comment: "VoiceOver: a set's prefilled values, not logged yet. 1: e.g. 10 reps at 75 kilograms.")
                : text)
        } else if rowState != nil, storedValue == nil, !showsBodyweightGlyph {
            parts.append(String(localized: "empty"))
        }
        if showsBodyweightGlyph { parts.append(String(localized: "bodyweight", comment: "VoiceOver: a set with no added load, in a workout.")) }
        if let stored = storedValue { parts.append(stored.spoken) }
        if let estimate = controller.columnSpoken(of: set, in: exercise) { parts.append(estimate) }
        if let rpe = set.rpe { parts.append(String(localized: "RPE \(Fmt.kgNumber(rpe))")) }
        parts.append(set.isCompleted ? String(localized: "completed") : String(localized: "not done"))
        return parts.joined(separator: ", ")
    }

    /// A row with a stored time or distance has no reps to suggest: VoiceOver reads what the row shows.
    static func spokenReps(_ reps: Int?, ghost: Int?, stored: SetStoredValue?) -> Int? {
        reps ?? (stored == nil ? ghost : nil)
    }

    /// Focused: a time or distance this set got from an import or another client. There is no entry for them (L20), so
    /// the field reads the stored value and isn't a button (design.md §3.2).
    private var storedValue: SetStoredValue? {
        columns == nil ? nil : SetStoredValue(reps: set.reps, durationSec: set.durationSec, distanceM: set.distanceM)
    }

    /// Focused: a bodyweight set with no added load and no ghost says so instead of a dash.
    private var showsBodyweightGlyph: Bool {
        columns != nil && exercise.loadType == .bodyweight && set.weightKg == nil && ghost.kg == nil
    }

    private func readOnlyField(_ stored: SetStoredValue) -> some View {
        Text(stored.text)
            .font(.ryftNumber(size: columns?.numeral ?? 22))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(rowState == .active ? Theme.textPrimary : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 48)
    }

    /// The estimate: read-only, grey on every row (brief, PR 1), the dash quieter still (design.md §2.8).
    private var estimateCell: some View {
        let text = controller.columnText(of: set, in: exercise)
        return Text(verbatim: text)
            .font(.ryftNumber(size: numeralSize(.rpe)))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(text == Fmt.placeholder ? Theme.textTertiary : Theme.textSecondary)
            .frame(width: columns?.fourth, height: 48)
    }

    /// Focused's RPE is quieter than kg and reps, and empty when unset: a table without RPE stays calm (design.md §2.5).
    private func emptyText(_ f: SetFocus.Field) -> String {
        columns != nil && f == .rpe ? "" : Fmt.placeholder
    }

    private func numeralSize(_ f: SetFocus.Field) -> CGFloat {
        guard let columns else { return 22 }
        return f == .rpe ? 17 : columns.numeral
    }

    private func field(_ f: SetFocus.Field, value: String?, ghost: String?) -> some View {
        let focused = controller.focus == SetFocus(setID: set.id, field: f)
        let shown = focused ? (controller.buffer.isEmpty ? nil : controller.displayBuffer) : value
        return Button {
            tap {
                // An upcoming row's first tap makes it active. With the keypad up it moves there, as in List.
                if rowState == .upcoming, controller.focus == nil {
                    controller.activate(set)
                } else {
                    controller.edit(set, f)
                }
            }
        } label: {
            Group {
                if f == .kg, showsBodyweightGlyph, shown == nil {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text(shown ?? ghost ?? emptyText(f))
                        .font(.ryftNumber(size: numeralSize(f)))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(columns == nil ? 0.6 : 0.75)
                        .foregroundStyle(valueColor(hasValue: shown != nil, hasGhost: ghost != nil))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(raisedFill.opacity(fieldOpacity(f, focused: focused)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? Theme.accent : .clear, lineWidth: 2))
            // A row with no field chrome still takes the whole field's tap.
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The set row's "Edit reps". A modifier rather than `accessibilityActions`, so the actions keep their order and List's
/// row, where it is always offered, stays as it was.
private struct EditRepsAction: ViewModifier {
    let offered: Bool
    let edit: () -> Void

    func body(content: Content) -> some View {
        if offered {
            content.accessibilityAction(named: Text("Edit reps"), edit)
        } else {
            content
        }
    }
}

/// A time or distance in a set's reps slot, read-only: what the Focused table and its last-time card show for a set
/// that has one and no reps (design.md §3.2). Nil for a set with reps, or with neither.
struct SetStoredValue: Equatable {
    let text: String
    let spoken: String

    init?(reps: Int?, durationSec: Int?, distanceM: Double?) {
        guard reps == nil else { return nil }
        if let durationSec {
            text = Fmt.clock(TimeInterval(durationSec))
            spoken = String(localized: "time \(text)", comment: "VoiceOver: a set's stored time, e.g. time 0:45.")
        } else if let distanceM {
            text = Fmt.distance(meters: distanceM)
            spoken = String(localized: "distance \(text)", comment: "VoiceOver: a set's stored distance, e.g. distance 5.0 km.")
        } else {
            return nil
        }
    }
}

/// An exercise in the live session: name, target, last time, set rows, add set.
struct ExerciseCard: View {
    var controller: SessionController
    let exercise: LocalSessionExercise
    var onPlates: () -> Void
    var onHistory: () -> Void

    @State private var confirmRemove = false
    @State private var showsReplace = false
    @State private var showsTargets = false
    @State private var showsNotes = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl

    private var usesWeight: Bool { exercise.loadType == .weight || exercise.loadType == .bodyweight }

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                header
                columnTitles
                let sets = exercise.orderedSets
                let current = controller.currentSetID
                ForEach(Array(sets.enumerated()), id: \.element.id) { i, set in
                    SetRow(controller: controller, set: set, exercise: exercise, number: i + 1, count: sets.count)
                        .id(set.id) // scroll anchor for the keypad
                        .currentSetHighlight(current == set.id, setID: set.id)
                }
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
        .confirmationDialog("Remove \(exercise.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove exercise", role: .destructive) { controller.remove(exercise) }
        } message: {
            Text("Its sets in this workout are deleted.")
        }
        .sheet(isPresented: $showsReplace) {
            AddExerciseSheet(replacing: controller.replaceContext(for: exercise)) { picked, alsoChangePlan in
                let ex = exercise, window = SessionController.undoWindow(voiceOver: voiceOver, switchControl: switchControl)
                Task { await controller.replace(ex, with: picked, alsoChangePlan: alsoChangePlan, window: window) }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showsTargets) {
            EditTargetsSheet(controller: controller, exercise: exercise)
        }
        .sheet(isPresented: $showsNotes) {
            ExerciseNotesSheet(controller: controller, exercise: exercise)
        }
    }

    private var menuItems: some View {
        ExerciseMenuItems(controller: controller, exercise: exercise,
                          onReplace: { showsReplace = true }, onTargets: { showsTargets = true }, onNotes: { showsNotes = true },
                          onPlates: onPlates, onHistory: onHistory, onRemove: { confirmRemove = true })
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    // The toast's Undo, reachable from the card too while it lasts (ui.md §4).
                    .accessibilityActions {
                        if let undo = controller.undo, undo.touches(exercise.id) {
                            Button(String(localized: "Undo", comment: "Toast button that takes back the last change, e.g. a replaced exercise.")) {
                                SessionToastOverlay.undo(undo, in: controller)
                            }
                        }
                    }
                if let target = exercise.targetText {
                    Text(target)
                        .font(.ryft(.callout))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel(Text("Target \(target)"))
                }
                if let last = lastTimeText {
                    Text("Last time: \(last)")
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                if !exercise.notes.isEmpty {
                    Button {
                        controller.focus = nil
                        showsNotes = true
                    } label: {
                        Label(exercise.notes, systemImage: "note.text")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 28, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Notes: \(exercise.notes)", comment: "VoiceOver: an exercise's notes in a workout. 1: the notes."))
                    .accessibilityHint(Text("Edits the notes", comment: "VoiceOver hint on an exercise's notes in a workout."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu { menuItems }
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

    private var columnTitles: some View {
        HStack(spacing: 6) {
            Text("Set").frame(width: 40)
            if usesWeight { Text("kg").frame(maxWidth: .infinity) }
            Text("Reps").frame(maxWidth: .infinity)
            Text("RPE").frame(maxWidth: 64)
            Text("").frame(width: 56)
        }
        .ryftLabelStyle(Theme.textTertiary)
        .accessibilityHidden(true)
    }

    /// "97.5 × 5, 97.5 × 4"; past five sets "…, 80 × 5, +2 more", never a silent cut.
    private var lastTimeText: String? {
        let sets = exercise.lastTime.filter { !$0.isWarmup }
        guard !sets.isEmpty else { return nil }
        let shown = 5
        let list = sets.prefix(shown).map { s in
            switch (s.weightKg, s.reps) {
            // No-break spaces keep a set ("80 × 5") on one line when the list wraps.
            case let (kg?, r?): return "\(Fmt.kgNumber(kg))\u{00A0}×\u{00A0}\(r)"
            case let (nil, r?): return "\(r)"
            default: return Fmt.placeholder
            }
        }.joined(separator: ", ")
        let more = sets.count - shown
        guard more > 0 else { return list }
        return list + ", " + String(localized: "+\(more) more",
                                   comment: "Train session, an exercise's Last time line: sets not listed after the first five.")
    }
}

/// Exercises sharing a superset group, held together by a teal bracket.
struct SupersetBracket<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Superset", systemImage: "link")
                .ryftLabelStyle(Theme.accent)
                .padding(.leading, 18)
            HStack(spacing: 8) {
                BracketShape()
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 10)
                    .padding(.vertical, 18)
                    .accessibilityHidden(true)
                VStack(spacing: 10, content: content)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Superset"))
    }
}

/// `[` with rounded ends.
private struct BracketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

#Preview("Exercise card", traits: .sizeThatFitsLayout) {
    let c = TrainPreview.liveController()
    return SchemePair {
        VStack(spacing: 12) {
            ExerciseCard(controller: c, exercise: c.exercises[0], onPlates: {}, onHistory: {})
            SupersetBracket {
                ForEach(c.exercises.filter { $0.supersetGroup == 1 }) {
                    ExerciseCard(controller: c, exercise: $0, onPlates: {}, onHistory: {})
                }
            }
        }
    }
}
