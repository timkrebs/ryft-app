import SwiftUI

/// Step 4 (ui.md §7): every distinct imported exercise matched to the library once. How many need the user first,
/// then those rows, then the matched ones. A fuzzy match is never accepted without a tap; a bodyweight question has a
/// default and never blocks.
struct ImportMapView: View {
    @Bindable var model: ImportFlowModel

    @State private var actionsFor: RowTarget?
    @State private var chooseFor: RowTarget?
    @State private var createFor: RowTarget?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A row's key as a sheet's item.
    struct RowTarget: Identifiable, Equatable {
        let key: SourceExerciseKey
        let name: String
        var id: SourceExerciseKey { key }
    }

    var body: some View {
        ImportStepScaffold(model: model, step: .map) {
            switch model.libraryState {
            case .loading: loading
            case .unavailable: unavailable
            case .ready: if let mapping = model.mapping { content(mapping) }
            }
        } bottom: {
            if let left = model.mapping?.leftToCheck, left > 0, model.libraryState == .ready {
                ImportBarCaption(text: String(localized: "\(left) left to check.",
                                              comment: "Training import M3: rows that still block Continue."))
                    .accessibilityIdentifier("import.leftToCheck")
            }
            ImportPrimaryButton(title: String(localized: "Continue"),
                                isEnabled: model.libraryState == .ready && model.mapping?.leftToCheck == 0) {
                model.continueFromMap()
            }
        }
        .modifier(SearchWhen(enabled: model.showsMapControls, text: $model.search))
        .confirmationDialog(Text(verbatim: actionsFor?.name ?? ""), isPresented: Binding(
            get: { actionsFor != nil }, set: { if !$0 { actionsFor = nil } }), titleVisibility: .visible,
            presenting: actionsFor) { target in
            dialogButtons(target)
        } message: { target in
            Text(verbatim: dialogMessage(target))
        }
        .sheet(item: $chooseFor) { target in
            AddExerciseSheet(title: "Match “\(target.name)”", initialQuery: target.name) { exercise in
                model.choose(target.key, exercise)
            }
            .environment(model.deps.library)
        }
        .sheet(item: $createFor) { target in
            if let draft = model.draft(for: target.key) {
                CustomExerciseForm(draft: CustomExerciseDraft(draft)) { edited in
                    model.create(target.key, ImportCustomDraft(edited, base: draft))
                }
                .environment(model.deps.library)
            }
        }
    }

    // MARK: States

    /// M4: outline rows, no shimmer, no spinner.
    private var loading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Loading the exercise library…", comment: "Training import M4.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline)
                    .frame(height: 64)
            }
            .accessibilityHidden(true)
        }
    }

    /// M5: no partial matching without the library.
    private var unavailable: some View {
        InlineMessage(message: String(localized: "The exercise library isn't available offline yet.", comment: "Training import M5."),
                      systemImage: "wifi.exclamationmark",
                      retry: { await model.prepareMapping() },
                      caption: String(localized: "RYFT needs it to match exercises.", comment: "Training import M5."),
                      identifier: "import.library")
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ mapping: ImportMappingState) -> some View {
        countLine(mapping)
        if model.showsMapControls { filter(mapping) }
        let likely = mapping.likelyChecks.count
        if likely > 0 {
            ImportTextButton(title: String(localized: "Accept \(likely) likely matches",
                                           comment: "Training import, step 4: accept every likely suggestion."),
                             systemImage: "checkmark.circle", identifier: "import.accept") {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { model.acceptLikely() }
            }
        }
        let attention = model.visibleRows(attention: true)
        let resolved = model.filter == .needsCheck ? [] : model.visibleRows(attention: false)
        if attention.isEmpty, resolved.isEmpty, !model.search.isEmpty {
            InlineMessage(message: String(localized: "No exercise matches “\(model.search)”.",
                                          comment: "Training import, step 4: the search found nothing."),
                          systemImage: "magnifyingglass")
        }
        LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
            if !attention.isEmpty {
                Section { rows(attention, mapping, section: "attention") } header: {
                    header(String(localized: "Needs your attention", comment: "Training import: step 4's section, and Profile → Data's row."))
                }
            }
            if !resolved.isEmpty {
                Section { rows(resolved, mapping, section: "matched") } header: {
                    header(String(localized: "Matched", comment: "Training import, step 4: a row's status."))
                }
            }
        }
        footer(mapping)
    }

    private func countLine(_ mapping: ImportMappingState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: String(localized: "\(mapping.rows.count) exercises"))
                .font(.ryft(.metric))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(verbatim: breakdown(mapping))
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("import.mapCount")
    }

    private func breakdown(_ mapping: ImportMappingState) -> String {
        if mapping.allMatched {
            return String(localized: "All \(mapping.rows.count) matched. Check them if you like.", comment: "Training import M2.")
        }
        return [String(localized: "\(mapping.matchedCount) matched", comment: "Training import, step 4: the count line."),
                String(localized: "\(mapping.checkCount) to check", comment: "Training import, step 4: the count line."),
                String(localized: "\(mapping.newCount) new", comment: "Training import, step 4: the count line.")]
            .joined(separator: " · ")
    }

    @ViewBuilder
    private func filter(_ mapping: ImportMappingState) -> some View {
        let all = String(localized: "All", comment: "Training import, step 4: the filter shows every row.")
        let check = String(localized: "Needs a check (\(mapping.leftToCheck))", comment: "Training import, step 4: the filter.")
        if typeSize.isAccessibilitySize {
            Picker(selection: $model.filter) {
                Text(verbatim: all).tag(ImportFlowModel.MapFilter.all)
                Text(verbatim: check).tag(ImportFlowModel.MapFilter.needsCheck)
            } label: {
                Text(verbatim: all)
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
        } else {
            SegmentedPicker(selection: $model.filter, options: [.all, .needsCheck]) { $0 == .all ? all : check }
        }
    }

    private func header(_ title: String) -> some View {
        TrainSectionTitle(title: LocalizedStringKey(title))
            .padding(.vertical, 6)
            .background(Theme.background)
    }

    /// A row's identity includes its section: a row that moves from "Needs your attention" to "Matched" is a new
    /// view there (a lazy stack otherwise reused the old one's content).
    private func rows(_ rows: [ImportMappingRow], _ mapping: ImportMappingState, section: String) -> some View {
        ForEach(rows) { row in
            let index = mapping.rows.firstIndex(of: row) ?? 0
            ExerciseMatchRow(content: mapping.content(row), index: index, actions: actions(row))
                .id("\(section)\u{1F}\(row.id.name)\u{1F}\(row.id.equipment)")
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: mapping.rows)
    }

    private func actions(_ row: ImportMappingRow) -> ExerciseMatchRow.Actions {
        let target = RowTarget(key: row.id, name: row.source.name)
        let isCheck = if case .check = row.decision { true } else { false }
        return ExerciseMatchRow.Actions(
            open: { actionsFor = target },
            accept: isCheck ? { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { model.accept(row.id) } } : nil,
            chooseAnother: { chooseFor = target },
            createCustom: { createFor = target },
            skip: { model.skip(row.id) },
            setMuscle: { muscle in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { model.setMuscle(row.id, muscle) } },
            answer: { model.answer(row.id, $0) })
    }

    @ViewBuilder
    private func footer(_ mapping: ImportMappingState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if mapping.newCount > 0 {
                Text("\(mapping.newCount) new exercises are created when you import.", comment: "Training import M6.")
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("RYFT remembers your choices for next time. They're part of Export my data, and you can clear them in Profile → Data.",
                 comment: "Training import, step 4: the footer.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The row's actions

    @ViewBuilder
    private func dialogButtons(_ target: RowTarget) -> some View {
        if let row = model.mapping?.row(target.key) {
            if case .check = row.decision, let name = model.mapping?.exercise(for: row)?.name {
                Button(String(localized: "Use “\(name)”", comment: "Training import, step 4: accept the suggestion.")) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { model.accept(row.id) }
                }
            }
            Button(String(localized: "Choose another exercise…", comment: "Training import, step 4: pick from the library.")) {
                chooseFor = target
            }
            Button(String(localized: "Create a custom exercise…", comment: "Training import, step 4: a new exercise.")) {
                createFor = target
            }
            Button(String(localized: "Skip this exercise", comment: "Training import, step 4: leave it out."), role: .destructive) {
                model.skip(row.id)
            }
        }
    }

    /// What the row maps to now, and what skipping means.
    private func dialogMessage(_ target: RowTarget) -> String {
        let skip = String(localized: "Its sets aren't imported and it's removed from the plan.",
                          comment: "Training import, step 4: what Skip this exercise does.")
        guard let mapping = model.mapping, let row = mapping.row(target.key), let name = mapping.content(row).matchName else {
            return skip
        }
        return "\(name) · \(mapping.status(of: row).word)\n\(skip)"
    }
}

/// `.searchable` only when there are enough rows to need it (ui.md 7.1: more than 8).
private struct SearchWhen: ViewModifier {
    let enabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, prompt: Text("Search exercises"))
        } else {
            content
        }
    }
}

extension CustomExerciseDraft {
    /// The custom-exercise form, prefilled from an import row.
    init(_ draft: ImportCustomDraft) {
        self.init(name: draft.name)
        kind = draft.kind
        loadType = draft.loadType
        muscle = draft.muscle
        unilateral = draft.unilateral
    }
}

extension ImportCustomDraft {
    /// The form's answer back as the row's draft.
    init(_ edited: CustomExerciseDraft, base: ImportCustomDraft) {
        self.init(name: edited.trimmedName.isEmpty ? base.name : edited.trimmedName, kind: edited.kind,
                  loadType: edited.loadType, muscle: edited.muscle, unilateral: edited.unilateral)
    }
}

#Preview("Step 4 · mixed rows · dark") {
    NavigationStack { ImportMapView(model: ImportMockData.flow(.map)) }
        .previewEnvironment()
}

#Preview("Step 4 · mixed rows · light · AX3") {
    NavigationStack { ImportMapView(model: ImportMockData.flow(.map)) }
        .previewEnvironment(scheme: .light)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Step 4 · all matched · light") {
    NavigationStack {
        ImportMapView(model: ImportMockData.flow(.map) { flow in
            for row in flow.mapping?.rows ?? [] {
                flow.accept(row.id)
                if row.draft != nil { flow.setMuscle(row.id, .hamstrings) }
                if let answer = flow.mapping?.bodyweightAnswer(row) { flow.answer(row.id, answer) }
            }
        })
    }
    .previewEnvironment(scheme: .light)
}

#Preview("Step 4 · loading · dark") {
    NavigationStack { ImportMapView(model: ImportMockData.flow(.map) { $0.libraryState = .loading }) }
        .previewEnvironment()
}

#Preview("Step 4 · library unavailable · light") {
    NavigationStack { ImportMapView(model: ImportMockData.flow(.map) { $0.libraryState = .unavailable }) }
        .previewEnvironment(scheme: .light)
}

#Preview("Step 4 · 60 exercises, filter on · dark") {
    NavigationStack {
        ImportMapView(model: ImportMockData.flow(.map, files: [ImportMockData.file(0, "Library.csv", ImportMockData.manyExercises)]) {
            $0.filter = .needsCheck
        })
    }
    .previewEnvironment()
}
