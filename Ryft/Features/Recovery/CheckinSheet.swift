import SwiftUI

struct CheckinSheet: View {
    @Bindable var model: CheckinSheetModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(Text("Morning check-in", comment: "Title of the morning check-in sheet."), closeLabel: Text("Cancel")) {
            PillButton(Text("Save"), size: .compact, systemImage: PillButton.Icon.confirm, busy: model.saving) {
                guard await model.save() else { return }
                if model.consentNotice != nil {
                    // Let the inline refusal appear before the app presents the consent gate.
                    try? await Task.sleep(for: .seconds(1))
                }
                dismiss()
            }
            .disabled(!model.canSave)
            .accessibilityIdentifier("checkin.save")
        } pinned: {
            if let notice = model.consentNotice {
                InlineMessage(message: notice, systemImage: "hand.raised", identifier: "checkin.consent")
            } else if let error = model.error {
                InlineMessage(message: error.message, systemImage: "exclamationmark.circle", details: error.details,
                              identifier: "checkin.error")
            } else if let validation = model.validation {
                InlineMessage(message: validation.message, systemImage: "clock", identifier: "checkin.validation", announces: false)
            }
        } content: {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                SleepDial(bed: $model.bed, wake: $model.wake, duration: model.duration)
                    .frame(maxWidth: .infinity)
                rating(Text("How well did you sleep?", comment: "Morning check-in sleep quality question."),
                       value: $model.quality, word: CheckinSheetModel.qualityWord, identifier: "checkin.quality")
                rating(Text("How recovered do you feel?", comment: "Morning check-in freshness question."),
                       value: $model.freshness, word: CheckinSheetModel.freshnessWord, identifier: "checkin.freshness")
                VStack(alignment: .leading, spacing: Theme.Metrics.itemSpacing) {
                    heading(Text("Sore muscles?", comment: "Morning check-in soreness question."))
                    SegmentedPicker(selection: $model.soreness, options: [false, true], look: .inkFill) { sore in
                        sore ? String(localized: "Yes", comment: "Yes answer to the soreness question.")
                            : String(localized: "No", comment: "No answer to the soreness question.")
                    }
                    .accessibilityIdentifier("checkin.soreness")
                }
                Button {
                    model.skip()
                    dismiss()
                } label: {
                    (model.canSkip ? Text("Skip") : Text("Cancel"))
                        .font(.ryft(.button))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("checkin.skip")
            }
            .disabled(model.saving || model.consentNotice != nil)
        }
        .closeDisabled(model.saving)
        .interactiveDismissDisabled(model.saving)
        .presentationDetents([.large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("checkin.sheet")
        .onAppear { model.opened() }
        .onChange(of: model.bed) { _, _ in model.clearError() }
        .onChange(of: model.wake) { _, _ in model.clearError() }
        .onChange(of: model.quality) { _, _ in model.clearError() }
        .onChange(of: model.freshness) { _, _ in model.clearError() }
        .onChange(of: model.soreness) { _, _ in model.clearError() }
    }

    private func rating(_ title: Text, value: Binding<Int?>, word: @escaping @MainActor (Int) -> String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.itemSpacing) {
            heading(title).accessibilityHidden(true)
            EffortScale(value: value, label: title, word: word, identifier: identifier)
        }
    }

    private func heading(_ title: Text) -> some View {
        title.font(.ryft(.headline))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Morning check-in sheet · AX3") {
    let store = RecoveryCheckinStore(env: .preview(flags: [.recoveryCheckin: true]))
    let status = RecoveryStatus(date: store.today, source: .none, confidence: nil, recoveryScore: nil, needsCheckin: true,
                                checkin: nil, suggestedBedtime: "22:10", suggestedWakeTime: "05:40", suggestionBasis: .checkins7d)
    CheckinSheet(model: CheckinSheetModel(store: store, status: status, canSkip: true))
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility3)
}
