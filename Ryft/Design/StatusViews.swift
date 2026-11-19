import SwiftUI
import UIKit

/// A tab's root page: the RYFT header at the top (or the screen's own), scrolling content on the screen colour,
/// pull-to-refresh (sync + reload), no navigation bar.
///
/// The tab bar (`RyftTabBar`, design.md §P5-2) is not over the page: the tab ends at the bar's top (`ryftTab()`), so the
/// page's viewport does too, and nothing sits under the bar at the end of the scroll; the 32 pt under the content are the
/// air under the last card, not room for the bar. A re-tap on the selected tab rebuilds the tab (`AppState.reselect`), so
/// the page starts at the top again: nothing to expose or wire here.
struct ScreenScaffold<Content: View>: View {
    @Environment(ScreenModels.self) private var screens
    /// The centred `RyftHeader` above the content. Today and Sleep in Nocturne draw their own `ScreenHeader` as the
    /// content's first row and pass `false` (design.md §P4-1, §P4-2); the content then starts at the safe-area top.
    var showsHeader = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Metrics.sectionSpacing) {
                if showsHeader {
                    RyftHeader()
                        .padding(.top, 6)
                }
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

/// The banner's numbers (Nocturne, PR 6 A G6, D6A-10; C §2.7): an opaque `surface` card, the grouped card's radius, no
/// stroke, 14 above and 16 at the sides.
enum InlineMessageSpec {
    static let radius = Theme.Metrics.neutralTileRadius
    static let topPadding: CGFloat = 14
    static let horizontalPadding: CGFloat = 16
    /// Under the text when there are no buttons; with buttons their 44 pt targets leave room under their labels, so 2.
    static let bottomPadding: CGFloat = 14, bottomPaddingUnderButtons: CGFloat = 2
    /// The glyph: 16 pt at the default size, growing with the sentence; 12 to the text.
    static let glyphSize: CGFloat = 16
    static let glyphGap: CGFloat = 12
    /// The sentence → its caption, and the text → the buttons' row.
    static let captionGap: CGFloat = 4
    static let buttonsGap: CGFloat = 6
    /// Between two text buttons in a row.
    static let buttonSpacing: CGFloat = 18
}

/// Calm inline message for routine failures and notices — never a bare alert, never coral for a failure (Nocturne, PR 6
/// A G6): an opaque `surface` card, radius 22; a 16 pt glyph and the sentence in `textPrimary`; a caption in
/// `textSecondary` (tabular digits); text buttons under it from the card's leading edge, 18 apart, each at least 44 × 44:
/// "Try again" 16 Medium in ink, "Details" 15 in `textSecondary`, a plain `action` 16 Medium in ink. They go in a row while
/// they fit, one under the other otherwise and at accessibility sizes. While `retry` runs, "Trying again…" (or
/// `retryingTitle`) in `textSecondary`, never a spinner.
///
/// Severity is the glyph and the words: `.neutral` (the default) draws the glyph in ink; `.attention` in `warning`, only
/// where the user has something to fix; `.destructive` in `alert`, only for a destructive outcome. The sentence says it.
///
/// VoiceOver: the sentence and the caption are read in order, then each button. `readsAsOne` makes the glyph, the sentence
/// and the caption one element (a settings notice). A banner is announced when it appears and when its sentence changes
/// (low priority: it waits for what VoiceOver is saying), once per sentence; `announces: false` for a notice that is part
/// of the page.
struct InlineMessage: View {
    /// How much the message asks of the user: the glyph's ink.
    enum Severity: Sendable {
        case neutral, attention, destructive

        var glyphColor: Color {
            switch self {
            case .neutral: return Theme.textPrimary
            case .attention: return Theme.warning
            case .destructive: return Theme.alert
            }
        }
    }

    let message: String
    var systemImage = "wifi.exclamationmark"
    var retryTitle: LocalizedStringKey = "Try again"
    /// Status and request ID behind a "Details" toggle (for support and server logs).
    var details: String?
    var retry: (() async -> Void)?
    /// A second line under the message ("Showing data from 14:05"), monospaced digits.
    var caption: String?
    /// While `retry` runs, this label (disabled); "Trying again…" when nil.
    var retryingTitle: LocalizedStringKey?
    /// Shows the retrying state from outside (previews).
    var isRetrying = false
    /// "Details" opens something (a sheet) instead of the inline toggle.
    var onDetails: (() -> Void)?
    /// Prefix of the buttons' identifiers: "<prefix>.retry", "<prefix>.details", "<prefix>.action".
    var identifier = "inlineMessage"
    /// A plain action, not a retry ("Garmin Connect in the App Store"): a text button in the buttons' row, after "Try
    /// again". Its title is already localized (`String(localized:)`) and shown verbatim.
    var action: (title: String, perform: () -> Void)?
    /// The glyph's ink; the sentence carries the words.
    var severity: Severity = .neutral
    /// Announce the sentence when the banner appears and when it changes.
    var announces = true
    /// The glyph, the sentence and the caption as one VoiceOver element.
    var readsAsOne = false

    @State private var retrying = false
    @State private var showDetails = false
    /// The sentence last announced: a banner that scrolls out and back in isn't announced again.
    @State private var announced: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 16 pt at the default size, growing with the message's callout text.
    @ScaledMetric(relativeTo: .callout) private var iconSize: CGFloat = InlineMessageSpec.glyphSize

    private var hasButtons: Bool { retry != nil || details != nil || onDetails != nil || action != nil }
    private var isBusy: Bool { retrying || isRetrying }

    private var bottomPadding: CGFloat {
        guard hasButtons, !showDetails else { return InlineMessageSpec.bottomPadding }
        // At accessibility sizes a label is taller than its target and would sit on the card's edge.
        return typeSize.isAccessibilitySize ? InlineMessageSpec.bottomPadding : InlineMessageSpec.bottomPaddingUnderButtons
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InlineMessageSpec.buttonsGap) {
            sentence
            if hasButtons { buttons }
            if showDetails, let details {
                Text(details)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, InlineMessageSpec.bottomPadding - InlineMessageSpec.bottomPaddingUnderButtons)
            }
        }
        .padding(.horizontal, InlineMessageSpec.horizontalPadding)
        .padding(.top, InlineMessageSpec.topPadding)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: InlineMessageSpec.radius, style: .continuous))
        .onAppear { announce() }
        .onChange(of: message) { announce() }
    }

    @ViewBuilder private var sentence: some View {
        let row = HStack(alignment: .top, spacing: InlineMessageSpec.glyphGap) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(severity.glyphColor)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: InlineMessageSpec.captionGap) {
                Text(message)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption)
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        if readsAsOne {
            row.accessibilityElement(children: .combine)
        } else {
            row
        }
    }

    /// The text buttons: a row while they fit on one line each, else (and at accessibility sizes) one under the other.
    @ViewBuilder private var buttons: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) { buttonViews(stacked: true) }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: InlineMessageSpec.buttonSpacing) { buttonViews(stacked: false) }
                VStack(alignment: .leading, spacing: 0) { buttonViews(stacked: true) }
            }
        }
    }

    @ViewBuilder private func buttonViews(stacked: Bool) -> some View {
        if let retry {
            Button {
                Task {
                    retrying = true
                    await retry()
                    retrying = false
                }
            } label: {
                Group {
                    if isBusy {
                        Text(retryingTitle ?? "Trying again…").foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(retryTitle).foregroundStyle(Theme.textPrimary)
                    }
                }
                .font(.ryft(.button))
            }
            .modifier(TextButtonFrame(stacked: stacked))
            .disabled(isBusy)
            .accessibilityIdentifier("\(identifier).retry")
        }
        if let action {
            Button(action: action.perform) {
                Text(verbatim: action.title)
                    .font(.ryft(.button))
                    .foregroundStyle(Theme.textPrimary)
            }
            .modifier(TextButtonFrame(stacked: stacked))
            .accessibilityIdentifier("\(identifier).action")
        }
        if let onDetails {
            Button(action: onDetails) {
                Text("Details").font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
            }
            .modifier(TextButtonFrame(stacked: stacked))
            .accessibilityIdentifier("\(identifier).details")
        } else if details != nil {
            Button { showDetails.toggle() } label: {
                Text(showDetails ? "Hide details" : "Details").font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
            }
            .modifier(TextButtonFrame(stacked: stacked))
        }
    }

    private func announce() {
        guard announces, announced != message else { return }
        announced = message
        var text = AttributedString(message)
        text.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(text).post()
    }
}

/// A text button's 44 × 44 pt target: one line in a row, wrapping and full width when the buttons stack.
private struct TextButtonFrame: ViewModifier {
    let stacked: Bool

    func body(content: Content) -> some View {
        content
            .lineLimit(stacked ? nil : 1)
            .fixedSize(horizontal: !stacked, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(minWidth: Theme.Metrics.minHitTarget, minHeight: Theme.Metrics.minHitTarget, alignment: .leading)
            .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
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
    /// `centered`: centred, each button 44 pt high (Today before Nocturne). `leading`: Nocturne's status row (design.md
    /// §P4-1, row 4), leading-aligned and as high as its text, each button's tap target 44 pt or more around it
    /// (`hitOutset` past the text above and below), so the row adds one text line to the board, not 44 pt.
    enum Alignment: Sendable { case centered, leading }

    let line: SyncLine
    /// The line's tap: the gate's screen, or Sync details. Without it the line is plain text.
    var action: (() -> Void)? = nil
    /// "Try again" on a stale line.
    var retry: (() async -> Void)? = nil
    var alignment: Alignment = .centered

    /// `leading`: the tap target's least outset past the text above and below; a shorter line gets more, so the
    /// target is always 44 pt or more (`verticalOutset`, VN5).
    nonisolated static let hitOutset: CGFloat = 14

    /// `leading`: the outset above and below a label `textHeight` high: `hitOutset`, or what makes the target a device
    /// pixel (`scale`) over 44, on the pixel grid. The target's edges snap to the grid: one exactly 44 tall, its edges on
    /// half pixels, came out 43.67 on the fault line (R3-E); with a pixel to spare it snaps to 44 or more.
    nonisolated static func verticalOutset(textHeight: CGFloat, scale: CGFloat) -> CGFloat {
        let scale = max(scale, 1)
        let outset = max(hitOutset, (44 + 1 / scale - textHeight) / 2)
        // Up to the grid; 1e-6 keeps an outset already on it (14.67 × 3 = 44.000…01) where it is.
        return (outset * scale - 1e-6).rounded(.up) / scale
    }

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
                    tapTarget(label(now: now).foregroundStyle(Theme.accent))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens what's needed"))
                .accessibilityIdentifier("today.actionNeeded")
            } else {
                label(now: now).foregroundStyle(Theme.accent)
            }
        case .stale:
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: alignment == .leading ? .leading : .center, spacing: 0))
                : AnyLayout(HStackLayout(spacing: 6))
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
                        tapTarget(Text("Try again")
                            .font(.ryft(.caption))
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.accent))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Tries to load your data again"))
                    .accessibilityIdentifier("today.syncLine.retry")
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
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
                tapTarget(label(now: now).foregroundStyle(color))
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
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.ryft(.caption))
        .frame(maxWidth: current.isStale ? nil : .infinity, alignment: alignment == .leading ? .leading : .center)
    }

    /// A button's label as its tap target: at least 44 pt high (`centered`), or as high as the text with the target
    /// `verticalOutset` above and below it (`leading`: 44 or more for one line), so the row's height is the text's.
    @ViewBuilder
    private func tapTarget(_ label: some View) -> some View {
        switch alignment {
        case .centered:
            label.frame(minHeight: 44).contentShape(Rectangle())
        case .leading:
            label.modifier(LeadingTapTarget())
        }
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

/// `SyncStatusLineView`'s `leading` tap target: the label keeps its own height in the layout, its tap target reaches
/// `verticalOutset` past it above and below (a 15.67 pt line at 3x: 14.33 each side, 44.33).
private struct LeadingTapTarget: ViewModifier {
    @State private var textHeight: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let outset = SyncStatusLineView.verticalOutset(textHeight: textHeight, scale: displayScale)
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            .padding(.vertical, outset)
            .contentShape(Rectangle())
            .padding(.vertical, -outset)
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
        case .busy:
            return String(localized: "RYFT is busy right now. Your data is safe; try again in a moment.",
                          comment: "Error card on Today and Sleep → Day's failed night. Server busy or failing (429, 5xx, 408) after retries. Try again.")
        case .unreachable:
            return String(localized: "RYFT can't be reached right now. Your connection looks fine, so this isn't on your side.",
                          comment: "Error card on Today and Sleep → Day's failed night. No HTTP response. Try again. Offline, Sleep shows No connection.")
        case .unexpected:
            return String(localized: "Part of your data couldn't be loaded. The details help us find out why.",
                          comment: "Error card on Today and Sleep → Day's failed night. Any other failure. Try again.")
        case .signedOut:
            return String(localized: "You're signed out, so new data can't load.",
                          comment: "Error card on Today and Sleep → Day's failed night (Sign in). The session ended; new data can't load.")
        case .appTooOld:
            return String(localized: "This version of RYFT is too old to load new data. Update it to continue.",
                          comment: "Error card on Today and Sleep → Day's failed night (no button). App too old for the server; an update helps.")
        }
    }

    /// What the message's button does (ui.md §3), on Today's card and Sleep's failed night: Sign in when signed out;
    /// none for an outdated app until the platform says how to tell (no store link to guess); else Try again. Trying
    /// again fixes neither of the first two.
    enum Action: Equatable, Sendable {
        case retry, signIn, noButton

        /// The button's title: "Sign in", else "Try again" (unused without a button).
        var title: LocalizedStringKey { self == .signIn ? "Sign in" : "Try again" }

        /// The button's action from the caller's two: `retry`, `signIn`, or none for `noButton`.
        func button(retry: (() async -> Void)?, signIn: (() async -> Void)?) -> (() async -> Void)? {
            switch self {
            case .retry: return retry
            case .signIn: return signIn
            case .noButton: return nil
            }
        }
    }

    var action: Action {
        switch self {
        case .signedOut: return .signIn
        case .appTooOld: return .noButton
        case .busy, .unreachable, .unexpected: return .retry
        }
    }

    /// The button on Today's card and Sleep's failed night, decided once for both: `action`, except no Sign in with
    /// demo data on. Demo data needs no account, and a 401 there only comes from fault injection (DEBUG); Sign in signs
    /// out (`AppState.signInAgain`), which would end a real session behind the demo, or do nothing. Details stays.
    func action(isDemo: Bool) -> Action {
        isDemo && action == .signIn ? .noButton : action
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
    /// Demo data is on: no Sign in (`RefreshIssue.Reason.action(isDemo:)`).
    var isDemo = false
    var retry: () async -> Void = {}
    var signIn: () async -> Void = {}
    /// Previews: the "Trying again…" state.
    var isRetrying = false

    @State private var showsDetails = false

    var body: some View {
        let action = issue.reason.action(isDemo: isDemo)
        InlineMessage(message: issue.reason.message, systemImage: issue.reason.systemImage,
                      retryTitle: action.title, retry: action.button(retry: retry, signIn: signIn), caption: age,
                      retryingTitle: "Trying again…", isRetrying: isRetrying,
                      onDetails: { showsDetails = true }, identifier: "refreshIssue")
            .sheet(isPresented: $showsDetails) { RefreshDetailsSheet(issue: issue) }
            // A container: Try again (or Sign in) and Details stay separate buttons for VoiceOver.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.refreshIssue")
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
/// failures in a row; "Send to RYFT" (when Report a problem is wired) and "Copy details". Nocturne (PR 6 A §A-16): the
/// sheet's own header (the title, "Done" as the close circle), the facts as a grouped card, the two pills pinned so they are
/// reachable at the opening (medium) detent, the caption under them.
struct RefreshDetailsSheet: View {
    let issue: RefreshIssue

    @Environment(\.reportProblemDestination) private var reportProblem
    @Environment(\.locale) private var locale
    @State private var copied = false
    @State private var sends = false

    var body: some View {
        NavigationStack {
            SubpageScaffold(Text("Details"), navigation: .close(label: Text("Done")), isSheet: true) {
                GroupedCard {
                    GroupedRow.value(Text("What failed"), value: Text(verbatim: issue.resourceName))
                    GroupedRow.value(Text("HTTP status"), value: Text(verbatim: issue.statusText ?? "—"),
                                     detail: issue.statusText == nil ? Text("No response") : nil)
                    GroupedRow.value(Text("Code"), value: Text(verbatim: issue.error.code ?? "—").monospaced())
                    RequestIDRow(requestID: issue.error.requestID, answered: issue.error.status != nil)
                    GroupedRow.value(Text("Time"), value: Text(verbatim: Self.time(issue.error.at, locale: locale)))
                    GroupedRow.value(Text("Showing data from"),
                                     value: Text(verbatim: issue.dataFrom.map { Self.time($0, locale: locale) } ?? "—"))
                    GroupedRow.value(Text("Failed in a row"), value: Text(issue.failures.formatted()))
                }
            }
            .pinnedBar(footnote: reportProblem == nil ? nil : Text("Sends this and the last 20 requests. No health values.")) {
                if reportProblem != nil {
                    PillButton(Text("Send to RYFT")) { sends = true }
                        .accessibilityIdentifier("refreshDetails.send")
                }
                PillButton(copied ? Text("Copied") : Text("Copy details"), style: .secondary) {
                    // On this iPhone only, and not for long (`LocalPasteboard`).
                    LocalPasteboard.copy(issue.copyText)
                    copied = true
                }
                .disabled(copied)
                .accessibilityIdentifier("refreshDetails.copy")
            }
            .navigationDestination(isPresented: $sends) {
                if let reportProblem {
                    reportProblem(issue.resourceName, issue.reportStatus, issue.error.code, issue.error.requestID)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// "14:07:12" today, else with the date; in the screen's locale (German shows 24-hour time).
    static func time(_ date: Date, locale: Locale) -> String {
        let today = Calendar.current.isDateInToday(date)
        return date.formatted(Date.FormatStyle(date: today ? .omitted : .abbreviated, time: .standard, locale: locale))
    }
}

/// The request ID exactly as received, with a copy button; support searches for it. A row of the Details card:
/// "Request ID", and under it the 36 characters in 12 pt monospaced type (they don't fit beside the label) with the copy
/// button at the end. VoiceOver reads the label and the ID as one element and offers "Copy request ID" as an action.
private struct RequestIDRow: View {
    let requestID: String?
    /// Something answered (a status came back): a missing ID means a proxy answered first.
    let answered: Bool
    @State private var copied = false

    var body: some View {
        if let requestID {
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                Text("Request ID")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                HStack(alignment: .center, spacing: GroupedListSpec.rowSpacing) {
                    // 12 pt: a UUID stays on one line beside the copy button at 390 pt. Copied with the button or the
                    // VoiceOver action, not by selection.
                    Text(verbatim: requestID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: copy) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: GroupedListSpec.glyphSize, weight: .regular))
                            .foregroundStyle(copied ? Theme.textPrimary : Theme.textSecondary)
                            .frame(width: Theme.Metrics.minHitTarget, height: Theme.Metrics.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(copied ? "Copied" : "Copy request ID"))
                    // The glyph lines up with the other rows' values; its 44 pt target reaches into the padding.
                    .padding(.vertical, -RequestIDRowSpec.buttonOverhang)
                    .padding(.trailing, -RequestIDRowSpec.buttonOverhang)
                }
            }
            .padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.vertical, GroupedListSpec.textPadding)
            .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
            .groupedRowHairline()
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: Text("Copy request ID"), copy)
            .accessibilityIdentifier("refreshDetails.requestID")
        } else {
            GroupedRow.value(Text("Request ID"), value: Text("Not available"),
                             detail: answered ? Text("A proxy answered before RYFT did.") : nil)
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

private enum RequestIDRowSpec {
    /// The copy button's 44 pt box reaches this far past its glyph into the row's padding.
    static let buttonOverhang: CGFloat = 12
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

/// One signal in Check sync (ui.md §5.2; Nocturne PR 6 A §A-12, C §4.5): glyph, name and result, every state with its own
/// symbol and words, never colour alone. Not tappable. 46 high (a list row); at accessibility sizes the result goes under
/// the name.
struct CheckRow: View {
    enum Kind: Equatable {
        case waiting, checking
        /// Arrived: the filled check in ink (it was the teal accent; Nocturne keeps teal for recovery).
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
            case .ok: return Theme.textPrimary
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
        .frame(minHeight: Theme.Metrics.listRowHeight)
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
    /// A check's row: arrived in ink, an expected gap neutral, only an unexpected one amber.
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
    DarkPreview { CheckRowPreview() }
}

#Preview("Check row · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { CheckRowPreview() }
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
///
/// Nocturne (PR 6 A §A-12, tokens only; the layout is area C's): a `Card` (radius 22), full-width hairlines between the
/// header, the summary and each section, section titles in `textTertiary`, arrived signals in ink, and the store and
/// "Add a tracker" buttons as secondary pills.
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
                if isOpen {
                    Self.hairline
                    content
                }
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
                    if index > 0 { Self.hairline }
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
                        Self.hairline
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
            // The App Store page, which says "Open" itself when the app is installed. Only Today's hint opens the app by
            // its compiled scheme (`Tracker.appURL`, plan.md decision 3 (data quality), ADR 0012); this card keeps the store page.
            PillButton(verbatim: String(localized: "\(tracker.appTitle) in the App Store"), style: .secondary) {
                openURL(store)
            }
            .accessibilityHint(Text("Opens the App Store."))
            .accessibilityIdentifier("tracker.open")
        }
        if let addTracker {
            PillButton(Text("Add a tracker"), style: .secondary) { addTracker() }
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

    /// A hairline across the whole card, a label (13 pt `textTertiary`, capped at AX3 like `ProfileSection`), then the
    /// content.
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Self.hairline
            Text(title)
                .font(.ryft(.label))
                .foregroundStyle(Theme.textTertiary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// 1 pt `separator` (the grouped list's) across the whole card, past its padding.
    private static var hairline: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Theme.Metrics.hairline)
            .padding(.horizontal, -CardSpec.padding)
            .accessibilityHidden(true)
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
    DarkPreview { TrackerCardsPreview(ids: ["garmin"]) }
}

#Preview("Tracker card · Garmin · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { TrackerCardsPreview(ids: ["garmin"]) }
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Tracker card · collapsed list", traits: .sizeThatFitsLayout) {
    DarkPreview { TrackerCardsPreview(ids: ["garmin", "oura"], collapsible: true) }
}

#Preview("Tracker card · guide stale", traits: .sizeThatFitsLayout) {
    DarkPreview { TrackerCardsPreview(ids: ["garmin"], checked: "2026-03-03") }
}

#Preview("Tracker card · Fitbit", traits: .sizeThatFitsLayout) {
    DarkPreview { TrackerCardsPreview(ids: ["fitbit"]) }
}

#Preview("Tracker card · Samsung", traits: .sizeThatFitsLayout) {
    DarkPreview { TrackerCardsPreview(ids: ["samsung_galaxy_watch"]) }
}

#Preview("Tracker card · Samsung · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { TrackerCardsPreview(ids: ["samsung_galaxy_watch"]) }
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Tracker card · Just my iPhone", traits: .sizeThatFitsLayout) {
    DarkPreview { TrackerCardsPreview(ids: ["iphone"]) }
}

#Preview("Tracker card · Other", traits: .sizeThatFitsLayout) {
    DarkPreview { TrackerCardsPreview(ids: ["other"]) }
}

#Preview("Tracker card · Apple Watch", traits: .sizeThatFitsLayout) {
    DarkPreview { TrackerCardsPreview(ids: ["apple_watch"]) }
}

#Preview("Tracker card · Oura", traits: .sizeThatFitsLayout) {
    DarkPreview { TrackerCardsPreview(ids: ["oura"]) }
}

/// The numbered step's numbers (Nocturne, PR 6 C #9, A §A-12): an outlined circle, no tinted fill.
enum NumberedStepSpec {
    /// The circle at the default size; it grows with the text.
    static let badge: CGFloat = 22
    /// Its outline: 1 pt `textPrimary` at 32 %.
    static let strokeWidth: CGFloat = 1
    static let strokeOpacity = 0.32
}

/// One step of a numbered run ("1  Open the app's settings."): setup cards and their fixes. The number in `textPrimary` in
/// an outlined circle, the step in `textSecondary`. Catalog text goes in verbatim, never as Markdown.
struct NumberedStep: View {
    let number: Int
    let text: Text
    /// VoiceOver says "Step 1 of 4" when the run's length is known.
    var total: Int?
    /// The number's circle grows with the text (22 pt at the default size).
    @ScaledMetric(relativeTo: .caption) private var badge: CGFloat = NumberedStepSpec.badge

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
                .foregroundStyle(Theme.textPrimary)
                .frame(width: badge, height: badge)
                .overlay {
                    Circle().strokeBorder(Theme.textPrimary.opacity(NumberedStepSpec.strokeOpacity),
                                          lineWidth: NumberedStepSpec.strokeWidth)
                }
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
    DarkPreview {
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

/// Nocturne's status row (design.md §P4-1, row 4): leading, the text's height; the borders show the layout boxes.
#Preview("Sync status line · leading", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 12) {
            SyncStatusLineView(line: .upToDate(.now.addingTimeInterval(-120), demo: false), action: {}, alignment: .leading)
                .border(Theme.separator)
            SyncStatusLineView(line: .scoring(night: true), action: {}, alignment: .leading)
            SyncStatusLineView(line: .offline, action: {}, alignment: .leading)
            SyncStatusLineView(line: .stale(since: PreviewIssue.at(14, 5)), action: {}, retry: {}, alignment: .leading)
                .border(Theme.separator)
            SyncStatusLineView(line: .actionNeeded(.consent), action: {}, alignment: .leading)
        }
    }
}

#Preview("Sync status line · leading · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 12) {
            SyncStatusLineView(line: .upToDate(.now.addingTimeInterval(-120), demo: true), action: {}, alignment: .leading)
            SyncStatusLineView(line: .stale(since: PreviewIssue.at(14, 5)), action: {}, retry: {}, alignment: .leading)
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
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
    DarkPreview {
        InlineMessage(message: "Your night hasn't reached Apple Health yet. Open Garmin Connect to sync it.", systemImage: "moon.zzz",
                      caption: "Last data from Garmin Connect: Wed 23:24", action: ("Garmin Connect in the App Store", {}))
    }
}

/// Every look of the banner once (a-17): error with actions, retrying, notices, attention and destructive glyphs.
private struct InlineMessageStates: View {
    var body: some View {
        VStack(spacing: 12) {
            InlineMessage(message: "Couldn't reach RYFT. Showing what was loaded earlier.",
                          details: "HTTP 503 · Request ID 01JD8K2V9Q7M3X", retry: {}, caption: "Showing data from 9:20",
                          announces: false)
            InlineMessage(message: "Couldn't reach RYFT. Showing what was loaded earlier.", retry: {}, isRetrying: true,
                          onDetails: {}, announces: false)
            InlineMessage(message: "Your file is ready. Sign in to continue.", systemImage: "doc.text", announces: false)
            InlineMessage(message: "Sign-in isn't set up in this build.", systemImage: "key", announces: false)
            InlineMessage(message: "Notifications are off for RYFT. Turn them on in Settings.", systemImage: "bell.slash",
                          action: ("Open Settings", {}), severity: .attention, announces: false)
            InlineMessage(message: "Your account is being deleted. This activity is deleted with it.", systemImage: "trash",
                          severity: .destructive, announces: false, readsAsOne: true)
        }
    }
}

#Preview("Inline message · states", traits: .sizeThatFitsLayout) {
    DarkPreview { InlineMessageStates() }
}

#Preview("Inline message · states · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { InlineMessageStates() }
        .environment(\.dynamicTypeSize, .accessibility3)
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

#Preview("Details sheet · with ID") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            RefreshDetailsSheet(issue: PreviewIssue.make(.busy))
                .environment(\.reportProblemDestination) { _, _, _, _ in AnyView(Text(verbatim: "Report a problem")) }
        }
        .preferredColorScheme(.dark)
}

#Preview("Details sheet · no ID") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            RefreshDetailsSheet(issue: PreviewIssue.make(.unreachable))
        }
        .preferredColorScheme(.dark)
}

#Preview("Details sheet · no request ID · AX3") {
    RefreshDetailsSheet(issue: PreviewIssue.make(.busy, requestID: nil))
        .environment(\.reportProblemDestination) { _, _, _, _ in AnyView(Text(verbatim: "Report a problem")) }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
