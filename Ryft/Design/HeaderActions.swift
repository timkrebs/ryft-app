import SwiftUI

@MainActor
struct HeaderActions: View {
    @Environment(AppState.self) private var state
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        let sync = screens.homeSync
        let nextChange = sync.nextStateChange
        HStack(spacing: ScreenHeaderSpec.minGap) {
            CircleButton(systemImage: "plus", accessibilityLabel: Text(QuickLogSheet.titleResource)) {
                state.showsQuickLog = true
            }
            .accessibilityHint(Text("Opens Quick log", comment: "VoiceOver hint for the header's Quick log button."))
            .accessibilityIdentifier("header.quickLog")

            HeaderAvatar(initials: screens.profile.identity.initials,
                         status: SyncStatusText(state: sync.state, sources: sync.sources, now: sync.now,
                                                scoresTakingLonger: sync.scoresTakingLonger),
                         canSync: sync.canSync, open: state.openProfile) {
                await sync.sync(trigger: .homescreenTopRight) == .success
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .task(id: nextChange) { await sync.updateState(at: nextChange) }
    }
}

enum AvatarSyncBadge: Equatable {
    case upToDate, error, none, syncing

    init(state: SyncIndicatorState) {
        switch state {
        case .upToDate: self = .upToDate
        case .error: self = .error
        case .stale: self = .none
        case .syncing: self = .syncing
        }
    }

    var dot: Color? {
        switch self {
        case .upToDate: Theme.accentSecondary
        case .error: Theme.warning
        case .none, .syncing: nil
        }
    }
}

@MainActor
private struct HeaderAvatar: View {
    let initials: String?
    let status: SyncStatusText
    let canSync: Bool
    let open: () -> Void
    let sync: @MainActor () async -> Bool

    @State private var impact = 0
    @State private var success = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let badge = AvatarSyncBadge(state: status.state)
        Button(action: open) {
            ZStack {
                Circle().fill(Theme.surface)
                    .frame(width: CircleButton.diameter, height: CircleButton.diameter)
                if let initials {
                    Text(verbatim: initials)
                        .font(.ryftNumber(size: CircleButton.iconSize, weight: .light))
                } else {
                    Image(systemName: "person")
                        .font(.system(size: CircleButton.iconSize, weight: .regular))
                }
            }
        }
        .buttonStyle(CircleButtonStyle())
        .overlay(alignment: .topTrailing) {
            if let color = badge.dot {
                Circle().fill(color)
                    .frame(width: Theme.Metrics.controlOutline * 4, height: Theme.Metrics.controlOutline * 4)
                    .padding(Theme.Metrics.itemSpacing / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if badge == .syncing {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1)
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Theme.textSecondary, lineWidth: Theme.Metrics.controlOutline)
                        .rotationEffect(.degrees(reduceMotion ? 0 : 360 * turn))
                }
                .frame(width: CircleButton.diameter, height: CircleButton.diameter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(Text(AppTab.profile.title))
        .accessibilityValue(Text(verbatim: status.accessibilityValue))
        .accessibilityHint(Text("Opens Profile. Touch and hold for sync options.",
                                comment: "VoiceOver hint for the header avatar."))
        .accessibilityIdentifier("header.avatar")
        .sensoryFeedback(.impact(weight: .light), trigger: impact)
        .sensoryFeedback(.success, trigger: success)
        .contextMenu { status.menu(enabled: canSync, sync: syncNow) }
    }

    private func syncNow() {
        impact += 1
        Task {
            if await sync() { success += 1 }
        }
    }
}

#Preview("Header actions", traits: .sizeThatFitsLayout) {
    DarkPreview {
        HeaderActions()
            .previewEnvironment(.preview(flags: [.structureV2: true]))
    }
}

#Preview("Avatar sync badges", traits: .sizeThatFitsLayout) {
    let states: [SyncIndicatorState] = [.upToDate, .error(.source), .stale(.old), .syncing]
    DarkPreview {
        HStack(spacing: ScreenHeaderSpec.minGap) {
            ForEach(Array(states.enumerated()), id: \.offset) { index, state in
                HeaderAvatar(initials: index == 0 ? nil : "AD", status: SyncStatusText(state: state, sources: [], now: .now),
                             canSync: true, open: {}) { true }
            }
        }
    }
}
