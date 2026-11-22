import SwiftUI

/// The one appearance there is (Nocturne is dark-only, ADR 0016): the content on the screen colour, 390 pt wide.
struct DarkPreview<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .frame(width: 390)
            .background(Theme.background)
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    /// Injects the environment objects every screen expects, backed by mock
    /// data and a fake signed-in session (no Supabase, no network).
    @MainActor
    func previewEnvironment(_ state: AppState? = nil, auth: AuthService? = nil, online: Bool = true) -> some View {
        // One environment for the screen and its view models: same auth, same network state.
        let state = state ?? AppState.preview(online: online, auth: auth)
        let sync = SyncService(env: state.env)
        return environment(\.appEnvironment, state.env)
            .environment(ScreenModels(state: state, sync: sync,
                                      coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                   clock: state.env.clock),
                                      store: TrainPreview.store, library: TrainPreview.library))
            .environment(Settings.shared)
            .environment(state.env.auth)
            .environment(sync)
            .environment(state)
            .environment(TrainPreview.library)
            .environment(TrainPreview.sync)
            .environment(TrainPreview.coordinator)
            .environment(state.env.connectivityMonitor)
            .preferredColorScheme(.dark)
            .tint(Theme.textPrimary)
    }
}
