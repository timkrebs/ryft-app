import SwiftUI
import UIKit
import UserNotifications

/// Profile → Notifications. Wrapper builds the model from the screen models.
struct NotificationSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        NotificationSettingsScreen(model: NotificationSettingsViewModel(state: state, push: screens.push))
    }
}

/// Profile → Notifications in Nocturne (PR 6 C §4.7): what RYFT may tell the user, and when not to.
///
/// - Rolling out (`push.enabled` off for the account): a notice and the four categories as rows to read, no switch that
///   looks on while nothing can be sent.
/// - Otherwise "Notify me about" (a switch per category, its sentence under the title) and "Quiet hours" (a switch, then
///   From and Until as time chips while it's on; from AX1 the chips go under their titles). The values are the account's as
///   last loaded (`AppState.user`), so the page reads the same offline. While a change is on its way every switch and both
///   chips are disabled (35 %, §4.7); a change RYFT refuses or that can't be sent (offline) goes back, and a notice under
///   its group says so, with the status and request ID as its caption.
/// - Not asked yet: a notice and the pinned "Allow notifications". Off in iOS Settings: a notice (the switches stay, the
///   choices are kept) and the pinned "Open Settings".
private struct NotificationSettingsScreen: View {
    @State var model: NotificationSettingsViewModel
    /// The switch whose change is on its way: a category's raw value, or `quietKey`.
    @State private var pending: String?
    @Environment(\.openURL) private var openURL

    private static let quietKey = "quietHours"

    var body: some View {
        SubpageScaffold(Text("Notifications")) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                if model.showsSwitches {
                    permission
                    categories
                    if let failure = model.failure, !failure.quietHours { notice(failure) }
                    quietHours
                    if let failure = model.failure, failure.quietHours { notice(failure) }
                } else {
                    // No switches that look on while nothing can be sent.
                    rollout
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { pinned }
        .task { await model.load() }
    }

    // MARK: permission

    @ViewBuilder
    private var permission: some View {
        switch model.mode {
        case .allowed, .rollingOut:
            EmptyView()
        case .notAsked:
            InlineMessage(message: String(localized: "RYFT hasn't asked to send notifications yet."), systemImage: "bell",
                          announces: false, readsAsOne: true)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("notifications.notAsked")
        case .denied:
            InlineMessage(message: String(localized: "Notifications are off in iOS Settings"), systemImage: "bell.slash",
                          caption: String(localized: "Your choices below are kept for when you turn notifications back on."),
                          announces: false, readsAsOne: true)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("notifications.denied")
        }
    }

    /// The page's one action, pinned: ask now, or go to iOS Settings.
    @ViewBuilder
    private var pinned: some View {
        switch model.mode {
        case .notAsked:
            PinnedActionBar {
                PillButton(Text("Allow notifications"), systemImage: "bell") { await model.allow() }
                    .accessibilityIdentifier("notifications.allow")
            }
        case .denied:
            PinnedActionBar {
                PillButton(Text("Open Settings"), systemImage: PillButton.Icon.linkOut) {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("notifications.openSettings")
            }
        case .allowed, .rollingOut:
            EmptyView()
        }
    }

    // MARK: rolling out

    /// `push.enabled` is off for this account: what will come, as a list to read.
    private var rollout: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
            InlineMessage(message: String(localized: "Notifications are being rolled out"), systemImage: "bell",
                          caption: String(localized: "We'll let you know here when notifications reach your account."),
                          announces: false, readsAsOne: true)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("notifications.rollingOut")
            GroupedCard(Text("You'll get")) {
                ForEach(NotificationCategory.allCases) { category in
                    RolloutRow(title: Text(NotificationSettingsViewModel.title(category)),
                               detail: Text(NotificationSettingsViewModel.detail(category)))
                }
            }
        }
    }

    // MARK: switches

    /// A change is on its way: nothing else can change meanwhile (the model rolls a refused one back to what was saved).
    private var inFlight: Bool { pending != nil || model.saving }

    private func notice(_ failure: NotificationSettingsFailure) -> some View {
        InlineMessage(message: failure.message, systemImage: "exclamationmark.circle", caption: failure.details)
            .textSelection(.enabled)
    }

    private var categories: some View {
        GroupedCard(Text("Notify me about")) {
            ForEach(NotificationCategory.allCases) { category in
                GroupedRow.toggle(Text(NotificationSettingsViewModel.title(category)),
                                  detail: Text(NotificationSettingsViewModel.detail(category)),
                                  identifier: "notifications.\(category.rawValue)",
                                  isOn: change(category.rawValue, get: { model.isOn(category) },
                                               set: { await model.set(category, on: $0) }))
                    .disabled(inFlight)
            }
        }
    }

    private var quietHours: some View {
        GroupedCard(Text("Quiet hours"),
                    footer: Text("Times are local. Equal times turn quiet hours off; a start later than the end spans midnight.")) {
            GroupedRow.toggle(Text("Pause at night"),
                              detail: Text("Nothing arrives in this window; the morning score waits until it ends."),
                              identifier: "notifications.quietHours",
                              isOn: change(Self.quietKey, get: { model.quietHoursOn }, set: { await model.setQuietHours(on: $0) }))
                .disabled(inFlight)
            if model.quietHoursOn {
                ValueChipRow(Text("From")) {
                    timeChip(Text("From"), get: { model.quietFrom }, set: { await model.setQuietFrom($0) })
                }
                ValueChipRow(Text("Until")) {
                    timeChip(Text("Until"), get: { model.quietTo }, set: { await model.setQuietTo($0) })
                }
            }
        }
    }

    /// A time chip: each value the wheel stops on is saved; only the latest save's answer shows (the model). Disabled and at
    /// 35 % while a change is on its way, as the switches are.
    private func timeChip(_ label: Text, get: @escaping () -> Date, set: @escaping (Date) async -> Void) -> some View {
        ValueChip(label, date: Binding(get: get, set: { date in Task { await set(date) } }), displayedComponents: .hourAndMinute)
            .disabled(inFlight)
            .opacity(inFlight ? GroupedListSpec.disabledOpacity : 1)
    }

    /// A switch's binding: the model's value; a change marks the switch pending while it's saved. One change at a time
    /// (the model rolls a refused change back to the values before it), so a tap on another switch meanwhile does nothing.
    private func change(_ key: String, get: @escaping () -> Bool, set: @escaping (Bool) async -> Void) -> Binding<Bool> {
        Binding(get: get, set: { on in
            guard pending == nil, !model.saving else { return }
            pending = key
            Task {
                await set(on)
                pending = nil
            }
        })
    }
}

/// A category while notifications are being rolled out: its title and its sentence as a row to read, one element that
/// VoiceOver reads title first (no switch, nothing to tap).
private struct RolloutRow: View {
    let title: Text
    let detail: Text

    var body: some View {
        GroupedRowLabel(title, detail: detail)
            .groupedRowHairline()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(detail)
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - previews (dark only)

@MainActor
private func notificationsPreview(_ status: UNAuthorizationStatus, rolledOut: Bool = true, quietHours: Bool = false,
                                  size: DynamicTypeSize = .large) -> some View {
    let notifier = MockNotifier()
    notifier.status = status
    let state = AppState.preview(flags: rolledOut ? [.pushEnabled: true] : [:], notifier: notifier)
    if quietHours, let user = state.user {
        state.user?.notifications = NotificationPrefs(categories: user.notifications.categories,
                                                      quietHours: NotificationSettingsViewModel.defaultQuietHours)
    }
    return NavigationStack { NotificationSettingsView() }
        .previewEnvironment(state)
        .toggleStyle(.ryft)
        .dynamicTypeSize(size)
}

#Preview("Notifications · allowed") { notificationsPreview(.authorized) }
#Preview("Notifications · rolling out") { notificationsPreview(.authorized, rolledOut: false) }
#Preview("Notifications · off in iOS") { notificationsPreview(.denied) }
#Preview("Notifications · not asked") { notificationsPreview(.notDetermined) }
#Preview("Notifications · AX3") { notificationsPreview(.authorized, size: .accessibility3) }
#Preview("Notifications · quiet hours") { notificationsPreview(.authorized, quietHours: true) }
#Preview("Notifications · quiet hours · AX3") { notificationsPreview(.authorized, quietHours: true, size: .accessibility3) }
