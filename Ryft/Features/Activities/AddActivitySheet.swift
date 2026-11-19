import SwiftUI

/// Add activity / Edit activity (Nocturne PR 6 B §10.1, `b-19`): the sheet header (the Cancel circle, the title, a compact Save),
/// the sport row, Start / End / Duration, distance, perceived effort, notes and where strain comes from. Save is enabled only
/// when the form is valid, and every reason stands under its field. Saving writes on this iPhone and closes the sheet at once;
/// the upload follows (the day's row and the detail show it), so it works the same offline.
struct AddActivitySheet: View {
    @State var model: AddActivityModel
    /// After a save (the list cross-fades the new row in).
    var onSaved: () -> Void = {}
    /// Save couldn't write on this iPhone: the banner on top, with Try again. Previews and shots may start with it.
    @State var saveFailed = false

    @Environment(\.dismiss) private var dismiss
    @Environment(TrainCoordinator.self) private var coordinator
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focus: Field?
    @State private var picksSport = false
    @State private var announced: [AddActivityModel.Issue] = []
    @ScaledMetric(relativeTo: .title3) private var durationSize: CGFloat = ActivitiesLayout.durationValueSize

    private enum Field { case distance, notes }

    /// The save error's place in the scroll view.
    private static let saveErrorID = "addActivity.saveError"

    /// Save is off while a time, the distance or the notes need fixing (not while it saves: the pill is busy then); it also
    /// stays off once it saved, while the sheet closes (`didSave`).
    private var isValid: Bool { model.issues.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: ActivitiesLayout.blockSpacing) {
                            if saveFailed { saveError.id(Self.saveErrorID) }
                            sportGroup
                            if model.suggestsTrain {
                                strengthSuggestion
                            } else if model.sport == .strength, model.mode == .add {
                                strengthNote
                            }
                            whenGroup
                            if model.showsDistance { distanceGroup }
                            effortGroup
                            notesGroup
                            if model.sport != .strength { footer }
                        }
                        .padding(.horizontal, Theme.Metrics.screenPadding)
                        .padding(.top, ActivitiesLayout.headerGap)
                        .padding(.bottom, ActivitiesLayout.bottomPadding)
                        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: model.suggestsTrain)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    // Save is at the top, the form may be scrolled: bring the reason into view.
                    .onChange(of: saveFailed) { _, failed in
                        guard failed else { return }
                        withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick)) {
                            scroll.scrollTo(Self.saveErrorID, anchor: .top)
                        }
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { focus = nil } label: { Text("Done") }
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .navigationDestination(isPresented: $picksSport) {
                SportPicker(selection: $model.sport, sports: model.sports, recents: model.recents)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
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

    // MARK: header

    /// The Cancel circle (it discards what was typed) · "Add activity" / "Edit activity" · Save: off until the form is valid,
    /// its VoiceOver hint the first reason; busy while it writes.
    private var header: some View {
        SheetHeader(Text(verbatim: model.title), closeLabel: Text("Cancel")) {
            PillButton(Text("Save"), size: .compact, busy: model.isSaving) { save() }
                .disabled(!isValid || model.didSave)
                .accessibilityHint(Text(verbatim: model.issues.first.map(AddActivityModel.message) ?? ""))
                .accessibilityIdentifier("addActivity.save")
                // A compact pill keeps its one line (`SheetHeader`).
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .accessibilityShowsLargeContentViewer()
        }
        .padding(.horizontal, SheetHeaderSpec.sidePadding)
        .padding(.top, SheetHeaderSpec.topInset)
    }

    private func save() {
        // Once saved, a second tap (the sheet is closing) does nothing: no second activity, no error.
        guard model.canSave else { return }
        if model.save() {
            saveFailed = false
            onSaved()
            dismiss()
        } else {
            saveFailed = true
            // Every failed try is said, a Try again that fails too included.
            AccessibilityNotification.Announcement(Self.saveErrorMessage).post()
        }
    }

    static var saveErrorMessage: String {
        String(localized: "Couldn't save on this iPhone.",
               comment: "Add activity or Add sleep: Save couldn't write the entry on the phone; the form stays. Try again follows.")
    }

    /// Nothing could be written (signed out meanwhile, the row gone): the form stays as typed.
    private var saveError: some View {
        InlineMessage(message: Self.saveErrorMessage, systemImage: "exclamationmark.circle", retry: { save() },
                      identifier: Self.saveErrorID)
    }

    // MARK: sport

    /// The sport in a `surface` row (a 36 pt outline disc, the name, `chevron.up.chevron.down`), opening the sport picker. A
    /// merged activity keeps its sport: no chevron, not a button. A recorded one says its times and distance are measured.
    private var sportGroup: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.footerGap) {
            Button { picksSport = true } label: {
                HStack(spacing: ActivitiesLayout.sportRowSpacing) {
                    IconDisc(systemImage: model.sport.symbol)
                    Text(verbatim: model.sport.name)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if !model.sportLocked {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: ActivitiesLayout.chevronSize, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(ActivitiesLayout.chevronOpacity))
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, ActivitiesLayout.sportRowInset)
                .padding(.vertical, GroupedListSpec.textPadding)
                .frame(maxWidth: .infinity, minHeight: ActivitiesLayout.sportRowMinHeight, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: GroupedListSpec.cardRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: GroupedListSpec.cardRadius, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(model.sportLocked)
            .accessibilityLabel(Text("Sport, \(model.sport.name)", comment: "VoiceOver: the chosen sport."))
            .accessibilityHint(model.sportLocked ? Text(verbatim: "") : Text("Opens the list of sports",
                                                                             comment: "VoiceOver: the sport row opens the picker."))
            .accessibilityIdentifier("addActivity.sport")
            if model.measured {
                Text("Measured by RYFT. Times and distance can't be changed.",
                     comment: "Edit activity: a recorded activity's times and distance are fixed.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("addActivity.measured")
            }
        }
    }

    // MARK: times

    @ViewBuilder
    private var whenGroup: some View {
        if model.measured {
            measuredTimes
        } else {
            VStack(alignment: .leading, spacing: 0) {
                GroupedCard {
                    chipRow(Text("Start"), date: Text("Start date", comment: "VoiceOver: Add activity's chip for the start's day."),
                            time: Text("Start time", comment: "VoiceOver: Add activity's chip for the start's time."),
                            selection: $model.start, in: model.earliest...model.now, id: "addActivity.start")
                    chipRow(Text("End"), date: Text("End date", comment: "VoiceOver: Add activity's chip for the end's day."),
                            time: Text("End time", comment: "VoiceOver: Add activity's chip for the end's time."),
                            selection: $model.end, in: model.start...max(model.start, model.now), id: "addActivity.end")
                    durationRow
                }
                issueLines(model.issues.filter(Self.isTimeIssue))
            }
        }
    }

    private static func isTimeIssue(_ issue: AddActivityModel.Issue) -> Bool {
        [.endInFuture, .endBeforeStart, .longerThanADay, .startTooEarly].contains(issue)
    }

    /// Start or End: the label and two chips, the date and the time (the system's compact pickers behind them, named "Start
    /// date", "Start time" for VoiceOver). The chips go under the label from AX1, or where it wouldn't keep its line
    /// (`ValueChipRow`). The date chip keeps the row's identifier; the time chip adds `.time`.
    private func chipRow(_ label: Text, date: Text, time: Text, selection: Binding<Date>, in range: ClosedRange<Date>,
                         id: String) -> some View {
        ValueChipRow(label) {
            ValueChip(date, date: selection, in: range, displayedComponents: .date)
                .accessibilityIdentifier(id)
            ValueChip(time, date: selection, in: range, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("\(id).time")
        }
    }

    /// "Duration" · "(next day)" across midnight · "1h 00m" in 20 Light, on one line while they fit; from AX1, or where they
    /// don't (320 pt at xxxLarge across midnight), the value and "(next day)" go under the label, one under the other if need be.
    private var durationRow: some View {
        Group {
            if typeSize.isAccessibilitySize {
                durationStacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: ActivitiesLayout.durationGap) {
                        durationLabel
                        Spacer(minLength: ActivitiesLayout.durationGap)
                        if model.crossesMidnight { nextDay }
                        durationValue
                    }
                    durationStacked
                }
            }
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, GroupedListSpec.textPadding)
        .frame(maxWidth: .infinity, minHeight: ActivitiesLayout.durationRowMinHeight, alignment: .leading)
        .groupedRowHairline()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(durationSpoken)
        .accessibilityIdentifier("addActivity.duration")
    }

    private var durationStacked: some View {
        VStack(alignment: .leading, spacing: ActivitiesLayout.durationStackGap) {
            durationLabel
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: ActivitiesLayout.durationGap) {
                    durationValue
                    if model.crossesMidnight { nextDay }
                }
                VStack(alignment: .leading, spacing: ActivitiesLayout.durationStackGap) {
                    durationValue
                    if model.crossesMidnight { nextDay }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationLabel: some View {
        Text("Duration")
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var nextDay: some View {
        Text("(next day)", comment: "Add activity: the end is on the day after the start.")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var durationValue: some View {
        Text(verbatim: Fmt.duration(seconds: model.duration))
            .font(.ryftNumber(size: durationSize, weight: .light))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }

    /// "Duration, 1 hour", and across midnight "Duration, 1 hour, ends the next day": the "(next day)" said, not only shown.
    private var durationSpoken: Text {
        let spoken = MyDayRow.spokenDuration(model.duration)
        return model.crossesMidnight
            ? Text("Duration, \(spoken), ends the next day",
                   comment: "VoiceOver: the activity's duration, spelled out; its end is on the day after the start.")
            : Text("Duration, \(spoken)", comment: "VoiceOver: the activity's duration, spelled out.")
    }

    /// A recorded (or merged) activity: its times as measured, shown, not editable.
    private var measuredTimes: some View {
        GroupedCard {
            GroupedRow.value(Text("Start"), value: Text(verbatim: Fmt.time(model.start, locale: locale)))
            GroupedRow.value(Text("End"), value: Text(verbatim: Fmt.time(model.end, locale: locale)))
            GroupedRow.value(Text("Duration"), value: Text(verbatim: Fmt.duration(seconds: model.duration)))
        }
    }

    // MARK: distance

    private var distanceGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupedCard {
                if model.measured {
                    // The recording's distance, nothing to type.
                    GroupedRow.value(Text("Distance"), value: Text(verbatim: Fmt.distance(meters: model.draft.distanceM)))
                } else {
                    FormField(Text("Distance (optional)"), isFocused: focus == .distance, valueSize: .large) {
                        TextField(text: $model.distanceText,
                                  prompt: Text("Optional", comment: "Add activity: the distance field's placeholder.").fieldPrompt()) {
                            Text("Distance (optional)")
                        }
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .distance)
                        .accessibilityIdentifier("addActivity.distance")
                    } trailing: {
                        // Said after the field ("miles"), not only shown: the number alone doesn't say the unit.
                        Text(verbatim: ActivityFormat.distanceSymbol(locale))
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityLabel(Text(verbatim: Self.unitName(locale)))
                            .accessibilityIdentifier("addActivity.distanceUnit")
                    }
                }
            }
            if !model.measured {
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

    // MARK: effort, notes, footer

    private var effortGroup: some View {
        Card {
            VStack(alignment: .leading, spacing: ActivitiesLayout.effortLabelGap) {
                Text("Perceived effort (optional)").ryftLabelStyle()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                EffortScale(value: $model.effort)
            }
        }
    }

    private var notesGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(text: $model.notes, prompt: Text("Notes").fieldPrompt(), axis: .vertical) { Text("Notes") }
                .lineLimit(ActivitiesLayout.notesMinLines...6)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.textPrimary)
                .focused($focus, equals: .notes)
                .accessibilityIdentifier("addActivity.notes")
                .padding(.horizontal, GroupedListSpec.rowInset)
                .padding(.vertical, ActivitiesLayout.notesVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: GroupedListSpec.cardRadius, style: .continuous))
            notesCount
        }
    }

    /// From 400 characters: the count, and at the limit the reason.
    @ViewBuilder private var notesCount: some View {
        let count = model.notes.count
        if count >= 400 {
            HStack(alignment: .firstTextBaseline, spacing: ActivitiesLayout.issueGlyphGap) {
                if count >= AddActivityModel.notesLimit {
                    Image(systemName: "exclamationmark.circle")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityHidden(true)
                    Text(verbatim: AddActivityModel.message(.notesTooLong))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer(minLength: 0)
                Text(verbatim: "\(count) / \(AddActivityModel.notesLimit)")
                    .monospacedDigit()
                    .foregroundStyle(count >= AddActivityModel.notesLimit ? Theme.textPrimary : Theme.textTertiary)
            }
            .font(.ryft(.caption))
            .padding(.top, GroupedListSpec.footerGap)
            .accessibilityElement(children: .combine)
        }
    }

    /// The distance unit's name for VoiceOver: "miles" or "kilometers", the locale's word.
    static func unitName(_ locale: Locale) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitStyle = .long
        return formatter.string(from: ActivityFormat.distanceUnit(locale))
    }

    /// Where strain comes from, as a fact at the bottom: the effort rating only for a sport it makes strain for, so the
    /// detail never says otherwise (mobility: "Without heart rate there is no strain for this activity.").
    private var footer: some View {
        Text(model.effortMakesStrain
             ? String(localized: "Strain comes from the heart rate your tracker syncs for this time. Without it, your effort rating is used.")
             : String(localized: "Without heart rate there is no strain for this activity."))
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("addActivity.footer")
    }

    // MARK: strength (§10.1)

    /// Under the sport row while adding Strength: the sentence, Log in Train (an outline pill) and Add here anyway.
    private var strengthSuggestion: some View {
        Card {
            VStack(alignment: .leading, spacing: ActivitiesLayout.suggestionSpacing) {
                Text("Strength is best logged in Train. Your sets, reps and load count toward muscular load.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(Text("Log in Train"), style: .secondary) {
                    dismiss()
                    await coordinator.quickStart(.auto)
                }
                .accessibilityIdentifier("addActivity.logInTrain")
                Button { model.addsStrengthHere = true } label: {
                    Text("Add here anyway")
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minHitTarget)
                }
                .ryftLink()
                .accessibilityIdentifier("addActivity.addAnyway")
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("addActivity.strength")
    }

    /// After "Add here anyway": one line, and Log in Train still at hand.
    private var strengthNote: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: ActivitiesLayout.suggestionSpacing) {
                strengthNoteText
                Spacer(minLength: 0)
                strengthNoteLink
            }
            VStack(alignment: .leading, spacing: 0) {
                strengthNoteText
                strengthNoteLink
            }
        }
        .transition(.opacity)
    }

    private var strengthNoteText: some View {
        Text("Strength is best logged in Train.", comment: "Add activity: the collapsed Strength suggestion.")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var strengthNoteLink: some View {
        Button {
            dismiss()
            Task { await coordinator.quickStart(.auto) }
        } label: {
            Text("Log in Train")
        }
        .ryftLink()
        .accessibilityIdentifier("addActivity.strengthNote.logInTrain")
    }

    // MARK: reasons

    private func issueLines(_ issues: [AddActivityModel.Issue]) -> some View {
        ForEach(issues, id: \.self) { issue in
            IssueLine(text: AddActivityModel.message(issue)).accessibilityIdentifier("addActivity.issue.\(issue)")
        }
    }
}

/// A reason under a field (§10.1): `exclamationmark.circle` and the sentence, both `caption` in ink, 6 apart. No amber: the
/// glyph and the words carry it (L27), and the field above keeps its look.
struct IssueLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ActivitiesLayout.issueGlyphGap) {
            Image(systemName: "exclamationmark.circle")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, GroupedListSpec.footerGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - previews (dark only)

@MainActor
private enum AddPreview {
    static let state = AppState.preview(flags: [.todayMyDay: true, .activitiesManual: true])
    static func add(_ setup: (AddActivityModel) -> Void = { _ in }) -> AddActivityModel {
        let model = AddActivityModel(env: state.env, day: .now)
        setup(model)
        return model
    }
    static func filled(_ model: AddActivityModel) {
        model.sport = .running
        model.distanceText = "5.2"
        model.effort = 7
    }
    static var recordedRun: SportActivity { MockActivitiesSource.demo().first { $0.origin == .recorded } ?? MockActivitiesSource.demo()[0] }
}

#Preview("Add activity") {
    Color.clear.sheet(isPresented: .constant(true)) { AddActivitySheet(model: AddPreview.add()) }
        .previewEnvironment(AddPreview.state)
}

#Preview("Add activity · filled") {
    Color.clear.sheet(isPresented: .constant(true)) { AddActivitySheet(model: AddPreview.add(AddPreview.filled)) }
        .previewEnvironment(AddPreview.state)
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

#Preview("Add activity · strength, added here") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddActivitySheet(model: AddPreview.add {
            $0.sport = .strength
            $0.addsStrengthHere = true
        })
    }
    .previewEnvironment(AddPreview.state)
}

#Preview("Add activity · too fast") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddActivitySheet(model: AddPreview.add {
            AddPreview.filled($0)
            $0.distanceText = "60"
        })
    }
    .previewEnvironment(AddPreview.state)
}

#if DEBUG
#Preview("Add activity · saving") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddActivitySheet(model: AddPreview.add {
            AddPreview.filled($0)
            $0.previewSaving()
        })
    }
    .previewEnvironment(AddPreview.state)
}
#endif

#Preview("Add activity · couldn't save") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddActivitySheet(model: AddPreview.add(AddPreview.filled), saveFailed: true)
    }
    .previewEnvironment(AddPreview.state)
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
