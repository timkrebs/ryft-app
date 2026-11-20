import SwiftUI

// MARK: - report a problem

/// Profile → About's first row: "Report a problem", and what's still waiting to send.
struct ReportProblemRow: View {
    let waiting: Int
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    status
                }
                Spacer(minLength: 8)
            } else {
                title
                Spacer(minLength: 8)
                status
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text("Report a problem")
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textPrimary)
    }

    @ViewBuilder private var status: some View {
        if waiting > 0 {
            Text("\(waiting) waiting to send")
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Profile → About → Report a problem (ui.md §5): a message, what it's about, and diagnostics that help find
/// the cause, never a health value. Pushed from Profile, or from an error's Details (`context`), pre-filled.
/// `sent` and `queued` replace the form; a refusal shows on it, with the message kept.
struct ReportProblemView: View {
    let model: ReportProblemModel
    var context: ReportContext?
    /// "What's included" open from the start (previews).
    var showsIncluded = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editing: Bool
    @AccessibilityFocusState private var outcomeFocused: Bool
    @State private var included = false
    @State private var prepared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                switch model.result {
                case .sent?, .queued?:
                    outcome.transition(.opacity)
                default:
                    form.transition(.opacity)
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 16)
            .animation(Theme.Motion.respecting(reduceMotion), value: model.result)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("Report a problem"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editing = false }
            }
        }
        .sensoryFeedback(.success, trigger: model.result) { _, new in new == .sent }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            included = showsIncluded
            // No keyboard on arrival: from Details the message is written already, and the keyboard would
            // cover what's attached.
            model.prepare(context)
        }
        .onChange(of: model.includeDiagnostics) { _, on in if !on { included = false } }
        .analyticsScreen(.reportProblem)
    }

    // MARK: compose

    @ViewBuilder private var form: some View {
        // The request ID shows only while it's attached.
        if let context = model.context { ReportContextChip(context: context, showsRequestID: model.includeDiagnostics) }
        notice
        Group {
            ProfileSection(title: "Message") { message }
            ProfileSection(title: "Category") { categories }
            ProfileSection(title: "Diagnostics") { diagnostics }
        }
        .disabled(model.sending)
        VStack(alignment: .leading, spacing: 8) {
            PrimaryButton(title: model.sending ? "Sending…" : "Send") { await model.send() }
                .disabled(!model.canSend)
                .accessibilityIdentifier("report.send")
            Text("Reports are limited to 10 a day.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What stopped the report, with the message kept to copy.
    @ViewBuilder private var notice: some View {
        switch model.result {
        case .rateLimited?:
            InlineMessage(message: String(localized: "You've reached today's limit of 10 reports. Your message is kept; try again tomorrow."),
                          systemImage: "clock", retryTitle: "Copy message", details: model.resultDetails) {
                model.copyMessage()
            }
            .accessibilityIdentifier("report.rateLimited")
        case .rejected?:
            InlineMessage(message: String(localized: "RYFT couldn't take this report. Copy your message and try again later."),
                          systemImage: "exclamationmark.circle", retryTitle: "Copy message",
                          details: model.resultDetails) {
                model.copyMessage()
            }
        case .saveFailed?:
            InlineMessage(message: String(localized: "Couldn't save your report. Copy it and try again later."),
                          systemImage: "exclamationmark.circle", retryTitle: "Copy message") {
                model.copyMessage()
            }
        case .signedOut?:
            InlineMessage(message: String(localized: "You're signed out, so this report can't be sent. Your message is kept."),
                          systemImage: "person.crop.circle.badge.exclamationmark", retryTitle: "Copy message") {
                model.copyMessage()
            }
            .accessibilityIdentifier("report.signedOut")
        default:
            EmptyView()
        }
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: Bindable(model).message,
                      prompt: Text("What happened? What did you expect?").foregroundStyle(Theme.textSecondary),
                      axis: .vertical)
                .lineLimit(6...)
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
                .focused($editing)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                .background(Theme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
                .accessibilityLabel(Text("Message"))
                .accessibilityIdentifier("report.message")
            if model.showsCount {
                Text("\(model.length) / 4000")
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(model.isTooLong ? Theme.warning : Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text("Please don't type health values you'd rather keep private.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One choice: a check in Teal on the chosen row, "selected" for VoiceOver.
    private var categories: some View {
        VStack(spacing: 0) {
            ForEach(Array(FeedbackCategory.allCases.enumerated()), id: \.element) { index, category in
                if index > 0 { Divider().overlay(Theme.separator) }
                let chosen = model.category == category
                Button {
                    model.category = category
                } label: {
                    HStack(spacing: 12) {
                        Text(Self.title(category))
                            .font(.ryft(.body))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .opacity(chosen ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("report.category.\(category.rawValue)")
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

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Bindable(model).includeDiagnostics) {
                Text("Include diagnostics")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("report.diagnostics")
            if model.includeDiagnostics {
                DisclosureGroup(isExpanded: $included) {
                    VStack(alignment: .leading, spacing: 6) {
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
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    Text("What's included")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(minHeight: 44)
                }
                // Like Sleep's "Why this need": the system disclosure keeps VoiceOver's expanded state.
                .tint(Theme.textSecondary)
                .accessibilityIdentifier("report.included")
            } else {
                Text("Nothing is attached except your message.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        return VStack(spacing: 18) {
            Image(systemName: sent ? "checkmark.circle" : "clock")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(sent ? Theme.accent : Theme.textSecondary)
                .accessibilityHidden(true)
            Text(headline)
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($outcomeFocused)
                .accessibilityIdentifier(sent ? "report.sent" : "report.queued")
            PrimaryButton(title: "Done", style: .secondary) { dismiss() }
                .accessibilityIdentifier("report.done")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .onAppear { outcomeFocused = true }
    }
}

/// "About: Today · 503 · request 01a14ffa…" above a report from Details; VoiceOver reads the whole ID.
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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
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

/// One state of Report a problem on mock data (previews).
@MainActor
private func reportPreview(de: Bool = false, size: DynamicTypeSize = .large,
                           context: ReportContext? = nil, showsIncluded: Bool = false,
                           stage: (ReportProblemModel) -> Void = { _ in }) -> some View {
    let state = AppState.preview()
    let model = ReportProblemModel(env: state.env, apiStatus: APIStatus()) { FeedbackSync() }
    stage(model)
    return NavigationStack { ReportProblemView(model: model, context: context, showsIncluded: showsIncluded) }
        .previewEnvironment(state)
        .environment(\.locale, Locale(identifier: de ? "de" : "en"))
        .dynamicTypeSize(size)
}

private let previewMessage = "Today said calibrating after a full week of nights, and pulling to refresh didn't change it."

#Preview("Report · empty · dark") { reportPreview() }
#Preview("Report · empty · dark · de") { reportPreview(de: true) }
#Preview("Report · empty · AX3") { reportPreview(size: .accessibility3) }
#Preview("Report · filled · dark") { reportPreview { $0.stage(message: previewMessage, category: .data) } }
#Preview("Report · from Details · dark") { reportPreview(context: .preview) }
#Preview("Report · from Details · de") { reportPreview(de: true, context: .preview) }
#Preview("Report · diagnostics off · dark") {
    reportPreview { $0.stage(message: previewMessage, includeDiagnostics: false) }
}
#Preview("Report · disclosure open · dark") { reportPreview(showsIncluded: true) }
#Preview("Report · disclosure open · AX3") { reportPreview(size: .accessibility3, showsIncluded: true) }
#Preview("Report · sending · dark") { reportPreview { $0.stage(message: previewMessage, sending: true) } }
#Preview("Report · sent · dark") { reportPreview { $0.stage(result: .sent) } }
#Preview("Report · sent · AX3") { reportPreview(size: .accessibility3) { $0.stage(result: .sent) } }
#Preview("Report · sent · demo · dark") { reportPreview { $0.stage(result: .sent, demo: true) } }
#Preview("Report · sent · demo · de") { reportPreview(de: true) { $0.stage(result: .sent, demo: true) } }
#Preview("Report · queued · dark") { reportPreview { $0.stage(result: .queued, waiting: 1) } }
#Preview("Report · rate limited · dark") {
    reportPreview { $0.stage(message: previewMessage, result: .rateLimited) }
}
#Preview("Report · signed out · dark") {
    reportPreview { $0.stage(message: previewMessage, result: .signedOut) }
}
#Preview("Report · from Details · diagnostics off") {
    reportPreview { $0.stage(message: ReportProblemModel.prefill(.preview), category: .bug, includeDiagnostics: false,
                             context: .preview) }
}
#Preview("Report · over limit · dark") {
    reportPreview { $0.stage(message: String(repeating: "The tiles and the gauge disagree. ", count: 120)) }
}

#Preview("Report row · dark") {
    VStack(spacing: 12) {
        Card { ReportProblemRow(waiting: 0) }
        Card { ReportProblemRow(waiting: 1) }
        Card { ReportProblemRow(waiting: 2) }
    }
    .padding()
    .frame(maxHeight: .infinity)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
