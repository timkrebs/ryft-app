import SwiftUI

// MARK: - developer (Debug builds only)

#if DEBUG
/// Platform overrides for a compose stack, API key mode (`AUTH_MODE=apikey`), request IDs of recent failures and a connection
/// test, in the page's grouped card (§P5-6.2: the same rows). Not in Release; English only, never in the catalog.
struct ProfileDeveloperGroup: View {
    let model: ProfileViewModel
    @Environment(ScreenModels.self) private var screens
    @Environment(Settings.self) private var settings
    private let apiStatus = APIStatus.shared

    var body: some View {
        // Held as Demo data is (D6, security review N-1): another platform or another credential mid-way would end the
        // withdrawal unsent, or send it somewhere else.
        let held = model.withdrawingConsent
        GroupedCard(GroupTitle(Text(verbatim: "Developer"))) {
            GroupedRow.value(Text(verbatim: "Push registration"), value: Text(verbatim: screens.push.lastResult ?? "—"))
            field("API URL override") {
                TextField(Bundle.configValue("RyftAPIURL") ?? "https://api.ryftlab.de", text: Bindable(settings).devAPIURLOverride)
                    .keyboardType(.URL)
                    .accessibilityIdentifier(ProfileRows.devAPIURL)
            }
            .disabled(held)
            field("Ingest URL override (compose: :8081, needed with an API override)") {
                TextField(Bundle.configValue("RyftIngestURL") ?? "https://ingest.ryftlab.de",
                          text: Bindable(settings).devIngestURLOverride)
                    .keyboardType(.URL)
                    .accessibilityIdentifier(ProfileRows.devIngestURL)
            }
            .disabled(held)
            GroupedRow.toggle(Text(verbatim: "API key mode"),
                              detail: Text(verbatim: held ? "Held while your consent withdrawal is on its way."
                                                          : "Sends a static bearer instead of your session, for a platform started with AUTH_MODE=apikey."),
                              identifier: ProfileRows.devAPIKeyMode, isOn: Bindable(settings).apiKeyMode)
                // Held, the switch alone dims, so "Held while…" stays readable (as Demo data's).
                .toggleStyle(RyftToggleStyle(dimsLabel: !held))
                .disabled(held)
            if settings.apiKeyMode {
                field("API key") {
                    SecureField("Bearer token", text: Bindable(settings).devAPIKey)
                }
                .disabled(held)
            }
            GroupedRow.toggle(Text(verbatim: "Show request IDs"), isOn: Bindable(settings).showRequestIDs)
            if settings.showRequestIDs {
                requestIDs
            }
            GroupedRow.action(Text(verbatim: "Test connection"), systemImage: "network", busy: model.testingConnection) {
                Task { await model.testConnection() }
            }
        } footer: {
            FooterStack {
                switch model.connection {
                case .ok(let text):
                    InlineMessage(message: text, systemImage: "checkmark.circle", announces: false)
                case .failed(let text):
                    InlineMessage(message: text, systemImage: "exclamationmark.circle")
                case nil:
                    EmptyView()
                }
                GroupFooter(Text(verbatim: "Debug builds only."))
            }
        }
    }

    /// A text field under its label, in the card's row padding.
    private func field<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: label)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
            field()
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, GroupedListSpec.textPadding)
        .groupedRowHairline()
    }

    @ViewBuilder private var requestIDs: some View {
        VStack(alignment: .leading, spacing: 8) {
            if apiStatus.failures.isEmpty {
                Text(verbatim: "No failed requests since launch.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(apiStatus.failures) { f in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(f.status) \(f.method) \(redactedPath(f.path))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: "\(f.requestID ?? "–") · \(f.date.formatted(date: .omitted, time: .standard))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, GroupedListSpec.textPadding)
        .groupedRowHairline()
    }
}
#endif
