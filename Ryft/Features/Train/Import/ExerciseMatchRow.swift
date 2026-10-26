import SwiftUI

/// One distinct imported exercise in step 4 (ui.md 7.2): the file's name and equipment, the RYFT exercise it maps to,
/// and a trailing status (glyph and word). The row opens its actions; VoiceOver gets them as custom actions too. A
/// new exercise without its muscle group offers the muscle inline; a `+N` exercise asks the bodyweight question inline.
struct ExerciseMatchRow: View {
    /// Everything the row shows, from `ImportMappingState`.
    struct Content: Equatable {
        let row: ImportMappingRow
        let status: ImportRowStatus
        /// The RYFT exercise (or the new one's name); nil when skipped.
        let matchName: String?
        let questionOpen: Bool
        let loadType: LoadType?
        let bodyweightOptions: [BodyweightAnswer]
        let bodyweight: BodyweightAnswer?
        let dropsPlusLoad: Bool
    }

    struct Actions {
        var open: () -> Void
        var accept: (() -> Void)?
        var chooseAnother: () -> Void
        var createCustom: () -> Void
        var skip: () -> Void
        var setMuscle: (Muscle) -> Void
        var answer: (BodyweightAnswer) -> Void
    }

    let content: Content
    let index: Int
    let actions: Actions

    @State private var editingAnswer = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var row: ImportMappingRow { content.row }
    private static let muscles = Muscle.allCases.sorted { $0.title < $1.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: actions.open) { main }
                .buttonStyle(PressableButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: spokenLabel))
                .accessibilityHint(Text("Shows what you can do with this exercise",
                                        comment: "Training import, step 4, VoiceOver: a row opens its actions."))
                .accessibilityAction(named: Text("Use suggestion", comment: "Training import, step 4: VoiceOver action.")) {
                    actions.accept?()
                }
                .accessibilityAction(named: Text("Choose another", comment: "Training import, step 4: VoiceOver action.")) {
                    actions.chooseAnother()
                }
                .accessibilityAction(named: Text("Create custom", comment: "Training import, step 4: VoiceOver action.")) {
                    actions.createCustom()
                }
                .accessibilityAction(named: Text("Skip")) {
                    actions.skip()
                }
                .accessibilityIdentifier("import.row.\(index)")
            if !content.questionOpen, let answer = content.bodyweight, let loadType = content.loadType,
               let plus = row.source.plusLoads {
                answerTag(BodyweightText.title(answer, loadType: loadType, plus: plus))
            }
            if case .new(ready: false) = content.status { musclePicker }
            if row.source.hasAssistedSets {
                ImportNoteLine(systemImage: "info.circle",
                               text: String(localized: "Assisted sets: RYFT imports the reps and leaves out the assistance weight.",
                                            comment: "Training import, step 4: a -N exercise."))
            }
            if content.dropsPlusLoad {
                ImportNoteLine(systemImage: "info.circle",
                               text: String(localized: "The weight is left out for this exercise.",
                                            comment: "Training import, step 4: a +N exercise matched to a time or distance exercise."),
                               tertiary: true)
            }
            if let plus = row.source.plusLoads, let loadType = content.loadType, !content.bodyweightOptions.isEmpty,
               content.questionOpen || editingAnswer {
                BodyweightQuestion(exerciseName: row.source.name, plus: plus, loadType: loadType,
                                   options: content.bodyweightOptions, selected: content.bodyweight) { answer in
                    actions.answer(answer)
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { editingAnswer = false }
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
    }

    // MARK: Parts

    private var main: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            VStack(alignment: .leading, spacing: 5) {
                (Text(verbatim: row.source.name).foregroundStyle(Theme.textPrimary)
                    + Text(verbatim: row.source.equipment.map { " · \($0)" } ?? "").foregroundStyle(Theme.textSecondary))
                    .font(.ryft(.body))
                    .fixedSize(horizontal: false, vertical: true)
                if let name = content.matchName {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textTertiary)
                        Text(verbatim: name)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let detail = content.status.detail {
                    Text(verbatim: detail)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
                if let only = onlyIn {
                    Text(verbatim: only)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 6) {
                statusLabel(content.status.symbol, content.status.word, strong: isCheck)
                if content.questionOpen {
                    statusLabel("scalemass", String(localized: "Question", comment: "Training import, step 4: the bodyweight question is open."),
                                strong: true)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var isCheck: Bool {
        if case .check = content.status { return true }
        return false
    }

    private func statusLabel(_ symbol: String, _ word: String, strong: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(verbatim: word)
        }
        .font(.ryft(.caption))
        .foregroundStyle(strong ? Theme.textPrimary : Theme.textSecondary)
        .fixedSize()
    }

    /// The answered question as a tag beside the match name: tapping it asks again.
    private func answerTag(_ title: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { editingAnswer.toggle() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "scalemass").imageScale(.small)
                Text(verbatim: title)
            }
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.surfaceRaised, in: Capsule())
            .frame(minHeight: 44)
            .padding(.leading, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityHint(Text("Change the answer", comment: "Training import, step 4, VoiceOver: the bodyweight answer tag."))
    }

    /// "Create as custom exercise": choosing the muscle group is enough (name and equipment come from the file).
    private var musclePicker: some View {
        Menu {
            ForEach(Self.muscles) { muscle in
                Button(muscle.title) { actions.setMuscle(muscle) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("Create as custom exercise", comment: "Training import, step 4: a new row's inline action.")
                Text(verbatim: "·").foregroundStyle(Theme.textTertiary)
                Text("Muscle group", comment: "Training import, step 4: choose the new exercise's muscle group.")
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .font(.ryft(.callout))
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("import.muscle.\(index)")
    }

    private var onlyIn: String? {
        switch (row.source.inPlan, row.source.inHistory) {
        case (true, false): String(localized: "Plan only", comment: "Training import, step 4: the exercise is only in the plan.")
        case (false, true): String(localized: "History only", comment: "Training import, step 4: the exercise is only in the workouts.")
        default: nil
        }
    }

    /// "Bench Press, Barbell, matched to Bench press, Matched, Likely match. Question open: is +20 added weight…"
    private var spokenLabel: String {
        var parts = [row.source.name]
        if let equipment = row.source.equipment { parts.append(equipment) }
        if let name = content.matchName {
            parts.append(String(localized: "matched to \(name)", comment: "Training import, step 4, VoiceOver: the RYFT exercise."))
        }
        parts.append(content.status.word)
        if let detail = content.status.detail { parts.append(detail) }
        if content.questionOpen, let plus = row.source.plusLoads {
            parts.append(String(localized: "question open: is \(BodyweightText.plus(plus)) added weight or your body weight",
                                comment: "Training import, step 4, VoiceOver: the bodyweight question is open."))
        }
        if let onlyIn { parts.append(onlyIn) }
        return parts.joined(separator: ", ")
    }
}

extension ImportMappingState {
    /// A row's content for `ExerciseMatchRow`.
    func content(_ row: ImportMappingRow) -> ExerciseMatchRow.Content {
        let matchName: String? = switch row.decision {
        case .check, .matched, .chosen: exercise(for: row)?.name
        case let .create(draft): draft.name
        case .skip: nil
        }
        return ExerciseMatchRow.Content(row: row, status: status(of: row), matchName: matchName,
                                        questionOpen: isQuestionOpen(row), loadType: loadType(of: row),
                                        bodyweightOptions: bodyweightOptions(row), bodyweight: bodyweightAnswer(row),
                                        dropsPlusLoad: dropsPlusLoad(row))
    }
}

#Preview("Match rows", traits: .sizeThatFitsLayout) {
    let flow = ImportMockData.flow(.map)
    let mapping = flow.mapping
    return SchemePair {
        VStack(spacing: 10) {
            ForEach(Array((mapping?.rows ?? []).prefix(7).enumerated()), id: \.offset) { index, row in
                if let mapping {
                    ExerciseMatchRow(content: mapping.content(row), index: index, actions: .preview)
                }
            }
        }
    }
}

#Preview("Match rows · AX3", traits: .sizeThatFitsLayout) {
    let flow = ImportMockData.flow(.map)
    let mapping = flow.mapping
    return SchemePair {
        VStack(spacing: 10) {
            ForEach(Array((mapping?.attention ?? []).prefix(3).enumerated()), id: \.offset) { index, row in
                if let mapping {
                    ExerciseMatchRow(content: mapping.content(row), index: index, actions: .preview)
                }
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

extension ExerciseMatchRow.Actions {
    static var preview: Self {
        Self(open: {}, accept: {}, chooseAnother: {}, createCustom: {}, skip: {}, setMuscle: { _ in }, answer: { _ in })
    }
}
