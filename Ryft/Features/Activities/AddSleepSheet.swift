import SwiftUI

/// Add sleep / Edit sleep (Nocturne PR 6 B §10.2, `b-20`): the sheet header (the Cancel circle, the title, a compact Save),
/// when you went to bed and woke up as chips, the time between them live, the reasons under the times, and that the entry is
/// "added by you" (the tracker's night wins later). Editing adds Delete this entry. Medium detent; large from xLarge.
/// Saving writes on this iPhone first, so it works the same offline.
struct AddSleepSheet: View {
    @State var model: AddSleepModel
    var onSaved: () -> Void = {}
    /// Save couldn't write on this iPhone: the banner on top, with Try again. Previews and shots may start with it.
    @State var saveFailed = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmsDelete = false
    @State private var announced: [AddSleepModel.Issue] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = ActivitiesLayout.sleepValueSize

    /// The save error's identifier (it comes first, before the form).
    private static let saveErrorID = "addSleep.saveError"
    /// The scroll view's top, above the top padding: scrolled to with the save error, so the page is at rest and the pinned
    /// header's edge doesn't cut the error's top (as `AddActivitySheet.formTopID`).
    static let formTopID = "addSleep.formTop"

    /// From xLarge the form doesn't fit the medium detent: it opens large.
    static func detents(for typeSize: DynamicTypeSize) -> Set<PresentationDetent> {
        typeSize >= .xLarge ? [.large] : [.medium, .large]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id(Self.formTopID)
                        VStack(alignment: .leading, spacing: 0) {
                            if model.trackerHasNight {
                                InlineMessage(message: String(localized: "Sleep was already recorded by \(MyDayAssembler.appleHealth).",
                                                              comment: "Add sleep: the platform has a night for this day; its source."),
                                              systemImage: "bed.double", identifier: "addSleep.exists")
                            } else {
                                if saveFailed {
                                    saveError.padding(.bottom, ActivitiesLayout.sleepIntroGap)
                                }
                                form
                            }
                        }
                        .padding(.horizontal, Theme.Metrics.screenPadding)
                        .padding(.top, ActivitiesLayout.headerGap)
                        .padding(.bottom, ActivitiesLayout.bottomPadding)
                    }
                }
                .scrollIndicators(.hidden)
                .underPinnedHeader(gap: ActivitiesLayout.headerGap)
                // Save is at the top, the form may be scrolled: bring the reason, the first block, into view at rest.
                .onChange(of: saveFailed) { _, failed in
                    guard failed else { return }
                    withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick)) {
                        scroll.scrollTo(Self.formTopID, anchor: .top)
                    }
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .confirmationDialog(Text("Delete this sleep entry?"), isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button(role: .destructive) {
                model.delete()
                onSaved()
                dismiss()
            } label: {
                Text("Delete", comment: "Confirms deleting an activity or a night the user added.")
            }
            Button(role: .cancel) {} label: { Text("Keep", comment: "Cancels deleting an activity or a night.") }
        } message: {
            Text("Your scores for that night are recalculated.", comment: "Delete a night the user added: what happens.")
        }
        .presentationDetents(Self.detents(for: typeSize))
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .accessibilityIdentifier("addSleep.sheet")
        // The wake day's night is checked against its detail; one not on this iPhone is loaded first.
        .task(id: model.targetDay) { await model.checkTargetDay() }
        .onChange(of: model.issues) { _, issues in
            let new = issues.filter { !announced.contains($0) }
            announced = issues
            if let first = new.first { AccessibilityNotification.Announcement(AddSleepModel.message(first)).post() }
        }
    }

    // MARK: header

    /// The Cancel circle ("Close" where the tracker has the night: nothing to discard) · "Add sleep" / "Edit sleep" · Save
    /// (none where the tracker has the night): off until the night is valid and once it saved, its VoiceOver hint the first
    /// reason; busy while it writes.
    private var header: some View {
        // nil: the sheet header's "Close".
        SheetHeader(Text(verbatim: model.title), closeLabel: model.trackerHasNight ? nil : Text("Cancel")) {
            if !model.trackerHasNight {
                PillButton(Text("Save"), size: .compact, busy: model.isSaving) { save() }
                    .disabled(!model.issues.isEmpty || model.didSave)
                    .accessibilityHint(Text(verbatim: model.issues.first.map(AddSleepModel.message) ?? ""))
                    .accessibilityIdentifier("addSleep.save")
                    // A compact pill keeps its one line (`SheetHeader`).
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .accessibilityShowsLargeContentViewer()
            }
        }
        .padding(.horizontal, SheetHeaderSpec.sidePadding)
        .padding(.top, SheetHeaderSpec.topInset)
    }

    private func save() {
        // Once saved, a second tap (the sheet is closing) does nothing.
        guard model.canSave else { return }
        if model.save() {
            saveFailed = false
            onSaved()
            dismiss()
        } else {
            saveFailed = true
            AccessibilityNotification.Announcement(AddActivitySheet.saveErrorMessage).post()
        }
    }

    private var saveError: some View {
        InlineMessage(message: AddActivitySheet.saveErrorMessage, systemImage: "exclamationmark.circle", retry: { save() },
                      identifier: Self.saveErrorID)
    }

    // MARK: form

    @ViewBuilder
    private var form: some View {
        // True for any wake day the pickers allow, not only last night.
        Text("For a night no tracker recorded.", comment: "Add sleep: what the sheet is for, for any night.")
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        GroupedCard {
            chipRow(Text("Went to bed"),
                    date: Text("Date you went to bed", comment: "VoiceOver: Add sleep's chip for the bedtime's day."),
                    time: Text("Time you went to bed", comment: "VoiceOver: Add sleep's chip for the bedtime."),
                    selection: $model.bed, in: DayFormat.shift(model.earliestWake, days: -1)...model.now, id: "addSleep.bed")
            chipRow(Text("Woke up"),
                    date: Text("Date you woke up", comment: "VoiceOver: Add sleep's chip for the wake-up's day."),
                    time: Text("Time you woke up", comment: "VoiceOver: Add sleep's chip for the wake-up time."),
                    selection: $model.wake, in: model.earliestWake...model.now, id: "addSleep.wake")
        }
        .padding(.top, ActivitiesLayout.sleepIntroGap)
        ForEach(model.issues, id: \.self) { issue in
            IssueLine(text: AddSleepModel.message(issue)).accessibilityIdentifier("addSleep.issue.\(issue)")
        }
        duration
            .padding(.top, ActivitiesLayout.sleepDurationGap)
        Text("It's marked “added by you”. If your tracker records this night later, RYFT uses the tracker's data instead.")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, ActivitiesLayout.sleepNoteGap)
        if model.isEditing {
            PillButton(Text("Delete this entry", comment: "Edit sleep: delete the night the user added."), style: .destructive) {
                confirmsDelete = true
            }
            .accessibilityIdentifier("addSleep.delete")
            .padding(.top, ActivitiesLayout.tilesGap)
        }
    }

    /// Went to bed or Woke up: the label and two chips, the date and the time, each named for VoiceOver. The date chip keeps
    /// the row's identifier; the time chip adds `.time`.
    private func chipRow(_ label: Text, date: Text, time: Text, selection: Binding<Date>, in range: ClosedRange<Date>,
                         id: String) -> some View {
        ValueChipRow(label) {
            ValueChip(date, date: selection, in: range, displayedComponents: .date)
                .accessibilityIdentifier(id)
            ValueChip(time, date: selection, in: range, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("\(id).time")
        }
    }

    /// "Time asleep" and "8h 00m" (24 Light) on one baseline, the caption under them; one element for VoiceOver.
    private var duration: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: ActivitiesLayout.sleepValueGap) { durationLabel; durationValue }
                VStack(alignment: .leading, spacing: 2) { durationLabel; durationValue }
            }
            Text("Time in bed. RYFT can't see your sleep stages for this entry.",
                 comment: "Add sleep: the duration is the time in bed; no stages for a typed-in night.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // On the combined element: a child's identifier is lost in it.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("addSleep.duration")
    }

    private var durationLabel: some View {
        Text("Time asleep").ryftLabelStyle()
    }

    private var durationValue: some View {
        Text(verbatim: Fmt.duration(seconds: model.duration))
            .font(.ryftNumber(size: valueSize, weight: .light))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(Text(verbatim: MyDayRow.spokenDuration(model.duration)))
    }
}

// MARK: - previews (dark only)

@MainActor
private enum SleepPreview {
    static let state = AppState.preview(flags: [.todayMyDay: true, .activitiesManual: true])

    /// A night added on this iPhone for yesterday's wake day, 23:10 to 06:50.
    static var edited: AddSleepModel {
        let calendar = Calendar.current
        let wakeDay = DayFormat.shift(calendar.startOfDay(for: .now), days: -1)
        let bed = calendar.date(bySettingHour: 23, minute: 10, second: 0, of: DayFormat.shift(wakeDay, days: -1)) ?? wakeDay
        let wake = calendar.date(bySettingHour: 6, minute: 50, second: 0, of: wakeDay) ?? wakeDay
        guard let night = state.env.activities.saveSleep(day: DayFormat.string(from: wakeDay), bed: bed, wake: wake) else {
            return AddSleepModel(env: state.env, day: .now)
        }
        return AddSleepModel(env: state.env, editing: night)
    }
}

#Preview("Add sleep") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddSleepSheet(model: AddSleepModel(env: SleepPreview.state.env, day: .now)).presentedRoot()
    }
        .previewEnvironment(SleepPreview.state)
}

#Preview("Edit sleep") {
    Color.clear.sheet(isPresented: .constant(true)) { AddSleepSheet(model: SleepPreview.edited).presentedRoot() }
        .previewEnvironment(SleepPreview.state)
}

#Preview("Add sleep · invalid") {
    Color.clear.sheet(isPresented: .constant(true)) {
        let model = AddSleepModel(env: SleepPreview.state.env, day: .now)
        model.wake = model.bed.addingTimeInterval(1_800)
        return AddSleepSheet(model: model).presentedRoot()
    }
    .previewEnvironment(SleepPreview.state)
}

#Preview("Add sleep · couldn't save") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddSleepSheet(model: AddSleepModel(env: SleepPreview.state.env, day: .now), saveFailed: true)
            .presentedRoot()
    }
    .previewEnvironment(SleepPreview.state)
}

#Preview("Add sleep · tracker has the night") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddSleepSheet(model: AddSleepModel(env: SleepPreview.state.env, day: .now, night: { _ in .recorded }))
            .presentedRoot()
    }
    .previewEnvironment(SleepPreview.state)
}

#Preview("Add sleep · AX3") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddSleepSheet(model: AddSleepModel(env: SleepPreview.state.env, day: .now)).presentedRoot()
    }
        .previewEnvironment(SleepPreview.state)
        .environment(\.dynamicTypeSize, .accessibility3)
}
