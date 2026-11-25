import SwiftUI

/// A provider uses the same grouped rows and connection actions as the rest of Devices & sync.
struct DirectProviderDetailView: View {
    let row: DirectProviderRow
    let placement: DevicesPagePlacement
    let online: Bool
    let loading: Bool
    let working: Bool
    let busy: Bool
    let failure: DirectConnectionFailure?
    var revocationPending = false
    let refresh: () async -> Void
    let connect: () async -> Void
    let disconnect: () async -> Void

    @State private var confirmingDisconnect = false

    var body: some View {
        SubpageScaffold(Text(verbatim: row.name), navigation: placement.navigation, isSheet: placement.isSheet) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                connectionCard
                if !row.kinds.isEmpty { dataCard }
                if row.canConnect {
                    PillButton(row.status == .available ? Text("Connect account") : Text("Reconnect account"),
                               systemImage: PillButton.Icon.linkOut, busy: working, action: connect)
                        .disabled(!online || loading || (busy && !working))
                        .accessibilityIdentifier("devices.direct.connect")
                }
                if row.canDisconnect {
                    PillButton(Text("Disconnect"), style: .destructive) { confirmingDisconnect = true }
                        .disabled(!online || loading || busy)
                        .accessibilityIdentifier("devices.direct.disconnect")
                }
                if !online {
                    GroupFooter(Text("Offline. Reconnect to refresh this status or change your connection."))
                } else if let failure {
                    GroupFooter(Text(verbatim: failure.message))
                } else if revocationPending {
                    GroupFooter(Text("Disconnected from RYFT. Revoking access at the provider is still pending."))
                }
            }
        }
        .devicesPagePlacement(placement)
        .confirmationDialog("Disconnect provider?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect and delete direct data", role: .destructive) { Task { await disconnect() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
            This stops future direct sync and removes health data imported through this connection. Any copies synced through Apple Health are kept. \
            RYFT asks the provider to revoke access when supported.
            """)
        }
    }

    private var connectionCard: some View {
        GroupedCard(Text("Connection"), footer: footer) {
            GroupedRow.value(Text("Status"), value: Text(verbatim: row.status.title), identifier: "devices.direct.status")
            if let date = row.connection?.lastDataAt {
                GroupedRow.value(Text("Last data received"),
                                 value: Text(date, format: .dateTime.month().day().hour().minute()))
            }
            if online {
                GroupedRow.action(Text("Refresh status"), systemImage: "arrow.clockwise", busy: loading,
                                  identifier: "devices.direct.refresh") {
                    Task { await refresh() }
                }
                .disabled(busy)
            }
        }
    }

    private var dataCard: some View {
        GroupedCard(Text("Shared health data"), footer: Text("You review the requested permissions when you link your provider account.")) {
            GroupedRow.value(Text("Supported data"), value: Text(verbatim: DevicesViewModel.kinds(row.kinds)))
            if (row.connection?.history ?? row.offer?.history) == "none" {
                GroupedRow.value(Text("History"), value: Text("From the time you connect"))
            }
        }
    }

    private var footer: Text {
        switch row.status {
        case .comingSoon: Text("Direct connection will be available after partner setup is complete.")
        case .waitingForData: Text("RYFT will show the latest data here once the provider sends it.")
        case .reauthorize: Text("Reconnect to resume receiving data from this provider.")
        case .unavailable, .full: Text("You can check availability again later.")
        case .available, .connected, .revoked:
            Text("Direct data appears in your existing health views when available.")
        }
    }
}

#if DEBUG
#Preview("Garmin coming soon") {
    DirectProviderDetailView(row: .init(id: "garmin", availability: "partner_onboarding", offer: nil, connection: nil),
                             placement: .pushed, online: true, loading: false, working: false, busy: false, failure: nil,
                             refresh: {}, connect: {}, disconnect: {})
        .preferredColorScheme(.dark)
}

#Preview("Suunto connected") {
    DirectProviderDetailView(row: .init(id: "suunto", availability: "available", offer: nil,
                                      connection: .init(provider: "suunto", status: "connected", connectedAt: .now,
                                                        lastDataAt: .now, provides: ["workout"], history: "none")),
                             placement: .pushed, online: true, loading: false, working: false, busy: false, failure: nil,
                             refresh: {}, connect: {}, disconnect: {})
        .preferredColorScheme(.dark)
}
#endif
