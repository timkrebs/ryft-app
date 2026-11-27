#if DEBUG
import SwiftUI

struct LocalGarminTestView: View {
    @Environment(\.openURL) private var openURL
    @State private var link = ""
    @State private var pairing: LocalGarminPairing?
    @State private var snapshot: LocalGarminSnapshot?
    @State private var fetching = false
    @State private var failure: LocalGarminFailure?
    @State private var usbPreview = false

    var body: some View {
        SubpageScaffold(Text("Garmin local test")) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                if pairing == nil {
                    GroupedCard(footer: Text("Start the test API on your Mac, then paste its pairing link here. Use the same Wi-Fi network.")) {
                        SecureField("Pairing link", text: $link)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .accessibilityIdentifier("devices.garminLocal.pairing")
                    }
                }
                PillButton(Text(pairing == nil ? "Fetch Garmin data" : "Refresh Garmin data"), busy: fetching) { await fetch() }
                    .disabled(pairing == nil && link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("devices.garminLocal.fetch")
                PillButton(Text("Load USB preview"), style: .secondary) { loadUSB() }
                    .disabled(fetching)
                    .accessibilityIdentifier("devices.garminLocal.usb")
                if let failure {
                    InlineMessage(message: failure.localizedDescription, systemImage: "exclamationmark.circle")
                    if failure == .network, let settings = URL(string: UIApplication.openSettingsURLString) {
                        PillButton(Text("Open RYFT Settings"), style: .secondary) { openURL(settings) }
                    }
                }
                if let snapshot { activities(snapshot) }
                if snapshot != nil {
                    PillButton(Text("Forget local test"), style: .secondary) {
                        pairing = nil
                        snapshot = nil
                        failure = nil
                        usbPreview = false
                    }
                    .disabled(fetching)
                }
            }
        }
    }

    private func activities(_ snapshot: LocalGarminSnapshot) -> some View {
        GroupedCard(Text("Garmin activities"), footer: Text("Local preview on this device. This test does not add activities to your RYFT account.")) {
            GroupedRow.value(Text("Connection"),
                             value: Text(usbPreview ? "USB preview loaded" : "Local API verified"),
                             identifier: "devices.garminLocal.verified")
            GroupedRow.value(Text("Last fetched"), value: Text(snapshot.fetchedAt, format: .dateTime.hour().minute().second()))
            if snapshot.activities.isEmpty {
                GroupedRow.value(Text("Activities"), value: Text("No activities returned"))
            }
            ForEach(Array(snapshot.activities.enumerated()), id: \.offset) { _, activity in
                let duration = activity.durationSeconds.map { Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) }
                let title = activity.sport.map { Text(verbatim: $0.replacingOccurrences(of: "_", with: " ").capitalized) } ?? Text("Activity")
                GroupedRow.value(title, value: Text(verbatim: duration ?? "—"), detail: activity.startedAtLocal.map { Text(verbatim: $0) })
            }
        }
    }

    private func fetch() async {
        guard !fetching else { return }
        failure = nil
        guard let target = pairing ?? LocalGarminPairing(link) else {
            failure = .link
            return
        }
        fetching = true
        defer { fetching = false }
        do {
            let response = try await LocalGarminSnapshot.fetch(target)
            try Task.checkCancellation()
            snapshot = response
            pairing = target
            link = ""
            usbPreview = false
        } catch let error as LocalGarminFailure {
            failure = error
        } catch where !error.isCancellation {
            failure = .response
        } catch {}
    }

    private func loadUSB() {
        failure = nil
        do {
            snapshot = try LocalGarminSnapshot.loadUSB()
            pairing = nil
            link = ""
            usbPreview = true
        } catch let error as LocalGarminFailure {
            failure = error
        } catch {
            failure = .response
        }
    }
}
#endif
