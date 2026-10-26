import SwiftUI

/// Add activity / Edit activity (ui.md §3): a sheet of card groups (Journal's look, not a system Form). Save is
/// enabled only when the form is valid, and every reason stands under its field. Saving writes on this iPhone and
/// closes the sheet at once; the upload follows (the row shows it).
struct AddActivitySheet: View {
    @State var model: AddActivityModel
    /// After a save (the list cross-fades the new row in).
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(TrainCoordinator.self) private var coordinator
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: Field?
    @State private var picksSport = false
    @State private var announced: [AddActivityModel.Issue] = []

    private enum Field { case distance, notes }

    /// Whether the platform makes strain from perceived effort (open question 4, plan D2-4): the footer's second
    /// sentence. Both variants stay until the contract says which applies.
    static let effortMakesStrain = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.suggestsTrain {
                        strengthSuggestion
                    } else if model.sport == .strength, model.mode == .add {
                        strengthNote
                    }
                    sportGroup
                    whenGroup
                    if model.showsDistance { distanceGroup }
                    effortGroup
                    notesGroup
                    if model.sport != .strength { footer }
                }
                .padding(Theme.Metrics.screenPadding)
                .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: model.suggestsTrain)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text(verbatim: model.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel").foregroundStyle(Theme.textPrimary) }
                        .accessibilityIdentifier("addActivity.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if model.save() {
                            onSaved()
                            dismiss()
                        }
                    } label: {
                        Text("Save").fontWeight(.semibold)
                    }
                    .tint(Theme.accent)
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("addActivity.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { focus = nil } label: { Text("Done") }
                }
            }
            .navigationDestination(isPresented: $picksSport) {
                SportPicker(selection: $model.sport, sports: model.sports, recents: model.recents)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("addActivity.sheet")
        // A reason that appears is announced once, never on every keystroke.
        .onChange(of: model.issues) { _, issues in
            let new = issues.filter { !announced.contains($0) }
            announced = issues
            if let first = new.first {
                AccessibilityNotification.Announcement(AddActivityModel.message(first)).post()
            }
        }
    }

    // MARK: groups

    private var sportGroup: some View {
        Card {
            Button { picksSport = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: model.sport.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    Text(verbatim: model.sport.name)
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    if !model.sportLocked {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.sportLocked)
            .accessibilityLabel(Text("Sport, \(model.sport.name)", comment: "VoiceOver: the chosen sport."))
            .accessibilityHint(model.sportLocked ? Text(verbatim: "") : Text("Opens the list of sports",
                                                                             comment: "VoiceOver: the sport row opens the picker."))
            .accessibilityIdentifier("addActivity.sport")
        }
    }

    @ViewBuilder
    private var whenGroup: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if model.measured {
                    measuredTimes
                } else {
                    picker(Text("Start"), selection: $model.start, in: model.earliest...model.now, id: "addActivity.start")
                    Divider().overlay(Theme.separator)
                    picker(Text("End"), selection: $model.end, in: model.start...max(model.start, model.now), id: "addActivity.end")
                    durationLine
                }
                ForEach(model.issues.filter(Self.isTimeIssue), id: \.self) { issue in
                    IssueLine(text: AddActivityModel.message(issue)).accessibilityIdentifier("addActivity.issue.\(issue)")
                }
            }
        }
    }

    private static func isTimeIssue(_ issue: AddActivityModel.Issue) -> Bool {
        [.endInFuture, .endBeforeStart, .longerThanADay, .startTooEarly].contains(issue)
    }

    /// Start or End: label and a compact date-and-time picker side by side; stacked at accessibility sizes.
    private func picker(_ label: Text, selection: Binding<Date>, in range: ClosedRange<Date>, id: String) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            label
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            DatePicker(selection: selection, in: range, displayedComponents: [.date, .hourAndMinute]) { label }
                .labelsHidden()
                .datePickerStyle(.compact)
                .monospacedDigit()
                .tint(Theme.accent)
                .accessibilityIdentifier(id)
        }
    }

    /// "Duration 1h 00m", and "(next day)" across midnight.
    private var durationLine: some View {
        HStack(spacing: 6) {
            Text("Duration \(MyDayText.keepTogether(Fmt.duration(seconds: model.duration)))",
                 comment: "Add activity: the time between start and end.")
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            if model.crossesMidnight {
                Text("(next day)", comment: "Add activity: the end is on the day after the start.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Duration, \(MyDayRow.spokenDuration(model.duration))",
                                 comment: "VoiceOver: the activity's duration, spelled out."))
        .accessibilityIdentifier("addActivity.duration")
    }

    /// A recorded (or merged) activity: its times as measured, not editable.
    private var measuredTimes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: MyDayText.join(["\(Fmt.time(model.start, locale: locale))–\(Fmt.time(model.end, locale: locale))",
                                           Fmt.duration(seconds: model.duration)]))
                .font(.ryft(.body))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Label {
                Text("Measured by RYFT. Times and distance can't be changed.",
                     comment: "Edit activity: a recorded activity's times and distance are fixed.")
            } icon: {
                Image(systemName: "location.fill")
            }
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("addActivity.measured")
    }

    private var distanceGroup: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                // Measured: the recording's distance, nothing to type.
                (model.measured ? Text("Distance") : Text("Distance (optional)")).ryftLabelStyle()
                if model.measured {
                    Text(verbatim: Fmt.distance(meters: model.draft.distanceM))
                        .font(.ryft(.body))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    HStack(spacing: 8) {
                        TextField(text: $model.distanceText) {
                            Text("Optional", comment: "Add activity: the distance field's placeholder.")
                        }
                        .keyboardType(.decimalPad)
                        .font(.ryft(.body))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .focused($focus, equals: .distance)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("addActivity.distance")
                        Text(verbatim: ActivityFormat.distanceSymbol(locale))
                            .font(.ryft(.body))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if model.issues.contains(.distanceInvalid) {
                        IssueLine(text: AddActivityModel.message(.distanceInvalid))
                            .accessibilityIdentifier("addActivity.issue.distanceInvalid")
                    } else if model.isTooFast {
                        IssueLine(text: String(localized: "That's faster than expected for this sport. Check the distance."))
                            .accessibilityIdentifier("addActivity.tooFast")
                    }
                }
            }
        }
    }

    private var effortGroup: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Perceived effort (optional)").ryftLabelStyle()
                EffortScale(value: $model.effort)
            }
        }
    }

    private var notesGroup: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                TextField(text: $model.notes, axis: .vertical) { Text("Notes") }
                    .lineLimit(2...6)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focus, equals: .notes)
                    .accessibilityIdentifier("addActivity.notes")
                let count = model.notes.count
                if count >= 400 {
                    HStack(spacing: 6) {
                        if count >= AddActivityModel.notesLimit {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.warning)
                                .accessibilityHidden(true)
                            Text(verbatim: AddActivityModel.message(.notesTooLong))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Text(verbatim: "\(count) / \(AddActivityModel.notesLimit)")
                            .monospacedDigit()
                            .foregroundStyle(count >= AddActivityModel.notesLimit ? Theme.textPrimary : Theme.textTertiary)
                    }
                    .font(.ryft(.caption))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Where strain comes from, as a fact at the bottom.
    private var footer: some View {
        Text(Self.effortMakesStrain
             ? String(localized: "Strain comes from the heart rate your tracker syncs for this time. Without it, your effort rating is used.")
             : String(localized: "Without heart rate there is no strain for this activity."))
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("addActivity.footer")
    }

    // MARK: strength (ui.md §3.4)

    private var strengthSuggestion: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "dumbbell")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                Text("Strength is best logged in Train. Your sets, reps and load count toward muscular load.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(title: "Log in Train", style: .secondary) {
                dismiss()
                await coordinator.quickStart(.auto)
            }
            .accessibilityIdentifier("addActivity.logInTrain")
            Button { model.addsStrengthHere = true } label: {
                Text("Add here anyway")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addActivity.addAnyway")
        }
        .padding(Theme.Metrics.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
            .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("addActivity.strength")
    }

    /// After "Add here anyway": one line.
    private var strengthNote: some View {
        Label {
            Text("Strength is best logged in Train.", comment: "Add activity: the collapsed Strength suggestion.")
        } icon: {
            Image(systemName: "dumbbell")
        }
        .font(.ryft(.caption))
        .foregroundStyle(Theme.textSecondary)
        .transition(.opacity)
    }
}

/// A reason under a field: amber glyph, quiet text (ui.md §3.5; amber text fails contrast).
struct IssueLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - previews

@MainActor
private enum AddPreview {
    static let state = AppState.preview(flags: [.todayMyDay: true, .activitiesManual: true])
    static func add(_ setup: (AddActivityModel) -> Void = { _ in }) -> AddActivityModel {
        let model = AddActivityModel(env: state.env, day: .now)
        setup(model)
        return model
    }
    static var recordedRun: SportActivity { MockActivitiesSource.demo().first { $0.origin == .recorded } ?? MockActivitiesSource.demo()[0] }
}

#Preview("Add activity · dark") {
    Color.clear.sheet(isPresented: .constant(true)) { AddActivitySheet(model: AddPreview.add()) }
        .previewEnvironment(AddPreview.state)
}

#Preview("Add activity · light") {
    Color.clear.sheet(isPresented: .constant(true)) { AddActivitySheet(model: AddPreview.add()) }
        .previewEnvironment(AddPreview.state, scheme: .light)
}

#Preview("Add activity · invalid") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddActivitySheet(model: AddPreview.add {
            $0.end = $0.start.addingTimeInterval(-600)
            $0.distanceText = "0"
        })
    }
    .previewEnvironment(AddPreview.state)
}

#Preview("Add activity · strength") {
    Color.clear.sheet(isPresented: .constant(true)) { AddActivitySheet(model: AddPreview.add { $0.sport = .strength }) }
        .previewEnvironment(AddPreview.state)
}

#Preview("Add activity · too fast · de") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddActivitySheet(model: AddPreview.add {
            $0.sport = .running
            $0.distanceText = "60"
            $0.effort = 7
        })
    }
    .previewEnvironment(AddPreview.state, scheme: .light)
    .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Add activity · AX3") {
    Color.clear.sheet(isPresented: .constant(true)) { AddActivitySheet(model: AddPreview.add { $0.effort = 6 }) }
        .previewEnvironment(AddPreview.state)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Edit activity · recorded") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddActivitySheet(model: AddActivityModel(env: AddPreview.state.env, editing: AddPreview.recordedRun, merged: false))
    }
    .previewEnvironment(AddPreview.state)
}
