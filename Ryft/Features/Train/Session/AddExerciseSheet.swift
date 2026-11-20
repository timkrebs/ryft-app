import SwiftUI

/// What the sheet needs to replace an exercise mid-session (ui.md §2): the old exercise, what happens to its sets,
/// and whether "Also change the plan" is offered.
struct ReplaceContext {
    /// The exercise being replaced, as the session shows it.
    let name: String
    let exerciseID: UUID
    let kind: SessionController.ReplaceKind
    /// nil: not a plan session, a built-in plan, or no plan link: the row is absent.
    let plan: PlanChangeOption?
    let offline: Bool
}

/// Search the library with muscle and kind filters, or create a custom exercise.
/// Works offline from the cached library. In replace mode (`replacing`) "Similar" comes first, a note says what
/// happens to done sets, and a plan session can change its plan too.
///
/// Nocturne (PR 6 B §4.8, `b-24`): `SheetHeader` with the title and the close circle, the search field pinned under it, the
/// filter chips (the chosen one filled with ink), then the exercises as rows of grouped cards under "Similar" and "All
/// exercises", each with a quiet `+`, and "Custom exercise" as a text row at the end. "Also change the plan" is a toggle row,
/// pinned under the list at the default sizes and scrolling with it at the accessibility sizes.
struct AddExerciseSheet: View {
    var title: LocalizedStringKey = "Add exercise"
    /// The search field's text when the sheet opens (the import's "Choose another exercise…": the file's name).
    var initialQuery = ""
    /// The import: "Custom exercise" opens the form with this draft and hands the draft back; nothing is created
    /// now (the import creates it under its derived id when Import is tapped). nil: the form saves to the library.
    var importDraft: CustomExerciseDraft?
    var onImportDraft: ((CustomExerciseDraft) -> Void)?
    /// Replace mode; a pick goes to `onReplace` with the plan toggle's value.
    var replacing: ReplaceContext?
    var onReplace: ((Exercise, _ alsoChangePlan: Bool) -> Void)?
    let onPick: (Exercise) -> Void

    @Environment(TrainLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var muscle: Muscle?
    @State private var kind: ExerciseKind?
    @State private var showsCustom = false
    @State private var seeded = false
    /// Off every time the sheet opens (never remembered).
    @State private var alsoChangePlan = false

    /// An exercise row's trailing glyph.
    static let pickGlyph = "plus"

    private var muscles: [Muscle] {
        Array(Set(library.exercises.flatMap(\.primaryMuscles))).sorted { $0.title < $1.title }
    }

    private var kinds: [ExerciseKind] {
        ExerciseKind.allCases.filter { k in library.exercises.contains { $0.kind == k } }
    }

    private var results: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return library.exercises.filter { e in
            e.id != replacing?.exerciseID
                && (q.isEmpty || e.name.lowercased().contains(q) || e.slug.contains(q))
                && (muscle.map { e.primaryMuscles.contains($0) || e.secondaryMuscles.contains($0) } ?? true)
                && (kind.map { e.kind == $0 } ?? true)
        }
    }

    /// Hidden while the user steers (search or a filter).
    private var similar: [Exercise] {
        guard let id = replacing?.exerciseID, let old = library.exercise(id: id),
              query.trimmingCharacters(in: .whitespaces).isEmpty, muscle == nil, kind == nil else { return [] }
        return ExerciseSimilarity.rank(for: old, in: library.exercises)
    }

    /// At accessibility sizes a pinned bar would leave room for about one row: the plan toggle scrolls instead.
    private var pinsPlanControl: Bool { !typeSize.isAccessibilitySize }

    var body: some View {
        SheetFrame(navigationTitle) {
            EmptyView()
        } pinned: {
            SearchField(text: $query, prompt: Text("Search exercises"), identifier: "exercise.search")
        } content: {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                if let replacing {
                    replaceHeader(replacing)
                }
                if !pinsPlanControl, let plan = replacing?.plan {
                    planControl(plan)
                }
                let similar = similar
                if !similar.isEmpty {
                    GroupedCard(Text("Similar", comment: "Section of exercises like the one being replaced.")) {
                        ForEach(similar) { row($0) }
                    }
                }
                filters
                if results.isEmpty {
                    InlineMessage(message: library.exercises.isEmpty
                                  ? String(localized: "The exercise library hasn't loaded yet. Create a custom exercise to log it now.")
                                  : String(localized: "No exercise matches. Create it as a custom exercise."),
                                  systemImage: "magnifyingglass")
                } else {
                    GroupedCard(Text("All exercises", comment: "Section with the whole exercise library, below Similar.")) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(results) { row($0) }
                        }
                    }
                }
                customRow
            }
        }
        .modifier(PlanBar(plan: pinsPlanControl ? replacing?.plan : nil) { planControl($0) })
        .sheet(isPresented: $showsCustom) {
            if let importDraft, let onImportDraft {
                CustomExerciseForm(draft: importDraft) { draft in
                    onImportDraft(draft)
                    dismiss()
                }
                .presentedRoot()
            } else {
                CustomExerciseForm(name: query) { e in
                    pick(e)
                }
                .presentedRoot()
            }
        }
        .onAppear {
            guard !seeded else { return }
            seeded = true
            query = initialQuery
            alsoChangePlan = false
        }
    }

    private var navigationTitle: Text {
        guard let replacing else { return Text(title) }
        return Text("Replace \(replacing.name)",
                    comment: "Title of the sheet that replaces an exercise mid-workout. 1: exercise name.")
    }

    /// The exercise as a grouped row: the name, "Barbell · Chest" under it, a `+` at the end. VoiceOver: a button named by the
    /// exercise, the detail as its value.
    private func row(_ e: Exercise) -> some View {
        GroupedRow.action(Text(verbatim: e.name), detail: Text(verbatim: Self.detail(of: e)), systemImage: Self.pickGlyph) {
            pick(e)
        }
        .accessibilityIdentifier("exercise.pick.\(e.slug.isEmpty ? e.id.uuidString : e.slug)")
    }

    /// "Barbell · Chest", "Barbell · Quads, glutes" (`b-24`: the muscles as a list after the first), "Custom · Dumbbell · Shoulders".
    static func detail(of e: Exercise) -> String {
        let custom = e.isCustom ? [String(localized: "Custom")] : []
        let muscles = e.primaryMuscles.enumerated().map { $0.offset == 0 ? $0.element.title : $0.element.title.localizedLowercase }
        let parts = custom + [e.kind.title] + (muscles.isEmpty ? [] : [muscles.joined(separator: ", ")])
        return parts.joined(separator: " · ")
    }

    /// A text row at the end: `+` and "Custom exercise" in ink, 46 high.
    private var customRow: some View {
        Button {
            showsCustom = true
        } label: {
            Label("Custom exercise", systemImage: "plus")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.listRowHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exercise.custom")
    }

    private func pick(_ e: Exercise) {
        if let onReplace, replacing != nil {
            onReplace(e, alsoChangePlan && replacing?.plan?.isAvailable == true)
        } else {
            onPick(e)
        }
        dismiss()
    }

    // MARK: replace mode

    @ViewBuilder
    private func replaceHeader(_ r: ReplaceContext) -> some View {
        if r.offline {
            Label {
                Text("Offline. Showing your saved exercise library.",
                     comment: "Caption in the replace sheet without a connection.")
            } icon: {
                Image(systemName: "wifi.slash")
            }
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if case .split(let done, let remaining) = r.kind, done > 0 {
            InlineMessage(message: Self.doneLine(done: done, name: r.name), systemImage: "arrow.triangle.2.circlepath",
                          caption: Self.remainingLine(remaining), identifier: "replace.split", announces: false,
                          readsAsOne: true)
        }
    }

    static func doneLine(done: Int, name: String) -> String {
        done == 1
            ? String(localized: "Your done set stays with \(name).",
                     comment: "Replace sheet, one set already done. 1: the exercise being replaced.")
            : String(localized: "Your \(done) done sets stay with \(name).",
                     comment: "Replace sheet, several sets already done. 1: number of sets, 2: the exercise being replaced.")
    }

    static func remainingLine(_ remaining: Int) -> String {
        remaining == 1
            ? String(localized: "The new exercise continues with 1 set.",
                     comment: "Replace sheet: the picked exercise gets the one remaining set.")
            : String(localized: "The new exercise continues with \(remaining) sets.",
                     comment: "Replace sheet: the picked exercise gets the remaining sets. 1: number of sets.")
    }

    /// "Also change the plan" as a toggle row, its caption the row's detail (VoiceOver reads both as the switch's label).
    private func planControl(_ plan: PlanChangeOption) -> some View {
        let caption = plan.isAvailable
            ? String(localized: "Applies from the next \(plan.dayName) day.",
                     comment: "Under the Also change the plan toggle. 1: plan day name, e.g. Upper.")
            : String(localized: "Applies from the next \(plan.dayName) day. You're offline: the plan can only be changed online.",
                     comment: "Under the disabled Also change the plan toggle without a connection. 1: plan day name.")
        return GroupedCard {
            GroupedRow.toggle(Text("Also change the plan", comment: "Toggle in the replace sheet: change the plan day too."),
                              detail: Text(verbatim: caption), isOn: $alsoChangePlan)
                .disabled(!plan.isAvailable)
                .accessibilityIdentifier("replace.alsoChangePlan")
        }
        .toggleStyle(.ryft)
    }

    /// Two rows of chips, muscles then kinds, each scrolling sideways; "All muscles" and "All kinds" first.
    private var filters: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: FilterChip.spacing) {
                    FilterChip(title: String(localized: "All muscles"), selected: muscle == nil) { muscle = nil }
                    ForEach(muscles) { m in
                        FilterChip(title: m.title, selected: muscle == m) { muscle = muscle == m ? nil : m }
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: FilterChip.spacing) {
                    FilterChip(title: String(localized: "All kinds"), selected: kind == nil) { kind = nil }
                    ForEach(kinds) { k in
                        FilterChip(title: k.title, selected: kind == k) { kind = kind == k ? nil : k }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        // The chips' 44 pt boxes reach 5 above and below their 34 pt capsules: the row keeps the group spacing to the capsule.
        .padding(.vertical, -FilterChip.hitOverhang)
    }
}

/// Pins "Also change the plan" under the list (`pinnedBar`) when there is a plan to change and the sizes allow it.
private struct PlanBar<Control: View>: ViewModifier {
    let plan: PlanChangeOption?
    @ViewBuilder let control: (PlanChangeOption) -> Control

    func body(content: Content) -> some View {
        if let plan {
            // `pinnedBar`'s bar, with VoiceOver meeting it after the header and the search and before the list it decides
            // about (it sits under it). The priority goes on the bar itself: it is a group of its own.
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PinnedActionBar { control(plan) }
                        .accessibilitySortPriority(SheetFrameSpec.outsidePinnedPriority)
                }
                .accessibilityElement(children: .contain)
        } else {
            content
        }
    }
}

/// A filter chip (PR 6 B §4.8): a 34 pt capsule in a 44 pt tap box, `callout`. The chosen one is filled with ink and its title
/// in the screen's colour; the others are a 1 pt outline of ink at 16 % with an ink title. Selected for VoiceOver too.
struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    /// The capsule: 34 high, 12 at the sides, chips 8 apart; its tap box 44, so 5 above and below.
    static let height: CGFloat = 34, horizontalPadding: CGFloat = 12, spacing: CGFloat = 8
    static let hitOverhang = (Theme.Metrics.minHitTarget - height) / 2
    /// An unchosen chip's outline: ink at 16 %.
    static let edge = 0.16

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ryft(.callout))
                .foregroundStyle(selected ? Theme.background : Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, Self.horizontalPadding)
                .frame(minHeight: Self.height)
                .background { Capsule().fill(selected ? Theme.textPrimary : .clear) }
                .overlay {
                    Capsule().strokeBorder(Theme.textPrimary.opacity(selected ? 0 : Self.edge), lineWidth: Theme.Metrics.hairline)
                }
                .padding(.vertical, Self.hitOverhang)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A user's own exercise; saved locally first, so it can be logged offline (PR 6 B §4.8): `SheetHeader("Custom exercise")`
/// with a compact "Add", the name as a form field, and Kind, Main muscle and Logged as as menu rows with the value in grey,
/// then "One side at a time".
struct CustomExerciseForm: View {
    let onSave: (Exercise) -> Void
    /// The import's mode: the draft goes back and nothing is saved now (it's created when Import is tapped, ui.md 7.3).
    private var onDraft: ((CustomExerciseDraft) -> Void)?

    @Environment(TrainLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomExerciseDraft
    @State private var saving = false
    /// Set once the form is cancelled or goes away. A save still under way then hands nothing back: the workout (or plan) it
    /// was for may be over. A reference, so `save()` sees the write made after its await began.
    @State private var closing = FormClosing()
    @FocusState private var nameFocused: Bool

    private static let muscles = Muscle.allCases.sorted { $0.title < $1.title }
    private static let loadTypes: [LoadType] = [.weight, .bodyweight, .time, .distance]
    /// Under the name while it is longer than the platform takes: "Up to 80 characters."
    static var tooLong: Text {
        Text("Up to \(CustomExerciseDraft.maxNameLength) characters.",
             comment: "Under a custom exercise's name while it is too long; Add stays off. 1: the limit, 80.")
    }

    init(name: String, onSave: @escaping (Exercise) -> Void) {
        _draft = State(initialValue: CustomExerciseDraft(name: name))
        self.onSave = onSave
    }

    /// Prefilled (the import: name and kind from the file, the muscle left to choose); Add hands the draft back.
    init(draft: CustomExerciseDraft, onDraft: @escaping (CustomExerciseDraft) -> Void) {
        _draft = State(initialValue: draft)
        onSave = { _ in }
        self.onDraft = onDraft
    }

    var body: some View {
        SheetFrame(Text("Custom exercise"), closeLabel: Text("Cancel"), onClose: {
            closing.closed = true
            dismiss()
        }) {
            PillButton(Text("Add"), size: .compact, busy: saving) { await save() }
                .disabled(!draft.canSave)
                .accessibilityIdentifier("customExercise.add")
        } content: {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                // Over the platform's 80 scalars, Add stays off and the reason sits under the field.
                GroupedCard(footer: draft.nameIsTooLong ? Self.tooLong : nil) {
                    // The field's label says "Name" once: an empty prompt, not the label again.
                    FormField(Text("Name"), isFocused: nameFocused) {
                        TextField(text: $draft.name, prompt: Text(verbatim: "").fieldPrompt()) { Text("Name") }
                            .textInputAutocapitalization(.words)
                            .focused($nameFocused)
                            .accessibilityIdentifier("customExercise.name")
                    }
                }
                GroupedCard {
                    GroupedRow.menu(Text("Kind"), value: Text(verbatim: draft.kind.title)) {
                        Picker(selection: $draft.kind) {
                            ForEach(ExerciseKind.allCases) { Text(verbatim: $0.title).tag($0) }
                        } label: { Text("Kind") }
                            .pickerStyle(.inline)
                    }
                    GroupedRow.menu(Text("Main muscle"), value: draft.muscle.map { Text(verbatim: $0.title) } ?? Text("Choose")) {
                        Picker(selection: $draft.muscle) {
                            if draft.muscle == nil {
                                Text("Choose").tag(Muscle?.none)
                            }
                            ForEach(Self.muscles) { Text(verbatim: $0.title).tag(Optional($0)) }
                        } label: { Text("Main muscle") }
                            .pickerStyle(.inline)
                    }
                    .accessibilityIdentifier("customExercise.muscle")
                    GroupedRow.menu(Text("Logged as"), value: Text(verbatim: draft.loadType.title)) {
                        Picker(selection: $draft.loadType) {
                            ForEach(Self.loadTypes, id: \.self) { Text(verbatim: $0.title).tag($0) }
                        } label: { Text("Logged as") }
                            .pickerStyle(.inline)
                    }
                    GroupedRow.toggle(Text("One side at a time"), isOn: $draft.unilateral)
                }
                .toggleStyle(.ryft)
            }
        }
        .onDisappear { closing.closed = true }
    }

    private func save() async {
        guard !saving else { return }
        if let onDraft {
            onDraft(draft)
            dismiss()
            return
        }
        saving = true
        let e = draft.exercise
        // Nil only for a name the platform would refuse, which `canSave` already keeps out: stay open, add nothing.
        guard let saved = await library.createExercise(e) else {
            saving = false
            return
        }
        saving = false
        // Cancelled or gone while it saved: the library keeps the exercise; the session or plan doesn't get it.
        guard !closing.closed else { return }
        onSave(saved)
        dismiss()
    }
}

/// `CustomExerciseForm`'s "closed" mark.
@MainActor private final class FormClosing {
    var closed = false
}

extension AddExerciseSheet {
    /// Replace mode: "Replace <name>", Similar first, the split note and the plan toggle.
    init(replacing context: ReplaceContext, onReplace: @escaping (Exercise, _ alsoChangePlan: Bool) -> Void) {
        self.init(replacing: context, onReplace: onReplace, onPick: { _ in })
    }
}

// MARK: - previews (dark only)

/// `b-24`.
#Preview("Add exercise") {
    Color.clear
        .sheet(isPresented: .constant(true)) { AddExerciseSheet { _ in } }
        .environment(TrainPreview.library)
        .preferredColorScheme(.dark)
}

#Preview("Add exercise · AX3") {
    AddExerciseSheet { _ in }
        .environment(TrainPreview.library)
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.dark)
}

#Preview("Custom exercise") {
    CustomExerciseForm(name: "Landmine press") { _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.dark)
}

/// Over the platform's 80 scalars (11 family emoji and "Rows"): Add off, the reason under the field.
#Preview("Custom exercise · name too long") {
    CustomExerciseForm(name: String(repeating: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}", count: 11) + "Rows") { _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.dark)
}

#Preview("Custom exercise · AX3") {
    CustomExerciseForm(name: "Landmine press") { _ in }
        .environment(TrainPreview.library)
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.dark)
}

#Preview("Replace · free session") {
    AddExerciseSheet(replacing: SessionSheetsPreview.replaceContext(split: false, plan: false)) { _, _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.dark)
}

#Preview("Replace · plan, split") {
    AddExerciseSheet(replacing: SessionSheetsPreview.replaceContext()) { _, _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.dark)
}

#Preview("Replace · plan · AX3 (toggle scrolls)") {
    AddExerciseSheet(replacing: SessionSheetsPreview.replaceContext()) { _, _ in }
        .environment(TrainPreview.library)
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.dark)
}

#Preview("Replace · plan, offline") {
    AddExerciseSheet(replacing: SessionSheetsPreview.replaceContext(offline: true)) { _, _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.dark)
}
