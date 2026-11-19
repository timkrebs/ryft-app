import SwiftUI

// MARK: - body settings (shared by onboarding, Sleep and Profile)

/// Which setting's editor is open.
enum BodySetting: String, Identifiable {
    case sleepBase, maxHR
    var id: String { rawValue }
}

extension View {
    /// The editor for `item` as a sheet: its own page with Close (Nocturne, PR 6 C §4.11). `rescores: false` in onboarding:
    /// there are no past days to rescore yet, so the page offers none.
    func bodySettingSheet(_ item: Binding<BodySetting?>, editor: BodySettingsEditor, rescores: Bool = true) -> some View {
        sheet(item: item) { setting in
            Group {
                switch setting {
                case .sleepBase: BaselineSleepNeedForm(editor: editor, showsClose: true, rescores: rescores)
                case .maxHR: MaxHeartRateForm(editor: editor, showsClose: true, rescores: rescores)
                }
            }
            .presentationDetents([.large])
        }
    }
}

/// The editors' numbers (Nocturne, PR 6 C §4.11; plain values, so tests assert numbers, not pixels).
enum BodySettingsLayout {
    /// The numeral (and its unit) → the source line, and the source line → the ruler.
    nonisolated static let numeralToSource: CGFloat = 8, sourceToRuler: CGFloat = 14
    /// The ruler's 36 pt box → the first block under it (a notice, or the paragraph).
    nonisolated static let rulerToContent: CGFloat = 24
    /// Between the blocks under the ruler: notices, groups, the paragraph (`GroupedListSpec.groupSpacing`).
    nonisolated static let blockSpacing: CGFloat = 18
    /// A group → the notice about it (`GroupedListSpec.footerGap`).
    nonisolated static let noticeGap: CGFloat = 8
    /// The baseline's numeral is at least 130 wide, so the circles stay put from "4:00" to "9:45".
    nonisolated static let baselineNumeralMinWidth: CGFloat = 130
    /// "bpm" under the heart rate's numeral.
    nonisolated static let unitGap: CGFloat = 2
    /// One tick per step, so the needle lands on a tick: 4–12 h in 15 minutes is 33; 100–230 bpm in 5 is 27.
    nonisolated static let baselineTicks = 33, maxHRTicks = 27
    /// The "Use …" row's glyph.
    nonisolated static let estimateGlyph = "arrow.uturn.backward"

    /// The "Use …" row dims while it can't be used, never while its own write runs (as the pill and the rescore row).
    nonisolated static func estimateOpacity(enabled: Bool, busy: Bool) -> Double {
        enabled || busy ? 1 : GroupedListSpec.disabledOpacity
    }
}

extension BodySetting {
    var title: Text {
        switch self {
        case .sleepBase: return Text("Baseline sleep need")
        case .maxHR: return Text("Maximum heart rate")
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .sleepBase: return BodySettingsEditor.sleepBaseRange
        case .maxHR: return BodySettingsEditor.maxHRRange
        }
    }

    var step: Int {
        switch self {
        case .sleepBase: return BodySettingsEditor.sleepBaseStep
        case .maxHR: return 1
        }
    }

    var tickCount: Int {
        switch self {
        case .sleepBase: return BodySettingsLayout.baselineTicks
        case .maxHR: return BodySettingsLayout.maxHRTicks
        }
    }

    /// The numeral's unlit template while nothing is drawn.
    var placeholder: String {
        switch self {
        case .sleepBase: return "0:00"
        case .maxHR: return "000"
        }
    }

    /// Save's identifier for UI tests (`sleepBase.save` as before the restyle).
    var saveIdentifier: String { "\(rawValue).save" }

    /// One step from `value` in `direction`, on the ruler's grid: from a value off it (the default 7:40, a learned 7:52) the
    /// first step goes to the grid line that way (7:45 up, 7:30 down), so the needle lands on a tick; then a step at a time.
    func stepped(_ value: Int, direction: Int) -> Int {
        let low = range.lowerBound, offset = value - low
        let next: Int
        if offset % step == 0 {
            next = value + direction.signum() * step
        } else {
            next = low + (offset / step + (direction > 0 ? 1 : 0)) * step
        }
        return min(range.upperBound, max(range.lowerBound, next))
    }

    /// The numeral: "7:45", "190".
    func numeral(_ value: Int) -> String {
        switch self {
        case .sleepBase: return Fmt.clock(minutes: value)
        case .maxHR: return "\(value)"
        }
    }

    /// The value with its unit, as text beside other words: "7:30", "190 bpm".
    func text(_ value: Int) -> String {
        switch self {
        case .sleepBase: return Fmt.clock(minutes: value)
        case .maxHR: return String(localized: "\(value) bpm")
        }
    }

    /// As VoiceOver says it: "7 hours 45 minutes", "185 beats per minute".
    func spoken(_ value: Int) -> String {
        switch self {
        case .sleepBase: return Fmt.spokenDuration(minutes: value)
        case .maxHR:
            return String(localized: "\(value) beats per minute",
                          comment: "VoiceOver: the Maximum heart rate editor's value, e.g. \"185 beats per minute\".")
        }
    }

    /// The ruler's labels: the ends and the middle of the range.
    var rulerLabels: [String] {
        switch self {
        case .sleepBase:
            return [String(localized: "4 h", comment: "Baseline sleep need editor: the ruler's start, four hours."),
                    String(localized: "8 h", comment: "Baseline sleep need editor: the ruler's middle, eight hours."),
                    String(localized: "12 h", comment: "Baseline sleep need editor: the ruler's end, twelve hours.")]
        case .maxHR:
            let r = BodySettingsEditor.maxHRRange
            return [String(localized: "\(r.lowerBound) bpm"), "\((r.lowerBound + r.upperBound) / 2)",
                    String(localized: "\(r.upperBound) bpm")]
        }
    }

    /// Under the ruler: what the setting does (today's sentences).
    var explanation: Text {
        switch self {
        case .sleepBase:
            // swiftlint:disable:next line_length
            return Text("Each night's sleep need starts from this baseline, plus top-ups for strain and sleep debt, minus naps. RYFT adjusts it from your nights unless you set it.")
        case .maxHR:
            return Text("Strain and heart-rate zones are measured against it. If you know yours from a test, set it here.")
        }
    }
}

/// What an editor shows for its draft value (Nocturne, PR 6 C §4.11): pure, so tests read the decisions without a view.
struct BodySettingContent: Equatable {
    /// The "Use …" row that goes back to RYFT's value: its title and, where RYFT has one to show, the value.
    struct Estimate: Equatable {
        let title: String
        let value: String?
        let spokenValue: String?
    }

    /// Why the account's values aren't here: the page says so, and the numeral is unlit.
    enum Unloaded: Equatable {
        /// Offline, with nothing cached.
        case offline
        /// Online, and the account hasn't come yet.
        case loading

        var message: String {
            switch self {
            case .offline:
                // swiftlint:disable:next line_length
                return String(localized: "You're offline and RYFT hasn't loaded your settings yet, so this shows the default. You can change it once you're back online.",
                              comment: "Body setting editors, offline with no account on this iPhone: the value is the default, Save is off.")
            case .loading:
                return String(localized: "RYFT hasn't loaded your settings yet, so this shows the default.",
                              comment: "Body setting editors, online while the account hasn't loaded yet: the value is the default, Save is off.")
            }
        }

        var systemImage: String { self == .offline ? "wifi.slash" : "info.circle" }
        var identifier: String { self == .offline ? "bodySettings.offline" : "bodySettings.notLoaded" }
    }

    /// The numeral; `nil` draws it unlit while the account isn't here (the default isn't the user's value), as the need
    /// sheet's "Not loaded yet" says.
    let numeral: String?
    let spoken: String
    /// The saved value (the account's, or the default while it isn't here).
    let saved: Int
    /// Where the saved value comes from, and the saved value while the numeral shows an unsaved one: "Set by you · saved 7:30".
    /// `nil` while the account isn't here.
    let source: String?
    /// `source` as VoiceOver reads it: "Set by you, saved 7 hours 30 minutes" (a clock would be read as a time of day).
    let spokenSource: String?
    /// The numeral differs from what is saved.
    let isChanged: Bool
    /// Save can go: changed, the account here (its values are the saved ones, not the defaults), signed in, nothing in flight.
    let canSave: Bool
    let estimate: Estimate?
    /// The account isn't here: the numeral is unlit, and a notice says why.
    let unloaded: Unloaded?
    /// The last save's failure when it was this setting's (`BodySettingsEditor.errorSetting`): another setting's failure
    /// (a max HR change made elsewhere) stays off this page, as the need sheet keeps it (PR 6 C review N7).
    let error: String?

    @MainActor
    init(_ setting: BodySetting, editor: BodySettingsEditor, draft: Int) {
        let loaded = editor.isLoaded
        numeral = loaded ? setting.numeral(draft) : nil
        spoken = loaded ? setting.spoken(draft) : String(localized: "Not loaded yet")
        let saved: Int
        let source: String?
        switch setting {
        case .sleepBase:
            saved = editor.sleepBase
            // Set by you: the learned value is on the "Use RYFT's estimate" row under it, not repeated here.
            source = editor.sleepBaseSource == .manual ? String(localized: "Set by you") : editor.sleepBaseSourceText
            estimate = editor.canUseLearnedBase
                ? Estimate(title: editor.usesLearnedTitle, value: editor.sleepBaseLearned.map { setting.text($0) },
                           spokenValue: editor.sleepBaseLearned.map { setting.spoken($0) })
                : nil
        case .maxHR:
            saved = editor.maxHR
            source = editor.maxHRSourceText
            // The platform's estimate isn't sent, so the row has no value (the phone computes none).
            estimate = editor.canUseMaxHREstimate ? Estimate(title: editor.usesMaxHREstimateTitle, value: nil, spokenValue: nil)
                : nil
        }
        self.saved = saved
        isChanged = draft != saved
        if loaded, let source {
            self.source = isChanged ? [source, Self.savedWords(setting.text(saved))].joined(separator: " · ") : source
            spokenSource = isChanged ? [source, Self.savedWords(setting.spoken(saved))].joined(separator: ", ") : source
        } else {
            self.source = nil
            spokenSource = nil
        }
        canSave = isChanged && loaded && editor.canSave && !editor.isBusy
        unloaded = loaded ? nil : editor.isOnline ? .loading : .offline
        error = editor.errorSetting == setting ? editor.error : nil
    }

    private static func savedWords(_ value: String) -> String {
        // swiftlint:disable:next line_length
        String(localized: "saved \(value)", comment: "Body setting editors, after the source while the value isn't saved: the saved one, \"saved 7:30\"; VoiceOver: \"saved 7 hours 30 minutes\".")
    }
}

/// Baseline sleep need: 15-minute steps, 4–12 h. A sheet's root from Profile and onboarding (`showsClose`), or pushed inside
/// Sleep's need sheet (Back).
struct BaselineSleepNeedForm: View {
    let editor: BodySettingsEditor
    var showsClose = false
    /// The rescore row under Saved (not in onboarding).
    var rescores = true

    var body: some View {
        BodySettingPage(setting: .sleepBase, editor: editor, showsClose: showsClose, rescores: rescores)
    }
}

/// Maximum heart rate: 100–230 bpm, one at a time. A sheet from Profile and onboarding.
struct MaxHeartRateForm: View {
    let editor: BodySettingsEditor
    var showsClose = false
    /// The rescore row under Saved (not in onboarding).
    var rescores = true

    var body: some View {
        BodySettingPage(setting: .maxHR, editor: editor, showsClose: showsClose, rescores: rescores)
    }
}

/// One editor in Nocturne (PR 6 C §4.11, D6C-11, D6C-14): the header with Close (or Back) · 22 · the numeral between Less and
/// More, one adjustable element · 8 · where the value comes from · 14 · the ruler with the Volt needle at the draft (hidden
/// from VoiceOver: it repeats the value) · 24 · the notices about the value (the account not here, a refusal, Saved and the
/// rescore under it) · the paragraph · the "Use …" row · Save pinned under the page.
///
/// A save sends `PATCH /v1/me` (`BodySettingsEditor`, which holds its state: a page opened while it's out shows "Saving…"
/// and its answer). Offline nothing is sent and it says so at once; a refusal, no answer or a server error says so in words
/// under the ruler and the numeral goes back to the saved value, so nothing reads as saved that wasn't. While the save is
/// out only the controls wait (the stepper, Save, the "Use …" row): the page scrolls, and Close, Back and the sheet's swipe
/// down leave it; the save goes on, the rows that open the editor say "Saving…", and a failure that arrives after the page
/// went is said where the user is (`BodySettingsEditor.errorMissed`). Save is off while nothing changed, while the account
/// isn't here, and while anything is in flight.
private struct BodySettingPage: View {
    let setting: BodySetting
    let editor: BodySettingsEditor
    let showsClose: Bool
    let rescores: Bool

    @State private var draft: Int
    /// Edited by hand (or opened on a value on its way): no longer follows the saved value.
    @State private var touched: Bool
    /// This page's token among the editor's open pages.
    @State private var page = UUID()

    init(setting: BodySetting, editor: BodySettingsEditor, showsClose: Bool, rescores: Bool) {
        self.setting = setting
        self.editor = editor
        self.showsClose = showsClose
        self.rescores = rescores
        let pending = editor.pending(setting)
        _draft = State(initialValue: pending ?? (setting == .sleepBase ? editor.sleepBase : editor.maxHR))
        _touched = State(initialValue: pending != nil)
    }

    private var content: BodySettingContent { BodySettingContent(setting, editor: editor, draft: draft) }
    private var savedValue: Int { setting == .sleepBase ? editor.sleepBase : editor.maxHR }
    /// This page's value is on its way: Save's pill says so.
    private var savingValue: Bool { editor.pending(setting) != nil }
    /// Going back to RYFT's value is on its way: the "Use …" row says so.
    private var savingEstimate: Bool { editor.writing == .estimate(setting) }

    var body: some View {
        let content = content
        // A sheet's root (Close) sets the sheet's presentation; pushed inside Sleep's need sheet (Back) it only keeps the
        // sheet's 26 pt top inset: setting the presentation again would move the grabber and the page down (C2's finding).
        SubpageScaffold(setting.title, navigation: showsClose ? .close() : .back(), isSheet: showsClose) {
            VStack(alignment: .leading, spacing: 0) {
                stepper(content)
                if let source = content.source {
                    Text(verbatim: source)
                        .font(.ryft(.label))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, BodySettingsLayout.numeralToSource)
                        .accessibilityLabel(Text(verbatim: content.spokenSource ?? source))
                        .accessibilityIdentifier("bodySettings.source")
                }
                RulerScale(range: Double(setting.range.lowerBound)...Double(setting.range.upperBound), value: Double(draft),
                           tickCount: setting.tickCount, labels: setting.rulerLabels,
                           accessibilityLabel: setting.title, accessibilityValue: Text(verbatim: content.spoken),
                           followingGap: BodySettingsLayout.rulerToContent)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("bodySettings.ruler")
                    .padding(.top, content.source == nil ? BodySettingsLayout.numeralToSource : BodySettingsLayout.sourceToRuler)
                VStack(alignment: .leading, spacing: BodySettingsLayout.blockSpacing) {
                    notices(content)
                    setting.explanation
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let estimate = content.estimate {
                        GroupedCard {
                            EstimateRow(estimate: estimate, busy: savingEstimate) {
                                Task { await useEstimate() }
                            }
                            .disabled((editor.isBusy && !savingEstimate) || !editor.canSave || !editor.isLoaded)
                        }
                    }
                }
                .padding(.top, BodySettingsLayout.rulerToContent)
            }
        }
        .pinnedBar {
            // Busy is the spinner; the title stays "Save" (VoiceOver: "Save, In progress"), as every pill (build plan §P5-1.2).
            PillButton(Text("Save"), systemImage: PillButton.Icon.confirm, busy: savingValue) {
                await save()
            }
            .disabled(!content.canSave && !savingValue)
            .accessibilityIdentifier(setting.saveIdentifier)
        }
        .safeAreaPadding(.top, showsClose ? 0 : SubpageSpec.sheetTopInset)
        .onAppear {
            editor.pageAppeared(page)
            if editor.pending(setting) == nil { reset() }
        }
        .onDisappear { editor.pageDisappeared(page) }
        // The account arrived (or changed, or RYFT was asked again) while the page was open: follow it until edited.
        .onChange(of: savedValue) { if !touched { draft = savedValue } }
        // A write this page didn't start (it opened while it was out) ended: back to what's saved.
        .onChange(of: editor.isWriting(setting)) { _, writing in if !writing { reset() } }
    }

    /// The numeral between Less and More: one adjustable element ("Baseline sleep need, 7 hours 45 minutes"), off while a
    /// write is in flight and while the account isn't here. A step from a value off the ruler's grid lands on it.
    private func stepper(_ content: BodySettingContent) -> some View {
        let binding = drafted
        let value = RyftStepperValue(text: content.numeral ?? setting.placeholder, spoken: content.spoken,
                                     canDecrement: draft > setting.range.lowerBound,
                                     canIncrement: draft < setting.range.upperBound) { direction in
            binding.wrappedValue = setting.stepped(binding.wrappedValue, direction: direction)
        }
        return HeroStepper(setting.title, value: value) {
            VStack(spacing: BodySettingsLayout.unitGap) {
                DotNumeral(content.numeral, glyphGap: DotNumeral.glyphGapDetail, placeholder: setting.placeholder,
                           accessibilityLabel: setting.title)
                    .frame(minWidth: setting == .sleepBase ? BodySettingsLayout.baselineNumeralMinWidth : nil)
                if setting == .maxHR {
                    Text("bpm", comment: "Under the Maximum heart rate editor's numeral: its unit, beats per minute.")
                        .font(.ryft(.label))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .disabled(editor.isBusy || !editor.isLoaded)
        .accessibilityIdentifier("bodySettings.stepper")
    }

    /// Under the ruler, about the value: the account not here; the last refusal; Saved, the rescore and how it went.
    @ViewBuilder private func notices(_ content: BodySettingContent) -> some View {
        if let unloaded = content.unloaded {
            InlineMessage(message: unloaded.message, systemImage: unloaded.systemImage, announces: false, readsAsOne: true)
                .accessibilityIdentifier(unloaded.identifier)
        }
        // This setting's failure only: the other editor's (a max HR change from About you) is on its own page.
        if let error = content.error {
            InlineMessage(message: error, systemImage: "exclamationmark.circle", caption: editor.errorDetails)
                .textSelection(.enabled)
                .accessibilityIdentifier("bodySettings.error")
        }
        if editor.hasSaved(setting) {
            InlineMessage(message: rescores ? String(localized: "Saved. Past days keep their scores until you rescore them.")
                                            : String(localized: "Saved.", comment: "Body setting editors in onboarding: saved (no past days to rescore yet)."),
                          systemImage: "checkmark", readsAsOne: true)
                .accessibilityIdentifier("bodySettings.saved")
        }
        if rescores, editor.hasSaved(setting) || editor.rescoreStatus != nil {
            VStack(alignment: .leading, spacing: BodySettingsLayout.noticeGap) {
                GroupedCard {
                    GroupedRow.action(editor.rescoring ? Text("Rescoring…", comment: "Body setting editors: the rescore row while it runs.")
                                                       : Text("Rescore the last 90 days"),
                                      systemImage: "arrow.clockwise", busy: editor.rescoring, identifier: "bodySettings.rescore") {
                        Task { await editor.rescore() }
                    }
                    // Rescored: nothing new to rescore until the next saved change.
                    .disabled(editor.saving || !editor.canSave || editor.rescored)
                }
                if let status = editor.rescoreStatus {
                    InlineMessage(message: status, systemImage: rescoreGlyph, caption: editor.rescoreDetails,
                                  readsAsOne: editor.rescoreDetails == nil)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("bodySettings.rescoreStatus")
                }
            }
        }
    }

    /// Failed: the error glyph; rescored and seen: the check; accepted and on its way: the clock.
    private var rescoreGlyph: String {
        if editor.rescoreFailed { return "exclamationmark.circle" }
        return editor.rescored ? "checkmark" : "clock"
    }

    // MARK: writes

    /// Back to what's saved: after a save (taken or not) or going back to RYFT's value.
    private func reset() {
        draft = savedValue
        touched = false
    }

    /// The numeral's binding: still while a write is in flight.
    private var drafted: Binding<Int> {
        Binding(get: { draft }, set: { value in
            guard !editor.isBusy else { return }
            draft = value
            touched = true
        })
    }

    private func save() async {
        guard !editor.isBusy else { return }
        switch setting {
        case .sleepBase: await editor.setSleepBase(draft)
        case .maxHR: await editor.setMaxHR(draft)
        }
        reset()
    }

    private func useEstimate() async {
        guard !editor.isBusy else { return }
        switch setting {
        case .sleepBase: await editor.useLearnedSleepBase()
        case .maxHR: await editor.useMaxHREstimate()
        }
        reset()
    }
}

/// "Use RYFT's estimate 7:52 ↺": an action row with a value (`GroupedRow.action` has no value slot), a button VoiceOver reads
/// as the title and the spoken value; busy, a spinner in the glyph's place and "In progress", at full strength (as the pill
/// and the rescore row are while theirs runs).
private struct EstimateRow: View {
    let estimate: BodySettingContent.Estimate
    let busy: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            if !busy { action() }
        } label: {
            GroupedRowLabel(Text(verbatim: estimate.title), value: estimate.value.map { Text(verbatim: $0) },
                            accessory: busy ? .spinner : .glyph(BodySettingsLayout.estimateGlyph))
        }
        .buttonStyle(.plain)
        .opacity(BodySettingsLayout.estimateOpacity(enabled: isEnabled, busy: busy))
        .groupedRowHairline()
        .accessibilityLabel(Text(verbatim: estimate.title))
        .accessibilityValue(busy ? GroupedRow.busyValue : Text(verbatim: estimate.spokenValue ?? ""))
        .accessibilityIdentifier("bodySettings.useEstimate")
    }
}

/// What the editors say when a change didn't go through, in words, with the status and request ID as the caption when RYFT
/// answered, never the raw error text (as Journal settings and Notifications do). How it failed is judged by what left the
/// phone (`SettingsWriteFailure`, shared with Notifications):
/// - offline: nothing was sent, so nothing changed;
/// - no answer (a timeout, a dropped connection): it may have saved, so RYFT is asked again;
/// - a server error (`5xx`): it's back as it was, and RYFT is asked again all the same;
/// - busy (`429`): nothing changed; try again in a minute;
/// - anything else (`409`, `403`): nothing changed; try again.
/// A `422` keeps the editor's own sentence naming the range (`BodySettingsEditor`).
struct BodySettingsFailure: Equatable {
    let kind: SettingsWriteFailure
    let message: String
    let details: String?

    /// A save (`PATCH /v1/me`).
    init(save error: Error) {
        kind = SettingsWriteFailure(error)
        message = kind.saveMessage
        details = error.diagnosticDetails
    }

    /// "Rescore the last 90 days" (`POST /v1/recompute`).
    init(rescore error: Error) {
        self.init(rescore: SettingsWriteFailure(error), details: error.diagnosticDetails)
    }

    /// A rescore that failed as `kind` (`.offline` when nothing was sent).
    init(rescore kind: SettingsWriteFailure, details: String?) {
        self.kind = kind
        switch kind {
        case .offline:
            message = String(localized: "You're offline, so nothing was rescored. Try again when you're back online.",
                             comment: "Body setting editors and Profile: Rescore the last 90 days, offline.")
        case .noAnswer:
            message = String(localized: "RYFT didn't answer, so the rescore may not have started. Try again in a moment.",
                             comment: "Body setting editors and Profile: Rescore the last 90 days, no answer (a timeout, a dropped connection).")
        case .serverError, .busy, .refused:
            message = String(localized: "RYFT couldn't rescore your days, so past days keep their scores. Try again in a moment.",
                             comment: "Body setting editors and Profile: Rescore the last 90 days, refused or a server error (5xx, 429, 403 …).")
        }
        self.details = details
    }
}

// MARK: - previews (dark only)

#Preview("Baseline sleep need") {
    let state = MockSleepNeedStates.state()
    BaselineSleepNeedForm(editor: BodySettingsEditor(state: state), showsClose: true)
        .previewEnvironment(state)
}

#Preview("Baseline sleep need · AX3") {
    let state = MockSleepNeedStates.state()
    BaselineSleepNeedForm(editor: BodySettingsEditor(state: state), showsClose: true)
        .previewEnvironment(state)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Baseline sleep need · offline, no account") {
    let state = MockSleepNeedStates.state(account: false, online: false)
    BaselineSleepNeedForm(editor: BodySettingsEditor(state: state), showsClose: true)
        .previewEnvironment(state)
}

#Preview("Baseline sleep need · not loaded yet") {
    let state = MockSleepNeedStates.state(account: false)
    BaselineSleepNeedForm(editor: BodySettingsEditor(state: state), showsClose: true)
        .previewEnvironment(state)
}

#Preview("Maximum heart rate") {
    let state = MockSleepNeedStates.state()
    MaxHeartRateForm(editor: BodySettingsEditor(state: state), showsClose: true)
        .previewEnvironment(state)
}
