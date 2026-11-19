import SwiftUI

// MARK: - body settings (shared by onboarding, Sleep and Profile)

/// Which setting's editor is open.
enum BodySetting: String, Identifiable {
    case sleepBase, maxHR
    var id: String { rawValue }
}

extension View {
    /// The editor for `item` as a sheet.
    func bodySettingSheet(_ item: Binding<BodySetting?>, editor: BodySettingsEditor) -> some View {
        sheet(item: item) { setting in
            NavigationStack {
                switch setting {
                case .sleepBase: BaselineSleepNeedForm(editor: editor, showsClose: true)
                case .maxHR: MaxHeartRateForm(editor: editor, showsClose: true)
                }
            }
            .presentationDetents([.large])
            .presentedRoot()
        }
    }
}

/// A big value between − and +; VoiceOver adjusts it by swiping up and down.
struct SettingStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let label: LocalizedStringKey
    let text: (Int) -> String
    /// The − and + grow with the text.
    @ScaledMetric(relativeTo: .title) private var buttonSize: CGFloat = 48
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func change(by delta: Int) {
        withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick)) {
            value = min(range.upperBound, max(range.lowerBound, value + delta))
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            button("minus", enabled: value > range.lowerBound) { change(by: -step) }
            Text(text(value))
                .font(.ryft(.numberLarge))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: Double(value)))
                .frame(minWidth: 150)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            button("plus", enabled: value < range.upperBound) { change(by: step) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(text(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(by: step)
            case .decrement: change(by: -step)
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(.title3, weight: .semibold))
                .frame(width: buttonSize, height: buttonSize)
                .background(Theme.surfaceRaised, in: Circle())
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Baseline sleep need: 15-minute steps, 4–12 h. In a sheet (`showsClose`) or pushed from
/// Sleep's need breakdown.
struct BaselineSleepNeedForm: View {
    let editor: BodySettingsEditor
    var showsClose = false
    @Environment(\.dismiss) private var dismiss
    @State private var draft = BodySettingsEditor.defaultSleepBase
    /// Edited by hand: no longer follows the saved value.
    @State private var touched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingStepper(value: drafted, range: BodySettingsEditor.sleepBaseRange, step: BodySettingsEditor.sleepBaseStep,
                             label: "Baseline sleep need") { Fmt.duration(minutes: $0) }
                    .padding(.vertical, 8)
                if let source = editor.sleepBaseSourceText {
                    Label(source, systemImage: "info.circle")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("Each night's sleep need starts from this baseline, plus top-ups for strain and sleep debt, minus naps. RYFT adjusts it from your nights unless you set it.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if editor.canUseLearnedBase {
                    Button(editor.usesLearnedTitle) {
                        Task {
                            await editor.useLearnedSleepBase()
                            reset()
                        }
                    }
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .disabled(editor.isBusy)
                }
                SettingSaveFooter(editor: editor)
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("Baseline sleep need"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { SheetTitle(text: "Baseline sleep need") }
            if showsClose {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await editor.setSleepBase(draft)
                        reset()
                    }
                }
                .disabled(draft == editor.sleepBase || editor.isBusy || !editor.canSave)
                    .accessibilityIdentifier("sleepBase.save")
            }
        }
        .onAppear {
            editor.begin()
            reset()
        }
        // The account arrived (or changed) while the form was open: follow it until edited.
        .onChange(of: editor.sleepBase) { if !touched { draft = editor.sleepBase } }
    }

    /// Back to what's saved: after a save (taken or refused) or going back to learned.
    private func reset() {
        draft = editor.sleepBase
        touched = false
    }

    private var drafted: Binding<Int> {
        Binding(get: { draft }, set: { draft = $0; touched = true })
    }
}

/// Maximum heart rate: 100–230 bpm.
struct MaxHeartRateForm: View {
    let editor: BodySettingsEditor
    var showsClose = false
    @Environment(\.dismiss) private var dismiss
    @State private var draft = BodySettingsEditor.defaultMaxHR
    @State private var touched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingStepper(value: drafted, range: BodySettingsEditor.maxHRRange, step: 1,
                             label: "Maximum heart rate") { "\($0) bpm" }
                    .padding(.vertical, 8)
                if let source = editor.maxHRSourceText {
                    Label(source, systemImage: "info.circle")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("Strain and heart-rate zones are measured against it. If you know yours from a test, set it here.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if editor.canUseMaxHREstimate {
                    Button("Use the estimate") {
                        Task {
                            await editor.useMaxHREstimate()
                            reset()
                        }
                    }
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .disabled(editor.isBusy)
                }
                SettingSaveFooter(editor: editor)
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("Maximum heart rate"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { SheetTitle(text: "Maximum heart rate") }
            if showsClose {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await editor.setMaxHR(draft)
                        reset()
                    }
                }
                .disabled(draft == editor.maxHR || editor.isBusy || !editor.canSave)
            }
        }
        .onAppear {
            editor.begin()
            reset()
        }
        .onChange(of: editor.maxHR) { if !touched { draft = editor.maxHR } }
    }

    private func reset() {
        draft = editor.maxHR
        touched = false
    }

    private var drafted: Binding<Int> {
        Binding(get: { draft }, set: { draft = $0; touched = true })
    }
}

/// Under an editor: a refusal, or after a save that past days keep their scores, with the
/// offer to rescore them.
private struct SettingSaveFooter: View {
    let editor: BodySettingsEditor

    var body: some View {
        if editor.saving {
            ProgressView().tint(Theme.accent)
        }
        if let error = editor.error {
            InlineMessage(message: error, systemImage: "exclamationmark.circle", details: editor.errorDetails)
                .accessibilityIdentifier("bodySettings.error")
        }
        if editor.savedChange || editor.rescoreStatus != nil {
            VStack(alignment: .leading, spacing: 10) {
                if editor.savedChange {
                    Label("Saved. Past days keep their scores until you rescore them.", systemImage: "checkmark.circle")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PrimaryButton(title: "Rescore the last 90 days", style: .secondary, busy: editor.rescoring) {
                    await editor.rescore()
                }
                .disabled(editor.saving)
                RescoreStatus(editor: editor)
            }
        }
    }
}

#Preview("Baseline sleep need · dark") {
    let state = AppState.preview()
    NavigationStack { BaselineSleepNeedForm(editor: BodySettingsEditor(state: state), showsClose: true) }
        .previewEnvironment(state)
}

#Preview("Baseline sleep need · de") {
    let state = AppState.preview()
    NavigationStack { BaselineSleepNeedForm(editor: BodySettingsEditor(state: state), showsClose: true) }
        .previewEnvironment(state)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Maximum heart rate · dark") {
    let state = AppState.preview()
    NavigationStack { MaxHeartRateForm(editor: BodySettingsEditor(state: state), showsClose: true) }
        .previewEnvironment(state)
}
