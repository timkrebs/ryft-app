import SwiftUI

/// Empty state when there's no Health data: Health access may be off, or the
/// watch isn't writing to Apple Health. HealthKit never tells an app which. With a
/// tracker chosen (`devices.setup`) it names that tracker's app and the catalog's
/// route to RYFT's own permission.
struct HealthAccessHint: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.appEnvironment) private var env
    @Environment(\.locale) private var locale
    @Environment(ScreenModels.self) private var screens: ScreenModels?

    /// The first chosen tracker with an app of its own ("Garmin Connect").
    private var app: String? {
        guard env.flags.isOn(.devicesSetup), let devices = screens?.devices else { return nil }
        return devices.trackers.compactMap(env.trackerCatalog.tracker).first { $0.integration == .vendorApp }?.appTitle
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("No Health data yet", systemImage: "heart.text.square")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                if let app {
                    trackerText(app)
                } else {
                    Text("RYFT needs Apple Health access, and your watch app writing to Apple Health (Garmin Connect → More → Settings → Apple Health). Check RYFT's access in Health → your profile → Apps → RYFT.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Neutral (Nocturne, design.md §P5-1.2): an outline pill, no teal.
                PillButton(Text("Open Health"), style: .secondary) { HealthLinks.open(with: openURL) }
                    .accessibilityIdentifier("health.openHealth")
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Both places, as the sync check words it: the tracker's app writing, RYFT reading.
    @ViewBuilder private func trackerText(_ app: String) -> some View {
        Text(verbatim: String(localized: "RYFT needs \(app) writing to Apple Health, and Apple Health access. Profile → Devices & sync shows how to set up \(app)."))
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        let steps = env.trackerCatalog.healthAccess.value(in: locale)
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            NumberedStep(number: index + 1, verbatim: step, total: steps.count)
        }
    }
}

/// Saving workouts was refused (iOS asks only once) or the access was taken away since.
struct HealthWriteAccessHint: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Allow it in Health → Sharing → Apps → RYFT → Workouts.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Metrics.itemSpacing)
            // A link in ink, underlined (G2); the sentence before it keeps `warning`: a fault named with its words.
            Button { HealthLinks.open(with: openURL) } label: { Text("Open Health") }
                .ryftLink()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("health.writeAccessHint")
    }
}

// Dark only (NOCTURNE_STYLE §1).
#Preview("Health hint", traits: .sizeThatFitsLayout) {
    DarkPreview { HealthAccessHint() }
}

#Preview("Health write access hint", traits: .sizeThatFitsLayout) {
    DarkPreview { Card { HealthWriteAccessHint() } }
}
