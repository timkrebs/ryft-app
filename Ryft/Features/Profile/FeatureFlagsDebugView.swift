#if DEBUG
import SwiftUI

/// Profile → Developer → Feature flags (Debug builds only): every flag, its value
/// and where that value comes from (compiled default, the platform, or a local
/// override), an override per flag, and a reload of `GET /v1/config`.
struct FeatureFlagsDebugView: View {
    @Environment(\.appEnvironment) private var env
    @Environment(ScreenModels.self) private var screens
    @State private var reloading = false
    @State private var reloadResult: String?

    private var store: FlagStore? { env.flags as? FlagStore }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                remote
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(FeatureFlag.allCases) { flag in
                            row(flag)
                            if flag != FeatureFlag.allCases.last { Divider().overlay(Theme.separator) }
                        }
                    }
                }
                if store?.overrides.isEmpty == false {
                    PrimaryButton(title: "Clear all overrides", style: .secondary) { store?.clearOverrides() }
                }
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Feature flags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var remote: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                StatRow(title: "Fetched", value: store?.fetchedAt?.formatted(.relative(presentation: .named))
                        ?? String(localized: "Never"))
                StatRow(title: "Evaluated", value: store?.evaluatedAt?.formatted(date: .abbreviated, time: .shortened)
                        ?? Fmt.placeholder)
                StatRow(title: "Refreshes every", value: Fmt.duration(minutes: Int((store?.ttl ?? FlagStore.defaultTTL) / 60)))
                PrimaryButton(title: "Reload from the platform", style: .secondary, busy: reloading) {
                    reloading = true
                    let applied = await screens.featureFlags?.refresh(force: true) ?? false
                    reloading = false
                    reloadResult = applied ? String(localized: "Updated.") : String(localized: "Couldn't load; keeping the cached flags.")
                }
                .disabled(screens.featureFlags == nil)
                if let reloadResult {
                    Text(reloadResult)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func row(_ flag: FeatureFlag) -> some View {
        let source = env.flags.source(of: flag)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { env.flags.isOn(flag) }, set: { store?.setOverride(flag, $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: flag.rawValue)
                        .font(.ryft(.body).monospaced())
                        .foregroundStyle(Theme.textPrimary)
                    Text(Self.sourceTitle(source))
                        .font(.ryft(.caption))
                        .foregroundStyle(source == .override ? Theme.warning : Theme.textTertiary)
                }
            }
            .tint(Theme.accent)
            .disabled(store == nil)
            if source == .override {
                Button("Use the platform's value") { store?.setOverride(flag, nil) }
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func sourceTitle(_ source: FlagSource) -> String {
        switch source {
        case .compiled: return String(localized: "Compiled default")
        case .remote: return String(localized: "From the platform")
        case .override: return String(localized: "Local override")
        }
    }
}

#Preview("Feature flags · dark") {
    NavigationStack { FeatureFlagsDebugView() }
        .previewEnvironment(.preview(flags: [.todayRedesign: true]))
}

#Preview("Feature flags · light") {
    NavigationStack { FeatureFlagsDebugView() }
        .previewEnvironment(.preview(flags: [.todayRedesign: true]), scheme: .light)
}
#endif
