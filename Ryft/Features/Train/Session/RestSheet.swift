import SwiftUI

/// The rest pill's sheet (design.md §2.7, §4c; PR 6 B §4.5, `b-07`, `b-27`). Idle: −15 and +15 set the length of the rest Start
/// begins; the exercise changes only through "Set as rest for this exercise". Running: they move the countdown, Skip ends it. If
/// the rest ends with the sheet open, it turns into the idle one. The clock, two outlined keys, the primary pill, the Next line.
struct RestSheet: View {
    var controller: SessionController
    let exercise: LocalSessionExercise

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: RestDraft

    /// `seconds`: a length other than the exercise's, for previews and shots.
    init(controller: SessionController, exercise: LocalSessionExercise, seconds: Int? = nil) {
        self.controller = controller
        self.exercise = exercise
        _draft = State(initialValue: RestDraft(seconds: seconds ?? exercise.restSec))
    }

    /// Medium at 390 pt, within 4 pt. At 693 pt high, medium ends above "Set as rest for this exercise", which appears
    /// only once the length changed: nobody would scroll down to find it.
    private static let detent = PresentationDetent.height(426)

    /// 426 pt is measured at the default text size and fits only there: at XL the last line touches the edge, and above it
    /// a wrapped Next line or the longer German button ends below it. So every larger size opens full. Large stays in reach
    /// at the default size too, for a long exercise name.
    private var detents: Set<PresentationDetent> {
        typeSize > .large ? [.large] : [Self.detent, .large]
    }

    private var isRunning: Bool { controller.rest.isRunning }
    private var keySize: CGFloat { typeSize >= .accessibility3 ? 64 : 56 }

    /// −15 and +15. A fixed size, as every number here, so they grow by hand with the key.
    static func keyNumeral(_ typeSize: DynamicTypeSize) -> CGFloat { typeSize >= .accessibility3 ? 26 : 17 }
    /// Skip's glyph in the pill's circle.
    static let skipGlyph = "forward.end"

    var body: some View {
        SheetFrame(Text("Rest"), closeLabel: Text("Done")) {
            VStack(spacing: 16) {
                value
                HStack(spacing: 12) {
                    key(.less)
                    key(.more)
                }
                primary
                Text(RestBar.nextLine(controller.nextLabel()))
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !isRunning, draft.seconds != exercise.restSec { saveToExercise }
            }
            .padding(Theme.Metrics.screenPadding)
            .frame(maxWidth: .infinity)
        }
        .restSheet()
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : detents)
    }

    @ViewBuilder
    private var value: some View {
        if isRunning {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                clock(controller.rest.remaining(at: context.date).rounded(.up))
            }
        } else {
            clock(TimeInterval(draft.seconds))
        }
    }

    private func clock(_ seconds: TimeInterval) -> some View {
        Text(Fmt.clock(seconds))
            .font(.ryftNumber(size: 56))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .accessibilityLabel(Text("Rest"))
            .accessibilityValue(Text(verbatim: RestSpeech.duration(Int(seconds))))
            .accessibilityIdentifier("restSheet.value")
    }

    private enum Key {
        case less, more
        var sign: Int { self == .less ? -1 : 1 }
        // A true minus (U+2212).
        var title: String { self == .less ? "\u{2212}15 s" : "+15 s" }
        var label: Text { self == .less ? Text("Fifteen seconds less") : Text("Fifteen seconds more") }
        var spoken: Text {
            self == .less ? Text("Minus 15", comment: "Voice Control name of the rest bar's −15 button.")
                : Text("Plus 15", comment: "Voice Control name of the rest bar's +15 button.")
        }
    }

    private func isEnabled(_ key: Key) -> Bool {
        if isRunning { return true }
        return key == .less ? draft.canDecrease : draft.canIncrease
    }

    private func key(_ key: Key) -> some View {
        let enabled = isEnabled(key)
        return Button {
            if isRunning {
                controller.adjustRest(by: TimeInterval(key.sign) * RestTimer.step)
            } else {
                draft.adjust(by: key.sign * RestDraft.step)
            }
        } label: {
            Text(verbatim: key.title)
                .font(.ryftNumber(size: Self.keyNumeral(typeSize)))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: keySize)
                .outlinedKey(isEnabled: enabled)
        }
        .buttonStyle(PressableButtonStyle())
        // Held, it walks the length. Not a running rest: a held −15 would end it.
        .buttonRepeatBehavior(isRunning ? .disabled : .enabled)
        .disabled(!enabled)
        .accessibilityLabel(key.label)
        .accessibilityInputLabels([key.spoken, key.label])
        .accessibilityIdentifier(key == .less ? "restSheet.less" : "restSheet.more")
    }

    @ViewBuilder
    private var primary: some View {
        if isRunning {
            PillButton(Text("Skip rest"), systemImage: Self.skipGlyph) {
                controller.skipRest()
                dismiss()
            }
            .accessibilityInputLabels([Text("Skip"), Text("Skip rest")])
            .accessibilityIdentifier("restSheet.skip")
        } else {
            // The pill wraps at the largest sizes and grows with it.
            PillButton(startLabel(Fmt.clock(TimeInterval(draft.seconds))), systemImage: PillButton.Icon.start) {
                controller.startRest(for: exercise, seconds: draft.seconds)
                dismiss()
            }
            .disabled(!draft.canStart)
            .accessibilityLabel(startLabel(RestSpeech.duration(draft.seconds)))
            // VoiceOver says the words, the screen says 1:15: Voice Control takes what the user reads.
            .accessibilityInputLabels([startLabel(Fmt.clock(TimeInterval(draft.seconds))), startLabel(RestSpeech.duration(draft.seconds))])
            .accessibilityIdentifier("restSheet.start")
        }
    }

    private func startLabel(_ length: String) -> Text {
        Text("Start rest \(length)", comment: "The rest sheet's button in a workout, and its VoiceOver label. 1: the length, e.g. 1:15.")
    }

    /// The caption is about the steppers, so it comes first: under the button it would read as what the button does, the
    /// opposite of what it does.
    private var saveToExercise: some View {
        VStack(spacing: 2) {
            Text("Changes the length of this rest only.",
                 comment: "The rest sheet in a workout, above Set as rest for this exercise: the steppers alone don't change the exercise.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                controller.setRest(draft.seconds, for: exercise)
            } label: {
                Text("Set as rest for this exercise", comment: "The rest sheet in a workout: keeps the chosen length for this exercise.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .ryftLink()
            .accessibilityIdentifier("restSheet.save")
        }
    }
}

/// The Rest chip's sheet (design.md §2.7): the rest submenu's presets as rows. One tap sets the exercise's rest and closes.
struct RestChoicesSheet: View {
    var controller: SessionController
    let exercise: LocalSessionExercise

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        SheetFrame(Text("Rest for this exercise", comment: "Title of the sheet behind the rest chip in a workout."),
                   closeLabel: Text("Done")) {
            VStack(spacing: 0) {
                ForEach(RestChoices.presets, id: \.self) { seconds in
                    row(seconds)
                    if seconds != RestChoices.presets.last {
                        Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline)
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
        }
        .restSheet()
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium])
    }

    private func row(_ seconds: Int) -> some View {
        let isCurrent = seconds == exercise.restSec
        return Button {
            controller.setRest(seconds, for: exercise)
            dismiss()
        } label: {
            HStack {
                Text(Fmt.clock(TimeInterval(seconds)))
                    .font(.ryftNumber(size: 20))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: RestSpeech.duration(seconds)))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("restChoice.\(seconds)")
    }
}

/// Both sheets' frame: `SheetFrame` with the close circle labelled "Done" (closing keeps whatever was set) and known as
/// `restSheet.done` to the UI tests and this sheet's history (`SheetHeader` names its close `sheet.close`), a body that pads
/// itself, and the grabber left to the detents (the caller's: large at accessibility sizes). It scrolls, so a short phone cuts
/// nothing off; the header stays.
private extension SheetFrame {
    func restSheet() -> SheetFrame {
        closeIdentifier("restSheet.done")
            .bodyInsets(EdgeInsets())
            .grabber(.automatic)
    }
}

#Preview("Rest sheet · idle") {
    let c = FocusedPreview.controller(.midSession)
    return RestSheet(controller: c, exercise: c.exercises[1]).previewEnvironment()
}

/// `b-27`: idle, the length changed to 3:00.
#Preview("Rest sheet · a changed length") {
    let c = FocusedPreview.controller(.midSession)
    return RestSheet(controller: c, exercise: c.exercises[1], seconds: 180).previewEnvironment()
}

/// `b-07`: running, 1:54 left.
#Preview("Rest sheet · running") {
    let c = FocusedPreview.controller(.restRunning)
    return RestSheet(controller: c, exercise: c.exercises[1]).previewEnvironment()
}

#Preview("Rest sheet · AX3") {
    let c = FocusedPreview.controller(.midSession)
    return RestSheet(controller: c, exercise: c.exercises[1], seconds: 180).previewEnvironment().dynamicTypeSize(.accessibility3)
}

#Preview("Rest choices") {
    let c = FocusedPreview.controller(.midSession)
    return RestChoicesSheet(controller: c, exercise: c.exercises[1]).previewEnvironment()
}
