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
    /// Prefix of the buttons' identifiers: "<prefix>.retry", "<prefix>.details", "<prefix>.action".
    var identifier = "inlineMessage"
    /// A plain action, not a retry ("Garmin Connect in the App Store"): a secondary capsule where the buttons
    /// sit. Its title is already localized (`String(localized:)`) and shown verbatim.
    var action: (title: String, perform: () -> Void)?

    @State private var retrying = false
    @State private var showDetails = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var hasTextButtons: Bool { retry != nil || details != nil || onDetails != nil }

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
                        // Secondary ink: tertiary was under 4.5:1 on the card in light mode.
                        Text(caption)
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if let action { actionButton(action) }
            // ui.md §3.2: the buttons start at the card's leading edge, 18 pt apart; stacked at AX sizes.
            if hasTextButtons { buttons }
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
        .padding(.bottom, hasTextButtons && !showDetails ? 2 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
            .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
    }

    /// The plain action: `PrimaryButton`'s secondary look, wrapping instead of shrinking at large sizes.
    private func actionButton(_ action: (title: String, perform: () -> Void)) -> some View {
        Button(action: action.perform) {
            Text(verbatim: action.title)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.surfaceRaised, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.top, 4)
        .accessibilityIdentifier("\(identifier).action")
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
        // Slow scoring reads like an issue's line (secondary ink), without the pulse of progress.
        let color = current.isActive || current.isIssue || current == .scoringSlow ? Theme.textSecondary : Theme.textTertiary
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

    /// VoiceOver hears the stale claim, slow scoring once, and the return to "Up to date" after a manual
    /// Try again; the other changes stay silent (they would chatter).
    private func announce(_ old: SyncLine, _ new: SyncLine) {
        let now = Date.now
        if new.isStale, !old.isStale {
            AccessibilityNotification.Announcement(new.text(now: now)).post()
        } else if new == .scoringSlow, old != .scoringSlow {
            AccessibilityNotification.Announcement(String(localized: "Taking longer than usual")).post()
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

/// Setup card for the unconfigured state.
struct SetupCard: View {
    var action: () -> Void

    @Environment(\.appEnvironment) private var env
    @Environment(ScreenModels.self) private var screens: ScreenModels?

    /// With `devices.setup` on, step 1 names the first chosen tracker with an app of its own ("Garmin Connect"),
    /// or no vendor; off, it reads as it always did.
    private var app: String? {
        guard env.flags.isOn(.devicesSetup), let devices = screens?.devices else { return nil }
        return devices.trackers.compactMap(env.trackerCatalog.tracker).first { $0.integration == .vendorApp }?.appTitle
    }

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
                    if !env.flags.isOn(.devicesSetup) {
                        NumberedStep(number: 1, text: "Let Garmin Connect write to Apple Health (Garmin Connect → More → Settings → Apple Health).",
                                     total: 3)
                    } else if let app {
                        NumberedStep(number: 1, verbatim: String(localized: "Let \(app) write to Apple Health. Profile → Devices & sync shows how."),
                                     total: 3)
                    } else {
                        NumberedStep(number: 1, text: "Let your watch or ring app write to Apple Health.", total: 3)
                    }
                    NumberedStep(number: 2, text: "Allow RYFT to read Health data when asked.", total: 3)
                    NumberedStep(number: 3, text: "Check your RYFT server URL in Profile.", total: 3)
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

/// One tracker's setup card (ui.md §3): what reaches RYFT and what that means for its features, how to set the
/// tracker up, how to keep it flowing, and the store button. Catalog text is plain (`Text(verbatim:)`); the only
/// links are the vendor's allowlisted guide and the App Store page built from digits (ADR 0002).
struct TrackerSetupCard: View {
    let tracker: Tracker
    /// In a list of several (onboarding): the header opens and closes the card.
    var expanded: Binding<Bool>?
    /// "Show me again later"; nil: no such button.
    var later: (() -> Void)?
    /// Just my iPhone: "Add a tracker".
    var addTracker: (() -> Void)?

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.appEnvironment) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var guide: GuidePage?

    /// A guide older than this says its steps may have changed (ui.md C6).
    static let staleAfterDays = 180

    private var isOpen: Bool { expanded?.wrappedValue ?? true }
    private var features: RyftFeatures.Line? { RyftFeatures.line(for: tracker) }
    private var steps: [String] { tracker.setup.value(in: locale) }
    private var habits: [String] { tracker.habits.value(in: locale) }
    /// A tracker that writes nothing already says so in the app's own words: its lines about RYFT go.
    private var limits: [String] {
        let all = tracker.limits.value(in: locale)
        return tracker.integration == .none ? all.filter { !$0.contains("RYFT") } : all
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                if let expanded {
                    disclosure(expanded)
                } else {
                    header
                }
                if isOpen { content }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tracker.card.\(tracker.id)")
        .sheet(item: $guide) { SafariView(url: $0.url).ignoresSafeArea() }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: tracker.symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: tracker.cardTitle)
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// The collapsed card's row (ui.md §3.1): the whole row toggles, with the one-line verdict.
    private func disclosure(_ expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(Theme.Motion.respecting(reduceMotion)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: tracker.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: tracker.cardTitle)
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    Text(verbatim: RyftFeatures.verdict(for: tracker))
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: reduceMotion && expanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(!reduceMotion && expanded.wrappedValue ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(tracker.cardTitle), \(RyftFeatures.verdict(for: tracker))"))
        .accessibilityValue(expanded.wrappedValue ? Text("Expanded") : Text("Collapsed"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("tracker.header.\(tracker.id)")
    }

    // MARK: content

    @ViewBuilder private var content: some View {
        if let features {
            Text(verbatim: features.text)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(verbatim: features.spoken))
                .accessibilityIdentifier("tracker.features")
        }
        switch tracker.integration {
        case .none: honestLimit
        case .unknown: otherTracker
        case .appleBuiltin, .vendorApp: capabilities
        }
        if tracker.integration == .none {
            // Nothing to set up: only the vendor's own page.
            if let help = tracker.help { guideRow(help) }
        } else if !steps.isEmpty || tracker.help != nil {
            setUp
        }
        if !habits.isEmpty { bullets("Keep it flowing", habits) }
        if !limits.isEmpty { bullets("Good to know", limits) }
        if tracker.isJustIPhone {
            Text("You can add a tracker any time. RYFT will show how to connect it.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        buttons
    }

    /// "What reaches RYFT": one row per signal, sleep stages as Sleep's detail.
    private var capabilities: some View {
        section("What reaches RYFT") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(TrackerSignal.rows.enumerated()), id: \.element) { index, signal in
                    if index > 0 { Divider().overlay(Theme.separator) }
                    CapabilityRow(title: signal.title, spokenTitle: signal.spoken, state: state(of: signal),
                                  detail: detail(of: signal))
                        .accessibilityIdentifier("tracker.capability.\(signal.rawValue)")
                }
            }
        }
    }

    /// A tracker that writes nothing to Apple Health (ui.md C2): a fact, not a fault, and what stays empty.
    private var honestLimit: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    // Catalog text only ever as an argument, shown verbatim (ADR 0002).
                    Text(verbatim: String(localized: "RYFT can't read \(tracker.name) data on iPhone today."))
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                    Text(verbatim: String(localized: "\(tracker.name) doesn't write to Apple Health, so nothing it records can reach RYFT. Your iPhone's own step count still does."))
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tracker.limit")
            section("What stays empty") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach([TrackerSignal.heartRate, .hrv, .restingHR, .sleep, .respiratoryRate, .spo2], id: \.self) { signal in
                        CapabilityRow(title: signal.title, spokenTitle: signal.spoken, state: .notAvailable)
                        Divider().overlay(Theme.separator)
                    }
                    CapabilityRow(title: TrackerSignal.steps.title, state: .partial, word: String(localized: "From your iPhone"))
                }
            }
        }
    }

    /// "Other" (ui.md C4): no promises, the check shows what arrives.
    private var otherTracker: some View {
        Text("RYFT reads whatever your tracker saves to Apple Health. What arrives depends on the tracker, so the check shows exactly what it is.")
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Set it up": one numbered run, then the vendor's guide and when it was checked.
    private var setUp: some View {
        section("Set it up") {
            VStack(alignment: .leading, spacing: 10) {
                if let app = tracker.appName, tracker.integration == .vendorApp, !steps.isEmpty {
                    Text(verbatim: String(localized: "In \(app)"))
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    NumberedStep(number: index + 1, verbatim: step, total: steps.count)
                }
                if let help = tracker.help {
                    guideRow(help)
                }
            }
        }
    }

    private func guideRow(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                guide = GuidePage(url: url)
            } label: {
                HStack {
                    guideTitle
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isLink)
            .accessibilityValue(checkedText.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
            .accessibilityIdentifier("tracker.guide")
            if let checkedText {
                Text(verbatim: checkedText)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The page's maker: the vendor's (a tracker app, or one that writes nothing), Apple's for its own devices.
    private var guideTitle: Text {
        switch tracker.integration {
        case .vendorApp, .none: return Text("Vendor guide")
        case .appleBuiltin: return Text("Apple's guide")
        case .unknown: return Text("Guide")
        }
    }

    /// "Checked 22 Oct 2026", or with "Steps may have changed." once it's older than 180 days.
    private var checkedText: String? {
        guard let day = DayFormat.date(from: tracker.checked) else { return nil }
        let date = day.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        let age = env.clock.now().timeIntervalSince(day)
        return age > Double(Self.staleAfterDays) * 86_400
            ? String(localized: "Checked \(date). Steps may have changed.")
            : String(localized: "Checked \(date)")
    }

    private func bullets(_ title: LocalizedStringKey, _ items: [String]) -> some View {
        section(title) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(Theme.textTertiary)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            .accessibilityHidden(true)
                        Text(verbatim: item)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        if tracker.integration == .vendorApp, let store = tracker.appStoreURL {
            // The App Store page, which says "Open" itself when the app is installed: no URL schemes (ADR 0002).
            PrimaryButton(verbatim: String(localized: "\(tracker.appTitle) in the App Store"), style: .secondary) {
                openURL(store)
            }
            .accessibilityHint(Text("Opens the App Store."))
            .accessibilityIdentifier("tracker.open")
        }
        if let addTracker {
            PrimaryButton(title: "Add a tracker", style: .secondary) { addTracker() }
                .accessibilityIdentifier("tracker.add")
        }
        if let later {
            // Not the screen's "Show me again later": this one puts off this tracker only.
            Button(action: later) { Text(verbatim: String(localized: "Set up \(tracker.cardTitle) later")) }
                .font(.ryft(.body))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("tracker.later")
        }
    }

    // MARK: rows

    private func state(of signal: TrackerSignal) -> CapabilityState {
        let state = CapabilityState(tracker.capabilities[signal] ?? .unverified)
        // The iPhone alone doesn't "keep" anything from RYFT: those signals aren't there at all.
        return tracker.isJustIPhone && state == .no ? .notAvailable : state
    }

    /// The catalog's reason, or for Sleep whether its stages arrive.
    private func detail(of signal: TrackerSignal) -> String? {
        if let note = tracker.notes[signal] { return note.value(in: locale) }
        guard signal == .sleep, let sleep = tracker.capabilities[.sleep], sleep == .yes || sleep == .partial else { return nil }
        switch tracker.capabilities[.sleepStages] ?? .unverified {
        case .yes: return String(localized: "With sleep stages")
        case .partial: return String(localized: "Sleep stages in part")
        case .no: return String(localized: "No sleep stages")
        case .unverified: return String(localized: "Sleep stages not confirmed")
        }
    }

    /// A hairline, a label (capped at AX3, like `ProfileSection`), then the content.
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.separator)
            Text(title).ryftLabelStyle()
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private struct GuidePage: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
}

extension Tracker {
    /// The picker's name: the two RYFT itself names are localized ("Just my iPhone", "Other").
    var title: String {
        switch id {
        case TrackerSelectionStore.iPhone: return String(localized: "Just my iPhone")
        case "other": return String(localized: "Other")
        default: return name
        }
    }

    /// The card's heading: "Other tracker" for Other.
    var cardTitle: String { integration == .unknown ? String(localized: "Other tracker") : title }
}

/// Setup cards on the bundled catalog, one canvas per variant.
private struct TrackerCardsPreview: View {
    let ids: [String]
    var checked: String?
    /// Several cards as onboarding shows them: the first open, the rest collapsed.
    var collapsible = false
    @State private var open: String?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(ids, id: \.self) { id in
                let tracker = MockData.tracker(id, checked: checked)
                TrackerSetupCard(tracker: tracker,
                                 expanded: collapsible ? Binding(get: { (open ?? ids.first) == id },
                                                                 set: { open = $0 ? id : nil }) : nil,
                                 later: tracker.isJustIPhone ? nil : {},
                                 addTracker: tracker.isJustIPhone ? {} : nil)
            }
        }
        .environment(\.appEnvironment, .preview())
    }
}

#Preview("Tracker card · Garmin", traits: .sizeThatFitsLayout) {
    SchemePair { TrackerCardsPreview(ids: ["garmin"]) }
}

#Preview("Tracker card · Garmin · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair { TrackerCardsPreview(ids: ["garmin"]) }
        .environment(\.locale, Locale(identifier: "de"))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Tracker card · collapsed list", traits: .sizeThatFitsLayout) {
    SchemePair { TrackerCardsPreview(ids: ["garmin", "oura"], collapsible: true) }
}

#Preview("Tracker card · guide stale", traits: .sizeThatFitsLayout) {
    SchemePair { TrackerCardsPreview(ids: ["garmin"], checked: "2026-03-03") }
}

#Preview("Tracker card · Fitbit", traits: .sizeThatFitsLayout) {
    SchemePair { TrackerCardsPreview(ids: ["fitbit"]) }
}

#Preview("Tracker card · Samsung", traits: .sizeThatFitsLayout) {
    SchemePair { TrackerCardsPreview(ids: ["samsung_galaxy_watch"]) }
}

#Preview("Tracker card · Samsung · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair { TrackerCardsPreview(ids: ["samsung_galaxy_watch"]) }
        .environment(\.locale, Locale(identifier: "de"))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Tracker card · Just my iPhone", traits: .sizeThatFitsLayout) {
    SchemePair { TrackerCardsPreview(ids: ["iphone"]) }
}

#Preview("Tracker card · Other", traits: .sizeThatFitsLayout) {
    SchemePair { TrackerCardsPreview(ids: ["other"]) }
}

#Preview("Tracker card · Apple Watch", traits: .sizeThatFitsLayout) {
    SchemePair { TrackerCardsPreview(ids: ["apple_watch"]) }
}

#Preview("Tracker card · Oura", traits: .sizeThatFitsLayout) {
    SchemePair { TrackerCardsPreview(ids: ["oura"]) }
}

/// One step of a numbered run ("1  Open the app's settings."): setup cards and their fixes.
/// Catalog text goes in verbatim, never as Markdown.
struct NumberedStep: View {
    let number: Int
    let text: Text
    /// VoiceOver says "Step 1 of 4" when the run's length is known.
    var total: Int?
    /// The number's circle grows with the text (18 pt at the default size).
    @ScaledMetric(relativeTo: .caption) private var badge: CGFloat = 18

    init(number: Int, text: LocalizedStringKey, total: Int? = nil) {
        self.number = number
        self.text = Text(text)
        self.total = total
    }

    init(number: Int, verbatim: String, total: Int? = nil) {
        self.number = number
        text = Text(verbatim: verbatim)
        self.total = total
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .frame(width: badge, height: badge)
                .background(Theme.accent.opacity(0.14), in: Circle())
            text
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total.map { Text("Step \(number) of \($0)") + Text(verbatim: ", ") + text } ?? text)
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

#Preview("Sync status line · taking longer", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            SyncStatusLineView(line: .scoring(night: true), action: {})
            // 5b: scoring past max(60 s, 3 × the estimate). No pulse; the tap opens Sync details.
            SyncStatusLineView(line: .scoringSlow, action: {})
            SyncStatusLineView(line: .scoring(night: false), action: {})
        }
    }
}

#Preview("Sync status line · taking longer · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        SyncStatusLineView(line: .scoringSlow, action: {})
    }
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Inline message · action", traits: .sizeThatFitsLayout) {
    SchemePair {
        InlineMessage(message: "Your night hasn't reached Apple Health yet. Open Garmin Connect to sync it.", systemImage: "moon.zzz",
                      caption: "Last data from Garmin Connect: Wed 23:24", action: ("Garmin Connect in the App Store", {}))
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
