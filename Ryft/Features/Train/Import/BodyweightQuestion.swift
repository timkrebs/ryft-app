import SwiftUI

/// The `+N` question, inline on its row (ui.md 7.4, design §5): asked once per exercise, its options by the matched
/// exercise's `load_type`, one pre-selected. Equal full-width tiles at least 44 pt tall; the selected one has a filled
/// radio and the selected trait, never colour alone.
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
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: BodyweightText.question(name: exerciseName, plus: plus))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: BodyweightText.seen(plus))
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
            if loadType == .weight {
                Text("The file logs this as a bodyweight exercise.",
                     comment: "Training import, step 4: a +N exercise matched to a loaded exercise.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    ImportOptionTile(title: BodyweightText.title(option, loadType: loadType, plus: plus),
                                     caption: BodyweightText.caption(option, loadType: loadType, plus: plus),
                                     isSelected: option == selected) {
                        onSelect(option)
                    }
                    .accessibilityIdentifier("import.bodyweight.\(option.identifier)")
                }
            }
        }
        .padding(.leading, 16)
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline) }
    }
}

/// One choice of an inline question: a radio, a title and an optional caption.
struct ImportOptionTile: View {
    let title: String
    let caption: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(verbatim: caption)
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isSelected ? Theme.surfaceRaised : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Theme.separator, lineWidth: isSelected ? 1.5 : Theme.Metrics.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: caption ?? ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
            ? String(localized: "Seen on \(plus.setCount) sets.", comment: "Training import, step 4: how many sets have the +N load.")
            : String(localized: "Seen on \(plus.setCount) sets with different values.",
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
    return SchemePair { Demo() }
}

#Preview("Bodyweight question · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        if let plus = PlusLoadSummary(kilograms: [75, 75, 75]) {
            BodyweightQuestion(exerciseName: "Pull-Ups", plus: plus, loadType: .bodyweight,
                               options: BodyweightAnswer.options(for: .bodyweight, plus: plus), selected: .bodyWeight) { _ in }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
