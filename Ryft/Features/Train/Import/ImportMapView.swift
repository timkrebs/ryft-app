import SwiftUI

/// Step 4 (ui.md §7): every distinct imported exercise matched to the library once. How many need the user first,
/// then those rows, then the matched ones. A fuzzy match is never accepted without a tap; a bodyweight question has a
/// default and never blocks. Look (PR 6 C §4.14, c-23c): the count line, the filter and search once there are many rows,
/// "Accept 3 likely matches", then "Needs your attention" and "Matched" as grouped cards; the pinned bar says how many are
/// left to check.
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
        .confirmationDialog(Text(verbatim: actionsFor?.name ?? ""), isPresented: Binding(
            get: { actionsFor != nil }, set: { if !$0 { actionsFor = nil } }), titleVisibility: .visible,
            presenting: actionsFor) { target in
            dialogButtons(target)
        } message: { target in
            Text(verbatim: dialogMessage(target))
        }
        .sheet(item: $chooseFor) { target in
            // Its "Custom exercise" stays a draft here: nothing is created before Import (review fix).
            let draft = model.draft(for: target.key)
                ?? ImportCustomDraft(name: target.name, kind: .machine, loadType: .weight, muscle: nil)
            AddExerciseSheet(title: "Match “\(target.name)”", initialQuery: target.name,
                             importDraft: CustomExerciseDraft(draft),
                             onImportDraft: { model.create(target.key, ImportCustomDraft($0, base: draft)) }) { exercise in
                model.choose(target.key, exercise)
            }
            .environment(model.deps.library)
            .presentedRoot()
        }
        .sheet(item: $createFor) { target in
            if let draft = model.draft(for: target.key) {
                CustomExerciseForm(draft: CustomExerciseDraft(draft)) { edited in
                    model.create(target.key, ImportCustomDraft(edited, base: draft))
                }
                .environment(model.deps.library)
                .presentedRoot()
            }
        }
    }

    // MARK: States

    /// M4: the words, then outline rows; no shimmer, no spinner.
    private var loading: some View {
        VStack(alignment: .leading, spacing: ImportLayout.slotSpacing) {
            Text("Loading the exercise library…", comment: "Training import M4.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
            ImportLoadingRows(count: 6, label: Text("Loading the exercise library…", comment: "Training import M4."))
                .accessibilityHidden(true)
        }
    }

    /// M5: no partial matching without the library; never a spinner that waits for a connection.
    private var unavailable: some View {
        InlineMessage(message: String(localized: "The exercise library isn't available offline yet.", comment: "Training import M5."),
                      systemImage: "wifi.slash",
                      retry: { await model.prepareMapping() },
                      caption: String(localized: "RYFT needs it to match exercises.", comment: "Training import M5."),
                      identifier: "import.library")
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ mapping: ImportMappingState) -> some View {
        countLine(mapping)
        if model.showsMapControls {
            filter(mapping)
            ImportSearchField(text: $model.search)
        }
        let likely = mapping.likelyChecks.count
        if likely > 0 {
            ImportTextButton(title: String(localized: "Accept \(likely) likely matches",
                                           comment: "Training import, step 4: accept every likely suggestion."),
                             identifier: "import.accept") {
                withAnimation(Theme.Motion.respecting(reduceMotion)) { model.acceptLikely() }
            }
            .padding(.vertical, -ImportLayout.lineGap)
        }
        let attention = model.visibleRows(attention: true)
        let resolved = model.filter == .needsCheck ? [] : model.visibleRows(attention: false)
        if attention.isEmpty, resolved.isEmpty, !model.search.isEmpty {
            InlineMessage(message: String(localized: "No exercise matches “\(model.search)”.",
                                          comment: "Training import, step 4: the search found nothing."),
                          systemImage: "magnifyingglass", announces: false)
        }
        if !attention.isEmpty {
            GroupedCard(Text("Needs your attention", comment: "Training import: step 4's section, and Profile → Data's row."),
                        footer: resolved.isEmpty ? footer(mapping) : nil) {
                rows(attention, mapping, section: "attention")
            }
        }
        if !resolved.isEmpty {
            GroupedCard(Text("Matched", comment: "Training import, step 4: a row's status."), footer: footer(mapping)) {
                rows(resolved, mapping, section: "matched")
            }
        }
    }

    /// One line (c-23c): "12 matched · 2 to check · 1 new" (from AX1 one count per line, `PartsLine`), or "All 12
    /// matched…". VoiceOver hears the total first.
    private func countLine(_ mapping: ImportMappingState) -> some View {
        PartsLine(breakdownParts(mapping) ?? [], joined: breakdown(mapping),
                  spoken: "\(String(localized: "\(mapping.rows.count) exercises")). \(breakdown(mapping))")
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .accessibilityIdentifier("import.mapCount")
    }

    private func breakdown(_ mapping: ImportMappingState) -> String {
        breakdownParts(mapping)?.joined(separator: " · ")
            ?? String(localized: "All \(mapping.rows.count) matched. Check them if you like.", comment: "Training import M2.")
    }

    /// "12 matched", "2 to check", "1 new"; nil once all are matched (one sentence, not counts).
    private func breakdownParts(_ mapping: ImportMappingState) -> [String]? {
        guard !mapping.allMatched else { return nil }
        return [String(localized: "\(mapping.matchedCount) matched", comment: "Training import, step 4: the count line."),
                String(localized: "\(mapping.checkCount) to check", comment: "Training import, step 4: the count line."),
                String(localized: "\(mapping.newCount) new", comment: "Training import, step 4: the count line.")]
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
        } else {
            SegmentedPicker(selection: $model.filter, options: [.all, .needsCheck]) { $0 == .all ? all : check }
        }
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
        .animation(Theme.Motion.respecting(reduceMotion), value: mapping.rows)
    }

    private func actions(_ row: ImportMappingRow) -> ExerciseMatchRow.Actions {
        let target = RowTarget(key: row.id, name: row.source.name)
        let isCheck = if case .check = row.decision { true } else { false }
        return ExerciseMatchRow.Actions(
            open: { actionsFor = target },
            accept: isCheck ? { withAnimation(Theme.Motion.respecting(reduceMotion)) { model.accept(row.id) } } : nil,
            chooseAnother: { chooseFor = target },
            createCustom: { createFor = target },
            skip: { model.skip(row.id) },
            setMuscle: { muscle in withAnimation(Theme.Motion.respecting(reduceMotion)) { model.setMuscle(row.id, muscle) } },
            answer: { model.answer(row.id, $0) })
    }

    /// The last group's footer: M6 (how many exercises importing creates), then what RYFT remembers.
    private func footer(_ mapping: ImportMappingState) -> Text {
        let remembers = Text("RYFT remembers your choices for next time. They're part of Export my data, and you can clear them in Profile → Data.",
                             comment: "Training import, step 4: the footer.")
        guard mapping.newCount > 0 else { return remembers }
        return Text("\(mapping.newCount) new exercises are created when you import.", comment: "Training import M6.")
            + Text(verbatim: " ") + remembers
    }

    // MARK: The row's actions

    @ViewBuilder
    private func dialogButtons(_ target: RowTarget) -> some View {
        if let row = model.mapping?.row(target.key) {
            if case .check = row.decision, let name = model.mapping?.exercise(for: row)?.name {
                Button(String(localized: "Use “\(name)”", comment: "Training import, step 4: accept the suggestion.")) {
                    withAnimation(Theme.Motion.respecting(reduceMotion)) { model.accept(row.id) }
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

/// Step 4's search once there are more than 8 rows (ui.md 7.1): the page has no navigation bar for `.searchable`, so the
/// field sits in the content. A `surface` capsule 46 high: the glass, the text, a clear button while there is text.
/// PR 6 B's `SearchField` (on the Train branch) draws the same; this one goes once both are merged.
private struct ImportSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: GroupedListSpec.glyphSize, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text("Search exercises").fieldPrompt()) { Text("Search exercises") }
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("Search exercises"))
                .accessibilityIdentifier("import.search")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: GroupedListSpec.glyphSize, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: Theme.Metrics.minHitTarget, height: Theme.Metrics.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search", comment: "VoiceOver label of the button that empties a search field."))
            }
        }
        .padding(.leading, GroupedListSpec.rowInset)
        .padding(.trailing, text.isEmpty ? GroupedListSpec.rowInset : 0)
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
        .background(Theme.surface, in: Capsule())
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

#Preview("Step 4 · mixed rows") {
    NavigationStack { ImportMapView(model: ImportMockData.flow(.map)) }
        .previewEnvironment()
}

#Preview("Step 4 · mixed rows · AX3") {
    NavigationStack { ImportMapView(model: ImportMockData.flow(.map)) }
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Step 4 · all matched") {
    NavigationStack {
        ImportMapView(model: ImportMockData.flow(.map) { flow in
            for row in flow.mapping?.rows ?? [] {
                flow.accept(row.id)
                if row.draft != nil { flow.setMuscle(row.id, .hamstrings) }
                if let answer = flow.mapping?.bodyweightAnswer(row) { flow.answer(row.id, answer) }
            }
        })
    }
    .previewEnvironment()
}

#Preview("Step 4 · loading") {
    NavigationStack { ImportMapView(model: ImportMockData.flow(.map) { $0.libraryState = .loading }) }
        .previewEnvironment()
}

#Preview("Step 4 · library unavailable") {
    NavigationStack { ImportMapView(model: ImportMockData.flow(.map) { $0.libraryState = .unavailable }) }
        .previewEnvironment()
}

#Preview("Step 4 · 60 exercises, filter on") {
    NavigationStack {
        ImportMapView(model: ImportMockData.flow(.map, files: [ImportMockData.file(0, "Library.csv", ImportMockData.manyExercises)]) {
            $0.filter = .needsCheck
        })
    }
    .previewEnvironment()
}
