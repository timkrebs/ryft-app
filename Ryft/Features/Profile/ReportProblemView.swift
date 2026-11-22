import SwiftUI

// MARK: - report a problem

/// Report a problem's numbers (Nocturne, PR 6 C §4.3; plain values, so tests assert numbers).
enum ReportProblemLayout {
    /// The message's text area: room for 4 lines at every size, so the field card is about 132 with its label at the
    /// default size (C §2.5) and the prompt is never cut off; it grows with what's typed.
    nonisolated static let messageLines = 4
    /// The counter inside the card, under the text: 12 above the card's bottom edge.
    nonisolated static let counterBottom: CGFloat = 12
    /// "What's included": 6 between its lines, 4 more above the health sentence, 14 under the last line.
    nonisolated static let includedSpacing: CGFloat = 6, includedSentenceGap: CGFloat = 4, includedBottom: CGFloat = 14
    /// The context chip: a capsule, 8 above and below the text, 14 at the sides.
    nonisolated static let chipVertical: CGFloat = 8, chipHorizontal: CGFloat = 14
    /// Sent and queued replace the form: 56 under the header (the scaffold's 22, then 34), a 72 pt circle with a 24 pt glyph,
    /// 22 to the headline (20 pt Light), 22 to Done.
    nonisolated static let outcomeTop: CGFloat = 34
    nonisolated static let outcomeCircle: CGFloat = 72, outcomeGlyph: CGFloat = 24, outcomeGap: CGFloat = 22
    nonisolated static let headlineSize: CGFloat = 20
    /// While the message has focus, Done and Send side by side in the pinned bar: 12 apart, equal widths (gate D5). From AX1
    /// they stack 8 apart (`PinnedBarSpec.spacing`).
    nonisolated static let barButtonGap: CGFloat = 12
}

/// Profile → About → Report a problem (ui.md §5; Nocturne, PR 6 C §4.3): the message, what it's about, and diagnostics that
/// help find the cause, never a health value. Pushed from Profile, or from an error's Details (`context`), pre-filled.
///
/// - The frame is `SubpageScaffold`; Send is the pinned primary (the pill's spinner while it goes, the title stays), with
///   "Reports are limited to 10 a day." under it. At the accessibility sizes that line (and the caption that says why Send
///   waits) ends the page instead, so the bar keeps only the pills and the page its room (C §2.9).
/// - While the message has focus the bar rides on the keyboard and holds Done beside Send (Nocturne gate D5): the way out of
///   the multi-line field is a visible pill where the thumb already is, and Send stays one tap away. There is no keyboard
///   toolbar: its floating Done covered the pinned Send on iOS 26 and later.
/// - A refusal shows above the form as a notice, with the message kept and "Copy message".
/// - `sent` and `queued` replace the form and the bar: a ring with a checkmark or a clock, the headline (VoiceOver goes to
///   it), Done. Queued says it is saved on this iPhone and goes out once online: it never claims to have been sent.
struct ReportProblemView: View {
    let model: ReportProblemModel
    var context: ReportContext?
    /// "What's included" open from the start (previews).
    var showsIncluded = false
    /// The message focused from the start, as after a tap on it: the bar's Done beside Send (previews).
    var startsEditing = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var editing: Bool
    @AccessibilityFocusState private var outcomeFocused: Bool
    @State private var includedOpen = false
    @State private var prepared = false
    @ScaledMetric(relativeTo: .title3) private var headlineSize: CGFloat = ReportProblemLayout.headlineSize
    /// The disclosure's chevron grows with its title, as a row's accessories do.
    @ScaledMetric(relativeTo: .callout) private var chevronScale: CGFloat = 1

    private var showsOutcome: Bool { model.result == .sent || model.result == .queued }

    var body: some View {
        SubpageScaffold(Text("Report a problem")) {
            Group {
                if showsOutcome {
                    outcome.transition(.opacity)
                } else {
                    form.transition(.opacity)
                }
            }
            .animation(Theme.Motion.respecting(reduceMotion), value: model.result)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !showsOutcome { sendBar }
        }
        .sensoryFeedback(.success, trigger: model.result) { _, new in new == .sent }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            includedOpen = showsIncluded
            // No keyboard on arrival: from Details the message is written already, and the keyboard would
            // cover what's attached.
            model.prepare(context)
            if startsEditing { editing = true }
        }
        .onChange(of: model.includeDiagnostics) { _, on in if !on { includedOpen = false } }
        .analyticsScreen(.reportProblem)
    }

    // MARK: compose

    private var form: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
            // The request ID shows only while it's attached.
            if let context = model.context { ReportContextChip(context: context, showsRequestID: model.includeDiagnostics) }
            notice
            Group {
                message
                categories
                diagnostics
            }
            .disabled(model.sending)
            if typeSize.isAccessibilitySize { barLines }
        }
    }

    /// The pinned bar's caption (why Send waits) and footnote; at the accessibility sizes they end the page instead.
    private var sendCaption: Text? {
        model.result == .rateLimited
            ? Text("You can send again tomorrow.",
                   comment: "Report a problem: the pinned bar's caption while today's 10 reports are used up.")
            : nil
    }

    private static var sendFootnote: Text { Text("Reports are limited to 10 a day.") }

    /// The bar's lines at the end of the page (accessibility sizes): the caption, then the footnote, flush left.
    private var barLines: some View {
        VStack(alignment: .leading, spacing: PinnedBarSpec.spacing) {
            if let sendCaption {
                sendCaption
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Self.sendFootnote
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The pinned bar: Send, and while the message has focus Done (D5). Below AX1 one row, Done leading and Send trailing,
    /// 12 apart and equal; from AX1 stacked, Send above Done (the primary first, as in every stacked bar). Without focus
    /// Send alone, full width. The row changes with `Theme.Motion.quick`, at once under Reduce Motion.
    private var sendBar: some View {
        let inBar = !typeSize.isAccessibilitySize
        return PinnedActionBar(caption: inBar ? sendCaption : nil, footnote: inBar ? Self.sendFootnote : nil) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: PinnedBarSpec.spacing) {
                        sendButton
                        if editing { doneButton }
                    }
                } else {
                    HStack(spacing: ReportProblemLayout.barButtonGap) {
                        if editing { doneButton }
                        sendButton
                    }
                }
            }
            .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: editing)
        }
    }

    /// Send: busy while it goes (the pill keeps its size and its title), disabled without a message, over the limit and
    /// after today's tenth report (the caption then says why; from AX1 at the page's end, with the footnote). It ends the
    /// editing first, so the bar is Send alone again while the report goes.
    private var sendButton: some View {
        PillButton(Text("Send"), systemImage: PillButton.Icon.send, busy: model.sending) {
            editing = false
            await model.send()
        }
        .disabled(!model.canSend && !model.sending)
        .accessibilityIdentifier("report.send")
    }

    /// Done while the message has focus: closes the keyboard, keeps what's typed. Never disabled: while a report goes the
    /// field has no focus, so Done isn't there.
    private var doneButton: some View {
        PillButton(Text("Done"), style: .secondary) { editing = false }
            .accessibilityIdentifier("report.done")
    }

    /// What stopped the report, with the message kept to copy.
    @ViewBuilder private var notice: some View {
        switch model.result {
        case .rateLimited?:
            refusal(String(localized: "You've reached today's limit of 10 reports. Your message is kept; try again tomorrow."),
                    systemImage: "clock", caption: model.resultDetails)
                .accessibilityIdentifier("report.rateLimited")
        case .rejected?:
            refusal(String(localized: "RYFT couldn't take this report. Copy your message and try again later."),
                    systemImage: "exclamationmark.circle", caption: model.resultDetails)
        case .saveFailed?:
            refusal(String(localized: "Couldn't save your report. Copy it and try again later."), systemImage: "exclamationmark.circle")
        case .signedOut?:
            refusal(String(localized: "You're signed out, so this report can't be sent. Your message is kept."),
                    systemImage: "person.crop.circle.badge.exclamationmark")
                .accessibilityIdentifier("report.signedOut")
        default:
            EmptyView()
        }
    }

    /// A refusal: the sentence, the status and request ID as its caption (selectable, for support), and "Copy message".
    private func refusal(_ sentence: String, systemImage: String, caption: String? = nil) -> some View {
        InlineMessage(message: sentence, systemImage: systemImage, caption: caption, identifier: "report.notice",
                      action: (String(localized: "Copy message"), { model.copyMessage() }))
            .textSelection(.enabled)
            .accessibilityElement(children: .contain)
    }

    /// The message: a field card (its label "Message" inside, the focus bar at its edge), the counter under the text once it
    /// nears the limit, and the privacy hint as the footer; over the limit the footer says so first, in words. The field
    /// keeps 4 lines' room at every size, so its prompt shows whole and a tap anywhere in it edits.
    private var message: some View {
        GroupedCard(footer: messageFooter) {
            FormField(Text("Message"), isFocused: editing) {
                TextField(text: Bindable(model).message,
                          prompt: Text("What happened? What did you expect?").fieldPrompt(),
                          axis: .vertical) {
                    Text("Message")
                }
                // A vertical field with a range keeps its lower bound's room (`reservesSpace` takes only a fixed limit).
                .lineLimit(ReportProblemLayout.messageLines...)
                .focused($editing)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityIdentifier("report.message")
            }
            if model.showsCount { counter }
        }
    }

    private var messageFooter: Text {
        model.isTooLong
            ? Text("Too long: a report takes up to 4,000 characters. Please don't type health values you'd rather keep private.",
                   comment: "Report a problem: the message card's footer while the message is over 4,000 characters.")
            : Text("Please don't type health values you'd rather keep private.")
    }

    /// "3812 / 4000" at the card's bottom right; over the limit in `warning`, and VoiceOver adds "Over the limit".
    private var counter: some View {
        Text("\(model.length) / 4000")
            .font(.ryft(.caption))
            .monospacedDigit()
            .foregroundStyle(model.isTooLong ? Theme.warning : Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.bottom, ReportProblemLayout.counterBottom)
            .accessibilityValue(model.isTooLong ? Text("Over the limit") : Text(verbatim: ""))
            .accessibilityIdentifier("report.count")
    }

    /// One choice: the checkmark on the chosen row, "selected" for VoiceOver.
    private var categories: some View {
        GroupedCard(Text("Category")) {
            ForEach(FeedbackCategory.allCases, id: \.self) { category in
                GroupedRow.select(Text(Self.title(category)), isSelected: model.category == category,
                                  identifier: "report.category.\(category.rawValue)") {
                    model.category = category
                }
            }
        }
    }

    static func title(_ category: FeedbackCategory) -> String {
        switch category {
        case .bug: return String(localized: "Something's broken")
        case .idea: return String(localized: "An idea")
        case .data: return String(localized: "My numbers look wrong")
        case .other: return String(localized: "Something else")
        }
    }

    /// The switch, and while it's on "What's included" inside the same card: a row that opens the list under it (the chevron
    /// points down, then up; VoiceOver says "Collapsed" or "Expanded"). While it's off the footer says nothing else goes along.
    private var diagnostics: some View {
        GroupedCard(Text("Diagnostics"),
                    footer: model.includeDiagnostics ? nil : Text("Nothing is attached except your message.")) {
            GroupedRow.toggle(Text("Include diagnostics"), identifier: "report.diagnostics",
                              isOn: Bindable(model).includeDiagnostics)
            if model.includeDiagnostics {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(Theme.Motion.respecting(reduceMotion)) { includedOpen.toggle() }
                    } label: {
                        HStack(spacing: GroupedListSpec.rowSpacing) {
                            Text("What's included")
                                .font(.ryft(.callout))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: includedOpen ? "chevron.up" : "chevron.down")
                                .font(.system(size: GroupedListSpec.chevronSize * chevronScale, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary.opacity(GroupedListSpec.accessoryOpacity))
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, GroupedListSpec.textPadding)
                        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(includedOpen ? Text("Expanded") : Text("Collapsed"))
                    .accessibilityIdentifier("report.included")
                    if includedOpen { includedList }
                }
                .padding(.horizontal, GroupedListSpec.rowInset)
                .groupedRowHairline()
            }
        }
    }

    private var includedList: some View {
        VStack(alignment: .leading, spacing: ReportProblemLayout.includedSpacing) {
            ForEach(included(about: model.context != nil), id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "•").accessibilityHidden(true)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityElement(children: .combine)
            }
            Text("No health values: no scores, no sleep, heart or workout data, and no times of day from Apple Health.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ReportProblemLayout.includedSentenceGap)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, ReportProblemLayout.includedBottom)
    }

    /// "What's included": exactly what `FeedbackPayload` sends, in its order.
    private func included(about context: Bool) -> [String] {
        var rows = [
            String(localized: "App version and build"),
            String(localized: "Device model and iOS version"),
            String(localized: "Language and region"),
            String(localized: "The last 20 requests: method, path without its query, status, error code, request ID, time, duration"),
            String(localized: "Loaded data, per area (Today, History, Profile …): when RYFT last loaded it, and its last error's status, code and request ID"),
            String(localized: "Sync state: phase, queue and backlog, and per data type the number of records and days and the date of the newest record"),
            String(localized: "Account gates and feature flags"),
        ]
        if model.includesTrackers {
            rows.append(String(localized: "What you wear, as RYFT's tracker ids (no device names)"))
        }
        // Only while a recent check would go along.
        if model.syncCheck != nil {
            rows.append(String(localized: "Your last Check sync: its day, and per tracker and data type a result code"))
        }
        if context { rows.append(String(localized: "From Details: what failed, its status, error code and request ID")) }
        return rows
    }

    // MARK: sent, queued

    private var outcome: some View {
        let sent = model.result == .sent
        let headline: LocalizedStringKey = switch (sent, model.isDemo) {
        case (true, false): "Thanks, your report reached RYFT."
        // Demo data posts to the in-memory platform: it says so.
        case (true, true): "Sent in demo mode: nothing reached RYFT."
        case (false, _): "Saved. It will be sent as soon as you're back online. You can close the app."
        }
        return VStack(spacing: ReportProblemLayout.outcomeGap) {
            Image(systemName: sent ? "checkmark" : "clock")
                .font(.system(size: ReportProblemLayout.outcomeGlyph, weight: .light))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: ReportProblemLayout.outcomeCircle, height: ReportProblemLayout.outcomeCircle)
                .overlay {
                    Circle().strokeBorder(Theme.textPrimary.opacity(IconDisc.ringOpacity), lineWidth: IconDisc.ringWidth)
                }
                .accessibilityHidden(true)
            Text(headline)
                .font(.ryftNumber(size: headlineSize, weight: .light))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($outcomeFocused)
                .accessibilityIdentifier(sent ? "report.sent" : "report.queued")
            PillButton(Text("Done"), style: .secondary) { dismiss() }
                .accessibilityIdentifier("report.done")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, ReportProblemLayout.outcomeTop)
        .onAppear { outcomeFocused = true }
    }
}

/// "About: Today · 503 · request 01a14ffa…" above a report from Details, as a capsule on `surface`; VoiceOver reads the whole
/// ID.
private struct ReportContextChip: View {
    let context: ReportContext
    /// Off with "Include diagnostics": the ID isn't sent then.
    var showsRequestID = true

    private var requestID: String? { showsRequestID ? context.requestID : nil }

    var body: some View {
        text(requestID.map(Self.short))
            .font(.ryft(.caption))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ReportProblemLayout.chipHorizontal)
            .padding(.vertical, ReportProblemLayout.chipVertical)
            .background(Theme.surface, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text(requestID))
            .accessibilityIdentifier("report.context")
    }

    private func text(_ id: String?) -> Text {
        if let id {
            return Text("About: \(context.resource) · \(context.statusText) · request \(id)")
        }
        return Text("About: \(context.resource) · \(context.statusText)")
    }

    /// The first 8 characters: enough to recognise it; the whole ID goes in `request_ids`.
    static func short(_ id: String) -> String {
        id.count > 9 ? String(id.prefix(8)) + "…" : id
    }
}

extension ReportContext {
    /// What previews and screenshot runs report about.
    static var preview: ReportContext {
        ReportContext(resource: String(localized: "Today"), status: "503",
                      requestID: "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c")
    }
}

// MARK: - previews (dark only)

/// One state of Report a problem on mock data, pushed as Profile pushes it.
@MainActor
private func reportPreview(size: DynamicTypeSize = .large, context: ReportContext? = nil, showsIncluded: Bool = false,
                           editing: Bool = false, stage: (ReportProblemModel) -> Void = { _ in }) -> some View {
    let state = AppState.preview()
    let model = ReportProblemModel(env: state.env, apiStatus: APIStatus()) { FeedbackSync() }
    stage(model)
    return NavigationStack {
        ReportProblemView(model: model, context: context, showsIncluded: showsIncluded, startsEditing: editing)
    }
        .previewEnvironment(state)
        .toggleStyle(.ryft)
        .dynamicTypeSize(size)
}

private let previewMessage = "Today shows 'Updating…' for hours and my Garmin night never arrives."

#Preview("Report · empty") { reportPreview() }
#Preview("Report · filled") { reportPreview { $0.stage(message: previewMessage, category: .data, includeDiagnostics: false) } }
#Preview("Report · typing") { reportPreview(editing: true) { $0.stage(message: previewMessage, category: .data) } }
#Preview("Report · from Details, what's included") {
    reportPreview(context: .preview, showsIncluded: true) {
        $0.stage(message: previewMessage, category: .data, context: .preview)
    }
}
#Preview("Report · from Details · diagnostics off") {
    reportPreview { $0.stage(message: ReportProblemModel.prefill(.preview), category: .bug, includeDiagnostics: false,
                             context: .preview) }
}
#Preview("Report · sending") { reportPreview { $0.stage(message: previewMessage, category: .data, sending: true) } }
#Preview("Report · rate limited") { reportPreview { $0.stage(message: previewMessage, category: .data, result: .rateLimited) } }
#Preview("Report · signed out") { reportPreview { $0.stage(message: previewMessage, result: .signedOut) } }
#Preview("Report · over the limit") {
    reportPreview { $0.stage(message: String(repeating: "The tiles and the gauge disagree. ", count: 120)) }
}
#Preview("Report · sent") { reportPreview { $0.stage(result: .sent) } }
#Preview("Report · sent · demo") { reportPreview { $0.stage(result: .sent, demo: true) } }
#Preview("Report · queued") { reportPreview { $0.stage(result: .queued, waiting: 1) } }
#Preview("Report · AX3") { reportPreview(size: .accessibility3) { $0.stage(message: previewMessage, category: .data) } }
#Preview("Report · typing · AX3") {
    reportPreview(size: .accessibility3, editing: true) { $0.stage(message: previewMessage, category: .data) }
}
#Preview("Report · what's included · AX3") { reportPreview(size: .accessibility3, showsIncluded: true) }
#Preview("Report · queued · AX3") { reportPreview(size: .accessibility3) { $0.stage(result: .queued, waiting: 1) } }
