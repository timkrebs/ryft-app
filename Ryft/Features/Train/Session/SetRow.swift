import SwiftUI

/// The Focused set table's columns at a width (design.md §2.5): the row, its header and the last-time card share them,
/// so a column reads straight down the page. The two fields take what's left, equally.
struct SetTableColumns: Equatable {
    let number: CGFloat
    let fourth: CGFloat
    let check: CGFloat
    let gap: CGFloat
    /// The kg and reps numerals.
    var numeral: CGFloat
    /// Page padding, into which the number's 44 pt hit area reaches.
    let padding: CGFloat
    /// The 320 pt table, whatever the text size.
    var isCompact = false
    /// Off at the sizes where the fields need its room. RPE then moves to a line of the row.
    var hasFourth = true
    var rowHeight: CGFloat = 56
    var lastTimeRow: CGFloat = 36
    /// How far a quiet RPE line, on a done row or an upcoming one that holds an RPE, comes up into its row. A field is
    /// `rowHeight - 8` high and centred, so it starts 4 pt down, and the line sits on top of it: this leaves the field 44 pt.
    var quietLineLift: CGFloat { rowHeight - 48 }

    /// 390 pt class.
    static let regular = SetTableColumns(number: 36, fourth: 56, check: 56, gap: 6, numeral: 22, padding: 16)
    /// 320 pt (Display Zoom).
    static let compact = SetTableColumns(number: 28, fourth: 48, check: 56, gap: 4, numeral: 20, padding: 12, isCompact: true)

    /// The table at a width and a text size (design.md §5.1). From AX1 the numerals grow, and at 320 the fourth column goes,
    /// because a field would be under the 66 pt that holds "102.5". From AX3 it goes everywhere.
    static func fitting(width: CGFloat, typeSize: DynamicTypeSize = .large) -> SetTableColumns {
        var columns = width > 0 && width < 360 ? compact : regular
        if typeSize >= .accessibility1 {
            columns.numeral = 26
            columns.lastTimeRow = 44
            columns.hasFourth = !columns.isCompact
        }
        if typeSize >= .accessibility3 {
            columns.numeral = 30
            columns.rowHeight = 64
            columns.hasFourth = false
        }
        return columns
    }

    /// The number's hit area, 44 wide and a row high, in its own coordinates: left into the page padding, then right into the gap.
    var numberHitArea: CGRect {
        let left = min(padding, 44 - number)
        return CGRect(x: -left, y: 0, width: 44, height: rowHeight)
    }
}

/// A row's look (design.md §3.1, PR 6 B §4.3): Focused's states, which List's rows take too (§4.7). Derived from the set and the
/// active row, never stored.
enum FocusedRowState: Equatable {
    case active, done, upcoming

    init(isCompleted: Bool, isActive: Bool) {
        self = isCompleted ? .done : isActive ? .active : .upcoming
    }
}

/// One set: number (tap: warm-up), kg, reps, RPE, check. 56 pt tall, large
/// monospaced numbers; empty fields show last time / the target ghosted. Both layouts draw the three looks of §4.3
/// (`FocusedRowInk`): List's active row is the controller's current set, and its upcoming fields stay raised at 55 %.
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
    private static let revealWidth: CGFloat = 88

    private var ghost: (reps: Int?, kg: Double?) { controller.ghost(for: set, in: exercise) }
    /// The look: Focused's state, or List's (§4.7: done, the controller's current set, or upcoming). Inks only: what a tap or
    /// VoiceOver does still follows `rowState`. Read once per body and passed down: List's `currentSetID` walks the session.
    private var resolvedLook: FocusedRowState {
        rowState ?? FocusedRowState(isCompleted: set.isCompleted, isActive: controller.currentSetID == set.id)
    }
    private var usesWeight: Bool { exercise.loadType == .weight || exercise.loadType == .bodyweight }

    var body: some View {
        let look = resolvedLook
        return row(look)
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

    /// Focused's row height, with the field and the check filling it as at the default size. List's is 56 (`listRowHeight`).
    private var rowHeight: CGFloat { columns?.rowHeight ?? LiveSessionSpec.listRowHeight }

    private func row(_ look: FocusedRowState) -> some View {
        VStack(spacing: rpeLineIsQuiet(look) ? 0 : 4) {
            cells(look)
            if let columns, controller.showsRPELine(of: set, in: exercise, columns: columns) { rpeLine(look) }
        }
    }

    private func cells(_ look: FocusedRowState) -> some View {
        HStack(spacing: columns?.gap ?? 6) {
            Button {
                tap { controller.toggleWarmup(set) }
            } label: {
                Text(set.isWarmup ? "W" : "\(number)")
                    .font(.ryftNumber(size: 17))
                    .foregroundStyle(FocusedRowInk.number(look))
                    .frame(width: columns?.number ?? 40, height: rowHeight)
                    .background { if look == .active { activePill } }
                    .contentShape(columns.map { Path($0.numberHitArea) } ?? Path(CGRect(x: 0, y: 0, width: 40, height: LiveSessionSpec.listRowHeight)))
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            if usesWeight {
                field(.kg, value: set.weightKg.map(Fmt.kgNumber), ghost: ghost.kg.map(Fmt.kgNumber), look: look)
            }
            if let stored = storedValue {
                readOnlyField(stored, look: look)
            } else {
                field(.reps, value: set.reps.map(String.init), ghost: ghost.reps.map(String.init), look: look)
            }
            if columns?.hasFourth != false {
                if controller.column(for: exercise) == .rpe {
                    field(.rpe, value: set.rpe.map(Fmt.kgNumber), ghost: nil, look: look)
                        .frame(minWidth: columns?.fourth, maxWidth: columns?.fourth ?? 64)
                } else {
                    estimateCell
                }
            }

            Button {
                tap { check() }
            } label: {
                let shape = RoundedRectangle(cornerRadius: LiveSessionSpec.rowRadius, style: .continuous)
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(FocusedRowInk.checkGlyph(look))
                    .frame(width: 56, height: rowHeight)
                    .background(FocusedRowInk.checkFill(look), in: shape)
                    .overlay {
                        if look == .upcoming {
                            shape.strokeBorder(FocusedRowInk.upcomingOutline(), lineWidth: Theme.Metrics.hairline)
                        }
                    }
                    .contentShape(shape)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityHidden(true)
        }
        .frame(minHeight: rowHeight)
    }

    /// RPE at the sizes without a fourth column (design.md §5.1): "RPE 8.5", full width, 44 high. It takes the row's taps as
    /// the field does.
    private func rpeLine(_ look: FocusedRowState) -> some View {
        let focused = rpeLineIsFocused
        let quiet = rpeLineIsQuiet(look)
        let shown = focused ? (controller.buffer.isEmpty ? nil : controller.displayBuffer) : set.rpe.map(Fmt.kgNumber)
        return Button {
            tapField(.rpe)
        } label: {
            Text("RPE \(shown ?? Fmt.placeholder)")
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(shown == nil || set.isCompleted ? Theme.textSecondary : Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: quiet ? .topLeading : .center)
                .padding(.leading, quiet ? (columns?.number ?? 0) + (columns?.gap ?? 0) : 0)
                .background(Theme.surfaceRaised.opacity(fieldOpacity(.rpe, focused: focused, look: look)),
                            in: RoundedRectangle(cornerRadius: LiveSessionSpec.fieldRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: LiveSessionSpec.fieldRadius, style: .continuous)
                    .strokeBorder(focused ? FocusedRowInk.focusRing : .clear, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: LiveSessionSpec.fieldRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        // Over the row's empty lower edge, clear of the ✓, so it stays that row's caption. Its 44 pt stay whole.
        .padding(.trailing, quiet ? (columns?.check ?? 0) + (columns?.gap ?? 0) : 0)
        .padding(.top, quiet ? -(columns?.quietLineLift ?? 0) : 0)
    }

    private var rpeLineIsFocused: Bool { controller.focus == SetFocus(setID: set.id, field: .rpe) }
    /// A line with no field behind it reads as a caption, so it sits under its own row's values, nearer them than the next row.
    /// Centred, with the same gap above and below, it read as the next row's.
    private func rpeLineIsQuiet(_ look: FocusedRowState) -> Bool { fieldOpacity(.rpe, focused: rpeLineIsFocused, look: look) == 0 }

    // MARK: the looks (PR 6 B §4.3, §4.7)

    /// The raised `#` of the active row, with its Volt dot (hidden from VoiceOver with the number: the row says "Next set.").
    private var activePill: some View {
        let side = min(columns?.number ?? LiveSessionSpec.activeNumber, LiveSessionSpec.activeNumber)
        return Circle()
            .fill(Theme.surfaceRaised)
            .frame(width: side, height: side)
            .overlay(alignment: .topTrailing) {
                Circle().fill(FocusedRowInk.mark).frame(width: LiveSessionSpec.activeDot, height: LiveSessionSpec.activeDot)
            }
    }

    /// Only the active row's fields are raised, and RPE stays quieter: it is optional. List raises its upcoming fields too, at
    /// 55 %: it has no pager, so its rows read as a form (§4.7). A done row has no chrome in either.
    private func fieldOpacity(_ f: SetFocus.Field, focused: Bool, look: FocusedRowState) -> Double {
        guard !focused else { return 1 }
        switch look {
        case .active: return f == .rpe ? 0.55 : 1
        case .done: return 0
        case .upcoming: return rowState == nil ? 0.55 : 0
        }
    }

    /// A ghost reads as what you'll do, in a colour that holds 4.5:1; only an empty field is quieter than that. A done
    /// value is grey, told apart from a ghost by the check column.
    private func valueColor(_ f: SetFocus.Field, focused: Bool, look: FocusedRowState, hasValue: Bool, hasGhost: Bool) -> Color {
        FocusedRowInk.value(look, hasValue: hasValue, hasGhost: hasGhost,
                            onRaisedField: fieldOpacity(f, focused: focused, look: look) > 0)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            requestDelete()
        } label: {
            Label("Delete", systemImage: "trash")
                .labelStyle(.iconOnly)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.alert, in: RoundedRectangle(cornerRadius: LiveSessionSpec.rowRadius, style: .continuous))
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
        case let (r?, k?): values = String(localized: "\(r)\u{00A0}reps at \(Fmt.kgNumber(k))\u{00A0}kilograms")
        case let (r?, nil): values = String(localized: "\(r)\u{00A0}reps")
        case let (nil, k?): values = String(localized: "\(Fmt.kgNumber(k))\u{00A0}kilograms")
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

    private func readOnlyField(_ stored: SetStoredValue, look: FocusedRowState) -> some View {
        Text(stored.text)
            .font(.ryftNumber(size: columns?.numeral ?? 22, weight: .regular))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(look == .active ? Theme.textPrimary : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: rowHeight - 8)
    }

    /// The estimate: read-only, grey on every row (brief, PR 1), the dash quieter still (design.md §2.8).
    private var estimateCell: some View {
        let text = controller.columnText(of: set, in: exercise)
        return Text(verbatim: text)
            .font(.ryftNumber(size: numeralSize(.rpe)))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(FocusedRowInk.estimate(isDash: text == Fmt.placeholder))
            .frame(width: columns?.fourth, height: 48)
            .contentShape(Rectangle())
            // As the RPE field in this cell: the first tap on an upcoming row makes it active. The value stays read-only.
            .onTapGesture {
                guard rowState == .upcoming, controller.focus == nil else { return }
                tap { controller.activate(set) }
            }
    }

    /// RPE is quieter than kg and reps, and empty when unset: a table without RPE stays calm (design.md §2.5). List's too
    /// (PR 6 B `b-02`): its raised field says where to type.
    private func emptyText(_ f: SetFocus.Field) -> String {
        f == .rpe ? "" : Fmt.placeholder
    }

    private func numeralSize(_ f: SetFocus.Field) -> CGFloat {
        guard let columns else { return 22 }
        return f == .rpe ? 17 : columns.numeral
    }

    private func tapField(_ f: SetFocus.Field) {
        tap {
            // An upcoming row's first tap makes it active. With the keypad up it moves there, as in List.
            if rowState == .upcoming, controller.focus == nil {
                controller.activate(set)
            } else {
                controller.edit(set, f)
            }
        }
    }

    private func field(_ f: SetFocus.Field, value: String?, ghost: String?, look: FocusedRowState) -> some View {
        let focused = controller.focus == SetFocus(setID: set.id, field: f)
        let shown = focused ? (controller.buffer.isEmpty ? nil : controller.displayBuffer) : value
        return Button {
            tapField(f)
        } label: {
            Group {
                if f == .kg, showsBodyweightGlyph, shown == nil {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text(shown ?? ghost ?? emptyText(f))
                        .font(.ryftNumber(size: numeralSize(f), weight: .regular))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(columns == nil ? 0.6 : 0.75)
                        .foregroundStyle(valueColor(f, focused: focused, look: look, hasValue: shown != nil, hasGhost: ghost != nil))
                }
            }
            .frame(maxWidth: .infinity, minHeight: rowHeight - 8)
            .background(Theme.surfaceRaised.opacity(fieldOpacity(f, focused: focused, look: look)),
                        in: RoundedRectangle(cornerRadius: LiveSessionSpec.fieldRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LiveSessionSpec.fieldRadius, style: .continuous)
                .strokeBorder(focused ? FocusedRowInk.focusRing : .clear, lineWidth: 2))
            // A row with no field chrome still takes the whole field's tap.
            .contentShape(RoundedRectangle(cornerRadius: LiveSessionSpec.fieldRadius, style: .continuous))
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

/// Focused's active row (PR 6 B §4.3): ink at 5 % under it, radius 14, and a 2 pt Volt bar outside its leading edge (10 pt at
/// 390, 6 pt from the screen's edge at either width), as high as the cells less 8 at each end. VoiceOver hears "Next set." as
/// the row's value and the row takes VoiceOver focus after a jump, as List's `CurrentSetHighlight` does; the bar sits further out
/// here, in the page's side rather than a card's padding. One structure whether active or not, so the row keeps its identity as
/// the marks move.
struct FocusedRowHighlight: ViewModifier {
    let isActive: Bool
    let setID: UUID
    let columns: SetTableColumns

    @Environment(\.sessionVoiceOverFocus) private var voiceOverFocus

    func body(content: Content) -> some View {
        let marked = content
            .background {
                RoundedRectangle(cornerRadius: LiveSessionSpec.rowRadius, style: .continuous)
                    .fill(FocusedRowInk.activeRowFill(isActive))
            }
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(FocusedRowInk.mark)
                    .frame(width: LiveSessionSpec.activeBarWidth,
                           height: LiveSessionSpec.activeBarHeight(rowHeight: columns.rowHeight))
                    .offset(x: -LiveSessionSpec.activeBarOutset(padding: columns.padding), y: LiveSessionSpec.activeBarInset)
                    .opacity(isActive ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .accessibilityValue(isActive
                ? Text("Next set.", comment: "VoiceOver: said with the set row the user does next in a workout.")
                : Text(verbatim: ""))
        // The environment is the same for every row of a page, so this never switches a row's identity.
        if let voiceOverFocus {
            marked.accessibilityFocused(voiceOverFocus, equals: setID)
        } else {
            marked
        }
    }
}

extension View {
    /// Focused's active-row marks and its VoiceOver value and focus (`FocusedRowHighlight`).
    func focusedRowHighlight(_ isActive: Bool, setID: UUID, columns: SetTableColumns) -> some View {
        modifier(FocusedRowHighlight(isActive: isActive, setID: setID, columns: columns))
    }
}

// MARK: - previews (dark only)

/// A Focused page's rows as `ExercisePage` lays them out, at 390 pt: `b-04`'s Barbell row (set 1 done, set 2 active with its
/// dot, bar and filled ✓, sets 3 and 4 upcoming on their ghosts).
@MainActor
private func focusedRows(_ scenario: FocusedPreview.Scenario, typeSize: DynamicTypeSize = .large) -> some View {
    let c = FocusedPreview.controller(scenario)
    let ex = c.pageExercise ?? c.exercises[0]
    let sets = ex.orderedSets.filter { !$0.isWarmup }
    let active = c.activeSet(in: ex)?.id
    let columns = SetTableColumns.fitting(width: 390, typeSize: typeSize)
    return VStack(spacing: 4) {
        ForEach(Array(sets.enumerated()), id: \.element.id) { i, set in
            SetRow(controller: c, set: set, exercise: ex, number: i + 1, count: sets.count, swipeToDelete: false,
                   columns: columns, rowState: FocusedRowState(isCompleted: set.isCompleted, isActive: set.id == active))
                .focusedRowHighlight(set.id == active, setID: set.id, columns: columns)
        }
    }
    .padding(.horizontal, columns.padding)
    .padding(.vertical, 20)
    .frame(width: 390)
    .background(Theme.background)
    .dynamicTypeSize(typeSize)
}

/// List's rows on their card (§4.7): `b-02`'s Bench press, set 1 done, set 2 the current set, the rest upcoming with raised
/// fields at 55 %.
@MainActor
private func listRows() -> some View {
    let c = FocusedPreview.controller(.draftList)
    let ex = c.exercises[0]
    let sets = ex.orderedSets
    return VStack(spacing: 10) {
        ForEach(Array(sets.enumerated()), id: \.element.id) { i, set in
            SetRow(controller: c, set: set, exercise: ex, number: i + 1, count: sets.count)
        }
    }
    .padding(14)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: CardSpec.radius, style: .continuous))
    .padding(16)
    .frame(width: 390)
    .background(Theme.background)
}

#Preview("Set rows · Focused", traits: .sizeThatFitsLayout) {
    focusedRows(.draft).previewEnvironment()
}

#Preview("Set rows · Focused, a tapped row and a typed value", traits: .sizeThatFitsLayout) {
    focusedRows(.tappedRow).previewEnvironment()
}

#Preview("Set rows · Focused, AX3", traits: .sizeThatFitsLayout) {
    focusedRows(.draft, typeSize: .accessibility3).previewEnvironment()
}

#Preview("Set rows · List", traits: .sizeThatFitsLayout) {
    listRows().previewEnvironment()
}
