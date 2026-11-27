import SwiftUI

/// An optional step before Apple Health. The provider catalog decides which selected trackers can be linked.
struct TrackerDirectConnectionStep: View {
    let providers: [String]
    let account: String
    let api: any DirectConnectionsAPI
    let browser: () -> any DirectConnectionBrowser
    let showsLockup: Bool
    let back: () -> Void
    let finish: () -> Void

    @Environment(\.appEnvironment) private var env
    @State private var connections = DirectConnectionsModel()

    var body: some View {
        OnboardingScreen(title: Text("Connect your tracker"),
                         lead: Text("Sign in with your tracker service to choose what data to share with RYFT."),
                         showsLockup: showsLockup) {
            VStack(alignment: .leading, spacing: OnboardingSpec.actionGap) {
                ForEach(providers, id: \.self) { provider in connectionCard(provider) }
                if let failure = connections.actionFailure ?? connections.loadFailure {
                    InlineMessage(message: failure.message, systemImage: "exclamationmark.circle")
                }
                if !env.connectivity.isOnline {
                    GroupFooter(Text("Connect to the internet to update the connection."))
                } else if !connections.loading, connections.loadFailure != nil {
                    PillButton(Text("Try again"), style: .secondary) { await refresh() }
                }
                GroupFooter(Text("You can continue setup and connect later in Profile → Devices & sync."))
            }
        }
        .pinnedBar {
            PillButton(Text("Continue"), systemImage: PillButton.Icon.confirm) {
                connections.setAccount(nil)
                finish()
            }
            .accessibilityIdentifier("wear.connect.continue")
            LaterButton(title: "Back") {
                connections.setAccount(nil)
                back()
            }
            .accessibilityIdentifier("wear.connect.back")
        }
        .task(id: account) {
            connections.setAccount(account)
            await refresh()
        }
        .onChange(of: env.connectivity.isOnline) { _, online in
            if online { Task { await refresh() } }
        }
        .onDisappear { connections.setAccount(nil) }
    }

    private func connectionCard(_ provider: String) -> some View {
        let row = connections.providers.first { $0.id == provider }
        let garmin = provider == "garmin"
        let name = garmin ? Text("Garmin Connect") : Text("Suunto")
        return GroupedCard {
            GroupedRow.value(name, value: status(row), icon: "applewatch",
                             identifier: "wear.connect.status.\(provider)")
            if row?.canConnect == true {
                GroupedRow.action(garmin ? Text("Sign in to Garmin Connect") : Text("Sign in to Suunto"),
                                  systemImage: "arrow.up.right", busy: connections.activeProvider == provider,
                                  identifier: "wear.connect.\(provider)") {
                    Task {
                        guard connections.account == account else { return }
                        await connections.link(provider, api: api, browser: browser(), now: { env.clock.now() })
                    }
                }
                .disabled(!env.connectivity.isOnline || connections.loading || connections.activeProvider != nil)
            }
        }
    }

    private func status(_ row: DirectProviderRow?) -> Text {
        if let row { return Text(verbatim: row.status.title) }
        return connections.loading ? Text("Checking availability") : Text("Currently unavailable")
    }

    private func refresh() async {
        guard connections.account == account, env.connectivity.isOnline else { return }
        await connections.refresh(api)
    }
}
