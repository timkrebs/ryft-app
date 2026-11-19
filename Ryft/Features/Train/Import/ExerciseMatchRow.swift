import SwiftUI

/// One distinct imported exercise in step 4 (ui.md 7.2; PR 6 C §4.14, c-23c), a row of its section's grouped card: the
/// file's name and equipment, "→ the RYFT exercise" under it, and a trailing status: "Likely" or "Check" in `warning` (a
/// suggestion to confirm), "New" in `textSecondary`, a checkmark when matched, "Skipped" in `textTertiary`. The row opens its
/// actions; VoiceOver gets them as custom actions too, and hears the status in words. A new exercise without its muscle
/// group offers the muscle inline; a `+N` exercise asks the bodyweight question inline, as select rows under it.
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
        /// The file's names of the other rows mapped to the same RYFT exercise.
        var alsoUsedFor: [String] = []
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: ImportLayout.lineGap) {
                Button(action: actions.open) { main }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
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
                if let shared = alsoUsedForText {
                    ImportNoteLine(systemImage: "arrow.triangle.merge", text: shared)
                        .accessibilityIdentifier("import.shared.\(index)")
                }
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
            }
            .padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.vertical, GroupedListSpec.textPadding + 2)
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
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
        .groupedRowHairline()
    }

    // MARK: Parts

    private var main: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: GroupedListSpec.detailGap * 2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: GroupedListSpec.rowSpacing))
        return layout {
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                (Text(verbatim: row.source.name).foregroundStyle(Theme.textPrimary)
                    + Text(verbatim: row.source.equipmentSuffix).foregroundStyle(Theme.textSecondary))
                    .font(.ryft(.callout))
                    .fixedSize(horizontal: false, vertical: true)
                if let name = content.matchName {
                    Text(verbatim: "→ \(name)")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = quietDetail {
                    Text(verbatim: detail)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ExerciseMatchStatus(status: content.status, questionOpen: content.questionOpen)
        }
        .frame(minHeight: GroupedListSpec.rowMinHeight - 2 * (GroupedListSpec.textPadding + 2))
        .contentShape(Rectangle())
    }

    /// Under the match, what the trailing word doesn't say: a remembered match, a new exercise that is ready, and where the
    /// exercise appears in the file when only in one part.
    private var quietDetail: String? {
        let parts: [String] = switch content.status {
        case .matched(remembered: true), .new(ready: true): [content.status.detail, onlyIn].compactMap { $0 }
        default: [onlyIn].compactMap { $0 }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The answered question as a tag under the match name: tapping it asks again.
    private func answerTag(_ title: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { editingAnswer.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "scalemass").imageScale(.small)
                Text(verbatim: title)
            }
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
            .frame(minHeight: Theme.Metrics.minHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityHint(Text("Change the answer", comment: "Training import, step 4, VoiceOver: the bodyweight answer tag."))
    }

    /// "Create as custom exercise": choosing the muscle group is enough (name and equipment come from the file). An ink
    /// text menu, 44 pt tall.
    private var musclePicker: some View {
        Menu {
            ForEach(Self.muscles) { muscle in
                Button(muscle.title) { actions.setMuscle(muscle) }
            }
        } label: {
            // One paragraph, so it wraps as a sentence at large sizes instead of as two columns.
            (Text("Create as custom exercise", comment: "Training import, step 4: a new row's inline action.")
                + Text(verbatim: " · ")
                + Text("Muscle group", comment: "Training import, step 4: choose the new exercise's muscle group.")
                + Text(verbatim: " ")
                + Text(Image(systemName: "chevron.up.chevron.down")).font(.ryft(.caption)))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .menuStyle(.button)
        .ryftLink()
        // The chevron glyph isn't read: the words only.
        .accessibilityLabel(Text("Create as custom exercise", comment: "Training import, step 4: a new row's inline action.")
            + Text(verbatim: ", ")
            + Text("Muscle group", comment: "Training import, step 4: choose the new exercise's muscle group."))
        .accessibilityIdentifier("import.muscle.\(index)")
    }

    /// "Also used for “Reverse Fly · Machine”": another row of the file maps to the same RYFT exercise.
    private var alsoUsedForText: String? {
        guard !content.alsoUsedFor.isEmpty else { return nil }
        let names = content.alsoUsedFor.map { name in
            String(localized: "“\(name)”", comment: "A name quoted inside a sentence, e.g. an exercise from an imported file.")
        }.formatted(.list(type: .and))
        return String(localized: "Also used for \(names)",
                      comment: "Training import, step 4: other rows of the file map to the same RYFT exercise; the file's exercise names.")
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

/// A match row's trailing status (c-23c): a word, or the checkmark for a match. "Likely", "Check" and "Question" (the
/// bodyweight question is open) are in `warning`: the user has something to answer; "New" in `textSecondary`; "Skipped" in
/// `textTertiary`. The word is always there, so the colour never carries the state alone; VoiceOver reads it with the row.
struct ExerciseMatchStatus: View {
    let status: ImportRowStatus
    var questionOpen = false

    /// What the trailing slot shows: a word in its ink, or the checkmark.
    enum Mark: Equatable {
        case word(String, Ink)
        case checkmark
    }

    enum Ink: Equatable { case attention, secondary, tertiary }

    static func mark(_ status: ImportRowStatus, questionOpen: Bool = false) -> Mark {
        if questionOpen {
            return .word(String(localized: "Question", comment: "Training import, step 4: the bodyweight question is open."), .attention)
        }
        return switch status {
        case .check(likely: true):
            .word(String(localized: "Likely", comment: "Training import, step 4: a row's status, a likely suggestion to confirm."), .attention)
        case .check(likely: false): .word(status.word, .attention)
        case .new: .word(status.word, .secondary)
        case .skipped: .word(status.word, .tertiary)
        case .matched, .yourChoice: .checkmark
        }
    }

    var body: some View {
        switch Self.mark(status, questionOpen: questionOpen) {
        case let .word(word, ink):
            Text(verbatim: word)
                .font(.ryft(.callout))
                .foregroundStyle(color(ink))
                .fixedSize()
        case .checkmark:
            Image(systemName: "checkmark")
                .font(.system(size: GroupedListSpec.checkmarkSize, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func color(_ ink: Ink) -> Color {
        switch ink {
        case .attention: Theme.warning
        case .secondary: Theme.textSecondary
        case .tertiary: Theme.textTertiary
        }
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
                                        dropsPlusLoad: dropsPlusLoad(row),
                                        alsoUsedFor: sharing(row).map(\.source.displayName))
    }
}

#Preview("Match rows", traits: .sizeThatFitsLayout) {
    let flow = ImportMockData.flow(.map)
    let mapping = flow.mapping
    return DarkPreview {
        GroupedCard {
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
    return DarkPreview {
        GroupedCard {
            ForEach(Array((mapping?.attention ?? []).prefix(3).enumerated()), id: \.offset) { index, row in
                if let mapping {
                    ExerciseMatchRow(content: mapping.content(row), index: index, actions: .preview)
                }
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

/// Two rows of the file chosen onto one RYFT exercise: both say so, and both keep their choice.
#Preview("Match rows · one exercise twice", traits: .sizeThatFitsLayout) {
    let flow = ImportMockData.flow(.map) { flow in
        let rows = flow.mapping?.rows ?? []
        if rows.count > 1, let mapping = flow.mapping, let target = rows.lazy.compactMap(mapping.exercise(for:)).first {
            flow.choose(rows[0].id, target)
            flow.choose(rows[1].id, target)
        }
    }
    let mapping = flow.mapping
    return DarkPreview {
        GroupedCard {
            ForEach(Array((mapping?.rows ?? []).prefix(2).enumerated()), id: \.offset) { index, row in
                if let mapping {
                    ExerciseMatchRow(content: mapping.content(row), index: index, actions: .preview)
                }
            }
        }
    }
}

extension ExerciseMatchRow.Actions {
    static var preview: Self {
        Self(open: {}, accept: {}, chooseAnother: {}, createCustom: {}, skip: {}, setMuscle: { _ in }, answer: { _ in })
    }
}
