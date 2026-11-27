import SwiftUI

struct SyncStatusButton: View {
    let state: SyncIndicatorState
    let sources: [SyncSource]
    let now: Date
    var scoresTakingLonger = false
    var enabled = true
    let sync: @MainActor () async -> Bool

    @State private var impact = 0
    @State private var success = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The rotate effect's speed: 1 is the system's own pace, about a turn a second.
    nonisolated static let rotationSpeed: Double = 1

    var body: some View {
        Button(action: syncNow) {
            // The arrows turn while syncing (continuous, about a turn a second): the common iOS "it's working" and
            // what the device test expected. Under Reduce Motion they stand still; the accessibility value says
            // "Syncing" either way.
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: TodayHeader.calendarIconSize, weight: .regular))
                .symbolEffect(.rotate.clockwise.wholeSymbol, options: .repeat(.continuous).speed(Self.rotationSpeed),
                              isActive: state == .syncing && !reduceMotion)
        }
        .buttonStyle(CircleButtonStyle())
        .overlay(alignment: .topTrailing) {
            if let badge {
                Circle().fill(badge)
                    .frame(width: Theme.Metrics.controlOutline * 4, height: Theme.Metrics.controlOutline * 4)
                    .padding(Theme.Metrics.itemSpacing / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .disabled(!enabled)
        .accessibilityLabel(Text("Sync", comment: "VoiceOver label for the Apple Health sync button in Today's header."))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityHint(Text("Syncs Apple Health now", comment: "VoiceOver hint for tapping the sync button."))
        .accessibilityIdentifier("today.header.sync")
        .sensoryFeedback(.impact(weight: .light), trigger: impact)
        .sensoryFeedback(.success, trigger: success)
        .contextMenu {
            ForEach(sources, id: \.source) { source in
                Button {} label: { Text(verbatim: sourceSummary(source)) }
                    .disabled(true)
            }
            Button(action: syncNow) {
                Text("Sync now", comment: "Action in Today's sync button menu that starts an Apple Health sync.")
            }
            .disabled(!enabled)
        }
    }

    private var badge: Color? {
        switch state {
        case .upToDate: return Theme.accentSecondary
        case .error: return Theme.warning
        case .syncing, .stale: return nil
        }
    }

    private var accessibilityValue: String {
        let stateText: String
        switch state {
        case .syncing:
            stateText = String(localized: "Syncing", comment: "VoiceOver sync status while Apple Health sends or scoring runs.")
        case .upToDate:
            stateText = String(localized: "Up to date", comment: "VoiceOver sync status when recent Apple Health data has been scored and loaded.")
        case .stale(.offline):
            stateText = String(localized: "Offline", comment: "VoiceOver sync status when the last sync could not reach RYFT.")
        case .stale(.scoresPending):
            stateText = String(localized: "Scores are still being calculated", comment: "Sync status after scoring takes longer than three minutes.")
        case .stale:
            stateText = String(localized: "Sync needed", comment: "VoiceOver sync status when Apple Health data is stale or unconfirmed.")
        case .error(.healthAccess):
            stateText = String(localized: "Apple Health access needed", comment: "VoiceOver sync status when RYFT needs permission to read Apple Health.")
        case .error:
            stateText = String(localized: "Sync problem", comment: "Generic sync status when a data source or upload reports an error.")
        }
        if let lastSync = sources.first?.lastSyncAt {
            let age = SyncDetailsModel.lastSyncWords(lastSync, now: now)
            return String(localized: "\(stateText), synced \(age)", comment: "VoiceOver sync value: state followed by when Apple Health last synced.")
        }
        return String(localized: "\(stateText), never synced", comment: "VoiceOver sync value: state followed by the absence of an Apple Health sync.")
    }

    private func sourceSummary(_ source: SyncSource) -> String {
        let name: String
        switch source.source {
        case "garmin": name = String(localized: "Garmin", comment: "Garmin direct data source in Today's sync menu.")
        case "suunto": name = String(localized: "Suunto", comment: "Suunto direct data source in Today's sync menu.")
        default: name = String(localized: "Apple Health", comment: "Apple Health data source in Today's sync menu.")
        }
        let age = SyncDetailsModel.lastSyncWords(source.lastSyncAt, now: now)
        guard let detail = detail(for: source) else {
            return String(localized: "\(name) · \(age)", comment: "Sync menu source name and the time it last synced.")
        }
        return String(localized: "\(name) · \(age) · \(detail)", comment: "Sync menu source name, time it last synced, and its pending or error status.")
    }

    private func detail(for source: SyncSource) -> String? {
        switch source.status {
        case .ok: return nil
        case .pending:
            if scoresTakingLonger {
                return String(localized: "Scores are still being calculated", comment: "Sync status after scoring takes longer than three minutes.")
            }
            return String(localized: "Pending", comment: "Sync menu status for a source whose data is still being processed.")
        case .error:
            switch source.reason {
            case "needs_reauth":
                return String(localized: "Needs reconnecting", comment: "Sync menu status for a provider that needs authorization again.")
            case "consent_required":
                return String(localized: "Consent required", comment: "Sync menu status when consent is required before this source can sync.")
            case "invite_required":
                return String(localized: "Invite required", comment: "Sync menu status when an invite is required before this source can sync.")
            default:
                return String(localized: "Sync problem", comment: "Generic sync status when a data source or upload reports an error.")
            }
        }
    }

    private func syncNow() {
        impact += 1
        Task {
            if await sync() { success += 1 }
        }
    }
}

private struct SyncStatusButtonPreview: View {
    let state: SyncIndicatorState
    var providerStatus: SyncSourceStatus = .ok

    var body: some View {
        let now = TestClock().now()
        let healthAge: TimeInterval = state == .stale(.old) ? 45 * 60 : 4 * 60
        DarkPreview {
            SyncStatusButton(state: state, sources: [
                SyncSource(source: "healthkit", lastSyncAt: now.addingTimeInterval(-healthAge), status: .ok, reason: nil),
                SyncSource(source: "garmin", lastSyncAt: now.addingTimeInterval(-2 * 60 * 60), status: providerStatus,
                           reason: providerStatus == .error ? "needs_reauth" : nil),
            ], now: now) { true }
            .padding(Theme.Metrics.screenPadding)
            .background(Theme.background)
        }
    }
}

#Preview("Sync · Syncing", traits: .sizeThatFitsLayout) { SyncStatusButtonPreview(state: .syncing, providerStatus: .pending) }
#Preview("Sync · Up to date", traits: .sizeThatFitsLayout) { SyncStatusButtonPreview(state: .upToDate) }
#Preview("Sync · Stale", traits: .sizeThatFitsLayout) { SyncStatusButtonPreview(state: .stale(.old)) }
#Preview("Sync · Offline", traits: .sizeThatFitsLayout) { SyncStatusButtonPreview(state: .stale(.offline)) }
#Preview("Sync · Error", traits: .sizeThatFitsLayout) { SyncStatusButtonPreview(state: .error(.source), providerStatus: .error) }
