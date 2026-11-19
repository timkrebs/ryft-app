import SwiftUI

/// The sheet's numbers (Nocturne, PR 6 C §4.12; plain values, so tests assert numbers).
enum SleepNeedLayout {
    /// The night's line → the numeral, the numeral → "needed for this night", that caption → the tile.
    nonisolated static let nightToNumeral: CGFloat = 14, numeralToCaption: CGFloat = 10, captionToTile: CGFloat = 20
    /// The tile (or the no-breakdown notice) → the sentence, and between the blocks under it.
    nonisolated static let blockSpacing: CGFloat = 18
}

/// What the sheet shows about one night (pure, so tests read it without a view).
struct SleepNeedSheetContent: Equatable {
    /// The numeral, "8:18"; `nil` draws it unlit (no need known).
    let numeral: String?
    /// "Sleep need, 8 hours 18 minutes"; "Sleep need, no value yet".
    let spokenNumeral: String
    /// `nil` for a night scored before the breakdown existed: the tile gives way to a notice.
    let breakdown: SleepNeedBreakdown?

    /// - Parameters:
    ///   - need: the night's breakdown (`DayDetail.sleep.need`).
    ///   - needMinutes: the night's need without one (`DailyScore.sleepNeedMin`).
    init(need: SleepNeed?, needMinutes: Int?) {
        breakdown = need.map(SleepNeedBreakdown.init)
        let minutes = need?.total ?? needMinutes
        numeral = minutes.map { Fmt.clock(minutes: $0) }
        spokenNumeral = minutes.map {
            String(localized: "Sleep need, \(Fmt.spokenDuration(minutes: $0))",
                   comment: "VoiceOver: the Sleep need sheet's numeral, e.g. \"Sleep need, 8 hours 18 minutes\".")
        } ?? String(localized: "Sleep need, no value yet",
                    comment: "VoiceOver: the Sleep need sheet's numeral while the night's need isn't known.")
    }

    /// The "Baseline sleep need" row: its value, as VoiceOver reads it, and its second line (the source). While the account
    /// isn't on this iPhone the value says "Not loaded yet", never the default as if it were saved; while a change is out it
    /// says "Saving…" (the value on its way is the editor's alone), then the saved value.
    struct BaselineRow: Equatable {
        let value: String
        let spokenValue: String
        let detail: String?

        @MainActor
        init(editor: BodySettingsEditor) {
            if editor.isWriting(.sleepBase) {
                value = BodySettingsEditor.savingWord
                spokenValue = value
                detail = nil
            } else if editor.isLoaded {
                value = Fmt.clock(minutes: editor.sleepBase)
                spokenValue = Fmt.spokenDuration(minutes: editor.sleepBase)
                // As the editor says it: set by hand is "Set by you" (the learned value is the editor's "Use RYFT's estimate").
                detail = editor.sleepBaseSource == .manual ? String(localized: "Set by you") : editor.sleepBaseSourceText
            } else {
                value = String(localized: "Not loaded yet")
                spokenValue = value
                detail = nil
            }
        }
    }
}

/// The night's sleep need, term by term (`base + strain + debt − nap credit`), and the baseline (the part that's yours to
/// set) one row away (Nocturne, PR 6 C §4.12, c-18, c-18b): the sheet header with Close · 22 · the night ("Last night · Sun,
/// Nov 15") · 14 · the need as the dot numeral · 10 · "needed for this night" · 20 · the sleep tile of tick rows (or, for a
/// night scored before the breakdown, a notice that says so) · 18 · the sentence · 18 · what the top-ups follow · 18 · the
/// "Baseline sleep need" row, which pushes its editor inside the sheet. Everything here is the cached night and the cached
/// account, so it reads the same offline; the editor says what it can't save, and a failure that arrives after its page went
/// (swiped back mid-save) is said under the row.
struct SleepNeedSheet: View {
    /// `nil` for nights scored before the breakdown existed.
    let need: SleepNeed?
    /// The need as Sleep's details card writes it ("8h 18m"): kept for the callers that only have the text; the numeral reads
    /// `need` or `needMinutes`.
    let total: String
    /// The night's need without a breakdown, minutes (`DailyScore.sleepNeedMin`).
    var needMinutes: Int?
    /// The night as Sleep's header names it ("Last night · Sun, Nov 15"); no line without one.
    var night: String?
    let editor: BodySettingsEditor

    @State private var editsBaseline = false

    init(need: SleepNeed?, total: String, needMinutes: Int? = nil, night: String? = nil, editor: BodySettingsEditor) {
        self.need = need
        self.total = total
        self.needMinutes = needMinutes
        self.night = night
        self.editor = editor
    }

    private var content: SleepNeedSheetContent { SleepNeedSheetContent(need: need, needMinutes: needMinutes) }

    var body: some View {
        let content = content
        NavigationStack {
            SubpageScaffold(Text("Sleep need"), navigation: .close(), isSheet: true) {
                VStack(alignment: .leading, spacing: 0) {
                    if let night {
                        Text(verbatim: night)
                            .font(.ryft(.label))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, SleepNeedLayout.nightToNumeral)
                    }
                    numeral(content)
                    VStack(alignment: .leading, spacing: SleepNeedLayout.blockSpacing) {
                        if let need, let breakdown = content.breakdown {
                            SleepNeedBar(need: need)
                            Text(verbatim: breakdown.sentence)
                                .font(.ryft(.callout))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(Text(verbatim: breakdown.spokenSentence))
                                .accessibilityIdentifier("sleepNeed.sentence")
                        } else {
                            InlineMessage(message: String(localized: "This night was scored before RYFT broke the need down."),
                                          systemImage: "info.circle", announces: false, readsAsOne: true)
                                .accessibilityIdentifier("sleepNeed.noBreakdown")
                        }
                        Text("Your baseline is yours to set. The top-ups follow yesterday's strain and your sleep debt; a nap lowers the next night's need.")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        baseline
                    }
                    .padding(.top, SleepNeedLayout.captionToTile)
                }
            }
            .navigationDestination(isPresented: $editsBaseline) { BaselineSleepNeedForm(editor: editor) }
        }
        .presentationDetents([.large])
    }

    /// The need as the dot numeral (Light from AX1), centred, and "needed for this night" under it.
    private func numeral(_ content: SleepNeedSheetContent) -> some View {
        VStack(spacing: SleepNeedLayout.numeralToCaption) {
            DotNumeral(content.numeral, glyphGap: DotNumeral.glyphGapDetail, placeholder: "0:00",
                       accessibilityLabel: Text(verbatim: content.spokenNumeral))
                .accessibilityIdentifier("sleepNeed.numeral")
            // The numeral's label says it: "Sleep need, 8 hours 18 minutes".
            Text("needed for this night", comment: "Sleep need sheet: the caption under the night's need numeral.")
                .font(.ryft(.label))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    /// "Baseline sleep need 7:30 ›", its source under the title; pushes the editor (Back returns here). A save's failure that
    /// arrived with the editor gone is under it.
    @ViewBuilder private var baseline: some View {
        let row = SleepNeedSheetContent.BaselineRow(editor: editor)
        GroupedCard {
            GroupedRow.push(Text("Baseline sleep need"), value: Text(verbatim: row.value),
                            detail: row.detail.map { Text(verbatim: $0) }, hint: Text("Opens the editor"),
                            identifier: "sleepNeed.changeBaseline") {
                editsBaseline = true
            }
            // The row reads its value and detail as one Text, which drops a spoken label on the value: "7 hours 30 minutes,
            // Set by you", not "7:30" read as a time of day.
            .accessibilityValue(Text(verbatim: [row.spokenValue, row.detail].compactMap(\.self).joined(separator: ", ")))
        }
        if editor.errorMissed, editor.errorSetting == .sleepBase, let error = editor.error {
            InlineMessage(message: error, systemImage: "exclamationmark.circle", caption: editor.errorDetails)
                .textSelection(.enabled)
                .accessibilityIdentifier("sleepNeed.baselineError")
        }
    }
}

extension SleepDetail {
    /// The night's need as terms (`sleep.need`), or `nil` for a night scored before the breakdown existed. API.md: such a
    /// night reports its whole need as `base` until it is rescored, and its score's `nap_min` is `null` (the field came with
    /// the breakdown, 2026-10-19; it is `0` without a nap otherwise). Without a score the need is taken as it is.
    func needBreakdown(score: DailyScore?) -> SleepNeed? {
        guard let need else { return nil }
        if let score, score.napMin == nil { return nil }
        return need
    }
}

/// Sleep Day's need card (Nocturne, PR 6 C §4.12, c-18c): one push row "Sleep need 8:18 ›" in a group, the sentence as the
/// group's footer. The row opens the need sheet; VoiceOver hears the need and the sentence in words.
struct SleepNeedCard: View {
    let need: SleepNeed
    let open: () -> Void

    var body: some View {
        let b = SleepNeedBreakdown(need)
        GroupedCard(footer: Text(verbatim: b.sentence).accessibilityLabel(Text(verbatim: b.spokenSentence))) {
            GroupedRow.push(Text("Sleep need"),
                            value: Text(verbatim: Fmt.clock(minutes: b.total))
                                .accessibilityLabel(Text(verbatim: Fmt.spokenDuration(minutes: b.total))),
                            hint: Text("Shows how your sleep need adds up, and your baseline to change"),
                            identifier: "sleep.need", action: open)
        }
    }
}

// MARK: - previews (dark only)

#Preview("Sleep need card") {
    ScrollView {
        SleepNeedCard(need: MockSleepNeedStates.need) {}
            .padding(20)
    }
    .background(Theme.background)
    .previewEnvironment(MockSleepNeedStates.state())
}
