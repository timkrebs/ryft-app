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
                permission
                categories
                quietHours
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

    @ViewBuilder
    private var permission: some View {
        switch model.permission {
        case .allowed:
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
                    Text("Notifications for RYFT are off in Settings. Your choices below are kept for when you turn them on.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Open Settings", style: .secondary) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            }
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
        }
    }
}

#Preview("Notifications · dark") {
    NavigationStack { NotificationSettingsView() }.previewEnvironment()
}

#Preview("Notifications · light") {
    NavigationStack { NotificationSettingsView() }.previewEnvironment(scheme: .light)
}
