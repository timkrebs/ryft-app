import SwiftUI

/// The `+N` question, inline on its row (ui.md 7.4, design §5; PR 6 C §4.14 "select rows"): asked once per exercise, its
/// options by the matched exercise's `load_type`, one pre-selected. The question and how often the file has it, then one
/// select row per option (its title, its caption on the detail line, the checkmark and the selected trait on the chosen one,
/// never colour alone), full width in the row's card.
struct BodyweightQuestion: View {
    /// The file's name for the exercise ("Dips").
    let exerciseName: String
    let plus: PlusLoadSummary
    let loadType: LoadType
    let options: [BodyweightAnswer]
    /// The tapped, remembered or default answer.
    let selected: BodyweightAnswer?
    let onSelect: (BodyweightAnswer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                Text(verbatim: BodyweightText.question(name: exerciseName, plus: plus))
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: BodyweightText.seen(plus))
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                if loadType == .weight {
                    Text("The file logs this as a bodyweight exercise.",
                         comment: "Training import, step 4: a +N exercise matched to a loaded exercise.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.vertical, GroupedListSpec.textPadding + 2)
            .groupedRowHairline()
            .accessibilityElement(children: .combine)
            ForEach(options, id: \.self) { option in
                GroupedRow.select(Text(verbatim: BodyweightText.title(option, loadType: loadType, plus: plus)),
                                  detail: BodyweightText.caption(option, loadType: loadType, plus: plus).map { Text(verbatim: $0) },
                                  isSelected: option == selected, identifier: "import.bodyweight.\(option.identifier)") {
                    onSelect(option)
                }
            }
        }
    }
}

extension BodyweightAnswer {
    /// The identifiers' last part: `import.bodyweight.added`.
    var identifier: String {
        switch self {
        case .addedWeight: "added"
        case .bodyWeight: "body"
        case .ignore: "ignore"
        }
    }
}

/// The question's words (ui.md 7.4, §11).
enum BodyweightText {
    /// "+20": the most frequent N.
    static func plus(_ plus: PlusLoadSummary) -> String { "+\(Fmt.kgNumber(plus.mostCommonKg))" }

    static func question(name: String, plus: PlusLoadSummary) -> String {
        String(localized: "‘\(Self.plus(plus))’ for \(name): is that added weight, or your body weight?",
               comment: "Training import, step 4: the bodyweight question; the load as written (+20) and the file's exercise name.")
    }

    static func seen(_ plus: PlusLoadSummary) -> String {
        plus.isUniform
            ? String(localized: "Seen on \(plus.setCount)\u{00A0}sets.", comment: "Training import, step 4: how many sets have the +N load.")
            : String(localized: "Seen on \(plus.setCount)\u{00A0}sets with different values.",
                     comment: "Training import, step 4: the +N load differs between sets.")
    }

    static func title(_ answer: BodyweightAnswer, loadType: LoadType, plus: PlusLoadSummary) -> String {
        switch (answer, loadType) {
        case (.addedWeight, .weight):
            String(localized: "\(Fmt.kg(plus.mostCommonKg)) is the weight",
                   comment: "Training import, step 4: a +N exercise matched to a loaded exercise; e.g. 20 kg.")
        case (.addedWeight, _): String(localized: "Added weight", comment: "Training import, step 4: N is added on top of the body.")
        case (.bodyWeight, _): String(localized: "Body weight", comment: "Training import, step 4: N is the user's own weight.")
        case (.ignore, _): String(localized: "Ignore", comment: "Training import, step 4: import the reps only.")
        }
    }

    static func caption(_ answer: BodyweightAnswer, loadType: LoadType, plus: PlusLoadSummary) -> String? {
        let kg = Fmt.kg(plus.mostCommonKg)
        switch (answer, loadType) {
        case (.addedWeight, .weight): return nil
        case (.addedWeight, _):
            return String(localized: "Each set adds \(kg) to your body weight.", comment: "Training import, step 4: the added-weight option.")
        case (.bodyWeight, _):
            return String(localized: "The number is your own weight. RYFT logs the sets without added weight and notes \(kg) as your body weight for the workout.",
                          comment: "Training import, step 4: the body-weight option.")
        case (.ignore, _):
            return String(localized: "Import the reps only.", comment: "Training import, step 4: the ignore option.")
        }
    }
}

#Preview("Bodyweight question", traits: .sizeThatFitsLayout) {
    struct Demo: View {
        @State var answer: BodyweightAnswer? = .addedWeight
        @State var uniform: BodyweightAnswer? = .bodyWeight
        var body: some View {
            VStack(spacing: 24) {
                if let plus = PlusLoadSummary(kilograms: [20, 20, 20, 20, 20, 20, 15, 20]) {
                    BodyweightQuestion(exerciseName: "Dips", plus: plus, loadType: .bodyweight,
                                       options: BodyweightAnswer.options(for: .bodyweight, plus: plus), selected: answer) {
                        answer = $0
                    }
                }
                if let plus = PlusLoadSummary(kilograms: [75, 75, 75]) {
                    BodyweightQuestion(exerciseName: "Pull-Ups", plus: plus, loadType: .bodyweight,
                                       options: BodyweightAnswer.options(for: .bodyweight, plus: plus), selected: uniform) {
                        uniform = $0
                    }
                }
                if let plus = PlusLoadSummary(kilograms: [20, 20]) {
                    BodyweightQuestion(exerciseName: "Dips", plus: plus, loadType: .weight,
                                       options: BodyweightAnswer.options(for: .weight, plus: plus), selected: .addedWeight) { _ in }
                }
            }
        }
    }
    return DarkPreview { GroupedCard { Demo() } }
}

#Preview("Bodyweight question · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { GroupedCard {
        if let plus = PlusLoadSummary(kilograms: [75, 75, 75]) {
            BodyweightQuestion(exerciseName: "Pull-Ups", plus: plus, loadType: .bodyweight,
                               options: BodyweightAnswer.options(for: .bodyweight, plus: plus), selected: .bodyWeight) { _ in }
        }
    } }
    .environment(\.dynamicTypeSize, .accessibility3)
}
