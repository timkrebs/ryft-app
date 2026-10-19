import SwiftUI

/// Common screen frame: RYFT header at the top, scrolling content, Graphite
/// background, pull-to-refresh (sync + reload).
struct ScreenScaffold<Content: View>: View {
    @Environment(AppState.self) private var state
    @Environment(SyncService.self) private var sync
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
        .refreshable { await state.syncAndRefresh(using: sync) }
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

    @State private var retrying = false
    @State private var showDetails = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if retry != nil || details != nil {
                    HStack(spacing: 18) {
                        if let retry {
                            Button {
                                Task {
                                    retrying = true
                                    await retry()
                                    retrying = false
                                }
                            } label: {
                                if retrying {
                                    ProgressView().controlSize(.small).tint(Theme.accent)
                                } else {
                                    Text(retryTitle).font(.ryft(.callout)).foregroundStyle(Theme.accent)
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                            .disabled(retrying)
                        }
                        if details != nil {
                            Button(showDetails ? "Hide details" : "Details") { showDetails.toggle() }
                                .font(.ryft(.callout))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                                .buttonStyle(.plain)
                        }
                    }
                }
                if showDetails, let details {
                    Text(details)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
            .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
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
