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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let replacing {
                        replaceHeader(replacing)
                    }
                    let similar = similar
                    if !similar.isEmpty {
                        Text("Similar", comment: "Section of exercises like the one being replaced.")
                            .ryftLabelStyle()
                            .accessibilityAddTraits(.isHeader)
                        LazyVStack(spacing: 8) {
                            ForEach(similar) { row($0) }
                        }
                        Divider().overlay(Theme.separator)
                        Text("All exercises", comment: "Section with the whole exercise library, below Similar.")
                            .ryftLabelStyle()
                            .accessibilityAddTraits(.isHeader)
                    }
                    filters
                    if results.isEmpty {
                        InlineMessage(message: library.exercises.isEmpty
                                      ? String(localized: "The exercise library hasn't loaded yet. Create a custom exercise to log it now.")
                                      : String(localized: "No exercise matches. Create it as a custom exercise."),
                                      systemImage: "magnifyingglass")
                    }
                    LazyVStack(spacing: 8) {
                        ForEach(results) { row($0) }
                    }
                    Button {
                        showsCustom = true
                    } label: {
                        Label("Custom exercise", systemImage: "plus.circle")
                    }
                    .buttonStyle(TealButtonStyle(prominent: false))
                    .padding(.top, 4)
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search exercises"))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let plan = replacing?.plan { planBar(plan) }
            }
            .sheet(isPresented: $showsCustom) {
                if let importDraft, let onImportDraft {
                    CustomExerciseForm(draft: importDraft) { draft in
                        onImportDraft(draft)
                        dismiss()
                    }
                } else {
                    CustomExerciseForm(name: query) { e in
                        pick(e)
                    }
                }
            }
            .onAppear {
                guard !seeded else { return }
                seeded = true
                query = initialQuery
                alsoChangePlan = false
            }
        }
    }

    private var navigationTitle: Text {
        guard let replacing else { return Text(title) }
        return Text("Replace \(replacing.name)",
                    comment: "Title of the sheet that replaces an exercise mid-workout. 1: exercise name.")
    }

    private func row(_ e: Exercise) -> some View {
        Button {
            pick(e)
        } label: {
            ExerciseRow(exercise: e, wrapsSubtitle: replacing != nil && typeSize.isAccessibilitySize)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("exercise.pick.\(e.slug.isEmpty ? e.id.uuidString : e.slug)")
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
        }
        if case .split(let done, let remaining) = r.kind, done > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.doneLine(done: done, name: r.name))
                Text(Self.remainingLine(remaining))
            }
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.accent).frame(width: 2).padding(.vertical, 10)
            }
            .accessibilityElement(children: .combine)
        }
    }

    static func doneLine(done: Int, name: String) -> String {
        done == 1
            ? String(localized: "Your done set stays as \(name).",
                     comment: "Replace sheet, one set already done. 1: the exercise being replaced.")
            : String(localized: "Your \(done) done sets stay as \(name).",
                     comment: "Replace sheet, several sets already done. 1: number of sets, 2: the exercise being replaced.")
    }

    static func remainingLine(_ remaining: Int) -> String {
        remaining == 1
            ? String(localized: "The new exercise continues with 1 set.",
                     comment: "Replace sheet: the picked exercise gets the one remaining set.")
            : String(localized: "The new exercise continues with \(remaining) sets.",
                     comment: "Replace sheet: the picked exercise gets the remaining sets. 1: number of sets.")
    }

    private func planBar(_ plan: PlanChangeOption) -> some View {
        let caption = plan.isAvailable
            ? String(localized: "Applies from the next \(plan.dayName) day.",
                     comment: "Under the Also change the plan toggle. 1: plan day name, e.g. Upper.")
            : String(localized: "Applies from the next \(plan.dayName) day. You're offline: the plan can only be changed online.",
                     comment: "Under the disabled Also change the plan toggle without a connection. 1: plan day name.")
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $alsoChangePlan) {
                Text("Also change the plan", comment: "Toggle in the replace sheet: change the plan day too.")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .disabled(!plan.isAvailable)
            .accessibilityHint(Text(caption))
            .accessibilityIdentifier("replace.alsoChangePlan")
            Text(caption)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline) }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    FilterChip(title: String(localized: "All muscles"), selected: muscle == nil) { muscle = nil }
                    ForEach(muscles) { m in
                        FilterChip(title: m.title, selected: muscle == m) { muscle = muscle == m ? nil : m }
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    FilterChip(title: String(localized: "All kinds"), selected: kind == nil) { kind = nil }
                    ForEach(kinds) { k in
                        FilterChip(title: k.title, selected: kind == k) { kind = kind == k ? nil : k }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    /// The subtitle may take two lines (replace mode at accessibility sizes).
    var wrapsSubtitle = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: Self.icon(for: exercise.kind))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exercise.name)
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    if exercise.isCustom {
                        Text("Custom")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.accentSecondary)
                    }
                }
                Text(([exercise.kind.title] + exercise.primaryMuscles.map(\.title)).joined(separator: " · "))
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(wrapsSubtitle ? 2 : 1)
            }
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .frame(minHeight: 56)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func icon(for kind: ExerciseKind) -> String {
        switch kind {
        case .barbell, .dumbbell, .kettlebell: return "dumbbell.fill"
        case .bodyweight: return "figure.strengthtraining.functional"
        case .machine, .cable: return "figure.strengthtraining.traditional"
        case .cardio: return "figure.rower"
        }
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ryft(.callout))
                .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(selected ? Theme.accent : Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A user's own exercise; saved locally first, so it can be logged offline.
struct CustomExerciseForm: View {
    let onSave: (Exercise) -> Void
    /// The import's mode: the draft goes back and nothing is saved now (it's created when Import is tapped, ui.md 7.3).
    private var onDraft: ((CustomExerciseDraft) -> Void)?

    @Environment(TrainLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomExerciseDraft
    @State private var saving = false

    private static let muscles = Muscle.allCases.sorted { $0.title < $1.title }

    init(name: String, onSave: @escaping (Exercise) -> Void) {
        _draft = State(initialValue: CustomExerciseDraft(name: name))
        self.onSave = onSave
    }

    /// Prefilled (the import: name and kind from the file, the muscle left to choose); Save hands the draft back.
    init(draft: CustomExerciseDraft, onDraft: @escaping (CustomExerciseDraft) -> Void) {
        _draft = State(initialValue: draft)
        onSave = { _ in }
        self.onDraft = onDraft
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .font(.ryft(.body))
                        .textInputAutocapitalization(.words)
                }
                Section("Kind") {
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(ExerciseKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Main muscle", selection: $draft.muscle) {
                        if draft.muscle == nil {
                            Text("Choose").tag(Muscle?.none)
                        }
                        ForEach(Self.muscles) { Text($0.title).tag(Optional($0)) }
                    }
                    .accessibilityIdentifier("customExercise.muscle")
                    Picker("Logged as", selection: $draft.loadType) {
                        ForEach([LoadType.weight, .bodyweight, .time, .distance], id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("One side at a time", isOn: $draft.unilateral)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Custom exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!draft.canSave || saving)
                }
            }
        }
    }

    private func save() async {
        if let onDraft {
            onDraft(draft)
            dismiss()
            return
        }
        saving = true
        let e = draft.exercise
        let saved = await library.createExercise(e) ?? e
        saving = false
        onSave(saved)
        dismiss()
    }
}

#Preview("Add exercise · dark") {
    AddExerciseSheet { _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.dark)
}

#Preview("Add exercise · light") {
    AddExerciseSheet { _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.light)
}

#Preview("Custom exercise") {
    CustomExerciseForm(name: "Landmine press") { _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.dark)
}

extension AddExerciseSheet {
    /// Replace mode: "Replace <name>", Similar first, the split note and the plan toggle.
    init(replacing context: ReplaceContext, onReplace: @escaping (Exercise, _ alsoChangePlan: Bool) -> Void) {
        self.init(replacing: context, onReplace: onReplace, onPick: { _ in })
    }
}

private extension ReplaceContext {
    static func preview(split: Bool, plan: PlanChangeOption?, offline: Bool = false) -> ReplaceContext {
        ReplaceContext(name: MockTrain.bench.name, exerciseID: MockTrain.bench.id,
                       kind: split ? .split(done: 2, remaining: 2) : .inPlace, plan: plan, offline: offline)
    }
}

#Preview("Replace · free session · dark") {
    AddExerciseSheet(replacing: .preview(split: false, plan: nil)) { _, _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.dark)
}

#Preview("Replace · free session · light") {
    AddExerciseSheet(replacing: .preview(split: false, plan: nil)) { _, _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.light)
}

#Preview("Replace · plan, split · dark") {
    AddExerciseSheet(replacing: .preview(split: true, plan: PlanChangeOption(dayName: "Upper", isAvailable: true))) { _, _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.dark)
}

#Preview("Replace · plan, split · light") {
    AddExerciseSheet(replacing: .preview(split: true, plan: PlanChangeOption(dayName: "Upper", isAvailable: true))) { _, _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.light)
}

#Preview("Replace · plan, offline · dark") {
    AddExerciseSheet(replacing: .preview(split: true, plan: PlanChangeOption(dayName: "Upper", isAvailable: false),
                                         offline: true)) { _, _ in }
        .environment(TrainPreview.library)
        .preferredColorScheme(.dark)
}
