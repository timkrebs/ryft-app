import SwiftUI
import UIKit

/// Common screen frame: RYFT header at the top, scrolling content, Graphite
/// background, pull-to-refresh (sync + reload).
struct ScreenScaffold<Content: View>: View {
    @Environment(ScreenModels.self) private var screens
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Metrics.sectionSpacing) {
                RyftHeader()
                    .padding(.top, 6)
                content()
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .refreshable { await screens.pullToRefresh() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Calm inline message for routine failures — never a bare alert.
struct InlineMessage: View {
    let message: String
    var systemImage = "wifi.exclamationmark"
    var retryTitle: LocalizedStringKey = "Try again"
    /// Status and request ID behind a "Details" toggle (for support and server logs).
    var details: String? = nil
    var retry: (() async -> Void)? = nil
    /// A second line under the message ("Showing data from 14:05"), monospaced digits.
    var caption: String? = nil
    /// While `retry` runs, this label (disabled) instead of a spinner ("Trying again…").
    var retryingTitle: LocalizedStringKey? = nil
    /// Shows the retrying state from outside (previews).
    var isRetrying = false
    /// "Details" opens something (a sheet) instead of the inline toggle.
    var onDetails: (() -> Void)? = nil
    /// Prefix of the buttons' identifiers: "<prefix>.retry", "<prefix>.details".
    var identifier = "inlineMessage"

    @State private var retrying = false
    @State private var showDetails = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var hasButtons: Bool { retry != nil || details != nil || onDetails != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(caption)
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            // ui.md §3.2: the buttons start at the card's leading edge, 18 pt apart; stacked at AX sizes.
            if hasButtons { buttons }
            if showDetails, let details {
                Text(details)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        // A button row's 44 pt targets already leave room under their labels.
        .padding(.bottom, hasButtons && !showDetails ? 2 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
            .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
    }

    /// Try again and Details: each at least 44 × 44 pt.
    private var buttons: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 18))
        return layout {
            if let retry {
                Button {
                    Task {
                        retrying = true
                        await retry()
                        retrying = false
                    }
                } label: {
                    if retrying || isRetrying, let retryingTitle {
                        Text(retryingTitle).font(.ryft(.callout)).foregroundStyle(Theme.textTertiary)
                    } else if retrying || isRetrying {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                    } else {
                        Text(retryTitle).font(.ryft(.callout)).foregroundStyle(Theme.accent)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .disabled(retrying || isRetrying)
                .accessibilityIdentifier("\(identifier).retry")
            }
            if let onDetails {
                Button("Details", action: onDetails)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(identifier).details")
            } else if details != nil {
                Button(showDetails ? "Hide details" : "Details") { showDetails.toggle() }
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
        }
    }
}

/// "Updated 14:05" when the platform scored the day (`computed_at`), else
/// "Updated 5 min ago" from the last fetch; refreshes itself every 30 s.
struct UpdatedLabel: View {
    let date: Date?
    var isLoading = false
    var isDemo = false
    /// `DailyScore.computedAt`; `0001-01-01` (not scored yet) is ignored.
    var scoredAt: Date? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(text(now: context.date))
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private func text(now: Date) -> String {
        if isLoading { return String(localized: "Updating…") }
        let prefix = isDemo ? String(localized: "Demo data · ") : ""
        if let scoredAt, scoredAt > Date(timeIntervalSince1970: 0) {
            return prefix + String(localized: "Updated \(Fmt.time(scoredAt))")
        }
        guard let date else { return prefix + String(localized: "Not updated yet") }
        if now.timeIntervalSince(date) < 60 { return prefix + String(localized: "Updated just now") }
        let rel = date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return prefix + String(localized: "Updated \(rel)")
    }
}

/// Today's one status line under the greeting: what the sync is doing, or how fresh the
/// numbers are. Never a modal. Tapping it opens what's needed (a gate) or Sync details; a stale
/// line ("Showing data from 14:05") has its own "Try again" unless the error card shows one.
struct SyncStatusLineView: View {
    let line: SyncLine
    /// The line's tap: the gate's screen, or Sync details. Without it the line is plain text.
    var action: (() -> Void)? = nil
    /// "Try again" on a stale line.
    var retry: (() async -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// "Try again" was tapped: the return to "Up to date" is announced once.
    @State private var retried = false
    /// The line on screen and since when: each one stays at least `minimumShown` so it can be read
    /// (ui.md §2.2), then the newest one cross-fades in. Lines in between are skipped.
    @State private var shown: SyncLine?
    @State private var shownAt = Date.distantPast

    static let minimumShown: TimeInterval = 0.6

    /// What's drawn: the line held on screen, until the newest one may replace it.
    private var current: SyncLine { shown ?? line }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        // A container: VoiceOver (and UI tests) reach the line and its "Try again" as separate buttons.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.syncLine")
        .onChange(of: line) { old, new in announce(old, new) }
        .task(id: line) { await show(line) }
    }

    /// Shows `next` once the line on screen has been up `minimumShown`; a newer line cancels the wait.
    private func show(_ next: SyncLine) async {
        if shown != nil {
            let wait = Self.minimumShown - Date.now.timeIntervalSince(shownAt)
            if wait > 0 {
                try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
                guard !Task.isCancelled else { return }
            }
        }
        guard shown != next else { return }
        withAnimation(Theme.Motion.respecting(reduceMotion)) { shown = next }
        shownAt = .now
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        switch current {
        case .actionNeeded:
            if let action {
                Button(action: action) {
                    label(now: now)
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens what's needed"))
                .accessibilityIdentifier("today.actionNeeded")
            } else {
                label(now: now).foregroundStyle(Theme.accent)
            }
        case .stale:
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                tappable(now: now, hint: "Opens sync details")
                    .accessibilityIdentifier("today.syncLine.line")
                if let retry {
                    if !typeSize.isAccessibilitySize {
                        Text(verbatim: "·").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                            .accessibilityHidden(true)
                    }
                    Button {
                        retried = true
                        Task { await retry() }
                    } label: {
                        Text("Try again")
                            .font(.ryft(.caption))
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.accent)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Tries to load your data again"))
                    .accessibilityIdentifier("today.syncLine.retry")
                }
            }
            .frame(maxWidth: .infinity)
        case .waitingForUnlock:
            label(now: now).foregroundStyle(Theme.textTertiary)
        case .issue:
            tappable(now: now, hint: "Shows what couldn't load")
                .accessibilityIdentifier("today.syncLine.issue")
        default:
            tappable(now: now, hint: "Opens sync details")
                .accessibilityIdentifier("today.syncLine.line")
        }
    }

    /// The line as one button (Sync details), or as text without an action.
    @ViewBuilder
    private func tappable(now: Date, hint: LocalizedStringKey) -> some View {
        let color = current.isActive || current.isIssue ? Theme.textSecondary : Theme.textTertiary
        if let action {
            Button(action: action) {
                label(now: now)
                    .foregroundStyle(color)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(hint))
        } else {
            label(now: now).foregroundStyle(color)
        }
    }

    private func label(now: Date) -> some View {
        // The icon sits on the first line when the text wraps.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: current.systemImage)
                .symbolEffect(.pulse, options: .repeating, isActive: current.isActive && !reduceMotion)
                .accessibilityHidden(true)
            // Wraps at every size, never truncates ("Demodaten · Aktuell · gerade eben" at AX3 is
            // three lines); the fixed vertical size keeps a parent from squeezing it into an ellipsis.
            Text(current.text(now: now))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.ryft(.caption))
        .frame(maxWidth: current.isStale ? nil : .infinity)
    }

    /// VoiceOver hears the stale claim, and the return to "Up to date" after a manual Try again;
    /// the other changes stay silent (they would chatter).
    private func announce(_ old: SyncLine, _ new: SyncLine) {
        let now = Date.now
        if new.isStale, !old.isStale {
            AccessibilityNotification.Announcement(new.text(now: now)).post()
        } else if retried, case .upToDate = new {
            retried = false
            AccessibilityNotification.Announcement(new.text(now: now)).post()
        }
    }
}

extension SyncLine {
    var isStale: Bool { if case .stale = self { return true } else { return false } }
    var isIssue: Bool { if case .issue = self { return true } else { return false } }
}

// MARK: - refresh issue (the calm error card and its Details)

/// What "Send to RYFT" opens on the Details sheet's stack: Report a problem, pre-filled with the
/// resource, the status, the error's code and the request ID. Set on the root view (`RootView`);
/// without it the button hides.
typealias ReportProblemDestination = @MainActor (_ resource: String, _ status: String, _ code: String?,
                                                 _ requestID: String?) -> AnyView

private struct ReportProblemDestinationKey: EnvironmentKey {
    static var defaultValue: ReportProblemDestination? { nil }
}

extension EnvironmentValues {
    var reportProblemDestination: ReportProblemDestination? {
        get { self[ReportProblemDestinationKey.self] }
        set { self[ReportProblemDestinationKey.self] = newValue }
    }
}

extension RefreshIssue.Reason {
    /// ui.md §3.3: one plain sentence per class.
    var message: String {
        switch self {
        case .busy: return String(localized: "RYFT is busy right now. Your data is safe; try again in a moment.")
        case .unreachable:
            return String(localized: "RYFT can't be reached right now. Your connection looks fine, so this isn't on your side.")
        case .unexpected: return String(localized: "Part of your data couldn't be loaded. The details help us find out why.")
        case .signedOut: return String(localized: "You're signed out, so new data can't load.")
        case .appTooOld: return String(localized: "This version of RYFT is too old to load new data. Update it to continue.")
        }
    }

    var systemImage: String {
        switch self {
        case .busy: return "clock.arrow.circlepath"
        case .unreachable: return "wifi.exclamationmark"
        case .unexpected: return "exclamationmark.circle"
        case .signedOut: return "person.crop.circle.badge.exclamationmark"
        case .appTooOld: return "arrow.down.app"
        }
    }
}

/// Today's calm error card (ui.md §3): the reason, how old the data is, Try again (or Sign in)
/// and Details. Only past `RefreshPolicy`'s threshold, or for something the user can act on.
struct RefreshIssueCard: View {
    let issue: RefreshIssue
    var retry: () async -> Void = {}
    var signIn: () async -> Void = {}
    /// Previews: the "Trying again…" state.
    var isRetrying = false

    @State private var showsDetails = false

    var body: some View {
        InlineMessage(message: issue.reason.message, systemImage: issue.reason.systemImage,
                      retryTitle: issue.reason == .signedOut ? "Sign in" : "Try again",
                      retry: action, caption: age, retryingTitle: "Trying again…", isRetrying: isRetrying,
                      onDetails: { showsDetails = true }, identifier: "refreshIssue")
            .sheet(isPresented: $showsDetails) { RefreshDetailsSheet(issue: issue) }
            // A container: Try again (or Sign in) and Details stay separate buttons for VoiceOver.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.refreshIssue")
    }

    /// No action for an outdated app until the platform says how to tell (no store link to guess).
    private var action: (() async -> Void)? {
        switch issue.reason {
        case .signedOut: return signIn
        case .appTooOld: return nil
        case .busy, .unreachable, .unexpected: return retry
        }
    }

    private var age: String? {
        issue.dataFrom.map { String(localized: "Showing data from \(SyncLine.dataTime($0, now: .now))") }
    }
}

extension RefreshIssue {
    /// The status Report a problem names: "503", or "No response". Never a transport's raw name ("timedOut"):
    /// that goes out in the report's `resources` lines.
    var reportStatus: String { statusText ?? String(localized: "No response") }
}

/// The error card's Details (ui.md §3.4): what failed, status, code, request ID, time, data age,
/// failures in a row; "Send to RYFT" (when Report a problem is wired) and "Copy details".
struct RefreshDetailsSheet: View {
    let issue: RefreshIssue

    @Environment(\.dismiss) private var dismiss
    @Environment(\.reportProblemDestination) private var reportProblem
    @Environment(\.locale) private var locale
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Metrics.sectionSpacing) {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            DetailRow(title: "What failed", value: issue.resourceName)
                            DetailRow(title: "HTTP status", value: issue.statusText ?? "—",
                                      detail: issue.statusText == nil ? String(localized: "No response") : nil)
                            DetailRow(title: "Code", value: issue.error.code ?? "—", monospaced: true)
                            RequestIDRow(requestID: issue.error.requestID, answered: issue.error.status != nil)
                            DetailRow(title: "Time", value: Self.time(issue.error.at, locale: locale))
                            DetailRow(title: "Showing data from",
                                      value: issue.dataFrom.map { Self.time($0, locale: locale) } ?? "—")
                            DetailRow(title: "Failed in a row", value: issue.failures.formatted())
                        }
                    }
                }
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            // Pinned: "Send to RYFT" (and Copy details) are reachable at the opening (medium) detent.
            .safeAreaInset(edge: .bottom) { actions }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text("Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// "Send to RYFT" (only once Report a problem is wired), "Copy details", and what's sent.
    private var actions: some View {
        VStack(spacing: 10) {
            if let reportProblem {
                NavigationLink {
                    reportProblem(issue.resourceName, issue.reportStatus, issue.error.code, issue.error.requestID)
                } label: {
                    Text("Send to RYFT")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("refreshDetails.send")
            }
            PrimaryButton(title: copied ? "Copied" : "Copy details", style: .secondary) {
                // On this iPhone only, and not for long (`LocalPasteboard`).
                LocalPasteboard.copy(issue.copyText)
                copied = true
            }
            if reportProblem != nil {
                Text("Sends this and the last 20 requests. No health values.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.background)
    }

    /// "14:07:12" today, else with the date; in the screen's locale (German shows 24-hour time).
    static func time(_ date: Date, locale: Locale) -> String {
        let today = Calendar.current.isDateInToday(date)
        return date.formatted(Date.FormatStyle(date: today ? .omitted : .abbreviated, time: .standard, locale: locale))
    }
}

/// A label and its value; at accessibility sizes the value goes under the label.
private struct DetailRow: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String? = nil
    var monospaced = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            Text(title)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                Text(value)
                    .font(monospaced ? .system(.body, design: .monospaced) : .ryft(.body))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The request ID exactly as received, selectable, with a copy button; support searches for it.
private struct RequestIDRow: View {
    let requestID: String?
    /// Something answered (a status came back): a missing ID means a proxy answered first.
    let answered: Bool
    @State private var copied = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let requestID {
            // One row (ui.md §3.4): the label, the ID as received, the copy button at the trailing edge.
            // At AX sizes the ID and its button go under the label.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            layout {
                Text("Request ID")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize()
                HStack(alignment: .center, spacing: 4) {
                    Spacer(minLength: 0)
                    Text(verbatim: requestID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: copy) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(copied ? Theme.accent : Theme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(copied ? "Copied" : "Copy request ID"))
                    // The glyph lines up with the other rows' values; its 44 pt target reaches into the padding.
                    .padding(.trailing, -13)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: Text("Copy request ID"), copy)
            .accessibilityIdentifier("refreshDetails.requestID")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Request ID")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                Text("Not available")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                if answered {
                    Text("A proxy answered before RYFT did.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func copy() {
        guard let requestID else { return }
        UIPasteboard.general.string = requestID
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// Under a day in a picker: scored (a dot), pending (a hollow dot), no data (nothing),
/// from `DailyScore.scoringState`.
struct DayMarker: View {
    enum Kind: Equatable {
        case scored, pending

        /// For VoiceOver after the day's value; `nil` when scored.
        var spoken: String? { self == .pending ? String(localized: "not scored yet") : nil }
    }

    let kind: Kind?

    static func kind(for score: DailyScore?) -> Kind? {
        guard let score else { return nil }
        switch score.scoringState {
        case .pending, .waitingForSleep: return .pending
        default: return TodayStates.isScored(score) ? .scored : nil
        }
    }

    var body: some View {
        ZStack {
            switch kind {
            case .scored: Circle().fill(Theme.textTertiary)
            case .pending: Circle().strokeBorder(Theme.textSecondary, lineWidth: 1)
            case nil: Color.clear
            }
        }
        .frame(width: 5, height: 5)
        .accessibilityHidden(true)
    }
}

/// One signal in Check sync (ui.md §5.2): glyph, name and result, every state with its own symbol and words,
/// never colour alone. Not tappable. At accessibility sizes the result goes under the name.
struct CheckRow: View {
    enum Kind: Equatable {
        case waiting, checking
        /// Arrived: the one accent.
        case ok
        /// Not shared by the tracker: a neutral fact, never red or amber.
        case expected
        /// Not seen yet, or from another tracker: nothing promised.
        case neutral
        /// A nightly signal last seen before last night.
        case late
        /// Should arrive and doesn't: amber, with the fix under it.
        case fix

        var symbol: String {
            switch self {
            case .waiting: return "circle"
            case .checking: return "circle.dotted"
            case .ok: return "checkmark.circle.fill"
            case .expected: return "minus.circle"
            case .neutral: return "circle.dashed"
            case .late: return "clock"
            case .fix: return "exclamationmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .ok: return Theme.accent
            case .fix: return Theme.warning
            case .checking, .late: return Theme.textSecondary
            case .waiting, .expected, .neutral: return Theme.textTertiary
            }
        }
    }

    let name: String
    let result: String
    let kind: Kind
    /// VoiceOver's value ("Arriving, last 07:42"); the result when nil.
    var spoken: String?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 20 pt glyphs in a 24 pt column at the default size, growing with the text.
    @ScaledMetric(relativeTo: .callout) private var glyphSize: CGFloat = 17
    @ScaledMetric(relativeTo: .callout) private var glyphWidth: CGFloat = 24

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: glyphSize, weight: .regular))
                .foregroundStyle(kind.color)
                .frame(width: glyphWidth)
                // The status line's pulse while checking; static under Reduce Motion ("checking…" says it).
                .symbolEffect(.pulse, options: .repeating, isActive: kind == .checking && !reduceMotion)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    nameText
                    resultText
                }
            } else {
                nameText
                Spacer(minLength: 8)
                resultText.multilineTextAlignment(.trailing)
            }
        }
        .frame(minHeight: 44)
        .animation(Theme.Motion.respecting(reduceMotion), value: kind)
        .animation(Theme.Motion.respecting(reduceMotion), value: result)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: spoken ?? result))
    }

    private var nameText: some View {
        Text(verbatim: name)
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var resultText: some View {
        Text(verbatim: result)
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
    }
}

extension CheckRow.Kind {
    /// A check's row: arrived is the one accent, an expected gap neutral, only an unexpected one amber.
    init(_ check: SignalCheck) {
        switch check {
        case .waiting: self = .waiting
        case .checking: self = .checking
        case .arrived: self = .ok
        case .notLastNight: self = .late
        case .notShared: self = .expected
        case .notSeenYet, .elsewhere: self = .neutral
        case .missing: self = .fix
        }
    }
}

#Preview("Check row · states", traits: .sizeThatFitsLayout) {
    SchemePair { CheckRowPreview() }
}

#Preview("Check row · de · AX3", traits: .sizeThatFitsLayout) {
    CheckRowPreview()
        .padding(20)
        .frame(width: 390)
        .background(Theme.background)
        .environment(\.locale, Locale(identifier: "de_DE"))
        .environment(\.dynamicTypeSize, .accessibility3)
}

/// Every kind once, worded in the preview's locale (`TrackerCheckText`).
private struct CheckRowPreview: View {
    @Environment(\.locale) private var locale

    var body: some View {
        let text = TrackerCheckText(locale: locale)
        let now = Date.now
        let rows: [(TrackerSignal, SignalCheck)] = [
            (.heartRate, .arrived(now.addingTimeInterval(-1_200))), (.hrv, .notShared), (.sleep, .arrived(now)),
            (.sleepStages, .notSeenYet), (.restingHR, .missing(visible: true)),
            (.respiratoryRate, .notLastNight(lastSeen: now.addingTimeInterval(-34 * 3_600))),
            (.workouts, .checking), (.steps, .waiting),
        ]
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.0) { signal, check in
                CheckRow(name: text.name(signal), result: text.result(check, signal: signal, app: "Garmin Connect", now: now),
                         kind: CheckRow.Kind(check))
            }
        }
    }
}

/// Setup card for the unconfigured state.
struct SetupCard: View {
    var action: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                RyftMark()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Theme.accent)
                Text("Connect RYFT")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                VStack(alignment: .leading, spacing: 10) {
                    SetupStep(number: 1, text: "Let Garmin Connect write to Apple Health (Garmin Connect → More → Settings → Apple Health).")
                    SetupStep(number: 2, text: "Allow RYFT to read Health data when asked.")
                    SetupStep(number: 3, text: "Check your RYFT server URL in Profile.")
                }
                Button(action: action) {
                    Text("Open Profile")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 4)
            }
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .frame(width: 18, height: 18)
                .background(Theme.accent.opacity(0.14), in: Circle())
            Text(text)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Status", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 16) {
            InlineMessage(message: "Couldn't reach RYFT. Showing what was loaded earlier.",
                          details: "HTTP 503 · Request ID 01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c", retry: {})
            UpdatedLabel(date: .now.addingTimeInterval(-300))
            SetupCard {}
        }
    }
}

#Preview("Sync status line", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            SyncStatusLineView(line: .upToDate(.now.addingTimeInterval(-120), demo: false))
            SyncStatusLineView(line: .reading(.sleep))
            SyncStatusLineView(line: .uploading(records: 12_400))
            SyncStatusLineView(line: .scoring(night: true))
            SyncStatusLineView(line: .waitingForUnlock)
            SyncStatusLineView(line: .offline)
            SyncStatusLineView(line: .actionNeeded(.consent)) {}
            HStack(spacing: 12) {
                DayMarker(kind: .scored)
                DayMarker(kind: .pending)
                DayMarker(kind: nil)
            }
        }
    }
}

#Preview("Sync status line · de", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            SyncStatusLineView(line: .uploading(records: 12_400))
            SyncStatusLineView(line: .actionNeeded(.invite)) {}
            SyncStatusLineView(line: .stale(since: PreviewIssue.at(14, 5)), action: {}, retry: {})
        }
    }
    .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Sync status line · stale", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            SyncStatusLineView(line: .stale(since: PreviewIssue.at(14, 5)), action: {}, retry: {})
            SyncStatusLineView(line: .stale(since: PreviewIssue.at(22, 10, daysAgo: 1)),
                               action: {}, retry: {})
            SyncStatusLineView(line: .issue(.today), action: {})
            SyncStatusLineView(line: .issue(.me, signedOut: true), action: {})
            SyncStatusLineView(line: .reading(.sleep), action: {})
        }
    }
}

#Preview("Sync status line · stale · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            SyncStatusLineView(line: .stale(since: PreviewIssue.at(14, 5)), action: {}, retry: {})
            // The longest up-to-date line (demo prefix) wraps instead of truncating.
            SyncStatusLineView(line: .upToDate(.now, demo: true), action: {})
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

/// Mock issues for the card and sheet previews: data from 14:05, 3 failures, the API.md request ID.
private enum PreviewIssue {
    static func at(_ hour: Int, _ minute: Int, daysAgo: Int = 0) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func make(_ reason: RefreshIssue.Reason, requestID: String? = "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c")
        -> RefreshIssue {
        let status: Int?, kind: FailureKind
        switch reason {
        case .busy: (status, kind) = (503, .transient)
        case .unreachable: (status, kind) = (nil, .transient)
        case .unexpected: (status, kind) = (404, .other)
        case .signedOut: (status, kind) = (401, .signedOut)
        case .appTooOld: (status, kind) = (nil, .appTooOld)
        }
        let error = ResourceError(kind: kind, status: status, code: nil,
                                  requestID: status == nil ? nil : requestID,
                                  transport: status == nil ? "timedOut" : nil, attempts: 3, at: at(14, 7))
        return RefreshIssue(reason: reason, resource: .today, dataFrom: at(14, 5), failures: 3, error: error)
    }
}

#Preview("Error card", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            RefreshIssueCard(issue: PreviewIssue.make(.busy))
            RefreshIssueCard(issue: PreviewIssue.make(.unreachable))
            RefreshIssueCard(issue: PreviewIssue.make(.unexpected))
            RefreshIssueCard(issue: PreviewIssue.make(.signedOut))
            RefreshIssueCard(issue: PreviewIssue.make(.busy), isRetrying: true)
        }
    }
}

#Preview("Error card · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        RefreshIssueCard(issue: PreviewIssue.make(.busy))
    }
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Details sheet · with ID · dark") {
    RefreshDetailsSheet(issue: PreviewIssue.make(.busy))
        .environment(\.reportProblemDestination) { _, _, _, _ in AnyView(Text(verbatim: "Report a problem")) }
        .preferredColorScheme(.dark)
}

#Preview("Details sheet · with ID · light") {
    RefreshDetailsSheet(issue: PreviewIssue.make(.busy))
        .preferredColorScheme(.light)
}

#Preview("Details sheet · no ID · dark") {
    RefreshDetailsSheet(issue: PreviewIssue.make(.unreachable))
        .preferredColorScheme(.dark)
}

#Preview("Details sheet · no ID · light · de") {
    RefreshDetailsSheet(issue: PreviewIssue.make(.busy, requestID: nil))
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: "de"))
}
