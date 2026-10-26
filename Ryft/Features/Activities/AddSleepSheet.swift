import SwiftUI

/// Add sleep / Edit sleep (ui.md §3.7): when you went to bed and woke up, the time between them live, the reasons
/// under the pickers, and that the entry is "added by you" (the tracker's night wins later). Medium detent; large at
/// accessibility sizes.
struct AddSleepSheet: View {
    @State var model: AddSleepModel
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmsDelete = false
    @State private var announced: [AddSleepModel.Issue] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.trackerHasNight {
                        InlineMessage(message: String(localized: "Sleep was already recorded by \(MyDayAssembler.appleHealth).",
                                                      comment: "Add sleep: the platform has a night for this day; its source."),
                                      systemImage: "bed.double", identifier: "addSleep.exists")
                    } else {
                        form
                    }
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text(verbatim: model.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel").foregroundStyle(Theme.textPrimary) }
                        .accessibilityIdentifier("addSleep.cancel")
                }
                if !model.trackerHasNight {
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
                        .accessibilityIdentifier("addSleep.save")
                    }
                }
            }
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
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("addSleep.sheet")
        // The wake day's night is checked against its detail; one not on this iPhone is loaded first.
        .task(id: model.targetDay) { await model.checkTargetDay() }
        .onChange(of: model.issues) { _, issues in
            let new = issues.filter { !announced.contains($0) }
            announced = issues
            if let first = new.first { AccessibilityNotification.Announcement(AddSleepModel.message(first)).post() }
        }
    }

    @ViewBuilder
    private var form: some View {
        // True for any wake day the pickers allow, not only last night.
        Text("For a night no tracker recorded.", comment: "Add sleep: what the sheet is for, for any night.")
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                picker(Text("Went to bed"), selection: $model.bed,
                       in: DayFormat.shift(model.earliestWake, days: -1)...model.now, id: "addSleep.bed")
                Divider().overlay(Theme.separator)
                picker(Text("Woke up"), selection: $model.wake, in: model.earliestWake...model.now, id: "addSleep.wake")
                ForEach(model.issues, id: \.self) { issue in
                    IssueLine(text: AddSleepModel.message(issue)).accessibilityIdentifier("addSleep.issue.\(issue)")
                }
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("Time asleep \(MyDayText.keepTogether(Fmt.duration(seconds: model.duration)))")
                .font(.ryft(.headline))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text("Time in bed. RYFT can't see your sleep stages for this entry.",
                 comment: "Add sleep: the duration is the time in bed; no stages for a typed-in night.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // On the combined element: a child's identifier is lost in it.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("addSleep.duration")
        Label {
            Text("It's marked “added by you”. If your tracker records this night later, RYFT uses the tracker's data instead.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "pencil")
        }
        .font(.ryft(.caption))
        .foregroundStyle(Theme.textSecondary)
        if model.isEditing {
            Button(role: .destructive) { confirmsDelete = true } label: {
                Text("Delete this entry", comment: "Edit sleep: delete the night the user added.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.alert)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addSleep.delete")
        }
    }

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
                .tint(Theme.accent)
                .accessibilityIdentifier(id)
        }
    }
}

// MARK: - previews

@MainActor
private enum SleepPreview {
    static let state = AppState.preview(flags: [.todayMyDay: true, .activitiesManual: true])
}

#Preview("Add sleep · dark") {
    Color.clear.sheet(isPresented: .constant(true)) { AddSleepSheet(model: AddSleepModel(env: SleepPreview.state.env, day: .now)) }
        .previewEnvironment(SleepPreview.state)
}

#Preview("Add sleep · light · de") {
    Color.clear.sheet(isPresented: .constant(true)) { AddSleepSheet(model: AddSleepModel(env: SleepPreview.state.env, day: .now)) }
        .previewEnvironment(SleepPreview.state, scheme: .light)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Add sleep · invalid") {
    Color.clear.sheet(isPresented: .constant(true)) {
        let model = AddSleepModel(env: SleepPreview.state.env, day: .now)
        model.wake = model.bed.addingTimeInterval(1_800)
        return AddSleepSheet(model: model)
    }
    .previewEnvironment(SleepPreview.state)
}

#Preview("Add sleep · tracker has the night") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddSleepSheet(model: AddSleepModel(env: SleepPreview.state.env, day: .now, night: { _ in .recorded }))
    }
    .previewEnvironment(SleepPreview.state)
}
