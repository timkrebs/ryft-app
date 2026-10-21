import SwiftUI
import UIKit

/// Profile → Notifications. Wrapper builds the model from the screen models.
struct NotificationSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        NotificationSettingsScreen(model: NotificationSettingsViewModel(state: state, push: screens.push))
    }
}

private struct NotificationSettingsScreen: View {
    @State var model: NotificationSettingsViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                if model.showsSwitches {
                    permission
                    categories
                    quietHours
                } else {
                    // No switches that look on while nothing can be sent.
                    rollout
                }
                if let error = model.error {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle")
                }
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await model.load() }
    }

    /// `push.enabled` is off for this account: what will come, as a list to read.
    private var rollout: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Notifications are being rolled out", systemImage: "bell.badge")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("You'll get").ryftLabelStyle()
                    ForEach(NotificationCategory.allCases) { category in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NotificationSettingsViewModel.title(category))
                                .font(.ryft(.body))
                                .foregroundStyle(Theme.textPrimary)
                            Text(NotificationSettingsViewModel.detail(category))
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Divider().overlay(Theme.separator)
                Text("We'll let you know here when notifications reach your account. Your choices are kept.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("notifications.rollingOut")
    }

    @ViewBuilder
    private var permission: some View {
        switch model.mode {
        case .allowed, .rollingOut:
            EmptyView()
        case .notAsked:
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("RYFT hasn't asked to send notifications yet.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                    PrimaryButton(title: "Allow notifications", style: .secondary) { await model.allow() }
                }
            }
        case .denied:
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Notifications are off in iOS Settings", systemImage: "bell.slash")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your choices below are kept for when you turn them on.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Open Settings", style: .secondary) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            }
            .accessibilityIdentifier("notifications.denied")
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notify me about").ryftLabelStyle()
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(NotificationCategory.allCases) { category in
                        Toggle(isOn: Binding(get: { model.isOn(category) },
                                             set: { on in Task { await model.set(category, on: on) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NotificationSettingsViewModel.title(category))
                                    .font(.ryft(.body))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(NotificationSettingsViewModel.detail(category))
                                    .font(.ryft(.caption))
                                    .foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.accent)
                        if category != NotificationCategory.allCases.last {
                            Divider().overlay(Theme.separator)
                        }
                    }
                }
            }
        }
    }

    private var quietHours: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quiet hours").ryftLabelStyle()
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: Binding(get: { model.quietHoursOn },
                                         set: { on in Task { await model.setQuietHours(on: on) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pause at night")
                                .font(.ryft(.body))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Nothing arrives in this window; the morning score waits until it ends.")
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.accent)
                    if model.quietHoursOn {
                        Divider().overlay(Theme.separator)
                        DatePicker("From", selection: Binding(get: { model.quietFrom },
                                                              set: { d in Task { await model.setQuietFrom(d) } }),
                                   displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: Binding(get: { model.quietTo },
                                                               set: { d in Task { await model.setQuietTo(d) } }),
                                   displayedComponents: .hourAndMinute)
                    }
                }
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
            }
            Text("Times are local. Equal times turn quiet hours off; a start later than the end spans midnight.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Notifications · dark") {
    NavigationStack { NotificationSettingsView() }.previewEnvironment(.preview(flags: [.pushEnabled: true]))
}

#Preview("Notifications · rolling out") {
    NavigationStack { NotificationSettingsView() }.previewEnvironment()
}

#Preview("Notifications · rolling out · light · de") {
    NavigationStack { NotificationSettingsView() }
        .previewEnvironment(scheme: .light)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Notifications · light") {
    NavigationStack { NotificationSettingsView() }
        .previewEnvironment(.preview(flags: [.pushEnabled: true]), scheme: .light)
}
